/**
 * Shared Google Drive service-account auth helpers — #301 / ADR-0108.
 *
 * Extracted from the #209 EFs (revoke-drive-permission / audit-drive-offboarding-access), which
 * duplicated this trio inline. The new #301 grant/revoke EF imports it to avoid a third copy.
 * (The two #209 EFs still carry their inline copies — deduping them is a severable follow-up; this
 * module is behaviour-identical so a later refactor is byte-safe.)
 *
 * SA creds come from Vault `google_drive_service_account_json` via `_get_vault_secret` (service-role
 * only). The SA must hold organizer/fileOrganizer on the target folders (PM elevated it 2026-06-27
 * for #209) — creating/deleting a permission for another user is an organizer-only operation.
 */
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const VAULT_KEY = "google_drive_service_account_json";

/** Full Drive (write) scope — required to BOTH create and delete permissions. */
export const DRIVE_WRITE_SCOPE = "https://www.googleapis.com/auth/drive";

export async function getServiceAccountKey(): Promise<{ available: boolean; key?: any; error?: string }> {
  const sb = createClient<any, "public", any>(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data, error } = await sb.rpc("_get_vault_secret", { p_name: VAULT_KEY });
  if (error) return { available: false, error: `Vault read error: ${error.message}` };
  if (!data || typeof data !== "string" || data.length === 0) {
    return { available: false, error: `Vault key '${VAULT_KEY}' not seeded — see docs/operations/DRIVE_OFFBOARDING_CASCADE.md` };
  }
  try { return { available: true, key: JSON.parse(data) }; }
  catch { return { available: false, error: "Vault key is not valid JSON" }; }
}

async function signJwt(saKey: any, scope: string): Promise<string> {
  const header = { alg: "RS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const payload = { iss: saKey.client_email, scope, aud: "https://oauth2.googleapis.com/token", exp: now + 3600, iat: now };
  const enc = (o: any) => btoa(JSON.stringify(o)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
  const unsigned = `${enc(header)}.${enc(payload)}`;
  const pemHeaderPattern = new RegExp("-{5}(BEGIN|END) PRIVATE KEY-{5}|\\s", "g");
  const pem = saKey.private_key.replace(pemHeaderPattern, "");
  const der = Uint8Array.from(atob(pem), c => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8", der.buffer, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", cryptoKey, new TextEncoder().encode(unsigned));
  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(sig))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
  return `${unsigned}.${sigB64}`;
}

export async function getAccessToken(saKey: any, scope: string): Promise<string> {
  const jwt = await signJwt(saKey, scope);
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
  });
  if (!res.ok) throw new Error(`Token exchange failed: ${res.status} ${await res.text()}`);
  return (await res.json()).access_token;
}

export function bearerFrom(req: Request): string | null {
  const h = req.headers.get("Authorization") ?? req.headers.get("authorization") ?? "";
  return h.startsWith("Bearer ") ? h.slice(7) : null;
}
