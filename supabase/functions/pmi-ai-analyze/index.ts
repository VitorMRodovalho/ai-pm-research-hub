/**
 * pmi-ai-analyze — AI analysis worker for PMI VEP candidates.
 *
 * Workflow:
 *   1. Receive { application_id }
 *   2. Validate consent (consent_ai_analysis_at NOT NULL AND consent_ai_analysis_revoked_at IS NULL)
 *   3. Build Gemini prompt from selection_applications text fields + candidate links
 *   4. Call gemini-2.5-flash:generateContent with responseSchema (structured JSON)
 *   5. Persist ai_analysis (jsonb) + ai_pm_focus_tags (text[])
 *
 * Auth: service-role only. Triggered by give_consent_via_token via net.http_post (fire-and-forget).
 *
 * Env: GEMINI_API_KEY required.
 *
 * Cost note: ~3-5k tokens per candidate. Gemini 2.5 Flash pricing trivial pra MVP scale.
 *
 * NOTE: Não faz CV PDF extraction nem LinkedIn post scraping (Phase C deferred V2).
 *       Análise é baseada em texto livre que VEP entrega + candidate-provided links.
 */
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";

const json = (d: unknown, s = 200) =>
  new Response(JSON.stringify(d), { status: s, headers: { "Content-Type": "application/json" } });

const ANALYSIS_SCHEMA = {
  type: "object",
  required: ["summary", "seniority_signal", "leadership_signal", "ai_pm_focus_areas", "fit_for_role", "raises_the_bar", "key_strengths", "areas_to_probe", "red_flags"],
  properties: {
    summary: { type: "string", description: "2-3 frases executivas em PT-BR sobre o candidato" },
    seniority_signal: { type: "string", enum: ["junior","mid","senior","principal","unknown"] },
    leadership_signal: { type: "string", enum: ["none","team-lead","manager","director","executive","unknown"] },
    ai_pm_focus_areas: {
      type: "array",
      items: { type: "string" },
      maxItems: 6,
      description: "Tags em snake-case sobre áreas AI/PM evidenciadas. Exemplos: agile_methodologies, risk_management, ai_governance, predictive_analytics, llm_integration, change_management"
    },
    fit_for_role: {
      type: "object",
      required: ["score", "rationale"],
      properties: {
        score: { type: "integer", minimum: 1, maximum: 5 },
        rationale: { type: "string" }
      }
    },
    raises_the_bar: {
      type: "object",
      required: ["verdict", "rationale"],
      description: "PM mindset (Vitor 2026-05-01): 'Does this candidate raise the bar of the team?' Critério-chave que orienta toda a seleção do início ao fim.",
      properties: {
        verdict: { type: "string", enum: ["yes", "no", "uncertain"], description: "yes=evidências apontam contribuições acima da média; no=aplicação genérica/sem evidência de produção/contribuição relevante; uncertain=ambíguo ou dados thin" },
        rationale: { type: "string", description: "Justificativa concisa em PT-BR ancorada em evidências do texto do candidato" }
      }
    },
    key_strengths: { type: "array", items: { type: "string" }, maxItems: 5 },
    areas_to_probe: { type: "array", items: { type: "string" }, maxItems: 5 },
    red_flags: { type: "array", items: { type: "string" }, maxItems: 5 },
    evidence_quotes: {
      type: "array",
      maxItems: 5,
      items: { type: "string", description: "Citação curta direta dos textos do candidato" }
    }
  }
};

