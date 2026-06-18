/**
 * Tribe Selection Híbrida — PR1 (DB core) contract test.
 * See docs/specs/SPEC_TRIBE_SELECTION_HYBRID.md, migration 20260805000216.
 *
 * PR1 builds the CONTINUOUS post-promotion tribe-entry flow on the V4-native
 * initiative/engagement axis (the 8 tribes ARE initiatives kind='research_tribe'):
 *   - trg_sync_tribe_id_from_engagement: bridges an active volunteer research_tribe
 *     engagement -> members.tribe_id (admission) and zeroes it on demotion ONLY when
 *     no other active research_tribe engagement remains (count_tribe_slots reads
 *     members.tribe_id, so the slot count follows automatically).
 *   - request_tribe_assignment(int, text): researcher self-requests a tribe (volunteer-term
 *     gate identical to select_tribe; blocks if already in any tribe — self-service is
 *     "join your first tribe", moves are GP-mediated).
 *   - review_tribe_request(uuid, text, text): tribe leader (Caminho-3 INLINE-scope) or GP
 *     (manage_member) approves/declines; approve inserts the engagement (granted_by = the
 *     reviewer's PERSON id, since engagements.granted_by FK -> persons(id)).
 *   - invariants AG_tribe_engagement_has_tribe_id + AH_research_tribe_single_active_engagement
 *     (baseline 0/0). AH supersedes the SPEC's I_research_tribe_no_dual_pending (which
 *     false-positives on a legitimate tribe-move).
 *
 * Static asserts on the migration body + DB-gated asserts on the live objects and the two
 * new invariants reporting 0. The end-to-end behaviour (admission, demotion, demotion-guard,
 * request, authority negative/positive, bridge-on-approve) was validated via a transactional
 * smoke test at apply time (documented in the migration); CI keeps the DB checks read-only
 * per house convention.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const MIG_FILE = '20260805000216_tribe_selection_hybrid_pr1.sql';
const MIG = readFileSync(join(MIGRATIONS_DIR, MIG_FILE), 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── (A) static: the migration declares the three objects + trigger ──
test('migration declares the bridge trigger function and trigger', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\._sync_tribe_id_from_engagement\(\)/);
  assert.match(MIG, /CREATE TRIGGER trg_sync_tribe_id_from_engagement\s+AFTER INSERT OR UPDATE OF status, kind ON public\.engagements/);
  assert.match(MIG, /WHEN \(NEW\.kind = 'volunteer'\)/);
});

test('migration declares request_tribe_assignment and review_tribe_request RPCs', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.request_tribe_assignment\(p_tribe_id integer, p_message text\)/);
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.review_tribe_request\(p_invitation_id uuid, p_decision text, p_note text DEFAULT NULL::text\)/);
});

test('bridge trigger has the mandatory demotion branch (zero only if no other active tribe engagement)', () => {
  // demotion: active -> non-active, and the "no other active research_tribe engagement" guard
  assert.match(MIG, /OLD\.status = 'active' AND NEW\.status <> 'active'/);
  assert.match(MIG, /NOT EXISTS \(\s*SELECT 1\s*FROM public\.engagements e2/);
  assert.match(MIG, /SET tribe_id = NULL/);
});

test('request_tribe_assignment keeps the select_tribe volunteer-term gate (fail-closed)', () => {
  assert.match(MIG, /member_is_pre_onboarding\(v_person_id, v_member_status\)/);
  // blocks if already in ANY tribe (protects the AH single-active invariant on approval)
  assert.match(MIG, /Você já participa de uma tribo/);
});

test('review_tribe_request uses Caminho-3 inline-scope authority (no shared-gate, no seed)', () => {
  // GP via manage_member OR active volunteer/leader engagement scoped to THIS initiative
  assert.match(MIG, /can_by_member\(v_caller_member_id, 'manage_member'\)/);
  assert.match(MIG, /e\.initiative_id = v_invitation\.initiative_id\s+AND e\.kind = 'volunteer'\s+AND e\.role = 'leader'/);
  // must NOT touch the shared gate nor seed engagement_kind_permissions
  assert.doesNotMatch(MIG, /CREATE OR REPLACE FUNCTION public\.review_initiative_request/);
  assert.doesNotMatch(MIG, /INSERT INTO public\.engagement_kind_permissions/);
});

test('review_tribe_request grants engagement with granted_by = reviewer PERSON id (FK -> persons)', () => {
  // the bug the smoke test caught: granted_by FK is persons(id), not members(id)
  assert.match(MIG, /v_caller_person_id,\s*--\s*engagements\.granted_by FK -> persons\(id\)/);
});

test('migration marks tribe_selections legacy (frozen) without dropping it', () => {
  assert.match(MIG, /COMMENT ON TABLE public\.tribe_selections IS/);
  assert.match(MIG, /LEGACY \(frozen\)/);
  assert.doesNotMatch(MIG, /DROP TABLE[^\n]*tribe_selections/);
});

test('migration appends invariants AG + AH to check_schema_invariants', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.check_schema_invariants\(\)/);
  assert.match(MIG, /'AG_tribe_engagement_has_tribe_id'::text/);
  assert.match(MIG, /'AH_research_tribe_single_active_engagement'::text/);
  // AG keeps the bridge contract; AH guards the single-active assumption
  assert.match(MIG, /m\.tribe_id IS DISTINCT FROM i\.legacy_tribe_id/);
  assert.match(MIG, /GROUP BY e\.person_id\s*\n\s*HAVING COUNT\(\*\) > 1/);
});

test('migration is registered in the active synthetic series', () => {
  const files = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql'));
  assert.ok(files.includes(MIG_FILE), 'migration present in migrations dir');
  const ts = Number(MIG_FILE.slice(0, 14));
  assert.ok(ts >= 20260805000216 && ts < 20260806000000, 'timestamp in the active synthetic series');
});

// ── (B) DB-gated: the two new invariants exist and report 0 ──
test('DB: check_schema_invariants includes AG + AH, both reporting 0 violations', { skip: !dbGated && skipMsg }, async () => {
  const supa = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await supa.rpc('check_schema_invariants');
  assert.equal(error, null, error ? `check_schema_invariants failed: ${error.message}` : '');
  const byName = Object.fromEntries((data || []).map((r) => [r.invariant_name, r]));
  const ag = byName['AG_tribe_engagement_has_tribe_id'];
  const ah = byName['AH_research_tribe_single_active_engagement'];
  assert.ok(ag, 'AG_tribe_engagement_has_tribe_id present');
  assert.ok(ah, 'AH_research_tribe_single_active_engagement present');
  assert.equal(ag.violation_count, 0, `AG must be 0, got ${ag.violation_count}`);
  assert.equal(ah.violation_count, 0, `AH must be 0, got ${ah.violation_count}`);
});
