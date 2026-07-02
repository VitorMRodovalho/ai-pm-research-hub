/**
 * EF: audit-drive-offboarding-access — #209 / ADR-0107 (detection half).
 *
 * Weekly cron cross-references offboarded members (member_status inactive/alumni,
 * offboarded_at set) against Google Drive permissions, and queues pending revocations in
 * drive_offboarding_audit (idempotent via upsert_drive_revocation_candidates), then notifies GP.
 * READ-ONLY against Drive (drive.readonly scope). The actual DELETE lives in
 * revoke-drive-permission and is gated on the SA's Workspace role (PM task, ADR-0094 G4.1).
 *
 * SCAN STRATEGY (scales): rather than walking the whole folder tree and calling permissions.list
 * on every file (O(files) — blows the EF wall-clock on a large tree), we run ONE files.list per
 * offboarded email — q="'<email>' in writers or '<email>' in readers" over the SA's whole corpus
 * (corpora=allDrives) — then permissions.list ONLY on the matched files (small). Scope = everything
 * the institutional SA can see, which IS the Núcleo workspace (the SA is added as Editor to the
 * linked folders + the shared drive). This is a superset of "parent folder + subfolders" and is the
 * correct LGPD scope: any offboarded access the SA can manage. The dry_run probes the parent folder
 * to validate emailAddress readability under the SA scope/role before the live scan is trusted.
 *
 * Auth: service-role caller only (cron via pg_net, or MCP) — isServiceRoleToken (#738/#850;
 *   never a literal token compare). SA creds: Vault google_drive_service_account_json.
 *   Absent → 503 not_configured (fail-safe).
 *
 * #1026 (Fatia A): a targeted { member_id } body runs the scan for ONE just-offboarded member
 *   (fired event-triggered by trg_drive_teardown_scan on members), instead of the weekly cohort sweep.
 *   Every scanned member also gets a drive_teardown_scans ledger row (grants_found=0 == positive
 *   "verified no Drive access" attestation, LL#588). Approval model UNCHANGED (still pending_revoke,
 *   manual GP approve). cron 63 stays the weekly reconciliation backstop.
 *
 * Body: { dry_run?: boolean, max_files?: number, source?: string, member_id?: string }
 */
import { createClient } from "jsr:@supabase/supabase-js@2";
import { isServiceRoleToken } from "../_shared/service-auth.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const VAULT_KEY = "google_drive_service_account_json";
const PARENT_FOLDER_ID = "1PFLzCa8dwjFNhc_y3TPOnkN9O7jfbqnA";
const SHARED_DRIVE_ID = "0ABRgwbztNXgDUk9PVA";
const READONLY_SCOPE = "https://www.googleapis.com/auth/drive.readonly";
const FOLDER_MIME = "application/vnd.google-apps.folder";
const MAX_FILES_PER_EMAIL = 1000;

interface DrivePermission { id: string; type: string; role: string; emailAddress?: string; deleted?: boolean; }
interface DriveItem { id: string; name: string; mimeType: string; webViewLink?: string; driveId?: string; parents?: string[]; permissions?: DrivePermission[]; }

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

const DRIVE_LIST_BASE = (): URL => {
  const url = new URL("https://www.googleapis.com/drive/v3/files");
  url.searchParams.set("supportsAllDrives", "true");
  url.searchParams.set("includeItemsFromAllDrives", "true");
  url.searchParams.set("corpora", "allDrives");
  url.searchParams.set("pageSize", "1000");
  url.searchParams.set("fields", "nextPageToken, files(id,name,mimeType,webViewLink,driveId)");
  return url;
};

/** Files where `email` has writer/reader access, across the SA's whole corpus (My Drive + shared drives). */
async function findFilesSharedWith(email: string, accessToken: string): Promise<DriveItem[]> {
  const out: DriveItem[] = [];
  let pageToken: string | undefined;
  do {
    const url = DRIVE_LIST_BASE();
    // Inline permissions collapse the per-file permissions.list into the same call (Google returns up
    // to 100 inline; >100 falls back to a targeted permissions.list in the caller). This is what makes
    // the scan fit the EF wall-clock in a heavily-shared workspace.
    url.searchParams.set("fields", "nextPageToken, files(id,name,webViewLink,driveId,parents,permissions(id,emailAddress,role,type,deleted))");
    // FOLDERS only: in a heavily-shared workspace, granting a member a folder makes every descendant
    // FILE match `'email' in writers` via inheritance (the 10k-row explosion). Folder-level grants are
    // where access is actually managed and are the deletable revoke targets; querying folders bounds the
    // fetch. Direct grants on individual non-folder files are a documented v2 follow-up (ADR-0107).
    url.searchParams.set("q", `trashed = false and mimeType = 'application/vnd.google-apps.folder' and ('${email}' in writers or '${email}' in readers)`);
    if (pageToken) url.searchParams.set("pageToken", pageToken);
    const res = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } });
    if (!res.ok) throw new Error(`files.list (folders shared-with ${email}) failed: ${res.status} ${await res.text()}`);
    const json = await res.json();
    for (const f of (json.files ?? [])) { out.push(f); if (out.length >= MAX_FILES_PER_EMAIL) return out; }
    pageToken = json.nextPageToken;
  } while (pageToken);
  return out;
}

