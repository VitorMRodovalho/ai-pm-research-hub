/**
 * Drive Integration EF — upload file to a Drive folder via Service Account.
 *
 * Multipart upload (Drive API V3 /upload). Accepts text or base64 content.
 *
 * Auth: Service Account JWT (RS256) → OAuth2 token → Drive API.
 * Scope: drive (full) — SA must have Editor on target folder.
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
const VAULT_KEY = "google_drive_service_account_json";

async function getServiceAccountKey(): Promise<{ available: boolean; key?: any; error?: string }> {
  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data, error } = await sb.rpc("_get_vault_secret", { p_name: VAULT_KEY });
  if (error) return { available: false, error: `Vault read error: ${error.message}` };
  if (!data || typeof data !== "string" || data.length === 0) {
    return { available: false, error: `Vault key '${VAULT_KEY}' not seeded` };
  }
  try { return { available: true, key: JSON.parse(data) }; }
  catch { return { available: false, error: "Vault key is not valid JSON" }; }
}

async function signJwt(saKey: any): Promise<string> {
  const header = { alg: "RS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  // Domain-Wide Delegation: SA impersonates a real user so file ownership
  // (and quota) belongs to that user — SAs have no own storage quota.
  // PM must enable DwD in Workspace Admin → Security → API Controls.
  const impersonate = Deno.env.get("GOOGLE_DRIVE_IMPERSONATE_USER") ?? "nucleoia@pmigo.org.br";
  const payload: Record<string, unknown> = {
    iss: saKey.client_email,
    scope: "https://www.googleapis.com/auth/drive",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
    sub: impersonate,
  };
  const enc = (o: any) => btoa(JSON.stringify(o)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
  const unsigned = `${enc(header)}.${enc(payload)}`;

  const pemHeaderPattern = new RegExp("-{5}(BEGIN|END) PRIVATE KEY-{5}|\\s", "g");
  const pem = saKey.private_key.replace(pemHeaderPattern, "");
  const der = Uint8Array.from(atob(pem), c => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8", der.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false, ["sign"]
  );
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", cryptoKey, new TextEncoder().encode(unsigned));
  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(sig))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
  return `${unsigned}.${sigB64}`;
}

async function getAccessToken(saKey: any): Promise<string> {
  const jwt = await signJwt(saKey);
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) throw new Error(`Token exchange failed: ${res.status} ${await res.text()}`);
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

  const saResult = await getServiceAccountKey();
  if (!saResult.available) {
    return new Response(
      JSON.stringify({
        error: "drive_integration_not_configured",
        detail: saResult.error,
        next_steps: "PM: see docs/SETUP_GOOGLE_DRIVE_INTEGRATION.md",
      }),
      { status: 503 },
    );
  }

  try {
    const accessToken = await getAccessToken(saResult.key);
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
