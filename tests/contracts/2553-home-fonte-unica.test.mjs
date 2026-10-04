/**
 * Contract #2553 PR 1: a home conta capítulos e pesquisadores por UMA fonte.
 *
 * DEFEITO, medido em 03/10/2026 na mesma página:
 *   - capítulos: 5 em "A plataforma em números" e nas Metas (get_chapter_metrics().signed), 15 no
 *     selo do hero (texto fixo no i18n) e 15 no título da seção de capítulos (chapter_registry);
 *   - pesquisadores: 76 no hero (v_operational_members, ADR-0126) e 97 na linha do mapa, que contava
 *     outra população (todo ativo do ciclo, incluindo patrocinador, representante de capítulo,
 *     convidado e observador).
 *
 * DECISÕES DO GP (03/10/2026): capítulos = 'engaged' (assinados + em negociação) no público e nas
 * Metas internas; o mapa conta só a equipe de pesquisa.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. Frontend (estático): a página busca get_homepage_stats UMA vez (loadHomeStats) e passa o
 *      objeto ao hero e à seção de capítulos; cada número é ligado ao campo que o produz.
 *   B. Banco (estático): a captura VIGENTE de cada função, via latestFunctionCapture (#1932), liga a
 *      condição ao resultado. As 3 leitoras de capítulo leem 'engaged'; as 4 RPCs do mapa leem
 *      v_operational_members e mantêm os portões de LGPD.
 *   C. Banco (vivo, DB-aware): as três contagens de capítulo são iguais a engaged, a lista de selos
 *      tem o mesmo tamanho, e a soma do mapa é a equipe de pesquisa com país preenchido.
 *
 * Os números NÃO aparecem nas asserções: o guard afirma RELAÇÕES, que sobrevivem ao crescimento.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
// Astro: comentário JS no frontmatter/script, {/* */} no template e <!-- --> no HTML.
const maskAstro = (src) => maskJsComments(src).replace(/<!--[\s\S]*?-->/g, (m) => m.replace(/[^\n]/g, ' '));

// ── A. Frontend ──────────────────────────────────────────────────────────────────

test('A1: loadHomeStats lê get_homepage_stats e não inventa número', () => {
  const src = maskJsComments(read('src/lib/homeStats.ts'));
  assert.match(src, /await sb\.rpc\('get_homepage_stats'\)/, 'a fonte única é get_homepage_stats');
  assert.match(src, /chapters:\s*count\(s\.chapters\)/, 'chapters vem de get_homepage_stats.chapters');
  assert.match(src, /members:\s*count\(s\.members\)/, 'members vem de get_homepage_stats.members');
  assert.doesNotMatch(src, /\?\?\s*\d/, 'sem fallback numérico literal: número ausente é omitido, não inventado');
});

for (const page of ['src/pages/index.astro', 'src/pages/en/index.astro', 'src/pages/es/index.astro']) {
  test(`A2: ${page} busca uma vez e passa o mesmo objeto ao hero e aos capítulos`, () => {
    const src = maskAstro(read(page));
    assert.equal((src.match(/loadHomeStats\(\)/g) || []).length, 1, 'uma busca por requisição');
    assert.match(src, /\[homeSchedule, homeStats\] = await Promise\.all\(\[getHomeSchedule\(\), loadHomeStats\(\)\]\)/, 'homeStats é o resultado dessa busca');
    assert.match(src, /<HomepageHero lang=\{lang\} stats=\{homeStats\} \/>/, 'o hero recebe o objeto');
    assert.match(src, /<ChaptersSection lang=\{lang\} stats=\{homeStats\} \/>/, 'a seção de capítulos recebe o mesmo objeto');
  });
}

