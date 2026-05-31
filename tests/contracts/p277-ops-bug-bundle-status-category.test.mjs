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
// SQL with `-- ...` line comments stripped, so prose in the header (which legitimately
// mentions the phantom 'administrative' code being removed) cannot satisfy a code assertion.
const code = src.replace(/^\s*--.*$/gm, '');

// ── #450 — valid meeting status ───────────────────────────────────────────────
test('#450 register_decision writes the valid terminal status done', () => {
  assert.match(code, /'decision', 'done'/, "register_decision must INSERT status 'done'");
});

test('#450 create_action_item decision branch yields done', () => {
  assert.match(code, /WHEN p_kind = 'decision' THEN 'done' ELSE 'open' END/,
    "create_action_item decision branch must yield 'done'");
});

test('#450 the invalid completed status is gone from meeting-item writes', () => {
  assert.doesNotMatch(code, /'decision', 'completed'/, 'register_decision must not write completed');
  assert.doesNotMatch(code, /THEN 'completed' ELSE 'open'/, 'create_action_item must not write completed');
});

// ── #449 — offboarding category never NULL, never phantom ──────────────────────
test('#449 trigger coalesces a missing/invalid category to the real code other', () => {
  assert.match(code, /COALESCE\(v_inferred_category, 'other'\)/,
    "trigger must fall back to the valid 'other' code, never NULL");
});

test('#449 offboard_member passes the real category code, not the phantom administrative', () => {
  assert.match(code, /p_reason_category => 'other'/, "offboard_member must pass 'other'");
  // the phantom code must not be PASSED in code (the header comment may still name it)
  assert.doesNotMatch(code, /=> 'administrative'/, "offboard_member must not pass 'administrative'");
});

test('#449 admin_offboard_member is restored to its original reason write (minimal scope)', () => {
  // minimal scope keeps the original behaviour: status_change_reason = COALESCE(detail, category)
  assert.match(code, /status_change_reason = COALESCE\(p_reason_detail, p_reason_category\)/,
    'admin_offboard_member must keep its original status_change_reason expression');
});

// ── invariants preserved on every CREATE OR REPLACE ───────────────────────────
test('all five functions are CREATE OR REPLACE with SECURITY DEFINER + search_path', () => {
  for (const name of ['register_decision', 'create_action_item', '_offboarding_create_stub',
                      'admin_offboard_member', 'offboard_member']) {
    assert.ok(code.includes(`CREATE OR REPLACE FUNCTION public.${name}(`),
      `missing CREATE OR REPLACE for ${name}`);
  }
  assert.equal((code.match(/SECURITY DEFINER/g) || []).length, 5, 'five SECURITY DEFINER clauses');
  assert.equal((code.match(/SET search_path TO 'public', 'pg_temp'/g) || []).length, 5,
    "five SET search_path TO 'public', 'pg_temp'");
});

test('load-bearing signature shapes are preserved (trigger no-arg; offboard_member 4-arg)', () => {
  assert.match(code, /public\._offboarding_create_stub\(\)/, 'trigger keeps its no-arg signature');
  assert.match(code, /RETURNS trigger/, 'trigger keeps RETURNS trigger');
  assert.match(code, /offboard_member\(p_member_id uuid, p_new_status text, p_reason text, p_effective_date date/,
    'offboard_member keeps its 4-arg shape');
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
