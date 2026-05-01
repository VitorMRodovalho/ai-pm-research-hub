/**
 * pmi-ai-analyze-research — research-mode AI analysis (Issue #119, Sprint 1)
 *
 * Flow:
 *   1. service_role POST {application_id}
 *   2. Calls anonymize_application_for_ai_training RPC → PII-strippped payload
 *   3. Builds Gemini prompt from anonymized fields
 *   4. Calls Gemini with same ANALYSIS_SCHEMA as pmi-ai-analyze
 *   5. Persists row in ai_analysis_runs com triggered_by='research_validation'
 *      (preserves selection_applications.ai_analysis live data — does NOT
 *      UPDATE selection_applications)
 *   6. Returns: success, run_id, fit_for_role.score, raises_the_bar.verdict,
 *      final_outcome (for concordance comparison)
 *
 * LGPD: Option B — anonymized training. AI nunca vê applicant_name, email,
 * linkedin, credly, phone, pmi_id, chapter. Apenas conteúdo de aplicação
 * (motivation_letter, leadership_experience, etc) + outcome label.
 */

import { createClient } from "jsr:@supabase/supabase-js@2.105.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY")!;

const json = (d: unknown, s = 200) =>
  new Response(JSON.stringify(d), { status: s, headers: { "Content-Type": "application/json" } });

const ANALYSIS_SCHEMA = {
  type: "object",
  required: ["summary", "seniority_signal", "leadership_signal", "ai_pm_focus_areas", "fit_for_role", "raises_the_bar", "key_strengths", "areas_to_probe", "red_flags"],
  properties: {
    summary: { type: "string" },
    seniority_signal: { type: "string", enum: ["junior","mid","senior","principal","unknown"] },
    leadership_signal: { type: "string", enum: ["none","team-lead","manager","director","executive","unknown"] },
    ai_pm_focus_areas: { type: "array", items: { type: "string" }, maxItems: 6 },
    fit_for_role: {
      type: "object", required: ["score", "rationale"],
      properties: { score: { type: "integer", minimum: 1, maximum: 5 }, rationale: { type: "string" } }
    },
    raises_the_bar: {
      type: "object", required: ["verdict", "rationale"],
      properties: {
        verdict: { type: "string", enum: ["yes", "no", "uncertain"] },
        rationale: { type: "string" }
      }
    },
    key_strengths: { type: "array", items: { type: "string" }, maxItems: 5 },
    areas_to_probe: { type: "array", items: { type: "string" }, maxItems: 5 },
    red_flags: { type: "array", items: { type: "string" }, maxItems: 5 },
    evidence_quotes: { type: "array", maxItems: 5, items: { type: "string" } }
  }
};

const SYSTEM_PROMPT = `Você é um avaliador profissional de candidatos voluntários ao Núcleo IA & GP do PMI Brasil. Esta é uma análise RESEARCH MODE — texto anonimizado para validação de rubric.

Diretrizes:
- Retorne APENAS JSON válido conforme o schema (sem markdown fences)
- Idioma: português brasileiro
- Seja objetivo e baseado em evidências do texto
- NÃO faça avaliações sobre características pessoais — apenas competências profissionais
- O candidato é referido apenas por pseudônimo (Candidato_XXXX). NÃO tente inferir identidade
- Se a informação não permite avaliar algum aspecto, use "unknown" ou "areas_to_probe"
- Para raises_the_bar use o critério PM (Vitor 2026-05-01): "Se a pessoa não se esforçar para fazer uma aplicação decente, podemos esperar dela fazer pesquisa, publicar artigo, liderar webinar, liderar tribos, representar o núcleo?" — Verdict "yes" pode vir por DOIS caminhos convergentes:
  (a) TRACK RECORD: evidências factuais de contribuições acima da média (rigor demonstrado, artigos publicados, leadership com escopo, expertise técnica reconhecida com proof)
  (b) POTENCIAL CONVERGENTE: formação acadêmica sólida (mestrado/MBA + área PM/IA) + commitment evidente (voluntariado ativo, certificações em progresso, articulação clara de contribuição) + fit_for_role >= 4 + sem red flags significativos
  Verdict "no" se aplicação genérica E sem sinal claro de potencial convergente. "uncertain" se dados thin. INDEPENDENTE de fit_for_role.
  Calibração Sprint 4: validation cycle3-2026 (n=14) mostrou que aplicação concisa NEM SEMPRE indica candidato fraco — comissão humana frequentemente aprova via LinkedIn/contexto chapter/conhecimento prévio (NÃO disponível ao AI). Se convergência forte de potential signals mesmo com texto conciso, considere yes via path (b)`;

