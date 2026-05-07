/**
 * extract-cv-text — CV text extraction worker (ARM-11, ADR-0075).
 *
 * Workflow:
 *   1. Receive { application_id, triggered_by? } (POST)
 *   2. Auth: service-role only (called by cron RPC, pmi-ai-triage lazy fallback, or admin)
 *   3. Load application (consent + resume_url + cv_extracted_text)
 *   4. Early returns: consent_missing | no_resume_url | already_extracted
 *   5. Fetch resume_url (User-Agent realista, 30s timeout)
 *   6. Detect content-type → unpdf for PDF, response.text() for text/plain
 *   7. Normalize + truncate at 50K chars (defense-in-depth; pmi-ai-triage truncates to 12K for prompt)
 *   8. UPDATE selection_applications.cv_extracted_text
 *   9. INSERT ai_processing_log (purpose=enrichment, hashes only; NEVER content per LGPD Art. 37)
 *  10. Return 200 with stats
 *
 * Idempotente: re-run em app já extraído retorna 200 com noop_reason=already_extracted.
 *
 * LGPD: prompt_hash = sha256(resume_url) | response_hash = sha256(extracted_text). Conteúdo NÃO logado.
 *       cv_extracted_text gravada em coluna já protegida por purge trigger
 *       (_trg_purge_ai_analysis_on_consent_revocation) + retenção via cycle_decision_date.
 */

import { createClient } from "jsr:@supabase/supabase-js@2";
import { extractText, getDocumentProxy } from "npm:unpdf@1.6.2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

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

// Cap stored text to defense-in-depth limit. pmi-ai-triage prompt truncates further to 12K.
const STORED_TEXT_MAX_CHARS = 50_000;
const FETCH_TIMEOUT_MS = 30_000;
// Realistic User-Agent (mirrors p116 backfill script that successfully fetched 16/16 PDFs)
const USER_AGENT =
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36";

interface AppRow {
  id: string;
  resume_url: string | null;
  cv_extracted_text: string | null;
  consent_ai_analysis_at: string | null;
  consent_ai_analysis_revoked_at: string | null;
}

async function sha256Hex(text: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(text);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function normalizeText(raw: string): string {
  // NFC normalization + trim + collapse runs of whitespace
  return raw.normalize("NFC").trim().replace(/[\t ]+\n/g, "\n").replace(/\n{3,}/g, "\n\n");
}

async function fetchResume(url: string): Promise<{ bytes: Uint8Array; contentType: string }> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      method: "GET",
      headers: { "User-Agent": USER_AGENT, Accept: "*/*" },
      signal: controller.signal,
    });
    if (!res.ok) {
      throw new Error(`fetch_failed_status_${res.status}`);
    }
    const contentType = (res.headers.get("content-type") ?? "").toLowerCase();
    const bytes = new Uint8Array(await res.arrayBuffer());
    return { bytes, contentType };
  } finally {
    clearTimeout(timer);
  }
}

