// tests/contracts/public-site-es-visitor-fixes.test.mjs
// Registered in BOTH the "test:structural" and "test:contracts" whitelists in package.json.
/**
 * Public site, non-pt-BR visitor: display-layer fixes, guarded offline (no DB).
 *
 * 1. /about blanked with `ReferenceError: lp is not defined`: LeadCaptureForm used `lp`, which
 *    only existed in the scope of ImpactPageIsland. The guard binds the declaration to the
 *    component that uses it.
 * 2. AgendaVivaPublic rendered pt-BR fallbacks before hydration (usePageI18n fills its dict in
 *    an effect). The guard binds: the island's `t` reads the `labels` prop first, AND every
 *    Astro caller passes `labels=`.
 * 3. Vertical titles come from the DB in pt-BR. The guard binds: keys exist in the 3
 *    dictionaries, and the home's research lines section (#2553 PR-7: the verticals cards left the
 *    home) maps each DB title to its key before any chip, line badge or empty-field message reads it.
 * 4. (retired in #2553 PR-7) members.linkedin_url hrefs went through withScheme(). The sections that
 *    rendered them (team, operational arms, tribes) left the home, and D3 keeps person names off it
 *    (2553-home-v2-virada, item B), so the helper and its checks left with them.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const root = resolve(import.meta.dirname, '../..');
const read = (p) => readFileSync(resolve(root, p), 'utf8');
const code = (p) => maskJsComments(read(p));

test('1. LeadCaptureForm declares lp in its own scope before using it', () => {
  const src = code('src/components/islands/ImpactPageIsland.tsx');
  const start = src.indexOf('function LeadCaptureForm(');
  const end = src.indexOf('export default function ImpactPageIsland(');
  assert.ok(start > -1 && end > start, 'component boundaries not found');
  const body = src.slice(start, end);
  const decl = body.search(/const lp = lang === 'pt-BR' \? '' : lang === 'en-US' \? '\/en' : '\/es';/);
  const use = body.indexOf('${lp}/privacy');
  assert.ok(decl > -1, 'LeadCaptureForm must declare lp from its own lang prop');
  assert.ok(use > decl, 'the privacy link must use the lp declared in LeadCaptureForm');
});

test('2. AgendaVivaPublic reads the labels prop first, and every caller passes it', () => {
  const island = code('src/components/agenda/AgendaVivaPublic.tsx');
  assert.match(island, /const t = useCallback\(\s*\(key: string, fallback\?: string\) => labels\?\.\[key\] \|\| pageT\(key, fallback\),\s*\[labels, pageT\],?\s*\)/);
  assert.match(island, /export default function AgendaVivaPublic\(\{[^}]*\blabels\b[^}]*\}/);
  assert.match(code('src/components/sections/WeeklyScheduleSection.astro'),
    /<AgendaVivaPublic\b[^>]*\blabels=\{agendaLabels\}/);
  assert.match(code('src/components/sections/WeeklyScheduleSection.astro'),
    /const agendaLabels[^=]*= JSON\.parse\(buildPageI18n\(\['comp\.agendaViva'\], lang\)\)/);
  assert.match(code('src/pages/reunioes-gerais.astro'),
    /<AgendaVivaPublic\b[^>]*\blabels=\{JSON\.parse\(i18nBundle\)\}/);
});

test('3. vertical titles: keys in all 3 dictionaries, resolved server side, rendered as label', () => {
  const keys = ['agile', 'construction', 'esg', 'business', 'pmo'];
  for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
    const dict = read(`src/i18n/${lang}.ts`);
    for (const k of keys) {
      assert.match(dict, new RegExp(`'model\\.vertical\\.${k}': '[^']+'`), `${lang} lacks model.vertical.${k}`);
    }
  }
  const es = read('src/i18n/es-LATAM.ts');
  assert.match(es, /'model\.vertical\.construction': 'Construcción'/);
  assert.match(es, /'model\.vertical\.business': 'Negocio'/);

  const lines = code('src/components/sections/ResearchLinesSection.astro');
  assert.match(lines, /'Construção': 'model\.vertical\.construction'/);
  assert.match(lines, /'Negócio': 'model\.vertical\.business'/);
  // the mapped list replaces the DB list: every later reader (chips, line badges, empty-field title) sees the label
  assert.match(lines, /const \[lines, pairs, dbVerticals\] = await Promise\.all\(\[loadResearchLines\(lang\), loadLineFields\(\), loadVerticals\(\)\]\);/);
  assert.match(lines, /const verticals = dbVerticals\.map\(\(v\) => \(\{ \.\.\.v, title: FIELD_TITLE_KEYS\[v\.title\] \? t\(FIELD_TITLE_KEYS\[v\.title\], lang\) : v\.title \}\)\);/);
  assert.equal((lines.match(/\bdbVerticals\b/g) || []).length, 2, 'the raw DB list is read once, to build the mapped one');
});
