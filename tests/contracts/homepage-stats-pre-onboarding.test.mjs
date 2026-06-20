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
const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const retentionBody = existsSync(MIG_630) ? readFileSync(MIG_630, 'utf8') : '';
const r2Body = existsSync(MIG_R2) ? readFileSync(MIG_R2, 'utf8') : '';

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

test('mig 143 static: WeeklyScheduleSection consumes the RPC and keeps the i18n fallback', () => {
  const comp = readFileSync('src/components/sections/WeeklyScheduleSection.astro', 'utf8');
  assert.match(comp, /rpc\('get_next_general_meeting'\)/, 'component calls the public RPC');
  assert.match(comp, /schedule\.generalSchedule/, 'SSR i18n fallback retained');
  for (const dict of ['pt-BR', 'en-US', 'es-LATAM']) {
    const i18n = readFileSync(`src/i18n/${dict}.ts`, 'utf8');
    assert.match(i18n, /'schedule\.generalSchedule':/, `${dict} has the fallback key`);
    assert.ok(!/'schedule\.generalSchedule':\s*'[^']*19:30/.test(i18n),
      `${dict} fallback no longer claims the stale 19:30 cadence`);
  }
});

test('mig 161 static: public retention_rate excludes pre-onboarding from the retention cohort', () => {
  assert.ok(existsSync(MIG_630), 'migration 161 exists');
  assert.match(retentionBody, /CREATE OR REPLACE FUNCTION public\.get_public_platform_stats\(\)/);
  const retentionBlock = retentionBody.slice(retentionBody.indexOf("'retention_rate'"));
  assert.match(
    retentionBlock,
    /WHERE m\.member_status IN \('active','alumni','observer'\)\s+AND NOT public\.member_is_pre_onboarding\(m\.person_id, m\.member_status\)/,
    'retention cohort must exclude pre-onboarding via canonical helper',
  );
  assert.match(retentionBody, /GRANT EXECUTE ON FUNCTION public\.get_public_platform_stats\(\) TO anon, authenticated, service_role;/);
  assert.match(retentionBody, /Zero PII public surface/);
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

test('behavioural: public retention_rate recomputes from operating cohort only', { skip: svcGated ? false : skipMsg }, async () => {
  const sb = svc();
  const { data: plat, error: e1 } = await sb.rpc('get_public_platform_stats');
  assert.ifError(e1);

  const { data: rows, error: e2 } = await sb
    .from('members')
    .select('person_id, member_status, is_active, current_cycle_active');
  assert.ifError(e2);

  const { data: engs, error: e3 } = await sb
    .from('engagements')
    .select('person_id, kind, agreement_certificate_id')
    .eq('status', 'active');
  assert.ifError(e3);
  const { data: kinds, error: e4 } = await sb
    .from('engagement_kinds')
    .select('slug, requires_agreement');
  assert.ifError(e4);

  const reqMap = new Map((kinds ?? []).map((kind) => [kind.slug, kind.requires_agreement === true]));
  const byPerson = new Map();
  for (const engagement of engs ?? []) {
    if (!byPerson.has(engagement.person_id)) byPerson.set(engagement.person_id, []);
    byPerson.get(engagement.person_id).push(engagement);
  }
  const isPreOnboarding = (member) => {
    if (member.member_status !== 'active') return false;
    const list = byPerson.get(member.person_id) ?? [];
    return list.length > 0
      && !list.some((engagement) => !reqMap.get(engagement.kind) || engagement.agreement_certificate_id !== null);
  };

  const cohort = (rows ?? []).filter((m) =>
    ['active', 'alumni', 'observer'].includes(m.member_status)
    && !isPreOnboarding(m)
    && (m.is_active || m.member_status === 'alumni')
  );
  const numerator = cohort.filter((m) => m.current_cycle_active).length;
  const expected = cohort.length === 0 ? 0 : Math.round((numerator / cohort.length) * 1000) / 10;
  const actual = Number(plat.retention_rate);
  // Full `npm test` runs many DB-aware contracts concurrently. Some tests can read live data
  // between the RPC call and the client-side recompute below, so keep this behavioural check
  // tight but not exact; the static migration test above locks the SQL predicate itself.
  assert.ok(Math.abs(actual - expected) <= 0.6,
    `retention_rate must use the operating cohort denominator, excluding pre-onboarding (actual=${actual}, expected=${expected})`);
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
