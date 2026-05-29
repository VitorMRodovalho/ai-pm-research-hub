/**
 * Contract: p277 — get_event_champion_suggestions derives real candidates (Feature 3).
 *
 * Was a pure pass-through of events.suggested_champion_ids (0/95 events ever populated → always
 * empty). Now: manual override preserved; otherwise DERIVES present members at the event ranked
 * by current-cycle contribution. Same signature + return shape (CREATE OR REPLACE, no break).
 * Live smoke: a recent 'geral' event derived 8 present-member candidates (was 0).
 *
 * Migration: supabase/migrations/20260805000059_p277_champion_suggestions_derive_from_attendance.sql
 * Cross-ref: docs/audit/METRIC_DISPARITY_AUDIT_2026-05-28.md (rule-wiring probe F3) · #424.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000059_p277_champion_suggestions_derive_from_attendance.sql');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

test('p277 F3: migration exists, same signature + return shape (CREATE OR REPLACE, no DROP)', () => {
  assert.ok(existsSync(MIG));
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_event_champion_suggestions\(p_event_id uuid\)/i);
  assert.match(body, /RETURNS TABLE\(member_id uuid, member_name text, designation_summary text\)/i);
  assert.ok(!/DROP FUNCTION/i.test(body), 'shape unchanged → no DROP');
  assert.match(body, /NOTIFY\s+pgrst/i);
});

test('p277 F3: auth gate preserved (manage_event OR award_champion + org check)', () => {
  assert.match(body, /can_by_member\(v_caller_id, 'manage_event'\)[\s\S]*?can_by_member\(v_caller_id, 'award_champion'\)/i);
  assert.match(body, /v_event_org != v_caller_org/i, 'cross-org guard preserved');
});

test('p277 F3: manual override (suggested_champion_ids) still takes precedence', () => {
  assert.match(body, /IF v_suggestions IS NOT NULL AND cardinality\(v_suggestions\) > 0 THEN[\s\S]*?m\.id = ANY\(v_suggestions\)[\s\S]*?RETURN;/i, 'manual list returned first, then RETURN');
});

test('p277 F3: derived path = present members ranked by cycle contribution, excludes self', () => {
  assert.match(body, /FROM public\.attendance a\s+JOIN public\.members m ON m\.id = a\.member_id/i, 'derives from attendance');
  assert.match(body, /a\.present = true/i, 'only present members (award_champion needs present)');
  assert.match(body, /LATERAL \(\s*SELECT COALESCE\(SUM\(gp\.points\), 0\) AS cyc_pts[\s\S]*?gp\.created_at >= COALESCE\(v_cycle_start/i, 'ranks by current-cycle contribution');
  assert.match(body, /ORDER BY sig\.cyc_pts DESC, m\.name\s+LIMIT 12/i, 'top-12 by contribution');
  assert.match(body, /m\.id <> v_caller_id/i, 'excludes the caller (no self-award)');
});

// DB-gated: gate still fires for no-auth (service-role auth.uid() is null)
test('p277 F3 DB: denies without auth (gate intact)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { error } = await sb.rpc('get_event_champion_suggestions', { p_event_id: '00000000-0000-0000-0000-000000000000' });
  assert.ok(error, 'no-auth caller must be rejected (member not found)');
});
