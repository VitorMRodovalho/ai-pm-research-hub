/**
 * pmi-video-finalize-upload — register video screening after Drive upload completes.
 *
 * Token-authenticated. Browser, after completing Drive resumable upload directly
 * to Drive, calls this EF with the drive_file_id returned by Drive. EF calls the
 * register_video_screening RPC (token-auth gated) which inserts/updates the row.
 *
 * Body (JSON):
 *   {
 *     token: string,
 *     pillar: string,
 *     question_index: number,
 *     question_text?: string,
 *     drive_file_id: string,
 *     drive_file_name?: string,
 *     drive_folder_id?: string
 *   }
 *
 * Returns:
 *   { success: true, screening_id: uuid, status: 'uploaded' }
 */
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PMI_VIDEO_DRIVE_FOLDER_ID = Deno.env.get("PMI_VIDEO_DRIVE_FOLDER_ID") ?? "";

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  let body: any;
  try { body = await req.json(); }
  catch { return json({ error: "invalid JSON" }, 400); }

  const { token, pillar, question_index, question_text, drive_file_id, drive_file_name, drive_folder_id } = body ?? {};

  if (!token || !pillar || !drive_file_id) return json({ error: "missing required fields" }, 400);
  if (!Number.isInteger(question_index) || question_index < 1 || question_index > 10) return json({ error: "invalid question_index" }, 400);

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // RPC enforces: token + scope + source_type='pmi_application' + storage_consistency CHECK
  const { data, error } = await sb.rpc("register_video_screening", {
    p_token: token,
    p_pillar: pillar,
    p_question_index: question_index,
    p_question_text: question_text ?? `Pillar ${question_index}: ${pillar}`,
    p_storage_provider: "google_drive",
    p_drive_file_id: drive_file_id,
    p_drive_folder_id: drive_folder_id ?? PMI_VIDEO_DRIVE_FOLDER_ID,
    p_drive_file_name: drive_file_name ?? null,
    p_youtube_url: null,
  });

  if (error) {
    return json({ error: "register_video_screening_failed", detail: error.message }, 500);
  }

  return json({
    success: true,
    screening_id: (data as any)?.screening_id,
    status: (data as any)?.status ?? "uploaded",
  });
});
