/**
 * Drive Integration EF — upload file to a Drive folder.
 *
 * Multipart upload (Drive API V3 /upload). Accepts text or base64 content.
 *
 * Auth: OAuth user-delegated refresh token flow (ADR-0064 amended).
 *   - Path F adopted because PM is not Workspace Admin of pmigo.org.br
 *     (Path A DwD blocked) and `nucleoia@pmigo.org.br` user lacks Shared Drive
 *     creation perms (Path B blocked).
 *   - Refresh token grants offline access AS the user; files are owned by the
 *     user (uses their quota) — bypasses SA storage-quota constraint.
 *
 * Vault key: google_drive_oauth_credentials (JSON with client_id, client_secret, refresh_token)
 *
 * Body:
 *   {
 *     folder_id: string,         // Drive folder ID
 *     filename: string,
 *     mime_type?: string,        // default text/plain
 *     content_text?: string,     // raw text (for ata.md generation)
 *     content_base64?: string    // base64-encoded binary
 *   }
 *
 * Returns: { success, drive_file_id, drive_file_url, filename, mime_type, size_bytes }
 */
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const VAULT_KEY = "google_drive_oauth_credentials";

interface OAuthCreds {
  client_id: string;
  client_secret: string;
  refresh_token: string;
}

async function getOAuthCreds(): Promise<{ available: boolean; creds?: OAuthCreds; error?: string }> {
  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data, error } = await sb.rpc("_get_vault_secret", { p_name: VAULT_KEY });
  if (error) return { available: false, error: `Vault read error: ${error.message}` };
  if (!data || typeof data !== "string" || data.length === 0) {
    return { available: false, error: `Vault key '${VAULT_KEY}' not seeded` };
  }
  try {
    const parsed = JSON.parse(data);
    if (!parsed.client_id || !parsed.client_secret || !parsed.refresh_token) {
      return { available: false, error: "OAuth creds JSON missing client_id/client_secret/refresh_token" };
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

async function uploadFile(
  folderId: string,
  filename: string,
  mimeType: string,
  body: Uint8Array,
  accessToken: string,
): Promise<{ id: string; webViewLink: string; size?: string; mimeType: string; name: string }> {
  // Multipart-related per Drive API V3 docs
  const boundary = `------WebKitFormBoundary${crypto.randomUUID().replace(/-/g, "")}`;
  const metadata = JSON.stringify({ name: filename, parents: [folderId], mimeType });

  const enc = new TextEncoder();
  const preamble = enc.encode(
    `--${boundary}\r\n` +
    `Content-Type: application/json; charset=UTF-8\r\n\r\n` +
    `${metadata}\r\n` +
    `--${boundary}\r\n` +
    `Content-Type: ${mimeType}\r\n\r\n`,
  );
  const closing = enc.encode(`\r\n--${boundary}--`);
  const multipartBody = new Uint8Array(preamble.length + body.length + closing.length);
  multipartBody.set(preamble, 0);
  multipartBody.set(body, preamble.length);
  multipartBody.set(closing, preamble.length + body.length);

  const url = new URL("https://www.googleapis.com/upload/drive/v3/files");
  url.searchParams.set("uploadType", "multipart");
  url.searchParams.set("fields", "id,name,mimeType,size,webViewLink");
  url.searchParams.set("supportsAllDrives", "true");

  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": `multipart/related; boundary=${boundary}`,
    },
    body: multipartBody,
  });
  if (!res.ok) throw new Error(`Drive upload failed: ${res.status} ${await res.text()}`);
  return await res.json();
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405 });
  }

  let body: { folder_id?: string; filename?: string; mime_type?: string; content_text?: string; content_base64?: string };
  try { body = await req.json(); }
  catch { return new Response(JSON.stringify({ error: "Invalid JSON body" }), { status: 400 }); }

  const folderId = body.folder_id?.trim();
  const filename = body.filename?.trim();
  if (!folderId) return new Response(JSON.stringify({ error: "folder_id required" }), { status: 400 });
  if (!filename) return new Response(JSON.stringify({ error: "filename required" }), { status: 400 });

  const hasText = typeof body.content_text === "string";
  const hasBase64 = typeof body.content_base64 === "string";
  if (!hasText && !hasBase64) {
    return new Response(JSON.stringify({ error: "content_text or content_base64 required" }), { status: 400 });
  }
  if (hasText && hasBase64) {
    return new Response(JSON.stringify({ error: "provide only content_text OR content_base64, not both" }), { status: 400 });
  }

  // Hard cap: 7 MB (PM directive — keep platform light, use Drive native for heavy files)
  const MAX_BYTES = 7 * 1024 * 1024;
  let bytes: Uint8Array;
  if (hasText) {
    bytes = new TextEncoder().encode(body.content_text!);
  } else {
    try {
      const bin = atob(body.content_base64!);
      bytes = Uint8Array.from(bin, c => c.charCodeAt(0));
    } catch {
      return new Response(JSON.stringify({ error: "content_base64 is not valid base64" }), { status: 400 });
    }
  }
  if (bytes.length > MAX_BYTES) {
    return new Response(
      JSON.stringify({ error: "file_too_large", detail: `${bytes.length} bytes > 7MB cap. Use Drive native upload directly.` }),
      { status: 413 },
    );
  }

  const mimeType = body.mime_type?.trim() || (hasText ? "text/plain" : "application/octet-stream");

  const credsResult = await getOAuthCreds();
  if (!credsResult.available) {
    return new Response(
      JSON.stringify({
        error: "drive_integration_not_configured",
        detail: credsResult.error,
        next_steps: "PM: seed Vault key 'google_drive_oauth_credentials' (ADR-0064 amended). See docs/SETUP_GOOGLE_DRIVE_INTEGRATION.md Passo 9.",
      }),
      { status: 503 },
    );
  }

  try {
    const accessToken = await getAccessToken(credsResult.creds!);
    const file = await uploadFile(folderId, filename, mimeType, bytes, accessToken);
    return new Response(
      JSON.stringify({
        success: true,
        drive_file_id: file.id,
        drive_file_url: file.webViewLink,
        filename: file.name,
        mime_type: file.mimeType,
        size_bytes: file.size ? parseInt(file.size, 10) : bytes.length,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ error: "drive_api_error", detail: String(e) }),
      { status: 502 },
    );
  }
});
