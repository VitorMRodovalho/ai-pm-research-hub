/**
 * pmi-video-test-transcribe — temporary test EF for Gemini video transcription.
 *
 * Workflow:
 *   1. Receive { video_screening_id }
 *   2. Lookup drive_file_id from pmi_video_screenings
 *   3. Download bytes from Drive (via OAuth refresh from Vault key google_drive_oauth_credentials)
 *   4. Upload to Gemini File API (resumable)
 *   5. Wait for file to become ACTIVE (polling)
 *   6. Call models/gemini-2.0-flash-exp:generateContent with transcribe prompt
 *   7. Return transcript text
 *
 * Auth: service-role only (POST). Internal test EF — não expor à candidate UI.
 *
 * Env: GEMINI_API_KEY required.
 *
 * NOTE: Não atualiza pmi_video_screenings.transcription. Saída é só pra inspeção
 *       PM. Worker dedicado (ai-interview-drafter) será criado em phase futura
 *       que sim atualiza o DB.
 */
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const VAULT_KEY = "google_drive_oauth_credentials";

const json = (d: unknown, s = 200) =>
  new Response(JSON.stringify(d), { status: s, headers: { "Content-Type": "application/json" } });

interface OAuthCreds { client_id: string; client_secret: string; refresh_token: string; }

async function getDriveAccessToken(sb: ReturnType<typeof createClient>): Promise<string> {
  const { data, error } = await sb.rpc("_get_vault_secret", { p_name: VAULT_KEY });
  if (error || !data) throw new Error(`Vault read failed: ${error?.message ?? "no data"}`);
  const creds = JSON.parse(data as string) as OAuthCreds;
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
  if (!res.ok) throw new Error(`OAuth token failed: ${res.status} ${await res.text()}`);
  return (await res.json()).access_token;
}

async function downloadDriveFile(fileId: string, accessToken: string): Promise<{ bytes: Uint8Array; mimeType: string; name: string }> {
  // First metadata
  const metaRes = await fetch(`https://www.googleapis.com/drive/v3/files/${fileId}?fields=id,name,mimeType,size&supportsAllDrives=true`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!metaRes.ok) throw new Error(`Drive metadata: ${metaRes.status} ${await metaRes.text()}`);
  const meta = await metaRes.json();

  // Download bytes
  const dlRes = await fetch(`https://www.googleapis.com/drive/v3/files/${fileId}?alt=media&supportsAllDrives=true`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!dlRes.ok) throw new Error(`Drive download: ${dlRes.status} ${await dlRes.text()}`);
  const buf = new Uint8Array(await dlRes.arrayBuffer());
  return { bytes: buf, mimeType: meta.mimeType ?? "video/mp4", name: meta.name ?? "video.mp4" };
}

async function uploadToGeminiFileAPI(bytes: Uint8Array, mimeType: string, displayName: string): Promise<{ uri: string; name: string }> {
  // Step 1: initiate resumable upload
  const initRes = await fetch(
    `https://generativelanguage.googleapis.com/upload/v1beta/files?key=${GEMINI_API_KEY}`,
    {
      method: "POST",
      headers: {
        "X-Goog-Upload-Protocol": "resumable",
        "X-Goog-Upload-Command": "start",
        "X-Goog-Upload-Header-Content-Length": String(bytes.length),
        "X-Goog-Upload-Header-Content-Type": mimeType,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ file: { display_name: displayName } }),
    },
  );
  if (!initRes.ok) throw new Error(`Gemini upload init: ${initRes.status} ${await initRes.text()}`);
  const uploadUrl = initRes.headers.get("X-Goog-Upload-URL");
  if (!uploadUrl) throw new Error("Gemini did not return upload URL");

  // Step 2: upload bytes
  const upRes = await fetch(uploadUrl, {
    method: "POST",
    headers: {
      "Content-Length": String(bytes.length),
      "X-Goog-Upload-Offset": "0",
      "X-Goog-Upload-Command": "upload, finalize",
    },
    body: bytes,
  });
  if (!upRes.ok) throw new Error(`Gemini upload bytes: ${upRes.status} ${await upRes.text()}`);
  const uploaded = await upRes.json();
  const fileResource = uploaded.file ?? uploaded;
  if (!fileResource?.uri) throw new Error("Gemini upload no uri");
  return { uri: fileResource.uri, name: fileResource.name ?? "" };
}

