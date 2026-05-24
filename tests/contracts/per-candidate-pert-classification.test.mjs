import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const SELECTION_PAGE = readFileSync('src/pages/admin/selection.astro', 'utf8');
const I18N_PT = readFileSync('src/i18n/pt-BR.ts', 'utf8');
const I18N_EN = readFileSync('src/i18n/en-US.ts', 'utf8');
const I18N_ES = readFileSync('src/i18n/es-LATAM.ts', 'utf8');

describe('p245 #229a per-candidate PERT classification', () => {
  describe('selection.astro helpers', () => {
    it('declares bandClassify returning {color,label,delta} with above/within/below/none labels', () => {
      assert.match(
        SELECTION_PAGE,
        /function bandClassify\(score: any, cutoff: any\): \{ color: string; label: 'above'\|'within'\|'below'\|'none'; delta: number \| null \}/,
        'bandClassify signature must include the 4 label literals + delta typing'
      );
      assert.match(SELECTION_PAGE, /return \{ color: 'bg-red-50 text-red-700', label: 'below', delta \};/);
      assert.match(SELECTION_PAGE, /return \{ color: 'bg-emerald-50 text-emerald-700', label: 'above', delta \};/);
      assert.match(SELECTION_PAGE, /return \{ color: 'bg-amber-50 text-amber-700', label: 'within', delta \};/);
    });

    it('declares formatDelta with sign prefix + 1-decimal formatting', () => {
      assert.match(SELECTION_PAGE, /function formatDelta\(d: number \| null\): string/);
      assert.match(SELECTION_PAGE, /const sign = d >= 0 \? '\+' : '';/);
      assert.match(SELECTION_PAGE, /return `\$\{sign\}\$\{d\.toFixed\(1\)\}`;/);
    });

    it('declares pertBandChip returning HTML chip with band label + delta', () => {
      assert.match(SELECTION_PAGE, /function pertBandChip\(score: any, cutoff: any\): string/);
      assert.match(
        SELECTION_PAGE,
        /const labelText = label === 'above' \? T\.pertBandAbove : label === 'below' \? T\.pertBandBelow : T\.pertBandWithin;/
      );
      assert.match(
        SELECTION_PAGE,
        /return `<div class="text-\[10px\] font-bold mt-0\.5 px-1\.5 py-0\.5 rounded \$\{color\}">\$\{esc\(labelText\)\}\$\{esc\(deltaText\)\}<\/div>`;/
      );
    });

    it('declares pertFullTooltip with all 6 placeholders ({score,lower,upper,target,n,method})', () => {
      assert.match(SELECTION_PAGE, /function pertFullTooltip\(score: any, cutoff: any\): string/);
      for (const ph of ['{score}', '{lower}', '{upper}', '{target}', '{n}', '{method}']) {
        assert.ok(
          SELECTION_PAGE.includes(`.replace('${ph}',`),
          `pertFullTooltip must replace ${ph} placeholder`
        );
      }
    });

    it('declares leaderExtraChip handling disabled + classified branches separately', () => {
      assert.match(SELECTION_PAGE, /function leaderExtraChip\(score: any, cutoff: any\): string/);
      assert.match(
        SELECTION_PAGE,
        /if \(method === 'disabled'\) \{[\s\S]*?T\.leaderExtraDisabledChip[\s\S]*?\.replace\('\{n\}', String\(cohortN \?\? '\?'\)\)/,
        'disabled branch must use leaderExtraDisabledChip template + {n} replacement'
      );
    });

    it('leaderExtraChip prefixes leader_extra dimension with LE marker', () => {
      assert.match(
        SELECTION_PAGE,
        /return `<div class="text-\[10px\] font-bold mt-0\.5 px-1\.5 py-0\.5 rounded \$\{color\}" title="\$\{esc\(pertFullTooltip\(score, cutoff\)\)\}">LE /,
        'classified LE chip must include LE prefix + own tooltip'
      );
    });
  });

  describe('per-app TD render', () => {
    it('research_score TD calls pertBandChip(r.research_score, currentCycle?.pert_cutoff)', () => {
      assert.match(
        SELECTION_PAGE,
        /\$\{pertBandChip\(r\.research_score, currentCycle\?\.pert_cutoff\)\}/,
        'research_score TD must call pertBandChip with cycle pert_cutoff (objective rule)'
      );
    });

    it('research_score TD uses pertFullTooltip in TD title', () => {
      assert.match(
        SELECTION_PAGE,
        /<td class="px-4 py-2\.5 text-\[12px\] font-mono" title="\$\{esc\(pertFullTooltip\(r\.research_score, currentCycle\?\.pert_cutoff\)\)\}"/,
        'research_score TD title must use pertFullTooltip helper (enriched: target + banda + cohort + method)'
      );
    });

    it('leader_score TD calls leaderExtraChip(r.leader_extra_pert_score, leader_extra_cutoff)', () => {
      assert.match(
        SELECTION_PAGE,
        /\$\{leaderExtraChip\(r\.leader_extra_pert_score, \(currentCycle as any\)\?\.leader_extra_cutoff\)\}/,
        'leader_score TD must wire leader_extra_pert_score against leader_extra_cutoff (NOT pert_cutoff)'
      );
    });

    it('leader_score TD does NOT use bandColorClass against pert_cutoff (PM rule: nao comparar lider contra regua objetiva)', () => {
      // Forward-defense: the old line was `bandColorClass(r.leader_score, currentCycle?.pert_cutoff)`.
      // After #229a the leader_score TD must NOT pass pert_cutoff to a band classifier.
      assert.doesNotMatch(
        SELECTION_PAGE,
        /bandColorClass\(r\.leader_score, currentCycle\?\.pert_cutoff\)/,
        'PM rule (#229a): leader_score must NOT be color-coded against pert_cutoff'
      );
      assert.doesNotMatch(
        SELECTION_PAGE,
        /bandClassify\(r\.leader_score, currentCycle\?\.pert_cutoff\)/,
        'PM rule (#229a): leader_score must NOT be classified against pert_cutoff'
      );
    });
  });

  describe('cycle chip presence (p197b + p232 #229 Phase 2 baseline)', () => {
    it('renders cycle pert-cutoff-chip div placeholder', () => {
      assert.match(
        SELECTION_PAGE,
        /id="pert-cutoff-chip"/,
        'cycle-level objective PERT cutoff chip must remain present (p197b baseline)'
      );
    });

    it('renders cycle leader-extra-cutoff-chip div placeholder', () => {
      assert.match(
        SELECTION_PAGE,
        /id="leader-extra-cutoff-chip"/,
        'cycle-level leader_extra cutoff chip must remain present (p232 #229 Phase 2 baseline)'
      );
    });
  });

  describe('i18n parity across 3 dictionaries', () => {
    const KEYS = [
      "'admin.selection.pertBandAbove'",
      "'admin.selection.pertBandWithin'",
      "'admin.selection.pertBandBelow'",
      "'admin.selection.pertBandTooltipFull'",
      "'admin.selection.leaderExtraDisabledChip'",
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

    it('pertBandTooltipFull template includes all 6 placeholders in all 3 dicts', () => {
      for (const [name, dict] of [['pt-BR', I18N_PT], ['en-US', I18N_EN], ['es-LATAM', I18N_ES]]) {
        for (const ph of ['{score}', '{lower}', '{upper}', '{target}', '{n}', '{method}']) {
          const block = dict.match(/'admin\.selection\.pertBandTooltipFull': '([^']+)'/);
          assert.ok(block, `${name} must have pertBandTooltipFull string`);
          assert.ok(block[1].includes(ph), `${name} pertBandTooltipFull must include ${ph} placeholder`);
        }
      }
    });
  });

  describe('T object surface in page frontmatter + fallback', () => {
    it('frontmatter T object wires all 5 new i18n keys via t() calls', () => {
      assert.match(SELECTION_PAGE, /pertBandAbove: t\('admin\.selection\.pertBandAbove', lang\),/);
      assert.match(SELECTION_PAGE, /pertBandWithin: t\('admin\.selection\.pertBandWithin', lang\),/);
      assert.match(SELECTION_PAGE, /pertBandBelow: t\('admin\.selection\.pertBandBelow', lang\),/);
      assert.match(SELECTION_PAGE, /pertBandTooltipFull: t\('admin\.selection\.pertBandTooltipFull', lang\),/);
      assert.match(SELECTION_PAGE, /leaderExtraDisabledChip: t\('admin\.selection\.leaderExtraDisabledChip', lang\),/);
    });

    it('fallback T object inside script declares all 5 new keys (resilience when window.__SEL_I18N missing)', () => {
      assert.match(SELECTION_PAGE, /pertBandAbove: 'Acima',/);
      assert.match(SELECTION_PAGE, /pertBandWithin: 'Na banda',/);
      assert.match(SELECTION_PAGE, /pertBandBelow: 'Abaixo',/);
      assert.match(SELECTION_PAGE, /pertBandTooltipFull: 'Score \{score\} · Banda \{lower\}–\{upper\} \(target \{target\}\) · cohort n=\{n\} · método \{method\}',/);
      assert.match(SELECTION_PAGE, /leaderExtraDisabledChip: 'Régua líder: n=\{n\}<10',/);
    });
  });
});
