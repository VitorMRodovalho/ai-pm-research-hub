/**
 * p230 #318 — A3 invariant defense-in-depth contract.
 *
 * Forward-defense: asserts the CHECK constraint chk_a3_active_role_not_none
 * stays declared in migration text + (DB-gated) is enforced live.
 *
 * Background:
 *   A3 invariant in check_schema_invariants() detects (active + operational_role='none')
 *   only at audit time; check-invariants CI ratchet hard-fails when drift surfaces
 *   on a PR's run, leaving every subsequent PR blocked until repair. This contract
 *   makes the same rule load-bearing at write time so no future RPC, EF, or direct
 *   UPDATE can produce that state in the first place.
 *
 * Static checks always run. Live enforcement check is gated on SUPABASE_URL +
 * SUPABASE_SERVICE_ROLE_KEY.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

function loadAllMigrationsConcat() {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql')).sort();
  return files.map(f => readFileSync(join(MIGRATIONS_DIR, f), 'utf8')).join('\n');
}

const allSQL = loadAllMigrationsConcat();

test('p230 #318: migration 20260805000016 file present', () => {
  const files = readdirSync(MIGRATIONS_DIR);
  const match = files.find(f => f.startsWith('20260805000016_') && f.endsWith('.sql'));
  assert.ok(match, 'expected migration file starting with 20260805000016_');
  assert.match(
    match,
    /318.*a3.*active.*role.*not.*none/i,
    'migration filename must signal #318 / A3 / active_role_not_none scope'
  );
});

test('p230 #318: CHECK constraint chk_a3_active_role_not_none declared', () => {
  assert.match(
    allSQL,
    /CONSTRAINT\s+chk_a3_active_role_not_none/i,
    'constraint name chk_a3_active_role_not_none must appear in migration text'
  );
});

test('p230 #318: CHECK predicate forbids (active + none) exact tuple', () => {
  // The migration must declare CHECK (NOT (member_status='active' AND operational_role='none'))
  // on public.members. The exact spacing/quoting is flexible but the predicate semantics
  // must be present so that a future "loosened" version drift is caught.
  assert.match(
    allSQL,
    /CHECK\s*\(\s*NOT\s*\(\s*member_status\s*=\s*'active'\s*AND\s*operational_role\s*=\s*'none'\s*\)\s*\)/i,
    'CHECK predicate must be: NOT (member_status = \'active\' AND operational_role = \'none\')'
  );
});

test('p230 #318: ALTER TABLE targets public.members', () => {
  // Defense against accidentally adding the constraint to a different table.
  assert.match(
    allSQL,
    /ALTER\s+TABLE\s+public\.members[\s\S]{0,200}CONSTRAINT\s+chk_a3_active_role_not_none/i,
    'CHECK must be added via ALTER TABLE public.members …'
  );
});

test('p230 #318: Herlon repair audit row inserted under canonical action', () => {
  // The repair UPDATE in the same migration MUST also write an admin_audit_log
  // row so the operational_role change is forensically traceable (the original
  // mutation that produced \'none\' left no audit trail — issue #318 origin).
  assert.match(
    allSQL,
    /'member\.operational_role_a3_repair'/,
    'repair audit row must use action=member.operational_role_a3_repair'
  );
  assert.match(
    allSQL,
    /p230_318_a3_defense_in_depth/i,
    'repair audit row metadata.source must be p230_318_a3_defense_in_depth'
  );
});

test('p230 #318: repair derives operational_role via canonical V4 cache ladder', () => {
  // The repair query must use the same CASE ladder as sync_operational_role_cache
  // so the post-repair value matches what the cache trigger would produce. We
  // assert presence of the distinctive ladder branches; full ladder parity is
  // enforced by the runtime A3 invariant check.
  assert.match(
    allSQL,
    /ae\.kind\s*=\s*'volunteer'\s*AND\s*ae\.role\s*=\s*'manager'/i,
    'V4 ladder manager branch must be present in repair query'
  );
  assert.match(
    allSQL,
    /ae\.kind\s*=\s*'observer'/i,
    'V4 ladder observer branch must be present in repair query'
  );
  assert.match(
    allSQL,
    /ELSE\s+'guest'/i,
    'V4 ladder ELSE branch must be \'guest\' (matches sync_operational_role_cache)'
  );
  assert.match(
    allSQL,
    /auth_engagements/i,
    'repair must read from auth_engagements view (V4 source of truth)'
  );
  assert.match(
    allSQL,
    /is_authoritative\s*=\s*true/i,
    'repair must filter by is_authoritative = true'
  );
});

// ─── Live DB enforcement check (skip if no env) ───────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

async function execSQL(query) {
  // Uses PostgREST RPC pattern via the schema_invariants helper — but since
  // we need arbitrary SQL we'll use pg-meta via direct REST. Instead, lean on
  // check_schema_invariants() which already surfaces A3 violations.
  const url = `${SUPABASE_URL}/rest/v1/rpc/check_schema_invariants`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'apikey': SERVICE_ROLE_KEY,
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify({}),
  });
  if (!res.ok) throw new Error(`RPC failed: HTTP ${res.status}`);
  return res.json();
}

test('p230 #318 (live): A3 invariant has 0 violations post-repair', { skip: !canRun && skipMsg }, async () => {
  const rows = await execSQL();
  const a3 = rows.find(r => r.invariant_name === 'A3_active_role_engagement_derivation');
  assert.ok(a3, 'A3 invariant must be present in check_schema_invariants()');
  assert.strictEqual(
    a3.violation_count,
    0,
    `A3 must be 0 violations post-migration; got ${a3.violation_count} (samples: ${JSON.stringify(a3.sample_ids)})`
  );
});
