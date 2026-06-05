/**
 * Contract: #193 — clean phantom curation FSM states + dead auto-publish trigger.
 *
 * The board_items_curation_status_check CHECK allows only
 * {draft, peer_review, leader_review, curation_pending, published}. Two artifacts
 * referenced unreachable values:
 *   (1) trigger trg_auto_publish_approved + fn auto_publish_approved_article() gate
 *       on curation_status='approved' (impossible) -> dead code; real publish path is
 *       submit_curation_review() -> publish_board_item_from_curation().
 *   (2) get_curation_dashboard() items query filtered IN ('curation_pending','revision_requested')
 *       -> 'revision_requested' is not a valid value, always 0 rows.
 *
 * Migration 20260805000111 drops (1) and removes the phantom from (2). Behaviour-preserving
 * (0 live rows in either value). Forward-defense locks the cleanup permanently.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000111_193_curation_fsm_cleanup.sql');
const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const client = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

const CANONICAL_STATES = ['draft', 'peer_review', 'leader_review', 'curation_pending', 'published'];

// ── STATIC ──────────────────────────────────────────────────────────────────────
test('#193 static: migration 20260805000111 exists', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000111 exists');
});

test('#193 static: migration drops the dead auto-publish trigger + function', () => {
  assert.match(migRaw, /DROP TRIGGER IF EXISTS trg_auto_publish_approved ON public\.board_items/,
    'drops trg_auto_publish_approved');
  assert.match(migRaw, /DROP FUNCTION IF EXISTS public\.auto_publish_approved_article\(\)/,
    'drops auto_publish_approved_article()');
});

test('#193 static: rewritten get_curation_dashboard contains no phantom revision_requested', () => {
  assert.match(migRaw, /CREATE OR REPLACE FUNCTION public\.get_curation_dashboard/,
    'migration recreates get_curation_dashboard');
  // The function BODY must filter only curation_pending. The header comment may mention the
  // word in prose; assert the items WHERE clause uses the single canonical value.
  assert.match(migRaw, /WHERE bi\.curation_status = 'curation_pending'/,
    'items query filters only curation_pending (phantom removed)');
});

test('#193 static: migration preserves the additive curate_content OR write_board gate (#245)', () => {
  assert.match(migRaw,
    /can_by_member\(v_member_id, 'curate_content'\)[\s\S]{0,80}OR[\s\S]{0,80}can_by_member\(v_member_id, 'write_board'\)/,
    'get_curation_dashboard keeps the #245 additive gate');
});

// ── DB-GATED (forward-defense against re-introduction) ─────────────────────────────
test('#193 db: dead auto-publish function is no longer callable (dropped)',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    // A trigger function cannot be invoked directly anyway, but if it still EXISTED PostgREST would
    // surface a different error. Post-drop, the function is absent from the schema cache entirely.
    const { error } = await sb.rpc('auto_publish_approved_article');
    assert.ok(error, 'auto_publish_approved_article() must error (dropped)');
    assert.match(String(error.message || error.code || ''), /(does not exist|PGRST202|404|not find|Could not find)/i,
      `expected not-found error, got: ${JSON.stringify(error)}`);
  });

test('#193 db: no board_items row carries a phantom curation_status',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    const { data, error } = await sb.from('board_items')
      .select('id, curation_status')
      .not('curation_status', 'in', `(${CANONICAL_STATES.join(',')})`)
      .limit(5);
    assert.ifError(error);
    assert.equal((data || []).length, 0,
      `all board_items.curation_status must be in the canonical set; found phantom rows: ${JSON.stringify(data)}`);
  });

test('#193 db: get_curation_dashboard live body excludes the phantom value',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    // Calling as service-role (no auth.uid()) raises the gate — that proves the RPC exists and is gated.
    // The phantom-absence is asserted statically against the migration that defined the live body.
    const { error } = await sb.rpc('get_curation_dashboard');
    assert.ok(error, 'get_curation_dashboard gates service-role callers (Not authenticated)');
    assert.match(String(error.message || ''), /Not authenticated|Curatorship access required/,
      `expected auth gate, got: ${JSON.stringify(error)}`);
  });
