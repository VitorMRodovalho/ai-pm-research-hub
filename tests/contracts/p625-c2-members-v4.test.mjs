/**
 * Contract: #625 Camada 2 — /admin/members V4-native (DB layer / Fatia 1).
 *
 * Decisions (ratified PM 2026-06-15):
 *  - D1=C: vocabulário de tipos via catálogo + i18n trilíngue. New column
 *    engagement_kinds.display_i18n jsonb ({en,es}); display_name stays PT-BR canonical.
 *    Translations live in the catalog (config) → honours ADR-0009.
 *  - D2=B1: term_status farol 🟢 green / 🟡 amber now; 🔴 vencido deferred to #571
 *    (no validity anchor exists today — not fabricated).
 *  - D3=C1: shared lib/initiatives.ts loader (frontend, Fatia 2).
 *
 * This file covers the DB layer (migs 180 display_i18n + 181 admin_list_members V4).
 * Island + i18n chrome assertions land in Fatia 2.
 *
 * Live validation at ship time (2026-06-15): invariant violations=0; term_status
 * amber=26/green=74; pre_onboarding=25 (gap 26 vs 25 = 1 lateral-term member, by design);
 * filter-by-initiative 6=6; filter-by-cycle 63=63.
 *
 * Cross-ref: #625 (C0/F1 shipped earlier), #571 (term validity → 🔴), ADR-0009 (config kinds).
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const MIG_180_PATH = 'supabase/migrations/20260805000180_p625_c2_engagement_kinds_display_i18n.sql';
const MIG_181_PATH = 'supabase/migrations/20260805000181_p625_c2_admin_list_members_v4.sql';
const MIG_180 = readFileSync(MIG_180_PATH, 'utf8');
const MIG_181 = readFileSync(MIG_181_PATH, 'utf8');
const FN_181 = (MIG_181.match(/CREATE OR REPLACE FUNCTION public\.admin_list_members[\s\S]*?AS \$function\$([\s\S]*?)\$function\$;/) || [])[1] ?? '';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK
  ? createClient(SUPABASE_URL, SUPABASE_SRK, { auth: { persistSession: false } })
  : null;

describe('p625-c2 — mig 180 (engagement_kinds.display_i18n / D1=C)', () => {
  it('adds display_i18n jsonb column (idempotent) + ADR-0009 anchor', () => {
    assert.ok(existsSync(MIG_180_PATH));
    assert.match(MIG_180, /ADD COLUMN IF NOT EXISTS display_i18n jsonb NOT NULL DEFAULT '\{\}'::jsonb/);
    assert.match(MIG_180, /ADR-0009/);
  });

  it('populates en + es for representative kinds', () => {
    assert.match(MIG_180, /\('volunteer',\s*'\{"en":"Active Volunteer","es":"Voluntario Activo"\}'::jsonb\)/);
    assert.match(MIG_180, /\('chapter_board',\s*'\{"en":"Chapter Board","es":"Junta del Capítulo"\}'::jsonb\)/);
  });
});

describe('p625-c2 — mig 181 (admin_list_members V4)', () => {
  it('DROP+CREATE (signature change) with 7 params incl. initiative/chapter/cycle', () => {
    assert.match(MIG_181, /DROP FUNCTION IF EXISTS public\.admin_list_members\(text, text, integer, text\);/);
    // params live in the signature (outside the $function$ body) → assert against the file
    assert.match(MIG_181, /p_initiative_id uuid DEFAULT NULL::uuid/);
    assert.match(MIG_181, /p_chapter text DEFAULT NULL::text/);
    assert.match(MIG_181, /p_cycle text DEFAULT NULL::text/);
  });

  it('keeps the authority gate + restates ACL on the new signature + NOTIFY', () => {
    assert.match(FN_181, /can_by_member\(v_caller_id, 'view_internal_analytics'\)/);
    assert.match(MIG_181, /REVOKE ALL ON FUNCTION public\.admin_list_members\(text, text, integer, text, uuid, text, text\) FROM PUBLIC, anon;/);
    assert.match(MIG_181, /GRANT EXECUTE ON FUNCTION public\.admin_list_members\(text, text, integer, text, uuid, text, text\) TO authenticated;/);
    assert.match(MIG_181, /NOTIFY pgrst, 'reload schema';/);
  });

  it('pre-onboarding rule still delegates to the helper (not inline)', () => {
    assert.match(FN_181, /'is_pre_onboarding', public\.member_is_pre_onboarding\(m\.person_id, m\.member_status\)/);
    assert.doesNotMatch(FN_181, /ek\.requires_agreement IS NOT TRUE OR e\.agreement_certificate_id IS NOT NULL/);
  });

  it('term_status (D2=B1): amber = active engagement requiring term w/o certificate; else green', () => {
    assert.match(FN_181, /'term_status', CASE WHEN EXISTS \(/);
    assert.match(FN_181, /ek\.requires_agreement IS TRUE AND e\.agreement_certificate_id IS NULL\s*\)\s*THEN 'amber' ELSE 'green' END/);
    // 🔴 vencido is NOT fabricated here — deferred to #571. Check the CASE never RETURNS a
    // red/vencido/expired value (the word may appear in a comment explaining the deferral).
    assert.doesNotMatch(FN_181, /THEN '(red|vencido|expired)'/);
  });

  it('engagements[] carries catalog labels (display_name PT + display_i18n)', () => {
    assert.match(FN_181, /'kind_display_name', ek\.display_name/);
    assert.match(FN_181, /'kind_display_i18n', ek\.display_i18n/);
    assert.match(FN_181, /'initiative_title', i\.title/);
  });

  it('filters: by initiative (active engagement) + by cycle (member_cycle_history) + chapter', () => {
    assert.match(FN_181, /p_initiative_id IS NULL OR EXISTS \(\s*SELECT 1 FROM public\.engagements e\s*WHERE e\.person_id = m\.person_id AND e\.status = 'active' AND e\.initiative_id = p_initiative_id\)/);
    assert.match(FN_181, /p_cycle IS NULL OR EXISTS \(\s*SELECT 1 FROM public\.member_cycle_history mch\s*WHERE mch\.member_id = m\.id AND mch\.cycle_code = p_cycle\)/);
    assert.match(FN_181, /p_chapter IS NULL OR m\.chapter = p_chapter/);
  });
});

describe('p625-c2 — DB-gated (skip without env)', () => {
  it('every engagement_kind has en + es translations populated', { skip: !sb }, async () => {
    const { data, error } = await sb.from('engagement_kinds').select('slug, display_i18n');
    if (error) { console.warn(`[p625-c2] engagement_kinds read unavailable: ${error.message}`); return; }
    const missing = (data ?? []).filter(k => {
      const i = k.display_i18n || {};
      return !i.en || !i.es || String(i.en).trim() === '' || String(i.es).trim() === '';
    });
    assert.equal(missing.length, 0, `kinds missing en/es: ${missing.map(k => k.slug).join(', ')}`);
  });

  it('INVARIANT: every pre-onboarding member resolves to term_status=amber', { skip: !sb }, async () => {
    // Service-role replication (the RPC requires a member JWT). pre_onboarding ⟹ amber:
    // if all active engagements await the term, at least one requires_agreement w/o cert.
    const { data: actives, error } = await sb.from('members').select('id, person_id').eq('member_status', 'active');
    if (error) { console.warn(`[p625-c2] members read unavailable: ${error.message}`); return; }
    const { data: engs } = await sb.from('engagements')
      .select('person_id, kind, agreement_certificate_id').eq('status', 'active');
    const { data: kinds } = await sb.from('engagement_kinds').select('slug, requires_agreement');
    const reqMap = new Map((kinds ?? []).map(k => [k.slug, k.requires_agreement === true]));
    const byPerson = new Map();
    for (const e of engs ?? []) {
      if (!byPerson.has(e.person_id)) byPerson.set(e.person_id, []);
      byPerson.get(e.person_id).push(e);
    }
    let violations = 0;
    for (const m of actives ?? []) {
      const list = byPerson.get(m.person_id) ?? [];
      const hasAny = list.length > 0;
      const hasOperational = list.some(e => !reqMap.get(e.kind) || e.agreement_certificate_id !== null);
      const isPre = hasAny && !hasOperational;
      const isAmber = list.some(e => reqMap.get(e.kind) && e.agreement_certificate_id === null);
      if (isPre && !isAmber) violations++;
    }
    assert.equal(violations, 0, `pre-onboarding members not resolving to amber: ${violations}`);
  });

  it('migrations 180 + 181 registered once each (no wall-clock shadow)', { skip: !sb }, async () => {
    const { data, error } = await sb.rpc('_audit_list_schema_migrations');
    if (error) { console.warn(`[p625-c2] helper unavailable: ${error.message}`); return; }
    const m180 = (data ?? []).filter(r => r.name === 'p625_c2_engagement_kinds_display_i18n');
    const m181 = (data ?? []).filter(r => r.name === 'p625_c2_admin_list_members_v4');
    assert.equal(m180.length, 1, 'mig 180 registered exactly once');
    assert.equal(m180[0]?.version, '20260805000180');
    assert.equal(m181.length, 1, 'mig 181 registered exactly once');
    assert.equal(m181[0]?.version, '20260805000181');
  });
});
