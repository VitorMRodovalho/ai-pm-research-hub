// #1136 — Landing SSOT drift guard (static + DB-aware).
//
// Parte 1: as 4 seções que existem no home público mas sumiram do nav curado
//          (#tribes/#rules/#kpis/#trail-ranking) estão registradas no home-anchors.
// Parte 2: os 3 números de tribo não vivem hardcoded na copy — derivam do SSOT
//          (MIN_SLOTS/MAX_SLOTS e ACTIVE_TRIBE_COUNT em src/data/tribes.ts) via interpolação.
// Parte 3 (DB-aware, skip sem creds): quadrant_name / quadrant_name_i18n são consistentes
//          por quadrante (um único nome canônico + um único jsonb i18n, zero nulls).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(root, p), 'utf8');

const nav = read('src/lib/navigation.config.ts');
const tribesData = read('src/data/tribes.ts');
const tribesSection = read('src/components/sections/TribesSection.astro');
const baseLayout = read('src/layouts/BaseLayout.astro');
const dicts = {
  'pt-BR': read('src/i18n/pt-BR.ts'),
  'en-US': read('src/i18n/en-US.ts'),
  'es-LATAM': read('src/i18n/es-LATAM.ts'),
};

// ── Parte 1 — nav SSOT ───────────────────────────────────────────────────────
test('P1: as 4 seções antes em drift estão no home-anchors do nav', () => {
  for (const key of ['tribes', 'rules', 'kpis', 'trail-ranking']) {
    const re = new RegExp(`key:\\s*'${key}'[^\\n]*group:\\s*'home-anchors'`);
    assert.match(nav, re, `nav item '${key}' ausente do grupo home-anchors (drift de SSOT do nav)`);
  }
});

test('P1: nav.trailRanking existe nos 3 dicionários', () => {
  for (const [lang, src] of Object.entries(dicts)) {
    assert.match(src, /'nav\.trailRanking':/, `nav.trailRanking ausente em ${lang}`);
  }
});

// ── Parte 2 — números de tribo derivam do SSOT ───────────────────────────────
test('P2: tribes.slots interpola {min}/{max} e não carrega o cap hardcoded', () => {
  for (const [lang, src] of Object.entries(dicts)) {
    const m = src.match(/'tribes\.slots':\s*'([^']*)'/);
    assert.ok(m, `tribes.slots ausente em ${lang}`);
    assert.ok(m[1].includes('{min}') && m[1].includes('{max}'),
      `tribes.slots em ${lang} deve usar {min}/{max}, tem: "${m[1]}"`);
    assert.doesNotMatch(m[1], /\b(7|10|6|3)\b/, `tribes.slots em ${lang} tem número hardcoded: "${m[1]}"`);
  }
  // #1214: {max} passou a interpolar maxSlots (resolvido do SSOT via get_homepage_stats
  // no SSR, com MAX_SLOTS de data/tribes como fallback) — ver 1214-tribe-capacity-ssot.
  assert.match(tribesSection, /t\('tribes\.slots'[^)]*\)[\s\S]{0,80}?\.replace\('\{min\}',\s*String\(MIN_SLOTS\)\)[\s\S]{0,60}?\.replace\('\{max\}',\s*String\(maxSlots\)\)/,
    'TribesSection deve interpolar tribes.slots com MIN_SLOTS/maxSlots (SSOT #1214)');
});

test('P2: meta.description interpola {tribeCount} derivado do SSOT', () => {
  for (const [lang, src] of Object.entries(dicts)) {
    const m = src.match(/'meta\.description':\s*'([^']*)'/);
    assert.ok(m, `meta.description ausente em ${lang}`);
    assert.ok(m[1].includes('{tribeCount}'), `meta.description em ${lang} deve usar {tribeCount}, tem: "${m[1]}"`);
    assert.doesNotMatch(m[1], /\b7\s+(tribos|tribes|tribus)/i, `meta.description em ${lang} tem contagem hardcoded`);
  }
  assert.match(tribesData, /export const ACTIVE_TRIBE_COUNT = TRIBES\.length;/,
    'tribes.ts deve exportar ACTIVE_TRIBE_COUNT derivado de TRIBES.length');
  assert.match(baseLayout, /\.replace\('\{tribeCount\}',\s*String\(ACTIVE_TRIBE_COUNT\)\)/,
    'BaseLayout deve interpolar meta.description com ACTIVE_TRIBE_COUNT');
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
