/**
 * pmi-ai-briefing — Interview briefing generator (ARM-5 Onda 4 Fase 1, ADR-0074).
 *
 * Workflow:
 *   1. Receive { application_id } (POST, user JWT with view_pii OR service_role)
 *   2. Verify auth (members + can_by_member 'view_pii')
 *   3. INSERT row in ai_processing_log (purpose='briefing', status='running')
 *   4. Build prompt: applicant data + ai_analysis snapshot (Gemini) + ai_triage_* (if present)
 *   5. Call Anthropic Haiku 4.5 with structured output (output_config.format json_schema)
 *   6. Parse briefing { personalized_questions[3], interview_focus_areas[3-5], preparation_notes }
 *   7. UPDATE selection_applications.last_briefing_*
 *   8. UPDATE ai_processing_log (completed + tokens)
 *
 * Auth: user JWT with view_pii (committee + admin) OR service_role.
 * Env: ANTHROPIC_API_KEY required.
 *
 * LGPD note: prompt_hash + response_hash logged (SHA-256), NUNCA conteúdo.
 *
 * Onda 4 difference vs MCP tool: persists last_briefing_* (PM revisita sem re-call Haiku).
 * MCP tool was on-demand only; aqui persistimos para Tab Entrevista renderizar cache.
 *
 * Cost: Haiku 4.5 ~$0.80 input / $4 output per 1M tokens. ~5K input + 1K output =
 * $0.004 + $0.004 = ~$0.01/call. Per ciclo de 80 candidatos: ~$0.8 total.
 */

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (d: unknown, s = 200) =>
  new Response(JSON.stringify(d), {
    status: s,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });

const SYSTEM_PROMPT = `Você assiste entrevistadores do programa Núcleo IA & GP do PMI Brasil. Gere briefing de entrevista para o candidato:
- 3 perguntas personalizadas que probam pontos específicos do perfil (1 técnica, 1 sobre liderança/contribuição, 1 aberta sobre fit cultural)
- Áreas de atenção para o entrevistador focar (3-5 bullets curtos)
- Notas de preparação (3-4 frases sobre como abordar a conversa)

Critério: ajude o entrevistador a calibrar conforme o critério "raises the bar" — produção, leadership, expertise técnica, commitment. Não invente; ancorada em evidências do payload.

Retorne APENAS JSON válido conforme schema. Idioma: português brasileiro.`;

// NOTE: Anthropic structured outputs don't support `minItems`/`maxItems` on array types
// (returns 400 invalid_request_error). Counts (3 questions, 3-5 focus areas) are enforced
// in the system prompt + validated client-side after parsing (see validateBriefing below).
const BRIEFING_SCHEMA = {
  type: "object",
  required: ["personalized_questions", "interview_focus_areas", "preparation_notes"],
  additionalProperties: false,
  properties: {
    personalized_questions: {
      type: "array",
      items: {
        type: "object",
        required: ["question", "rationale"],
        additionalProperties: false,
        properties: {
          question: { type: "string" },
          rationale: { type: "string" },
        },
      },
    },
    interview_focus_areas: { type: "array", items: { type: "string" } },
    preparation_notes: { type: "string" },
  },
};

interface AppRow {
  id: string;
  applicant_name: string;
  role_applied: string;
  motivation_letter: string | null;
  leadership_experience: string | null;
  academic_background: string | null;
  proposed_theme: string | null;
  reason_for_applying: string | null;
  certifications: string | null;
  areas_of_interest: string | null;
  ai_analysis: Record<string, unknown> | null;
  ai_triage_score: number | null;
  ai_triage_reasoning: string | null;
  ai_triage_confidence: string | null;
  consent_ai_analysis_at: string | null;
  consent_ai_analysis_revoked_at: string | null;
}

function buildUserPrompt(app: AppRow): string {
  const parts: string[] = [
    `# Candidato: ${app.applicant_name}`,
    `# Função aplicada: ${app.role_applied}`,
  ];
  if (app.certifications) parts.push(`\n## Certificações\n${app.certifications}`);
  if (app.academic_background) parts.push(`\n## Formação\n${app.academic_background}`);
  if (app.motivation_letter) parts.push(`\n## Carta de motivação\n${app.motivation_letter}`);
  if (app.leadership_experience) parts.push(`\n## Liderança\n${app.leadership_experience}`);
  if (app.proposed_theme) parts.push(`\n## Tema proposto\n${app.proposed_theme}`);
  if (app.reason_for_applying) parts.push(`\n## Razão da aplicação\n${app.reason_for_applying}`);
  if (app.areas_of_interest) parts.push(`\n## Áreas de interesse\n${app.areas_of_interest}`);
  if (app.ai_analysis) {
    parts.push(`\n## Análise prévia (Gemini snapshot)\n${JSON.stringify(app.ai_analysis).slice(0, 1500)}`);
  }
  if (app.ai_triage_score !== null && app.ai_triage_score !== undefined) {
    parts.push(`\n## Triage Sonnet 4.6\nScore ${app.ai_triage_score}/10 (confidence: ${app.ai_triage_confidence ?? "n/a"}). Reasoning: ${app.ai_triage_reasoning ?? "-"}`);
  }
  parts.push(`\nGere briefing JSON conforme schema.`);
  return parts.join("\n");
}

async function sha256Hex(text: string): Promise<string> {
  const data = new TextEncoder().encode(text);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hashBuffer)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

interface AnthropicUsage {
  input_tokens?: number;
  output_tokens?: number;
}

interface AnthropicResponse {
  id: string;
  content: Array<{ type: string; text?: string }>;
  usage?: AnthropicUsage;
}

