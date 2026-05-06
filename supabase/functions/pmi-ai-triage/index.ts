/**
 * pmi-ai-triage — AI triage scoring worker (ARM-3 Triage, ARM Onda 3, ADR-0074).
 *
 * Workflow:
 *   1. Receive { application_id, triggered_by? } (POST, service-role only)
 *   2. Validate consent (consent_ai_analysis_at NOT NULL AND consent_ai_analysis_revoked_at IS NULL)
 *   3. INSERT row in ai_processing_log (purpose='triage', status='running')
 *   4. Build prompt: cached system rubric (~5K tokens) + per-candidate user data
 *   5. Call Anthropic Sonnet 4.6 with structured output (output_config.format json_schema)
 *   6. Parse score 0-10 + reasoning + confidence
 *   7. UPDATE selection_applications.ai_triage_*
 *   8. UPDATE ai_processing_log (completed + tokens incl cache_read_tokens)
 *
 * Auth: service-role only.
 * Env: ANTHROPIC_API_KEY required (Supabase secret).
 *
 * LGPD note: prompt_hash + response_hash logged (SHA-256), NUNCA conteúdo.
 *
 * Score is NON-BINDING per ADR-0074 (LGPD Art. 20 §1). Decisão humana é autoritária.
 *
 * Cost: ~$0.01/call after cache warm-up (5K rubric × $3/1M = $0.015 write 1x;
 * $0.30/1M cache reads = ~$0.0015 per subsequent + $0.005-0.01 user prompt + $0.0075 output).
 * Per ciclo de 80 candidatos: ~$0.79 total amortizado.
 */

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";

const json = (d: unknown, s = 200) =>
  new Response(JSON.stringify(d), { status: s, headers: { "Content-Type": "application/json" } });

// Cached rubric — load-bearing for prompt cache (~5K tokens, identical across all calls in window)
const TRIAGE_RUBRIC = `# Rubrica de Triage — Núcleo IA & GP do PMI Brasil

Você é um avaliador de triage para o programa voluntário Núcleo IA & GP do PMI Brasil. Sua função é gerar um SCORE NUMÉRICO 0-10 sobre fit do candidato para o programa.

## Critério-chave (Vitor Maia Rodovalho, GP, 2026-05-01)

"Does this candidate raise the bar of the team?" Mindset: a pessoa demonstra capacidade ou potencial de fazer pesquisa, publicar artigo, liderar webinar, liderar tribos, representar o núcleo? Avaliar não é punir nem aprovar generosamente — é calibrar conforme evidência.

## Rubric de scoring (0-10, valores inteiros)

- **0-2**: Aplicação genérica, sem evidência de produção/contribuição. Texto curto/vago. Sem certificações relevantes. Sem clarity de motivação além de "quero aprender". Aplicação parece template ou esforço mínimo.
- **3-4**: Aplicação básica completa. Tem certificação PMI ou IA mas sem track record de contribuição. Texto mostra interesse mas sem plano concreto de contribuição. Cumpridor mas sem sinais de elevar a barra.
- **5-6**: Aplicação sólida. Track record moderado (alguma liderança ou voluntariado prévio). Certificações relevantes (PMP/PMI-ACP/CPMAI ou equivalente IA). Plano de contribuição articulado mas conventional. Confiável mas não excepcional.
- **7-8**: Aplicação forte. Track record de produção (artigos, palestras, comunidade ativa) OU formação acadêmica robusta + commitment claro. Plano de contribuição específico ao Núcleo (e.g. menciona tribo específica + área de pesquisa). Liderança exercida com escopo concreto.
- **9-10**: Aplicação excepcional. Track record extenso (publicações, leadership reconhecida, expertise técnica com proof externo) E commitment articulado E plano de contribuição ambicioso (e.g. propõe mentorar tribo, liderar projeto cross-tribe, representar Núcleo em evento externo). Pessoa eleva claramente a barra do time.

## Caminhos para score alto

(a) **TRACK RECORD**: evidências factuais de contribuições acima da média (rigor de pesquisa, artigos publicados, leadership exercida, expertise técnica com proof externo).
(b) **POTENCIAL CONVERGENTE**: formação acadêmica sólida (mestrado/MBA + área PM/IA) + commitment evidente (voluntariado ativo, certificações em progresso, articulação clara de plano de contribuição). Mesmo sem track record extensivo articulado no texto, candidato com convergência forte de sinais de potencial PODE pontuar 7+.

Validation cycle3-2026 (n=14) mostrou que aplicação genérica/concisa NEM SEMPRE indica candidato fraco — comissão humana frequentemente aprova baseada em LinkedIn/contexto chapter/conhecimento prévio (data NÃO disponível ao AI). Calibração: se candidato exibe convergência forte de (formação_relevante + commitment + experiência_relevante) mesmo com aplicação concisa, considere score 6-7 via path (b) e confidence=low (não high) para sinalizar que decisão humana é load-bearing.

## Confidence calibration

- **high**: dados thick (texto detalhado + LinkedIn + certificações + experiência prévia descrita). Avaliação confiante; recomendação de score é precisa.
- **medium**: dados moderados. Algumas inferências necessárias mas evidência aponta direção clara.
- **low**: dados thin. Texto curto, poucas evidências externas. Score com alta variância — requer revisão humana cuidadosa antes de decidir.

## Regras de output

- Retorne APENAS JSON válido conforme schema. Não use markdown fences nem texto fora.
- Idioma do reasoning: português brasileiro.
- Reasoning conciso (máx 500 caracteres), ancorado em evidências do texto. Não invente.
- Score é UM NÚMERO INTEIRO 0-10. Não fracionar.
- Confidence: high|medium|low — calibrar conforme volume e qualidade dos dados.
- Não avalie características pessoais (gênero, etnia, idade, religião) — apenas competências profissionais demonstradas.

## Importante (LGPD Art. 20 §1)

Este score é NON-BINDING. Decisão humana é autoritária — o score serve só como signal de pre-screen para priorização visual da equipe de avaliação. Comitê humano valida (ou rejeita) cada conclusão.`;

