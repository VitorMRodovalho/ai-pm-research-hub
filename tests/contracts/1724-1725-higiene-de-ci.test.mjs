/**
 * Contract: #1724 + #1725 — os dois vermelhos de infraestrutura que nao carregavam sinal.
 *
 * Em 10 e 11/08/2026 a `main` e uma PR **doc-only** ficaram vermelhas tres vezes, nenhuma por
 * codigo. Cada uma custa abrir o log, classificar, re-executar e reconferir — e, pior, um vermelho
 * na `main` e exatamente o sinal usado para decidir se da para mergear.
 *
 * ## #1724 — a faixa do banco falhava por fila LONGA, nao por fila TRAVADA
 *
 * `wait-for-db-lane` ja implementa fila justa (ordem total por `started_at`), entao nao havia
 * injusticia: havia aritmetica errada. Medido em 08/2026, 11 runs de cada:
 *
 *   validate:          min 688s | mediana 763s | MAX 1552s
 *   check-invariants:  min  44s | mediana  52s | MAX  871s
 *
 * O teto era **900s**. Um UNICO `validate` na frente ja consumia 688-1552s, entao o teto era menor
 * que a espera legitima por um so job, e impossivel de cumprir com dois na fila — que foi
 * exatamente o caso observado (dois `validate` em sequencia).
 *
 * A correcao troca o criterio: desiste-se por **falta de progresso** (a cabeca da faixa nao muda),
 * nao por tempo total. Enquanto a fila anda, esperar e o comportamento correto.
 *
 * O segundo mecanismo da mesma issue e a chamada de API que morria no primeiro erro de TLS. Agora
 * tem retentativa limitada — e continua **falhando fechado** quando esgota, porque engolir o erro
 * faria a faixa parecer vazia e todo mundo entrar junto no banco (#1509).
 *
 * ## #1725 — um orcamento para duas coisas com variancia muito diferente
 *
 * `timeout-minutes: 2` cobria subir o servidor E exercer as rotas. O boot ficou estavel em ~18s nas
 * duas ocorrencias (com duas reotimizacoes do vite nas duas), ou seja ~15% do orcamento gasto antes
 * da primeira requisicao, e o passo morria **sem nenhuma assercao falhar**.
 *
 * Agora cada fase tem orcamento e mensagem propria, mais um teto por requisicao que antes nao
 * existia. O teto do workflow vira backstop.
 *
 * Este guard e estatico: exercer os caminhos de falha de verdade exigiria subir o dev server e
 * esperar os tetos, o que custa minutos por execucao para reprovar o que a leitura ja pega. Os tres
 * caminhos foram exercidos a mao ao escrever a correcao.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const ACTION = readFileSync(resolve(ROOT, '.github/actions/wait-for-db-lane/action.yml'), 'utf8');
const SMOKE = readFileSync(resolve(ROOT, 'scripts/smoke-routes.mjs'), 'utf8');
const CI = readFileSync(resolve(ROOT, '.github/workflows/ci.yml'), 'utf8');

/**
 * Um guard de AUSENCIA casa o proprio comentario: este arquivo EXPLICA `dev.kill()` como o defeito
 * corrigido, e a explicacao era suficiente para reprovar o codigo certo. Asserções negativas usam
 * esta versao sem prosa.
 */
const SMOKE_CODIGO = SMOKE.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');

// ── #1724 ────────────────────────────────────────────────────────────────────────────────

test('#1724: a faixa desiste por falta de PROGRESSO, nao por tempo total', () => {
  // Controle positivo: sem estes simbolos o scanner nao esta lendo o arquivo certo (#1636).
  assert.match(ACTION, /wait-for-db-lane|faixa do banco/, 'controle positivo: arquivo errado');

  assert.match(ACTION, /stuck-seconds:/, 'sem criterio de "fila travada", volta-se a falhar por fila longa');
  assert.match(ACTION, /stuck_deadline=\$\(\( \$\(date \+%s\) \+ STUCK_AFTER \)\)/,
    'o relogio de travamento precisa ser REINICIADO quando a cabeca da faixa muda');
  assert.match(ACTION, /if \[ "\$head_now" != "\$last_head" \]/,
    'sem comparar a cabeca atual com a anterior, nao ha como saber se a fila andou');
});

