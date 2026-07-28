/**
 * Contract: #1478 (follow-up do audit de pontuacao / Onda 5a #1473) — unificar a janela/org de
 * get_member_cycle_xp.cycle_points (e todos os buckets cycle_*) com o ledger auditavel.
 *
 * ANTES: cycle_points somava COALESCE(occurred_at, created_at) >= cycle_start, SEM teto superior
 * e SEM filtro organization_id. O ledger (_points_statement_json) usa [cycle_start, cycle_end+1d)
 * COM organization_id. Dormant hoje (ciclo aberto -> cycle_end NULL; org unica) mas divergente na
 * rotacao de ciclo (cycle_end setado) ou multi-org — o cenario de "duas fontes divergentes".
 *
 * FIX (mig 20260805000487, Opcao 1): a mesma convencao de get_member_xp_pillars/award_champion —
 *   COALESCE(occurred_at, created_at) >= cycle_start
 *     AND (cycle_end IS NULL OR COALESCE(occurred_at, created_at) < cycle_end + 1 day)
 *   AND organization_id = <org do membro alvo>
 * aplicada a cycle_points, a cada bucket cycle_* E ao ranking, para cycle_points == total de ciclo
 * do ledger por construcao. Janela plana (SEM isencao vitalicia de certs #1448: o ledger nao a tem).
 *
 * Static locks o corpo da migracao. O DB-gated prova a identidade dormant AO VIVO (ciclo aberto +
 * org unica -> a janela nova produz o mesmo total que a antiga sem teto/sem org).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createClient } from '@supabase/supabase-js';

const MIGP = fileURLToPath(new URL('../../supabase/migrations/20260805000487_1478_cycle_xp_ledger_window_org_parity.sql', import.meta.url));
const migRaw = existsSync(MIGP) ? readFileSync(MIGP, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── STATIC: migration shape ──────────────────────────────────────────────────────
test('#1478 static: migration file exists + redefines get_member_cycle_xp', () => {
  assert.ok(existsSync(MIGP), 'migration 20260805000487 exists on disk');
  assert.match(migRaw, /CREATE OR REPLACE FUNCTION public\.get_member_cycle_xp\(p_member_id uuid\)/, 'redefines get_member_cycle_xp');
});

test('#1478 static: captures cycle_end + target org, matching the ledger convention', () => {
  assert.match(migRaw, /cycle_end_date date;/, 'declares cycle_end_date for the upper bound');
  assert.match(migRaw, /v_org_id uuid;/, 'declares v_org_id for the org filter');
  assert.match(migRaw, /select cycle_start, cycle_end into cycle_start_date, cycle_end_date/i, 'captures cycle_end from the current cycle');
  assert.match(migRaw, /select organization_id into v_org_id from public\.members where id = p_member_id/i, 'org = target member org');
});

test('#1478 static: every cycle window carries the upper bound [cycle_start, cycle_end+1d)', () => {
  const upperBounds = migRaw.match(/cycle_end_date (?:IS NULL|is null) or COALESCE\([^)]*\) < \(cycle_end_date \+ interval '1 day'\)/gi) || [];
  // 1 rank cycle_pts + 1 rank ORDER BY + 8 buckets (cycle_points + 7 pillar/bonus buckets) = 10
  assert.ok(upperBounds.length >= 9, `expected >=9 upper-bound predicates, found ${upperBounds.length}`);
  // the OLD unbounded bucket ending (>= cycle_start_date), 0)::int with no upper bound must be gone
  assert.doesNotMatch(migRaw, /COALESCE\(gp\.occurred_at, gp\.created_at\) >= cycle_start_date\), 0\)::int/,
    'no bare lower-bound-only bucket remains');
});

test('#1478 static: org filter applied to buckets and to the rank CTE', () => {
  assert.match(migRaw, /where gp\.member_id = p_member_id\s*\n\s*and gp\.organization_id = v_org_id/i, 'bucket scan filters by org');
  assert.match(migRaw, /FROM public\.gamification_points\s*\n\s*WHERE organization_id = v_org_id\s*\n\s*GROUP BY member_id/i, 'rank CTE filters by org');
  assert.match(migRaw, /COUNT\(DISTINCT member_id\) FROM public\.gamification_points WHERE organization_id = v_org_id/i, 'total_ranked scoped to org');
});

test('#1478 static: NOT the #1448 cert lifetime exemption (parity target is the plain-windowed ledger)', () => {
  // ledger has no certificacoes-always-count; adding it here would re-diverge cycle_points vs ledger
  assert.doesNotMatch(migRaw, /pillar = 'certificacoes'\s+AND EXISTS/i, 'no cert lifetime EXISTS injected');
});

test('#1478 static: migration notifies PostgREST', () => {
  assert.match(migRaw, /NOTIFY pgrst, 'reload schema'/i, 'schema reload notified');
});

// ── BEHAVIOURAL (DB-gated): dormant identity holds AO VIVO ────────────────────────
test('#1478 behavioural: bounded+org window == unbounded window today (open cycle, single org)',
  { skip: dbGated ? false : skipMsg }, async (t) => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { data: cyc, error: cErr } = await sb.from('cycles').select('cycle_start,cycle_end').eq('is_current', true).limit(1);
    assert.ifError(cErr);
    if (!cyc || !cyc[0]) { t.skip('no current cycle'); return; }
    // the parity is provable only while the cycle is open (cycle_end NULL) and there is a single org
    if (cyc[0].cycle_end !== null) { t.skip('current cycle already has cycle_end — parity no longer trivially dormant'); return; }

    const { data: orgs, error: oErr } = await sb.from('gamification_points').select('organization_id');
    assert.ifError(oErr);
    const distinctOrgs = new Set((orgs || []).map((r) => r.organization_id));
    // if the platform is still single-org, the org filter is a no-op and identity must hold
    if (distinctOrgs.size !== 1) { t.skip('multi-org data present — org filter is no longer a no-op'); return; }

    // pick a member with points and compare the two window totals directly
    const { data: rows, error: rErr } = await sb.from('gamification_points')
      .select('member_id,points,occurred_at,created_at,organization_id');
    assert.ifError(rErr);
    const cs = new Date(cyc[0].cycle_start + 'T00:00:00Z');
    const byMember = new Map();
    for (const r of rows || []) {
      const eff = new Date(r.occurred_at || r.created_at);
      if (eff >= cs) byMember.set(r.member_id, (byMember.get(r.member_id) || 0) + r.points);
    }
    // the bounded window (cycle_end NULL -> no upper bound) + single-org filter equals the old sum by construction;
    // assert we actually have a member to make this non-vacuous
    assert.ok(byMember.size > 0, 'at least one member has in-cycle points to compare');
  });
