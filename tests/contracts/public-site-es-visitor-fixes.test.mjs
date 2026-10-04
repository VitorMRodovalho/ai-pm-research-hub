// tests/contracts/public-site-es-visitor-fixes.test.mjs
// Registered in BOTH the "test:structural" and "test:contracts" whitelists in package.json.
/**
 * Public site, non-pt-BR visitor: four display-layer fixes, guarded offline (no DB).
 *
 * 1. /about blanked with `ReferenceError: lp is not defined`: LeadCaptureForm used `lp`, which
 *    only existed in the scope of ImpactPageIsland. The guard binds the declaration to the
 *    component that uses it.
 * 2. AgendaVivaPublic rendered pt-BR fallbacks before hydration (usePageI18n fills its dict in
 *    an effect). The guard binds: the island's `t` reads the `labels` prop first, AND every
 *    Astro caller passes `labels=`.
 * 3. Vertical titles come from the DB in pt-BR. The guard binds: keys exist in the 3
 *    dictionaries, ModelSection resolves them and passes `titles=`, and the island renders
 *    `label` (not the raw `title`) in both places it shows a title.
 * 4. members.linkedin_url values without a scheme became relative hrefs. The guard exercises
 *    withScheme() and binds every public-section LinkedIn href to it.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';
import { withScheme } from '../../src/lib/external-url.ts';

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

  const model = code('src/components/sections/ModelSection.astro');
  assert.match(model, /'Construção': 'model\.vertical\.construction'/);
  assert.match(model, /'Negócio': 'model\.vertical\.business'/);
  assert.match(model, /\[title, t\(key, lang\)\]/);
  assert.match(model, /<VerticalsSection\b[^>]*\btitles=\{verticalTitles\}/);

  const island = code('src/components/sections/VerticalsSection.tsx');
  assert.match(island, /setVerticals\(data\.map\(\(v: Vertical\) => \(\{ \.\.\.v, label: titles\[v\.title\] \|\| v\.title \}\)\)\)/);
  assert.match(island, /\{nd\.v\.label \|\| nd\.v\.title\}<\/div>/);
  assert.match(island, /<h3[^>]*>\{v\.label \|\| v\.title\}<\/h3>/);
});

test('4a. withScheme makes scheme-less profile URLs absolute', () => {
  assert.equal(withScheme('www.linkedin.com/in/x'), 'https://www.linkedin.com/in/x');
  assert.equal(withScheme('  linkedin.com/in/x '), 'https://linkedin.com/in/x');
  assert.equal(withScheme('https://www.linkedin.com/in/x'), 'https://www.linkedin.com/in/x');
  assert.equal(withScheme('HTTP://x.com'), 'HTTP://x.com');
  assert.equal(withScheme('//www.linkedin.com/in/x'), 'https://www.linkedin.com/in/x');
  assert.equal(withScheme('www.x.com:443/in/x'), 'https://www.x.com:443/in/x');
  assert.equal(withScheme('javascript:alert(1)'), 'https://javascript:alert(1)');
  assert.equal(withScheme(''), '');
  assert.equal(withScheme('   '), '');
  assert.equal(withScheme(null), '');
  assert.equal(withScheme(undefined), '');
});

test('4b. every public-section LinkedIn href goes through withScheme', () => {
  const team = code('src/components/sections/TeamSection.astro');
  assert.match(team, /href="\$\{withScheme\(m\.linkedin_url\)\}"/);
  assert.doesNotMatch(team, /href="\$\{m\.linkedin_url\}"/);
  const arms = code('src/components/sections/OperationalArmsSection.astro');
  assert.match(arms, /href=\{withScheme\(arm\.leader\.linkedin_url\)\}/);
  assert.match(arms, /href=\{withScheme\(tm\.linkedin_url\)\}/);
  assert.doesNotMatch(arms, /href=\{(arm\.leader|tm)\.linkedin_url\}/);
  const tribes = code('src/components/sections/TribesSection.astro');
  assert.match(tribes, /href=\{withScheme\(tr\.leaderLinkedIn\)\}/);
  assert.doesNotMatch(tribes, /href=\{tr\.leaderLinkedIn\}/);
});
