/**
 * EF: manage-curation-drive-grant — #301 / ADR-0108 (GRANT mirror of #209 revoke).
 *
 * Creates OR deletes ONE curation Drive permission via the Google Drive API and marks the
 * drive_curation_grants row terminal. Drained by the curation-grant-drain / curation-revoke-drain
 * crons (the PRIMARY executor — the eager auto-grant has no synchronous human path), and invoked
 * synchronously by the GP force_grant/force_revoke MCP tools.
 *
 *   action='grant'  → POST   /files/{id}/permissions  (role=commenter, type=user) → permission_id
 *   action='revoke' → DELETE /files/{id}/permissions/{permission_id}
 *
 * Acts ONLY on rows in the matching open status (pending_grant / pending_revoke). Fail-safe: every
 * outcome maps to a stored terminal status (granted/failed | revoked/revoke_failed), never a crash.
 *
 * sendNotificationEmail wrinkle (create only): Google REJECTS sendNotificationEmail=false when the
 * grantee is OUTSIDE the SA's Workspace domain (400). All current curators are gmail (external), so
 * we default to true for out-of-domain and retry-with-true on that specific 400.
 *
 * Auth: service-role caller only — isServiceRoleToken (#738/#850). SA creds via Vault
 * google_drive_service_account_json; absent → 503 not_configured (fail-safe).
 *
 * Body: { grant_id: string, action: "grant" | "revoke" }
 */
import { createClient } from "jsr:@supabase/supabase-js@2";
import { isServiceRoleToken } from "../_shared/service-auth.ts";
import { getServiceAccountKey, getAccessToken, bearerFrom, DRIVE_WRITE_SCOPE } from "../_shared/drive-sa.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const WORKSPACE_DOMAIN = "pmigo.org.br"; // the SA's Workspace domain; out-of-domain → notify required

