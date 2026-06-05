import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const SELECTION_PAGE = readFileSync('src/pages/admin/selection.astro', 'utf8');
const I18N_PT = readFileSync('src/i18n/pt-BR.ts', 'utf8');
const I18N_EN = readFileSync('src/i18n/en-US.ts', 'utf8');
const I18N_ES = readFileSync('src/i18n/es-LATAM.ts', 'utf8');

describe('p247 #229b Frontend — per-candidate final-score régua + interview score', () => {
  describe('selection.astro: finalScoreChip helper', () => {
    it('declares finalScoreChip(row) helper with correct signature', () => {
      assert.match(
        SELECTION_PAGE,
        /function finalScoreChip\(row: any\): string/,
        'helper must accept a row (per-app fields) — not a separate (score, cutoff) tuple, since p246 backend resolves track per app'
      );
    });

    it('finalScoreChip reads r.final_score_pert_* per-app fields (track-resolved by backend p246)', () => {
      const requiredReads = [
        'row?.final_score',
        'row?.final_score_pert_cutoff_method',
        'row?.final_score_pert_cohort_n',
        'row?.final_score_pert_target',
        'row?.final_score_pert_band_lower',
        'row?.final_score_pert_band_upper',
      ];
      for (const ref of requiredReads) {
        assert.ok(
          SELECTION_PAGE.includes(ref),
          `finalScoreChip must read ${ref} (per-app, track-resolved by backend)`
        );
      }
    });

    it('finalScoreChip handles method === "disabled" branch with T.finalScoreDisabledChip template', () => {
      assert.match(
        SELECTION_PAGE,
        /if \(method === 'disabled'\) \{[\s\S]*?T\.finalScoreDisabledChip[\s\S]*?\.replace\('\{n\}', String\(cohortN \?\? '\?'\)\)/,
        'disabled branch must use finalScoreDisabledChip template + {n} replacement (mirrors leaderExtraChip pattern)'
      );
    });

    it('finalScoreChip delegates classification to bandClassify (PM rule: reuse — no parallel classifier)', () => {
      // finalScoreChip body must invoke bandClassify(score, cutoff) — not reimplement comparison
      const helperBody = SELECTION_PAGE.split('function finalScoreChip(row: any): string')[1]?.split('\n  function ')[0] || '';
      assert.ok(
        helperBody.includes('bandClassify(score, cutoff)'),
        'finalScoreChip must delegate to bandClassify — keeps classification logic in one place'
      );
    });

    it('finalScoreChip uses pertFullTooltip for hover-rich tooltip (cohort + method visible)', () => {
      const helperBody = SELECTION_PAGE.split('function finalScoreChip(row: any): string')[1]?.split('\n  function ')[0] || '';
      assert.ok(
        helperBody.includes('pertFullTooltip(score, cutoff)'),
        'finalScoreChip must reuse pertFullTooltip — operator sees same tooltip shape as research/leader chips'
      );
    });
  });

  describe('selection.astro: 2 new TH headers between Líder and Rank', () => {
    it('TH "colInterviewScore" with data-sort="interview_score" + colInterviewScoreHint title', () => {
      assert.match(
        SELECTION_PAGE,
        /data-sort="interview_score" title=\{t\('admin\.selection\.colInterviewScoreHint', lang\)\}>\{t\('admin\.selection\.colInterviewScore', lang\)\}(?:<span[^<]*<\/span>)?<\/th>/,
        'TH for Nota Entrevista must be sortable + carry i18n hint tooltip'
      );
    });

    it('TH "colFinal" with data-sort="final_score" + colFinalHint title', () => {
      assert.match(
        SELECTION_PAGE,
        /data-sort="final_score" title=\{t\('admin\.selection\.colFinalHint', lang\)\}>\{t\('admin\.selection\.colFinal', lang\)\}(?:<span[^<]*<\/span>)?<\/th>/,
        'TH for Score Final must be sortable + carry i18n hint tooltip'
      );
    });

    it('TH ordering: interview_score TH precedes final_score TH; both fall between leader_score and rank', () => {
      const leaderIdx = SELECTION_PAGE.indexOf('data-sort="leader_score"');
      const intervIdx = SELECTION_PAGE.indexOf('data-sort="interview_score"');
      const finalIdx = SELECTION_PAGE.indexOf('data-sort="final_score"');
      const rankIdx = SELECTION_PAGE.indexOf('data-sort="rank"');
      assert.ok(leaderIdx > 0 && intervIdx > leaderIdx, 'interview_score TH must come after leader_score');
      assert.ok(finalIdx > intervIdx, 'final_score TH must come after interview_score');
      assert.ok(rankIdx > finalIdx, 'rank TH must come after final_score');
    });
  });

  describe('selection.astro: 2 new TDs in row render', () => {
    it('interview_score TD renders plain number — NO chip (PM rule: não criar régua para entrevista)', () => {
      assert.match(
        SELECTION_PAGE,
        /<div class="\$\{r\.interview_score != null \? 'font-semibold text-\[var\(--text-primary\)\]' : 'text-\[var\(--text-muted\)\]'\}">\$\{r\.interview_score != null \? Number\(r\.interview_score\)\.toFixed\(1\) : '—'\}<\/div>/,
        'interview_score must render as plain number with one-decimal formatting (no chip below)'
      );
    });

    it('final_score TD renders number + finalScoreChip(r) call', () => {
      assert.match(
        SELECTION_PAGE,
        /<div class="\$\{r\.final_score != null \? 'font-semibold text-\[var\(--text-primary\)\]' : 'text-\[var\(--text-muted\)\]'\}">\$\{r\.final_score != null \? Number\(r\.final_score\)\.toFixed\(1\) : '—'\}<\/div>\s*\$\{finalScoreChip\(r\)\}/,
        'final_score TD must render number + finalScoreChip(r) below (track-resolved per app)'
      );
    });

    it('colspan in empty/error state bumped to 16 (was 15 pre-p270, was 13 pre-p247)', () => {
      const colspan16Count = (SELECTION_PAGE.match(/colspan="16"/g) || []).length;
      assert.ok(
        colspan16Count >= 2,
        `expected colspan="16" in both error + empty state placeholders post-p270 (+1 Rank Obj col) (got ${colspan16Count})`
      );
      const colspan15Count = (SELECTION_PAGE.match(/colspan="15"/g) || []).length;
      assert.equal(colspan15Count, 0, 'no leftover colspan="15" — must all be bumped to 16 post-p270 (+1 col on top of p247 baseline)');
    });
  });

  describe('forward-defense: PM "do-not" rules', () => {
    it('NO interview_score chip or régua introduced (PM rule: não criar régua para entrevista)', () => {
      // The interview_score TD must NOT call pertBandChip / leaderExtraChip / finalScoreChip / any classifier
      const interviewTdRegex = /<div class="\$\{r\.interview_score != null[\s\S]*?<\/td>/;
      const match = SELECTION_PAGE.match(interviewTdRegex);
      assert.ok(match, 'interview_score TD must be present');
      const interviewTdBlock = match[0];
      assert.doesNotMatch(interviewTdBlock, /pertBandChip\(/, 'interview_score TD must NOT call pertBandChip');
      assert.doesNotMatch(interviewTdBlock, /leaderExtraChip\(/, 'interview_score TD must NOT call leaderExtraChip');
      assert.doesNotMatch(interviewTdBlock, /finalScoreChip\(/, 'interview_score TD must NOT call finalScoreChip');
      assert.doesNotMatch(interviewTdBlock, /bandClassify\(/, 'interview_score TD must NOT call bandClassify');
    });

    it('finalScoreChip does NOT reference PERT Objetiva (currentCycle?.pert_cutoff) for final classification', () => {
      // PM rule: gating semantic is sequential — PERT Objetiva = gate to interview;
      // PERT Final = post-interview comparison. They must be wired to DIFFERENT cutoffs.
      const helperBody = SELECTION_PAGE.split('function finalScoreChip(row: any): string')[1]?.split('\n  function ')[0] || '';
      assert.doesNotMatch(
        helperBody,
        /currentCycle\?\.pert_cutoff/,
        'finalScoreChip must NOT use cycle pert_cutoff (objective rule) — it must use per-app r.final_score_pert_* (track-resolved final rule)'
      );
      assert.doesNotMatch(
        helperBody,
        /currentCycle\?\.leader_extra_cutoff/,
        'finalScoreChip must NOT use leader_extra_cutoff — final régua is its own dimension, separate from leader_extra'
      );
    });

    it('NO interview_score_pert_* columns or chip introduced anywhere in the page', () => {
      assert.doesNotMatch(SELECTION_PAGE, /interview_score_pert/, 'no interview_score_pert_* references — PR1 backend deliberately avoided this column');
      assert.doesNotMatch(SELECTION_PAGE, /interviewScoreChip/, 'no interviewScoreChip helper — interview is just a number per PM rule');
    });
  });

  describe('T object wiring (frontmatter + fallback) for 2 helper-consumed keys', () => {
    it('frontmatter T object wires finalScoreCutoffTooltip + finalScoreDisabledChip via t()', () => {
      assert.match(SELECTION_PAGE, /finalScoreCutoffTooltip: t\('admin\.selection\.finalScoreCutoffTooltip', lang\),/);
      assert.match(SELECTION_PAGE, /finalScoreDisabledChip: t\('admin\.selection\.finalScoreDisabledChip', lang\),/);
    });

    it('fallback T object inside script declares finalScoreDisabledChip (resilience when window.__SEL_I18N missing)', () => {
      assert.match(SELECTION_PAGE, /finalScoreDisabledChip: 'Régua final: n=\{n\}<10',/);
    });
  });

  describe('i18n parity across 3 dictionaries (6 new keys)', () => {
    const KEYS = [
      "'admin.selection.colInterviewScore'",
      "'admin.selection.colInterviewScoreHint'",
      "'admin.selection.colFinal'",
      "'admin.selection.colFinalHint'",
      "'admin.selection.finalScoreCutoffTooltip'",
      "'admin.selection.finalScoreDisabledChip'",
    ];
    for (const key of KEYS) {
      it(`pt-BR has ${key}`, () => {
        assert.ok(I18N_PT.includes(key), `pt-BR.ts must declare ${key}`);
      });
      it(`en-US has ${key}`, () => {
        assert.ok(I18N_EN.includes(key), `en-US.ts must declare ${key}`);
      });
      it(`es-LATAM has ${key}`, () => {
        assert.ok(I18N_ES.includes(key), `es-LATAM.ts must declare ${key}`);
      });
    }

    it('finalScoreDisabledChip template includes {n} placeholder in all 3 dicts (cohort_n surfacing)', () => {
      for (const [name, dict] of [['pt-BR', I18N_PT], ['en-US', I18N_EN], ['es-LATAM', I18N_ES]]) {
        const block = dict.match(/'admin\.selection\.finalScoreDisabledChip': '([^']+)'/);
        assert.ok(block, `${name} must have finalScoreDisabledChip string`);
        assert.ok(block[1].includes('{n}'), `${name} finalScoreDisabledChip must include {n} placeholder (cohort_n display)`);
      }
    });
  });
});
