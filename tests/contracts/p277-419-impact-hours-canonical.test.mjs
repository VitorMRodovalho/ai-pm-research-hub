/**
 * Contract: p277 / #419 (ADR-0100) metric 1 — impact_hours converges onto the canonical source.
 *
 * get_homepage_stats had its OWN inline impact_hours formula (audit D4: incl 60-min fallback,
 * hardcoded '2026-01-01', ROUND 0, no excused exclusion) — a 4th variant that disagreed with the
 * canonical get_impact_hours_canonical used by the KpiSection card + Admin KPI. Now it calls the
 * canonical (round() keeps the integer hero display; cycle_report inherits → auto-converges).
 *
 * This is the FIRST metric of the #419 canonical-metrics program; the forward-defense assertion is
 * the ADR-0100 §2C gate ("no inline re-implementation of a canonical metric") applied to impact_hours.
 *
 * Migration: supabase/migrations/20260805000061_p277_419_impact_hours_canonical_homepage.sql
 * Cross-ref: ADR-0100 §2.3/§3.2 · ADR-0096 (canonical) · docs/audit/METRIC_DISPARITY_AUDIT_2026-05-28.md (D4).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000061_p277_419_impact_hours_canonical_homepage.sql');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

test('p277/#419: migration exists + same-signature CREATE OR REPLACE + NOTIFY', () => {
  assert.ok(existsSync(MIG));
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_homepage_stats\(\)/i);
  assert.ok(!/DROP FUNCTION/i.test(body), 'no DROP (same signature)');
  assert.match(body, /NOTIFY\s+pgrst/i);
});

test('p277/#419: impact_hours reads the canonical source', () => {
  assert.match(body, /'impact_hours',\s*round\(public\.get_impact_hours_canonical\(\)\)/i, 'impact_hours must call get_impact_hours_canonical');
});

test('p277/#419 forward-defense: NO inline re-implementation of the impact_hours formula (ADR-0100 §2C gate)', () => {
  // the old inline formula's fingerprints must be gone from get_homepage_stats
  assert.ok(!/duration_actual,\s*e\.duration_minutes,\s*60/i.test(body), 'must not re-introduce the 60-min-fallback inline sum');
  assert.ok(!/\*\s*\(SELECT count\(\*\) FROM attendance a WHERE a\.event_id = e\.id AND a\.present\)/i.test(body), 'must not re-introduce the inline present-attendee multiplication');
  assert.ok(!/e\.date >= '2026-01-01'/i.test(body), 'must not re-introduce the hardcoded-literal window');
});

test('p277/#419 DB: homepage impact_hours == round(canonical) (converged)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: stats, error } = await sb.rpc('get_homepage_stats');
  assert.ok(!error, error?.message);
  const { data: canon, error: e2 } = await sb.rpc('get_impact_hours_canonical');
  assert.ok(!e2, e2?.message);
  assert.equal(Number(stats.impact_hours), Math.round(Number(canon)), 'homepage impact_hours must equal round(get_impact_hours_canonical())');
});