interface AnonymizedAppPayload {
  application_id: string;
  pseudo_name: string;
  role_applied: string | null;
  motivation_letter: string | null;
  non_pmi_experience: string | null;
  leadership_experience: string | null;
  academic_background: string | null;
  proposed_theme: string | null;
  reason_for_applying: string | null;
  certifications: string | null;
  areas_of_interest: string | null;
  availability_declared: string | null;
  final_outcome: string;
  objective_score_avg: number | null;
  has_human_evals: number;
}

function buildUserPrompt(p: AnonymizedAppPayload): string {
  const parts: string[] = [];
  parts.push(`# Candidato: ${p.pseudo_name}`);
  parts.push(`# Função aplicada: ${p.role_applied ?? '(não declarada)'}`);
  if (p.certifications) parts.push(`\n## Certificações declaradas\n${p.certifications}`);
  if (p.academic_background) parts.push(`\n## Formação acadêmica\n${p.academic_background}`);
  if (p.motivation_letter) parts.push(`\n## Carta de motivação\n${p.motivation_letter}`);
  if (p.non_pmi_experience) parts.push(`\n## Experiência fora do PMI\n${p.non_pmi_experience}`);
  if (p.leadership_experience) parts.push(`\n## Experiência de liderança\n${p.leadership_experience}`);
  if (p.proposed_theme) parts.push(`\n## Tema proposto\n${p.proposed_theme}`);
  if (p.reason_for_applying) parts.push(`\n## Razão da aplicação\n${p.reason_for_applying}`);
  if (p.areas_of_interest) parts.push(`\n## Áreas de interesse\n${p.areas_of_interest}`);
  if (p.availability_declared) parts.push(`\n## Disponibilidade\n${p.availability_declared}`);
  parts.push(`\nAnalise este candidato anonimizado conforme o schema fornecido e retorne JSON válido apenas.`);
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

async function callGeminiAnalyze(payload: AnonymizedAppPayload): Promise<Record<string, unknown>> {
  const userPrompt = buildUserPrompt(payload);
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
  let runId: string | null = null;

  try {
    // Anonymize
    const { data: anonData, error: anonErr } = await sb.rpc("anonymize_application_for_ai_training", {
      p_application_id: application_id
    });
    if (anonErr) return json({ error: "anonymize_failed", detail: anonErr.message }, 500);
    if (!anonData) return json({ error: "anonymize_returned_null" }, 500);

    const anonPayload = anonData as AnonymizedAppPayload;

    // Insert run row up-front
    const { data: lastRun } = await sb
      .from("ai_analysis_runs")
      .select("run_index")
      .eq("application_id", application_id)
      .order("run_index", { ascending: false })
      .limit(1)
      .maybeSingle();
    const nextRunIndex = (lastRun?.run_index ?? 0) + 1;

    const { data: insertedRun, error: insertErr } = await sb
      .from("ai_analysis_runs")
      .insert({
        application_id,
        run_index: nextRunIndex,
        triggered_by: "research_validation",
        status: "running",
        model_version: "gemini-2.5-flash",
      })
      .select("id")
      .single();
    if (insertErr) {
      console.warn("[pmi-ai-analyze-research] ai_analysis_runs INSERT failed:", insertErr.message);
    } else {
      runId = insertedRun?.id ?? null;
    }

    // Gemini
    const analysis = await callGeminiAnalyze(anonPayload);
    const t1 = Date.now();

    const aiAnalysisPayload = {
      ...analysis,
      model: "gemini-2.5-flash",
      analyzed_at: new Date().toISOString(),
      input_token_estimate: null,
      output_token_estimate: null,
      research_metadata: {
        final_outcome: anonPayload.final_outcome,
        objective_score_avg: anonPayload.objective_score_avg,
        has_human_evals: anonPayload.has_human_evals,
      },
    };

    // Update run row → completed (DO NOT update selection_applications.ai_analysis)
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
      if (runUpdErr) console.warn("[pmi-ai-analyze-research] ai_analysis_runs UPDATE failed:", runUpdErr.message);
    }

    return json({
      success: true,
      application_id,
      run_id: runId,
      run_index: nextRunIndex,
      triggered_by: "research_validation",
      gemini_ms: t1 - t0,
      total_ms: Date.now() - t0,
      fit_for_role_score: (analysis as any)?.fit_for_role?.score,
      raises_the_bar_verdict: (analysis as any)?.raises_the_bar?.verdict,
      final_outcome: anonPayload.final_outcome,
    });
  } catch (e) {
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