const TRIAGE_SCHEMA = {
  type: "object",
  required: ["score", "reasoning", "confidence"],
  additionalProperties: false,
  properties: {
    score: { type: "integer", minimum: 0, maximum: 10 },
    reasoning: { type: "string" },
    confidence: { type: "string", enum: ["high", "medium", "low"] },
  },
};

interface AppRow {
  id: string;
  applicant_name: string;
  role_applied: string;
  linkedin_url: string | null;
  credly_url: string | null;
  motivation_letter: string | null;
  non_pmi_experience: string | null;
  leadership_experience: string | null;
  academic_background: string | null;
  proposed_theme: string | null;
  reason_for_applying: string | null;
  certifications: string | null;
  areas_of_interest: string | null;
  availability_declared: string | null;
  consent_ai_analysis_at: string | null;
  consent_ai_analysis_revoked_at: string | null;
}

function buildUserPrompt(app: AppRow): string {
  const parts: string[] = [];
  parts.push(`# Candidato: ${app.applicant_name}`);
  parts.push(`# Função aplicada: ${app.role_applied}`);
  if (app.linkedin_url) parts.push(`LinkedIn: ${app.linkedin_url}`);
  if (app.credly_url) parts.push(`Credly: ${app.credly_url}`);
  if (app.certifications) parts.push(`\n## Certificações declaradas\n${app.certifications}`);
  if (app.academic_background) parts.push(`\n## Formação acadêmica\n${app.academic_background}`);
  if (app.motivation_letter) parts.push(`\n## Carta de motivação\n${app.motivation_letter}`);
  if (app.non_pmi_experience) parts.push(`\n## Experiência fora do PMI\n${app.non_pmi_experience}`);
  if (app.leadership_experience) parts.push(`\n## Experiência de liderança\n${app.leadership_experience}`);
  if (app.proposed_theme) parts.push(`\n## Tema proposto\n${app.proposed_theme}`);
  if (app.reason_for_applying) parts.push(`\n## Razão da aplicação\n${app.reason_for_applying}`);
  if (app.areas_of_interest) parts.push(`\n## Áreas de interesse\n${app.areas_of_interest}`);
  if (app.availability_declared) parts.push(`\n## Disponibilidade\n${app.availability_declared}`);
  parts.push(`\nAplique a rubrica e retorne JSON válido { score: 0-10, reasoning: <=500 chars PT-BR, confidence: high|medium|low }.`);
  return parts.join("\n");
}