test('#1724: o teto de 900s (menor que UM validate) nao voltou', () => {
  // A INVERSA e a causa raiz: 900s < 688-1552s de um unico validate na frente.
  const maxWait = ACTION.match(/max-wait-seconds:[\s\S]*?default:\s*'(\d+)'/);
  assert.ok(maxWait, 'max-wait-seconds perdeu o default');
  assert.ok(
    Number(maxWait[1]) >= 1552,
    `teto absoluto ${maxWait[1]}s e menor que o pior validate medido (1552s): a espera legitima por UM job nao cabe`,
  );

  const stuck = ACTION.match(/stuck-seconds:[\s\S]*?default:\s*'(\d+)'/);
  assert.ok(stuck, 'stuck-seconds perdeu o default');
  assert.ok(
    Number(stuck[1]) >= 1552,
    `janela de travamento ${stuck[1]}s e menor que o job mais longo da faixa (1552s): acusaria travamento em fila que so esta ocupada`,
  );
});

test('#1724: a consulta a API retenta, e continua FALHANDO FECHADO quando esgota', () => {
  assert.match(ACTION, /api-retries:/, 'sem retentativa, um blip de TLS vira vermelho na main');
  assert.match(ACTION, /api_with_retry\(\)/, 'a retentativa precisa envolver as DUAS consultas');

  // A INVERSA, e o ponto inteiro do #1509: engolir o erro faria a faixa parecer VAZIA e todos
  // entrarem juntos no banco. Retentar nao pode virar tolerar.
  assert.doesNotMatch(ACTION, /gh api[^\n]*\|\|\s*true/,
    'apareceu `|| true` numa consulta da faixa: faixa "vazia" por erro e o estrago do #1509');
  assert.match(ACTION, /return 1/, 'esgotadas as tentativas, a funcao tem de sinalizar erro');
  assert.match(ACTION, /set -euo pipefail/, 'sem pipefail, o erro da funcao nao derruba o passo');
});

// ── #1725 ────────────────────────────────────────────────────────────────────────────────

test('#1725: boot, assercoes e requisicao tem orcamentos SEPARADOS', () => {
  assert.match(SMOKE, /BOOT_TIMEOUT_MS/, 'o boot precisa de orcamento proprio');
  assert.match(SMOKE, /ASSERT_TIMEOUT_MS/, 'as assercoes precisam de orcamento proprio');
  assert.match(SMOKE, /REQ_TIMEOUT_MS/, 'sem teto por requisicao, uma rota pendurada come o orcamento inteiro');
  assert.match(SMOKE, /AbortSignal\.timeout\(REQ_TIMEOUT_MS\)/,
    'o teto por requisicao tem de estar armado no fetch, nao so declarado');
});

test('#1725: a falha DIZ qual fase travou', () => {
  // O defeito nao era so o tamanho do teto: era o vermelho nao carregar informacao. "timed out
  // after 2 minutes" nao distingue servidor lento de rota quebrada.
  assert.match(SMOKE, /Isto e boot, nao rota/, 'a falha de boot precisa se identificar como boot');
  assert.match(SMOKE, /Isto e rota, nao boot/, 'a falha de assercoes precisa se identificar como rota');
  assert.match(SMOKE, /rota pendurada/, 'o timeout por requisicao precisa nomear a rota');
  assert.match(SMOKE, /servidor pronto em/, 'o tempo de boot tem de aparecer no log mesmo no caminho feliz');
});

test('#1725: cada rota se anuncia ANTES de ser exercida', () => {
  // Os tres tetos so falam quando ELES disparam. O backstop do workflow mata o processo por fora,
  // e foi esse o caminho das duas ocorrencias: log do boot, depois silencio ate o `##[error]`.
  // Nesse caminho a unica pista e a ultima linha impressa, entao ela tem de sair ANTES do fetch.
  const corpo = SMOKE.slice(SMOKE.indexOf('async function req('), SMOKE.indexOf('async function waitForServer('));
  assert.ok(corpo.length > 0, 'controle positivo: nao achei a funcao req() no smoke-routes.mjs');

  const posLog = corpo.indexOf('console.log(`[smoke] -> ${path}`)');
  const posFetch = corpo.indexOf('await fetch(');
  assert.ok(posLog !== -1, 'sem log por rota, um passo morto pelo backstop nao diz onde parou');
  assert.ok(
    posFetch !== -1 && posLog < posFetch,
    'o log da rota sai DEPOIS do fetch: nessa ordem a rota pendurada e justamente a que nao aparece',
  );
});