test('A3: o selo do hero interpola a contagem de capítulos, e some sem ela', () => {
  const src = maskAstro(read('src/components/sections/HomepageHero.astro'));
  assert.match(src, /const chaptersCount = stats\?\.chapters \?\? null;/, 'chaptersCount vem de stats.chapters');
  assert.match(
    src,
    /\{chaptersCount !== null && \([\s\S]{0,400}?t\('hero\.chaptersAnnounce', lang\)\.replace\('\{n\}', String\(chaptersCount\)\)/,
    'o {n} do selo é a contagem, dentro do bloco que só renderiza quando ela existe',
  );
});

test('A4: os números do hero chegam no HTML; o script não busca de novo', () => {
  const src = maskAstro(read('src/components/sections/HomepageHero.astro'));
  for (const [id, field] of [['stat-members', 'members'], ['stat-tribes', 'tribes'], ['stat-initiatives', 'initiatives'], ['stat-hours', 'impactHours']]) {
    assert.match(src, new RegExp(`id="${id}" data-target=\\{stats\\?\\.${field} \\?\\? undefined\\}`), `${id} <- stats.${field}`);
  }
  assert.match(src, /animateCounter\(id, target, el\.dataset\.suffix \?\? ''\)/, 'o contador anima o valor que veio no HTML');
  assert.doesNotMatch(src, /rpc\('get_homepage_stats'\)/, 'uma segunda chamada no cliente seria outra fonte para os mesmos números');
});

test('A5: o selo de capítulos não carrega número fixo em nenhum dos 3 dicionários', () => {
  for (const dict of ['pt-BR', 'en-US', 'es-LATAM']) {
    const m = read(`src/i18n/${dict}.ts`).match(/'hero\.chaptersAnnounce':\s*'([^']*)'/);
    assert.ok(m, `hero.chaptersAnnounce ausente em ${dict}`);
    assert.ok(m[1].includes('{n}'), `${dict}: o selo deve interpolar {n}, tem "${m[1]}"`);
    assert.doesNotMatch(m[1], /\d/, `${dict}: número fixo no selo: "${m[1]}"`);
  }
});

test('A6: a seção de capítulos conta pela fonte única, não pela lista de selos', () => {
  const src = maskAstro(read('src/components/sections/ChaptersSection.astro'));
  assert.match(src, /const chapterCount = stats\?\.chapters \?\? null;/, 'chapterCount vem de stats.chapters');
  assert.match(
    src,
    /\{chapterCount !== null \? `\$\{chapterCount\} ` : ''\}\{t\('chapters\.title', lang\)\}/,
    'o título usa chapterCount',
  );
  assert.doesNotMatch(src, /chapters\.length/, 'contar a lista de selos seria a segunda fonte');
  assert.match(src, /const researchersCount = stats\?\.members \?\? null;/, 'o total do mapa vem de stats.members');
  assert.match(
    src,
    /\{researchersCount !== null && <>\{' · '\}\{researchersCount\} \{t\('chapters\.reachMembersSuffix', lang\)\}<\/>\}/,
    'a linha do mapa mostra researchersCount',
  );
  assert.doesNotMatch(src, /reachMembers\b/, 'a soma dos selos de país não é mais um número exibido');
});

// ── B. Banco: captura vigente ────────────────────────────────────────────────────

const current = (fn) => maskLineComments(latestFunctionCapture(ROOT, fn).block);

test('B1: as 3 leitoras de capítulo leem engaged', () => {
  const home = current('get_homepage_stats');
  assert.match(home, /'chapters',\s*\(public\.get_chapter_metrics\(\)->>'engaged'\)::int/, 'get_homepage_stats.chapters <- engaged');
  assert.doesNotMatch(home, /get_chapter_metrics\(\)->>'signed'/, 'get_homepage_stats sem signed');

  const plat = current('get_public_platform_stats');
  assert.match(plat, /'total_chapters',\s*\(public\.get_chapter_metrics\(\)->>'engaged'\)::int/, 'total_chapters <- engaged');
  assert.doesNotMatch(plat, /get_chapter_metrics\(\)->>'signed'/, 'get_public_platform_stats sem signed');

  const health = current('exec_portfolio_health');
  assert.match(
    health,
    /WHEN 'chapters_participating' THEN\s+v_current := \(public\.get_chapter_metrics\(\)->>'engaged'\)::numeric;/,
    'a meta de capítulos <- engaged',
  );
});

const MAP_RPCS = ['get_public_country_reach', 'get_public_precise_country_reach', 'get_public_continent_reach', 'get_public_state_reach_v3'];
const POPULATION = /FROM public\.members m\s+WHERE EXISTS \(SELECT 1 FROM public\.v_operational_members om WHERE om\.id = m\.id\)/;

for (const fn of MAP_RPCS) {
  test(`B2: ${fn} conta a equipe de pesquisa (v_operational_members), a mesma do hero`, () => {
    const body = current(fn);
    assert.match(body, POPULATION, `${fn}: população = v_operational_members`);
    // A população antiga, se voltar ao lado da nova, a estreitaria em silêncio e o mapa sairia do hero.
    assert.doesNotMatch(body, /member_is_pre_onboarding/, `${fn}: filtro de pré-onboarding re-derivado`);
    assert.doesNotMatch(body, /m\.is_active|m\.current_cycle_active/, `${fn}: filtro de atividade re-derivado`);
    assert.match(body, /SECURITY DEFINER/, `${fn}: superfície pública zero-PII`);
    assert.match(body, /SET search_path TO ''/, `${fn}: search_path vazio`);
  });
}

test('B3: os portões de LGPD do mapa seguem ligados à população nova', () => {
  assert.match(
    current('get_public_country_reach'),
    /CASE WHEN n >= 3 AND code <> 'XX' THEN code ELSE 'ZZ' END AS country_code/,
    'país com menos de 3 vira Internacional (k-anonimato)',
  );
  assert.match(
    current('get_public_precise_country_reach'),
    /WHERE EXISTS \([^)]*v_operational_members[^)]*\)\s+AND m\.allow_precise_location_in_public_map/,
    'pino preciso exige o opt-in preciso',
  );
  const state = current('get_public_state_reach_v3');
  assert.match(
    state,
    /WHERE EXISTS \([^)]*v_operational_members[^)]*\)\s+AND \(m\.allow_state_in_public_map OR m\.allow_precise_location_in_public_map\)/,
    'pino de estado exige um dos dois opt-ins',
  );
  assert.match(
    state,
    /WHERE count_precise >= 1 OR count_aggregate >= GREATEST\(p_min_k, 3\)/,
    'agregado só aparece com k>=3, mesmo se o chamador baixar p_min_k',
  );
});

