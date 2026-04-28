/**
 * Drive Integration EF — create a subfolder inside a parent Drive folder.
 *
 * Auth: Service Account JWT (RS256) → OAuth2 token → Drive API.
 * Scope: drive (full) — SA must have Editor on parent folder.
 *
 * Body:
 *   { parent_folder_id: string, name: string }
 *
 * Returns: { success, drive_folder_id, drive_folder_url, name }
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
  // Domain-Wide Delegation: SA impersonates a real user so created folders
  // are owned by that user (avoids edge cases when other users access them).
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

async function createSubfolder(
  parentId: string,
  name: string,
  accessToken: string,
): Promise<{ id: string; webViewLink: string; name: string }> {
  const url = new URL("https://www.googleapis.com/drive/v3/files");
  url.searchParams.set("fields", "id,name,webViewLink");
  url.searchParams.set("supportsAllDrives", "true");
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      name,
      mimeType: "application/vnd.google-apps.folder",
      parents: [parentId],
    }),
  });
  if (!res.ok) throw new Error(`Drive create folder failed: ${res.status} ${await res.text()}`);
  return await res.json();
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405 });
  }

  let body: { parent_folder_id?: string; name?: string };
  try { body = await req.json(); }
  catch { return new Response(JSON.stringify({ error: "Invalid JSON body" }), { status: 400 }); }

  const parentId = body.parent_folder_id?.trim();
  const name = body.name?.trim();
  if (!parentId) return new Response(JSON.stringify({ error: "parent_folder_id required" }), { status: 400 });
  if (!name) return new Response(JSON.stringify({ error: "name required" }), { status: 400 });
  if (name.length > 200) return new Response(JSON.stringify({ error: "name max length 200 chars" }), { status: 400 });

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
    const folder = await createSubfolder(parentId, name, accessToken);
    return new Response(
      JSON.stringify({
        success: true,
        drive_folder_id: folder.id,
        drive_folder_url: folder.webViewLink,
        name: folder.name,
        parent_folder_id: parentId,
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
