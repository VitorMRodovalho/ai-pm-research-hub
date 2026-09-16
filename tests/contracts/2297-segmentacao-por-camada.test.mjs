// tests/contracts/2297-segmentacao-por-camada.test.mjs
// Baldes (#1908 + #1109): "test:structural" E "test:contracts". HERMETICO — le tres dicionarios,
// uma pagina e um util, sem rede e sem banco. NAO entra em "test:behavioural".
/**
 * #2297 2a metade — o ranking passa a comparar POR CAMADA, e a camada sai do DADO.
 *
 * A FRASE DE FALHA QUE ESTE PORTAO PRODUZ:
 *
 *   Se alguem reintroduzir uma lista fixa de nomes de papel (no util de rotulos ou na derivacao
 *   das camadas), este arquivo fica vermelho nomeando a lista. E a consequencia nao e cosmetica:
 *   uma lista fixa SOME com quem tem papel fora dela, em silencio, sem lista vazia e sem erro.
 *
 * CONTEXTO MEDIDO (15/09, sobre o predicado REAL do ranking):
 *   - A proposta de 15/09 enumerava 7 camadas sobre 96 pessoas contadas com `is_active`.
 *   - `get_gamification_leaderboard` NAO filtra `is_active`. O predicado dele e
 *     `gamification_opt_out = false AND (current_cycle_active OR tem ponto na janela do ciclo)`.
 *   - Sobre ESSE denominador: 95 pessoas e OITO camadas. A oitava e `alumni`, com 6 pessoas,
 *     todas inativas, que entram pelo ramo "tem ponto no ciclo".
 *   - `getRoleLabelsMap` tinha 11 nomes fixos e omitia `chapter_liaison`, `deputy_manager` e
 *     `alumni`, ou seja, tres valores VIVOS da coluna.
 *   - `operational_role = 'alumni'` e `member_status = 'alumni'` sao o MESMO conjunto (31
 *     pessoas), porque a coluna e cache de trigger: a camada e estado de ciclo de vida, nao
 *     funcao. Dai o rotulo "Egresso" em pt-BR.
 *
 * Cross-ref: #2297, #2316 (1a metade), ADR-0071 (member lifecycle), CLAUDE.md (operational_role
 * e cache de `sync_operational_role_cache`).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = process.cwd();
const ler = (rel) => readFileSync(join(ROOT, rel), 'utf8');
const PAGINA = ler('src/pages/gamification.astro');
const UTILS = ler('src/i18n/utils.ts');
const DICTS = ['src/i18n/pt-BR.ts', 'src/i18n/en-US.ts', 'src/i18n/es-LATAM.ts'];

const CHAVES = ['layerAll', 'layerNote', 'layerOf'];

// ═══════════════════════════════════════════════════════════════════════════
test('A · as tres chaves novas existem nos TRES dicionarios (GC-097)', () => {
  for (const d of DICTS) {
    const src = ler(d);
    for (const k of CHAVES) {
      assert.ok(src.includes(`'gamification.lb.${k}'`),
        `${d} nao tem 'gamification.lb.${k}'. Uma chave em dois dicionarios de tres entrega a ` +
        'string crua na tela do terceiro idioma, e ninguem que fala portugues percebe');
    }
  }
});

test('B · a pagina consome as tres, e nenhuma fica declarada sem uso', () => {
  for (const k of CHAVES) {
    assert.ok(PAGINA.includes(`t('gamification.lb.${k}', lang)`),
      `a pagina nao carrega 'gamification.lb.${k}' para o dicionario do cliente`);
    const camel = 'lbLayer' + k.slice('layer'.length);
    assert.ok(PAGINA.includes(`I.${camel}`),
      `${camel} e carregada e nunca usada — chave morta vira drift silencioso`);
  }
});

// ═══════════════════════════════════════════════════════════════════════════
test('C · a OITAVA camada tem rotulo nos tres dicionarios', () => {
  // Sem `role.alumni`, `roleLabelFor` cai no fallback e a chip mostra a string crua "alumni".
  // Sao 6 pessoas VIVAS no ranking, nao um caso hipotetico.
  for (const d of DICTS) {
    assert.ok(ler(d).includes("'role.alumni'"),
      `${d} nao tem 'role.alumni'. A camada existe no dado e apareceria como chave crua na chip`);
  }
});

test('D · getRoleLabelsMap e DERIVADO do dicionario, nao de uma lista de nomes', () => {
  const corpo = (UTILS.match(/export function getRoleLabelsMap[\s\S]*?\n}/) || [])[0] ?? '';
  assert.ok(corpo.length > 0, 'controle positivo: nao achei getRoleLabelsMap');

  assert.match(corpo, /Object\.keys\(/,
    'o mapa tem de ser derivado enumerando o dicionario');
  assert.match(corpo, /startsWith\('role\.'\)/,
    'a derivacao tem de ser pelo PREFIXO `role.`, senao pega outros namespaces');

  // A regressao concreta: o array de nomes que existia antes.
  const nomesFixos = corpo.match(/'(manager|tribe_leader|researcher|guest|sponsor|curator|ambassador|founder|facilitator|communicator|comms_leader|chapter_liaison|deputy_manager|alumni)'/g) || [];
  assert.deepEqual(nomesFixos, [],
    'voltou uma lista fixa de nomes de papel em getRoleLabelsMap: ' + nomesFixos.join(', ') +
    '. Papel fora da lista recebe o valor cru de volta e parece nao existir — foi assim que ' +
    '`chapter_liaison`, `deputy_manager` e `alumni` ficaram sem rotulo');
});

// ═══════════════════════════════════════════════════════════════════════════
test('E · as camadas do ranking saem do DADO, nunca de uma lista de nomes', () => {
  const corpo = (PAGINA.match(/function deriveLayers[\s\S]*?\n  }/) || [])[0] ?? '';
  assert.ok(corpo.length > 0, 'controle positivo: nao achei deriveLayers');

  assert.match(corpo, /operational_role/,
    'a camada tem de vir de `operational_role` na propria linha do ranking');

  const nomesFixos = corpo.match(/'(researcher|tribe_leader|chapter_liaison|guest|alumni|sponsor|manager|deputy_manager)'/g) || [];
  assert.deepEqual(nomesFixos, [],
    'deriveLayers passou a citar nome de camada: ' + nomesFixos.join(', ') +
    '. Uma lista de 7 nomes sumiria com as 6 pessoas de `alumni` da tela, sem erro e sem ' +
    'lista vazia — que e exatamente o defeito que esta onda evitou');

  assert.match(PAGINA, /deriveLayers\(allRanked\)|layers\.map\(/,
    'as chips tem de ser montadas a partir do resultado de deriveLayers');
});

test('F · o posto exibido e o posto DENTRO da camada, e "sua posicao" recebe as filtradas', () => {
  const corpo = (PAGINA.match(/function renderLeaderboard\(\)[\s\S]*?renderMyPosition\(rankedRows\);/) || [])[0] ?? '';
  assert.ok(corpo.length > 0, 'controle positivo: nao achei o trecho de renderLeaderboard');

  // A ordem importa: ordenar global, DEPOIS filtrar. O inverso daria posto dentro da camada
  // por acidente de ordenacao parcial.
  const posSort = corpo.indexOf('.sort(');
  const posFiltro = corpo.indexOf('leaderboardLayer');
  assert.ok(posSort !== -1 && posFiltro > posSort,
    'o filtro de camada tem de vir DEPOIS da ordenacao global');

  assert.match(corpo, /renderMyPosition\(rankedRows\)/,
    '"sua posicao" tem de receber as linhas FILTRADAS, senao o posto continua sendo o global ' +
    'enquanto a lista mostra a camada');
});

test('G · camada que esvaziou volta para "todas" em vez de lista vazia', () => {
  assert.match(PAGINA, /if \(daCamada\.length\) rankedRows = daCamada; else leaderboardLayer = '';/,
    'sem esse retorno, uma camada que sumiu entre dois carregamentos deixa a lista vazia, e ' +
    'lista vazia aqui le como "o ranking quebrou"');
});

test('H · a chip "todas" sobrevive ao dispatcher (o bug do truthy-check)', () => {
  // `data-layer=""` e intencional. Um `|| ''` com truthy-check trataria a volta para "todas"
  // como clique sem acao, e o usuario ficaria preso na camada.
  assert.match(PAGINA, /target\.dataset\.layer \?\? ''/,
    'o dispatcher tem de usar `?? \'\'`: com `||` a chip "todas" nao faz nada e prende o ' +
    'usuario na camada selecionada');
});