const notConfigured = (err?: string) => new Response(JSON.stringify({
  error: "drive_integration_not_configured", detail: err,
  next_steps: "PM: seed Vault key 'google_drive_service_account_json'. See docs/operations/DRIVE_OFFBOARDING_CASCADE.md",
}), { status: 503 });

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405 });
  }
  if (!(await isServiceRoleToken(SUPABASE_URL, bearerFrom(req)))) {
    return new Response(JSON.stringify({ error: "unauthorized", detail: "service-role only" }), { status: 401 });
  }

  let body: { grant_id?: string; action?: string };
  try { body = await req.json(); } catch { return new Response(JSON.stringify({ error: "Invalid JSON body" }), { status: 400 }); }
  const grantId = body.grant_id?.trim();
  const action = body.action?.trim();
  if (!grantId) return new Response(JSON.stringify({ error: "grant_id required" }), { status: 400 });
  if (action !== "grant" && action !== "revoke") {
    return new Response(JSON.stringify({ error: "action must be 'grant' or 'revoke'" }), { status: 400 });
  }

  const sb = createClient<any, "public", any>(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const { data: row, error: rowErr } = await sb.rpc("get_curation_grant_row", { p_grant_id: grantId });
  if (rowErr) return new Response(JSON.stringify({ error: "rpc_error", detail: rowErr.message }), { status: 500 });
  if (!row) return new Response(JSON.stringify({ error: "not_found", grant_id: grantId }), { status: 404 });

  // ───────────────────────── GRANT ─────────────────────────
  if (action === "grant") {
    if (row.status !== "pending_grant") {
      return new Response(JSON.stringify({ grant_id: grantId, result: "skipped", status: row.status,
        note: "EF acts only on status=pending_grant" }), { status: 200, headers: { "Content-Type": "application/json" } });
    }

    const sa = await getServiceAccountKey();
    if (!sa.available) return notConfigured(sa.error);

    let accessToken: string;
    try { accessToken = await getAccessToken(sa.key, DRIVE_WRITE_SCOPE); }
    catch (e) { return new Response(JSON.stringify({ error: "drive_auth_error", detail: String(e) }), { status: 502 }); }

    const email: string = String(row.permission_email);
    const inDomain = email.toLowerCase().endsWith("@" + WORKSPACE_DOMAIN);

    const attempt = async (notify: boolean) => {
      const url = new URL(`https://www.googleapis.com/drive/v3/files/${row.drive_file_id}/permissions`);
      url.searchParams.set("supportsAllDrives", "true");
      url.searchParams.set("sendNotificationEmail", String(notify));
      url.searchParams.set("fields", "id,role,type,emailAddress");
      return await fetch(url, {
        method: "POST",
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        body: JSON.stringify({ role: row.role || "commenter", type: "user", emailAddress: email }),
      });
    };

    let httpStatus = 0; let respText = ""; let respJson: any = null;
    try {
      let res = await attempt(!inDomain); // default: notify out-of-domain users (Google requires it)
      // If we tried false (in-domain) and Google still demands a notification, retry with true.
      if (res.status === 400 && inDomain) res = await attempt(true);
      httpStatus = res.status;
      if (res.ok) respJson = await res.json().catch(() => null);
      else respText = await res.text();
    } catch (e) {
      await sb.rpc("mark_curation_grant_done", { p_grant_id: grantId, p_status: "failed",
        p_permission_id: null, p_api_error: { transport_error: String(e) } });
      return new Response(JSON.stringify({ grant_id: grantId, result: "failed", detail: String(e) }), { status: 502 });
    }

    let newStatus: "granted" | "failed";
    let permissionId: string | null = null;
    let apiError: any = null;
    if (httpStatus === 200 || httpStatus === 201) {
      newStatus = "granted";
      permissionId = respJson?.id ?? null;
      if (!permissionId) { newStatus = "failed"; apiError = { status: httpStatus, message: "grant succeeded but no permission id returned" }; }
    } else {
      newStatus = "failed"; // 403 (role/scope), 400 (sharing policy / external), etc.
      apiError = { status: httpStatus, message: respText.slice(0, 800) };
    }

    const { error: markErr } = await sb.rpc("mark_curation_grant_done", {
      p_grant_id: grantId, p_status: newStatus, p_permission_id: permissionId, p_api_error: apiError,
    });
    if (markErr) return new Response(JSON.stringify({ error: "mark_error", detail: markErr.message, google_status: httpStatus }), { status: 500 });

    const human = newStatus === "failed" && httpStatus === 403
      ? "grant blocked (403): the service account needs organizer/fileOrganizer role on the folder (Workspace admin task, ADR-0094 G4.1)."
      : (newStatus === "failed" && httpStatus === 400
        ? "grant blocked (400): Drive sharing policy may forbid external (out-of-domain) sharing for this file."
        : undefined);
    return new Response(JSON.stringify({ grant_id: grantId, result: newStatus, google_status: httpStatus, permission_id: permissionId, note: human }),
      { status: 200, headers: { "Content-Type": "application/json" } });
  }

  // ───────────────────────── REVOKE ─────────────────────────
  if (row.status !== "pending_revoke") {
    return new Response(JSON.stringify({ grant_id: grantId, result: "skipped", status: row.status,
      note: "EF acts only on status=pending_revoke" }), { status: 200, headers: { "Content-Type": "application/json" } });
  }

  // Nothing was ever created in Drive (grant never executed) → terminal revoked, no Drive call.
  if (!row.permission_id) {
    await sb.rpc("mark_curation_grant_revoked", { p_grant_id: grantId, p_status: "revoked",
      p_api_error: { note: "no permission_id — grant never executed, nothing to delete" } });
    return new Response(JSON.stringify({ grant_id: grantId, result: "revoked", note: "no permission_id (nothing to delete)" }),
      { status: 200, headers: { "Content-Type": "application/json" } });
  }

  const sa = await getServiceAccountKey();
  if (!sa.available) return notConfigured(sa.error);

  let accessToken: string;
  try { accessToken = await getAccessToken(sa.key, DRIVE_WRITE_SCOPE); }
  catch (e) { return new Response(JSON.stringify({ error: "drive_auth_error", detail: String(e) }), { status: 502 }); }

  const url = new URL(`https://www.googleapis.com/drive/v3/files/${row.drive_file_id}/permissions/${row.permission_id}`);
  url.searchParams.set("supportsAllDrives", "true");
  let httpStatus = 0; let respText = "";
  try {
    const res = await fetch(url, { method: "DELETE", headers: { Authorization: `Bearer ${accessToken}` } });
    httpStatus = res.status;
    if (!res.ok) respText = await res.text();
  } catch (e) {
    await sb.rpc("mark_curation_grant_revoked", { p_grant_id: grantId, p_status: "revoke_failed",
      p_api_error: { transport_error: String(e) } });
    return new Response(JSON.stringify({ grant_id: grantId, result: "revoke_failed", detail: String(e) }), { status: 502 });
  }

  let newStatus: "revoked" | "revoke_failed";
  let apiError: any = null;
  if (httpStatus === 204 || httpStatus === 200 || httpStatus === 404) {
    newStatus = "revoked"; // 404 = permission already gone → success-equivalent
    if (httpStatus === 404) apiError = { status: 404, message: respText.slice(0, 500) };
  } else {
    newStatus = "revoke_failed"; // 403 (role/scope), etc.
    apiError = { status: httpStatus, message: respText.slice(0, 800) };
  }

  const { error: markErr } = await sb.rpc("mark_curation_grant_revoked", {
    p_grant_id: grantId, p_status: newStatus, p_api_error: apiError,
  });
  if (markErr) return new Response(JSON.stringify({ error: "mark_error", detail: markErr.message, google_status: httpStatus }), { status: 500 });

  const human = newStatus === "revoke_failed" && httpStatus === 403
    ? "revoke blocked (403): the service account needs organizer/fileOrganizer role on the folder (ADR-0094 G4.1)."
    : undefined;
  return new Response(JSON.stringify({ grant_id: grantId, result: newStatus, google_status: httpStatus, note: human }),
    { status: 200, headers: { "Content-Type": "application/json" } });
});
