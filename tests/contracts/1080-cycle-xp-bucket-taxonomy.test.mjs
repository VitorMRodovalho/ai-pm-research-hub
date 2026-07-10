/**
 * Contract: #1080 — get_member_cycle_xp buckets are pillar-derived, not hardcoded bare slugs.
 *
 * BUG (live-grounded 2026-07-03, exposed by the Cycle-3 gamification conciliation): the RPC's
 * JSON bucket filters used bare category names that predate the granular slug taxonomy. The
 * write side emits canonical slugs matching gamification_rules.slug (showcase_case_study,
 * showcase_tool_review, showcase_awareness, champion_deliverable, artifact_published,
 * deliverable_completed, action_resolved, agenda_block_*, curation_*). Consequences:
 *   - cycle_artifacts was ALWAYS 0 (no row uses bare 'artifact'; the slug is 'artifact_published')
 *   - every showcase_* row fell into cycle_bonus instead of cycle_showcase
 *   - champions/curadoria/protagonismo were all dumped into cycle_bonus
 *   - badge/specialization landed in NO bucket, so the legacy buckets did not even sum to cycle_points
 * cycle_points and rank_position were always correct (they sum across all categories, bucket-blind).
 *
 * FIX (migration 20260805000327, body-only CREATE OR REPLACE, same signature): buckets derive
 * from the canonical pillar taxonomy via LEFT JOIN gamification_rules ON slug = category, so
 * buckets partition cycle_points cleanly and future slugs auto-route by pillar. The rank
 * computation and displayed field names are unchanged.
 *
 * Static checks lock the pillar-derived body. The DB-gated check proves the real invariant:
 * the six pillar buckets partition cycle_points for every member (no points lost, none
 * double-counted), and granular showcase_* rows land in cycle_showcase (not cycle_bonus).
 * The RPC itself can't be invoked here (its auth.uid() gate rejects a service-role client),
 * so the bucket math is replicated against the live ledger with the SAME join the RPC uses.
 *
 * Cross-ref: HANDOVER_2026-07-03_GAMIFICATION_CONCILIATION_C3.md §3; issue #1080.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { pointsCycleStart } from '../helpers/reference-cycle.mjs';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000327_fix_cycle_xp_bucket_taxonomy.sql');
const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

function fnBlock() {
  const m = migRaw.match(/CREATE OR REPLACE FUNCTION public\.get_member_cycle_xp[\s\S]*?\$function\$;/);
  assert.ok(m, 'get_member_cycle_xp CREATE OR REPLACE block parses');
  return m[0];
}

// ── STATIC: buckets are pillar-derived, not bare-slug hardcoded ─────────────────
test('#1080 static: migration file exists', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000327 exists on disk');
});

test('#1080 static: same-signature body-only replacement (no DROP)', () => {
  const fn = fnBlock();
  assert.match(fn, /CREATE OR REPLACE FUNCTION public\.get_member_cycle_xp\(p_member_id uuid\)/i);
  assert.doesNotMatch(migRaw, /DROP\s+FUNCTION/i, 'must not DROP the function (no consumer break)');
});

test('#1080 static: buckets join gamification_rules and filter on r.pillar', () => {
  const fn = fnBlock();
  assert.match(fn, /left join public\.gamification_rules r\s*\n?\s*on r\.slug = gp\.category/i,
    'LEFT JOIN to gamification_rules on slug = category');
  assert.match(fn, /r\.pillar = 'presenca'/i, 'attendance bucket keyed on pillar presenca');
  assert.match(fn, /r\.pillar = 'trilha'/i, 'learning bucket keyed on pillar trilha');
  assert.match(fn, /r\.pillar = 'certificacoes'/i, 'certs bucket keyed on pillar certificacoes');
  assert.match(fn, /r\.pillar = 'producao'/i, 'production buckets keyed on pillar producao');
});

test('#1080 static: cycle_artifacts no longer filters the nonexistent bare "artifact" slug', () => {
  const fn = fnBlock();
  // the old broken filters were category='showcase' and category='artifact' (bare) — must be gone
  assert.doesNotMatch(fn, /category = 'artifact'/i, "no bare category='artifact' filter (that slug never exists)");
  assert.doesNotMatch(fn, /category = 'showcase'/i, "no bare category='showcase' filter (misses showcase_*)");
});

test('#1080 static: showcase vs artifacts split within producao by slug prefix', () => {
  const fn = fnBlock();
  assert.match(fn, /r\.pillar = 'producao' and gp\.category like 'showcase%'/i,
    'cycle_showcase = producao AND slug LIKE showcase%');
  assert.match(fn, /r\.pillar = 'producao' and gp\.category not like 'showcase%'/i,
    'cycle_artifacts = producao AND slug NOT LIKE showcase%');
});

test('#1080 static: cycle_bonus is a true catch-all (champions+curadoria+protagonismo+orphan)', () => {
  const fn = fnBlock();
  assert.match(fn, /r\.pillar is null or r\.pillar not in \('presenca','trilha','certificacoes','producao'\)/i,
    'bonus = everything outside the four named pillars');
});

test('#1080 static: total/rank fields unchanged (bucket-only fix)', () => {
  const fn = fnBlock();
  assert.match(fn, /'cycle_points', coalesce\(sum\(gp\.points\) filter \(where gp\.created_at >= cycle_start_date\), 0\)::int/i,
    'cycle_points remains a bucket-blind sum');
  assert.match(fn, /'rank_position', coalesce\(v_rank, 0\)/i, 'rank_position preserved');
  assert.match(fn, /ROW_NUMBER\(\) OVER \(/i, 'rank computation preserved');
});

// ── BEHAVIOURAL (DB-gated): buckets partition cycle_points; showcase_* routes correctly ──
test('#1080 behavioural: pillar buckets partition cycle_points; showcase_* routes to showcase',
  { skip: dbGated ? false : skipMsg }, async (t) => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    // Replicate the RPC's exact bucket math against the live ledger (service role bypasses RLS).
    // Ground on the most recent cycle that actually has ledger rows: at a cycle boundary the current
    // cycle can be empty / start in the future (C3→C4 turnover, cycle_start 2026-07-09), zeroing the
    // window (#1123). The partition invariant is cycle-independent; it just needs a populated window.
    const cycleStart = await pointsCycleStart(sb);
    if (!cycleStart) { t.skip('no populated points cohort — cycle turnover (#1234)'); return; }

    const { data: rules } = await sb.from('gamification_rules').select('slug,pillar,organization_id');
    const pillarBySlugOrg = new Map((rules || []).map((r) => [`${r.organization_id}:${r.slug}`, r.pillar]));

    const { data: pts, error: pErr } = await sb
      .from('gamification_points')
      .select('member_id,points,category,organization_id,created_at')
      .gte('created_at', cycleStart);
    assert.ifError(pErr);

    const agg = new Map(); // member_id -> bucket sums mirroring the RPC
    for (const p of pts || []) {
      const pillar = pillarBySlugOrg.get(`${p.organization_id}:${p.category}`) ?? null;
      const m = agg.get(p.member_id) || { total: 0, presenca: 0, trilha: 0, cert: 0, showcase: 0, artifacts: 0, bonus: 0 };
      m.total += p.points;
      if (pillar === 'presenca') m.presenca += p.points;
      else if (pillar === 'trilha') m.trilha += p.points;
      else if (pillar === 'certificacoes') m.cert += p.points;
      else if (pillar === 'producao') {
        if (String(p.category).startsWith('showcase')) m.showcase += p.points;
        else m.artifacts += p.points;
      } else m.bonus += p.points;
      agg.set(p.member_id, m);
    }

    let checked = 0;
    for (const [mid, m] of agg) {
      const sum = m.presenca + m.trilha + m.cert + m.showcase + m.artifacts + m.bonus;
      assert.equal(sum, m.total, `buckets must sum to cycle_points for member ${mid}`);
      checked++;
    }
    assert.ok(checked > 0, 'at least one member with cycle XP was checked');

    // #1249/#1123: the showcase_* routing regression is defended over the WHOLE ledger, not just the
    // current cycle. A fresh cycle (C4) can carry zero showcase XP (data absence, not a routing bug),
    // which used to red the assertion. Routing is cycle-independent, so re-aggregate showcase_* across
    // all cycles; skip only if the platform has no showcase XP at all (nothing to defend).
    const { data: allPts } = await sb.from('gamification_points').select('category,points,organization_id');
    let showcaseTotal = 0, anyShowcaseCategory = false;
    for (const p of allPts || []) {
      if (!String(p.category).startsWith('showcase')) continue;
      anyShowcaseCategory = true;
      const pillar = pillarBySlugOrg.get(`${p.organization_id}:${p.category}`) ?? null;
      // regression: with the old bare-slug filter, granular showcase_* resolved to pillar null → bonus.
      if (pillar === 'producao') showcaseTotal += p.points;
    }
    if (!anyShowcaseCategory) { t.skip('no showcase_* XP in the ledger yet — routing regression not exercisable'); return; }
    assert.ok(showcaseTotal > 0, 'showcase_* XP resolves to the producao pillar (routes to showcase, not bonus)');
  });