async function extractFromBytes(bytes: Uint8Array, contentType: string): Promise<{
  text: string;
  source_format: "pdf" | "text" | "unknown";
}> {
  // PDF: %PDF magic header is the most reliable signal (Azure Blob often serves
  // octet-stream regardless of true content-type)
  const isPdfMagic = bytes.length >= 4 &&
    bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 && bytes[3] === 0x46;
  const isPdfCT = contentType.includes("application/pdf");
  if (isPdfMagic || isPdfCT) {
    const pdf = await getDocumentProxy(bytes);
    const result = await extractText(pdf, { mergePages: true });
    const text = typeof result.text === "string" ? result.text : (result.text as string[]).join("\n\n");
    return { text, source_format: "pdf" };
  }
  if (contentType.includes("text/")) {
    const text = new TextDecoder("utf-8", { fatal: false }).decode(bytes);
    return { text, source_format: "text" };
  }
  // Fallback: try to decode as text; if non-printable ratio is too high, give up
  const decoded = new TextDecoder("utf-8", { fatal: false }).decode(bytes);
  const printable = decoded.replace(/[^\x20-\x7E -￿\n\r\t]/g, "");
  if (printable.length / Math.max(decoded.length, 1) > 0.85) {
    return { text: decoded, source_format: "unknown" };
  }
  throw new Error(`unsupported_content_type_${contentType || "binary"}`);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const ah = req.headers.get("Authorization") ?? "";
  const tk = ah.replace(/^Bearer\s+/i, "").trim();
  // Accept either exact env key match OR a JWT whose payload.role === 'service_role'.
  // Vault-stored service_role_key may differ from injected SUPABASE_SERVICE_ROLE_KEY
  // env var (e.g., post-rotation skew); JWT decode is the canonical check.
  // Pattern mirrors pmi-ai-triage auth gate.
  let isServiceRole = tk === SUPABASE_SERVICE_ROLE_KEY;
  if (!isServiceRole && tk.length > 0) {
    try {
      const parts = tk.split(".");
      if (parts.length === 3) {
        const payload = JSON.parse(atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")));
        if (payload.role === "service_role") isServiceRole = true;
      }
    } catch { /* not a JWT */ }
  }
  if (!isServiceRole) {
    return json({ error: "unauthorized", message: "service-role only" }, 401);
  }

  const body = await req.json().catch(() => ({}));
  const { application_id, triggered_by } = body ?? {};
  if (!application_id) return json({ error: "missing_application_id" }, 400);

  const triggeredBy = typeof triggered_by === "string" && triggered_by.length > 0
    ? triggered_by
    : "service_role_call";

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const t0 = Date.now();
  let logId: string | null = null;

  // 1. Load application
  const { data: app, error: appErr } = await sb
    .from("selection_applications")
    .select("id, resume_url, cv_extracted_text, consent_ai_analysis_at, consent_ai_analysis_revoked_at")
    .eq("id", application_id)
    .single<AppRow>();
  if (appErr || !app) {
    return json({ error: "application_not_found", detail: appErr?.message }, 404);
  }

  // 2. Early returns (noop cases)
  if (!app.consent_ai_analysis_at || app.consent_ai_analysis_revoked_at) {
    return json({ application_id, noop_reason: "consent_missing" }, 200);
  }
  if (!app.resume_url) {
    return json({ application_id, noop_reason: "no_resume_url" }, 200);
  }
  if (app.cv_extracted_text && app.cv_extracted_text.trim().length > 0) {
    return json({
      application_id,
      noop_reason: "already_extracted",
      existing_chars: app.cv_extracted_text.length,
    }, 200);
  }

  // 3. Insert log row (status=running)
  const promptHash = await sha256Hex(app.resume_url);
  const { data: logRow, error: logErr } = await sb
    .from("ai_processing_log")
    .insert({
      application_id,
      model_provider: "other",
      model_id: "unpdf@1.6.2",
      purpose: "enrichment",
      triggered_by: triggeredBy,
      prompt_hash: promptHash,
      status: "running",
    })
    .select("id")
    .single();
  if (!logErr) logId = logRow?.id ?? null;

  try {
    // 4. Fetch resume
    const { bytes, contentType } = await fetchResume(app.resume_url);

    // 5. Extract
    const { text, source_format } = await extractFromBytes(bytes, contentType);
    const normalized = normalizeText(text);
    const truncated = normalized.length > STORED_TEXT_MAX_CHARS;
    const finalText = truncated ? normalized.slice(0, STORED_TEXT_MAX_CHARS) : normalized;

    if (finalText.length === 0) {
      throw new Error("parse_failed_empty_output");
    }

    // 6. Persist
    const { error: updErr } = await sb
      .from("selection_applications")
      .update({
        cv_extracted_text: finalText,
        updated_at: new Date().toISOString(),
      })
      .eq("id", application_id);
    if (updErr) throw new Error(`db_update_failed: ${updErr.message}`);

    const responseHash = await sha256Hex(finalText);
    const duration = Date.now() - t0;

    // 7. Log completion
    if (logId) {
      await sb
        .from("ai_processing_log")
        .update({
          status: "completed",
          response_hash: responseHash,
          output_tokens: finalText.length, // semantic stretch: store length as output measure
          duration_ms: duration,
          completed_at: new Date().toISOString(),
        })
        .eq("id", logId);
    }

    return json({
      application_id,
      extracted_chars: finalText.length,
      truncated,
      source_format,
      duration_ms: duration,
    }, 200);
  } catch (e) {
    const duration = Date.now() - t0;
    const errMsg = e instanceof Error ? e.message : String(e);
    if (logId) {
      await sb
        .from("ai_processing_log")
        .update({
          status: "failed",
          error_message: errMsg.slice(0, 500),
          duration_ms: duration,
          completed_at: new Date().toISOString(),
        })
        .eq("id", logId);
    }
    // Map known error tags to HTTP codes
    let status = 500;
    if (errMsg.startsWith("fetch_failed_status_")) status = 502;
    else if (errMsg.startsWith("unsupported_content_type_")) status = 422;
    else if (errMsg.startsWith("parse_failed")) status = 422;
    return json({
      application_id,
      error: errMsg,
      duration_ms: duration,
    }, status);
  }
});
