/**
 * #190 contract test — get_curation_queue_state board-only envelope.
 *
 * A normalized read envelope over the board_items curation FSM (ADR-0086) with
 * explicit origin_type='board_item', per-caller eligible_actions, SLA, review
 * round/count, and a caller capability block. The stable envelope #188's curator
 * MCP tools wrap. Cross-pipeline origin types deferred to an ADR (PM Option A).
 *
 * Verified live (impersonated admin): summary.total=3 (leader_review:2,
 * curation_pending:1), eligible_actions=['submit_review','assign_reviewer','publish'],
 * caller caps populated, p_status filter works.
 *
 * Static + DB-gated (the RPC is auth.uid()-gated; service-role hits the gate, which
 * is itself the assertion).
 *
 * Cross-ref: #190, ADR-0086 (FSM), get_curation_dashboard (sibling), #188 (consumer).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const MIG = readFileSync(
  join(resolve(process.cwd(), 'supabase/migrations'), '20260805000121_190_curation_queue_state_envelope.sql'),
  'utf8',
);

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── (A) static ──
test('#190: declares get_curation_queue_state(p_status)', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.get_curation_queue_state\(p_status text/);
  assert.match(MIG, /SECURITY DEFINER/);
});

test('#190: read gate is curate_content OR write_board OR participate_in_governance_review', () => {
  assert.match(MIG, /v_can_curate\s*:=\s*public\.can_by_member\(v_member_id, 'curate_content'\)/);
  assert.match(MIG, /v_can_write_board\s*:=\s*public\.can_by_member\(v_member_id, 'write_board'\)/);
  assert.match(MIG, /v_can_govern\s*:=\s*public\.can_by_member\(v_member_id, 'participate_in_governance_review'\)/);
  assert.match(MIG, /IF NOT \(v_can_curate OR v_can_write_board OR v_can_govern\) THEN/);
});

test('#190: normalized envelope — origin_type + eligible_actions + actionable-state filter', () => {
  assert.match(MIG, /'origin_type', 'board_item'/);
  assert.match(MIG, /'eligible_actions',/);
  assert.match(MIG, /curation_status IN \('peer_review', 'leader_review', 'curation_pending'\)/);
  // eligible_actions predicates must mirror the real write-RPC gates (all gate on
  // participate_in_governance_review; submit/publish require curation_pending state):
  assert.match(MIG, /SELECT 'submit_review'::text AS act\s*\n\s*WHERE v_can_govern\s*\n\s*AND q\.curation_status = 'curation_pending'/);
  assert.match(MIG, /SELECT 'assign_reviewer' WHERE v_can_govern/);
  assert.match(MIG, /SELECT 'publish' WHERE q\.curation_status = 'curation_pending' AND v_can_govern/);
});

test('#190: caller capability block is returned', () => {
  assert.match(MIG, /'caller', jsonb_build_object\([\s\S]*?'can_curate', v_can_curate[\s\S]*?'can_govern', v_can_govern/);
});

// ── (B) DB-gated: the RPC exists and fail-closes for an unauthenticated caller ──
test('#190 DB: get_curation_queue_state fail-closes (service-role has no auth.uid())', { skip: !dbGated && skipMsg }, async () => {
  const supa = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { error } = await supa.rpc('get_curation_queue_state', { p_status: null });
  // service-role token carries no auth.uid() -> the function RAISEs 'Not authenticated'
  // (proves the RPC exists, is reachable via PostgREST, and is auth-gated).
  assert.ok(error, 'expected an auth error from the gated RPC');
  assert.match(error.message, /Not authenticated|Curatorship access required/);
});
