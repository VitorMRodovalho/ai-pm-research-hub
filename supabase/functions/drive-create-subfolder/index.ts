/**
 * Drive Integration EF — create a subfolder inside a parent Drive folder.
 *
 * Drive auth: OAuth user-delegated refresh token flow (ADR-0064 amended).
 * Folders consume 0 bytes of quota, but using OAuth here keeps consistency
 * com upload EF + ownership cai no usuário (não na SA).
 *
 * Caller auth (#1380): service-role only (isServiceRoleToken, mirror of the
 * reconcile-initiative-drive-access EF, #738/#850). The EF deploys with
 * verify_jwt=false, so the gateway does NOT gate it — without this check any
 * unauthenticated internet caller could create Drive folders under the org SA.
 * Both legitimate callers (nucleo-mcp tools create_drive_subfolder /
 * provision_initiative_drive) enforce the member's V4 authority and call this
 * EF server-to-server with the SERVICE_ROLE_KEY, so gating on service-role is
 * non-breaking and independent of the deploy flags.
 *
 * Vault key: google_drive_oauth_credentials
 *
 * Body:
 *   { parent_folder_id: string, name: string }
 *
 * Returns: { success, drive_folder_id, drive_folder_url, name }
 */
import { createClient } from "jsr:@supabase/supabase-js@2";
import { isServiceRoleToken } from "../_shared/service-auth.ts";
import { bearerFrom } from "../_shared/drive-sa.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const VAULT_KEY = "google_drive_oauth_credentials";

interface OAuthCreds {
  client_id: string;
  client_secret: string;
  refresh_token: string;
}

async function getOAuthCreds(): Promise<{ available: boolean; creds?: OAuthCreds; error?: string }> {
  const sb = createClient<any, "public", any>(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
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

  // #1380: service-role only. verify_jwt=false leaves the gateway open, so this
  // is the sole auth moat. Callers gate the member's authority before invoking.
  if (!(await isServiceRoleToken(SUPABASE_URL, bearerFrom(req)))) {
    return new Response(
      JSON.stringify({ error: "unauthorized", detail: "service-role only" }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }

  let body: { parent_folder_id?: string; name?: string };
  try { body = await req.json(); }
  catch { return new Response(JSON.stringify({ error: "Invalid JSON body" }), { status: 400 }); }

  const parentId = body.parent_folder_id?.trim();
  const name = body.name?.trim();
  if (!parentId) return new Response(JSON.stringify({ error: "parent_folder_id required" }), { status: 400 });
  if (!name) return new Response(JSON.stringify({ error: "name required" }), { status: 400 });
  if (name.length > 200) return new Response(JSON.stringify({ error: "name max length 200 chars" }), { status: 400 });

  const credsResult = await getOAuthCreds();
  if (!credsResult.available) {
    return new Response(
      JSON.stringify({
        error: "drive_integration_not_configured",
        detail: credsResult.error,
        next_steps: "PM: seed Vault key 'google_drive_oauth_credentials' (ADR-0064 amended).",
      }),
      { status: 503 },
    );
  }

  try {
    const accessToken = await getAccessToken(credsResult.creds!);
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
