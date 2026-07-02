/**
 * #1039 (Fatia B do #1026) — alumni-only auto-approve/auto-revoke de Drive no offboard.
 * ADR-0107 Amendment 1 · council Tier-3 2026-07-02 (4× APPROVE_WITH_CONDITIONS, 0 blockers) ·
 * decision record docs/council/decisions/2026-07-02-1039-drive-auto-revoke-alumni-only.md.
 *
 * Guards (each pins a council must-fix or a load-bearing policy line):
 *   (A) Static (offline):
 *     1. provenance schema — approval_mode ('manual'|'auto') + skip_reason enum + CHECK
 *        "skipped requires skip_reason" (legal COND-2 / data-arch MF-4);
 *     2. auto_approve_alumni_drive_revocations — service-role gate, NULL-safe FAIL-CLOSED
 *        kill-switch (missing site_config key = disabled; security must-fix), ALUMNI-ONLY filter
 *        at UPDATE time, approved_by stays NULL, self-contained authorization record (audit_ids),
 *        fail-closed GRANTs;
 *     3. site_config seed is 'false'::jsonb and the RPC compares 'true'::jsonb — SAME jsonb
 *        subtype on both sides (security must-fix: a subtype mismatch bricks the switch);
 *     4. admin_reactivate_member cancels open queue rows (→ skipped/member_reactivated) BEFORE
 *        the members UPDATE clears offboarded_at (data-arch MF-3: AL clause-2 ordering);
 *     5. invariant AL amendment — clause 1 auto carve-out, clause 1b provenance coherence,
 *        clause 1c skipped⇒skip_reason, and the rebuild is FULL (AK + AN truncation guards);
 *     6. detection EF calls the auto RPC post-upsert, non-fatally, in both branches;
 *     7. GP surfaces expose provenance (admin_list: approval_mode + skip_reason; overview:
 *        auto_approved metric; island: skipped pill + auto badge).
 *   (B) DB-aware (skipped without SUPABASE_URL + SERVICE_ROLE_KEY) — shape-only, NON-polluting,
 *       and deliberately independent of the live kill-switch state (a live-state assertion would
 *       break CI the day the PM flips the switch — pt38 live-data≠diff lesson):
 *     1. service-role call returns 200 with a numeric approved_count (switch off ⇒ pure no-op;
 *        switch on ⇒ 0 pending alumni rows is still a no-op — never mutates in CI);
 *     2. anon-key call is rejected (fail-closed GRANT discipline);
 *     3. check_schema_invariants() → AL violation_count === 0 against the AMENDED live body.
 *
 * Cross-ref: #1039, #1026 (Fatias A/C: 1026-*.test.mjs), #209/ADR-0107, ADR-0071 Amd 3-D, ADR-0116.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const MIG_1039 = '20260805000319_1039_drive_teardown_fatia_b_auto_revoke.sql';
const EF_PATH = resolve(ROOT, 'supabase/functions/audit-drive-offboarding-access/index.ts');

function loadAllMigrations() {
  const files = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort();
  return files.map((f) => readFileSync(join(MIGRATIONS_DIR, f), 'utf8'));
}
const allSQL = loadAllMigrations().join('\n');
const mig = readFileSync(join(MIGRATIONS_DIR, MIG_1039), 'utf8');
const efSrc = readFileSync(EF_PATH, 'utf8');

// Escape set includes backslash → fully sanitized RegExp (reused from 1021/1026/963/991).
function latestFunctionBody(funcName) {
  const escaped = funcName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${escaped}\\s*\\([^)]*\\)[\\s\\S]*?AS\\s+\\$(\\w*)\\$([\\s\\S]*?)\\$\\1\\$`,
    'gi',
  );
  const matches = [...allSQL.matchAll(regex)];
  return matches.length > 0 ? matches[matches.length - 1][2] : null;
}

// ── A1: provenance schema ──
test('#1039 static: approval_mode + skip_reason columns with enum CHECKs + skipped-requires-reason', () => {
  assert.match(mig, /ADD\s+COLUMN\s+approval_mode\s+text\s+NOT\s+NULL\s+DEFAULT\s+'manual'/i, 'approval_mode must default manual (all pre-existing rows were human-approved)');
  assert.match(mig, /CHECK\s*\(approval_mode\s+IN\s*\('manual','auto'\)\)/i, 'approval_mode must be enum-CHECKed');
  assert.match(mig, /ADD\s+COLUMN\s+skip_reason\s+text/i, 'skip_reason column must exist');
  assert.match(mig, /CHECK\s*\(skip_reason\s+IN\s*\('owner_permission','member_reactivated'\)\)/i, 'skip_reason must be enum-CHECKed (structural Art.37 evidence, council COND-2)');
  assert.match(mig, /ADD\s+CONSTRAINT\s+drive_offb_audit_skipped_requires_reason\s+CHECK\s*\(status\s*<>\s*'skipped'\s+OR\s+skip_reason\s+IS\s+NOT\s+NULL\)/i, 'a skipped row without a reason must be impossible (data-arch MF-4)');
});

// ── A2: the auto-approve RPC ──
test('#1039 static: auto_approve RPC — service-role gate + NULL-safe fail-closed kill-switch + alumni-only', () => {
  const body = latestFunctionBody('auto_approve_alumni_drive_revocations');
  assert.ok(body, 'auto_approve_alumni_drive_revocations must be defined in a migration');
  assert.match(body, /current_caller_role\(\)\s+IS\s+DISTINCT\s+FROM\s+'service_role'/i, 'must be service-role gated (NULL-safe pattern)');
  // NULL-safe FAIL-CLOSED: a deleted/missing site_config row must read as DISABLED (security must-fix).
  assert.match(body, /coalesce\(v_enabled,\s*'false'::jsonb\)\s+IS\s+DISTINCT\s+FROM\s+'true'::jsonb/i, 'kill-switch check must be COALESCE(…,false) IS DISTINCT FROM true (fail-closed)');
  // Alumni-only, evaluated AT UPDATE TIME (closes the detect→approve race). inactive must never match.
  assert.match(body, /m\.member_status\s*=\s*'alumni'/, 'auto-approve must filter member_status=alumni ONLY');
  assert.match(body, /m\.offboarded_at\s+IS\s+NOT\s+NULL/, 'auto-approve must require offboarded_at set');
  assert.doesNotMatch(body, /member_status\s+IN\s*\(\s*'alumni'\s*,\s*'inactive'\s*\)/i, 'inactive must NOT be auto-approvable (reversible, ADR-0071 Amd 3-D)');
  assert.match(body, /d\.status\s*=\s*'pending_revoke'/, 'must flip only pending_revoke rows');
  assert.match(body, /approval_mode\s*=\s*'auto'/, 'must stamp approval_mode=auto (the provenance)');
  assert.doesNotMatch(body, /approved_by\s*=/, 'must NOT write approved_by (stays NULL — approval_mode IS the provenance)');
  // Self-contained authorization record (security rec): exact audit_ids in the audit entry.
  assert.match(body, /drive_revocation_auto_approved/, 'must write the authorization admin_audit_log entry');
  assert.match(body, /'audit_ids',\s*to_jsonb\(v_ids\)/, 'the authorization record must carry the exact audit_ids (O(1) forensics)');
  // Fail-closed grants (mirrors get_offboarded_member_emails(uuid) precedent).
  assert.match(mig, /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.auto_approve_alumni_drive_revocations\(uuid,\s*text\)\s+FROM\s+PUBLIC,\s*anon,\s*authenticated/i, 'must be revoked from PUBLIC/anon/authenticated');
  assert.match(mig, /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.auto_approve_alumni_drive_revocations\(uuid,\s*text\)\s+TO\s+service_role/i, 'must grant EXECUTE to service_role only');
});

// ── A3: jsonb literal consistency (security must-fix: subtype mismatch bricks the switch) ──
test('#1039 static: kill-switch seed and comparison use the SAME jsonb boolean subtype', () => {
  assert.match(mig, /INSERT\s+INTO\s+public\.site_config\s*\(key,\s*value\)\s*\n?\s*VALUES\s*\('drive_auto_revoke_enabled',\s*'false'::jsonb\)/i, "seed must be 'false'::jsonb (boolean subtype)");
  assert.match(mig, /ON\s+CONFLICT\s*\(key\)\s+DO\s+NOTHING/i, 'seed must be idempotent (never clobber a PM flip on re-apply)');
  // the RPC compares 'true'::jsonb — same boolean subtype (asserted in A2); no string-subtype literal anywhere:
  assert.doesNotMatch(mig, /'"(?:true|false)"'::jsonb/, 'no JSON-string subtype literal may appear (boolean form only)');
});

// ── A4: reactivation queue-clear, ordered BEFORE the members UPDATE (data-arch MF-3) ──
test('#1039 static: admin_reactivate_member cancels open queue rows BEFORE clearing offboarded_at', () => {
  const body = latestFunctionBody('admin_reactivate_member');
  assert.ok(body, 'admin_reactivate_member must be defined');
  assert.match(body, /UPDATE\s+public\.drive_offboarding_audit/i, 'reactivation must touch the revocation queue (AL clause-2 mechanism)');
  assert.match(body, /skip_reason\s*=\s*'member_reactivated'/, 'cancelled rows must carry the structural skip_reason');
  assert.match(body, /status\s+IN\s*\('pending_revoke','approved'\)/, 'must cancel BOTH open states (approved is the drain-dangerous one)');
  // Ordering: the queue-clear must appear BEFORE the members UPDATE that clears offboarded_at.
  const clearIdx = body.indexOf("skip_reason = 'member_reactivated'");
  const memberUpdateIdx = body.indexOf('offboarded_at = NULL');
  assert.ok(clearIdx > -1 && memberUpdateIdx > -1, 'both blocks must exist');
  assert.ok(clearIdx < memberUpdateIdx, 'queue-clear must run BEFORE offboarded_at is cleared (same tx; AL clause-2 ordering — MF-3)');
});

// ── A5: invariant AL amendment + full-rebuild truncation guards ──
test('#1039 static: AL amended (auto carve-out + provenance coherence + skipped reason) in a FULL rebuild', () => {
  assert.match(mig, /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.check_schema_invariants\(\)/i, 'migration must carry the full check_schema_invariants rebuild');
  const body = latestFunctionBody('check_schema_invariants');
  assert.ok(body, 'check_schema_invariants must be found');
  // clause 1: revoked needs revoked_at AND (approved_by OR auto provenance)
  assert.match(body, /status\s*=\s*'revoked'\s+AND\s+\(revoked_at\s+IS\s+NULL\s*\n?\s*OR\s+\(approved_by\s+IS\s+NULL\s+AND\s+approval_mode\s+IS\s+DISTINCT\s+FROM\s+'auto'\)\)/i, 'clause 1 must allow NULL approved_by only under approval_mode=auto');
  // clause 1b: an auto row may never carry a human approver nor sit pending
  assert.match(body, /approval_mode\s*=\s*'auto'\s+AND\s+\(approved_by\s+IS\s+NOT\s+NULL\s+OR\s+status\s*=\s*'pending_revoke'\)/i, 'clause 1b provenance coherence must be present');
  // clause 1c: skipped requires skip_reason
  assert.match(body, /status\s*=\s*'skipped'\s+AND\s+skip_reason\s+IS\s+NULL/i, 'clause 1c skipped⇒skip_reason must be present');
  // FULL rebuild truncation guards (the 209-test pattern): first and last sibling invariants still present.
  assert.ok(body.includes('AK_voice_biometric_consent_enforcement'), 'AK must survive the rebuild (truncation guard)');
  assert.ok(body.includes('AM_drive_curation_grant_terminal_consistency'), 'AM must survive the rebuild');
  assert.ok(body.includes('AN_no_dynamic_remission_cooperation'), 'AN (last invariant) must survive the rebuild');
});

// ── A6: detection EF calls the auto RPC post-upsert, non-fatally ──
test('#1039 static: detection EF wires auto_approve post-upsert (targeted + weekly), non-fatal', () => {
  assert.match(efSrc, /auto_approve_alumni_drive_revocations/, 'EF must call the auto-approve RPC');
  assert.match(efSrc, /p_member_id:\s*targeted\s*\?\s*body\.member_id\s*:\s*null/, 'targeted branch passes member_id; weekly passes null (deliberate catch-up)');
  assert.match(efSrc, /p_source:\s*scanSource/, 'must tag the source (event|weekly) for the authorization record');
  assert.match(efSrc, /errors\.push\(`auto_approve failed/, 'auto-approve failure must be non-fatal (manual lane unaffected)');
  const upsertIdx = efSrc.indexOf('upsert_drive_revocation_candidates');
  const autoIdx = efSrc.indexOf('auto_approve_alumni_drive_revocations');
  assert.ok(upsertIdx > -1 && autoIdx > upsertIdx, 'auto-approve must run AFTER the upsert');
});

// ── A7: GP surfaces expose provenance ──
test('#1039 static: admin_list + overview + island expose approval_mode / skipped provenance', () => {
  const list = latestFunctionBody('admin_list_drive_revocation_audit');
  assert.match(list, /'approval_mode',\s*approval_mode/, 'admin_list must expose approval_mode');
  assert.match(list, /'skip_reason',\s*skip_reason/, 'admin_list must expose skip_reason');
  const ov = latestFunctionBody('get_drive_teardown_overview');
  assert.match(ov, /status\s*=\s*'approved'\s+AND\s+approval_mode\s*=\s*'auto'/, 'overview must count in-flight autos');
  assert.match(ov, /'auto_approved',/, 'overview must expose the auto_approved metric (per-member + summary)');
  const island = readFileSync(resolve(ROOT, 'src/components/admin/members/DriveTeardownIsland.tsx'), 'utf8');
  assert.match(island, /driveTeardown\.stSkipped/, 'island must render the skipped pill');
  assert.match(island, /driveTeardown\.autoShort/, 'island must render the auto provenance badge');
  assert.match(island, /driveTeardown\.autoInFlight/, 'island must surface the in-flight auto note');
});

// ── B: DB-aware (shape-only, non-polluting, kill-switch-state independent) ──
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const SUPABASE_ANON = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#1039 runtime: auto RPC is service-role callable and returns a numeric approved_count (state-independent)', { skip: dbGated ? false : skipMsg }, async () => {
  // Non-polluting in every live state: switch off ⇒ pure no-op; switch on ⇒ a nonexistent member id
  // matches zero rows ⇒ still a no-op. Deliberately NO assertion on `enabled` (live kill-switch state).
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/auto_approve_alumni_drive_revocations`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` },
    body: JSON.stringify({ p_member_id: '00000000-0000-0000-0000-000000000000', p_source: 'contract-test' }),
  });
  assert.equal(res.status, 200, `service_role must be able to call the RPC (got ${res.status})`);
  const data = await res.json();
  assert.equal(typeof data.approved_count, 'number', 'response must carry a numeric approved_count');
  assert.equal(data.approved_count, 0, 'a nonexistent member must flip zero rows');
});

test('#1039 runtime: auto RPC rejects a non-service-role caller (fail-closed grants)', { skip: dbGated && SUPABASE_ANON ? false : 'Skipped: SUPABASE_URL + SERVICE_ROLE + ANON keys required' }, async () => {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/auto_approve_alumni_drive_revocations`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: SUPABASE_ANON, Authorization: `Bearer ${SUPABASE_ANON}` },
    body: JSON.stringify({}),
  });
  assert.notEqual(res.status, 200, 'anon must NOT be able to invoke the auto-approve RPC');
});

test('#1039 runtime: invariant AL holds (violation_count 0) against the amended live body', { skip: dbGated ? false : skipMsg }, async () => {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/check_schema_invariants`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` },
    body: JSON.stringify({}),
  });
  assert.equal(res.status, 200, `check_schema_invariants must be callable (got ${res.status})`);
  const rows = await res.json();
  const al = rows.find((r) => r.invariant_name === 'AL_drive_revocation_terminal_consistency');
  assert.ok(al, 'AL must exist in the live invariant set');
  assert.equal(al.violation_count, 0, `AL must have zero violations (sample: ${JSON.stringify(al.sample_ids)})`);
});
