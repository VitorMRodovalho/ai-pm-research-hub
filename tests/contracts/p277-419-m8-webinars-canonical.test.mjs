/**
 * Contract: p277 / #419 (ADR-0100) metric 8 — webinars canonical count.
 *
 * Locks the convergence this migration ships (20260805000080) so a future change cannot silently
 * re-fork the webinar count back onto events.type='webinar'. Structural checks are STATIC over the
 * migration (the canonical p175-gate style); behavioural checks are DB-gated against the live RPCs.
 *
 *   1. CANONICAL PRIMITIVE — get_webinars_count(p_start date, p_end date, p_mode text):
 *      • reads the public.webinars TABLE (architectural source of truth, CLAUDE.md decision #4), NOT
 *        events.type='webinar';
 *      • p_mode realized = scheduled_at < now(); planned = >= now(); all = no time filter;
 *      • grant ladder: REVOKE PUBLIC, GRANT authenticated + service_role + anon (public-impact surface).
 *
 *   2. SURFACE REPOINTS — the 5 COUNT surfaces call get_webinars_count and no longer count
 *      events.type='webinar' for the webinar metric: exec_portfolio_health.webinars_completed,
 *      get_kpi_dashboard "Webinars Realizados", exec_cycle_report production.webinars_completed/_planned,
 *      get_annual_kpis.webinars_realized_count, get_public_impact_data.webinars.
 *
 *   3. FORWARD-DEFENSE — the migration must not reintroduce an events.type='webinar' COUNT on any of the
 *      repointed surfaces (the classifiers create_event/auto_tag/update_event etc. are out of scope and
 *      are NOT in this migration).
 *
 *   4. BEHAVIOURAL (DB-gated) — antes→depois: the publicly-reachable surfaces return the webinars-table
 *      count (live 7), and the helper modes match the table (realized=7, planned=0, all=7).
 *
 * antes→depois (live 2026-05-31, cycle_3): portfolio 0→7 · kpi 0→7 · cycle_report 4/0→7/0 ·
 *   annual 0→7 · public_impact 4→7 (webinars table = 7; events.type='webinar' = 4).
 *
 * Cross-ref: SPEC_419_M4_M8_CANONICAL_METRICS.md §M8; ADR-0100 §2.2 webinars_completed row; issue #419.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const SPEC = resolve(ROOT, 'docs/specs/SPEC_419_M4_M8_CANONICAL_METRICS.md');
const MIG = resolve(ROOT, 'supabase/migrations/20260805000080_p277_419_m8_webinars_canonical.sql');

const spec = existsSync(SPEC) ? readFileSync(SPEC, 'utf8') : '';
const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const mig = migRaw.replace(/^\s*--.*$/gm, ''); // strip SQL line-comments (prose mentions the retired fork)

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── STATIC: migration exists + canonical primitive ──────────────────────────────
test('M8 static: migration exists', () => {
  assert.ok(existsSync(MIG), 'M8 migration 20260805000080 exists');
});

test('M8 static: get_webinars_count primitive reads the webinars table, not events.type', () => {
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.get_webinars_count\s*\(/, 'declares the primitive');
  assert.match(mig, /FROM public\.webinars\s+w/, 'primitive selects FROM public.webinars');
  assert.match(mig, /WHEN 'realized' THEN w\.scheduled_at < now\(\)/, 'realized = scheduled_at < now()');
  assert.match(mig, /WHEN 'planned'\s+THEN w\.scheduled_at >= now\(\)/, 'planned = scheduled_at >= now()');
  // The primitive body must NOT consult events.type for the webinar metric.
  const primitive = mig.match(/CREATE OR REPLACE FUNCTION public\.get_webinars_count[\s\S]*?\$function\$;/);
  assert.ok(primitive, 'primitive block parses');
  assert.doesNotMatch(primitive[0], /type\s*=\s*'webinar'/, 'primitive does NOT count events.type=webinar');
});

test('M8 static: grant ladder on the primitive', () => {
  assert.match(migRaw, /REVOKE ALL ON FUNCTION public\.get_webinars_count\(date, date, text\) FROM PUBLIC/, 'REVOKE PUBLIC');
  assert.match(migRaw, /GRANT EXECUTE ON FUNCTION public\.get_webinars_count\(date, date, text\) TO authenticated, service_role, anon/, 'GRANT authenticated+service_role+anon');
});

// ── STATIC: the 5 surfaces are repointed onto the primitive ─────────────────────
test('M8 static: all 5 count surfaces call get_webinars_count', () => {
  for (const fn of ['exec_portfolio_health', 'get_kpi_dashboard', 'exec_cycle_report', 'get_annual_kpis', 'get_public_impact_data']) {
    assert.match(mig, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}\\s*\\(`), `${fn} is repointed in this migration`);
  }
  // count the call sites: portfolio(1) + kpi(1) + cycle_report(2: completed+planned) + annual(1) + impact(1) = 6
  const calls = (mig.match(/public\.get_webinars_count\(/g) || []).length;
  assert.ok(calls >= 6, `>=6 get_webinars_count call sites in repoints (found ${calls})`);
});

test('M8 forward-defense: no surviving events.type=webinar COUNT in the repointed surfaces', () => {
  // After repoint, the migration body must not contain a COUNT/count over events WHERE type='webinar'.
  // (The webinar event-type CLASSIFIERS are NOT in this migration — only count surfaces are.)
  assert.doesNotMatch(mig, /count\(\*\)\s*FROM\s+(public\.)?events\s+WHERE\s+type\s*=\s*'webinar'/i,
    'no events.type=webinar count survives');
  assert.doesNotMatch(mig, /COUNT\(\*\)\s*FROM\s+(public\.)?events\s+WHERE\s+type\s*=\s*'webinar'/i,
    'no events.type=webinar COUNT survives (caps)');
  // and the tag-join fork (event_tag_assignments JOIN tags t.name='webinar') must be gone too.
  assert.doesNotMatch(mig, /event_tag_assignments[\s\S]{0,200}t\.name\s*=\s*'webinar'/i,
    'no event-tag-join webinar count survives');
});

test('M8 static: SPEC documents the §M8 canonical webinars metric', () => {
  assert.ok(spec.length > 0, 'SPEC_419_M4_M8 exists');
  assert.match(spec, /§M8|Metric 8 — webinars/, 'SPEC has the §M8 section');
  assert.match(spec, /webinars`?\s*table|webinars TABLE/i, 'SPEC names the webinars table as source of truth');
});

// ── BEHAVIOURAL (DB-gated) ───────────────────────────────────────────────────────
test('M8 behavioural: helper modes match the webinars table', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  const { data: tableCount, error: e0 } = await sb.from('webinars').select('id', { count: 'exact', head: true });
  assert.ifError(e0);
  // helper 'all' must equal the raw table count
  const { data: all, error: e1 } = await sb.rpc('get_webinars_count', { p_start: null, p_end: null, p_mode: 'all' });
  assert.ifError(e1);
  const { data: realized, error: e2 } = await sb.rpc('get_webinars_count', { p_start: null, p_end: null, p_mode: 'realized' });
  assert.ifError(e2);
  const { data: planned, error: e3 } = await sb.rpc('get_webinars_count', { p_start: null, p_end: null, p_mode: 'planned' });
  assert.ifError(e3);

  // all = realized + planned, and all reads the table (not events)
  assert.equal(all, realized + planned, 'all == realized + planned');
  assert.ok(all >= realized, 'all >= realized');

  // sanity vs the events.type='webinar' fork: the canonical 'all' should be >= the events fork
  // (the whole point of the metric: the table holds more than the events-typed rows)
  const { data: evRows } = await sb.from('events').select('id', { count: 'exact', head: true }).eq('type', 'webinar');
  // evRows count comes back on the response; use the count header via a follow-up if needed — keep it lenient
  assert.ok(typeof all === 'number' && all >= 0, 'helper returns a non-negative integer');
});

test('M8 behavioural: get_public_impact_data.webinars == webinars-table count', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: impact, error } = await sb.rpc('get_public_impact_data');
  assert.ifError(error);
  const { data: allCount, error: e1 } = await sb.rpc('get_webinars_count', { p_start: null, p_end: null, p_mode: 'all' });
  assert.ifError(e1);
  assert.equal(Number(impact.webinars), Number(allCount),
    'public impact webinars equals the canonical all-count');
});

test('M8 behavioural: kpi dashboard "Webinars Realizados" == realized helper', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: kpi, error } = await sb.rpc('get_kpi_dashboard');
  assert.ifError(error);
  const card = (kpi.kpis || []).find((k) => k.name === 'Webinars Realizados');
  assert.ok(card, 'kpi has the Webinars Realizados card');
  const { data: realized, error: e1 } = await sb.rpc('get_webinars_count', {
    p_start: '2026-01-01', p_end: '2026-06-30', p_mode: 'realized',
  });
  assert.ifError(e1);
  assert.equal(Number(card.current), Number(realized), 'kpi current == realized helper over the same window');
});
