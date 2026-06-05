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
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000115_186_curation_committee_broadcast.sql');
const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

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
  assert.match(migRaw, /WHEN 'curation_item_submitted'\s+THEN 'transactional_immediate'/,
    'new type is immediate-email');
  // adr-0022 parity: the existing catalog WHENs must be preserved
  assert.match(migRaw, /WHEN 'selection_cutoff_approved'\s+THEN 'transactional_immediate'/,
    'existing _delivery_mode_for catalog preserved');
});

test('#186 static: notify trigger broadcasts to curate_content curators on the transition', () => {
  assert.match(migRaw, /CREATE OR REPLACE FUNCTION public\.notify_on_curation_status_change/,
    'recreates the trigger function');
  assert.match(migRaw, /NEW\.curation_status = 'curation_pending'\s*AND OLD\.curation_status IS DISTINCT FROM 'curation_pending'/,
    'broadcast is gated on the curation_pending TRANSITION (idempotent)');
  assert.match(migRaw, /can_by_member\(m\.id, 'curate_content'\)/,
    'broadcast targets V4 curate_content authority');
  assert.match(migRaw, /'curation_item_submitted'[\s\S]{0,200}'\/admin\/curatorship'/,
    'broadcast emits curation_item_submitted linking to /admin/curatorship');
  assert.match(migRaw, /member_status = 'active'/, 'broadcast restricted to active members');
});

test('#186 static: assignee-notify path is preserved (not replaced)', () => {
  assert.match(migRaw, /FOR v_assignee IN[\s\S]{0,120}board_item_assignments/,
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