// ── C. Banco vivo ────────────────────────────────────────────────────────────────

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const client = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

test('C1: uma contagem de capítulos em toda a home, igual a engaged', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = client();
  const [m, home, plat, health, chips] = await Promise.all([
    sb.rpc('get_chapter_metrics'),
    sb.rpc('get_homepage_stats'),
    sb.rpc('get_public_platform_stats'),
    sb.rpc('exec_portfolio_health'),
    sb.rpc('get_active_chapters'),
  ]);
  for (const r of [m, home, plat, health, chips]) assert.ifError(r.error);
  const engaged = Number(m.data.engaged);
  assert.equal(Number(home.data.chapters), engaged, 'hero e seção de capítulos (get_homepage_stats.chapters)');
  assert.equal(Number(plat.data.total_chapters), engaged, '"A plataforma em números" (get_public_platform_stats.total_chapters)');
  const row = (health.data || []).find((r) => r.metric_key === 'chapters_participating');
  assert.ok(row, 'Metas: exec_portfolio_health tem chapters_participating');
  assert.equal(Number(row.current), engaged, 'Metas (exec_portfolio_health.chapters_participating.current)');
  // A seção mostra a lista de selos (chapter_registry) embaixo da contagem (partner_entities). Se as
  // duas divergirem, a página volta a se contradizer: um capítulo novo no registro (ADR-0128) ou na
  // negociação pede decisão de quem entra na contagem, não um ajuste neste teste.
  assert.equal((chips.data || []).length, engaged, 'a lista de selos tem o tamanho da contagem');
});

test('C2: a soma do mapa por país é a equipe de pesquisa com país preenchido', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = client();
  const [reach, home, team] = await Promise.all([
    sb.rpc('get_public_country_reach'),
    sb.rpc('get_homepage_stats'),
    sb.from('v_operational_members').select('id'),
  ]);
  for (const r of [reach, home, team]) assert.ifError(r.error);
  const ids = (team.data || []).map((r) => r.id);
  assert.ok(ids.length > 0, 'equipe de pesquisa vazia: o teste não mediria nada');
  assert.equal(ids.length, Number(home.data.members), 'a view é a mesma população do hero');

  const { data: rows, error } = await sb.from('members').select('id,country').in('id', ids);
  assert.ifError(error);
  const comPais = rows.filter((r) => r.country && String(r.country).trim() !== '').length;
  const somaMapa = (reach.data || []).reduce((s, r) => s + Number(r.member_count || 0), 0);
  assert.equal(somaMapa, comPais, 'mapa por país (incluindo Internacional) == equipe de pesquisa com país');
});
