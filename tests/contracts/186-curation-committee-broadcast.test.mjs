/**
 * Contract: #186 — broadcast to the curation committee when an item enters curation.
 *
 * Before: submit_for_curation()/p196 auto-submit move an item to curation_pending but
 * notify_on_curation_status_change only looped board_item_assignments, so the canonical
 * "submit without naming curators" path notified NOBODY.
 *
 * After (PM decision = immediate email + in-app, mig 20260805000115):
 *   - _delivery_mode_for('curation_item_submitted') = 'transactional_immediate'
 *   - notify_on_curation_status_change broadcasts to every active curate_content member
 *     on the curation_pending TRANSITION (idempotent), link /admin/curatorship.
 *
 * Live build smoke (rolled back): transitioning a draft item to curation_pending created
 * exactly 3 curation_item_submitted notifications (= the 3 curate_content curators).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
// Entrega histórica: a migration 115 existe. As invariantes CORRENTES leem a captura vigente das
// funções (#1932): a #2496 recriou as duas, e fixar a 115 afirmaria sobre texto vencido.
const MIG = resolve(ROOT, 'supabase/migrations/20260805000115_186_curation_committee_broadcast.sql');
const delivery = maskLineComments(latestFunctionCapture(ROOT, '_delivery_mode_for').body);
const notifyCap = latestFunctionCapture(ROOT, 'notify_on_curation_status_change');
const notify = maskLineComments(notifyCap.body);
/** O bloco `IF NEW.curation_status ... END IF;` que contém a âncora. */
function ifBlockContaining(body, anchor) {
  const at = body.indexOf(anchor);
  assert.ok(at !== -1, `âncora ausente do corpo vigente: ${anchor}`);
  return body.slice(body.lastIndexOf('IF NEW.curation_status', at), body.indexOf('END IF;', at));
}

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const client = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

// ── STATIC ──────────────────────────────────────────────────────────────────────
test('#186 static: migration 115 exists', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000115 exists');
});

test('#186 static: _delivery_mode_for routes curation_item_submitted to transactional_immediate', () => {
  assert.match(delivery, /WHEN 'curation_item_submitted'\s+THEN 'transactional_immediate'/,
    'new type is immediate-email');
  // adr-0022 parity: the existing catalog WHENs must be preserved
  assert.match(delivery, /WHEN 'selection_cutoff_approved'\s+THEN 'transactional_immediate'/,
    'existing _delivery_mode_for catalog preserved');
});

test('#186 static: notify trigger broadcasts to curate_content curators on the transition', () => {
  assert.match(notifyCap.block, /^CREATE OR REPLACE FUNCTION public\.notify_on_curation_status_change/,
    'the current capture recreates the trigger function');
  const block = ifBlockContaining(notify, "'curation_item_submitted'");
  assert.match(block, /^IF NEW\.curation_status = 'curation_pending'\s*AND OLD\.curation_status IS DISTINCT FROM 'curation_pending' THEN/,
    'broadcast is gated on the curation_pending TRANSITION (idempotent)');
  assert.match(block, /WHERE m\.member_status = 'active'\s+AND public\.can_by_member\(m\.id, 'curate_content'\)\s+LOOP/,
    'broadcast targets active members with V4 curate_content authority');
  assert.match(block, /'curation_item_submitted'[\s\S]{0,200}'\/admin\/curatorship'/,
    'broadcast emits curation_item_submitted linking to /admin/curatorship');
});

test('#186 static: assignee-notify path is preserved (not replaced)', () => {
  assert.match(notify, /FOR v_assignee IN[\s\S]{0,120}board_item_assignments/,
    'the existing assignee notification loop is retained');
});

// ── DB-GATED ──────────────────────────────────────────────────────────────────────
test('#186 db: _delivery_mode_for(curation_item_submitted) = transactional_immediate',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    const { data, error } = await sb.rpc('_delivery_mode_for', { p_type: 'curation_item_submitted' });
    assert.ifError(error);
    assert.equal(data, 'transactional_immediate',
      'curation committee broadcast must route to immediate email');
  });
