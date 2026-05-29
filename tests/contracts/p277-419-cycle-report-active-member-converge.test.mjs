/**
 * Contract: p277 / #419 (ADR-0100) metric 2 continuation — get_cycle_report org-level active converge.
 *
 * get_cycle_report computed members.active (FILTER is_active = 53) + members.by_role (FROM members
 * WHERE is_active) with the is_active-ONLY base — the +1 real drift (audit D5). Converges both onto
 * the canonical v_active_members view (52); the view gains an append-only operational_role column so
 * by_role can group on it from the canonical set. tribes[].member_count (tribe-scoped roster, = #419
 * step 4) + observers/alumni (member_status lifecycle buckets) are deliberately LEFT ALONE.
 *
 * Live smoke (as Vitor / view_internal_analytics): members.active 53→52; by_role sums to exactly 52
 * (researcher 29 + tribe_leader 6 + sponsor 5 + observer 5 + chapter_liaison 3 + manager 2 + guest 2).
 *
 * Migration: supabase/migrations/20260805000063_p277_419_cycle_report_active_member_converge.sql
 * Cross-ref: ADR-0100 §2.2/§2.3 · audit D5 · migration 062 (the view + first 3 converges).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000063_p277_419_cycle_report_active_member_converge.sql');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

test('p277/#419 m2-cont: v_active_members gains operational_role (append-only, predicate preserved)', () => {
  assert.ok(existsSync(MIG));
  assert.match(body, /CREATE OR REPLACE VIEW public\.v_active_members AS\s+SELECT id, organization_id, chapter, tribe_id, person_id, operational_role/i, 'operational_role appended at the end (CREATE OR REPLACE VIEW rule)');
  assert.match(body, /WHERE is_active = true AND current_cycle_active = true/i, 'canonical 2-predicate preserved');
  assert.match(body, /NOTIFY\s+pgrst/i);
});

test('p277/#419 m2-cont: get_cycle_report active + by_role read the canonical view', () => {
  assert.match(body, /'active', \(SELECT count\(\*\) FROM public\.v_active_members\)/i, 'org active = canonical view count');
  assert.match(body, /SELECT operational_role, count\(\*\) as cnt FROM public\.v_active_members GROUP BY operational_role/i, 'by_role groups the canonical set');
});

test('p277/#419 m2-cont: same-signature CREATE OR REPLACE (no DROP), SECDEF + empty search_path + gate preserved', () => {
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_cycle_report\(p_cycle integer DEFAULT 3\)/i);
  assert.ok(!/DROP FUNCTION/i.test(body), 'shape unchanged → no DROP');
  assert.match(body, /SECURITY DEFINER/i);
  assert.match(body, /SET search_path TO ''/i, 'empty search_path preserved (every ref fully-qualified public.X)');
  assert.match(body, /can_by_member\(v_caller_id, 'view_internal_analytics'\)/i, 'auth gate preserved');
});

test('p277/#419 m2-cont forward-defense: tribe roster + lifecycle buckets NOT converged', () => {
  // tribes[].member_count is a DIFFERENT metric (#419 step 4) — must stay tribe-scoped is_active
  assert.match(body, /WHERE tribe_id = t\.id AND is_active/i, 'tribe member_count stays tribe-scoped is_active');
  // observers/alumni are member_status lifecycle buckets (ADR-0100 §7), not the active-member headcount
  assert.match(body, /'observers', count\(\*\) FILTER \(WHERE member_status = 'observer'\)/i);
  assert.match(body, /'alumni', count\(\*\) FILTER \(WHERE member_status = 'alumni'\)/i);
  // the org-level 'active' must NO LONGER be an inline is_active FILTER (it now reads the view)
  assert.ok(!/'active',\s*count\(\*\) FILTER \(WHERE is_active\)/i.test(body), 'org active no longer FILTER is_active inline');
});

// ── DB-gated ──────────────────────────────────────────────────────────────────
test('p277/#419 m2-cont DB: view exposes operational_role + row count == canonical active (the value active reads)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.from('v_active_members').select('id, operational_role').limit(1000);
  assert.ok(!error, error?.message);
  assert.ok(data.length > 0 && Object.prototype.hasOwnProperty.call(data[0], 'operational_role'), 'view exposes operational_role');
  const { count: canonical } = await sb.from('members').select('id', { count: 'exact', head: true })
    .eq('is_active', true).eq('current_cycle_active', true);
  assert.equal(data.length, canonical, 'view row count == canonical active count (get_cycle_report.active = SELECT count(*) FROM this view)');
});

test('p277/#419 m2-cont DB: get_cycle_report gate intact (unauthenticated service-role rejected)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { error } = await sb.rpc('get_cycle_report', { p_cycle: 4 });
  assert.ok(error, 'no-auth caller must be rejected (view_internal_analytics gate, auth.uid() null)');
});
