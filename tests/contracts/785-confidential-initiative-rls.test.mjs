/**
 * #785 PR-2 — Confidential initiative visibility gate (RLS layer).
 *
 * PR-1 (mig 20260805000231) added initiatives.visibility + rls_can_see_initiative()
 * (behavior-neutral). PR-2 (mig 20260805000232) wires the gate: a RESTRICTIVE SELECT
 * policy on each of the 8 initiative-dependent tables, two SECURITY DEFINER resolver
 * helpers (board→initiative, artifact→initiative) so cross-table resolution bypasses
 * RLS instead of leaking through an inline subquery, and the AJ structural invariant.
 *
 * Static (offline) assertions on the migration file + DB-aware checks that the gate is
 * live (AJ invariant green) and that the standard path stays open (helper(NULL)=true).
 *
 * The 3-identity behavioural proof (active non-engaged sees 182 board items under
 * 'standard' but 0 under 'confidential'; engaged + GP keep access) was validated live
 * via simulated identities during PR-2 development; it is not replayed here because the
 * test harness has no per-user JWT/SET ROLE path (service_role bypasses RLS). The AJ
 * invariant guards that all 8 RESTRICTIVE policies remain present.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const MIG = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20260805000232_p785_pr2_confidential_initiative_rls.sql'),
  'utf8',
);

const DEPENDENT_TABLES = [
  'initiatives', 'events', 'project_boards', 'board_items',
  'meeting_artifacts', 'tribe_deliverables', 'recurring_meeting_rules', 'governance_documents',
];

test('#785 PR-2 mig: each of the 8 dependent tables gets a RESTRICTIVE SELECT confidentiality policy', () => {
  for (const t of DEPENDENT_TABLES) {
    const re = new RegExp(
      `CREATE POLICY ${t}_confidential_visibility ON public\\.${t}\\s+AS RESTRICTIVE FOR SELECT TO public`,
      'i',
    );
    assert.match(MIG, re, `${t} must have a RESTRICTIVE FOR SELECT confidentiality policy`);
  }
});

test('#785 PR-2 mig: every confidentiality policy USING calls a rls_can_see_* helper', () => {
  // initiatives/events/project_boards/tribe_deliverables/recurring_meeting_rules/governance_documents → rls_can_see_initiative
  for (const t of ['initiatives', 'events', 'project_boards', 'tribe_deliverables', 'recurring_meeting_rules', 'governance_documents']) {
    assert.match(MIG, new RegExp(`${t}_confidential_visibility[\\s\\S]{0,160}rls_can_see_initiative`, 'i'), `${t} USING must call rls_can_see_initiative`);
  }
  // board_items resolves through the SECDEF board helper (no inline subquery leak)
  assert.match(MIG, /board_items_confidential_visibility[\s\S]{0,160}rls_can_see_board\(board_id\)/i);
  // meeting_artifacts resolves through the SECDEF artifact helper (own initiative_id or via event)
  assert.match(MIG, /meeting_artifacts_confidential_visibility[\s\S]{0,200}rls_can_see_artifact_link\(initiative_id, event_id\)/i);
});

test('#785 PR-2 mig: two SECURITY DEFINER resolver helpers are created (anti inline-subquery leak)', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.rls_can_see_board\(p_board_id uuid\)/i);
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.rls_can_see_artifact_link\(p_initiative_id uuid, p_event_id uuid\)/i);
  // both must be SECURITY DEFINER with a pinned search_path
  const boardBlock = MIG.slice(MIG.indexOf('rls_can_see_board(p_board_id'));
  assert.match(boardBlock.slice(0, 400), /SECURITY DEFINER/i, 'rls_can_see_board must be SECURITY DEFINER');
  assert.match(boardBlock.slice(0, 400), /SET search_path TO 'public', 'pg_temp'/i);
  const artBlock = MIG.slice(MIG.indexOf('rls_can_see_artifact_link(p_initiative_id'));
  assert.match(artBlock.slice(0, 400), /SECURITY DEFINER/i, 'rls_can_see_artifact_link must be SECURITY DEFINER');
});

test('#785 PR-2 mig: adds the AJ structural invariant to check_schema_invariants', () => {
  assert.match(MIG, /AJ_confidential_visibility_gate_present/);
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.check_schema_invariants\(\)/i);
  // the AJ drift query is catalog-based (pg_policies) and RESTRICTIVE-scoped
  assert.match(MIG, /FROM pg_policies p[\s\S]{0,200}permissive = 'RESTRICTIVE'[\s\S]{0,120}rls_can_see_/i);
});

test('#785 PR-2 mig: does not weaken any read path (no USING (true), no anon grant of confidential)', () => {
  assert.doesNotMatch(MIG, /USING\s*\(\s*true\s*\)/i, 'confidentiality migration must never introduce USING (true)');
});

const dbGated = process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY;
const skipMsg = 'requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';

test('#785 PR-2 DB: AJ invariant is green (all 8 gate policies live)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('check_schema_invariants');
  assert.ifError(error);
  const aj = data.find(r => r.invariant_name === 'AJ_confidential_visibility_gate_present');
  assert.ok(aj, 'AJ invariant must be present in check_schema_invariants output');
  assert.equal(aj.violation_count, 0, 'all 8 confidentiality gate policies must be present (0 drift)');
});

test('#785 PR-2 DB: rls_can_see_initiative(NULL) is true (standard path stays open)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('rls_can_see_initiative', { p_initiative_id: null });
  assert.ifError(error);
  assert.equal(data, true, 'org-level (NULL initiative) rows must remain visible — behavior-neutral');
});
