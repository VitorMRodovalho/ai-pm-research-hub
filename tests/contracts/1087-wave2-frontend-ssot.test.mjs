// #1087 wave 2 — frontend SSOT contract (offline/static).
// Guards the wave's acceptance criteria: no gamification rule VALUE or level
// tier hardcoded in the frontend (ADR-0081 Pattern 47 extended to UI); the
// statement tab consumes get_my_points_statement; champion attribution and the
// LGPD opt-out surfaces exist; every new i18n key is present in all 3 dicts.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(root, p), 'utf8');

const gamPage = read('src/pages/gamification.astro');
const popover = read('src/components/ui/ScoringInfoPopover.tsx');
const profile = read('src/pages/profile.astro');
const tribeTab = read('src/components/tribes/TribeGamificationTab.tsx');
const catalogLib = read('src/lib/gamification-catalog.ts');
const dicts = {
  'pt-BR': read('src/i18n/pt-BR.ts'),
  'en-US': read('src/i18n/en-US.ts'),
  'es-LATAM': read('src/i18n/es-LATAM.ts'),
};

test('G1: ScoringInfoPopover has zero hardcoded XP values and renders the catalog', () => {
  // The old popover carried ~18 literal rows ("50 XP", "20–60 XP"). The rewrite
  // must not reintroduce any digit-XP literal — values interpolate from the catalog.
  assert.equal(popover.match(/\d+\s*(?:–\s*\d+\s*)?XP/g), null,
    'literal "<n> XP" found in ScoringInfoPopover.tsx — rule values must come from the catalog');
  assert.match(popover, /gam:catalog|__GAM_CATALOG/, 'popover must consume the shared catalog');
  assert.match(popover, /ruleXpRange/, 'popover must derive XP labels via the catalog helper');
});

test('G1: gamification page has no hardcoded level tiers or legend values', () => {
  for (const literal of ['0–30 pts', '31–90 pts', '91–200 pts', '201–400 pts', '401+ pts']) {
    assert.ok(!gamPage.includes(literal), `legacy tier literal "${literal}" still in gamification.astro`);
  }
  assert.equal(gamPage.match(/pts\s*>=\s*(31|91|201|401)\b/g), null,
    'hardcoded level threshold check found — thresholds must come from catalog level_thresholds');
  // Old static points-legend chips carried raw PT labels + values.
  for (const legacy of ['Trilha PMI</span>', 'AI &amp; PM</span>', 'AI & PM</span>', 'Especialização</span>']) {
    assert.ok(!gamPage.includes(legacy), `legacy points-legend label "${legacy}" still present`);
  }
  assert.match(gamPage, /level_thresholds/, 'level rendering must reference catalog level_thresholds');
  assert.match(gamPage, /from '\.\.\/lib\/gamification-catalog'/, 'page must import the shared catalog lib');
});

test('G2: My Points tab consumes get_my_points_statement with filters + pagination', () => {
  assert.match(gamPage, /get_my_points_statement/, 'statement RPC not wired');
  assert.match(gamPage, /p_category/, 'category filter param missing');
  assert.match(gamPage, /p_offset/, 'pagination offset param missing');
  assert.match(gamPage, /mp-load-more/, 'load-more control missing');
  // The old raw all-rows PostgREST read must not survive (Credly tier box keeps
  // a reason-scoped read; the statement list itself is RPC-driven).
  assert.equal(gamPage.match(/from\('gamification_points'\)\s*\n?\s*\.select\('\*'\)/g), null,
    'old raw gamification_points statement read still present');
  assert.match(gamPage, /URLSearchParams\(location\.search\)/, 'deep-link ?tab= handling missing');
});

test('G4: champion attribution drill exists on leaderboard and tribe tab', () => {
  assert.match(gamPage, /champion-drill/, 'leaderboard champion drill missing');
  assert.match(gamPage, /fetchChampionAttribution/, 'leaderboard must use the shared attribution helper');
  assert.match(tribeTab, /fetchChampionAttribution/, 'tribe tab must use the shared attribution helper');
  assert.match(tribeTab, /criterionLabel/, 'tribe tab must localize criteria via the catalog');
  assert.match(catalogLib, /champions_awarded/, 'attribution helper must read champions_awarded');
});

test('G3: LGPD opt-out UI wired to set_my_gamification_visibility', () => {
  assert.match(profile, /set_my_gamification_visibility/, 'opt-out RPC not called from profile');
  assert.match(profile, /self-gamification-optout/, 'opt-out checkbox missing in privacy section');
});

test('G2 UX: profile XP cards deep-link to the statement tab', () => {
  const links = profile.match(/gamification\?tab=mypoints/g) || [];
  assert.ok(links.length >= 2, `expected >=2 deep-links to the statement tab in profile.astro, found ${links.length}`);
});

test('G6: achievement level thresholds derive from the catalog', () => {
  assert.match(gamPage, /buildAchievementDefs/, 'achievements must build defs from catalog thresholds');
  for (const [lang, s] of Object.entries(dicts)) {
    for (const key of ['practitioner', 'expert', 'master', 'legend']) {
      const re = new RegExp(`'gamification\\.ach\\.def\\.${key}\\.desc':\\s*'[^']*\\{n\\}[^']*'`);
      assert.match(s, re, `${lang}: gamification.ach.def.${key}.desc must interpolate {n} (no hardcoded threshold)`);
    }
  }
});

test('i18n: every #1087 wave-2 key exists in all 3 dictionaries', () => {
  const newKeys = [
    'gamification.pillar.presenca', 'gamification.pillar.trilha', 'gamification.pillar.certificacoes',
    'gamification.pillar.producao', 'gamification.pillar.curadoria', 'gamification.pillar.champions',
    'gamification.pillar.protagonismo',
    'gamification.scoring.loading', 'gamification.scoring.onTimeBonus', 'gamification.scoring.perCriterion',
    'gamification.mp.filterCategory', 'gamification.mp.allCategories', 'gamification.mp.showingOf',
    'gamification.mp.loadMore', 'gamification.mp.filteredTotal', 'gamification.mp.grantedBy',
    'gamification.mp.reversal', 'gamification.mp.championBy', 'gamification.mp.championCriteria',
    'gamification.mp.emptyFiltered',
    'gamification.lb.championsDrillTitle', 'gamification.lb.championsDrillEmpty', 'gamification.lb.championsDrillHint',
    'gamification.champion.surface.general', 'gamification.champion.surface.tribe', 'gamification.champion.surface.deliverable',
    'gamification.ach.criteriaNote',
    'profile.gamOptOutLabel', 'profile.gamOptOutHint', 'profile.gamOptOutSaved', 'profile.gamOptOutError',
    'comp.gamification.champReceived', 'comp.gamification.champLoading', 'comp.gamification.champNone',
    'comp.gamification.champBy', 'comp.gamification.champSurface.general', 'comp.gamification.champSurface.tribe',
    'comp.gamification.champSurface.deliverable',
  ];
  for (const [lang, s] of Object.entries(dicts)) {
    for (const key of newKeys) {
      assert.ok(s.includes(`'${key}':`), `${lang}: missing i18n key ${key}`);
    }
  }
});

test('i18n: removed hardcoded-scoring keys are gone from all 3 dictionaries', () => {
  for (const [lang, s] of Object.entries(dicts)) {
    for (const key of ['gamification.scoring.certSenior', 'gamification.pointsLegend.attendance', 'gamification.mp.cycleBreakdown']) {
      assert.ok(!s.includes(`'${key}':`), `${lang}: orphaned key ${key} should have been removed`);
    }
  }
});
