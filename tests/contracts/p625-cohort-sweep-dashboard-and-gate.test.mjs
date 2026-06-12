/**
 * Contract: #625 (sweep de coorte / épico #660 Passo 3) — the pre-onboarding cohort stops
 * contaminating two more denominators above the C0 partition (PR #626 / mig 142):
 *
 *   1. get_admin_dashboard.active_members (+ adoption_7d denominator) — the admin/MCP KPI counted
 *      member_status='active' raw, inflating the headline by the whole cohort. Sibling of the
 *      homepage (#629, mig 143) and trail-ranking (#637, mig 145) exclusions, applied to the
 *      admin dashboard + the MCP tool get_admin_dashboard. Live antes→depois (2026-06-12):
 *      active_members 72 → 47; adoption_7d 55.6% → 51.1%.
 *
 *   2. _can_sign_gate('volunteers_in_role_active') — the 'all'-threshold ratification denominator
 *      (_gate_threshold_met) counted pre-onboarding volunteers as required signers, so the term/
 *      addendum ratification gate could never close (the circular #654-class defect: a member would
 *      have to ratify the very term they have not yet signed). Live antes→depois (2026-06-12):
 *      volunteer_term_template 55 → 32; volunteer_addendum 55 → 32.
 *
 * Both fixes reuse the canonical C0 helper member_is_pre_onboarding(person_id, member_status)
 * (mig 20260805000143) — single source of truth, no inline re-derivation.
 *
 * Cross-ref: #625 (C0 PR #626, C1 #629/#637), #419/ADR-0100 (denominator class), #654 (gate
 * purity), ADR-0006/0007 (V4 persons/engagements).
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const MIG_DASH_PATH = 'supabase/migrations/20260805000157_625_admin_dashboard_active_members_exclude_pre_onboarding.sql';
const MIG_GATE_PATH = 'supabase/migrations/20260805000158_625_can_sign_gate_volunteers_in_role_active_exclude_pre_onboarding.sql';
const MIG_DASH = readFileSync(MIG_DASH_PATH, 'utf8');
const MIG_GATE = readFileSync(MIG_GATE_PATH, 'utf8');

const bodyOf = (src, fnName) =>
  (src.match(new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fnName}[\\s\\S]*?AS \\$function\\$([\\s\\S]*?)\\$function\\$;`)) || [])[1] ?? '';
const DASH_BODY = bodyOf(MIG_DASH, 'get_admin_dashboard');
const GATE_BODY = bodyOf(MIG_GATE, '_can_sign_gate');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK
  ? createClient(SUPABASE_URL, SUPABASE_SRK, { auth: { persistSession: false } })
  : null;

describe('p625-sweep — dashboard KPI migration (157)', () => {
  it('exists with #625 anchor + NOTIFY', () => {
    assert.ok(existsSync(MIG_DASH_PATH));
    assert.match(MIG_DASH, /#625/);
    assert.match(MIG_DASH, /NOTIFY pgrst, 'reload schema';/);
  });

  it('active_members excludes the cohort via the canonical helper', () => {
    assert.match(
      DASH_BODY,
      /'active_members', \(SELECT count\(\*\) FROM public\.members WHERE is_active AND current_cycle_active AND NOT public\.member_is_pre_onboarding\(person_id, member_status\)\)/,
    );
  });

  it('adoption_7d denominator excludes the cohort too (numerator/base consistency)', () => {
    // both the FILTER numerator base and the NULLIF(count(*)) denominator read the same filtered set
    const adoptionLine = (DASH_BODY.match(/'adoption_7d',[\s\S]*?\),\n/) || [])[0] ?? '';
    assert.match(adoptionLine, /WHERE is_active AND current_cycle_active AND NOT public\.member_is_pre_onboarding\(person_id, member_status\)/);
  });

  it('signature unchanged (no-arg get_admin_dashboard — body-only CoR)', () => {
    assert.match(MIG_DASH, /CREATE OR REPLACE FUNCTION public\.get_admin_dashboard\(\)/);
  });
});

describe('p625-sweep — gate cohort migration (158)', () => {
  it('exists with #625 anchor + restated ACL + NOTIFY', () => {
    assert.ok(existsSync(MIG_GATE_PATH));
    assert.match(MIG_GATE, /#625/);
    assert.match(MIG_GATE, /REVOKE ALL ON FUNCTION public\._can_sign_gate\(uuid, uuid, text, text, uuid\) FROM public, anon;/);
    assert.match(MIG_GATE, /GRANT EXECUTE ON FUNCTION public\._can_sign_gate\(uuid, uuid, text, text, uuid\) TO authenticated, service_role;/);
    assert.match(MIG_GATE, /NOTIFY pgrst, 'reload schema';/);
  });

  it("volunteers_in_role_active branch excludes pre-onboarding (member-level, before the engagement EXISTS)", () => {
    const branch = (GATE_BODY.match(/WHEN 'volunteers_in_role_active' THEN([\s\S]*?)WHEN 'external_signer'/) || [])[1] ?? '';
    assert.match(branch, /v_member\.member_status = 'active'/);
    assert.match(branch, /AND NOT public\.member_is_pre_onboarding\(v_member\.person_id, v_member\.member_status\)/);
    assert.match(branch, /e\.kind = 'volunteer'[\s\S]*?e\.role IN \('researcher','leader','manager'\)/);
  });

  it("does NOT alter the #666 leader gate or other branches (reproduced verbatim)", () => {
    assert.match(GATE_BODY, /WHEN 'leader' THEN[\s\S]*?r\.role = 'leader'/);
    assert.match(GATE_BODY, /WHEN 'cert_director_go' THEN/);
    assert.match(GATE_BODY, /WHEN 'president_go' THEN/);
  });
});

describe('p625-sweep — DB-gated (skip without env)', () => {
  const md5Norm = async (body) => {
    const { createHash } = await import('node:crypto');
    return createHash('md5').update(body.replace(/\s+/g, ' ')).digest('hex');
  };

  it('live get_admin_dashboard body matches the migration capture (Phase-C md5)', { skip: !sb }, async () => {
    const { data, error } = await sb.rpc('_audit_list_public_function_bodies');
    if (error) { console.warn(`[p625-sweep] helper unavailable: ${error.message}`); return; }
    const fn = (data ?? []).find((f) => f.proname === 'get_admin_dashboard');
    assert.ok(fn, 'get_admin_dashboard exists live');
    assert.equal(fn.body_md5, await md5Norm(DASH_BODY), 'live get_admin_dashboard drifted from mig 157');
  });

  it('live _can_sign_gate body matches the migration capture (Phase-C md5)', { skip: !sb }, async () => {
    const { data, error } = await sb.rpc('_audit_list_public_function_bodies');
    if (error) { console.warn(`[p625-sweep] helper unavailable: ${error.message}`); return; }
    const fn = (data ?? []).find((f) => f.proname === '_can_sign_gate');
    assert.ok(fn, '_can_sign_gate exists live');
    assert.equal(fn.is_secdef, true);
    assert.equal(fn.body_md5, await md5Norm(GATE_BODY), 'live _can_sign_gate drifted from mig 158');
  });

  it('both migrations registered once (no wall-clock shadow row)', { skip: !sb }, async () => {
    const { data, error } = await sb.rpc('_audit_list_schema_migrations');
    if (error) { console.warn(`[p625-sweep] helper unavailable: ${error.message}`); return; }
    for (const v of ['20260805000157', '20260805000158']) {
      const rows = (data ?? []).filter((r) => r.version === v);
      assert.equal(rows.length, 1, `migration ${v} must be registered exactly once`);
    }
  });

  it('dashboard active_members cohort tightening is non-trivial live', { skip: !sb }, async () => {
    // Replicate the KPI predicate via direct reads (the RPC itself needs a member JWT).
    const { data: actives, error } = await sb.from('members')
      .select('id, person_id').eq('member_status', 'active').eq('current_cycle_active', true);
    if (error) { console.warn(`[p625-sweep] members read unavailable: ${error.message}`); return; }
    const pre = await preOnboardingPersonIds(sb);
    const excl = (actives ?? []).filter((m) => !pre.has(m.person_id)).length;
    assert.ok(excl <= actives.length, 'excluded count cannot exceed raw');
    assert.ok(excl >= 0);
    // At ship time raw=72, excl=47 — the cohort is non-empty, so exclusion must drop the count.
    assert.ok(excl < actives.length, `exclusion must reduce active_members (raw=${actives.length}, excl=${excl})`);
  });

  it('gate cohort volunteers_in_role_active excludes pre-onboarding live', { skip: !sb }, async () => {
    // Member-level replication of the _can_sign_gate branch (active + active volunteer engagement
    // in researcher/leader/manager), then the pre-onboarding exclusion.
    const { data: actives, error } = await sb.from('members')
      .select('id, person_id, is_active').eq('member_status', 'active');
    if (error) { console.warn(`[p625-sweep] members read unavailable: ${error.message}`); return; }
    const { data: engs } = await sb.from('engagements')
      .select('person_id, kind, role, status, end_date').eq('kind', 'volunteer').eq('status', 'active');
    const today = new Date().toISOString().slice(0, 10);
    const roleOk = new Set(['researcher', 'leader', 'manager']);
    const volunteerPersons = new Set(
      (engs ?? []).filter((e) => roleOk.has(e.role) && (e.end_date === null || e.end_date >= today)).map((e) => e.person_id),
    );
    const raw = (actives ?? []).filter((m) => m.is_active && volunteerPersons.has(m.person_id));
    const pre = await preOnboardingPersonIds(sb);
    const preInRole = raw.filter((m) => pre.has(m.person_id));
    // LIVE lock (not a tautology over the test's own arithmetic): read the rebuilt
    // preview_gate_eligibles_cache and assert NO pre-onboarding in-role member is still listed as
    // eligible for 'volunteers_in_role_active' on volunteer_term_template. Reverting the _can_sign_gate
    // fix (and rebuilding the cache) would re-list them → this fails. preInRole may legitimately reach
    // 0 once the cohort fully onboards, at which point the denominator defect cannot recur anyway.
    if (preInRole.length > 0) {
      const { data: cacheRows, error: cacheErr } = await sb.from('preview_gate_eligibles_cache')
        .select('member_id, eligible_gates')
        .eq('doc_type', 'volunteer_term_template')
        .in('member_id', preInRole.map((m) => m.id));
      if (cacheErr) { console.warn(`[p625-sweep] cache read unavailable: ${cacheErr.message}`); return; }
      for (const row of cacheRows ?? []) {
        assert.ok(
          !(row.eligible_gates ?? []).includes('volunteers_in_role_active'),
          `pre-onboarding member ${row.member_id} must NOT be eligible for volunteers_in_role_active`,
        );
      }
    }
  });
});

/** Person-ids of the pre-onboarding cohort (C0 rule), via service-role direct reads. */
async function preOnboardingPersonIds(sb) {
  const { data: actives } = await sb.from('members').select('person_id').eq('member_status', 'active');
  const { data: engs } = await sb.from('engagements')
    .select('person_id, kind, agreement_certificate_id').eq('status', 'active');
  const { data: kinds } = await sb.from('engagement_kinds').select('slug, requires_agreement');
  const reqMap = new Map((kinds ?? []).map((k) => [k.slug, k.requires_agreement === true]));
  const byPerson = new Map();
  for (const e of engs ?? []) {
    if (!byPerson.has(e.person_id)) byPerson.set(e.person_id, []);
    byPerson.get(e.person_id).push(e);
  }
  const pre = new Set();
  for (const m of actives ?? []) {
    const list = byPerson.get(m.person_id) ?? [];
    const hasAny = list.length > 0;
    const hasOperational = list.some((e) => !reqMap.get(e.kind) || e.agreement_certificate_id !== null);
    if (hasAny && !hasOperational) pre.add(m.person_id);
  }
  return pre;
}