/** Immediate children of a folder (used by dry_run only). */
async function listChildren(folderId: string, accessToken: string): Promise<DriveItem[]> {
  const url = DRIVE_LIST_BASE();
  url.searchParams.set("q", `'${folderId}' in parents and trashed = false`);
  const res = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } });
  if (!res.ok) throw new Error(`files.list (children ${folderId}) failed: ${res.status} ${await res.text()}`);
  return (await res.json()).files ?? [];
}

/** All permissions on a file/folder, fully paginated. */
async function listPermissions(fileId: string, accessToken: string): Promise<DrivePermission[]> {
  const out: DrivePermission[] = [];
  let pageToken: string | undefined;
  do {
    const url = new URL(`https://www.googleapis.com/drive/v3/files/${fileId}/permissions`);
    url.searchParams.set("fields", "nextPageToken, permissions(id,type,role,emailAddress,deleted,permissionDetails(inherited))");
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

  let body: { dry_run?: boolean; max_files?: number; source?: string; member_id?: string } = {};
  try { body = await req.json(); } catch { /* empty body ok */ }
  const dryRun = body.dry_run === true;

  const saResult = await getServiceAccountKey();
  if (!saResult.available) {
    return new Response(JSON.stringify({
      error: "drive_integration_not_configured",
      detail: saResult.error,
      next_steps: "PM: seed Vault key 'google_drive_service_account_json'. See docs/operations/DRIVE_OFFBOARDING_CASCADE.md",
    }), { status: 503 });
  }

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const errors: string[] = [];
  let accessToken: string;
  try { accessToken = await getAccessToken(saResult.key, READONLY_SCOPE); }
  catch (e) { return new Response(JSON.stringify({ error: "drive_auth_error", detail: String(e) }), { status: 502 }); }

  // ---- DRY RUN: probe permissions.list on the parent folder's children; no DB writes. ----
  if (dryRun) {
    try {
      const top = (await listChildren(PARENT_FOLDER_ID, accessToken)).slice(0, body.max_files ?? 3);
      const probes = [];
      for (const it of top) {
        try {
          const perms = await listPermissions(it.id, accessToken);
          probes.push({
            file_id: it.id, name: it.name, is_folder: it.mimeType === FOLDER_MIME,
            permission_count: perms.length,
            any_email_present: perms.some(p => !!p.emailAddress),
            sample: perms.slice(0, 5).map(p => ({ id: p.id, type: p.type, role: p.role, has_email: !!p.emailAddress })),
          });
        } catch (e) { probes.push({ file_id: it.id, error: String(e) }); }
      }
      return new Response(JSON.stringify({
        success: true, dry_run: true,
        parent_children_sampled: top.length, probes,
        note: "If any_email_present is true across user-type permissions, the live scan can match offboarded emails under the current SA scope/role. If false or 403, detection also depends on the Workspace role elevation (ADR-0107).",
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    } catch (e) {
      return new Response(JSON.stringify({ error: "drive_api_error", detail: String(e), dry_run: true }), { status: 502 });
    }
  }

  // ---- LIVE SCAN ----
  // 1. offboarded email → member map (SECDEF RPC; logs the PII read system-side).
  //    #1026: a targeted { member_id } event scan resolves just that member's email set; otherwise the
  //    weekly sweep resolves the whole offboarded cohort. cron 63 stays the reconciliation backstop.
  const targeted = typeof body.member_id === "string" && body.member_id.length > 0;
  const scanSource = targeted ? "event" : "weekly";
  const { data: emailData, error: emailErr } = targeted
    ? await sb.rpc("get_offboarded_member_emails", { p_member_id: body.member_id })
    : await sb.rpc("get_offboarded_member_emails");
  if (emailErr) return new Response(JSON.stringify({ error: "rpc_error", detail: emailErr.message }), { status: 500 });
  const emailToMember = new Map<string, string>();
  for (const r of (emailData ?? [])) emailToMember.set(String(r.email).toLowerCase(), r.member_id);
  if (emailToMember.size === 0) {
    return new Response(JSON.stringify({ success: true, targeted, member_id: body.member_id ?? null,
      emails_scanned: 0, grants_found: 0, inserted: 0, refreshed: 0,
      note: targeted ? "member not offboarded or has no emails — nothing to scan" : "no offboarded members with emails" }),
      { status: 200, headers: { "Content-Type": "application/json" } });
  }

  // #1026 per-member scan ledger accumulator: one drive_teardown_scans row per member scanned, so a member
  // with 0 grants (present in emailToMember, contributes nothing to candidates[]) still yields the positive
  // clean attestation. Keyed by member_id, so a member with >1 email is aggregated into a single row.
  const perMember = new Map<string, { emails_scanned: number; grants_found: number; deletable: number; exceptions: number }>();
  const accFor = (mid: string) => {
    let m = perMember.get(mid);
    if (!m) { m = { emails_scanned: 0, grants_found: 0, deletable: 0, exceptions: 0 }; perMember.set(mid, m); }
    return m;
  };

  // 2. Per offboarded email: find the files they can access, then read those files' permissions.
  const candidates: any[] = [];
  let emailsScanned = 0;
  let foldersConsidered = 0;
  for (const [email, memberId] of emailToMember) {
    const acc = accFor(memberId); // ensure every scanned member yields a ledger row (even 0-grant = clean)
    if (email.includes("'") || email.includes("\\")) { errors.push(`skipped unsafe email token`); continue; }
    let folders: DriveItem[];
    try { folders = await findFilesSharedWith(email, accessToken); }
    catch (e) { errors.push(String(e)); continue; }
    emailsScanned++;
    acc.emails_scanned++;
    // A matched folder is a DIRECT grant iff none of its parents is ALSO matched for this email — i.e.
    // it is the top of a shared subtree. Subfolders inheriting the grant have a matched parent and are
    // skipped. This works for My Drive (where permissionDetails.inherited is not exposed) AND shared
    // drives, in-memory, with no extra API calls — collapsing the inherited-cascade explosion.
    const matchedIds = new Set(folders.map(f => f.id));
    for (const f of folders) {
      if ((f.parents ?? []).some(pid => matchedIds.has(pid))) continue; // inherited from a matched ancestor
      foldersConsidered++;
      let p = (f.permissions ?? []).find(pp => pp.emailAddress?.toLowerCase() === email && !pp.deleted);
      if (!p) {
        // inline permissions truncated (folder has >100) → targeted fallback for this one item
        try { p = (await listPermissions(f.id, accessToken)).find(pp => pp.emailAddress?.toLowerCase() === email && !pp.deleted); }
        catch (e) { errors.push(String(e)); continue; }
      }
      if (!p) continue;
      acc.grants_found++; // a real (non-inherited) folder grant this member holds
      if (p.role === "owner") { acc.exceptions++; continue; } // undeletable owner perm; out of #209 scope (ADR-0107)
      acc.deletable++;
      candidates.push({
        member_id: memberId,
        drive_file_id: f.id,
        drive_file_name: f.name,
        drive_file_url: f.webViewLink ?? null,
        is_shared_drive: !!f.driveId,
        shared_drive_id: f.driveId ?? null,
        permission_id: p.id,
        permission_email: p.emailAddress,
        permission_role: p.role,
        permission_type: p.type,
      });
    }
  }

  // 3. Idempotent upsert + GP notification + admin_audit_log (server-side, SECDEF).
  const { data: upData, error: upErr } = await sb.rpc("upsert_drive_revocation_candidates", { p_rows: candidates });
  if (upErr) return new Response(JSON.stringify({ error: "upsert_error", detail: upErr.message, grants_found: candidates.length }), { status: 500 });

  // 4. #1026 positive attestation — one drive_teardown_scans row per member scanned (grants_found=0 == clean).
  let attestedClean = 0;
  for (const [memberId, m] of perMember) {
    if (m.grants_found === 0) attestedClean++;
    const { error: recErr } = await sb.rpc("record_drive_teardown_scan", {
      p_member_id: memberId,
      p_scan_source: scanSource,
      p_emails_scanned: m.emails_scanned,
      p_grants_found: m.grants_found,
      p_deletable_queued: m.deletable,
      p_exceptions_found: m.exceptions,
      p_notes: null,
    });
    if (recErr) errors.push(`ledger write failed for ${memberId}: ${recErr.message}`);
  }

  return new Response(JSON.stringify({
    success: true,
    targeted,
    member_id: body.member_id ?? null,
    scan_source: scanSource,
    members_scanned: perMember.size,
    attested_clean: attestedClean,
    emails_scanned: emailsScanned,
    direct_folder_grants_considered: foldersConsidered,
    grants_found: candidates.length,
    inserted: upData?.inserted ?? 0,
    refreshed: upData?.refreshed ?? 0,
    errors: errors.slice(0, 20),
    error_count: errors.length,
  }), { status: 200, headers: { "Content-Type": "application/json" } });
});
