/**
 * #1026 (Fatia A) — event-triggered Drive-teardown detection + positive clean-attestation.
 *
 * Behavior-additive over #209 / ADR-0107: an AFTER-UPDATE-OF-member_status trigger dispatches a TARGETED
 * Drive scan (pg_net) on offboard instead of waiting for the weekly cron 63, and every scanned member gets
 * a drive_teardown_scans ledger row (grants_found=0 == positive "verified no Drive access" attestation).
 * The approval model is UNCHANGED (still pending_revoke, manual GP approve) — NO auto-approve here.
 *
 * Guards:
 *   (A) Static (offline) — the four structural must-fixes that keep this AL-safe and non-destructive:
 *       1. the trigger dispatch is EXCEPTION-isolated (a vault/pg_net failure logs to admin_audit_log and
 *          RETURNs — it must NEVER roll back the offboard tx / LGPD Art.18 delete path);
 *       2. the trigger is column-scoped AFTER UPDATE OF member_status and only fires for alumni/inactive
 *          WITH offboarded_at set (single-fire + AL clause-2 safety);
 *       3. the ledger FK is ON DELETE SET NULL (preserve LGPD Art.16 scan evidence past member deletion);
 *       4. the targeted email overload keeps the Art.37 pii_access_log write and is service-role gated;
 *          the ledger table is fail-closed (RLS deny-all + REVOKE anon/authenticated); and the EF carries
 *          the { member_id } targeted branch + per-member ledger accumulator.
 *   (B) DB-aware (skipped without SUPABASE_URL + SERVICE_ROLE_KEY) — the targeted overload is wired and
 *       service-role-callable, returning [] for a nonexistent member (cardinality 0 ⇒ no pii_log write,
 *       so this probe is non-polluting).
 *
 * Live behavior (trigger single-fire via RAISE-rollback, targeted scan writing a clean-attestation row,
 * check_schema_invariants=0) was proven out-of-band and documented in the PR. Live==file is enforced by the
 * Phase C body-drift gate (these new functions are not on the p175 allowlist).
 *
 * Cross-ref: #1026, #209 / ADR-0107, #976 (_reacceptance_disengage second inactive producer), LL#588.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const EF_PATH = resolve(ROOT, 'supabase/functions/audit-drive-offboarding-access/index.ts');

function loadAllMigrations() {
  const files = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort();
  return files.map((f) => readFileSync(join(MIGRATIONS_DIR, f), 'utf8'));
}
const allSQL = loadAllMigrations().join('\n');
const efSrc = readFileSync(EF_PATH, 'utf8');

// Escape set includes backslash → fully sanitized RegExp (reused from 1021/963/991).
function latestFunctionBody(funcName) {
  const escaped = funcName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${escaped}\\s*\\([^)]*\\)[\\s\\S]*?AS\\s+\\$(\\w*)\\$([\\s\\S]*?)\\$\\1\\$`,
    'gi',
  );
  const matches = [...allSQL.matchAll(regex)];
  return matches.length > 0 ? matches[matches.length - 1][2] : null;
}

// ── Layer A1: the trigger dispatch is EXCEPTION-isolated (the BLOCKER must-fix) ──
test('#1026 static: trigger-fn dispatch is EXCEPTION-isolated — an offboard never rolls back on a Drive/vault failure', () => {
  const body = latestFunctionBody('_drive_teardown_enqueue_scan');
  assert.ok(body, '_drive_teardown_enqueue_scan must be defined in a migration');
  assert.match(body, /net\.http_post\(/, 'must dispatch the targeted scan via pg_net');
  assert.match(body, /EXCEPTION\s+WHEN\s+OTHERS\s+THEN/i, 'the dispatch must be wrapped in EXCEPTION WHEN OTHERS');
  assert.match(body, /admin_audit_log/, 'a dispatch failure must be logged (not propagated) to admin_audit_log');
  assert.match(body, /drive_teardown_trigger_dispatch_error/, 'the audit action names the dispatch error');
  // fire-and-forget targeted body: it posts the offboarded member id + the event source.
  assert.match(body, /'member_id',\s*NEW\.id/, 'must post the just-offboarded member id');
  assert.match(body, /'source',\s*'event'/, "must tag the scan source 'event'");
});

// ── Layer A2: the trigger is column-scoped + AL-safe + single-fire ──
test('#1026 static: trigger is column-scoped AFTER UPDATE OF member_status and only fires for offboards', () => {
  // Column-scope OF member_status avoids double-firing on the secondary operational_role UPDATE.
  assert.match(
    allSQL,
    /CREATE\s+TRIGGER\s+trg_drive_teardown_scan\s+AFTER\s+UPDATE\s+OF\s+member_status\s+ON\s+public\.members/i,
    'trigger must be AFTER UPDATE OF member_status ON public.members (column-scoped)',
  );
  // WHEN clause: status change into alumni/inactive AND offboarded_at set (AL clause-2 safety).
  assert.match(allSQL, /old\.member_status\s+IS\s+DISTINCT\s+FROM\s+new\.member_status/i, 'WHEN must require a real status change');
  assert.match(allSQL, /new\.member_status\s+IN\s*\(\s*'alumni'\s*,\s*'inactive'\s*\)/i, 'WHEN must restrict to alumni/inactive');
  assert.match(allSQL, /new\.offboarded_at\s+IS\s+NOT\s+NULL/i, 'WHEN must require offboarded_at IS NOT NULL (AL-safe; no scan for a non-offboard status flip)');
});

// ── Layer A3: the ledger preserves LGPD Art.16 evidence + is fail-closed ──
test('#1026 static: drive_teardown_scans ledger — FK ON DELETE SET NULL + RLS deny-all (fail-closed)', () => {
  assert.match(allSQL, /CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+public\.drive_teardown_scans/i, 'ledger table must be created');
  // ON DELETE SET NULL (not CASCADE — that would destroy Art.16 scan evidence; not RESTRICT — would block anonymization).
  assert.match(
    allSQL,
    /member_id\s+uuid\s+REFERENCES\s+public\.members\(id\)\s+ON\s+DELETE\s+SET\s+NULL/i,
    'member_id FK must be ON DELETE SET NULL to preserve scan evidence past member deletion',
  );
  assert.match(allSQL, /scan_source\s+text\s+NOT\s+NULL\s+CHECK\s*\(\s*scan_source\s+IN\s*\(\s*'event'\s*,\s*'weekly'\s*,\s*'manual'\s*\)/i, 'scan_source must be CHECK-constrained');
  assert.match(allSQL, /ALTER\s+TABLE\s+public\.drive_teardown_scans\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY/i, 'RLS must be enabled on the ledger');
  assert.match(allSQL, /CREATE\s+POLICY\s+drive_teardown_scans_deny_all[\s\S]*?USING\s*\(false\)\s*WITH\s+CHECK\s*\(false\)/i, 'ledger must be deny-all');
  assert.match(allSQL, /REVOKE\s+ALL\s+ON\s+public\.drive_teardown_scans\s+FROM\s+anon,\s*authenticated/i, 'ledger must revoke anon/authenticated');
});

// ── Layer A4: targeted overload keeps Art.37 pii_log + service-role gate; writer is service-role-only ──
test('#1026 static: targeted get_offboarded_member_emails(uuid) keeps pii_access_log + is service-role gated', () => {
  const body = latestFunctionBody('get_offboarded_member_emails');
  assert.ok(body, 'get_offboarded_member_emails overload must be defined');
  assert.match(body, /p_member_id/, 'the latest overload must filter by p_member_id (the targeted variant)');
  assert.match(body, /pii_access_log/, 'the targeted overload must keep the LGPD Art.37 pii_access_log write');
  assert.match(body, /current_caller_role\(\)\s+IS\s+DISTINCT\s+FROM\s+'service_role'/i, 'the overload must be service-role gated');
  assert.match(allSQL, /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.get_offboarded_member_emails\(uuid\)\s+FROM\s+PUBLIC,\s*anon,\s*authenticated/i, 'overload must be revoked from PUBLIC/anon/authenticated');
  assert.match(allSQL, /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.get_offboarded_member_emails\(uuid\)\s+TO\s+service_role/i, 'overload must grant EXECUTE to service_role');
});

test('#1026 static: record_drive_teardown_scan writer is service-role gated + fail-closed grants', () => {
  const body = latestFunctionBody('record_drive_teardown_scan');
  assert.ok(body, 'record_drive_teardown_scan must be defined');
  assert.match(body, /current_caller_role\(\)\s+IS\s+DISTINCT\s+FROM\s+'service_role'/i, 'writer must be service-role gated');
  assert.match(body, /INSERT\s+INTO\s+public\.drive_teardown_scans/i, 'writer must insert into the ledger');
  assert.match(allSQL, /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.record_drive_teardown_scan\([^)]*\)\s+FROM\s+PUBLIC,\s*anon,\s*authenticated/i, 'writer must be revoked from PUBLIC/anon/authenticated');
  assert.match(allSQL, /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.record_drive_teardown_scan\([^)]*\)\s+TO\s+service_role/i, 'writer must grant EXECUTE to service_role');
});

// ── Layer A5: the EF carries the targeted branch + per-member ledger accumulator ──
test('#1026 static: detection EF has the { member_id } targeted branch + per-member ledger emission', () => {
  assert.match(efSrc, /member_id\?:\s*string/, 'EF body type must accept member_id');
  assert.match(efSrc, /get_offboarded_member_emails",\s*\{\s*p_member_id:\s*body\.member_id\s*\}/, 'targeted branch must call the overload with p_member_id');
  assert.match(efSrc, /scanSource\s*=\s*targeted\s*\?\s*"event"\s*:\s*"weekly"/, 'scan_source must derive from the targeted flag');
  // per-member accumulator emitting ONE ledger row per member_id (a member with >1 email must not double-write).
  assert.match(efSrc, /record_drive_teardown_scan/, 'EF must write the attestation ledger row');
  assert.match(efSrc, /perMember\s*=\s*new\s+Map/, 'EF must aggregate counts per member_id (not per email)');
  assert.match(efSrc, /attested_clean/, 'EF response must surface the clean-attestation count');
});

// ── Layer B: DB-aware — targeted overload is wired + service-role-callable (non-polluting) ──
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#1026 runtime: targeted overload returns [] for a nonexistent member (wired, service-role, no pii pollution)', { skip: dbGated ? false : skipMsg }, async () => {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/get_offboarded_member_emails`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SUPABASE_KEY,
      Authorization: `Bearer ${SUPABASE_KEY}`,
    },
    // A random UUID: not an offboarded member ⇒ empty match set ⇒ cardinality 0 ⇒ no pii_access_log row.
    body: JSON.stringify({ p_member_id: '00000000-0000-0000-0000-000000000000' }),
  });
  assert.equal(res.status, 200, `overload must be callable by service_role (got ${res.status})`);
  const data = await res.json();
  assert.ok(Array.isArray(data), 'targeted overload must return a jsonb array');
  assert.equal(data.length, 0, 'a nonexistent member must resolve to an empty email set');
});

// ── Fatia C: panel reader RPC + frontend wiring (static) ──
test('#1026-C static: get_drive_teardown_overview is manage_member-gated + logs pii + fail-closed grants', () => {
  const body = latestFunctionBody('get_drive_teardown_overview');
  assert.ok(body, 'get_drive_teardown_overview must be defined in a migration');
  assert.match(body, /can_by_member\(v_caller_id, 'manage_member'\)/, 'the panel reader must require manage_member');
  assert.match(body, /log_pii_access_batch\(/, 'the panel reader must log the member-name PII read (Art.37)');
  assert.match(allSQL, /REVOKE ALL ON FUNCTION public\.get_drive_teardown_overview\(\) FROM PUBLIC, anon/, 'reader must be revoked from PUBLIC + anon');
  assert.match(allSQL, /GRANT EXECUTE ON FUNCTION public\.get_drive_teardown_overview\(\) TO authenticated, service_role/, 'reader must grant EXECUTE to authenticated + service_role');
});

test('#1026-C static: panel page + island + per-locale redirects exist and reuse the existing RPCs', () => {
  const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
  const page = read('src/pages/admin/members/drive-teardown.astro');
  assert.match(page, /DriveTeardownIsland/, 'page must mount the DriveTeardownIsland');
  assert.match(page, /buildPageI18n\(\['driveTeardown', 'common'\]/, 'page must load the driveTeardown i18n bundle');
  const island = read('src/components/admin/members/DriveTeardownIsland.tsx');
  assert.match(island, /get_drive_teardown_overview/, 'island must call the new overview reader');
  assert.match(island, /admin_list_drive_revocation_audit/, 'drill-down reuses the existing per-grant reader (no redundant RPC)');
  assert.match(island, /bulk_approve_drive_revocations/, 'approve action reuses the existing manual-approve RPC (Fatia A model unchanged)');
  // per-locale redirect stubs (i18n rule 4/5)
  assert.ok(existsSync(resolve(ROOT, 'src/pages/en/admin/members/drive-teardown.astro')), 'en redirect stub must exist');
  assert.ok(existsSync(resolve(ROOT, 'src/pages/es/admin/members/drive-teardown.astro')), 'es redirect stub must exist');
});

test('#1026-C static: driveTeardown i18n namespace has 3-dict parity', () => {
  const count = (p) => (readFileSync(resolve(ROOT, p), 'utf8').match(/'driveTeardown\./g) || []).length;
  const pt = count('src/i18n/pt-BR.ts');
  const en = count('src/i18n/en-US.ts');
  const es = count('src/i18n/es-LATAM.ts');
  assert.ok(pt > 0, 'pt-BR must define the driveTeardown namespace');
  assert.equal(en, pt, 'en-US driveTeardown key count must equal pt-BR (3-dict parity)');
  assert.equal(es, pt, 'es-LATAM driveTeardown key count must equal pt-BR (3-dict parity)');
});
