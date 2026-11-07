/**
 * #2974: o bloco de canais de /admin/comms decide pela pergunta do servidor, não por papel ou designação V3, e a faixa
 * de dado parado sai do bloco para todos que entram na página.
 *
 * A grade de canais, a lista de alertas de token e os botões de configurar e de dispensar apareciam só para superadmin,
 * papel `manager` ou `deputy_manager` e designação `comms_leader`. Os botões escrevem por `admin_manage_comms_channel` e
 * `comms_acknowledge_alert`, que perguntam `manage_comms`; a lista vem de `comms_check_token_expiry`, que escreve (varre
 * e cria alertas). O bloco passa a perguntar `canForUnscoped` dessa ação, que é o espelho no front do `can()` sem
 * recurso.
 *
 * A faixa de dado parado ("dado parado há N dias" e "token expirado") explica número velho nas métricas, e por isso vai
 * para todos que entram, no topo do painel. Ela lê só `comms_channel_status`, que não escreve e devolve as linhas a
 * todo o tier de analytics; o portão da página só deixa entrar quem está nele.
 *
 * O guard lê os corpos VIGENTES (`latestFunctionCapture`) e amarra a tela a eles.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { latestFunctionCapture, maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import { ADMIN_ROUTE_ACCESS } from '../../src/lib/navigation.config.ts';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const PAGINA = 'src/pages/admin/comms.astro';
const fonte = () => readFileSync(resolve(ROOT, PAGINA), 'utf8');
const pagina = () => maskJsComments(fonte());

function corpoDe(src, assinatura) {
  const i = src.indexOf(assinatura);
  assert.ok(i >= 0, `${PAGINA}: não tem ${assinatura}`);
  const fim = src.indexOf('\n  }\n', i);
  assert.ok(fim > i, `${PAGINA}: ${assinatura} sem fechamento`);
  return { ini: i, fim, corpo: src.slice(i + assinatura.length, fim) };
}

const sqlVigente = (nome) => {
  const { file, body } = latestFunctionCapture(ROOT, nome);
  return { file, sql: maskLineComments(body) };
};

/** A ação que a RPC de escrita pergunta, lida do corpo vigente. */
function acaoDeEscrita(nome, forma) {
  const { file, sql } = sqlVigente(nome);
  const m = sql.match(forma);
  assert.ok(m, `${nome} (${file}): o portão não tem a forma que o guard lê`);
  return m[1];
}

const acaoDeConfigurar = () => acaoDeEscrita('admin_manage_comms_channel',
  /\bIF NOT public\.can_by_member\(v_caller_member_id, '([a-z_]+)'\) THEN\s+RETURN jsonb_build_object\('success', false, 'error', 'permission_denied'\);/);
const acaoDeDispensar = () => acaoDeEscrita('comms_acknowledge_alert',
  /\bIF v_id IS NULL OR NOT public\.can_by_member\(v_id, '([a-z_]+)'\) THEN\s+RETURN jsonb_build_object\('success', false, 'error', 'unauthorized'\);/);

test('comms: canManageChannels pergunta, pelo canForUnscoped, a ação com que o servidor configura e dispensa', () => {
  const acao = acaoDeConfigurar();
  assert.equal(acaoDeDispensar(), acao, 'configurar canal e dispensar alerta perguntam ações diferentes no servidor');
  const src = pagina();
  assert.match(src, /^\s*import \{ canForUnscoped \} from '\.\.\/\.\.\/lib\/permissions';$/m, 'a página não importa o canForUnscoped');
  const { corpo } = corpoDe(src, 'function canManageChannels(member: any): boolean {');
  assert.match(corpo, new RegExp(`^\\s*if \\(!member\\) return false;\\s*return canForUnscoped\\('${acao}'\\);\\s*$`),
    `canManageChannels não é "sem membro, falso; senão canForUnscoped('${acao}')"`);
  assert.doesNotMatch(src, /\b(?:member|currentMember)\??\.(?:operational_role|designations|is_superadmin)\b/,
    'a página lê papel, designação ou superadmin do membro');
});

test('comms: grade, alertas de token e os dois botões só carregam atrás de canManageChannels', () => {
  const src = pagina();
  const painel = corpoDe(src, 'function showPanel() {');
  const bloco = painel.corpo.match(
    /\bif \(canManageChannels\(currentMember\)\) \{\s*loadChannelConfig\(\);\s*loadTokenAlerts\(\);\s*\} else \{\s*document\.getElementById\('admin-sections'\)\?\.classList\.add\('hidden'\);\s*\}/);
  assert.ok(bloco, 'showPanel não carrega a grade e os alertas só com canManageChannels, escondendo o bloco no else');
  const blocoIni = painel.ini + 'function showPanel() {'.length + bloco.index;
  const dentro = (i, ...faixas) => faixas.some(([a, b]) => i >= a && i < b);
  const chamadas = (nome) => [...src.matchAll(new RegExp(`(?<!function )\\b${nome}\\(\\)`, 'g'))].map((m) => m.index);
  const gate = [blocoIni, blocoIni + bloco[0].length];

  const alertas = corpoDe(src, 'async function loadTokenAlerts() {');
  const tokenCalls = chamadas('loadTokenAlerts');
  assert.ok(tokenCalls.some((i) => dentro(i, gate)), 'loadTokenAlerts não é chamada no bloco de canManageChannels');
  for (const i of tokenCalls) {
    assert.ok(dentro(i, gate, [alertas.ini, alertas.fim]),
      'loadTokenAlerts é chamada fora do bloco de canManageChannels, e quem não gere dispara a varredura');
  }
  assert.equal([...src.matchAll(/\bsb\.rpc\('comms_check_token_expiry'\)/g)].length, 1, 'comms_check_token_expiry é chamada mais de uma vez');
  assert.match(alertas.corpo, /\bsb\.rpc\('comms_check_token_expiry'\)/, 'comms_check_token_expiry saiu de loadTokenAlerts');
  assert.match(alertas.corpo, /\bdata-ack="\$\{a\.id\}"/, 'o botão de dispensar saiu de loadTokenAlerts');

  const grade = corpoDe(src, 'async function loadChannelConfig() {');
  const salvar = corpoDe(src, 'async function saveChannelConfig() {');
  const gradeCalls = chamadas('loadChannelConfig');
  assert.ok(gradeCalls.some((i) => dentro(i, gate)), 'loadChannelConfig não é chamada no bloco de canManageChannels');
  for (const i of gradeCalls) {
    assert.ok(dentro(i, gate, [salvar.ini, salvar.fim]), 'loadChannelConfig é chamada fora do bloco de canManageChannels');
  }
  assert.match(grade.corpo, /\bdata-action="config-channel"/, 'o botão de configurar saiu de loadChannelConfig');
  for (const m of src.matchAll(/data-action="config-channel"|data-ack=/g)) {
    assert.ok(dentro(m.index, [grade.ini, grade.fim], [alertas.ini, alertas.fim]),
      'um botão de configurar ou de dispensar aparece fora de loadChannelConfig e de loadTokenAlerts');
  }
});