async function waitForActive(geminiName: string, maxWaitMs = 120_000): Promise<void> {
  const deadline = Date.now() + maxWaitMs;
  while (Date.now() < deadline) {
    const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/${geminiName}?key=${GEMINI_API_KEY}`);
    if (!r.ok) throw new Error(`File status: ${r.status} ${await r.text()}`);
    const f = await r.json();
    if (f.state === "ACTIVE") return;
    if (f.state === "FAILED") throw new Error(`Gemini file FAILED: ${JSON.stringify(f)}`);
    await new Promise(res => setTimeout(res, 3000));
  }
  throw new Error("Gemini file did not become ACTIVE within timeout");
}

async function transcribeWithGemini(fileUri: string, mimeType: string): Promise<string> {
  const prompt = `Você é um transcritor profissional. Transcreva o áudio deste vídeo em português brasileiro com a maior fidelidade possível ao que foi falado.

Inclua:
- Texto completo da fala
- Marcadores de timestamp [mm:ss] a cada 30 segundos ou em pausas significativas
- Identificação de pausas longas como "[pausa]" se houver
- Não adicione comentários nem interpretação — só transcrição literal do que foi dito

Se o vídeo não tiver áudio claro, indique "[áudio inaudível]" no momento correspondente.`;

  // gemini-2.5-flash: free tier quota OK (gemini-2.0-flash had limit:0 for our project)
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${GEMINI_API_KEY}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [
          {
            parts: [
              { fileData: { mimeType, fileUri } },
              { text: prompt },
            ],
          },
        ],
        generationConfig: { temperature: 0.1, maxOutputTokens: 4096 },
      }),
    },
  );
  if (!res.ok) throw new Error(`Gemini generate: ${res.status} ${await res.text()}`);
  const result = await res.json();
  const text = result.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) throw new Error(`Gemini no text: ${JSON.stringify(result).slice(0, 500)}`);
  return text;
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
  const { video_screening_id } = body ?? {};
  if (!video_screening_id) return json({ error: "missing video_screening_id" }, 400);

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const { data: vs, error: vsErr } = await sb
    .from("pmi_video_screenings")
    .select("drive_file_id, drive_file_name, mime_type, file_size_bytes, status")
    .eq("id", video_screening_id)
    .single();
  if (vsErr || !vs) return json({ error: "screening not found", detail: vsErr?.message }, 404);
  if (!vs.drive_file_id) return json({ error: "no drive_file_id" }, 400);

  const t0 = Date.now();
  try {
    const driveToken = await getDriveAccessToken(sb);
    const { bytes, mimeType, name } = await downloadDriveFile(vs.drive_file_id, driveToken);
    const t1 = Date.now();

    const { uri, name: gName } = await uploadToGeminiFileAPI(bytes, mimeType, name);
    const t2 = Date.now();

    await waitForActive(gName);
    const t3 = Date.now();

    const transcript = await transcribeWithGemini(uri, mimeType);
    const t4 = Date.now();

    return json({
      success: true,
      video_screening_id,
      drive_file: { id: vs.drive_file_id, name },
      transcript,
      timings_ms: {
        drive_download: t1 - t0,
        gemini_upload: t2 - t1,
        gemini_processing: t3 - t2,
        gemini_transcribe: t4 - t3,
        total: t4 - t0,
      },
      bytes_processed: bytes.length,
      gemini_file_uri: uri,
    });
  } catch (e) {
    return json({ error: "transcribe_failed", detail: String(e) }, 500);
  }
});
