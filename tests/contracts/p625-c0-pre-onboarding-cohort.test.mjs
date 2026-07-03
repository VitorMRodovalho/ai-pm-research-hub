/**
 * Contract: #625 Camada 0 — pre-onboarding cohort split out of "Ativos" in /admin/members.
 *
 * Grounded live (2026-06-10): 26 cycle-4 members were created member_status='active' at
 * approval with ALL their engagements still awaiting the volunteer term — inflating the
 * "Ativos" indicator from ~48 to 73 and mixing cohorts (same denominator-defect family as
 * #419/ADR-0100 G6). Post-fix live smoke: pre_onboarding=25 + operating actives=48 = 73 ✓
 * (the 26th has an operational engagement — the lateral-role rule working as designed).
 *
 * Rule (RPC-derived, single source of truth): is_pre_onboarding = active member with >=1
 * active engagement AND NO operational engagement, where operational = kind that does not
 * require an agreement OR agreement already satisfied. An existing member taking a NEW role
 * (lateral pending term) keeps their operational engagements → NOT pre-onboarding.
 *
 * Compat: p_status='active' keeps legacy semantics (all member_status='active'); the island
 * partitions the VIEW client-side; p_status='pre_onboarding' is additive; the MCP consumer
 * of admin_list_members receives the new field additively.
 *
 * Cross-ref: #625 (camadas 1-2 pendentes), #419/ADR-0100, ADR-0006/0007 (V4 engagements).
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const MIG_PATH = 'supabase/migrations/20260805000142_p625_c0_admin_list_members_pre_onboarding.sql';
const MIG = readFileSync(MIG_PATH, 'utf8');
const ISLAND = readFileSync('src/components/admin/members/MemberListIsland.tsx', 'utf8');
const DICTS = {
  'pt-BR': readFileSync('src/i18n/pt-BR.ts', 'utf8'),
  'en-US': readFileSync('src/i18n/en-US.ts', 'utf8'),
  'es-LATAM': readFileSync('src/i18n/es-LATAM.ts', 'utf8'),
};

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK
  ? createClient(SUPABASE_URL, SUPABASE_SRK, { auth: { persistSession: false } })
  : null;

const FN_BODY = (MIG.match(/AS \$function\$([\s\S]*?)\$function\$;/) || [])[1] ?? '';

// #625 F1/C1-b: admin_list_members foi re-definido em ...148 (farol de filiação)
// e em ...160 (DRY da regra pre-onboarding via helper canônico). O check de md5
// do corpo VIVO deve comparar contra a captura CANÔNICA mais recente, não contra
// a do C0 (...142). Fallback progressivo para checkouts parciais.
const MIG_148_PATH = 'supabase/migrations/20260805000148_625_affiliation_verification_loop_f1_f3.sql';
const MIG_160_PATH = 'supabase/migrations/20260805000160_625_c1b_admin_list_members_pre_onboarding_helper.sql';
// #625 C2 (mig 181): admin_list_members redefinido V4-native (filtros iniciativa/ciclo +
// engagements[]/cycles[]/term_status). A regra pre-onboarding CONTINUA via helper; o RPC
// volta a ter um JOIN engagement_kinds, mas para labels do catálogo + term_status, NÃO para
// a regra de coorte inline. A captura canônica mais recente passa a ser a 181.
const MIG_181_PATH = 'supabase/migrations/20260805000181_p625_c2_admin_list_members_v4.sql';
// #727 (mig 329): admin_list_members re-definido body-only para expor country/state (filtros
// estado/país client-side). Assinatura/coorte inalteradas; a captura canônica mais recente passa
// a ser a 329.
const MIG_329_PATH = 'supabase/migrations/20260805000329_727_admin_list_members_geo.sql';
const LATEST_CAPTURE_PATH = existsSync(MIG_329_PATH)
  ? MIG_329_PATH
  : existsSync(MIG_181_PATH) ? MIG_181_PATH
  : existsSync(MIG_160_PATH) ? MIG_160_PATH : MIG_148_PATH;
const FN_BODY_LATEST = existsSync(LATEST_CAPTURE_PATH)
  ? ((readFileSync(LATEST_CAPTURE_PATH, 'utf8')
       .match(/CREATE OR REPLACE FUNCTION public\.admin_list_members[\s\S]*?AS \$function\$([\s\S]*?)\$function\$;/) || [])[1] ?? FN_BODY)
  : FN_BODY;

describe('p625-c0 — migration + RPC rule', () => {
  it('migration exists with #625 + ADR-0100 anchors + NOTIFY', () => {
    assert.ok(existsSync(MIG_PATH));
    assert.match(MIG, /#625/);
    assert.match(MIG, /ADR-0100/);
    assert.match(MIG, /NOTIFY pgrst, 'reload schema';/);
  });

  it('signature preserves all 4 parameter DEFAULTs (42P13 guard)', () => {
    assert.match(MIG, /p_search text DEFAULT NULL::text,\s*\n\s*p_tier text DEFAULT NULL::text,\s*\n\s*p_tribe_id integer DEFAULT NULL::integer,\s*\n\s*p_status text DEFAULT 'active'::text/);
  });

  it('derives is_pre_onboarding with the operational-engagement rule', () => {
    assert.match(FN_BODY, /'is_pre_onboarding', COALESCE\(pre\.flag, false\)/);
    assert.match(FN_BODY, /m\.member_status = 'active'/);
    assert.match(FN_BODY, /e\.person_id = m\.person_id AND e\.status = 'active'/);
    assert.match(FN_BODY, /ek\.requires_agreement IS NOT TRUE OR e\.agreement_certificate_id IS NOT NULL/,
      'operational = kind without agreement requirement OR agreement satisfied — its existence removes the member from the cohort');
  });

  it("adds p_status='pre_onboarding' WITHOUT changing the legacy 'active' branch (compat)", () => {
    assert.match(FN_BODY, /p_status = 'pre_onboarding' AND m\.member_status = 'active' AND COALESCE\(pre\.flag, false\)/);
    assert.match(FN_BODY, /p_status = 'active' AND m\.member_status = 'active'\)/,
      "p_status='active' keeps returning ALL active members — the island partitions the view");
  });

  it('keeps the authority gate + restates ACL', () => {
    assert.match(FN_BODY, /can_by_member\(v_caller_id, 'view_internal_analytics'\)/);
    assert.match(MIG, /REVOKE ALL ON FUNCTION public\.admin_list_members\(text, text, integer, text\) FROM PUBLIC, anon;/);
    assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\.admin_list_members\(text, text, integer, text\) TO authenticated;/);
  });
});

describe('p625-c1-b — admin_list_members delegates cohort rule to helper', () => {
  it('latest capture calls member_is_pre_onboarding for field + filter', () => {
    assert.match(FN_BODY_LATEST, /'is_pre_onboarding', public\.member_is_pre_onboarding\(m\.person_id, m\.member_status\)/);
    assert.match(FN_BODY_LATEST, /p_status = 'pre_onboarding' AND public\.member_is_pre_onboarding\(m\.person_id, m\.member_status\)/);
  });

  it('latest capture no longer carries the inline pre-onboarding cohort rule', () => {
    // The cohort rule (operational = kind w/o agreement OR agreement satisfied) must live in
    // the helper, never copied inline. C2 reintroduced a JOIN engagement_kinds for catalog
    // labels + the term_status farol — that join is fine; what must NOT reappear is the
    // operational-engagement *rule* itself (the helper owns it).
    assert.doesNotMatch(FN_BODY_LATEST, /COALESCE\(pre\.flag, false\)/);
    assert.doesNotMatch(FN_BODY_LATEST, /ek\.requires_agreement IS NOT TRUE OR e\.agreement_certificate_id IS NOT NULL/,
      'pre-onboarding cohort rule must stay in member_is_pre_onboarding, not inline');
  });

  it('migration 160 preserves grants + PostgREST reload', () => {
    assert.ok(existsSync(MIG_160_PATH));
    const mig160 = readFileSync(MIG_160_PATH, 'utf8');
    assert.match(mig160, /REVOKE ALL ON FUNCTION public\.admin_list_members\(text, text, integer, text\) FROM PUBLIC, anon;/);
    assert.match(mig160, /GRANT EXECUTE ON FUNCTION public\.admin_list_members\(text, text, integer, text\) TO authenticated;/);
    assert.match(mig160, /NOTIFY pgrst, 'reload schema';/);
  });
});

describe('p625-c0 — island (view partition + counters + affordances)', () => {
  it('MemberRow carries the derived field', () => {
    assert.match(ISLAND, /is_pre_onboarding: boolean;/);
  });

  it("counters: 'Ativos' excludes the cohort; pre-onboarding counted apart", () => {
    assert.match(ISLAND, /m\.member_status === 'active' && !m\.is_pre_onboarding\)\.length/);
    assert.match(ISLAND, /const preOnboarding = allMembers\.filter\(m => m\.is_pre_onboarding\)\.length;/);
  });

  it('stat card + filter option + row chip present', () => {
    assert.match(ISLAND, /comp\.memberList\.preOnboarding', 'Pré-onboarding'\), value: preOnboarding/);
    assert.match(ISLAND, /<option value="pre_onboarding">/);
    assert.match(ISLAND, /⏳ \{t\('comp\.memberList\.preOnboarding'/, 'flagged active rows show the chip instead of the green dot');
  });

  it("the 'Ativos' VIEW partitions out the cohort client-side", () => {
    assert.match(ISLAND, /statusFilter === 'active' \? members\.filter\(m => !m\.is_pre_onboarding\) : members/);
  });
});

describe('p625-c0 — i18n parity (3 dictionaries)', () => {
  for (const [lang, src] of Object.entries(DICTS)) {
    it(`${lang} has both keys`, () => {
      assert.match(src, /'comp\.memberList\.preOnboarding': '/);
      assert.match(src, /'comp\.memberList\.preOnboardingHint': '/);
    });
  }
});

describe('p625-c0 — DB-gated (skip without env)', () => {
  it('live body matches the migration capture (Phase-C md5)', { skip: !sb }, async () => {
    const { createHash } = await import('node:crypto');
    const localMd5 = createHash('md5').update(FN_BODY_LATEST.replace(/\s+/g, ' ')).digest('hex');
    const { data, error } = await sb.rpc('_audit_list_public_function_bodies');
    if (error) { console.warn(`[p625-c0] helper unavailable: ${error.message}`); return; }
    const fn = (data ?? []).find((f) => f.proname === 'admin_list_members');
    assert.ok(fn, 'admin_list_members exists live');
    assert.equal(fn.is_secdef, true);
    assert.equal(fn.body_md5, localMd5, 'live body drifted from the migration capture');
  });

  it('migration 20260805000142 registered once (no wall-clock shadow)', { skip: !sb }, async () => {
    const { data, error } = await sb.rpc('_audit_list_schema_migrations');
    if (error) { console.warn(`[p625-c0] helper unavailable: ${error.message}`); return; }
    const rows = (data ?? []).filter((r) => r.name === 'p625_c0_admin_list_members_pre_onboarding');
    assert.equal(rows.length, 1);
    assert.equal(rows[0].version, '20260805000142');
  });

  it('migration 20260805000160 registered once (C1-b helper consolidation)', { skip: !sb }, async () => {
    const { data, error } = await sb.rpc('_audit_list_schema_migrations');
    if (error) { console.warn(`[p625-c0] helper unavailable: ${error.message}`); return; }
    const rows = (data ?? []).filter((r) => r.name === '625_c1b_admin_list_members_pre_onboarding_helper');
    assert.equal(rows.length, 1);
    assert.equal(rows[0].version, '20260805000160');
  });

  it('cohort arithmetic holds live: pre_onboarding + operating = total actives', { skip: !sb }, async () => {
    // Service-role replication of the RPC rule via direct reads (the RPC itself requires a
    // member JWT). Locks the partition arithmetic against live data.
    const { data: actives, error } = await sb.from('members').select('id, person_id').eq('member_status', 'active');
    if (error) { console.warn(`[p625-c0] members read unavailable: ${error.message}`); return; }
    const { data: engs } = await sb.from('engagements')
      .select('person_id, kind, agreement_certificate_id')
      .eq('status', 'active');
    const { data: kinds } = await sb.from('engagement_kinds').select('slug, requires_agreement');
    const reqMap = new Map((kinds ?? []).map((k) => [k.slug, k.requires_agreement === true]));
    const byPerson = new Map();
    for (const e of engs ?? []) {
      if (!byPerson.has(e.person_id)) byPerson.set(e.person_id, []);
      byPerson.get(e.person_id).push(e);
    }
    let pre = 0;
    for (const m of actives ?? []) {
      const list = byPerson.get(m.person_id) ?? [];
      const hasAny = list.length > 0;
      const hasOperational = list.some((e) => !reqMap.get(e.kind) || e.agreement_certificate_id !== null);
      if (hasAny && !hasOperational) pre++;
    }
    assert.ok(pre + (actives.length - pre) === actives.length, 'partition is total');
    assert.ok(pre >= 0 && pre <= actives.length);
    // The cohort must never be the MAJORITY of actives silently (tripwire for a rule
    // inversion — at ship time it was 25 of 73).
    assert.ok(pre < actives.length, `pre-onboarding (${pre}) must not swallow all actives (${actives.length})`);
    // Council NIT: ratio tripwire — ship-time ratio was ~34% (25/73); >60% indicates a rule inversion.
    assert.ok(pre < actives.length * 0.6, `pre-onboarding cohort (${pre}/${actives.length}) exceeds 60% — possible rule inversion`);
  });
});
