import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// p271 #365c — sortable admin/selection table headers with visible sort indicator
// Frontend-only UX hotfix following #365 (data fix), #365b (rank dimension).
// PM rule: sort REORDERS visible rows only — it does NOT recompute ranks.
// objective_rank + rank_researcher + rank_leader stay canonical from backend cohort.

const PAGE = readFileSync('src/pages/admin/selection.astro', 'utf8');

describe('p271 #365c sortable headers with sort indicator', () => {
  describe('sortable column coverage (10 expected)', () => {
    const SORTABLE_COLUMNS = [
      'applicant_name',
      'role_applied',
      'chapter',
      'objective_score',
      'leader_score',
      'interview_score',
      'final_score',
      'objective_rank',
      'rank',
      'application_date',
    ];
    for (const col of SORTABLE_COLUMNS) {
      it(`TH with data-sort="${col}" exists`, () => {
        assert.match(
          PAGE,
          new RegExp(`data-sort="${col}"`),
          `TH for ${col} must exist (frontend hotfix p271 wires sort on this column)`
        );
      });
    }
  });

  describe('Track + Capítulo TH upgrade (were non-sortable pre-p271)', () => {
    it('Track TH is now sortable (data-sort="role_applied" + cursor-pointer)', () => {
      assert.match(
        PAGE,
        /<th[^>]*cursor-pointer[^>]*data-sort="role_applied"[^>]*>\{t\('admin\.selection\.colTrack', lang\)\}/,
        'Track TH must wire to role_applied + show pointer cursor for sortability discoverability'
      );
    });

    it('Capítulo TH is now sortable (data-sort="chapter" + cursor-pointer)', () => {
      assert.match(
        PAGE,
        /<th[^>]*cursor-pointer[^>]*data-sort="chapter"[^>]*>\{t\('admin\.selection\.chapter', lang\)\}/,
        'Capítulo TH must wire to chapter + show pointer cursor'
      );
    });
  });

  describe('sort-arrow span on every sortable TH (visible direction indicator)', () => {
    const SORTABLE_COLUMNS = [
      'applicant_name', 'role_applied', 'chapter',
      'objective_score', 'leader_score', 'interview_score', 'final_score',
      'objective_rank', 'rank', 'application_date',
    ];
    for (const col of SORTABLE_COLUMNS) {
      it(`TH[data-sort="${col}"] contains <span class="sort-arrow ...">`, () => {
        // Match: <th ... data-sort="COL" ...>...colLabel...<span class="sort-arrow ...">
        const thRegex = new RegExp(
          `<th[^>]*data-sort="${col}"[^>]*>[^<]*\\{t\\('[^']+', lang\\)\\}<span class="sort-arrow[^"]*"`
        );
        assert.match(
          PAGE,
          thRegex,
          `TH for ${col} must include a sort-arrow span placeholder (JS populates ↑/↓ at runtime)`
        );
      });
    }

    it('all 10 sort-arrow spans are present (single global count)', () => {
      const matches = PAGE.match(/<span class="sort-arrow ml-1 text-navy"><\/span>/g) || [];
      assert.equal(
        matches.length,
        10,
        `exactly 10 sort-arrow spans expected (1 per sortable TH); found ${matches.length}`
      );
    });
  });

  describe('sort direction defaults (column-type aware first-click)', () => {
    it('SORT_ASC_FIRST set declares text + rank columns', () => {
      assert.match(
        PAGE,
        /const SORT_ASC_FIRST = new Set\(\[[\s\S]*?'applicant_name', 'role_applied', 'chapter', 'objective_rank', 'rank',[\s\S]*?\]\);/,
        'ASC-first column set must include all 3 text fields + 2 rank fields (scores + dates default to DESC first)'
      );
    });

    it('defaultSortAsc(col) helper exists and returns SORT_ASC_FIRST membership', () => {
      assert.match(
        PAGE,
        /function defaultSortAsc\(col: string\): boolean \{ return SORT_ASC_FIRST\.has\(col\); \}/,
        'defaultSortAsc must be a pure membership check — no fancier logic that could drift'
      );
    });

    it('click handler uses defaultSortAsc on column change (not the old applicant_name literal)', () => {
      assert.match(
        PAGE,
        /sortCol = col; sortAsc = defaultSortAsc\(col\);/,
        'on column change, sortAsc must derive from defaultSortAsc — single source of truth'
      );
      assert.doesNotMatch(
        PAGE,
        /sortAsc = col === 'applicant_name'/,
        'legacy hardcoded applicant_name check must be removed (replaced by defaultSortAsc lookup)'
      );
    });
  });

  describe('updateSortIndicators function (DOM mutation per sort state)', () => {
    it('updateSortIndicators function exists', () => {
      assert.match(
        PAGE,
        /function updateSortIndicators\(\) \{/,
        'updateSortIndicators must exist as a named function (reused by click handler + init)'
      );
    });

    it('updateSortIndicators iterates all [data-sort] THs', () => {
      assert.match(
        PAGE,
        /function updateSortIndicators\(\) \{[\s\S]*?document\.querySelectorAll<HTMLElement>\('\[data-sort\]'\)\.forEach\(th =>/,
        'must iterate all THs with data-sort (not just the active one — must clear stale arrows)'
      );
    });

    it('updateSortIndicators sets ↑ for asc, ↓ for desc, empty for non-active', () => {
      assert.match(
        PAGE,
        /arrow\.textContent = th\.dataset\.sort === sortCol \? \(sortAsc \? '↑' : '↓'\) : '';/,
        'textContent assignment must use ternary on dataset.sort === sortCol for active vs inactive arrow text'
      );
    });

    it('click handler calls updateSortIndicators BEFORE applyFilters (so DOM reflects new state on re-render)', () => {
      assert.match(
        PAGE,
        /sortAsc = defaultSortAsc\(col\); \}\s*updateSortIndicators\(\);\s*applyFilters\(\);/,
        'updateSortIndicators must be invoked between state change and re-render'
      );
    });

    it('updateSortIndicators called once after handler setup (initial render reflects default sortCol)', () => {
      assert.match(
        PAGE,
        /\/\/ Initial indicator render[\s\S]*?updateSortIndicators\(\);/,
        'initial call ensures default ↓ on Final column appears immediately on page load'
      );
    });
  });

  describe('forward-defense: sort does NOT recompute ranks (PM rule)', () => {
    it('SORT_ASC_FIRST does NOT include score columns (scores must default DESC)', () => {
      // Extract the SET literal text once
      const setMatch = PAGE.match(/const SORT_ASC_FIRST = new Set\(\[([\s\S]*?)\]\);/);
      assert.ok(setMatch, 'SORT_ASC_FIRST set must exist');
      const setBody = setMatch[1];
      const banned = ['objective_score', 'leader_score', 'interview_score', 'final_score'];
      for (const col of banned) {
        assert.ok(
          !setBody.includes(`'${col}'`),
          `${col} must NOT be in SORT_ASC_FIRST — PM rule: scores default to DESC first (best first for cut decisions)`
        );
      }
    });

    it('comparator at applyFilters remains generic a[sortCol] (no per-column special-case)', () => {
      assert.match(
        PAGE,
        /let va = a\[sortCol\], vb = b\[sortCol\];/,
        'comparator must stay generic — no special branches for rank/score that could drift from cohort semantics'
      );
    });

    it('updateSortIndicators body has NO arithmetic on objective_rank or rank fields', () => {
      const fnMatch = PAGE.match(/function updateSortIndicators\(\) \{[\s\S]*?\n {4}\}/);
      assert.ok(fnMatch, 'updateSortIndicators function body must be extractable');
      const fnBody = fnMatch[0];
      assert.doesNotMatch(
        fnBody,
        /r\.objective_rank|r\.rank|rank_researcher|rank_leader/,
        'updateSortIndicators must NOT touch rank fields — it only renders ↑/↓ on TH'
      );
    });

    it('click handler body has NO mutation on r.objective_rank / r.rank values', () => {
      // Match the handler block
      const handlerMatch = PAGE.match(
        /document\.querySelectorAll<HTMLElement>\('\[data-sort\]'\)\.forEach\(th => \{\s*th\.addEventListener\('click', \(\) => \{[\s\S]*?applyFilters\(\);\s*\}\);\s*\}\);/
      );
      assert.ok(handlerMatch, 'sort click handler must be present');
      const handlerBody = handlerMatch[0];
      assert.doesNotMatch(
        handlerBody,
        /r\.objective_rank\s*=|r\.rank\s*=/,
        'click handler must NEVER mutate rank values — ranks come from backend cohort and are canonical'
      );
    });
  });
});
