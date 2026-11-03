// supabase/functions/analyze-application-video/index.ts
//
// Video transcription pipeline. For each uploaded pmi_video_screening row of an application,
// transcribes the audio with OpenAI Whisper and stores the text on the row.
//
// Scope: transcription only. This function does not call a text-model API, does not download
// the Drive thumbnail, does not send the applicant name to any model, and does not write
// selection_evaluation_ai_suggestions. Guarded by
// tests/contracts/analyze-application-video-transcription-only.test.mjs.
//
// Flow per video row:
//   1. Resolve the Google Drive file_id from pmi_video_screenings.drive_file_id
//   2. Skip when a transcription is already stored
//   3. Download the video (<= 25 MB, the Whisper limit) and transcribe via Whisper
//   4. Persist the transcription on pmi_video_screenings
//
// Auth: service_role only (called by the public analyze_application_video RPC via pg_net).
// LGPD: consent gates (re-verified here in case state changed since dispatch).
//
// Graceful degradation:
// - OPENAI_API_KEY missing -> skip the row (nothing to transcribe)
// - Video above the Whisper size limit -> row logged as failed

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { isServiceRoleToken } from "../_shared/service-auth.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const WHISPER_MAX_BYTES = 25 * 1024 * 1024; // 25 MB OpenAI limit
const WHISPER_MODEL = "whisper-1";

interface VideoRow {
  id: string;
  application_id: string;
  pillar: string;
  question_index: number;
  question_text: string;
  status: string;
  drive_file_id: string | null;
  youtube_url: string | null;
  transcription: string | null;
  file_size_bytes: number | null;
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

// p197d D1: use OAuth user-delegated refresh_token flow (same pattern as
// pmi-video-test-transcribe, drive-upload-to-folder, etc). Service account JWT was
// initial attempt but the SA email doesn't have access to candidate-uploaded folders;
// OAuth user-delegated does, since the upload itself happened with these credentials.
async function getDriveAccessToken(sb: SupabaseClient<any, "public", any>): Promise<string> {
  const credsStr = await getVaultSecret(sb, "google_drive_oauth_credentials");
  if (!credsStr) throw new Error("google_drive_oauth_credentials not in vault");
  const creds = JSON.parse(credsStr) as { client_id: string; client_secret: string; refresh_token: string };
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
  if (!res.ok) throw new Error(`drive_oauth_refresh_failed_${res.status}_${(await res.text()).slice(0, 150)}`);
  const { access_token } = await res.json();
  return access_token;
}

async function driveDownloadVideo(fileId: string, accessToken: string): Promise<{ bytes: Uint8Array; size: number; mime: string }> {
  const metaRes = await fetch(`https://www.googleapis.com/drive/v3/files/${fileId}?fields=size,mimeType,name&supportsAllDrives=true`, {
    headers: { authorization: `Bearer ${accessToken}` },
  });
  if (!metaRes.ok) throw new Error(`drive_meta_failed_${metaRes.status}_${(await metaRes.text()).slice(0, 100)}`);
  const meta = await metaRes.json();
  const size = parseInt(meta.size ?? "0", 10);
  const mime = meta.mimeType ?? "video/mp4";

  if (size > WHISPER_MAX_BYTES) {
    throw new Error(`video_too_large_${size}_bytes_max_${WHISPER_MAX_BYTES}`);
  }

  const dlRes = await fetch(`https://www.googleapis.com/drive/v3/files/${fileId}?alt=media&supportsAllDrives=true`, {
    headers: { authorization: `Bearer ${accessToken}` },
  });
  if (!dlRes.ok) throw new Error(`drive_download_failed_${dlRes.status}`);
  const bytes = new Uint8Array(await dlRes.arrayBuffer());
  return { bytes, size, mime };
}

async function whisperTranscribe(videoBytes: Uint8Array, mime: string, openaiKey: string): Promise<string> {
  const form = new FormData();
  form.append("file", new Blob([videoBytes as BlobPart], { type: mime }), `video.${mime.split("/")[1] ?? "mp4"}`);
  form.append("model", WHISPER_MODEL);
  form.append("language", "pt"); // PT-BR primary; Whisper auto-detects but seeding helps
  form.append("response_format", "text");

  const res = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: { authorization: `Bearer ${openaiKey}` },
    body: form,
  });
  if (!res.ok) {
    const errBody = await res.text();
    throw new Error(`whisper_failed_${res.status}_${errBody.slice(0, 200)}`);
  }
  return (await res.text()).trim();
}

async function getVaultSecret(sb: SupabaseClient<any, "public", any>, name: string): Promise<string | null> {
  const { data, error } = await sb.rpc("_get_vault_secret", { p_name: name });
  if (error) {
    console.warn(`vault_secret_${name}_failed:`, error.message);
    return null;
  }
  return (data as string) || null;
}

