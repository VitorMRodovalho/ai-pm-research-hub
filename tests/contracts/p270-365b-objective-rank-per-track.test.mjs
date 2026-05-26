import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

// p270 #365b — objective rank per track in get_selection_dashboard payload
// Server-side ROW_NUMBER() OVER (PARTITION BY role_applied ORDER BY objective_score_avg
// DESC NULLS LAST, id ASC). PM dispatched Opção B (server-side) over Opção A (client-side)
// because rank must be stable across UI filters for governance — filtering by chapter/
// status/search must NOT shift a candidate's rank.

const MIG_PATH = 'supabase/migrations/20260805000049_p270_365b_objective_rank_per_track.sql';
const SELECTION_PAGE_PATH = 'src/pages/admin/selection.astro';

const MIG_EXISTS = existsSync(MIG_PATH);
const MIG = MIG_EXISTS ? readFileSync(MIG_PATH, 'utf8') : '';
const PAGE = readFileSync(SELECTION_PAGE_PATH, 'utf8');
const I18N_PT = readFileSync('src/i18n/pt-BR.ts', 'utf8');
const I18N_EN = readFileSync('src/i18n/en-US.ts', 'utf8');
const I18N_ES = readFileSync('src/i18n/es-LATAM.ts', 'utf8');

describe('p270 #365b objective rank per track', () => {
  describe('migration body (server-side rank computation)', () => {
    it('migration file exists at canonical timestamp 20260805000049', () => {
      assert.ok(MIG_EXISTS, `migration must exist at ${MIG_PATH}`);
    });

    it('preserves get_selection_dashboard signature (p_cycle_code text DEFAULT NULL)', () => {
      assert.match(
        MIG,
        /CREATE OR REPLACE FUNCTION public\.get_selection_dashboard\(p_cycle_code text DEFAULT NULL\)/,
        'signature must stay byte-identical (no DROP+CREATE; preserve DEFAULT per SEDIMENT-238.C)'
      );
    });

    it('preserves SECURITY DEFINER + pinned search_path public,pg_temp', () => {
      assert.match(MIG, /SECURITY DEFINER/);
      assert.match(MIG, /SET search_path TO 'public', 'pg_temp'/);
    });

    it('preserves RETURNS jsonb + LANGUAGE plpgsql', () => {
      assert.match(MIG, /RETURNS jsonb/);
      assert.match(MIG, /LANGUAGE plpgsql/);
    });

    it('uses ROW_NUMBER window function PARTITION BY sa.role_applied', () => {
      assert.match(
        MIG,
        /ROW_NUMBER\(\)\s*OVER\s*\(\s*PARTITION BY sa\.role_applied/,
        'rank must be track-scoped (researcher cohort separate from leader cohort)'
      );
    });

    it('ORDER BY objective_score_avg DESC NULLS LAST with stable tiebreaker sa.id ASC', () => {
      assert.match(
        MIG,
        /ORDER BY sa\.objective_score_avg DESC NULLS LAST, sa\.id ASC/,
        'primary ORDER BY per PM spec + tiebreaker id ASC for determinism on ties'
      );
    });

    it('window result aliased as objective_rank (cast to int for clean JSON)', () => {
      assert.match(MIG, /\)::int AS objective_rank/);
    });

    it('jsonb_build_object includes objective_rank in applications[] chunk', () => {
      assert.match(MIG, /'objective_rank',\s*a\.objective_rank/);
    });

    it('inner subquery filters cycle_id (efficient partition scope)', () => {
      assert.match(
        MIG,
        /FROM public\.selection_applications sa\s+WHERE sa\.cycle_id = v_cycle_id/,
        'WHERE moved to inner subquery so window function partitions only within cycle rows'
      );
    });

    it('NOTIFY pgrst reload schema at end (PostgREST schema cache refresh)', () => {
      assert.match(MIG, /NOTIFY pgrst, 'reload schema'/);
    });

    it('header includes WHAT/WHY/TIEBREAKER/SCOPE/ROLLBACK provenance comments', () => {
      assert.match(MIG, /-- WHAT:/);
      assert.match(MIG, /-- WHY:/);
      assert.match(MIG, /-- TIEBREAKER:/);
      assert.match(MIG, /-- SCOPE:/);
      assert.match(MIG, /-- ROLLBACK:/);
    });
  });

  describe('migration body forward-defense (PM rule: not from composite/final scores)', () => {
    it('PARTITION BY MUST NOT reference research_score (composite ≡ final for interviewed researchers)', () => {
      assert.doesNotMatch(
        MIG,
        /PARTITION BY[^)]*research_score/,
        '#365 lesson: research_score is composite for interviewed researchers; rank must be objective-only'
      );
    });

    it('PARTITION BY MUST NOT reference final_score (rank is a pre-interview dimension)', () => {
      assert.doesNotMatch(
        MIG,
        /PARTITION BY[^)]*final_score/,
        'final_score includes interview weight; objective rank must be decoupled from interview noise'
      );
    });

    it('ROW_NUMBER OVER MUST NOT ORDER BY research_score', () => {
      assert.doesNotMatch(
        MIG,
        /ROW_NUMBER\(\)\s*OVER\s*\([^)]*ORDER BY[^)]*\bresearch_score\b/,
        'ranking on research_score would inherit the composite bias from #365'
      );
    });

    it('ROW_NUMBER OVER MUST NOT ORDER BY final_score', () => {
      assert.doesNotMatch(
        MIG,
        /ROW_NUMBER\(\)\s*OVER\s*\([^)]*ORDER BY[^)]*\bfinal_score\b/,
        'ranking on final_score would mix objective + interview into the cut-decision dimension'
      );
    });
  });

  describe('frontend (selection.astro)', () => {
    it('TH header declares data-sort="objective_rank" with colObjectiveRank label + colObjectiveRankHint title', () => {
      assert.match(
        PAGE,
        /<th[^>]*data-sort="objective_rank"[^>]*title=\{t\('admin\.selection\.colObjectiveRankHint', lang\)\}[^>]*>\{t\('admin\.selection\.colObjectiveRank', lang\)\}<\/th>/,
        'new TH must be sortable + i18n labeled + tooltip-hinted'
      );
    });

    it('TD renders r.objective_rank with # prefix and graceful — fallback', () => {
      assert.match(
        PAGE,
        /\$\{r\.objective_rank != null \? `#\$\{r\.objective_rank\}` : '<span class="text-\[var\(--text-muted\)\]">—<\/span>'\}/,
        'TD must read r.objective_rank, format as #N when present, fallback to muted — when missing (graceful pre-deploy degradation)'
      );
    });

    it('TD uses T.colObjectiveRankHint in title for hover help', () => {
      assert.match(
        PAGE,
        /title="\$\{esc\(T\.colObjectiveRankHint \|\| ''\)\}"/,
        'TD title hover must mirror TH tooltip via runtime T helper'
      );
    });

    it('colspan updated from 15 to 16 in empty/error rows (+1 new column)', () => {
      assert.doesNotMatch(PAGE, /colspan="15"/, 'colspan 15 must be retired post-p270');
      const matches = PAGE.match(/colspan="16"/g) || [];
      assert.ok(
        matches.length >= 2,
        `colspan="16" should appear at least 2 times (was 2 places at colspan="15"), found ${matches.length}`
      );
    });
  });

  describe('T object wiring (frontmatter + fallback)', () => {
    it('frontmatter T object wires colObjectiveRankHint via t() helper', () => {
      assert.match(
        PAGE,
        /colObjectiveRankHint: t\('admin\.selection\.colObjectiveRankHint', lang\),/,
        'T object accessible in client-side JS via window.__SEL_I18N must be populated'
      );
    });

    it('fallback T object declares colObjectiveRankHint with literal pt-BR string (resilience when window.__SEL_I18N missing)', () => {
      assert.match(
        PAGE,
        /colObjectiveRankHint: 'Rank dentro da trilha/,
        'fallback ensures TD tooltip renders even if i18n bridge fails to load'
      );
    });
  });

  describe('i18n parity across 3 dictionaries', () => {
    const KEYS = [
      "'admin.selection.colObjectiveRank'",
      "'admin.selection.colObjectiveRankHint'",
    ];
    for (const key of KEYS) {
      it(`pt-BR has ${key}`, () => assert.ok(I18N_PT.includes(key), `pt-BR.ts must declare ${key}`));
      it(`en-US has ${key}`, () => assert.ok(I18N_EN.includes(key), `en-US.ts must declare ${key}`));
      it(`es-LATAM has ${key}`, () => assert.ok(I18N_ES.includes(key), `es-LATAM.ts must declare ${key}`));
    }
  });
});