async function sha256Hex(text: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(text);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

interface AnthropicUsage {
  input_tokens?: number;
  output_tokens?: number;
  cache_creation_input_tokens?: number;
  cache_read_input_tokens?: number;
}

interface AnthropicResponse {
  id: string;
  content: Array<{ type: string; text?: string }>;
  usage?: AnthropicUsage;
  stop_reason?: string;
}

async function callAnthropicOnce(userPrompt: string): Promise<Response> {
  return await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "claude-sonnet-4-6",
      max_tokens: 1024,
      system: [
        {
          type: "text",
          text: TRIAGE_RUBRIC,
          cache_control: { type: "ephemeral" },
        },
      ],
      messages: [{ role: "user", content: userPrompt }],
      output_config: {
        format: {
          type: "json_schema",
          schema: TRIAGE_SCHEMA,
        },
      },
    }),
  });
}

// Retry on 429/529 with exponential backoff (CBGPL burst protection — same pattern as Gemini path)
async function callAnthropicTriage(userPrompt: string): Promise<AnthropicResponse> {
  const delays = [1000, 4000, 9000];
  let lastErr = "";
  for (let attempt = 0; attempt < 4; attempt++) {
    if (attempt > 0) await new Promise((r) => setTimeout(r, delays[attempt - 1]));
    const res = await callAnthropicOnce(userPrompt);
    if (res.ok) {
      return await res.json() as AnthropicResponse;
    }
    const status = res.status;
    const body = await res.text();
    lastErr = `${status} ${body.slice(0, 300)}`;
    if (status !== 429 && status !== 529 && status !== 500) break;
  }
  throw new Error(`Anthropic triage (after retries): ${lastErr}`);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const ah = req.headers.get("Authorization") ?? "";
  const tk = ah.replace(/^Bearer\s+/i, "").trim();
  let isServiceRole = tk === SUPABASE_SERVICE_ROLE_KEY;
  if (!isServiceRole) {
    try {
      const parts = tk.split(".");
      if (parts.length === 3) {
        const payload = JSON.parse(atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")));
        if (payload.role === "service_role") isServiceRole = true;
      }
    } catch { /* not JWT */ }
  }
  if (!isServiceRole) return json({ error: "service_role only" }, 401);
  if (!ANTHROPIC_API_KEY) return json({ error: "ANTHROPIC_API_KEY not configured" }, 503);

  const body = await req.json().catch(() => ({}));
  const { application_id, triggered_by } = body ?? {};
  if (!application_id) return json({ error: "missing application_id" }, 400);

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const t0 = Date.now();
  let logId: string | null = null;
  const triggeredBy = typeof triggered_by === "string" && triggered_by.length > 0
    ? triggered_by
    : "admin_request";

  try {
    const { data: app, error: appErr } = await sb
      .from("selection_applications")
      .select(
        "id, applicant_name, role_applied, linkedin_url, credly_url, motivation_letter, non_pmi_experience, leadership_experience, academic_background, proposed_theme, reason_for_applying, certifications, areas_of_interest, availability_declared, consent_ai_analysis_at, consent_ai_analysis_revoked_at",
      )
      .eq("id", application_id)
      .single<AppRow>();
    if (appErr || !app) {
      return json({ error: "application_not_found", detail: appErr?.message }, 404);
    }
    if (!app.consent_ai_analysis_at || app.consent_ai_analysis_revoked_at) {
      return json(
        { error: "consent_required", message: "Candidato não deu consent ou revogou. AI triage não roda." },
        403,
      );
    }

    const userPrompt = buildUserPrompt(app);
    const promptCombined = TRIAGE_RUBRIC + "\n---USER---\n" + userPrompt;
    const promptHash = await sha256Hex(promptCombined);

    const { data: logRow, error: logErr } = await sb
      .from("ai_processing_log")
      .insert({
        application_id,
        model_provider: "anthropic",
        model_id: "claude-sonnet-4-6",
        purpose: "triage",
        triggered_by: triggeredBy,
        prompt_hash: promptHash,
        status: "running",
      })
      .select("id")
      .single();
    if (logErr) {
      console.warn("[pmi-ai-triage] ai_processing_log INSERT failed:", logErr.message);
    } else {
      logId = logRow?.id ?? null;
    }

    const response = await callAnthropicTriage(userPrompt);
    const t1 = Date.now();

    const textBlock = response.content.find((b) => b.type === "text");
    if (!textBlock || !textBlock.text) {
      throw new Error(`no text block in Anthropic response: ${JSON.stringify(response).slice(0, 300)}`);
    }

    const parsed = JSON.parse(textBlock.text);
    if (typeof parsed.score !== "number" || parsed.score < 0 || parsed.score > 10) {
      throw new Error(`invalid score: ${JSON.stringify(parsed.score)}`);
    }
    if (!["high", "medium", "low"].includes(parsed.confidence)) {
      throw new Error(`invalid confidence: ${JSON.stringify(parsed.confidence)}`);
    }
    const reasoning = String(parsed.reasoning ?? "").slice(0, 500);

    const responseHash = await sha256Hex(JSON.stringify(parsed));

    const { error: updErr } = await sb
      .from("selection_applications")
      .update({
        ai_triage_score: parsed.score,
        ai_triage_reasoning: reasoning,
        ai_triage_confidence: parsed.confidence,
        ai_triage_at: new Date().toISOString(),
        ai_triage_model: "claude-sonnet-4-6",
        updated_at: new Date().toISOString(),
      })
      .eq("id", application_id);
    if (updErr) throw new Error(`db_update_failed: ${updErr.message}`);

    if (logId) {
      const usage = response.usage ?? {};
      const { error: logUpdErr } = await sb
        .from("ai_processing_log")
        .update({
          response_hash: responseHash,
          input_tokens: usage.input_tokens ?? null,
          output_tokens: usage.output_tokens ?? null,
          cache_creation_tokens: usage.cache_creation_input_tokens ?? 0,
          cache_read_tokens: usage.cache_read_input_tokens ?? 0,
          duration_ms: Date.now() - t0,
          status: "completed",
          completed_at: new Date().toISOString(),
        })
        .eq("id", logId);
      if (logUpdErr) console.warn("[pmi-ai-triage] log UPDATE failed:", logUpdErr.message);
    }

    return json({
      success: true,
      application_id,
      log_id: logId,
      triggered_by: triggeredBy,
      anthropic_ms: t1 - t0,
      total_ms: Date.now() - t0,
      score: parsed.score,
      confidence: parsed.confidence,
      cache_hit: (response.usage?.cache_read_input_tokens ?? 0) > 0,
      cache_read_tokens: response.usage?.cache_read_input_tokens ?? 0,
      cache_creation_tokens: response.usage?.cache_creation_input_tokens ?? 0,
    });
  } catch (e) {
    if (logId) {
      await sb.from("ai_processing_log").update({
        error_message: String(e).substring(0, 1000),
        duration_ms: Date.now() - t0,
        status: "failed",
        completed_at: new Date().toISOString(),
      }).eq("id", logId);
    }
    return json({ error: "triage_failed", detail: String(e) }, 500);
  }
});
