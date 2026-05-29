/**
 * Contract: p277 / #419 (ADR-0100) metric 2 — v_active_members canonical view + first converges.
 *
 * Canonical active member = is_active AND current_cycle_active (live 52). A discovery sweep found
 * ~10 org-level active-member computations; this ships the canonical VIEW and converges the 3
 * smallest REAL drifts (is_active-only → 53) onto it: get_platform_usage, get_sustainability_projections,
 * get_pilot_metrics (53→52). The legacy public.active_members view (is_active-only, consumed by
 * BoardEngine/AttendanceForm) is intentionally NOT touched (v_ prefix avoids the collision).
 *
 * Live smoke: v_active_members=52, legacy active_members=53 (untouched), platform_usage.members 53→52.
 *
 * Migration: supabase/migrations/20260805000062_p277_419_v_active_members_and_converge.sql
 * Cross-ref: ADR-0100 §2.2/§2.3 · audit D5. Deferred metric-2 sites (cycle_report/adoption/org_chart/
 * exec_cycle_report/executive_kpis + 2 frontend + legacy-view reconciliation + chapter member_status
 * PM decision) tracked in #419.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000062_p277_419_v_active_members_and_converge.sql');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

test('p277/#419 m2: v_active_members view = canonical predicate, anon revoked', () => {
  assert.ok(existsSync(MIG));
  assert.match(body, /CREATE OR REPLACE VIEW public\.v_active_members AS[\s\S]*?WHERE is_active = true AND current_cycle_active = true/i, 'canonical 2-predicate view');
  assert.match(body, /REVOKE ALL ON public\.v_active_members FROM PUBLIC, anon/i, 'not exposed to anon');
  assert.match(body, /GRANT SELECT ON public\.v_active_members TO authenticated, service_role/i);
  assert.match(body, /NOTIFY\s+pgrst/i);
});

test('p277/#419 m2: legacy public.active_members view is NOT touched (name-collision guard)', () => {
  // must not create/replace/drop the legacy (non-v_) active_members view
  assert.ok(!/CREATE OR REPLACE VIEW public\.active_members\b/i.test(body), 'must not clobber legacy active_members');
  assert.ok(!/DROP VIEW[^;]*\bactive_members\b/i.test(body.replace(/v_active_members/gi, '')), 'must not drop the legacy view');
});

test('p277/#419 m2: the 3 real-drift RPCs read count(*) FROM v_active_members', () => {
  const occ = (body.match(/count\(\*\)[\s\S]{0,40}?FROM public\.v_active_members/gi) || []).length;
  assert.ok(occ >= 3, `get_platform_usage + get_sustainability_projections + get_pilot_metrics must count from the view; found ${occ}`);
  for (const fn of ['get_platform_usage', 'get_sustainability_projections', 'get_pilot_metrics']) {
    assert.match(body, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}\\b`, 'i'), `${fn} converged`);
  }
});

test('p277/#419 m2 forward-defense: converged RPCs no longer headcount via is_active alone', () => {
  // the old "FROM members WHERE is_active" (standalone, no current_cycle_active) headcount must be gone
  assert.ok(!/FROM members WHERE is_active;/i.test(body), 'platform_usage must not count is_active-only');
  assert.ok(!/FROM public\.members WHERE is_active = true;/i.test(body), 'sustainability must not count is_active-only');
  // pilot adoption denominator must be canonical (both predicates), not is_active alone
  assert.match(body, /FILTER \(WHERE is_active = true AND current_cycle_active = true\)/i, 'pilot adoption denominator uses canonical predicate');
});

// DB-gated
test('p277/#419 m2 DB: v_active_members == canonical count AND distinct from legacy view', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { count: vCount, error } = await sb.from('v_active_members').select('id', { count: 'exact', head: true });
  assert.ok(!error, error?.message);
  const { count: canonical } = await sb.from('members').select('id', { count: 'exact', head: true })
    .eq('is_active', true).eq('current_cycle_active', true);
  assert.equal(vCount, canonical, 'v_active_members must equal the canonical predicate count');
  const { count: legacy } = await sb.from('members').select('id', { count: 'exact', head: true }).eq('is_active', true);
  // legacy (is_active-only) can be >= canonical; they are conceptually distinct
  assert.ok((legacy || 0) >= (vCount || 0), 'is_active-only base must be >= canonical (current-cycle subset)');
});