test('comms: a faixa de dado parado carrega para todos, lendo só comms_channel_status', () => {
  const src = pagina();
  const painel = corpoDe(src, 'function showPanel() {');
  const faixa = painel.corpo.search(/^ {4}loadStalenessBanner\(\);/m);
  assert.ok(faixa >= 0, 'showPanel não carrega a faixa de dado parado fora de condição');
  assert.ok(faixa < painel.corpo.indexOf('if (canManageChannels(currentMember))'), 'a faixa carrega depois do bloco de canManageChannels');
  assert.equal([...src.matchAll(/(?<!function )\bloadStalenessBanner\(\)/g)].length, 1, 'a faixa carrega por mais de um caminho');
  const { corpo } = corpoDe(src, 'async function loadStalenessBanner() {');
  assert.deepEqual([...corpo.matchAll(/\bsb\.rpc\('([a-z_]+)'/g)].map((m) => m[1]), ['comms_channel_status'],
    'a faixa chama outra RPC além de comms_channel_status');
  assert.match(corpo, /document\.getElementById\('comms-staleness-banner'\)/, 'a faixa não escreve na div dela');
});

test('comms: comms_channel_status só lê e devolve o status a todo o tier que o portão deixa entrar', () => {
  const { file, sql } = sqlVigente('comms_channel_status');
  assert.doesNotMatch(sql, /\b(?:INSERT|UPDATE|DELETE)\b|_comms_token_expiry_scan/, `comms_channel_status (${file}) escreve`);
  assert.match(sql, /\bIF v_id IS NULL OR NOT public\.can_view_comms_analytics\(\) THEN\s+RETURN '\[\]'::jsonb;/,
    `comms_channel_status (${file}): o portão não é o tier de analytics`);
  for (const campo of ['channel', 'sync_status', 'last_sync_at']) {
    assert.match(sql, new RegExp(`'${campo}', c\\.${campo},`), `comms_channel_status (${file}) não devolve ${campo} direto`);
  }
  const tier = sqlVigente('can_view_comms_analytics');
  const acoesDoTier = [...tier.sql.matchAll(/\bpublic\.can_by_member\(v_id, '([a-z_]+)'\)/g)].map((m) => m[1]);
  for (const acao of ADMIN_ROUTE_ACCESS['/admin/comms'].actions) {
    assert.ok(acoesDoTier.includes(acao),
      `can_view_comms_analytics (${tier.file}) não aceita ${acao}, que abre /admin/comms; a faixa viria vazia para quem entra por ela`);
  }
});

test('comms: a faixa fica no topo do painel, fora do bloco de canais e fora da impressão', () => {
  const src = fonte();
  assert.equal([...src.matchAll(/id="comms-staleness-banner"/g)].length, 1, 'a página não tem uma única faixa');
  const faixa = src.indexOf('<div id="comms-staleness-banner" class="hidden"></div>');
  const painel = src.indexOf('<div id="comms-panel"');
  const kpis = src.indexOf('<section id="kpi-section"');
  assert.ok(painel >= 0 && faixa > painel && faixa < kpis, 'a faixa não está no painel, acima dos KPIs');
  const ini = src.indexOf('<div id="admin-sections"');
  const fim = src.indexOf('<!-- Channel Config Modal -->', ini);
  assert.ok(ini > kpis && fim > ini, 'o bloco de canais não tem a forma que o guard lê');
  const bloco = src.slice(ini, fim);
  assert.match(bloco, /id="comms-token-alerts"/, 'a lista de alertas de token saiu do bloco de canais');
  assert.match(bloco, /id="comms-channels-grid"/, 'a grade de canais saiu do bloco de canais');
  const impressao = src.match(/@media print \{\s*([^{]+)\{ display: none !important; \}/);
  assert.ok(impressao, 'a regra de impressão não tem a forma que o guard lê');
  const seletores = impressao[1].split(',').map((x) => x.trim());
  assert.ok(seletores.includes('#admin-sections') && seletores.includes('#comms-staleness-banner'),
    'a impressão mostra o bloco de canais ou a faixa');
});
