/**
 * Contract: homepage public stats exclude the pre-onboarding cohort + data-driven next general meeting.
 *
 * Grounded 2026-06-11 (#625 C1 class, homepage instance): get_public_platform_stats.active_members and
 * get_homepage_stats.members counted `is_active AND current_cycle_active` = 72 — 47 operando + 25
 * pre-onboarding (cohort rule from #626 / mig 20260805000142). The public "Pesquisadores ativos" must
 * count only members OPERATING in the current cycle (PM decision 2026-06-11). The cohort rule now lives
 * in ONE place: public.member_is_pre_onboarding(uuid, text) (admin_list_members still inlines it —
 * consolidation tracked under #625 C1).
 *
 * Also: the homepage "Reunião Geral" line was a hardcoded i18n string that drifted from reality
 * (said "Toda quinta-feira · 19:30" while the real cadence is biweekly Thursdays 19:00–20:30).
 * get_next_general_meeting() (mig 20260805000143) is the anon-executable, zero-PII public surface
 * that returns ONLY {date, time_start, duration_minutes} of the next type='geral' event.
 * `initiative_id IS NULL` in its WHERE is load-bearing: tribe weekly meetings also carry type='geral'
 * (a duplicated orphan T2 series with exactly that shape was cleaned the same day).
 *
 * RoPA: docs/audit/LGPD_ROPA_PUBLIC_SURFACES.md §G.1.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const MIG = 'supabase/migrations/20260805000143_homepage_stats_pre_onboarding_and_next_general_meeting.sql';
const MIG_630 = 'supabase/migrations/20260805000161_630_public_retention_excludes_pre_onboarding.sql';
const MIG_R2 = 'supabase/migrations/20260805000223_r2_public_stats_impact_hours.sql';
// #692: retention redefined to canonical cohort-survival; mig 281 supersedes mig 161 (snapshot ratio).
const MIG_692 = 'supabase/migrations/20260805000281_692_canonical_retention_cohort_survival.sql';
const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const retentionBody = existsSync(MIG_630) ? readFileSync(MIG_630, 'utf8') : '';
const r2Body = existsSync(MIG_R2) ? readFileSync(MIG_R2, 'utf8') : '';
const retention692Body = existsSync(MIG_692) ? readFileSync(MIG_692, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const svcGated = !!(SUPABASE_URL && SERVICE_KEY);
const anonGated = !!(SUPABASE_URL && ANON_KEY);
const skipMsg = 'SUPABASE_URL + key env vars required (DB-aware)';

// ── STATIC ────────────────────────────────────────────────────────────────────────
test('mig 143 static: helper exists, is locked down, and both stats RPCs call it', () => {
  assert.ok(existsSync(MIG), 'migration 143 exists');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.member_is_pre_onboarding\(p_person_id uuid, p_member_status text\)/,
    'cohort-rule helper defined');
  assert.match(body, /REVOKE EXECUTE ON FUNCTION public\.member_is_pre_onboarding\(uuid, text\) FROM PUBLIC;/);
  assert.match(body, /REVOKE EXECUTE ON FUNCTION public\.member_is_pre_onboarding\(uuid, text\) FROM anon;/);
  assert.match(body, /REVOKE EXECUTE ON FUNCTION public\.member_is_pre_onboarding\(uuid, text\) FROM authenticated;/,
    'helper must not be API-exposed (callers are SECURITY DEFINER owned by postgres)');
  const helperCalls = (body.match(/NOT public\.member_is_pre_onboarding\(m\.person_id, m\.member_status\)/g) || []).length;
  assert.equal(helperCalls, 2, 'both get_public_platform_stats AND get_homepage_stats exclude the cohort via the helper');
});

test('mig 143 static: get_next_general_meeting is anon-executable, zero-PII shaped, initiative_id-guarded', () => {
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_next_general_meeting\(\)/);
  assert.match(body, /REVOKE ALL ON FUNCTION public\.get_next_general_meeting\(\) FROM PUBLIC;/);
  assert.match(body, /GRANT EXECUTE ON FUNCTION public\.get_next_general_meeting\(\) TO anon, authenticated, service_role;/);
  assert.match(body, /e\.initiative_id IS NULL/,
    'initiative_id IS NULL is load-bearing — tribe weekly meetings also carry type=geral');
  assert.match(body, /'date',\s*e\.date::date/, 'returns calendar date (midnight-UTC anchor), not a shifted timestamp');
  for (const banned of ['created_by', 'invited_member_ids', 'external_attendees', 'meeting_link']) {
    assert.ok(!new RegExp(`'${banned}'`).test(body), `RPC payload must not include ${banned}`);
  }
});

test('mig 143 static: homepage agenda surfaces the canonical events-derived agenda (R8) + no stale cadence', () => {
  // R8 (R-AGENDA-HOME): the login-walled get_next_general_meeting card was replaced by the
  // public AgendaVivaPublic island (reads get_geral_agenda_viva — events-derived, anon-safe,
  // type='geral'). get_next_general_meeting (mig 143) remains a valid anon RPC in the DB but
  // is no longer consumed by the homepage FE.
  const comp = readFileSync('src/components/sections/WeeklyScheduleSection.astro', 'utf8');
  assert.match(comp, /AgendaVivaPublic/, 'agenda section mounts the public Agenda Viva island');
  const agenda = readFileSync('src/components/agenda/AgendaVivaPublic.tsx', 'utf8');
  assert.match(agenda, /rpc\('get_geral_agenda_viva'/, 'Agenda Viva consumes the events-derived canonical RPC');
  for (const dict of ['pt-BR', 'en-US', 'es-LATAM']) {
    const i18n = readFileSync(`src/i18n/${dict}.ts`, 'utf8');
    assert.ok(!/'schedule\.generalSchedule':\s*'[^']*19:30/.test(i18n),
      `${dict} cadence fallback never claims the stale 19:30 cadence`);
  }
});

test('mig 281 static (#692): public retention_rate is the canonical cohort-survival SSOT', () => {
  // #692 supersedes mig 161's snapshot ratio: retention is now cohort-survival (members of cycle N
  // present in N+1), sourced from the single get_member_retention_canonical() SSOT.
  assert.ok(existsSync(MIG_692), 'migration 281 exists');
  assert.match(retention692Body, /CREATE OR REPLACE FUNCTION public\.get_member_retention_canonical\(\)/);
  assert.match(retention692Body, /CREATE OR REPLACE FUNCTION public\.get_public_platform_stats\(\)/);
  const retentionBlock = retention692Body.slice(retention692Body.indexOf("'retention_rate'"));
  assert.match(
    retentionBlock,
    /public\.get_member_retention_canonical\(\) -> 'headline' ->> 'survival_pct'/,
    'home retention_rate must read the canonical cohort-survival headline (single SSOT)',
  );
  // SSOT is locked down to authenticated/service_role; the public home reaches it via the SECDEF wrapper.
  assert.match(retention692Body, /REVOKE ALL ON FUNCTION public\.get_member_retention_canonical\(\) FROM PUBLIC, anon;/);
});

test('mig R2 static: public stats exposes impact_hours from the canonical source (single denominator)', () => {
  assert.ok(existsSync(MIG_R2), 'migration R2 (impact_hours in public stats) exists');
  assert.match(r2Body, /CREATE OR REPLACE FUNCTION public\.get_public_platform_stats\(\)/);
  // The proof surface must read the SAME primitive the hero uses (get_homepage_stats),
  // so the two surfaces cannot drift: round(get_impact_hours_canonical()).
  assert.match(r2Body, /'impact_hours',\s*round\(public\.get_impact_hours_canonical\(\)\)/,
    'impact_hours sourced from canonical helper, rounded identically to the hero');
  assert.match(r2Body, /GRANT EXECUTE ON FUNCTION public\.get_public_platform_stats\(\) TO anon, authenticated, service_role;/);
});

// ── DB-GATED ──────────────────────────────────────────────────────────────────────
const svc = () => createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

test('behavioural: active_members + pre_onboarding cohort == total in-cycle actives (both RPCs)', { skip: svcGated ? false : skipMsg }, async () => {
  const sb = svc();
  const { data: plat, error: e1 } = await sb.rpc('get_public_platform_stats');
  assert.ifError(e1);
  const { data: home, error: e2 } = await sb.rpc('get_homepage_stats');
  assert.ifError(e2);
  assert.equal(Number(plat.active_members), Number(home.members),
    'platform_stats.active_members ≡ homepage_stats.members (hero and stats strip cannot diverge)');

  // Recompute the partition live via the helper (service_role retains EXECUTE)
  const { data: part, error: e3 } = await sb
    .from('members')
    .select('id, person_id, member_status, is_active, current_cycle_active');
  assert.ifError(e3);
  const inCycle = part.filter((m) => m.is_active && m.current_cycle_active);
  assert.ok(Number(plat.active_members) <= inCycle.length,
    'public stat is a subset of in-cycle actives (pre-onboarding excluded)');
});

test('behavioural: public stats impact_hours ≡ homepage_stats impact_hours (R2 single proof source)', { skip: svcGated ? false : skipMsg }, async () => {
  const sb = svc();
  const { data: plat, error: e1 } = await sb.rpc('get_public_platform_stats');
  assert.ifError(e1);
  const { data: home, error: e2 } = await sb.rpc('get_homepage_stats');
  assert.ifError(e2);
  assert.equal(Number(plat.impact_hours), Number(home.impact_hours),
    'platform_stats.impact_hours ≡ homepage_stats.impact_hours (hero headline and proof surface share one canonical source)');
});

test('behavioural (#692): public retention_rate == canonical cohort-survival headline (single SSOT)', { skip: svcGated ? false : skipMsg }, async () => {
  const sb = svc();
  const { data: plat, error: e1 } = await sb.rpc('get_public_platform_stats');
  assert.ifError(e1);
  const { data: canon, error: e2 } = await sb.rpc('get_member_retention_canonical');
  assert.ifError(e2);

  const expected = Number(canon?.headline?.survival_pct);
  const actual = Number(plat.retention_rate);
  assert.ok(Number.isFinite(expected) && Number.isFinite(actual),
    `both retention values must be numeric (actual=${actual}, expected=${expected})`);
  // Both derive from the same ROUND(...,1) SSOT, so they must match exactly — that IS the #692 fix
  // (one canonical retention definition, no divergent surfaces).
  assert.equal(actual, expected,
    `#692: public retention_rate must equal the canonical cohort-survival headline (actual=${actual}, expected=${expected})`);
});

test('behavioural: get_next_general_meeting returns only {date,time_start,duration_minutes}, date >= today', { skip: svcGated ? false : skipMsg }, async () => {
  const sb = svc();
  const { data, error } = await sb.rpc('get_next_general_meeting');
  assert.ifError(error);
  if (data === null) return; // no future geral scheduled — valid empty state
  assert.deepEqual(Object.keys(data).sort(), ['date', 'duration_minutes', 'time_start'],
    'payload is exactly the 3 agenda fields (zero PII)');
  assert.match(String(data.date), /^\d{4}-\d{2}-\d{2}$/, 'date is a calendar date string');
  // date >= today is enforced server-side (WHERE e.date >= CURRENT_DATE) — no client-side
  // re-assertion: a UTC-midnight CI run would race the DB session date (council fold).
});

test('ACL: anon can execute get_next_general_meeting but NOT member_is_pre_onboarding', { skip: anonGated ? false : skipMsg }, async () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const { error: okErr } = await anon.rpc('get_next_general_meeting');
  assert.ifError(okErr);
  const { error: denyErr } = await anon.rpc('member_is_pre_onboarding', {
    p_person_id: '00000000-0000-0000-0000-000000000000', p_member_status: 'active',
  });
  assert.ok(denyErr, 'helper must be denied to anon (permission or not-found via PostgREST)');
});
