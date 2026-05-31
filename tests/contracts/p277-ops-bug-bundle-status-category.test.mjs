// Contract test — p277 ops-bug bundle: meeting decisions (#450) + offboarding (#449)
// Guards the two runtime-failure fixes in migration 20260805000076:
//  #450 register_decision + create_action_item(kind='decision') wrote status='completed',
//       invalid under meeting_action_items_status_check = {open,done,cancelled,carried_over}.
//       Fix: 'completed' -> 'done'.
//  #449 _offboarding_create_stub fell through to NULL reason_category_code (NOT NULL + FK)
//       for free-text reasons matching no heuristic. Fix: coalesce(v_inferred_category,'other').
// Static-source assertions (offline) + DB-gated smoke.
//
// Registered in package.json "test" + "test:contracts".
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO = join(__dirname, '..', '..');
const MIG = join(REPO, 'supabase', 'migrations', '20260805000076_ops_bug_bundle_status_and_category.sql');

const migSrc = readFileSync(MIG, 'utf8');

// ── #450 static-source assertions (always run, offline-safe) ──────────────────
test('#450 register_decision inserts the valid terminal status done', () => {
  assert.match(migSrc, /register_decision[\s\S]*'decision', 'done'/, "register_decision must use 'done'");
});

test('#450 create_action_item decision branch maps to done', () => {
  assert.match(migSrc, /when p_kind = 'decision' then 'done' else 'open' end/, "decision branch must yield 'done'");
});

test('#450 no meeting action item is written with the invalid completed status', () => {
  // The only valid terminal statuses are {open,done,cancelled,carried_over}.
  // 'completed' must not appear as a meeting_action_items status literal.
  assert.doesNotMatch(migSrc, /'decision', 'completed'/, 'register_decision must not write completed');
  assert.doesNotMatch(migSrc, /then 'completed' else 'open'/, 'create_action_item must not write completed');
});

// ── #449 static-source assertions ─────────────────────────────────────────────
test('#449 _offboarding_create_stub coalesces a missing category to other', () => {
  assert.match(migSrc, /coalesce\(v_inferred_category, 'other'\)/, "must coalesce to the valid 'other' code");
});

test('#449 heuristic inference is preserved (no regression)', () => {
  // the ILIKE heuristics must still map known reasons before falling back to 'other'
  assert.match(migSrc, /ilike '%mudança%'[\s\S]*'relocation'/, 'relocation heuristic retained');
  assert.match(migSrc, /ilike '%trabalho%'[\s\S]*'career_change'/, 'career_change heuristic retained');
});

// ── invariants preserved on all three CREATE OR REPLACE ───────────────────────
test('all three functions preserve SECURITY DEFINER + empty search_path', () => {
  const secdef = migSrc.match(/SECURITY DEFINER/g) || [];
  const sp = migSrc.match(/SET search_path TO ''/g) || [];
  assert.equal(secdef.length, 3, 'three SECURITY DEFINER');
  assert.equal(sp.length, 3, "three SET search_path TO ''");
});

test('signatures are preserved exactly (minimum-diff CREATE OR REPLACE)', () => {
  assert.match(migSrc, /register_decision\(p_event_id uuid, p_decision_text text, p_decision_maker_id uuid, p_rationale text\)/);
  assert.match(migSrc, /create_action_item\(p_event_id uuid, p_description text, p_assignee_id uuid, p_due_date date, p_board_item_id uuid, p_checklist_item_id uuid, p_kind text\)/);
  assert.match(migSrc, /_offboarding_create_stub\(p_member_id uuid, p_reason text, p_reason_category_code text, p_initiated_by uuid, p_notes text\)/);
});

// ── DB-gated smoke (skips offline when SUPABASE_SERVICE_ROLE_KEY absent) ───────
const HAS_DB = !!process.env.SUPABASE_SERVICE_ROLE_KEY;
const SUPA_URL = process.env.SUPABASE_URL || 'https://ldrfrvwhxsmgaabwmaik.supabase.co';

test("#449 the 'other' offboarding category exists and is active", { skip: !HAS_DB }, async () => {
  const res = await fetch(`${SUPA_URL}/rest/v1/offboarding_reason_categories?code=eq.other&is_active=eq.true&select=code`, {
    headers: {
      apikey: process.env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`,
    },
  });
  assert.equal(res.status, 200);
  const rows = await res.json();
  assert.equal(rows.length, 1, "the coalesce fallback 'other' must be a valid active category code");
});