// processVideos is the slow part — extracted into a separate async
// function so the request handler can return 200 immediately (pg_net default timeout = 5s,
// but Whisper+Drive download is 10-30s per pillar). EdgeRuntime.waitUntil keeps the
// runtime alive until the work finishes (Deno Edge Functions supports it).
async function processVideosBackground(
  sb: SupabaseClient<any, "public", any>,
  application_id: string,
  pillar: string | null,
  triggeredBy: string,
) {
  try {
    const { data: app, error: appErr } = await sb
      .from("selection_applications")
      .select("id, cycle_id, consent_ai_analysis_at, consent_ai_analysis_revoked_at, consent_voice_biometric_at, consent_voice_biometric_revoked_at")
      .eq("id", application_id).single();
    if (appErr || !app) { console.error("app_not_found:", appErr?.message); return; }
    if (!app.consent_ai_analysis_at || app.consent_ai_analysis_revoked_at) {
      console.log("consent_pending_or_revoked, skipping:", application_id); return;
    }
    if (!app.consent_voice_biometric_at || app.consent_voice_biometric_revoked_at) {
      console.log("voice_biometric_consent_pending_or_revoked, skipping:", application_id); return;
    }

    const videoQuery = sb.from("pmi_video_screenings")
      .select("id, application_id, pillar, question_index, question_text, status, drive_file_id, youtube_url, transcription, file_size_bytes")
      .eq("application_id", application_id).eq("status", "uploaded");
    const { data: videoRows, error: vErr } = pillar
      ? await videoQuery.eq("pillar", pillar) : await videoQuery;
    if (vErr) { console.error("video_query_failed:", vErr.message); return; }
    if (!videoRows || videoRows.length === 0) { console.log("no_uploaded_videos:", application_id); return; }

    const openaiKey = await getVaultSecret(sb, "openai_api_key");
    let driveToken: string | null = null;
    try { driveToken = await getDriveAccessToken(sb); }
    catch (e) { console.error("drive_oauth_failed:", (e as Error).message); }

    for (const v of videoRows as VideoRow[]) {
      const t0 = Date.now();
      let logId: string | null = null;
      let stage = "init";
      try {
        const { data: logRow } = await sb.from("ai_processing_log").insert({
          application_id, model_provider: "openai", model_id: WHISPER_MODEL,
          purpose: "video_screening", triggered_by: triggeredBy, status: "running",
        }).select("id").single();
        logId = logRow?.id ?? null;

        if (!v.drive_file_id) { console.log("no_drive_file_id:", v.id); continue; }
        if (!driveToken) { console.log("drive_oauth_unavailable for", v.id); continue; }

        let transcription = v.transcription ?? "";
        let transcribedNow = false;
        if (!transcription && openaiKey) {
          stage = "drive_download";
          const { bytes, mime } = await driveDownloadVideo(v.drive_file_id, driveToken);
          stage = "whisper";
          transcription = await whisperTranscribe(bytes, mime, openaiKey);
          transcribedNow = true;
          await sb.from("pmi_video_screenings").update({
            transcription, transcription_provider: "openai",
            transcription_model_version: WHISPER_MODEL,
            transcription_at: new Date().toISOString(),
          }).eq("id", v.id);
        } else if (!transcription && !openaiKey) {
          console.log("openai_key_missing for", v.id); continue;
        }

        if (logId) {
          await sb.from("ai_processing_log").update({
            status: "completed", duration_ms: Date.now() - t0,
            completed_at: new Date().toISOString(),
          }).eq("id", logId);
        }
        console.log(`ok pillar=${v.pillar} transcribed_now=${transcribedNow}`);
      } catch (e) {
        const errMsg = (e as Error).message;
        if (logId) {
          await sb.from("ai_processing_log").update({
            status: "failed", duration_ms: Date.now() - t0,
            error_message: `${stage}: ${errMsg}`,
            completed_at: new Date().toISOString(),
          }).eq("id", logId);
        }
        console.error(`pillar=${v.pillar} stage=${stage} error=${errMsg}`);
      }
    }
  } catch (e) {
    console.error("processVideosBackground fatal:", (e as Error).message);
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: {
      "access-control-allow-origin": "*",
      "access-control-allow-methods": "POST, OPTIONS",
      "access-control-allow-headers": "authorization, content-type",
    }});
  }
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  // Service-role gate (#738): exact env-key match, else PostgREST verifies the JWT
  // signature via current_caller_role() (accepts the vault service_role_key pg_net
  // sends, rejects forgeries). Previously decoded an UNVERIFIED payload.role. See
  // _shared/service-auth.ts.
  const authHeader = req.headers.get("authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!(await isServiceRoleToken(SUPABASE_URL, token))) {
    return json({ error: "unauthorized_service_role_only" }, 401);
  }

  const body = await req.json().catch(() => ({}));
  const { application_id, pillar, triggered_by } = body ?? {};
  if (!application_id) return json({ error: "missing_application_id" }, 400);

  const sb = createClient<any, "public", any>(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const triggeredBy = typeof triggered_by === "string" ? triggered_by : "service_role";

  // Return 200 immediately so pg_net doesn't time out (default 5s). Slow work runs in background.
  // @ts-ignore EdgeRuntime is provided by Supabase Edge Functions runtime
  if (typeof EdgeRuntime !== "undefined" && EdgeRuntime.waitUntil) {
    // @ts-ignore -- EdgeRuntime is a Supabase runtime global absent from Deno lib types
    EdgeRuntime.waitUntil(processVideosBackground(sb, application_id, pillar ?? null, triggeredBy));
  } else {
    // Local dev fallback: fire-and-forget without waitUntil (Deno still completes pending promises)
    processVideosBackground(sb, application_id, pillar ?? null, triggeredBy);
  }
  return json({ accepted: true, application_id, pillar: pillar ?? "all", async: true }, 202);
});

