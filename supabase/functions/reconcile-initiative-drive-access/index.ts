/**
 * EF: reconcile-initiative-drive-access — #1376 / ADR-0124 (auto-GRANT, mirror of #209 auto-revoke).
 *
 * For each active initiative with a workspace Drive link, diffs the ACTIVE roster against the folder's
 * live ACL and grants (role=writer) every roster member the folder is missing. This closes the
 * auto-revoke ↔ auto-grant asymmetry: #209 removes offboarded members, this adds active ones — so a
 * reorg / folder move / new member no longer breaks access silently with no repair (the #1375 incident).
 *
 * Unlike the offboarding scan (which searches the SA's whole corpus for files shared with an ex-member),
 * the grant side is folder-anchored: initiative_drive_links already names the folder, so we only
 * listPermissions on THAT folder — cheap and bounded.
 *
 * Flow (all DB reads/writes via SECURITY DEFINER service-role RPCs):
 *   1. get_membership_drive_targets(initiative_id?) → workspace folders to reconcile
 *   2. per initiative: get_initiative_drive_roster(initiative_id) → active member emails (PII-logged)
 *   3. per folder: listPermissions → diff roster vs present → POST the missing grants (writer)
 *   4. upsert_membership_drive_grants(rows) → idempotent ledger + admin_audit_log
 *
 * Body: { initiative_id?: string, dry_run?: boolean, source?: "pg_cron"|"provision"|"manual" }
 * Auth: service-role only (isServiceRoleToken, #738/#850). SA creds via Vault; absent → 503.
 *
 * The 403 gate (ADR-0094 G4.1): a POST fails with 403 until the SA holds organizer/fileOrganizer on
 * the folder — same Workspace-admin dependency as the revoke side. Failures land as `failed` ledger
 * rows (never crash), surfaced by get_membership_drive_grant_health.
 */
import { createClient } from "jsr:@supabase/supabase-js@2";
import { isServiceRoleToken } from "../_shared/service-auth.ts";
import { getServiceAccountKey, getAccessToken, bearerFrom, DRIVE_WRITE_SCOPE } from "../_shared/drive-sa.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const WORKSPACE_DOMAIN = "pmigo.org.br";
const MAX_GRANTS_PER_RUN = 800; // defensive backstop; a full sweep is ~roster×folders (< a few hundred)

interface DrivePermission { id?: string; type?: string; role?: string; emailAddress?: string; deleted?: boolean }

/** All permissions on a folder, fully paginated (copy of the audit EF helper). */
async function listPermissions(fileId: string, accessToken: string): Promise<DrivePermission[]> {
  const out: DrivePermission[] = [];
  let pageToken: string | undefined;
  do {
    const url = new URL(`https://www.googleapis.com/drive/v3/files/${fileId}/permissions`);
    url.searchParams.set("fields", "nextPageToken, permissions(id,type,role,emailAddress,deleted)");
    url.searchParams.set("pageSize", "100");
    url.searchParams.set("supportsAllDrives", "true");
    if (pageToken) url.searchParams.set("pageToken", pageToken);
    const res = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } });
    if (!res.ok) throw new Error(`permissions.list ${fileId} failed: ${res.status} ${await res.text()}`);
    const json = await res.json();
    for (const p of (json.permissions ?? [])) out.push(p);
    pageToken = json.nextPageToken;
  } while (pageToken);
  return out;
}

