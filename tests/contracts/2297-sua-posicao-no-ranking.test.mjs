// tests/contracts/2297-sua-posicao-no-ranking.test.mjs
// Baldes (#1908 + #1109): "test:structural" E "test:contracts". HERMETICO — le tres dicionarios e
// uma pagina, sem rede e sem banco. NAO entra em "test:behavioural".
/**
 * #2297 — a pergunta "o que eu faco para subir" passa a ter resposta na propria tela.
 *
 * A FRASE DE FALHA QUE ESTE PORTAO PRODUZ:
 *
 *   Se o cartao "sua posicao" perder a ancora de rolagem, reimplementar a composicao por pilar em
 *   vez de reusar a auditavel, ficar mudo para quem nao esta no ranking, ou se uma das nove chaves
 *   sumir de um dos tres dicionarios, este arquivo fica vermelho nomeando o caso.
 *
 * CONTEXTO MEDIDO (14/09, tres analises independentes; re-medido em 15/09):
 *   - "como funciona a pontuacao" JA estava resolvido: composicao por pilar de qualquer um da lista
 *     a um clique, mais a regua viva do catalogo.
 *   - "o que eu faco para subir" NAO fechava: a pessoa rolava a lista inteira, decorava os numeros
 *     do rival, abria outra pagina e subtraia de cabeca.
 *   - 21 de 96 ativos (21,9%) tem `view_pii`, e as seis RPCs de extrato existem e sao SECDEF.
 *     Ou seja, o drill-down de terceiro nao e feature nova; o que faltava era SUPERFICIE.
 *
 * ⚠️ E o cartao NAO amplia exposicao: a composicao por pilar de qualquer linha ja esta a um clique
 * pelo botao `pillar-drill`. O que muda e o trabalho manual, nao o acesso.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = process.cwd();
const ler = (rel) => readFileSync(join(ROOT, rel), 'utf8');
const PAGINA = ler('src/pages/gamification.astro');
const DICTS = ['src/i18n/pt-BR.ts', 'src/i18n/en-US.ts', 'src/i18n/es-LATAM.ts'];

const CHAVES = [
  'meTitle', 'meRank', 'meGoTo', 'meGap', 'meTop', 'meLead', 'meWhere', 'meWhereNone', 'meNotRanked',
];

// ═══════════════════════════════════════════════════════════════════════════
test('A · as nove chaves existem nos TRES dicionarios (GC-097)', () => {
  for (const d of DICTS) {
    const src = ler(d);
    for (const k of CHAVES) {
      assert.ok(src.includes(`'gamification.lb.${k}'`),
        `${d} nao tem 'gamification.lb.${k}'. Uma chave em dois dicionarios de tres entrega a ` +
        'string crua na tela do terceiro idioma, e ninguem que fala portugues percebe');
    }
  }
});

test('B · a pagina consome as nove, e nenhuma fica declarada sem uso', () => {
  for (const k of CHAVES) {
    assert.ok(PAGINA.includes(`t('gamification.lb.${k}', lang)`),
      `a pagina nao carrega 'gamification.lb.${k}' para o dicionario do cliente`);
    const camel = 'lbMe' + k.slice(2, 3).toUpperCase() + k.slice(3);
    assert.ok(PAGINA.includes(`I.${camel}`),
      `${camel} e carregada e nunca usada — chave morta vira drift silencioso`);
  }
});

// ═══════════════════════════════════════════════════════════════════════════
test('C · a ancora de rolagem e um id EXPLICITO, nunca combinacao de classe', () => {
  // ⚠️ ESTA CAMADA NASCE DE UM DEFEITO MEU, pego antes de commitar.
  // A primeira versao do botao fazia `querySelector('[data-lb-row].ring-2')`. Na marcacao real
  // `data-lb-row` esta no div EXTERNO e `ring-2` no INTERNO, entao o seletor casa NADA —
  // e `scrollIntoView` em null nao rola e nao reclama. O botao ficaria inerte, sem erro no
  // console, e so um humano clicando descobriria.
  assert.match(PAGINA, /id="lb-me-row"/,
    'a linha propria precisa de ancora explicita');
  assert.match(PAGINA, /getElementById\('lb-me-row'\)/,
    'o botao tem de buscar a ancora pelo id');
  assert.doesNotMatch(PAGINA, /querySelector\('\[data-lb-row\]\.[a-z]/,
    'seletor que combina atributo do div externo com classe do interno casa NADA e falha calado');
});

test('D · reusa a composicao AUDITAVEL em vez de reimplementar a soma', () => {
  const corpo = PAGINA.slice(
    PAGINA.indexOf('function renderMyPosition'),
    PAGINA.indexOf('function renderPillarBreakdown'),
  );
  assert.ok(corpo.length > 0, 'controle positivo: nao achei renderMyPosition');
  assert.match(corpo, /pillarDrillRows\(/,
    'o delta por pilar tem de sair de `pillarDrillRows`, que e a decomposicao que SOMA exatamente ' +
    'os pontos exibidos. Uma segunda soma aqui poderia divergir do numero ao lado dela, e um ' +
    'numero que nao bate com o vizinho destroi a confianca que esta tela existe para construir');
  assert.doesNotMatch(corpo, /attendance_points|curadoria_points/,
    'coluna crua dentro do cartao e reimplementacao da composicao: use pillarDrillRows');
});

test('E · quem NAO esta no ranking recebe frase, nao silencio', () => {
  const corpo = PAGINA.slice(
    PAGINA.indexOf('function renderMyPosition'),
    PAGINA.indexOf('function renderPillarBreakdown'),
  );
  assert.match(corpo, /idx === -1/, 'o caso "nao estou na lista" tem de ser tratado');
  assert.match(corpo, /lbMeNotRanked/,
    'sem frase, o cartao renderiza vazio — e vazio nesta posicao lê como "o ranking quebrou", ' +
    'que e pior que a ausencia honesta');
});

test('F · o botao tem alvo de toque utilizavel', () => {
  // A analise de UX de 14/09 apontou area de toque abaixo de 24px nos botoes de drill como
  // candidato a falha WCAG 2.2 SC 2.5.8. O botao NOVO nao repete isso.
  const corpo = PAGINA.slice(PAGINA.indexOf("data-action=\"lb-go-to-me\""), PAGINA.indexOf("data-action=\"lb-go-to-me\"") + 400);
  assert.match(corpo, /min-h-\[(2[4-9]|[3-9]\d)px\]/,
    'o botao precisa de altura minima >= 24px (WCAG 2.2 SC 2.5.8)');
});
