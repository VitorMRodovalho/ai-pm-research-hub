// #2783: ajustes mecânicos das páginas públicas. Offline: lê o código e exerce as funções puras.
//
//   A. hreflang: endereço de cada língua, no mesmo host do canonical, e o canonical/og:url como estavam.
//      A forma do endereço ('prefix' ou 'query') é conferida contra a ROTA REAL em disco: 'query' só vale onde
//      /en/x e /es/x são meta refresh para /x?lang=..., e 'prefix' só onde a cópia em /en e /es é página de verdade.
//   B. rodapé: o carimbo do build (#2255) entra no HTML; "development" só sem carimbo.
//   C. /about: nome e quadrante da linha pela fonte da home; descrição institucional da home; singular de membro;
//      rótulo do link de privacidade pelo dicionário.
//   D. Agenda Viva: rótulo de formato pelo catálogo, depois pelo dicionário, e só então o código; o catálogo espera
//      o cliente; a reunião concluída liga ao vídeo publicado (só https do YouTube).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, relative } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';
import { languageAlternates, basePath } from '../../src/lib/hreflang.ts';
import { resolveFormatLabel, safeRecordingUrl } from '../../src/lib/agendaViva.ts';

const read = (p) => maskJsComments(readFileSync(p, 'utf8'));
const LAYOUT = read('src/layouts/BaseLayout.astro');
const ABOUT = read('src/pages/about.astro');
const ISLAND = read('src/components/islands/ImpactPageIsland.tsx');
const AGENDA = read('src/components/agenda/AgendaVivaPublic.tsx');
const LANGS = ['pt-BR', 'en-US', 'es-LATAM'];
const DICT = Object.fromEntries(LANGS.map((l) => [l, readFileSync(`src/i18n/${l}.ts`, 'utf8')]));
const dictValue = (lang, key) => {
  const m = DICT[lang].match(new RegExp(`^  '${key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}': '([^']+)',$`, 'm'));
  return m ? m[1] : null;
};
const ORIGIN = 'https://seo.example';

/** O trecho de `src` entre `from` e `to` (exclusivo), com falha clara se algum marco sumir. */
function between(src, from, to) {
  const a = src.indexOf(from);
  assert.ok(a >= 0, `marco não encontrado: ${from}`);
  const b = src.indexOf(to, a + from.length);
  assert.ok(b > a, `marco final não encontrado: ${to}`);
  return src.slice(a, b);
}

// ── A. hreflang ─────────────────────────────────────────────────────────────────────────────────────────────────
test('A1: query: cada língua no ?lang da página em português, x-default = português', () => {
  assert.deepEqual(languageAlternates('/about', 'query', ORIGIN), [
    { hreflang: 'pt-BR', href: `${ORIGIN}/about` },
    { hreflang: 'en', href: `${ORIGIN}/about?lang=en-US` },
    { hreflang: 'es', href: `${ORIGIN}/about?lang=es-LATAM` },
    { hreflang: 'x-default', href: `${ORIGIN}/about` },
  ]);
});

test('A2: prefix: a home em /en/ e /es/, e as 3 cópias declaram o mesmo conjunto', () => {
  const expected = [
    { hreflang: 'pt-BR', href: `${ORIGIN}/` },
    { hreflang: 'en', href: `${ORIGIN}/en/` },
    { hreflang: 'es', href: `${ORIGIN}/es/` },
    { hreflang: 'x-default', href: `${ORIGIN}/` },
  ];
  for (const p of ['/', '/en/', '/es/', '/en', '/es']) assert.deepEqual(languageAlternates(p, 'prefix', ORIGIN), expected, p);
  assert.equal(basePath('/es/about'), '/about');
  assert.equal(basePath('/english'), '/english', 'só o segmento /en inteiro é prefixo');
});

test('A3: o layout emite os links só quando a página declara, no host do canonical, e o canonical/og:url seguem iguais', () => {
  assert.match(LAYOUT, /const languageLinks = alternates \? languageAlternates\(Astro\.url\.pathname, alternates, SEO_CANONICAL_ORIGIN\) : \[\];/);
  assert.match(LAYOUT, /\{languageLinks\.map\(\(a\) => <link rel="alternate" hreflang=\{a\.hreflang\} href=\{a\.href\} \/>\)\}/);
  assert.match(LAYOUT, /const seoCanonicalUrl = new URL\(Astro\.url\.pathname, SEO_CANONICAL_ORIGIN\)\.href;/);
  assert.match(LAYOUT, /<link rel="canonical" href=\{seoCanonicalUrl\} \/>/);
  assert.match(LAYOUT, /<meta property="og:url" content=\{seoCanonicalUrl\} \/>/);
});

/** Todo arquivo .astro sob src/pages. */
function pages(dir = 'src/pages') {
  const out = [];
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) out.push(...pages(p));
    else if (p.endsWith('.astro')) out.push(p);
  }
  return out;
}
const routeOf = (file) => {
  const rel = relative('src/pages', file).replace(/\.astro$/, '').replace(/(^|\/)index$/, '');
  return `/${rel}`;
};