const SYSTEM_PROMPT = `Você é um avaliador profissional de candidatos voluntários ao Núcleo IA & GP do PMI Brasil. Sua função é analisar perfis de candidatos com base nas informações que eles forneceram (cover letter, experiência prévia, formação acadêmica, etc) e gerar um sumário objetivo.

Diretrizes:
- Retorne APENAS JSON válido conforme o schema (sem markdown fences, sem texto fora)
- Idioma da análise: português brasileiro
- Seja objetivo e baseado em evidências do texto que o candidato escreveu
- NÃO faça avaliações sobre características pessoais (gênero, etnia, idade, religião) — apenas competências profissionais
- Se a informação não permite avaliar algum aspecto, use "unknown" no enum ou liste explicitamente em "areas_to_probe"
- Red flags = sinais factuais preocupantes (incoerências no texto, ausência total de experiência relevante para o role aplicado, expectativas desalinhadas com programa voluntário). Não use red flags pra preferências subjetivas
- Tags em ai_pm_focus_areas devem ser em snake_case e refletir áreas concretas evidenciadas (não inventadas)
- Para raises_the_bar use o critério PM (Vitor Maia Rodovalho, GP, 2026-05-01): "Se a pessoa não se esforçar para fazer uma aplicação decente, podemos esperar dela fazer pesquisa, publicar artigo, liderar webinar, liderar tribos, representar o núcleo? Mindset: does that person raise the bar?" — verdict "yes" pode vir por DOIS caminhos convergentes:
  (a) TRACK RECORD: evidências factuais de contribuições acima da média (rigor de pesquisa demonstrado, artigos publicados, leadership exercida com escopo, expertise técnica reconhecida com proof)
  (b) POTENCIAL CONVERGENTE: formação acadêmica sólida (mestrado/MBA + área PM/IA) + commitment evidente (voluntariado ativo, certificações em progresso, articulação clara de plano de contribuição) + fit_for_role >= 4 + ausência de red flags. Mesmo sem track record extensivo articulado no texto, candidato com convergência forte de sinais de potencial PODE raise the bar.
  Verdict "no" se aplicação genérica, sem produção/contribuição relevante evidenciada E sem sinal claro de potencial convergente, ou candidato busca primeira oportunidade sem preparação aparente. "uncertain" se dados são thin demais para julgar entre (a)/(b)/no.
  Esta avaliação é INDEPENDENTE de fit_for_role: alguém pode ter fit_for_role=4 e raises_the_bar="no" (cumpridor mas não eleva), ou fit_for_role=2 e raises_the_bar="yes" via potencial convergente (precisa mentoria mas sinal forte). Validation cycle3-2026 (n=14) mostrou que aplicação genérica/concisa NEM SEMPRE indica candidato fraco — comissão humana frequentemente aprova baseada em LinkedIn/contexto chapter/conhecimento prévio (data NÃO disponível ao AI). Calibração: se candidato exibe convergência forte de (formação_relevante + commitment + fit>=4) mesmo com aplicação concisa, considere yes via path (b)`;

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
  parts.push(`\nAnalise este candidato conforme o schema fornecido e retorne JSON válido apenas.`);
  return parts.join("\n");
}

async function callGeminiAnalyzeOnce(userPrompt: string): Promise<Response> {
  return await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${GEMINI_API_KEY}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
        contents: [{ parts: [{ text: userPrompt }] }],
        generationConfig: {
          temperature: 0.2,
          maxOutputTokens: 4096,
          responseMimeType: "application/json",
          responseSchema: ANALYSIS_SCHEMA,
        },
      }),
    },
  );
}

