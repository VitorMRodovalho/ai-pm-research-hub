/**
 * pmi-video-init-upload — Drive resumable upload session initiator.
 *
 * Token-authenticated (PMI candidate portal). Validates onboarding_token +
 * scope='video_screening', looks up application/cycle context, builds a
 * structured filename, asks Drive API for a resumable upload session, and
 * returns the Google upload URL for the browser to PUT chunks directly.
 *
 * Auth: Drive OAuth refresh-token flow via Vault key google_drive_oauth_credentials
 *       (ADR-0064 amended). Reused from drive-upload-to-folder pattern.
 *
 * Body (JSON):
 *   {
 *     token: string,           // PMI onboarding token
 *     pillar: string,          // background | communication | proactivity | teamwork | culture_alignment
 *     question_index: number,  // 1-10
 *     filename: string,        // original filename from browser (used only for ext fallback)
 *     size_bytes: number,
 *     mime_type: string        // must be video/*
 *   }
 *
 * Returns:
 *   {
 *     upload_url: string,      // Drive resumable session URL (browser PUTs chunks here)
 *     final_filename: string,  // structured filename Drive will save
 *     folder_id: string,
 *     max_size_bytes: number
 *   }
 */
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PMI_VIDEO_DRIVE_FOLDER_ID = Deno.env.get("PMI_VIDEO_DRIVE_FOLDER_ID") ?? "";
const VAULT_KEY = "google_drive_oauth_credentials";

const ALLOWED_ORIGIN = "https://nucleoia.vitormr.dev";
const cors = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
  "Access-Control-Max-Age": "86400",
  "Vary": "Origin",
};
const json = (d: unknown, s = 200) =>
  new Response(JSON.stringify(d), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

const PILLAR_KEYS = ["background", "communication", "proactivity", "teamwork", "culture_alignment"];
const VIDEO_MIME_RE = /^video\//;
const MAX_SIZE_BYTES = 500 * 1024 * 1024; // 500 MB

interface OAuthCreds { client_id: string; client_secret: string; refresh_token: string; }

async function getOAuthCreds(sb: ReturnType<typeof createClient>): Promise<{ available: boolean; creds?: OAuthCreds; error?: string }> {
  const { data, error } = await sb.rpc("_get_vault_secret", { p_name: VAULT_KEY });
  if (error) return { available: false, error: `Vault read error: ${error.message}` };
  if (!data || typeof data !== "string" || data.length === 0) return { available: false, error: `Vault key '${VAULT_KEY}' not seeded` };
  try {
    const parsed = JSON.parse(data) as OAuthCreds;
    if (!parsed.client_id || !parsed.client_secret || !parsed.refresh_token) {
      return { available: false, error: "OAuth creds JSON missing fields" };
    }
    return { available: true, creds: parsed };
  } catch {
    return { available: false, error: "Vault key is not valid JSON" };
  }
}

async function getAccessToken(creds: OAuthCreds): Promise<string> {
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: creds.client_id,
      client_secret: creds.client_secret,
      refresh_token: creds.refresh_token,
      grant_type: "refresh_token",
    }),
  });
  if (!res.ok) throw new Error(`Token refresh failed: ${res.status} ${await res.text()}`);
  return (await res.json()).access_token;
}

function slugify(s: string): string {
  return s
    .toLowerCase()
    .normalize("NFD").replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 60);
}

