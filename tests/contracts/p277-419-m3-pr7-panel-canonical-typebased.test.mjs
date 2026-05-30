/**
 * Contract: p277 / #419 (ADR-0100) metric 3 — PR7: get_attendance_panel → canonical type-based; drop orphan summary.
 *
 * PM decision B (2026-05-29): TYPE-BASED (_attendance_eligible_events) is the canonical Participação model.
 * get_attendance_panel was the last surface on a divergent model (tag-candidate + event_audience_rules eligibility
 * → operational avg 70.5% vs the canonical 76.2%). Rewritten onto _attendance_eligible_events; the 18-col TABLE
 * shape + D2 gate + privileged/own-row visibility + C+B cohort aggregate preserved verbatim. get_attendance_summary
 * (orphan since PR5a) DROPPED.
 *
 * Live smoke (MEASURED): panel operational avg 70.5 → 76.2 (== home calc_attendance_pct 76.2 == engagement_global
 * 76.19). Roberto Macêdo (curator, excluded from the old panel's mandatory denom) 0 → 22.2 (now consistent with
 * home/member-detail). Non-priv researcher (Ligia) gets exactly 1 own row + own_combined 94.7 / cohort_avg 76.2 /
 * cohort_size 40 / percentile 92. anon → 0 rows. summary gone. Phase-C md5 file==live (25a00caced…).
 *
 * Migration: supabase/migrations/20260805000074_p277_419_m3_pr7_panel_canonical_typebased.sql
 * Cross-ref: SPEC_419_M3_ATTENDANCE_TWO_METRIC.md §5 surfaces 2/11 + §7 PR7 + the Canonical Principle section.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000074_p277_419_m3_pr7_panel_canonical_typebased.sql');
const SPEC = resolve(ROOT, 'docs/specs/SPEC_419_M3_ATTENDANCE_TWO_METRIC.md');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const code = body.replace(/--[^\n]*/g, '');
const spec = existsSync(SPEC) ? readFileSync(SPEC, 'utf8') : '';

test('m3 PR7: get_attendance_panel converges onto _attendance_eligible_events (same 18-col shape)', () => {
  assert.ok(existsSync(MIG), 'migration exists');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_attendance_panel\(p_cycle_start date DEFAULT NULL::date, p_cycle_end date DEFAULT NULL::date\)/);
  // canonical eligibility source, per-member, replaces the dead tag/audience-rule selection
  assert.match(code, /CROSS JOIN LATERAL public\._attendance_eligible_events\(a\.id, p_cycle_start\) el/);
  // 18-col shape preserved (spot-check the full TABLE signature is intact)
  assert.match(body, /RETURNS TABLE\(member_id uuid, member_name text, tribe_name text, tribe_id integer, operational_role text,[\s\S]*cohort_avg_pct numeric, cohort_percentile numeric, cohort_size integer\)/);
  // general bucket = non-tribo eligible, tribe bucket = tribo eligible; excused excluded (D1)
  assert.match(code, /FILTER \(WHERE el\.event_type <> 'tribo' AND att\.excused IS NOT TRUE\)/);
  assert.match(code, /FILTER \(WHERE el\.event_type =  'tribo' AND att\.present = true\)/);
});

test('m3 PR7: the dead tag/audience-rule model is fully removed (no general_meeting/tribe_meeting/is_event_mandatory)', () => {
  assert.ok(!/general_meeting|tribe_meeting/.test(code), 'panel no longer selects events by tag');
  assert.ok(!/is_event_mandatory_for_member/.test(code), 'panel no longer delegates to the audience-rule helper');
  assert.ok(!/event_tag_assignments|event_audience_rules/.test(code), 'no tag/audience-rule tables referenced');
});

test('m3 PR7: D2 gate + privileged/own-row visibility + C+B cohort aggregate preserved', () => {
  assert.match(code, /WHERE m\.auth_id = auth\.uid\(\) AND m\.is_active = true/, 'D2 active-member gate');
  assert.match(code, /v_privileged := public\.can_by_member\(v_caller_id, 'manage_event'\)/);
  assert.match(code, /WHERE v_privileged OR c\.id = v_caller_id/, 'non-privileged caller gets only own row');
  // C+B anonymous aggregate columns still computed only for the non-privileged caller's own row
  assert.match(code, /CASE WHEN NOT v_privileged AND c\.id = v_caller_id THEN \(SELECT avg_pct FROM cohort\)/);
  assert.match(code, /CASE WHEN NOT v_privileged AND c\.id = v_caller_id THEN \(SELECT sz FROM cohort\)/);
  // no GRANT/REVOKE — CREATE OR REPLACE preserves the existing ACL (panel is called by authenticated users)
  assert.ok(!/GRANT|REVOKE/.test(code), 'no grant churn (preserve existing ACL for authenticated callers)');
});

test('m3 PR7 (review MED): C+B cohort population == canonical engagement cohort (not the looser active+eligible set)', () => {
  // The anonymous peer aggregate (cohort/caller CTEs) must filter to current_cycle_active + the operational union,
  // so the non-privileged standing card's cohort_avg matches the public home headline 76.2 (was 53.7 over 50 ppl).
  // All 3 cohort-defining clauses (cohort, caller numerator, caller denominator) carry the canonical filter.
  const canonicalFilter = /c(?:2|3)?\.cca = true AND c(?:2|3)?\.op_role IN \('researcher','tribe_leader','manager'\)/g;
  const hits = code.match(canonicalFilter) || [];
  assert.ok(hits.length >= 3, `canonical cohort filter on all 3 cohort clauses (found ${hits.length})`);
  // current_cycle_active threaded through active → computed for the filter to reference
  assert.match(code, /m\.current_cycle_active AS cca/);
  assert.match(code, /SELECT a\.id, a\.m_name, a\.t_name, a\.t_id, a\.op_role, a\.is_curator, a\.cca/);
});

test('m3 PR7: orphan get_attendance_summary dropped', () => {
  assert.match(body, /DROP FUNCTION IF EXISTS public\.get_attendance_summary\(date, date, integer\)/);
  assert.match(body, /NOTIFY\s+pgrst/);
});

test('m3 PR7: SPEC documents the canonical-eligibility principle (prerequisite for future metrics)', () => {
  assert.ok(existsSync(SPEC), 'SPEC exists');
  assert.match(spec, /CANONICAL/i, 'SPEC has a canonical principle section');
  assert.match(spec, /_attendance_eligible_events/, 'SPEC names the single eligibility source');
  // the prohibition on parallel models
  assert.ok(/tag-based|general_meeting|audience.rule/i.test(spec), 'SPEC names the prohibited parallel model(s)');
});

// ── DB-gated ──────────────────────────────────────────────────────────────────
test('m3 PR7 DB: panel auth gate intact (unauthenticated service-role → 0 rows)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('get_attendance_panel');
  // service-role has no auth.uid() member → D2 gate returns 0 rows (not an error)
  assert.ok(!error, error?.message);
  assert.ok(Array.isArray(data) && data.length === 0, 'no-member caller gets empty result');
});

test('m3 PR7 DB: get_attendance_summary no longer exists (dropped)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { error } = await sb.rpc('get_attendance_summary', { p_cycle_start: '2026-03-01', p_cycle_end: '2026-06-30', p_tribe_id: null });
  assert.ok(error, 'calling the dropped function must error (function does not exist)');
});
