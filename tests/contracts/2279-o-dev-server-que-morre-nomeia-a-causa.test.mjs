// tests/contracts/2279-o-dev-server-que-morre-nomeia-a-causa.test.mjs
// Baldes (#1908 + #1109): "test:structural" E "test:contracts". Este arquivo e HERMETICO — le
// package.json e dois arquivos do repo, sem rede, sem banco e sem subir servidor —, entao NAO
// entra em "test:behavioural", onde esperaria a faixa serializada do banco por nada.
/**
 * #2279 — o `browser_guards` deixa de entregar um timeout mudo quando o dev server morre.
 *
 * O QUE A MEDIÇÃO DE 14/09 MOSTROU, e que este arquivo existe para não deixar regredir.
 *
 * A #2279 registrava a hipótese de que a FREQUÊNCIA do erro `Unable to resolve` acompanharia o
 * desfecho (1 ocorrência no run verde, 8 e 14 nos vermelhos). A medição de hoje **não sustenta**
 * essa leitura, no job `browser_guards`:
 *
 *   | job                  | ocorrências | desfecho |
 *   |----------------------|-------------|----------|
 *   | 104052369030         | 1           | failure  |
 *   | 104050099085 (main)  | 0           | success  |
 *   | 104062268139         | 0           | success  |
 *
 * Um vermelho com UMA ocorrência tem a mesma contagem atribuída ao verde. O que separa os dois é
 * outra coisa: **a exceção é fatal**. No run vermelho a última requisição servida foi às 16:10:07,
 * a exceção às 16:10:08, e depois dela o dev server não serviu mais NADA — daí os 30s de espera
 * por `#boardgov-denied`, que é apenas a primeira rota DEPOIS da queda. O marcador é vítima, não
 * mecanismo.
 *
 * ⚠️ E a retentativa não tinha como passar. O `astro dev` é SINGLETON: com o servidor da tentativa
 * 1 ainda vivo (PID 2544 na porta 42369), a tentativa 2 imprimiu "Another astro dev server is
 * already running" e saiu, enquanto o harness esperava 45s por uma porta NOVA. Por isso cada
 * intermitência custava uma execução inteira: o retry era decorativo.
 *
 * As camadas:
 *
 *   A (unitário)  o classificador reconhece as linhas reais: a exceção fatal (com os códigos ANSI
 *                 que o vite emite) e as DUAS variantes da recusa do singleton, a do CI e a
 *                 JSON da máquina local. Conhecer só uma delas foi o defeito real da primeira
 *                 versão: o fast-fail não disparou aqui, e foram 45s de espera de novo.
 *                 A limpeza de ANSI NÃO decide se o padrão casa (medido por mutação: com ela
 *                 desligada o teste seguia verde); ela decide se o `detail` sai legível, e é
 *                 isso que a camada afirma.
 *   B (unitário)  ele NÃO classifica linha de tráfego normal. Um classificador que acusa todo
 *                 mundo é tão inútil quanto um que não acusa ninguém.
 *   C (unitário)  a explicação carrega a causa, e some quando não houve queda (não inventa causa).
 *   D (estático)  o harness mata o GRUPO de processos e sobe `detached`, como a irmã
 *                 `scripts/smoke-routes.mjs` já fazia. Sem isso o `astro dev` sobrevive ao `npm`
 *                 e bloqueia a tentativa seguinte.
 *   E (estático)  o harness LÊ a saída do dev server (não pode ser `stdio: 'inherit'`, que não
 *                 deixa ninguém classificar nada) e usa o classificador.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  classifyDevServerLine,
  explainWithDevServerState,
  SINGLETON_BLOCKED,
  FATAL_EXCEPTION,
} from '../helpers/dev-server-watch.mjs';

const ROOT = process.cwd();
const HARNESS = join(ROOT, 'tests/browser-guards.test.mjs');
const E = String.fromCharCode(27);

// As linhas ABAIXO são transcrições do log do job 104052369030 (14/09), com o ANSI preservado.
const LINHA_EXCECAO =
  `${E}[31m${E}[1m16:10:08${E}[22m [ERROR] [vite]${E}[39m Uncaught exception: ` +
  'workerd/jsg/_virtual_includes/iterator/workerd/jsg/value.h:1477: failed: remote.jsg.Error: ' +
  'Unable to resolve [/home/runner/work/ai-pm-research-hub/ai-pm-research-hub/src/layouts/' +
  'BaseLayout.astro?astro&type=script&index=0&lang.ts]';
// DUAS variantes reais da mesma recusa, medidas em 14/09. A primeira versão deste guard só
// conhecia a do CI, e ao exercer o harness na máquina local o fast-fail NÃO disparou: foram 45s
// de espera e o mesmo "Server did not start within 45000ms" de sempre. Guard por string que
// conhece uma variante fica cego na outra, e cego lê como verde.
const LINHA_SINGLETON = 'Another astro dev server is already running.';       // CI
const LINHA_SINGLETON_JSON =                                                  // máquina local
  '{"message":"Dev server already running at http://127.0.0.1:4488 (pid 43476)\\n  Stop: ' +
  'astro dev stop","label":"SKIP_FORMAT","level":"info"}';
const LINHA_TRAFEGO =
  `${E}[2m16:10:07${E}[22m ${E}[34m[vite]${E}[39m 16:10:07 [200] /admin/curatorship 127ms`;

// ═══════════════════════════════════════════════════════════════════════════
test('A · reconhece as duas linhas reais do log, com ANSI', () => {
  const fatal = classifyDevServerLine(LINHA_EXCECAO);
  assert.ok(fatal, 'a exceção fatal passou despercebida — e ela é o que mata o servidor');
  assert.equal(fatal.kind, FATAL_EXCEPTION);
  assert.match(fatal.detail, /Unable to resolve/, 'o detalhe precisa carregar o texto do erro');

  // As DUAS variantes, não uma. Cobrir só a do CI deixaria o fast-fail morto na máquina de quem
  // desenvolve, que é justamente onde ele é exercido primeiro.
  for (const [rotulo, linha] of [['CI', LINHA_SINGLETON], ['local/JSON', LINHA_SINGLETON_JSON]]) {
    const singleton = classifyDevServerLine(linha);
    assert.ok(singleton,
      `o bloqueio do singleton (variante ${rotulo}) passou despercebido — é o que inutiliza o retry`);
    assert.equal(singleton.kind, SINGLETON_BLOCKED, `variante ${rotulo} classificada errado`);
  }

  // A MORDIDA. A primeira versão desta camada afirmava "sem remover ANSI nenhum padrão casa" e
  // "provava" isso conferindo que a fixture tem ANSI — o que checa a fixture, não o código. Ao
  // injetar o defeito (limpeza desligada) o teste seguiu VERDE: os padrões casam a frase mesmo
  // cercada de códigos. O que a limpeza realmente entrega é um `detail` LIMPO, e é isso que vai
  // para a mensagem de erro que uma pessoa vai ler.
  assert.ok(
    LINHA_EXCECAO.includes(E),
    'a fixture precisa carregar ANSI, senão não exercita a limpeza',
  );
  assert.ok(
    !fatal.detail.includes(E),
    'o `detail` saiu com códigos ANSI: eles vão parar na mensagem de falha do passo, no meio do ' +
    'texto que alguém precisa ler às pressas',
  );
});

test('B · não classifica tráfego normal', () => {
  assert.equal(classifyDevServerLine(LINHA_TRAFEGO), null,
    'uma linha de requisição servida virou incidente: um classificador que acusa todo mundo ' +
    'obriga o harness a ignorá-lo');
  for (const ruido of ['  URL:  http://127.0.0.1:42369', '  PID:  2544', '', '> astro dev --host 127.0.0.1']) {
    assert.equal(classifyDevServerLine(ruido), null, `"${ruido}" não deveria ser classificado`);
  }
});

test('C · a explicação carrega a causa, e não inventa causa quando não houve queda', () => {
  const timeout = new Error('locator.waitFor: Timeout 30000ms exceeded.');

  const semQueda = explainWithDevServerState(timeout, { fatal: null });
  assert.equal(semQueda, timeout,
    'sem queda observada o erro tem de passar INTACTO — atribuir causa que não se mediu é pior ' +
    'que não atribuir nenhuma');

  const comQueda = explainWithDevServerState(timeout, {
    fatal: classifyDevServerLine(LINHA_EXCECAO),
  });
  assert.notEqual(comQueda, timeout);
  assert.match(comQueda.message, /Timeout 30000ms exceeded/, 'o sintoma original não pode sumir');
  assert.match(comQueda.message, /o dev server morreu ANTES/, 'a causa tem de estar na mensagem');
  assert.match(comQueda.message, /Unable to resolve/, 'e o texto do erro do runtime também');
  assert.match(comQueda.message, /#2279/, 'com a referência para quem for ler daqui a meses');
});

// ═══════════════════════════════════════════════════════════════════════════
test('D · o harness sobe detached e mata o GRUPO, como a irmã smoke-routes já fazia', () => {
  const src = readFileSync(HARNESS, 'utf8');
  assert.match(src, /detached:\s*true/,
    'sem `detached` o filho fica no grupo do pai, e `kill` alcança só o `npm`: o `astro dev` ' +
    'sobrevive reparentado ao init e BLOQUEIA a tentativa seguinte (singleton). Medido em 14/09.');
  assert.match(src, /process\.kill\(\s*-\s*\w+/,
    'o kill tem de ser no GRUPO (pid negativo), não no `npm`');
  assert.match(src, /SIGKILL/,
    'medido na irmã smoke-routes: com SIGTERM o `npm` morre e o `astro dev` NÃO. Educado não basta.');
});

test('E · o harness LÊ a saída do dev server e usa o classificador', () => {
  const src = readFileSync(HARNESS, 'utf8');
  assert.ok(
    !/stdio:\s*'inherit'/.test(src),
    "`stdio: 'inherit'` entrega a saída direto ao passo e não deixa NINGUÉM classificá-la — foi " +
    'por isso que o run de 14/09 entregou "Timeout 30000ms" sem nomear a queda do servidor',
  );
  assert.match(src, /classifyDevServerLine/, 'o harness precisa classificar o que lê');
  assert.match(src, /explainWithDevServerState/, 'e precisa usar a causa ao reportar a falha');
});
