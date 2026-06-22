/**
 * Contract: #599 + #600 — #419 M4 residuals (migration 20260805000138).
 *
 * #599 — get_initiative_detail.member_count was a raw count of ALL active engagements
 * (observers included): the page header disagreed with the roster/gamification surfaces
 * (participants-only v_initiative_roster). Grounded BEFORE (2026-06-10): 4 initiatives
 * disparate (e.g. congress 7 vs 4). Now sourced from the canonical M4 helper
 * get_initiative_roster_count — same denominator as get_tribe_gamification.
 *
 * #600 — get_initiative_gamification's standalone branch gated only on "is some member":
 * ANY authenticated member could read ANY standalone initiative's roster (names +
 * per-pillar XP). Grounded BEFORE: unrelated member read 3 members' XP live. Now mirrors
 * the tribe path's gate: active engagement on p_initiative_id OR view_internal_analytics
 * (fail-closed, ADR-0007). AFTER smokes: unrelated → Unauthorized; initiative member →
 * data; analytics capability → data.
 *
 * Cross-ref: #599, #600, #419 (ADR-0100/G6), ADR-0007, siblings #465/#468, PR #471.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const MIG_PATH = 'supabase/migrations/20260805000138_p599_600_initiative_roster_parity_and_gamification_gate.sql';
const MIG = readFileSync(MIG_PATH, 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK
  ? createClient(SUPABASE_URL, SUPABASE_SRK, { auth: { persistSession: false } })
  : null;

function fnBody(name) {
  const m = MIG.match(new RegExp(
    `CREATE OR REPLACE FUNCTION public\\.${name}\\([^)]*\\)[\\s\\S]*?AS \\$function\\$([\\s\\S]*?)\\$function\\$;`
  ));
  return m ? m[1] : '';
}
const DETAIL_BODY = fnBody('get_initiative_detail');
const GAMIF_BODY = fnBody('get_initiative_gamification');

describe('p599-600 — migration presence + header', () => {
  it('migration exists with both issue refs + ADR anchors', () => {
    assert.ok(existsSync(MIG_PATH));
    assert.match(MIG, /#599/);
    assert.match(MIG, /#600/);
    assert.match(MIG, /#419/);
    assert.match(MIG, /ADR-0007/);
    assert.match(MIG, /ADR-0100/);
    assert.match(MIG, /-- ROLLBACK/);
    assert.match(MIG, /NOTIFY pgrst, 'reload schema';/);
  });
});

describe('p599-600 — #599 header/roster denominator parity', () => {
  it('member_count comes from the canonical M4 roster helper', () => {
    assert.match(DETAIL_BODY, /v_member_count := public\.get_initiative_roster_count\(p_initiative_id\);/);
  });

  it('forward-defense: the raw active-engagements count never returns to the header', () => {
    assert.ok(!/count\(\*\) INTO v_member_count/.test(DETAIL_BODY),
      'header must use the participants-only roster denominator (ADR-0100 G6), not raw active engagements');
  });

  it('engagement_summary keeps the FULL active breakdown (observers stay visible THERE)', () => {
    assert.match(DETAIL_BODY, /SELECT e\.kind, e\.role, count\(\*\) as count\s+FROM engagements e\s+WHERE e\.initiative_id = p_initiative_id AND e\.status = 'active'/,
      'the by-kind/role breakdown intentionally covers ALL active engagements — that is where observers are labeled');
  });
});

describe('p599-600 — #600 standalone gamification gate', () => {
  it('tribe-backed path still delegates to get_tribe_gamification (own gate)', () => {
    assert.match(GAMIF_BODY, /RETURN public\.get_tribe_gamification\(v_tribe_id\);/);
  });

  it('standalone branch gates on initiative-scoped authority (engagement OR analytics capability)', () => {
    assert.match(GAMIF_BODY, /e\.initiative_id = p_initiative_id\s+AND e\.status = 'active'\s+AND e\.person_id = v_caller\.person_id/,
      'membership = ANY active engagement of the caller on THIS initiative');
    assert.match(GAMIF_BODY, /OR public\.can_by_member\(v_caller\.id, 'view_internal_analytics'\)/,
      'mirror of the tribe gate fallback');
  });

  it('gate sits AFTER the caller fetch and BEFORE any data read (fail-closed ordering)', () => {
    const callerAt = GAMIF_BODY.indexOf('SELECT * INTO v_caller FROM members');
    const gateAt = GAMIF_BODY.indexOf("AND e.person_id = v_caller.person_id");
    const firstReadAt = GAMIF_BODY.indexOf('SELECT cycle_start INTO v_cycle_start');
    assert.ok(callerAt > -1 && gateAt > -1 && firstReadAt > -1, 'all three anchors present');
    assert.ok(callerAt < gateAt && gateAt < firstReadAt,
      'caller fetch → authority gate → first data read; nothing leaks before the gate');
  });

  it('unauthorized exits are fail-closed envelopes (no data keys)', () => {
    const denies = GAMIF_BODY.match(/RETURN jsonb_build_object\('error', 'Unauthorized'\);/g) || [];
    assert.ok(denies.length >= 2, `ghost-deny + unrelated-member-deny both present (found ${denies.length})`);
  });
});

describe('p599-600 — ACL restated for single-file auditability', () => {
  for (const fn of ['get_initiative_detail', 'get_initiative_gamification']) {
    it(`${fn}: anon revoked, authenticated + service_role granted`, () => {
      assert.match(MIG, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn}\\(uuid\\) FROM PUBLIC, anon;`));
      assert.match(MIG, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn}\\(uuid\\) TO authenticated;`));
    });
  }
});

describe('p599-600 — DB-gated (skip without env)', () => {
  it('live bodies match the LATEST migration capture (Phase-C normalized md5)', { skip: !sb }, async () => {
    const { createHash } = await import('node:crypto');
    const localMd5 = (body) => createHash('md5').update(body.replace(/\s+/g, ' ')).digest('hex');
    // get_initiative_detail + get_initiative_gamification were last re-created by PR-3
    // (#785 confidential-initiative RPC gate, mig 20260805000233): that file is now their
    // canonical body capture. The #599/#600 intent (roster denominator + #600 scope gate) is
    // preserved there and is still asserted statically above against the originating 138.
    const PR3 = readFileSync('supabase/migrations/20260805000233_p785_pr3_confidential_initiative_rpcs.sql', 'utf8');
    const pr3Body = (name) => {
      const m = PR3.match(new RegExp(
        `CREATE OR REPLACE FUNCTION public\\.${name}\\([^)]*\\)[\\s\\S]*?AS \\$function\\$([\\s\\S]*?)\\$function\\$;`
      ));
      return m ? m[1] : '';
    };
    const expected = {
      get_initiative_detail: localMd5(pr3Body('get_initiative_detail')),
      get_initiative_gamification: localMd5(pr3Body('get_initiative_gamification')),
    };
    const { data, error } = await sb.rpc('_audit_list_public_function_bodies');
    if (error) { console.warn(`[p599-600] helper unavailable: ${error.message}`); return; }
    const rows = Array.isArray(data) ? data : [];
    for (const [name, md5] of Object.entries(expected)) {
      const fn = rows.find((f) => f.proname === name);
      assert.ok(fn, `${name} exists live`);
      assert.equal(fn.is_secdef, true, `${name} stays SECURITY DEFINER`);
      assert.equal(fn.body_md5, md5, `${name} live body drifted from the migration capture`);
    }
  });

  it('migration 20260805000138 registered once (no wall-clock shadow)', { skip: !sb }, async () => {
    const { data, error } = await sb.rpc('_audit_list_schema_migrations');
    if (error) { console.warn(`[p599-600] helper unavailable: ${error.message}`); return; }
    const rows = data.filter((r) => r.name === 'p599_600_initiative_roster_parity_and_gamification_gate');
    assert.equal(rows.length, 1);
    assert.equal(rows[0].version, '20260805000138');
  });

  it('denominator parity holds for EVERY initiative (header == canonical roster count)', { skip: !sb }, async () => {
    // get_initiative_detail has no auth gate on member_count (caller context only enriches
    // user_engagement), so the service-role client can probe the full surface.
    // Concurrent pairs (council LOW): keeps the probe O(1) wall-clock as initiatives grow.
    const { data: inits, error } = await sb.from('initiatives').select('id, title');
    if (error) { console.warn(`[p599-600] initiatives unavailable: ${error.message}`); return; }
    const results = await Promise.all((inits ?? []).map(async (i) => {
      const [{ data: detail }, { data: roster }] = await Promise.all([
        sb.rpc('get_initiative_detail', { p_initiative_id: i.id }),
        sb.rpc('get_initiative_roster_count', { p_initiative_id: i.id }),
      ]);
      return detail?.member_count !== roster
        ? `${i.title}: header=${detail?.member_count} roster=${roster}`
        : null;
    }));
    const mismatches = results.filter(Boolean);
    assert.deepEqual(mismatches, [], `header/roster disparity re-emerged: ${mismatches.join(' | ')}`);
  });

  it('behavioural ghost-deny: a caller with no member record gets Unauthorized (fail-closed entry)', { skip: !sb }, async () => {
    // Service-role JWT carries no `sub` → auth.uid() IS NULL inside the RPC → the ghost
    // branch must deny BEFORE the #600 scope gate (and before any data read). This locks the
    // entry gate behaviourally through PostgREST; the unrelated-member leg is covered by the
    // static order assertions + the live BEFORE/AFTER smokes recorded in the PR (no JWT-mint
    // harness exists in this repo to impersonate arbitrary members from CI).
    const { data: inits } = await sb.from('initiatives').select('id, legacy_tribe_id').is('legacy_tribe_id', null).limit(1);
    if (!inits?.length) { console.warn('[p599-600] no standalone initiative to probe'); return; }
    const { data, error } = await sb.rpc('get_initiative_gamification', { p_initiative_id: inits[0].id });
    assert.equal(error, null, `RPC reachable: ${error?.message}`);
    assert.deepEqual(data, { error: 'Unauthorized' }, 'ghost caller must get the fail-closed envelope, no data keys');
  });
});
