/**
 * Contract: p277 / #419 (ADR-0100) metric 3 — PR8: repoint get_dropout_risk_members onto canonical eligibility (#420).
 *
 * The function was LIVE-BROKEN: it filtered events by 'general_meeting' / 'tribe_meeting' /
 * 'leadership_meeting' — none of which exist live (types are geral/tribo/lideranca/kickoff/…). The candidate
 * set collapsed to ~0 events so `missed >= p_threshold` was never true → it flagged NOBODY, and both consumers
 * (HomepageHero GP alert + workspace DropoutRiskBanner) were silently dead.
 *
 * Fix: source per-member eligible events from the single canonical primitive public._attendance_eligible_events
 * (SPEC §3b Canonical Eligibility Principle). The dropout semantic is preserved (flag = absent for ALL of the
 * last p_threshold eligible mandatory events) and EXCUSED is treated as NEUTRAL (D1 / get_attendance_engagement_rate
 * parity — the old body wrongly counted excused as a miss). 8-col shape + p_threshold + manage_event gate preserved.
 *
 * Live smoke (MEASURED, as a manage_event holder, threshold 3): 0 flagged (antes) → 4 flagged (depois): Maria Luiza
 * (T8), Andressa Martins (T2), Gustavo Batista Ferreira (T2), Débora Moura (T2-leader). Two T4 researchers excused
 * in-window correctly do NOT flag. Phase-C md5 file==live (d1005d83105095a9fae313ff64956eca). Invariants 23/23=0.
 *
 * Also folds the home-hero attendance dead-read: HomepageHero read `tribe_events_count ?? tribe_total` (neither
 * exists on get_attendance_panel post-PR7) → always '—'; repointed to the real `tribe_mandatory` column.
 *
 * Migration: supabase/migrations/20260805000075_p277_419_m3_pr8_dropout_risk_canonical.sql
 * Cross-ref: SPEC_419_M3_ATTENDANCE_TWO_METRIC.md §5 surface 11 + §7 PR8; ADR-0100; issue #420.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000075_p277_419_m3_pr8_dropout_risk_canonical.sql');
const SPEC = resolve(ROOT, 'docs/specs/SPEC_419_M3_ATTENDANCE_TWO_METRIC.md');
const HERO = resolve(ROOT, 'src/components/sections/HomepageHero.astro');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const code = body.replace(/--[^\n]*/g, '');           // strip SQL line-comments for body asserts
const spec = existsSync(SPEC) ? readFileSync(SPEC, 'utf8') : '';
const hero = existsSync(HERO) ? readFileSync(HERO, 'utf8') : '';

test('m3 PR8: same signature + 8-col shape preserved (CREATE OR REPLACE, GC-097)', () => {
  assert.ok(existsSync(MIG), 'migration exists');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_dropout_risk_members\(p_threshold integer DEFAULT 3\)/);
  assert.match(body, /RETURNS TABLE\(member_id uuid, member_name text, tribe_id integer, tribe_name text, operational_role text, last_attendance_date date, days_since_last bigint, missed_events integer\)/);
  assert.match(body, /STABLE SECURITY DEFINER/);
  assert.match(body, /SET search_path TO ''/);
});

test('m3 PR8: eligibility repointed onto the canonical primitive with the canonical (NULL) cycle window', () => {
  assert.match(code, /CROSS JOIN LATERAL public\._attendance_eligible_events\(am\.id, NULL\) el/);
  // no hardcoded cycle-window date literal — the window comes from cycles.is_current inside the primitive
  assert.ok(!/'20\d\d-\d\d-\d\d'/.test(code.replace(/DATE '2025-01-01'/g, '')),
    "no cycle-window date literal (the DATE '2025-01-01' days_since_last floor is the only allowed literal)");
});

test('m3 PR8: the dead event-type model is fully removed', () => {
  assert.ok(!/general_meeting|tribe_meeting|leadership_meeting/.test(code),
    'no nonexistent meeting types');
  // events has no tribe column — tribe scoping is delegated to the primitive (get_member_tribe), never e.tribe_id
  assert.ok(!/e\d*\.tribe_id/.test(code), 'no events.tribe_id reference');
});

test('m3 PR8: EXCUSED treated as neutral (D1 / engagement parity), not counted as a miss', () => {
  assert.match(code, /WHERE att\.excused IS NOT TRUE/, 'excused removed from the recent window');
  // present detection is the clean boolean (att.present IS TRUE), not the old "row exists" proxy
  assert.match(code, /\(att\.present IS TRUE\) AS was_present/);
  assert.match(code, /count\(\*\) FILTER \(WHERE NOT me\.was_present\) AS missed/);
});

test('m3 PR8: manage_event gate preserved + fail-closed; no anon grant', () => {
  assert.match(code, /public\.can_by_member\(v_caller_id, 'manage_event'\)/);
  assert.match(code, /IF v_caller_id IS NULL THEN\s*RETURN;/);          // unauthenticated → empty
  assert.ok(!/GRANT[\s\S]*\banon\b/.test(code), 'must never grant execute to anon (PII surface)');
});

test('m3 PR8: HomepageHero reads the real panel column (tribe_mandatory), not the dead tribe_events_count/tribe_total', () => {
  assert.ok(existsSync(HERO), 'HomepageHero exists');
  assert.match(hero, /const tribeEvents = myRow\.tribe_mandatory \?\? 0;/);
  assert.ok(!/tribe_events_count|tribe_total\b/.test(hero), 'dead panel-column reads removed');
});

test('m3 PR8: SPEC §7 documents the dropout completeness fix (#420)', () => {
  assert.ok(existsSync(SPEC), 'SPEC exists');
  assert.match(spec, /get_dropout_risk_members/, 'SPEC names the function');
  assert.ok(/live-broken|nonexistent event types|flags nobody/i.test(spec), 'SPEC describes the break');
});

// ── DB-gated ──────────────────────────────────────────────────────────────────
test('m3 PR8 DB: manage_event gate fail-closed (service-role / no member → 0 rows, no error)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('get_dropout_risk_members', { p_threshold: 3 });
  assert.ok(!error, error?.message);
  assert.ok(Array.isArray(data) && data.length === 0, 'no-member caller gets empty result (gate fail-closed)');
});

test('m3 PR8 DB: default p_threshold is accepted (no-arg call also gate-closes cleanly)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('get_dropout_risk_members');
  assert.ok(!error, error?.message);
  assert.ok(Array.isArray(data) && data.length === 0);
});
