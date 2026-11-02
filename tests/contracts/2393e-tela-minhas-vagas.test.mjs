/**
 * Contract: #2393, fatia 3 (ADR-0134 §6, decisão do GP em 02/11/2026) — a tela do líder da vaga, /minhas-vagas.
 *
 * A tela lista as candidaturas das vagas de linha que o líder pode ler e abre o detalhe. Quem decide o acesso
 * são as duas RPCs da fatia 2 (portão, conflito de interesse e registro obrigatório). A tela:
 *   - chama SÓ list_opening_applications e get_opening_application: nada do painel do comitê, de avaliação ou
 *     de IA (D2 (a): sem nota de avaliador e sem saída de IA);
 *   - trata as duas recusas do servidor (Unauthorized e recused_conflict_of_interest) como aviso neutro,
 *     ANTES do ramo de erro, nas duas leituras;
 *   - não pede a lista de novo ao voltar do detalhe, porque cada leitura grava um registro por candidatura;
 *   - escapa o que interpola e só faz link de URL http(s);
 *   - tem as chaves nos 3 idiomas, e as páginas en e es redirecionam para a pt.
 * E admin/selection ganha o selo e o filtro da trilha line_pilot, lidos do painel (evaluation_track).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const ler = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const PAGINA = ler('src/pages/minhas-vagas.astro');
const SCRIPT = maskJsComments(PAGINA.slice(PAGINA.indexOf('<script>'))).replace(/\s+/g, ' ');
const SELECAO = maskJsComments(ler('src/pages/admin/selection.astro')).replace(/\s+/g, ' ');
const DICS = ['pt-BR', 'en-US', 'es-LATAM'].map((l) => [l, ler(`src/i18n/${l}.ts`)]);

test('#2393e: a tela chama só as duas RPCs da leitura por vaga', () => {
  const rpcs = [...new Set([...SCRIPT.matchAll(/\.rpc\(\s*'([a-z_]+)'/g)].map((m) => m[1]))].sort();
  assert.deepEqual(rpcs, ['get_opening_application', 'list_opening_applications'], 'a tela chama outra RPC');
  for (const proibido of ['get_selection_dashboard', 'get_evaluation_form', 'submit_evaluation', 'ai_suggestion', 'ai_analysis', 'ai_triage']) {
    assert.ok(!SCRIPT.includes(proibido), `a tela cita ${proibido}`);
  }
});

test('#2393e: as duas recusas viram aviso neutro, antes do ramo de erro, nas duas leituras', () => {
  assert.match(SCRIPT, /function recusa\(data: any\): boolean \{ if \(data\?\.error === 'Unauthorized'\) \{ showNotice\(I\.empty\); return true; \} if \(data\?\.error === 'recused_conflict_of_interest'\) \{ showNotice\(I\.recused\); return true; \} return false; \}/,
    'recusa() não mapeia Unauthorized e o conflito de interesse para os avisos');
  assert.match(SCRIPT, /const \{ data, error \} = await sb\.rpc\('list_opening_applications', \{ p_opportunity_id: vagaFiltro \|\| null \}\); if \(recusa\(data\)\) return; if \(error \|\| data\?\.error\) \{/,
    'a lista não trata a recusa antes do erro');
  assert.match(SCRIPT, /const \{ data, error \} = await sb\.rpc\('get_opening_application', \{ p_application_id: applicationId \}\); if \(recusa\(data\)\) return; if \(error \|\| data\?\.error\) \{/,
    'o detalhe não trata a recusa antes do erro');
});

test('#2393e: a lista só é pedida ao abrir a página, e voltar do detalhe não pede de novo', () => {
  assert.equal((SCRIPT.match(/sb\.rpc\('list_opening_applications'/g) || []).length, 1, 'a lista é pedida em mais de um lugar');
  assert.equal((SCRIPT.match(/(?<!function )loadList\(\)/g) || []).length, 1, 'loadList é chamada fora do boot');
  assert.match(SCRIPT, /\$\('mv-back'\)\?\.addEventListener\('click', \(\) => \{ showOnly\('list'\); \}\); loadList\(\); \} if \(document\.readyState/, 'a única chamada de loadList não é a do boot');
  assert.match(SCRIPT, /\$\('mv-back'\)\?\.addEventListener\('click', \(\) => \{ showOnly\('list'\); \}\);/, 'voltar pede a lista de novo');
});

test('#2393e: a tela escapa o que interpola e só faz link de URL http(s)', () => {
  assert.doesNotMatch(SCRIPT, /\$\{\s*(data|a|q)\??\.[a-z_]+/, 'a tela interpola campo da candidatura sem esc()');
  assert.match(SCRIPT, /const urlSegura = \(s: unknown\) => \(\/\^https\?:\\\/\\\/\/i\.test\(String\(s \?\? ''\)\) \? String\(s\) : ''\);/, 'urlSegura não restringe a http(s)');
  assert.match(SCRIPT, /const linkedin = urlSegura\(data\.linkedin_url\); const credly = urlSegura\(data\.credly_url\);/, 'os links não passam por urlSegura');
});

test('#2393e: as páginas en e es redirecionam para a pt com o idioma', () => {
  for (const [dir, code] of [['en', 'en-US'], ['es', 'es-LATAM']]) {
    const p = `src/pages/${dir}/minhas-vagas.astro`;
    assert.ok(existsSync(resolve(ROOT, p)), `${p} não existe`);
    assert.match(ler(p), new RegExp(`<meta http-equiv="refresh" content="0;url=/minhas-vagas\\?lang=${code}">`), `${p} não redireciona`);
  }
});

test('#2393e: toda chave da tela e do selo existe nos 3 dicionários', () => {
  const chaves = new Set([...PAGINA.matchAll(/\bt\('((?:myOpenings|myEvals|common)\.[A-Za-z.]+)'/g)].map((m) => m[1]));
  for (const k of ['admin.selection.pilotOnly', 'admin.selection.pilotOnlyHint', 'admin.selection.pilotBadge', 'admin.selection.pilotBadgeHint']) chaves.add(k);
  assert.ok(chaves.size >= 40, `o guard leu só ${chaves.size} chaves`);
  for (const [l, d] of DICS) {
    const faltam = [...chaves].filter((k) => !d.includes(`'${k}':`));
    assert.deepEqual(faltam, [], `${l}: faltam chaves`);
  }
});

test('#2393e: admin/selection filtra e marca a trilha line_pilot pelo campo do painel', () => {
  assert.match(SELECAO, /if \(filterHideShadowVep && r\.extra_flags\?\.is_shadow_vep === true\) return false; if \(filterPilotOnly && r\.evaluation_track !== 'line_pilot'\) return false;/,
    'o filtro da trilha não está em applyFilters');
  assert.match(SELECAO, /\+ \(r\.evaluation_track === 'line_pilot' \? `<div><span [^`]*\$\{esc\(T\.pilotBadge \|\| 'Piloto da linha'\)\}<\/span><\/div>` : ''\);/,
    'a célula da vaga não leva o selo da trilha');
  assert.match(SELECAO, /<button id="filter-pilot-only"[^>]*data-active="false"/, 'o chip do filtro não nasce desligado');
});
