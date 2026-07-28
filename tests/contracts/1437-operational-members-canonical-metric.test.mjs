/**
 * Contract: #1437 / #1354 / ADR-0126 — "Pesquisadores ativos" = the active RESEARCH TEAM (operational
 * tier), not the polluted Tema A active-system-user count.
 *
 * The home headline / admin KPI counted `is_active AND current_cycle_active AND NOT pre_onboarding` (= 87
 * live), which folded in chapter board / sponsors / external reviewers / observers who are NOT part of the
 * research operation. ADR-0126 splits "active member" into two metrics:
 *   Tema A — active system user      = is_active AND current_cycle_active            (v_active_members, ~89)
 *   Tema B — active research team    = Tema A ∧ operational_role IN {manager,          (v_operational_members, 68)
 *                                       deputy_manager, tribe_leader, researcher}
 * The label "Pesquisadores ativos" is unchanged (correct); only the COUNT narrows to the operational tier.
 * Curators / GP / Co-GP / comms-leaders collapse INTO those roles via the sync_operational_role_cache
 * ladder (SSOT), which is NOT modified here. v_active_members (Tema A) is NOT touched.
 *
 * Migration: supabase/migrations/20260805000467_1437_v_operational_members_canonical_metric.sql
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const MIG = resolve(process.cwd(), 'supabase/migrations/20260805000467_1437_v_operational_members_canonical_metric.sql');
const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const OPERATIONAL_TIER = ['manager', 'deputy_manager', 'tribe_leader', 'researcher'];

// ── STATIC ──────────────────────────────────────────────────────────────────
test('#1437: v_operational_members = operational tier, security_invoker, anon revoked', () => {
  assert.ok(existsSync(MIG), 'migration exists');
  assert.match(body, /CREATE OR REPLACE VIEW public\.v_operational_members\s+WITH \(security_invoker = true\)/i,
    'view is security_invoker (mirrors v_active_members)');
  assert.match(body, /operational_role IN \('manager', 'deputy_manager', 'tribe_leader', 'researcher'\)/i,
    'operational tier is exactly the 4 ladder-operational roles');
  assert.match(body, /is_active = true\s+AND m\.current_cycle_active = true/i, 'Tema A predicate preserved as the base');
  assert.match(body, /REVOKE ALL ON public\.v_operational_members FROM PUBLIC, anon/i);
  assert.match(body, /GRANT SELECT ON public\.v_operational_members TO authenticated, service_role/i);
  assert.match(body, /NOTIFY\s+pgrst/i);
});

test('#1437: the view does NOT filter pre_onboarding (ladder already excludes it; interim leaders count)', () => {
  const viewBlock = body.slice(body.indexOf('CREATE OR REPLACE VIEW public.v_operational_members'),
    body.indexOf('REVOKE ALL ON public.v_operational_members'));
  assert.ok(!/member_is_pre_onboarding/i.test(viewBlock),
    'operational tier is self-consistently post-onboarding; a pre_onboarding filter would wrongly drop interim-grant leaders (ADR-0121)');
});

test('#1437: the 3 headline consumers read the canonical view (not the old 87 inline predicate)', () => {
  for (const fn of ['get_public_platform_stats', 'get_homepage_stats', 'get_admin_dashboard']) {
    assert.match(body, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}\\b`, 'i'), `${fn} rewritten`);
  }
  // active_members / members headline reads the view
  assert.match(body, /'active_members', \(SELECT COUNT\(\*\) FROM public\.v_operational_members\)/i, 'public stats headline reads view');
  assert.match(body, /'members', \(SELECT count\(\*\) FROM public\.v_operational_members\)/i, 'homepage members reads view');
  assert.match(body, /'active_members', \(SELECT count\(\*\) FROM public\.v_operational_members\)/i, 'admin KPI reads view');
  // admin adoption_7d denominator uses the SAME base
  assert.match(body, /'adoption_7d',[\s\S]{0,200}?m\.id IN \(SELECT id FROM public\.v_operational_members\)/i, 'adoption denominator uses the operational base');
});

test('#1437 forward-defense: v_active_members (Tema A) is NOT touched by this migration', () => {
  assert.ok(!/CREATE OR REPLACE VIEW public\.v_active_members\b/i.test(body), 'must not redefine v_active_members');
  assert.ok(!/DROP VIEW[^;]*v_active_members/i.test(body), 'must not drop v_active_members');
});

// ── DB-gated ──────────────────────────────────────────────────────────────────
test('#1437 DB: view == operational tier predicate', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { count: viewCount, error } = await sb.from('v_operational_members').select('id', { count: 'exact', head: true });
  assert.ok(!error, error?.message);
  const { count: predicate } = await sb.from('members').select('id', { count: 'exact', head: true })
    .eq('is_active', true).eq('current_cycle_active', true).in('operational_role', OPERATIONAL_TIER);
  assert.equal(viewCount, predicate, 'v_operational_members == is_active ∧ current_cycle_active ∧ operational tier');
});

test('#1437 DB: home ≡ public ≡ view; and Tema A (v_active_members) is a strict superset', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: plat } = await sb.rpc('get_public_platform_stats');
  const { data: home } = await sb.rpc('get_homepage_stats');
  const { count: view } = await sb.from('v_operational_members').select('id', { count: 'exact', head: true });
  assert.equal(Number(plat.active_members), Number(home.members), 'public.active_members ≡ homepage.members');
  assert.equal(Number(plat.active_members), Number(view), 'headline ≡ v_operational_members count');
  const { count: temaA } = await sb.from('v_active_members').select('id', { count: 'exact', head: true });
  assert.ok(Number(temaA) >= Number(view), 'Tema A (system users) must be >= Tema B (research team)');
});
