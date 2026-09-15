// tests/contracts/2308-o-smoke-classifica-a-excecao-do-dev-server.test.mjs
// Baldes (#1908 + #1109): "test:structural" E "test:contracts". Este arquivo e HERMETICO — le dois
// arquivos do repo e exercita funcoes puras, sem rede, sem banco e sem subir servidor —, entao NAO
// entra em "test:behavioural", onde esperaria a faixa serializada do banco por nada.
/**
 * #2308 — o `Smoke Test Routes` deixa de acusar a rota errada quando quem falhou foi o dev server.
 *
 * A FRASE DE FALHA QUE ESTE PORTAO EXISTE PARA PRODUZIR:
 *
 *   Quando a resolucao do `BaseLayout` falha DURANTE a requisicao de uma rota, o smoke vai a
 *   vermelho nomeando a excecao do vite e dizendo que a rota e VITIMA. Quando o marcador esta
 *   genuinamente ausente da pagina, ele vai a vermelho com a assercao original e diz, com numero,
 *   que NAO houve causa de infraestrutura.
 *
 * O QUE A MEDICAO DE 15/09 MOSTROU, e que muda a proposta escrita na propria issue.
 *
 * A issue propunha "se a excecao apareceu na janela, falhar com ela". Medido, "a janela" nao podia
 * ser o RUN: a presenca no run nao discrimina.
 *
 *   | run          | desfecho | excecoes no `validate` | dentro de janela de assertContains |
 *   |--------------|----------|-----------------------:|----------------------------------:|
 *   | 34907019986  | failure  |                     17 |                  >=1 (a que caiu) |
 *   | 34983188642  | success  |                      2 |                                 0 |
 *   | 34979378916  | success  |                      0 |                                 0 |
 *   | 34925585161  | success  |                      0 |                                 0 |
 *   | 34989938199  | success  |                      0 |                                 0 |
 *   | 34982813861  | success  |                      0 |                                 0 |
 *
 * Um run VERDE teve DUAS excecoes. Um classificador por presenca-no-run teria acusado esse verde de
 * infraestrutura — a mesma mordida que a #2279 ja tinha levado com FREQUENCIA. Por isso a unidade
 * de atribuicao aqui e a JANELA DA PROPRIA REQUISICAO.
 *
 * E a segunda diferenca para a #2279, que e o que autoriza a re-amostragem: no `browser_guards` a
 * excecao e FATAL (depois dela o servidor nao serviu mais nada, e a retentativa era decorativa
 * porque o `astro dev` e singleton). No `validate`/smoke ela NAO e: as 28 rotas de `assertOk`
 * responderam 2xx com 17 excecoes pelo meio. Re-pedir a rota e uma segunda AMOSTRA de um servidor
 * vivo, e a assercao continua tendo de passar por merito — o que a camada D prova por mutacao.
 *
 * As camadas:
 *   A (unidade)  o classificador reconhece a linha REAL do log, com ANSI.
 *   B (unidade)  a JANELA atribui no vermelho e NAO atribui no verde. O controle negativo vem da
 *                historia e e provado NAO-VACUO: o run verde CONTEM duas excecoes.
 *   C (unidade)  as TRES saidas da explicacao, e "nao consegui ler" nao vira "nao houve".
 *   D (mutacao)  marcador genuinamente ausente REPROVA depois de esgotar as amostras.
 *   E (mutacao)  marcador que so aparece na 2a amostra PASSA e ANUNCIA, com token estavel.
 *   F (estatico) o smoke LE a saida do dev server, re-emite tudo, e delega ao helper compartilhado.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  classifyDevServerLine,
  createDevServerWatch,
  explainContentFailure,
  assertContentWithResamples,
  FATAL_EXCEPTION,
} from '../helpers/dev-server-watch.mjs';

const ROOT = process.cwd();
const SMOKE = join(ROOT, 'scripts/smoke-routes.mjs');
const E = String.fromCharCode(27);

// Transcricao FIEL do job 104185959684 (run 34907019986, main `ecb36a59`, 14/09), com o ANSI
// preservado. Uma fixture reescrita a mao prova que o padrao casa a fixture, nao o log.
const LINHA_EXCECAO =
  `${E}[31m${E}[1m23:19:16${E}[22m [ERROR] [vite]${E}[39m Uncaught exception: ` +
  'workerd/jsg/_virtual_includes/iterator/workerd/jsg/value.h:1477: failed: remote.jsg.Error: ' +
  'Unable to resolve [/home/runner/work/ai-pm-research-hub/ai-pm-research-hub/src/layouts/' +
  'BaseLayout.astro?astro&type=script&index=0&lang.ts]';

const t = (iso) => Date.parse(iso);

// ═══════════════════════════════════════════════════════════════════════════
test('A · reconhece a linha real do log do smoke, e o detail sai sem ANSI', () => {
  const c = classifyDevServerLine(LINHA_EXCECAO);
  assert.ok(c, 'a excecao de resolucao do BaseLayout passou despercebida');
  assert.equal(c.kind, FATAL_EXCEPTION);
  assert.match(c.detail, /Unable to resolve/);
  assert.ok(LINHA_EXCECAO.includes(E), 'a fixture precisa carregar ANSI, senao nao exercita nada');
  assert.ok(!c.detail.includes(E), 'o detail vai para a mensagem que alguem le as pressas');
});

// ═══════════════════════════════════════════════════════════════════════════
test('B · a janela atribui no vermelho e NAO atribui no verde (controle nao-vacuo)', () => {
  // ---- o VERMELHO: job 104185959684, a requisicao que falhou ----
  // 23:20:49.8095 `[smoke] -> /admin/selection` · 23:20:49.8147 a excecao · 23:20:52.4711 a resposta
  const vermelho = createDevServerWatch(() => t('2026-09-14T23:20:49.8147057Z'));
  vermelho.observe(LINHA_EXCECAO);
  const naJanelaVermelha = vermelho.naJanela(
    t('2026-09-14T23:20:49.8095306Z'),
    t('2026-09-14T23:20:52.4711593Z'),
  );
  assert.equal(naJanelaVermelha.length, 1,
    'a excecao caiu DENTRO da janela da requisicao que falhou, e e isso que autoriza atribuir');

  // ---- o VERDE: run 34983188642, que passou COM duas excecoes ----
  // 15:24:07.2345 (dentro de `/admin`, assertOk) e 15:24:17.4864 (dentro de `/notifications`).
  // A fase de assertContains comeca as 15:24:23.0776 e nao tem nenhuma.
  let relogio = t('2026-09-15T15:24:07.2345167Z');
  const verde = createDevServerWatch(() => relogio);
  verde.observe(LINHA_EXCECAO);
  relogio = t('2026-09-15T15:24:17.4864136Z');
  verde.observe(LINHA_EXCECAO);

  // ⚠️ O CONTROLE TEM DE CONTER O OUTRO ESTADO, senao ele so prova que estava limpo.
  assert.equal(verde.totalNoRun, 2,
    'controle vacuo: o run verde escolhido precisa MESMO ter tido excecoes, senao a camada nao ' +
    'distingue "a janela filtrou" de "nao havia nada para filtrar"');

  const naJanelaVerde = verde.naJanela(
    t('2026-09-15T15:24:23.0776183Z'),  // `[smoke] -> /admin/selection`, ja em assertContains
    t('2026-09-15T15:24:23.5338327Z'),  // a rota seguinte
  );
  assert.equal(naJanelaVerde.length, 0,
    'as duas excecoes do run VERDE cairam em janelas de assertOk. Se a janela as atribuisse a esta ' +
    'requisicao, o classificador acusaria de infraestrutura um run que passou — que e exatamente a ' +
    'armadilha em que a #2279 caiu ao raciocinar por FREQUENCIA');
});

// ═══════════════════════════════════════════════════════════════════════════
test('C · as tres saidas da explicacao, e nao-medido nao vira medido-zero', () => {
  const base = () => new Error('Expected /admin/selection to contain "id=\\"sel-denied\\""');

  const comCausa = explainContentFailure(base(), {
    naJanela: [classifyDevServerLine(LINHA_EXCECAO)],
    totalNoRun: 17,
    linhasLidas: 900,
    amostras: 3,
  });
  assert.match(comCausa.message, /Expected \/admin\/selection to contain/,
    'o sintoma original nao pode sumir: e por ele que se acha o caso nos logs antigos');
  assert.match(comCausa.message, /CAUSA MEDIDA/);
  assert.match(comCausa.message, /Unable to resolve/);
  assert.match(comCausa.message, /VITIMA/, 'a mensagem tem de dizer que a rota nomeada nao e a causa');
  assert.match(comCausa.message, /#2308/);

  const semCausa = explainContentFailure(base(), {
    naJanela: [], totalNoRun: 2, linhasLidas: 900, amostras: 3,
  });
  assert.match(semCausa.message, /SEM CAUSA DE INFRAESTRUTURA/);
  assert.doesNotMatch(semCausa.message, /CAUSA MEDIDA/,
    'janela limpa nao pode atribuir infraestrutura: seria inventar causa, e foi por isso que o ' +
    'classificador por presenca-no-run foi descartado');
  assert.match(semCausa.message, /2 no run/,
    'o numero que sustenta a afirmacao tem de estar na mensagem, senao e so uma opiniao');

  const naoMedido = explainContentFailure(base(), {
    naJanela: [], totalNoRun: 0, linhasLidas: 0, amostras: 3,
  });
  assert.match(naoMedido.message, /NAO MEDIDO/);
  assert.doesNotMatch(naoMedido.message, /SEM CAUSA DE INFRAESTRUTURA/,
    'ZERO linhas lidas e `unreachable`, nao "nao houve excecao". Dobrar os dois faz o detector ' +
    'mentir na direcao perigosa: basta o pipe quebrar para ele declarar a pagina culpada');
});

// ═══════════════════════════════════════════════════════════════════════════
// D e E sao a prova por MUTACAO: os dois defeitos injetados, nos dois sentidos.
// ═══════════════════════════════════════════════════════════════════════════
const respostaCom = (corpo) => ({
  res: { ok: true, status: 200, text: async () => corpo },
  inicio: 0,
  fim: 1,
});

test('D · mutacao: marcador GENUINAMENTE ausente continua reprovando', async () => {
  const watch = createDevServerWatch();
  watch.observe('  algum trafego normal, so para linhasLidas nao ser zero');
  let pedidos = 0;

  await assert.rejects(
    () => assertContentWithResamples({
      path: '/admin/selection',
      fragment: 'id="sel-denied"',
      watch,
      tentativas: 3,
      pedir: async () => { pedidos += 1; return respostaCom('<html>pagina sem o marcador</html>'); },
    }),
    (err) => {
      assert.match(err.message, /Expected \/admin\/selection to contain/);
      assert.match(err.message, /SEM CAUSA DE INFRAESTRUTURA/,
        'sem excecao na janela, a falha tem de ser atribuida a PAGINA');
      return true;
    },
    'A RE-AMOSTRAGEM AFROUXOU A ASSERCAO. O marcador `*-denied` e o que prova que uma rota admin ' +
    'nao vaza conteudo para quem nao tem autoridade (#2279 diz, em letra, para nao afrouxar isto). ' +
    'Se um corpo que NUNCA traz o marcador passa, este portao virou decoracao.',
  );

  assert.equal(pedidos, 3, 'as tres amostras tem de ter sido pedidas antes de desistir');
});

test('E · mutacao inversa: marcador na 2a amostra passa E anuncia, com token estavel', async () => {
  const watch = createDevServerWatch();
  watch.observe('  trafego normal');
  const ditas = [];
  let n = 0;

  await assertContentWithResamples({
    path: '/admin/sustainability',
    fragment: 'id="sust-denied"',
    watch,
    tentativas: 3,
    pedir: async () => {
      n += 1;
      return respostaCom(n === 1 ? '<html>sem marcador</html>' : '<html>id="sust-denied"</html>');
    },
    log: (linha) => ditas.push(linha),
  });

  assert.equal(n, 2, 'tem de parar na amostra que achou, nao gastar as tres');
  const anuncio = ditas.find((l) => l.includes('REAMOSTRAGEM-SALVOU'));
  assert.ok(anuncio,
    'um verde que so aconteceu na 2a amostra tem de deixar rastro CONTAVEL. Sem o anuncio a ' +
    're-amostragem esconde a #2308 em vez de tolera-la, e ninguem consegue medir se ela sumiu');
  assert.match(anuncio, /\/admin\/sustainability/);
  assert.match(anuncio, /#2308/);
});

// ═══════════════════════════════════════════════════════════════════════════
/**
 * Tira comentarios antes de medir. A primeira versao desta camada REPROVOU o codigo ja corrigido,
 * porque o proprio comentario que explica o conserto cita `stdio: 'inherit'` para dizer que NAO se
 * deve usar. Um guard estatico que casa a prosa que descreve o anti-padrao acusa exatamente quem
 * documentou o conserto — e, pior, ficaria verde se alguem removesse o comentario e mantivesse o
 * defeito.
 */