// Retry with exponential backoff for transient 429/503 errors (CBGPL burst protection).
async function callGeminiAnalyze(app: AppRow): Promise<Record<string, unknown>> {
  const userPrompt = buildUserPrompt(app);
  const delays = [1000, 4000, 9000];
  let lastErr = "";
  for (let attempt = 0; attempt < 4; attempt++) {
    if (attempt > 0) await new Promise(r => setTimeout(r, delays[attempt - 1]));
    const res = await callGeminiAnalyzeOnce(userPrompt);
    if (res.ok) {
      const result = await res.json();
      const text = result.candidates?.[0]?.content?.parts?.[0]?.text;
      if (!text) throw new Error(`Gemini no text: ${JSON.stringify(result).slice(0, 500)}`);
      return JSON.parse(text);
    }
    const status = res.status;
    const body = await res.text();
    lastErr = `${status} ${body.slice(0, 300)}`;
    // Retry on 429 (rate limit) or 503 (overloaded). Bail on 4xx (auth/format) other than 429.
    if (status !== 429 && status !== 503) break;
  }
  throw new Error(`Gemini analyze (after retries): ${lastErr}`);
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
  if (!GEMINI_API_KEY) return json({ error: "GEMINI_API_KEY not configured" }, 503);

  const body = await req.json().catch(() => ({}));
  const { application_id } = body ?? {};
  if (!application_id) return json({ error: "missing application_id" }, 400);

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const t0 = Date.now();

  // Optional triggered_by from caller (give_consent_via_token / request_application_enrichment / cron / admin)
  // Default derived from selection_applications.enrichment_count below.
  const triggeredByFromBody: string | undefined = body?.triggered_by;

  // p86 Wave 5b-1b: insert ai_analysis_runs row up-front, update on completion / fail.
  // Backward-compat: still maintain selection_applications.ai_analysis column (additive).
  let runId: string | null = null;

  try {
    const { data: app, error: appErr } = await sb
      .from("selection_applications")
      .select("id, applicant_name, role_applied, linkedin_url, credly_url, motivation_letter, non_pmi_experience, leadership_experience, academic_background, proposed_theme, reason_for_applying, certifications, areas_of_interest, availability_declared, consent_ai_analysis_at, consent_ai_analysis_revoked_at, enrichment_count")
      .eq("id", application_id)
      .single<AppRow & { enrichment_count: number }>();
    if (appErr || !app) return json({ error: "application_not_found", detail: appErr?.message }, 404);
    if (!app.consent_ai_analysis_at || app.consent_ai_analysis_revoked_at) {
      return json({ error: "consent_required", message: "Candidato não deu consent ou revogou. AI analysis não roda." }, 403);
    }

    // Compute run_index = MAX(run_index) + 1 for this application
    const { data: lastRun } = await sb
      .from("ai_analysis_runs")
      .select("run_index")
      .eq("application_id", application_id)
      .order("run_index", { ascending: false })
      .limit(1)
      .maybeSingle();
    const nextRunIndex = (lastRun?.run_index ?? 0) + 1;

    // Derive triggered_by: explicit body parameter, else infer from enrichment_count
    // (consent path → enrichment_count = 0 ; enrichment path → already incremented to >= 1)
    const triggeredBy = triggeredByFromBody && ["consent", "enrichment_request", "admin_retry", "cron_retry"].includes(triggeredByFromBody)
      ? triggeredByFromBody
      : (app.enrichment_count > 0 ? "enrichment_request" : "consent");

    // Insert run row (status='running')
    const { data: insertedRun, error: insertErr } = await sb
      .from("ai_analysis_runs")
      .insert({
        application_id,
        run_index: nextRunIndex,
        triggered_by: triggeredBy,
        status: "running",
        model_version: "gemini-2.5-flash",
      })
      .select("id")
      .single();
    if (insertErr) {
      console.warn("[pmi-ai-analyze] ai_analysis_runs INSERT failed:", insertErr.message);
    } else {
      runId = insertedRun?.id ?? null;
    }

    const analysis = await callGeminiAnalyze(app);
    const t1 = Date.now();

    const aiAnalysisPayload = {
      ...analysis,
      model: "gemini-2.5-flash",
      analyzed_at: new Date().toISOString(),
      input_token_estimate: null,
      output_token_estimate: null,
    };

    const focusTags = Array.isArray(analysis.ai_pm_focus_areas)
      ? (analysis.ai_pm_focus_areas as string[]).filter(t => typeof t === "string" && t.length > 0).slice(0, 6)
      : [];

    const { error: updErr } = await sb
      .from("selection_applications")
      .update({
        ai_analysis: aiAnalysisPayload,
        ai_pm_focus_tags: focusTags,
        updated_at: new Date().toISOString(),
      })
      .eq("id", application_id);
    if (updErr) {
      // Update run row to failed (best-effort)
      if (runId) {
        await sb.from("ai_analysis_runs").update({
          status: "failed",
          error_message: `db_update_failed: ${updErr.message}`,
          duration_ms: Date.now() - t0,
          completed_at: new Date().toISOString(),
        }).eq("id", runId);
      }
      return json({ error: "db_update_failed", detail: updErr.message }, 500);
    }

    // Update run row → completed
    if (runId) {
      const { error: runUpdErr } = await sb
        .from("ai_analysis_runs")
        .update({
          status: "completed",
          ai_analysis_snapshot: aiAnalysisPayload,
          duration_ms: Date.now() - t0,
          completed_at: new Date().toISOString(),
        })
        .eq("id", runId);
      if (runUpdErr) console.warn("[pmi-ai-analyze] ai_analysis_runs UPDATE failed:", runUpdErr.message);
    }

    return json({
      success: true,
      application_id,
      run_id: runId,
      run_index: nextRunIndex,
      triggered_by: triggeredBy,
      gemini_ms: t1 - t0,
      total_ms: Date.now() - t0,
      tags_count: focusTags.length,
    });
  } catch (e) {
    // Update run row → failed (best-effort)
    if (runId) {
      await sb.from("ai_analysis_runs").update({
        status: "failed",
        error_message: String(e).substring(0, 1000),
        duration_ms: Date.now() - t0,
        completed_at: new Date().toISOString(),
      }).eq("id", runId);
    }
    return json({ error: "analyze_failed", detail: String(e) }, 500);
  }
});
