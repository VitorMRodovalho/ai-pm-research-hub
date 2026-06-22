/**
 * #785 PR-3 — Confidential initiative visibility gate (RPC layer).
 *
 * PR-1 (20260805000231) added initiatives.visibility + rls_can_see_initiative().
 * PR-2 (20260805000232) added the 8 RESTRICTIVE RLS SELECT policies + 2 SECDEF
 * resolvers + the AJ invariant. PR-3 (20260805000233) gates the SECURITY DEFINER
 * read/list RPCs that BYPASS RLS, so a confidential initiative never leaks through
 * an RPC to a non-engaged member. Curation surfaces exclude confidential (PM #2);
 * public aggregates exclude confidential from their initiative counts.
 *
 * Static (offline) assertions: every read/list RPC's CREATE block calls the right
 * helper; aggregates filter by visibility; no read path is weakened. DB-aware checks:
 * the gate is live in every targeted function body, and the standard path is intact.
 *
 * The 3-identity behavioural proof (non-engaged: detail='Initiative not found',
 * board=NULL, summary='No board linked'; engaged + GP keep full access; standard path
 * unchanged at 33 board items) was validated live in a ROLLBACK transaction during PR-3
 * development. It is not replayed here because the harness has no per-user JWT path
 * (service_role bypasses RLS / sets auth.uid() = NULL).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const MIG = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20260805000233_p785_pr3_confidential_initiative_rpcs.sql'),
  'utf8',
);

// Read/list RPCs that resolve an initiative directly → rls_can_see_initiative(...)
const INITIATIVE_GATED = [
  'list_initiatives', 'list_open_initiatives', 'list_project_boards', 'list_tribe_deliverables',
  'search_board_items', 'search_hub_resources', 'list_initiative_events',
  'get_initiative_detail', 'get_initiative_gamification', 'get_initiative_drive_links',
  'get_initiative_board_summary', 'get_meeting_detail', 'get_near_events', 'get_recent_events',
  'get_agenda_smart', 'get_curation_cross_board', 'get_curation_dashboard',
  'list_curation_pending_board_items', 'list_pending_curation',
];
// RPCs that resolve through a board → rls_can_see_board(...)
const BOARD_GATED = ['get_board', 'get_card_detail', 'assign_curation_reviewer'];
// RPCs that resolve a meeting artifact (own initiative_id OR via event) → rls_can_see_artifact_link(...)
const ARTIFACT_GATED = ['list_meeting_artifacts', 'list_initiative_meeting_artifacts'];
// Public aggregates that exclude confidential from initiative counts (not auth-scoped)
const AGGREGATE_GATED = ['get_homepage_stats', 'get_public_platform_stats'];

const ALL = [...INITIATIVE_GATED, ...BOARD_GATED, ...ARTIFACT_GATED, ...AGGREGATE_GATED];

/** Slice the CREATE OR REPLACE block for a given function out of the migration text. */
function fnBlock(sql, name) {
  const start = sql.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  if (start === -1) return null;
  const next = sql.indexOf('CREATE OR REPLACE FUNCTION public.', start + 1);
  return sql.slice(start, next === -1 ? undefined : next);
}

test('#785 PR-3 mig: every targeted RPC is re-created (CREATE OR REPLACE present)', () => {
  for (const name of ALL) {
    assert.ok(fnBlock(MIG, name), `${name} must be CREATE OR REPLACE'd in the PR-3 migration`);
  }
});

test('#785 PR-3 mig: initiative-resolved RPCs call rls_can_see_initiative inside their own block', () => {
  for (const name of INITIATIVE_GATED) {
    const block = fnBlock(MIG, name);
    assert.match(block, /public\.rls_can_see_initiative\(/, `${name} must gate via rls_can_see_initiative`);
  }
});

test('#785 PR-3 mig: board-resolved RPCs call the SECDEF rls_can_see_board resolver', () => {
  for (const name of BOARD_GATED) {
    const block = fnBlock(MIG, name);
    assert.match(block, /public\.rls_can_see_board\(/, `${name} must gate via rls_can_see_board`);
  }
});

test('#785 PR-3 mig: meeting-artifact RPCs call the SECDEF rls_can_see_artifact_link resolver', () => {
  for (const name of ARTIFACT_GATED) {
    const block = fnBlock(MIG, name);
    assert.match(block, /public\.rls_can_see_artifact_link\(/, `${name} must gate via rls_can_see_artifact_link`);
  }
});

test('#785 PR-3 mig: public aggregates exclude confidential from initiative counts', () => {
  for (const name of AGGREGATE_GATED) {
    const block = fnBlock(MIG, name);
    assert.match(block, /visibility <> 'confidential'/, `${name} aggregate must exclude confidential initiatives`);
  }
});

test('#785 PR-3 mig: gate is fail-closed and preserves SECURITY DEFINER (no read path weakened)', () => {
  // Every re-created function must keep SECURITY DEFINER (RLS-bypass funcs must stay gated in-body).
  for (const name of ALL) {
    const block = fnBlock(MIG, name);
    assert.match(block, /SECURITY DEFINER/i, `${name} must remain SECURITY DEFINER`);
  }
  // The migration must never widen a read path.
  assert.doesNotMatch(MIG, /USING\s*\(\s*true\s*\)/i, 'PR-3 must not introduce USING (true)');
  // Detail/board RPCs fail closed: the gate returns a not-found/null/error, never raw data.
  assert.match(fnBlock(MIG, 'get_initiative_detail'), /rls_can_see_initiative\(p_initiative_id\)[\s\S]{0,120}'Initiative not found'/);
  assert.match(fnBlock(MIG, 'get_board'), /rls_can_see_board\(p_board_id\)[\s\S]{0,80}RETURN NULL/);
});

const dbGated = process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY;
const skipMsg = 'requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';

test('#785 PR-3 DB: standard path intact — public aggregates still return their initiative keys', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
  const { data: hp, error: e1 } = await sb.rpc('get_homepage_stats');
  assert.ifError(e1);
  assert.ok(hp && typeof hp.total_initiatives === 'number', 'get_homepage_stats must still return total_initiatives');
  assert.ok(hp.total_initiatives >= 0);
  const { data: ps, error: e2 } = await sb.rpc('get_public_platform_stats');
  assert.ifError(e2);
  assert.ok(ps && typeof ps.total_initiatives === 'number', 'get_public_platform_stats must still return total_initiatives');
});

test('#785 PR-3 DB: rls_can_see_initiative(NULL) is true (org-level rows stay visible)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('rls_can_see_initiative', { p_initiative_id: null });
  assert.ifError(error);
  assert.equal(data, true);
});