test('A4: a forma declarada bate com a rota real de /en e /es, e a home e o /about estão entre as páginas', () => {
  const declared = pages()
    .map((f) => ({ f, mode: (read(f).match(/<BaseLayout[^>]*\balternates="(query|prefix)"/) || [])[1] }))
    .filter((x) => x.mode);
  const routes = new Set();
  for (const { f, mode } of declared) {
    const rel = relative('src/pages', f);
    const localized = /^(en|es)\//.test(rel);
    if (localized) {
      assert.equal(mode, 'prefix', `${f}: cópia em /en ou /es só declara 'prefix'`);
      continue;
    }
    const route = routeOf(f);
    routes.add(route);
    for (const [prefix, code] of [['en', 'en-US'], ['es', 'es-LATAM']]) {
      const copy = join('src/pages', prefix, rel);
      assert.ok(existsSync(copy), `${f}: falta ${copy}`);
      const src = readFileSync(copy, 'utf8');
      const target = (src.match(/http-equiv="refresh" content="0;url=([^"]+)"/) || [])[1] ?? null;
      if (mode === 'query') {
        assert.equal(target, `${route}?lang=${code}`, `${copy}: 'query' exige meta refresh para ${route}?lang=${code}`);
      } else {
        assert.equal(target, null, `${copy}: 'prefix' exige página real, não meta refresh`);
        assert.match(src, /<BaseLayout[^>]*\balternates="prefix"/, `${copy}: a cópia declara o mesmo conjunto`);
      }
    }
  }
  for (const r of ['/', '/about']) assert.ok(routes.has(r), `${r} precisa declarar as variantes`);
});

// ── B. rodapé ──────────────────────────────────────────────────────────────────────────────────────────────────
test('B: o rodapé nasce com o carimbo do build e o nome da versão não o apaga', () => {
  assert.match(LAYOUT, /const releaseShort = \(import\.meta\.env\.PUBLIC_RELEASE_SHA \|\| ''\)\.slice\(0, 8\);/);
  assert.match(LAYOUT, /<span id="footer-version"[^>]*data-build=\{releaseShort\}>\{releaseShort \|\| 'development'\}<\/span>/);
  const script = between(LAYOUT, "sb.rpc('get_current_release')", '} catch {}');
  assert.match(script, /const build = el\?\.dataset\.build;\s+if \(el\) el\.textContent = build \? `\$\{data\.version\} · \$\{build\}` : data\.version;/);
});

// ── C. /about ──────────────────────────────────────────────────────────────────────────────────────────────────
test('C1: o /about lê nome e quadrante da linha pela fonte da home, na língua da página', () => {
  assert.match(ABOUT, /const lineNames: LineNames = Object\.fromEntries\(\s*\(\(await loadResearchLines\(lang\)\) \?\? \[\]\)\.map\(\(line\) => \[line\.id, \{ name: line\.name, quadrantName: line\.quadrantName \}\]\),\s*\);/);
  assert.match(ABOUT, /<ImpactPageIsland client:load lang=\{lang\} lineNames=\{lineNames\} text=\{text\} \/>/);
  const card = between(ISLAND, '(data.tribes_summary || []).map(', '</a>');
  assert.match(card, /\{lineNames\?\.\[tribe\.id\]\?\.name \|\| tribe\.name\}/);
  assert.match(card, /\{lineNames\?\.\[tribe\.id\]\?\.quadrantName \|\| tribe\.quadrant_name\}/);
  assert.doesNotMatch(ISLAND, /window\.location\.pathname\.startsWith\('\/en'\)/, 'a língua vinha do caminho, que no /about é sempre /about');
});

test('C2: descrição institucional e link de privacidade saem dos dicionários, sem texto novo', () => {
  assert.match(ABOUT, /const text = \{\s*relation: t\('homeV2\.hero\.relation', lang\),\s*privacy: t\('nav\.privacy', lang\),\s*memberOne: t\('about\.memberCountOne', lang\),\s*\};/);
  const hero = between(ISLAND, '{l.hero}</h1>', '</section>');
  assert.match(hero, /\{text\?\.relation && <p [^>]*>\{text\.relation\}<\/p>\}/);
  assert.doesNotMatch(ISLAND, /heroSub/);
  const form = between(ISLAND, 'function LeadCaptureForm(', 'export default function ImpactPageIsland(');
  assert.match(form, /<a href=\{`\$\{lp\}\/privacy`\}[^>]*>\{privacyLabel\}<\/a>/);
  assert.doesNotMatch(form, />Privacy<\/a>/);
  assert.match(ISLAND, /<LeadCaptureForm l=\{l\} lang=\{lang\} privacyLabel=\{text\?\.privacy \?\? ''\} \/>/);
});

