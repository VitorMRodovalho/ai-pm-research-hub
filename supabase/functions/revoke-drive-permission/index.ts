/**
 * EF: revoke-drive-permission — #209 / ADR-0107 (revocation half).
 *
 * Deletes ONE approved Drive permission via the Google Drive API and marks the
 * drive_offboarding_audit row terminal. Invoked by the MCP approve tools
 * (approve_drive_revocation / bulk_approve_drive_revocations) synchronously, and by
 * the revoke-drive-drain safety-net cron. Acts ONLY on rows already flipped to
 * status='approved' by a GP (the approve RPC re-checks manage_member).
 *
 * GATED (ADR-0094 G4.1): the SA needs (a) the drive (write) scope — set here — and
 * (b) an organizer/fileOrganizer role on the folders (a Workspace admin task, the PM
 * gate). Until (b) is done, Google returns 403; this EF FAILS SAFE — it marks the row
 * status='failed' with the captured google_error and returns it inline (the GP sees
 * "needs role elevation"), never crashing. A 404 (grant already gone) → already_absent.
 *
 * Auth: service-role caller only — isServiceRoleToken (#738/#850). SA creds via Vault
 * google_drive_service_account_json; absent → 503 not_configured (fail-safe).
 *
 * Body: { audit_id: string }
 */
import { createClient } from "jsr:@supabase/supabase-js@2";
import { isServiceRoleToken } from "../_shared/service-auth.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const VAULT_KEY = "google_drive_service_account_json";
const WRITE_SCOPE = "https://www.googleapis.com/auth/drive";

async function getServiceAccountKey(): Promise<{ available: boolean; key?: any; error?: string }> {
  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
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

async function getAccessToken(saKey: any, scope: string): Promise<string> {
  const jwt = await signJwt(saKey, scope);
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
  });
  if (!res.ok) throw new Error(`Token exchange failed: ${res.status} ${await res.text()}`);
  return (await res.json()).access_token;
}

function bearerFrom(req: Request): string | null {
  const h = req.headers.get("Authorization") ?? req.headers.get("authorization") ?? "";
  return h.startsWith("Bearer ") ? h.slice(7) : null;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405 });
  }
  if (!(await isServiceRoleToken(SUPABASE_URL, bearerFrom(req)))) {
    return new Response(JSON.stringify({ error: "unauthorized", detail: "service-role only" }), { status: 401 });
  }

  let body: { audit_id?: string };
  try { body = await req.json(); } catch { return new Response(JSON.stringify({ error: "Invalid JSON body" }), { status: 400 }); }
  const auditId = body.audit_id?.trim();
  if (!auditId) return new Response(JSON.stringify({ error: "audit_id required" }), { status: 400 });

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const { data: row, error: rowErr } = await sb.rpc("get_drive_revocation_row", { p_audit_id: auditId });
  if (rowErr) return new Response(JSON.stringify({ error: "rpc_error", detail: rowErr.message }), { status: 500 });
  if (!row) return new Response(JSON.stringify({ error: "not_found", audit_id: auditId }), { status: 404 });

  // Idempotency / safety: only act on GP-approved rows.
  if (row.status !== "approved") {
    return new Response(JSON.stringify({ audit_id: auditId, result: "skipped", status: row.status,
      note: "EF acts only on status=approved (GP must approve first)" }), { status: 200, headers: { "Content-Type": "application/json" } });
  }

  const saResult = await getServiceAccountKey();
  if (!saResult.available) {
    return new Response(JSON.stringify({
      error: "drive_integration_not_configured", detail: saResult.error,
      next_steps: "PM: seed Vault key 'google_drive_service_account_json'. See docs/operations/DRIVE_OFFBOARDING_CASCADE.md",
    }), { status: 503 });
  }

  let accessToken: string;
  try { accessToken = await getAccessToken(saResult.key, WRITE_SCOPE); }
  catch (e) { return new Response(JSON.stringify({ error: "drive_auth_error", detail: String(e) }), { status: 502 }); }

  // DELETE the permission.
  const url = new URL(`https://www.googleapis.com/drive/v3/files/${row.drive_file_id}/permissions/${row.permission_id}`);
  url.searchParams.set("supportsAllDrives", "true");
  let httpStatus = 0; let respText = "";
  try {
    const res = await fetch(url, { method: "DELETE", headers: { Authorization: `Bearer ${accessToken}` } });
    httpStatus = res.status;
    if (!res.ok) respText = await res.text();
  } catch (e) {
    // Network/transport error → failed, fail-safe.
    await sb.rpc("mark_drive_revocation_done", { p_audit_id: auditId, p_status: "failed",
      p_google_error: { transport_error: String(e) } });
    return new Response(JSON.stringify({ audit_id: auditId, result: "failed", detail: String(e) }), { status: 502 });
  }

  // Classify (fail-safe — every outcome maps to a stored status, never a crash).
  let newStatus: "revoked" | "already_absent" | "failed";
  let googleError: any = null;
  if (httpStatus === 204 || httpStatus === 200) {
    newStatus = "revoked";
  } else if (httpStatus === 404) {
    newStatus = "already_absent"; // grant already gone — success-equivalent
    googleError = { status: 404, message: respText.slice(0, 500) };
  } else {
    newStatus = "failed"; // 403 (role/scope), 400 (inherited), etc. — gated state, surfaced to GP
    googleError = { status: httpStatus, message: respText.slice(0, 800) };
  }

  const { error: markErr } = await sb.rpc("mark_drive_revocation_done", {
    p_audit_id: auditId, p_status: newStatus, p_google_error: googleError,
  });
  if (markErr) {
    return new Response(JSON.stringify({ error: "mark_error", detail: markErr.message, google_status: httpStatus }), { status: 500 });
  }

  const human = newStatus === "failed" && httpStatus === 403
    ? "revocation blocked (403): the service account needs organizer/fileOrganizer role on the folder (Workspace admin task, ADR-0094 G4.1)."
    : undefined;
  return new Response(JSON.stringify({ audit_id: auditId, result: newStatus, google_status: httpStatus, note: human }),
    { status: 200, headers: { "Content-Type": "application/json" } });
});