async function callHaikuOnce(userPrompt: string): Promise<Response> {
  return await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "claude-haiku-4-5",
      max_tokens: 1024,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: userPrompt }],
      output_config: { format: { type: "json_schema", schema: BRIEFING_SCHEMA } },
    }),
  });
}

async function callHaiku(userPrompt: string): Promise<AnthropicResponse> {
  const delays = [1000, 4000, 9000];
  let lastErr = "";
  for (let attempt = 0; attempt < 4; attempt++) {
    if (attempt > 0) await new Promise((r) => setTimeout(r, delays[attempt - 1]));
    const res = await callHaikuOnce(userPrompt);
    if (res.ok) return await res.json() as AnthropicResponse;
    const status = res.status;
    const body = await res.text();
    lastErr = `${status} ${body.slice(0, 300)}`;
    if (status !== 429 && status !== 529 && status !== 500) break;
  }
  throw new Error(`Anthropic Haiku (after retries): ${lastErr}`);
}

interface BriefingShape {
  personalized_questions: Array<{ question: string; rationale: string }>;
  interview_focus_areas: string[];
  preparation_notes: string;
}

function validateBriefing(b: unknown): asserts b is BriefingShape {
  const obj = b as Record<string, unknown>;
  if (!Array.isArray(obj.personalized_questions) || obj.personalized_questions.length !== 3) {
    throw new Error("invalid briefing: personalized_questions must be exactly 3");
  }
  if (!Array.isArray(obj.interview_focus_areas) || obj.interview_focus_areas.length < 3 || obj.interview_focus_areas.length > 5) {
    throw new Error("invalid briefing: interview_focus_areas must be 3-5");
  }
  if (typeof obj.preparation_notes !== "string" || obj.preparation_notes.length < 10) {
    throw new Error("invalid briefing: preparation_notes must be a non-trivial string");
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
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

  let callerMemberId: string | null = null;
  if (!isServiceRole) {
    if (!SUPABASE_ANON_KEY) return json({ error: "anon_key_missing" }, 503);
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: ah } },
    });
    const { data: userData } = await userClient.auth.getUser();
    if (!userData?.user) return json({ error: "unauthorized" }, 401);
    const sbSrv = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data: memberRow } = await sbSrv.from("members").select("id").eq("auth_id", userData.user.id).maybeSingle();
    if (!memberRow?.id) return json({ error: "member_not_found" }, 403);
    const { data: canRes } = await sbSrv.rpc("can_by_member", {
      p_member_id: memberRow.id,
      p_action: "view_pii",
    });
    if (canRes !== true) return json({ error: "forbidden", message: "view_pii required" }, 403);
    callerMemberId = memberRow.id;
  }

  if (!ANTHROPIC_API_KEY) return json({ error: "ANTHROPIC_API_KEY not configured" }, 503);

  const body = await req.json().catch(() => ({}));
  const { application_id } = body ?? {};
  if (!application_id) return json({ error: "missing application_id" }, 400);

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const t0 = Date.now();
  let logId: string | null = null;

  try {
    const { data: app, error: appErr } = await sb
      .from("selection_applications")
      .select(
        "id, applicant_name, role_applied, motivation_letter, leadership_experience, academic_background, proposed_theme, reason_for_applying, certifications, areas_of_interest, ai_analysis, ai_triage_score, ai_triage_reasoning, ai_triage_confidence, consent_ai_analysis_at, consent_ai_analysis_revoked_at",
      )
      .eq("id", application_id)
      .single<AppRow>();
    if (appErr || !app) {
      return json({ error: "application_not_found", detail: appErr?.message }, 404);
    }
    if (!app.consent_ai_analysis_at || app.consent_ai_analysis_revoked_at) {
      return json(
        { error: "consent_required", message: "Candidato não deu consent ou revogou. Briefing AI não roda." },
        403,
      );
    }

    const userPrompt = buildUserPrompt(app);
    const promptHash = await sha256Hex(SYSTEM_PROMPT + "\n---\n" + userPrompt);

    const { data: logRow, error: logErr } = await sb
      .from("ai_processing_log")
      .insert({
        application_id,
        model_provider: "anthropic",
        model_id: "claude-haiku-4-5",
        purpose: "briefing",
        triggered_by: "admin_request",
        caller_member_id: callerMemberId,
        prompt_hash: promptHash,
        status: "running",
      })
      .select("id")
      .single();
    if (logErr) {
      console.warn("[pmi-ai-briefing] ai_processing_log INSERT failed:", logErr.message);
    } else {
      logId = logRow?.id ?? null;
    }

    const response = await callHaiku(userPrompt);

    const textBlock = response.content.find((b) => b.type === "text");
    if (!textBlock?.text) {
      throw new Error(`no text block in Anthropic response: ${JSON.stringify(response).slice(0, 300)}`);
    }
    const briefing = JSON.parse(textBlock.text);
    validateBriefing(briefing);

    const responseHash = await sha256Hex(JSON.stringify(briefing));

    const { error: updErr } = await sb
      .from("selection_applications")
      .update({
        last_briefing_jsonb: briefing,
        last_briefing_at: new Date().toISOString(),
        last_briefing_model: "claude-haiku-4-5",
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
          cache_creation_tokens: 0,
          cache_read_tokens: 0,
          duration_ms: Date.now() - t0,
          status: "completed",
          completed_at: new Date().toISOString(),
        })
        .eq("id", logId);
      if (logUpdErr) console.warn("[pmi-ai-briefing] log UPDATE failed:", logUpdErr.message);
    }

    return json({
      success: true,
      application_id,
      log_id: logId,
      model: "claude-haiku-4-5",
      duration_ms: Date.now() - t0,
      briefing,
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
    return json({ error: "briefing_failed", detail: String(e) }, 500);
  }
});