test('C3: um membro no singular, nos cards de linha e de capítulo', () => {
  assert.match(ISLAND, /const membersLabel = \(n: number\) => \(n === 1 && text\?\.memberOne \? text\.memberOne : l\.membersCount\);/);
  const card = between(ISLAND, '(data.tribes_summary || []).map(', '</a>');
  assert.match(card, /\{tribe\.member_count\} \{membersLabel\(tribe\.member_count\)\}/);
  const chapters = between(ISLAND, 'data.chapters_summary.map(', '))}');
  assert.match(chapters, /\{ch\.member_count\}<\/div>\s*<div [^>]*>\{membersLabel\(ch\.member_count\)\}<\/div>/);
  assert.doesNotMatch(ISLAND, /\{l\.membersCount\}/, 'nenhum contador usa o plural direto');
  for (const lang of LANGS) assert.ok(dictValue(lang, 'about.memberCountOne'), `${lang}: about.memberCountOne`);
});

// ── D. Agenda Viva ─────────────────────────────────────────────────────────────────────────────────────────────
const SLUGS = ['case_aplicado', 'convidado', 'demo_pratica', 'espaco_aberto', 'insight_rapido', 'pilula_quinzena', 'prompt_semana', 'review_ferramenta'];

test('D1: rótulo de formato: catálogo, depois dicionário, depois o código', () => {
  const dict = (key) => (key === 'comp.agendaViva.format.prompt_semana' ? 'Do dicionário' : null);
  const catalog = { prompt_semana: { 'pt-BR': 'Prompt da Semana', 'en-US': 'Prompt of the Week' } };
  assert.equal(resolveFormatLabel('prompt_semana', 'en-US', catalog, dict), 'Prompt of the Week', 'o catálogo manda');
  assert.equal(resolveFormatLabel('prompt_semana', 'en-US', {}, dict), 'Do dicionário', 'sem catálogo, o dicionário');
  assert.equal(resolveFormatLabel('prompt_semana', 'es-LATAM', catalog, dict), 'Do dicionário', 'catálogo sem a língua: dicionário antes do português');
  assert.equal(resolveFormatLabel('formato_novo', 'en-US', {}, dict), 'formato_novo', 'nenhum dos dois conhece: o código');
  assert.match(AGENDA, /resolveFormatLabel\(slug, lang, formats, \(key\) => \{\s*const v = t\(key, ''\);\s*return v && v !== key \? v : null;\s*\}\)/);
  for (const lang of LANGS) {
    for (const s of SLUGS) assert.ok(dictValue(lang, `comp.agendaViva.format.${s}`), `${lang}: comp.agendaViva.format.${s}`);
    assert.ok(dictValue(lang, 'comp.agendaViva.watchRecording'), `${lang}: comp.agendaViva.watchRecording`);
  }
});

test('D2: o catálogo de formatos espera o cliente, como a pauta', () => {
  const effect = between(AGENDA, 'const loadFormats = () => {', "select('slug, label_i18n')");
  assert.match(effect, /const sb = getSb\(\);\s*if \(!sb\) \{ timer = setTimeout\(loadFormats, 300\); return; \}\s*sb\.from\('agenda_block_formats'\)\.$/);
});

test('D3: só a reunião concluída pede o vídeo, e só https do YouTube vira link', () => {
  const effect = between(AGENDA, 'const pastIds =', '}, [data, getSb]);');
  assert.match(effect, /const pastIds = \(data\?\.events \?\? \[\]\)\.filter\(\(e\) => e\.is_past\)\.map\(\(e\) => e\.id\);/);
  assert.match(effect, /sb\.from\('events'\)\.select\('id, youtube_url'\)\.eq\('type', 'geral'\)\.in\('id', pastIds\)/);
  assert.match(effect, /const url = safeRecordingUrl\(r\.youtube_url\);\s*if \(url\) map\[r\.id\] = url;/);
  assert.match(AGENDA, /\{ev\.is_past && recordings\[ev\.id\] && \(\s*<a href=\{recordings\[ev\.id\]\} target="_blank" rel="noopener noreferrer"[\s\S]{0,200}?\{t\('comp\.agendaViva\.watchRecording', 'Assistir gravação'\)\}/);
  assert.equal(safeRecordingUrl('https://youtu.be/abc'), 'https://youtu.be/abc');
  assert.equal(safeRecordingUrl('https://www.youtube.com/watch?v=abc'), 'https://www.youtube.com/watch?v=abc');
  assert.equal(safeRecordingUrl('http://youtu.be/abc'), null, 'http não');
  assert.equal(safeRecordingUrl('javascript:alert(1)'), null);
  assert.equal(safeRecordingUrl('https://drive.google.com/file/d/x'), null, 'outro host não');
  assert.equal(safeRecordingUrl('https://youtu.be.evil.example/abc'), null, 'sufixo enganoso não');
  assert.equal(safeRecordingUrl(null), null);
});