/** Grant one writer permission, honoring Google's out-of-domain sendNotificationEmail requirement. */
async function grantWriter(folderId: string, email: string, accessToken: string):
  Promise<{ ok: boolean; permissionId: string | null; status: number; error?: any }> {
  const inDomain = email.toLowerCase().endsWith("@" + WORKSPACE_DOMAIN);
  const attempt = async (notify: boolean) => {
    const url = new URL(`https://www.googleapis.com/drive/v3/files/${folderId}/permissions`);
    url.searchParams.set("supportsAllDrives", "true");
    url.searchParams.set("sendNotificationEmail", String(notify));
    url.searchParams.set("fields", "id,role,type,emailAddress");
    return await fetch(url, {
      method: "POST",
      headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({ role: "writer", type: "user", emailAddress: email }),
    });
  };
  try {
    let res = await attempt(!inDomain);
    if (res.status === 400 && inDomain) res = await attempt(true);
    if (res.status === 200 || res.status === 201) {
      const j = await res.json().catch(() => null);
      const pid = j?.id ?? null;
      return pid ? { ok: true, permissionId: pid, status: res.status }
                 : { ok: false, permissionId: null, status: res.status, error: { message: "grant ok but no permission id" } };
    }
    return { ok: false, permissionId: null, status: res.status, error: { status: res.status, message: (await res.text()).slice(0, 800) } };
  } catch (e) {
    return { ok: false, permissionId: null, status: 0, error: { transport_error: String(e) } };
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405 });
  if (!(await isServiceRoleToken(SUPABASE_URL, bearerFrom(req)))) {
    return new Response(JSON.stringify({ error: "unauthorized", detail: "service-role only" }), { status: 401 });
  }

  let body: { initiative_id?: string; dry_run?: boolean; source?: string; force_email?: string } = {};
  try { body = await req.json(); } catch { /* empty body ok */ }
  const dryRun = body.dry_run === true;
  const source = body.source ?? "manual";
  // force_email: POST a direct writer grant for ONE roster member even if the folder ACL already shows
  // them present (i.e. they only hold an INHERITED permission). Makes their access explicit + ledger-
  // tracked + self-healing, instead of fragile inheritance. Scope with initiative_id to bound the folders.
  const forceEmail = (body.force_email ?? "").trim().toLowerCase();

  const sa = await getServiceAccountKey();
  if (!sa.available) {
    return new Response(JSON.stringify({
      error: "drive_integration_not_configured", detail: sa.error,
      next_steps: "PM: seed Vault key 'google_drive_service_account_json'. See docs/operations/DRIVE_OFFBOARDING_CASCADE.md",
    }), { status: 503 });
  }

  const sb = createClient<any, "public", any>(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  let accessToken: string;
  try { accessToken = await getAccessToken(sa.key, DRIVE_WRITE_SCOPE); }
  catch (e) { return new Response(JSON.stringify({ error: "drive_auth_error", detail: String(e) }), { status: 502 }); }

  // 1. targets (workspace folders)
  const { data: targets, error: tErr } = await sb.rpc("get_membership_drive_targets",
    { p_initiative_id: body.initiative_id ?? null });
  if (tErr) return new Response(JSON.stringify({ error: "rpc_error", detail: tErr.message }), { status: 500 });
  if (!targets || targets.length === 0) {
    return new Response(JSON.stringify({ success: true, source, targets: 0, note: "no active workspace links to reconcile" }),
      { status: 200, headers: { "Content-Type": "application/json" } });
  }

  // 2. roster per initiative (cached across that initiative's folders)
  const rosterCache = new Map<string, Array<{ person_id: string; member_id: string; email: string }>>();
  const rosterFor = async (initiativeId: string) => {
    if (rosterCache.has(initiativeId)) return rosterCache.get(initiativeId)!;
    const { data, error } = await sb.rpc("get_initiative_drive_roster", { p_initiative_id: initiativeId });
    if (error) throw new Error(`roster ${initiativeId}: ${error.message}`);
    const list = (data ?? []) as Array<{ person_id: string; member_id: string; email: string }>;
    rosterCache.set(initiativeId, list);
    return list;
  };

  const rows: any[] = [];   // persisted ledger rows (granted | failed only)
  const plan: any[] = [];   // dry_run: would-grant preview (not persisted)
  const errors: string[] = [];
  let granted = 0, present = 0, failed = 0, foldersScanned = 0, grantsAttempted = 0;
  let capped = false;

  for (const t of targets) {
    if (capped) break; // cap reached on a prior folder — skip the remaining Drive round-trips
    let roster: Array<{ person_id: string; member_id: string; email: string }>;
    try { roster = await rosterFor(t.initiative_id); }
    catch (e) { errors.push(String(e)); continue; }
    if (roster.length === 0) continue;

    let perms: DrivePermission[];
    try { perms = await listPermissions(t.drive_folder_id, accessToken); }
    catch (e) { errors.push(String(e)); continue; }
    foldersScanned++;
    const present_by_email = new Map<string, DrivePermission>();
    for (const p of perms) {
      if (p.type === "user" && p.emailAddress && !p.deleted) present_by_email.set(p.emailAddress.toLowerCase(), p);
    }

    // dedupe roster emails per folder (a member with a primary + alternate email → one grant per email)
    const seen = new Set<string>();
    for (const r of roster) {
      const email = r.email.toLowerCase();
      if (seen.has(email)) continue;
      seen.add(email);
      if (forceEmail && email !== forceEmail) continue; // force mode: only the named member
      const base = {
        initiative_id: t.initiative_id, drive_link_id: t.drive_link_id,
        drive_folder_id: t.drive_folder_id, drive_folder_url: t.drive_folder_url,
        grantee_person_id: r.person_id, grantee_member_id: r.member_id,
        permission_email: email, role: "writer", reconcile_source: source,
      };
      // Already in the folder ACL → no Drive call, and NOT persisted (a daily cron would otherwise
      // accrete an already_present row per member per run). Counted for observability only.
      // EXCEPTION: force_email POSTs an explicit direct writer even when present (upgrade inherited).
      if (!forceEmail && present_by_email.has(email)) { present++; continue; }
      if (dryRun) { plan.push({ ...base, status: "pending_grant" }); continue; }
      if (grantsAttempted >= MAX_GRANTS_PER_RUN) { capped = true; errors.push(`MAX_GRANTS_PER_RUN (${MAX_GRANTS_PER_RUN}) reached — remainder next run`); break; }
      grantsAttempted++;
      const g = await grantWriter(t.drive_folder_id, email, accessToken);
      if (g.ok) { rows.push({ ...base, status: "granted", permission_id: g.permissionId }); granted++; }
      else { rows.push({ ...base, status: "failed", permission_id: null, api_error: g.error }); failed++; }
    }
  }

  if (dryRun) {
    return new Response(JSON.stringify({
      success: true, dry_run: true, source, targets: targets.length, folders_scanned: foldersScanned,
      would_grant: plan.length, already_present: present, plan: plan.slice(0, 200), errors,
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  }

  // 4. idempotent ledger upsert
  const { data: up, error: upErr } = await sb.rpc("upsert_membership_drive_grants", { p_rows: rows });
  if (upErr) return new Response(JSON.stringify({ error: "upsert_error", detail: upErr.message, granted, failed }), { status: 500 });

  return new Response(JSON.stringify({
    success: true, source, targets: targets.length, folders_scanned: foldersScanned,
    granted, already_present: present, failed, ledger: up, errors,
    note: failed > 0 ? "some grants failed — if 403, the SA needs organizer/fileOrganizer on the folder (ADR-0094 G4.1)." : undefined,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
});