const semComentarios = (src) =>
  src
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .split('\n')
    .filter((l) => !/^\s*\/\//.test(l))
    .join('\n');

test('F · o smoke LE a saida do dev server, re-emite tudo, e usa o helper compartilhado', () => {
  const bruto = readFileSync(SMOKE, 'utf8');
  const src = semComentarios(bruto);

  // Controle positivo do proprio despedacador: se ele nao tirasse nada, a assercao abaixo estaria
  // medindo a prosa; se tirasse tudo, as assercoes positivas ficariam vacuas.
  assert.ok(src.length < bruto.length, 'controle: o despedacador de comentarios nao tirou nada');
  assert.match(src, /spawn\(/, 'controle: o despedacador comeu o codigo, nao so os comentarios');
  assert.ok(/stdio:\s*'inherit'/.test(bruto),
    'controle: o comentario que NOMEIA o anti-padrao precisa seguir no arquivo — e ele que ensina ' +
    'o proximo leitor por que a saida e lida. Se sumir, esta camada passa a medir outra coisa');

  assert.ok(!/stdio:\s*'inherit'/.test(src),
    "`stdio: 'inherit'` entrega a saida direto ao passo e nao deixa NINGUEM classifica-la — era por " +
    'isso que o vermelho chegava como "Expected /admin/<rota> to contain ..." com a excecao do vite ' +
    'impressa um segundo antes, no mesmo log, sem ninguem cruzar as duas');

  assert.match(src, /createDevServerWatch/, 'o smoke precisa observar a saida');
  assert.match(src, /assertContentWithResamples/,
    'a assercao de conteudo tem de vir do helper COMPARTILHADO: uma copia local aqui nao seria ' +
    'alcancada pelas mutacoes D e E, e um guard que nao toca o codigo que roda nao guarda nada');
  assert.match(src, /watch\.observe\(/, 'cada linha lida tem de passar pelo classificador');
  assert.match(src, /saida\.write\(/,
    'o passo tem de continuar vendo TUDO o que via com `inherit`: trocar o log por um resumo ' +
    'perderia justamente as linhas do vite que permitiram diagnosticar isto');
});
