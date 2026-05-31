// Contract test — p277 ops-bug bundle (#449 offboarding category + #450 meeting decision status)
// Guards migration 20260805000078 (MINIMAL scope, PM-ratified 2026-05-31).
//
// #450 register_decision + create_action_item(kind='decision') wrote status='completed',
//      invalid under meeting_action_items_status_check = {open,done,cancelled,carried_over}
//      -> every decision-registration RPC failed (23514). Fix: 'completed' -> 'done'.
// #449 _offboarding_create_stub (AFTER UPDATE trigger) fell through to NULL reason_category_code
//      (NOT NULL + FK offboard_reason_categories) for free-text reasons -> whole offboard rolled
//      back (23502). Fix: COALESCE(v_inferred_category,'other'). offboard_member also passed the
//      phantom 'administrative' (not a real code) -> changed to the real code 'other'.
//      admin_offboard_member is restored to its original body (precision deferred).
//
// Static-source assertions (offline-safe) + a DB-gated smoke.
// Registered in package.json "test" + "test:contracts".
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO = join(__dirname, '..', '..');
const MIG = join(REPO, 'supabase', 'migrations',
  '20260805000078_ops_bug_bundle_meeting_status_offboarding_category.sql');
const src = readFileSync(MIG, 'utf8');

// ── #450 — valid meeting status ───────────────────────────────────────────────
test('#450 register_decision writes the valid terminal status done', () => {
  assert.match(src, /'decision', 'done'/, "register_decision must INSERT status 'done'");
});

test('#450 create_action_item decision branch yields done', () => {
  assert.match(src, /WHEN p_kind = 'decision' THEN 'done' ELSE 'open' END/,
    "create_action_item decision branch must yield 'done'");
});

test('#450 the invalid completed status is gone from meeting-item writes', () => {
  assert.doesNotMatch(src, /'decision', 'completed'/, 'register_decision must not write completed');
  assert.doesNotMatch(src, /THEN 'completed' ELSE 'open'/, 'create_action_item must not write completed');
});

// ── #449 — offboarding category never NULL, never phantom ──────────────────────
test('#449 trigger coalesces a missing/invalid category to the real code other', () => {
  assert.match(src, /COALESCE\(v_inferred_category, 'other'\)/,
    "trigger must fall back to the valid 'other' code, never NULL");
});

test('#449 offboard_member passes the real category code, not the phantom administrative', () => {
  assert.match(src, /p_reason_category => 'other'/, "offboard_member must pass 'other'");
  assert.doesNotMatch(src, /administrative/, "the phantom 'administrative' code must be gone");
});

test('#449 admin_offboard_member is restored to its original reason write (minimal scope)', () => {
  // minimal scope keeps the original behaviour: status_change_reason = COALESCE(detail, category)
  assert.match(src, /status_change_reason = COALESCE\(p_reason_detail, p_reason_category\)/,
    'admin_offboard_member must keep its original status_change_reason expression');
});

// ── invariants preserved on every CREATE OR REPLACE ───────────────────────────
test('all five functions preserve SECURITY DEFINER + search_path', () => {
  // newline-anchored so the header comment's prose "SECURITY DEFINER" is not counted
  assert.equal((src.match(/\n SECURITY DEFINER\n/g) || []).length, 5, 'five SECURITY DEFINER clauses');
  assert.equal((src.match(/SET search_path TO 'public', 'pg_temp'/g) || []).length, 5,
    "five SET search_path TO 'public', 'pg_temp'");
});

test('signatures are preserved exactly (minimum-diff CREATE OR REPLACE)', () => {
  assert.match(src, /register_decision\(p_event_id uuid, p_title text, p_description text DEFAULT NULL::text, p_related_card_ids uuid\[\] DEFAULT NULL::uuid\[\]\)/);
  assert.match(src, /create_action_item\(p_event_id uuid, p_description text, p_assignee_id uuid DEFAULT NULL::uuid, p_due_date date DEFAULT NULL::date, p_board_item_id uuid DEFAULT NULL::uuid, p_checklist_item_id uuid DEFAULT NULL::uuid, p_kind text DEFAULT 'action'::text\)/);
  assert.match(src, /_offboarding_create_stub\(\)\n RETURNS trigger/);
  assert.match(src, /admin_offboard_member\(p_member_id uuid, p_new_status text, p_reason_category text, p_reason_detail text DEFAULT NULL::text, p_reassign_to uuid DEFAULT NULL::uuid\)/);
  assert.match(src, /offboard_member\(p_member_id uuid, p_new_status text, p_reason text, p_effective_date date DEFAULT NULL::date\)/);
});

// ── DB-gated smoke (skips offline when SUPABASE_SERVICE_ROLE_KEY absent) ───────
const HAS_DB = !!process.env.SUPABASE_SERVICE_ROLE_KEY;
const SUPA_URL = process.env.SUPABASE_URL || 'https://ldrfrvwhxsmgaabwmaik.supabase.co';

test("#449 the coalesce fallback 'other' is a valid active offboard category", { skip: !HAS_DB }, async () => {
  const res = await fetch(
    `${SUPA_URL}/rest/v1/offboard_reason_categories?code=eq.other&is_active=eq.true&select=code`,
    { headers: {
        apikey: process.env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`,
    } });
  assert.equal(res.status, 200);
  const rows = await res.json();
  assert.equal(rows.length, 1, "'other' must be a valid active category for the fallback to be FK-safe");
});
