// #2553 PR 2 (D3, D9 e cursos, GP 20/10/2026): metas, escada e mural da home lidos do banco, no servidor.
//
// Medido em 21/10/2026: o alvo das metas vinha de src/data/kpis.ts (8 capítulos como manchete, com 15 no ar), a
// escada de src/data/trail.ts, e o mural de uma consulta do navegador a public_members filtrando pela categoria
// "cpmai", que pega quem só tem o curso introdutório. O guard afirma que (A) cada bloco lê a sua RPC pública, (B)
// sem leitura o bloco fica sem número e sem lista inventados, e (C) os rótulos novos existem nos 3 idiomas, com a
// linha do mural no aviso de privacidade.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const read = (p) => maskJsComments(readFileSync(p, 'utf8'));
const DATA = read('src/lib/publicHomeData.ts');
const KPI = read('src/components/sections/KpiSection.astro');
const LADDER = read('src/components/sections/LadderSection.astro');
const PRIVACY = readFileSync('src/pages/privacy.astro', 'utf8');
const DICTS = ['src/i18n/pt-BR.ts', 'src/i18n/en-US.ts', 'src/i18n/es-LATAM.ts'].map((p) => [p, readFileSync(p, 'utf8')]);
const NEW_KEYS = ['kpis.ofTarget', 'kpis.met', 'kpis.surpassed', 'trail.free', 'trail.freeForPmiMembers', 'cpmai.viewOnCredly', 'privacy.s4.cpmaiWall'];

describe('#2553 dados da home do banco', () => {
  it('A1: os loaders leem a RPC pública e devolvem null na falha, sem reserva', () => {
    assert.match(DATA, /async function rpc<T>\(name: string\): Promise<T \| null> \{\s+try \{\s+const \{ data, error \} = await anonClient\(\)\.rpc\(name\)\.abortSignal\(AbortSignal\.timeout\(TIMEOUT_MS\)\);\s+return error \|\| data === null \|\| data === undefined \? null : \(data as T\);\s+\} catch \{\s+return null;/);
    for (const name of ['exec_portfolio_health', 'get_trail_courses', 'get_public_cpmai_wall']) {
      assert.match(DATA, new RegExp(`const rows = await rpc<unknown\\[\\]>\\('${name}'\\);\\s+if \\(!Array\\.isArray\\(rows\\)\\) return null;`), name);
    }
    assert.match(DATA, /createClient\(import\.meta\.env\.PUBLIC_SUPABASE_URL, import\.meta\.env\.PUBLIC_SUPABASE_ANON_KEY,/);
  });

  it('A2: metas: o estado sai do atual contra o alvo, e o título leva o ano de Brasília', () => {
    assert.match(DATA, /return g\.current > g\.target \? 'surpassed' : g\.current === g\.target \? 'met' : 'behind';/);
    assert.match(KPI, /const goals = await loadHomeGoals\(lang\);/);
    assert.match(KPI, /\{t\('kpis\.title', lang\)\.replace\('\{year\}', currentYearBrt\(\)\)\}/);
    assert.match(KPI, /const pct = Math\.min\(100, Math\.round\(\(g\.current \/ g\.target\) \* 100\)\);/);
    assert.match(KPI, /\) : \(\s+<p class="[^"]*" id="kpi-unavailable">\{t\('kpis\.unavailable', lang\)\}<\/p>/);
    assert.doesNotMatch(KPI, /data\/kpis/);
  });

  it('A3: escada: os cursos vêm de get_trail_courses, e o rótulo de gratuidade vem de free_for', () => {
    assert.match(LADDER, /const courses = \(await loadTrailCourses\(\)\) \?\? \[\];/);
    assert.match(LADDER, /c\.freeFor === 'pmi_members' \? t\('trail\.freeForPmiMembers', lang\) : c\.freeFor === 'everyone' \? t\('trail\.free', lang\) : ''/);
    assert.match(DATA, /freeFor: r\.free_for === 'everyone' \|\| r\.free_for === 'pmi_members' \? r\.free_for : null,/);
    assert.doesNotMatch(LADDER, /data\/trail/);
  });

  it('A4: mural: renderizado no servidor pela RPC do selo, sem consulta do navegador e sem foto', () => {
    assert.match(LADDER, /const wall = await loadCpmaiWall\(\);/);
    assert.match(LADDER, /\{wall && wall\.length > 0 \? \(\s+<ul id="cpmai-grid"[\s\S]*?\{wall\.map\(\(w\) => \([\s\S]*?\{w\.name\}[\s\S]*?href=\{w\.credlyUrl\}/);
    assert.match(DATA, /\.filter\(\(r\) => typeof r\.name === 'string' && \/\^https:\\\/\\\/\(www\\\.\)\?credly\\\.com\\\/\/i\.test\(String\(r\.credly_url \?\? ''\)\)\)/);
    assert.doesNotMatch(LADDER, /public_members|navGetSb|photo_url|<script/);
  });

  it('C1: as chaves novas existem nos 3 dicionários, e o título das metas não carrega ano escrito', () => {
    for (const [path, src] of DICTS) {
      for (const key of NEW_KEYS) assert.match(src, new RegExp(`'${key.replace(/\./g, '\\.')}': `), `${key} ausente em ${path}`);
      const title = src.match(/'kpis\.title': '([^']*)'/)?.[1] ?? '';
      assert.match(title, /\{year\}/, `${path}: kpis.title sem {year}`);
      assert.doesNotMatch(title, /\b20\d\d\b/, `${path}: kpis.title com ano escrito`);
    }
  });

  it('C2: o aviso de privacidade mostra a linha do mural', () => {
    assert.match(PRIVACY, /<li>\{t\('privacy\.s4\.credly', lang\)\}<\/li>\s+<li>\{t\('privacy\.s4\.cpmaiWall', lang\)\}<\/li>/);
  });
});