function buildFilename(opts: {
  cycle_code: string;
  vep_opp_id: string | null;
  applicant_short_id: string;
  applicant_name: string;
  role: string;
  pillar: string;
  question_index: number;
  mime: string;
}): string {
  const extFromMime = opts.mime.split("/")[1] ?? "mp4";
  const ext = extFromMime.replace(/[^a-z0-9]/g, "").slice(0, 6) || "mp4";
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  const ts =
    `${now.getUTCFullYear()}${pad(now.getUTCMonth() + 1)}${pad(now.getUTCDate())}-` +
    `${pad(now.getUTCHours())}${pad(now.getUTCMinutes())}`;
  const slug = slugify(opts.applicant_name) || "applicant";
  const opp = opts.vep_opp_id ? `opp${opts.vep_opp_id}` : "opp-unknown";
  return [
    opts.cycle_code,
    opp,
    `${opts.applicant_short_id}-${slug}`,
    opts.role,
    `p${opts.question_index}-${opts.pillar}`,
    ts,
  ].join("__") + `.${ext}`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  let body: any;
  try { body = await req.json(); }
  catch { return json({ error: "invalid JSON" }, 400); }

  const { token, pillar, question_index, filename, size_bytes, mime_type } = body ?? {};

  if (!token || !pillar || !filename || !mime_type) return json({ error: "missing required fields" }, 400);
  if (typeof size_bytes !== "number" || !Number.isFinite(size_bytes) || size_bytes <= 0) {
    return json({ error: "invalid size_bytes" }, 400);
  }
  if (size_bytes > MAX_SIZE_BYTES) return json({ error: `size_bytes > ${MAX_SIZE_BYTES}` }, 400);
  if (!PILLAR_KEYS.includes(pillar)) return json({ error: "invalid pillar" }, 400);
  if (!Number.isInteger(question_index) || question_index < 1 || question_index > 10) return json({ error: "invalid question_index" }, 400);
  if (!VIDEO_MIME_RE.test(mime_type)) return json({ error: "mime_type must start with video/" }, 400);

  if (!PMI_VIDEO_DRIVE_FOLDER_ID) {
    return json({
      error: "drive_folder_not_configured",
      detail: "Set PMI_VIDEO_DRIVE_FOLDER_ID env var (Drive folder ID where PMI screening videos go).",
    }, 503);
  }

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // Validate token
  const { data: tokenRow, error: tokErr } = await sb
    .from("onboarding_tokens")
    .select("source_type, source_id, scopes, expires_at")
    .eq("token", token)
    .maybeSingle();
  if (tokErr) return json({ error: "token_lookup_error", detail: tokErr.message }, 500);
  if (!tokenRow) return json({ error: "invalid_token" }, 401);
  if (new Date(tokenRow.expires_at as string) <= new Date()) return json({ error: "token_expired" }, 401);
  if (!Array.isArray(tokenRow.scopes) || !tokenRow.scopes.includes("video_screening")) {
    return json({ error: "missing_video_screening_scope" }, 403);
  }
  if (tokenRow.source_type !== "pmi_application") return json({ error: "wrong_source_type" }, 400);

  // Lookup application + cycle for filename
  const { data: app, error: appErr } = await sb
    .from("selection_applications")
    .select("applicant_name, vep_opportunity_id, role_applied, cycle_id")
    .eq("id", tokenRow.source_id as string)
    .maybeSingle();
  if (appErr || !app) return json({ error: "application_not_found", detail: appErr?.message }, 404);

  const { data: cycle, error: cycErr } = await sb
    .from("selection_cycles")
    .select("cycle_code")
    .eq("id", app.cycle_id as string)
    .maybeSingle();
  if (cycErr || !cycle) return json({ error: "cycle_not_found", detail: cycErr?.message }, 404);

  const finalFilename = buildFilename({
    cycle_code: (cycle.cycle_code as string) ?? "unknown-cycle",
    vep_opp_id: (app.vep_opportunity_id as string | null) ?? null,
    applicant_short_id: String(tokenRow.source_id).slice(0, 8),
    applicant_name: (app.applicant_name as string) ?? "applicant",
    role: (app.role_applied as string) ?? "candidate",
    pillar,
    question_index,
    mime: mime_type,
  });

  // Drive resumable session init
  const credsResult = await getOAuthCreds(sb);
  if (!credsResult.available) return json({ error: "drive_oauth_unavailable", detail: credsResult.error }, 503);
  const accessToken = await getAccessToken(credsResult.creds!);

  const resumableRes = await fetch(
    "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&supportsAllDrives=true",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json; charset=UTF-8",
        "X-Upload-Content-Type": mime_type,
        "X-Upload-Content-Length": String(size_bytes),
        // Hint Google to allow CORS on subsequent PUT chunks from browser
        "Origin": ALLOWED_ORIGIN,
      },
      body: JSON.stringify({
        name: finalFilename,
        parents: [PMI_VIDEO_DRIVE_FOLDER_ID],
        mimeType: mime_type,
      }),
    },
  );

  if (resumableRes.status !== 200) {
    const errBody = await resumableRes.text();
    return json({
      error: "drive_resumable_init_failed",
      status: resumableRes.status,
      detail: errBody,
    }, 502);
  }

  const upload_url = resumableRes.headers.get("Location");
  if (!upload_url) return json({ error: "drive_no_location_header" }, 502);

  return json({
    upload_url,
    final_filename: finalFilename,
    folder_id: PMI_VIDEO_DRIVE_FOLDER_ID,
    max_size_bytes: MAX_SIZE_BYTES,
  });
});