test('#1725: morto pelo backstop, o passo leva o dev server junto', () => {
  // Observado ao exercer o script: `timeout` matou o pai, o `finally` nao rodou (SIGTERM nao
  // desenrola a pilha) e o `astro dev` sobreviveu segurando o stdout. Como o backstop do workflow
  // mata exatamente assim, o filho precisa de handler proprio, nao so do `finally`.
  assert.match(SMOKE, /process\.once\('SIGTERM'/, 'sem handler de SIGTERM o dev server vira orfao');
  assert.match(SMOKE, /process\.once\('SIGINT'/, 'idem para o Ctrl-C local');

  // Medido em tres rodadas, cada uma derrubando uma hipotese:
  //   1. `dev.kill('SIGTERM')`        -> 1 orfao (morre o `npm`, o `astro dev` fica)
  //   2. SIGTERM no GRUPO             -> 1 orfao (o sinal CHEGA, o astro dev nao sai)
  //   3. SIGTERM no grupo + SIGKILL   -> 0 orfaos
  // Por isso as tres pecas sao exigidas juntas: tirar qualquer uma reproduz o orfao.
  assert.match(SMOKE, /detached:\s*true/, 'sem grupo proprio, sinalizar o grupo nao e possivel');
  assert.match(SMOKE, /process\.kill\(-dev\.pid, sinal\)/,
    'o pid tem de ir NEGATIVO: positivo mata so o npm e o astro dev fica orfao');
  assert.match(SMOKE, /sinalizarGrupo\('SIGKILL'\)/,
    'sem escalar, o astro dev ignora o SIGTERM e sobrevive — medido, nao suposto');
  assert.doesNotMatch(SMOKE_CODIGO, /dev\.kill\(/,
    'voltou o kill no filho direto: era ele que deixava o astro dev de pe');
  // Controle positivo do proprio stripper: se ele apagar codigo, a negativa acima fica decorativa.
  assert.match(SMOKE_CODIGO, /process\.kill\(-dev\.pid/, 'o stripper de comentarios comeu codigo');
});

test('#1725: o teto do passo virou backstop, nao o primeiro a desistir', () => {
  const bloco = CI.slice(CI.indexOf('Smoke Test Routes'));
  const teto = bloco.match(/timeout-minutes:\s*(\d+)/);
  assert.ok(teto, 'o passo Smoke Test Routes perdeu o timeout-minutes');

  const minutos = Number(teto[1]);
  assert.ok(minutos > 2, `timeout-minutes ${minutos} nao pode ser o valor antigo: 2 min cobria boot + assercoes juntos`);

  // E tem de ser MAIOR que a soma dos orcamentos internos, senao o backstop dispara primeiro e o
  // diagnostico se perde outra vez — que e o defeito original com outro numero.
  //
  // O separador de milhar do JS (`90_000`) faz parte do numero: capturar so `\d+` leria 90 e a
  // comparacao passaria contra 210ms em vez de 210s, ou seja o guard ficaria decorativo.
  const orcamento = (nome) => {
    const achado = SMOKE.match(new RegExp(`${nome} \\|\\| (\\d[\\d_]*)`));
    assert.ok(achado, `${nome} perdeu o default no smoke-routes.mjs`);
    return Number(achado[1].replace(/_/g, ''));
  };
  const boot = orcamento('SMOKE_BOOT_TIMEOUT_MS');
  const asserts = orcamento('SMOKE_ASSERT_TIMEOUT_MS');
  assert.ok(boot >= 1000 && asserts >= 1000,
    `orcamentos lidos como ${boot}ms/${asserts}ms: a captura perdeu o separador de milhar`);
  assert.ok(
    minutos * 60_000 > boot + asserts,
    `o teto do passo (${minutos}min) tem de exceder boot+assercoes (${(boot + asserts) / 1000}s), senao ele desiste antes de quem sabe explicar`,
  );
});
