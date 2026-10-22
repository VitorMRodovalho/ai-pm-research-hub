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
import { createClient } from '@supabase/supabase-js';

const read = (p) => maskJsComments(readFileSync(p, 'utf8'));
const DATA = read('src/lib/publicHomeData.ts');
const KPI = read('src/components/sections/KpiSection.astro');
const LADDER = read('src/components/sections/LadderSection.astro');
const PRIVACY = readFileSync('src/pages/privacy.astro', 'utf8');
const DICTS = ['src/i18n/pt-BR.ts', 'src/i18n/en-US.ts', 'src/i18n/es-LATAM.ts'].map((p) => [p, readFileSync(p, 'utf8')]);
const NEW_KEYS = ['kpis.ofTarget', 'kpis.goalUnavailable', 'kpis.met', 'kpis.surpassed', 'trail.free', 'trail.freeForPmiMembers', 'cpmai.viewOnCredly', 'privacy.s4.cpmaiWall'];

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
    assert.match(KPI, /const pct = g\.current !== null && g\.target !== null \? Math\.min\(100, Math\.round\(\(g\.current \/ g\.target\) \* 100\)\) : 0;/);
    assert.match(KPI, /\) : \(\s+<p class="[^"]*" id="kpi-unavailable">\{t\('kpis\.unavailable', lang\)\}<\/p>/);
    assert.doesNotMatch(KPI, /data\/kpis/);
  });

  it('A2b: nenhuma meta sai da tela: toda linha da RPC vira item, e a sem número aparece como indisponível', () => {
    const loader = DATA.match(/export async function loadHomeGoals[\s\S]*?return goals\.length \? goals : null;/)?.[0] ?? '';
    assert.ok(loader, 'loadHomeGoals ausente');
    assert.doesNotMatch(loader, /\.filter\(/, 'filtro por valor em loadHomeGoals: uma meta cujo cálculo quebre sumiria da tela');
    assert.match(loader, /current: isNum\(r\.current\) \? r\.current : null,\s+target: isNum\(r\.target\) && r\.target > 0 \? r\.target : null,/);
    assert.match(DATA, /if \(g\.current === null \|\| g\.target === null\) return 'unavailable';/);
    assert.match(KPI, /: t\('kpis\.goalUnavailable', lang\);/);
    assert.match(KPI, /\{goals\.map\(\(g\) => \{[\s\S]*?<li class="grid gap-1\.5" data-kpi=\{g\.key\} data-state=\{state\}>[\s\S]*?<span>\{g\.label\}<\/span>/);
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

// ── com banco: a RPC devolve uma linha por meta pactuada do ciclo que ela resolve ─────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const opts = { auth: { persistSession: false } };
const ready = SUPABASE_URL && SRK && ANON_KEY;

describe('#2553 metas, com banco', { skip: !ready && 'sem SUPABASE_URL + chaves' }, () => {
  it('como anon, exec_portfolio_health devolve tantas linhas quantas metas pactuadas o ciclo resolvido tem', async () => {
    const anon = createClient(SUPABASE_URL, ANON_KEY, opts);
    const svc = createClient(SUPABASE_URL, SRK, opts);
    const { data: rows, error } = await anon.rpc('exec_portfolio_health');
    assert.equal(error, null, `exec_portfolio_health como anon: ${error?.message}`);
    const { data: targets, error: tErr } = await svc.from('portfolio_kpi_targets').select('cycle_code, created_at');
    assert.equal(tErr, null, tErr?.message);
    // a mesma resolução da função: o default se tiver metas; senão o cycle_code criado por último
    const codes = new Map();
    for (const t of targets) codes.set(t.cycle_code, (codes.get(t.cycle_code) ?? '') > t.created_at ? codes.get(t.cycle_code) : t.created_at);
    const resolved = codes.has('cycle3-2026') ? 'cycle3-2026' : [...codes.entries()].sort((a, b) => (a[1] < b[1] ? 1 : -1))[0]?.[0];
    const expected = targets.filter((t) => t.cycle_code === resolved).length;
    assert.ok(expected > 0, 'nenhuma meta pactuada lida: o controle não pode dizer não');
    assert.equal(rows.length, expected);
  });
});
