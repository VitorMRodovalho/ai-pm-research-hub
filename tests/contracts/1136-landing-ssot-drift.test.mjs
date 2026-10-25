// #1136 — Landing SSOT drift guard (static + DB-aware).
//
// Parte 1: toda seção renderizada no home público está registrada no home-anchors do nav
//          (#2553 PR 2: derivado do que index.astro renderiza, não mais uma lista fixa).
// Parte 2: os números de tribo não vivem hardcoded na copy — derivam do SSOT via interpolação
//          (na home, membros e vagas de cada linha vêm da RPC). PR3 C3 (GP 25/10/2026): a descrição de busca
//          da home deixou de levar a contagem de tribos, então não há mais o que interpolar nela.
// Parte 3 (DB-aware, skip sem creds): quadrant_name / quadrant_name_i18n são consistentes
//          por quadrante (um único nome canônico + um único jsonb i18n, zero nulls).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(root, p), 'utf8');

const nav = read('src/lib/navigation.config.ts');
const tribesData = read('src/data/tribes.ts');
const linesSection = maskJsComments(read('src/components/sections/ResearchLinesSection.astro'));
const baseLayout = read('src/layouts/BaseLayout.astro');
const dicts = {
  'pt-BR': read('src/i18n/pt-BR.ts'),
  'en-US': read('src/i18n/en-US.ts'),
  'es-LATAM': read('src/i18n/es-LATAM.ts'),
};

// ── Parte 1 — nav SSOT ───────────────────────────────────────────────────────
test('P1: toda seção que a home renderiza está no home-anchors do nav (sem drift)', () => {
  // #2553 PR 2 (home v2): a lista deixou de ser fixa (#tribes/#rules/#kpis/#trail-ranking da home antiga) e passou a
  // ser derivada do que a home renderiza: cada <section id> de um componente importado por index.astro tem item no menu.
  // O hero (topo) e o fechamento (#follow) não entram: não são destino de menu.
  const index = read('src/pages/index.astro');
  const files = [...index.matchAll(/^import \w+ from '\.\.\/components\/sections\/([\w.]+\.astro)';$/gm)].map((m) => `src/components/sections/${m[1]}`);
  const ids = files.flatMap((f) => [...read(f).matchAll(/<section [^>]*id="([\w-]+)"/g)].map((m) => m[1]))
    .filter((id) => !['hero', 'follow'].includes(id));
  assert.ok(ids.length >= 6, `seções da home não lidas (${ids.join(', ')})`);
  for (const id of ids) {
    const re = new RegExp(`href: '/#${id}'[^\\n]*group: 'home-anchors'`);
    assert.match(nav, re, `seção #${id} renderizada na home sem item no grupo home-anchors (drift de SSOT do nav)`);
  }
});

test('P1: nav.trailRanking existe nos 3 dicionários', () => {
  for (const [lang, src] of Object.entries(dicts)) {
    assert.match(src, /'nav\.trailRanking':/, `nav.trailRanking ausente em ${lang}`);
  }
});

// ── Parte 2 — números de tribo derivam do SSOT ───────────────────────────────
test('P2: as vagas da linha interpolam {n}/{max} e não carregam número no texto', () => {
  // #2553 PR-7: a TribesSection (tribes.slots com {min}/{max}) saiu da home. As vagas da seção de linhas usam
  // homeV2.lines.seats, com membros e capacidade da linha lidos de get_public_research_lines (ver 1214).
  for (const [lang, src] of Object.entries(dicts)) {
    const m = src.match(/^  'homeV2\.lines\.seats': '([^']*)',$/m);
    assert.ok(m, `homeV2.lines.seats ausente em ${lang}`);
    assert.ok(m[1].includes('{n}') && m[1].includes('{max}'),
      `homeV2.lines.seats em ${lang} deve usar {n}/{max}, tem: "${m[1]}"`);
    assert.doesNotMatch(m[1], /\d/, `homeV2.lines.seats em ${lang} tem número hardcoded: "${m[1]}"`);
  }
  assert.match(linesSection, /t\('homeV2\.lines\.seats', lang\)\.replace\('\{n\}', String\(l\.members\)\)\.replace\('\{max\}', String\(l\.capacity\)\)/,
    'a seção de linhas deve interpolar homeV2.lines.seats com os números da RPC');
});

test('P2: meta.description não leva contagem de tribos, nem escrita nem interpolada (PR3 C3)', () => {
  // PR3 C3 (GP 25/10/2026): a mesma regra do /about, nenhum número na descrição de busca. O número de tribos não
  // fica nem como {tribeCount}: o texto não fala em quantidade de tribos.
  for (const [lang, src] of Object.entries(dicts)) {
    const m = src.match(/^  'meta\.description': '([^']*)',$/m);
    assert.ok(m, `meta.description ausente em ${lang}`);
    assert.doesNotMatch(m[1], /\{tribeCount\}|\d/, `meta.description em ${lang} leva contagem: "${m[1]}"`);
  }
  // o layout entrega o texto como está: sem placeholder para trocar, e sem a constante que o alimentava
  assert.match(baseLayout, /description = t\('meta\.description', lang\),/, 'BaseLayout deve usar meta.description sem interpolação');
  assert.doesNotMatch(baseLayout, /tribeCount|ACTIVE_TRIBE_COUNT/, 'BaseLayout ainda interpola contagem de tribos');
  assert.doesNotMatch(tribesData, /ACTIVE_TRIBE_COUNT/, 'tribes.ts ainda exporta a contagem que só a descrição lia');
});

// ── Parte 3 — quadrant_name data-hygiene (DB-aware) ──────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

test(canRun ? 'P3: quadrant_name/i18n consistentes por quadrante (0 nulls, 1 nome cada)' : skipMsg, { skip: !canRun }, async () => {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/tribes?select=quadrant,quadrant_name,quadrant_name_i18n`, {
    headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` },
  });
  assert.ok(res.ok, `tribes HTTP ${res.status}`);
  const rows = await res.json();
  const byQuad = new Map();
  for (const r of rows) {
    const g = byQuad.get(r.quadrant) || { names: new Set(), i18n: new Set(), nulls: 0 };
    g.names.add(r.quadrant_name);
    if (r.quadrant_name_i18n == null) g.nulls++;
    else g.i18n.add(JSON.stringify(r.quadrant_name_i18n));
    byQuad.set(r.quadrant, g);
  }
  for (const [quad, g] of byQuad) {
    assert.equal(g.names.size, 1, `quadrante ${quad}: ${g.names.size} nomes canônicos distintos (esperado 1)`);
    assert.equal(g.nulls, 0, `quadrante ${quad}: ${g.nulls} tribos com quadrant_name_i18n null`);
    assert.equal(g.i18n.size, 1, `quadrante ${quad}: ${g.i18n.size} jsonbs i18n distintos (esperado 1)`);
  }
});
