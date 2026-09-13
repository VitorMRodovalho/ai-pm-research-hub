// tests/contracts/2255-carimbo-de-proveniencia-e-detector-de-atraso.test.mjs
// Register in the "test:structural" AND "test:contracts" whitelists in package.json (#1109).
// Este arquivo e HERMETICO: nao abre conexao de banco. Registra-lo tambem em `test:behavioural`
// o poria para esperar a faixa serializada por nada, e o guard do #1908 reprova exatamente isso
// ("estes sao hermeticos e estao em test:behavioural, esperando a faixa por nada"). O cabecalho
// de "registre nos DOIS" vale para teste DB-aware, nao para este.
/**
 * #2255 — o deploy carimba o commit que publicou, e alguem le esse carimbo.
 *
 * O DEFEITO (medido em 13/09/2026): a A3 fez o deploy depender do `CI Validate` por `workflow_run`.
 * Quando o `CI Validate` nao fecha verde, o run do Deploy termina como **`skipped`**, e `skipped` nao
 * e vermelho em lugar nenhum — nao falha check, nao abre issue, nao aparece em varredura que procure
 * `failure`. Nos ultimos 100 runs do Deploy: 88 `success` e 12 `skipped`; e **9 SHAs da main tiveram
 * skip e nunca um success**. Enquanto isso 5 dos ultimos 12 `CI Validate` da main falharam, todos por
 * `browser_guards` (#2231).
 *
 * A SEGUNDA METADE, que fechava o diagnostico pelo pior lado: nao havia como **perguntar a producao
 * qual commit ela roda**. O `deploy.yml` nao carimbava SHA e nao existia rota de versao. O atraso era
 * invisivel nas duas pontas, e descobri-lo exigiu cruzar o historico de runs a mao.
 *
 * O QUE ESTE ARQUIVO DEFENDE, e por que cada asserção existe:
 *
 *   1. O carimbo vem do MESMO commit que foi publicado. Num `workflow_run`, `github.sha` e o HEAD do
 *      branch padrao NO MOMENTO do run — nao o commit que disparou. Carimbar `github.sha` publicaria
 *      um commit e declararia outro, o que e PIOR que nao carimbar: o numero teria cara de medicao.
 *      Esta e a armadilha 1 do cabecalho do proprio `deploy.yml`, aplicada ao carimbo.
 *
 *   2. A rota nao pode ser cacheavel. Uma resposta cacheada devolve o SHA do build ANTERIOR, e o
 *      detector leria "em dia" durante exatamente o periodo em que a producao estivesse atrasada.
 *
 *   3. `unreachable` nao pode FECHAR alerta. Tratar "nao consegui medir" como "esta tudo bem" e a
 *      forma mais comum de um detector mentir na direcao perigosa: bastaria o site oscilar para o
 *      alerta de atraso sumir sozinho. E a mesma familia de "zero de uma chamada de ferramenta e
 *      ambiguo entre dado e chamada".
 *
 *   4. A carencia tem de existir. Atraso curto e NORMAL (o caminho leva ~16 min), e um detector que
 *      alerta em todo merge vira ruido — e alerta que quase sempre erra treina a ignorar.
 *
 * Cross-ref: #2255, #2231 (a instabilidade que dispara o skip), #2219 (o retry que nao e retry),
 * A3 (o cabecalho de `.github/workflows/deploy.yml`).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = process.cwd();
const ler = (rel) => readFileSync(join(ROOT, rel), 'utf8');

const DEPLOY = '.github/workflows/deploy.yml';
const HEARTBEAT = '.github/workflows/ci-heartbeat-monitor.yml';
const ROTA = 'src/pages/api/version.ts';

/** Tira comentarios YAML de linha inteira: um guard que casa o proprio comentario nao mede nada. */
const semComentarios = (yml) =>
  yml.split('\n').filter((l) => !/^\s*#/.test(l)).join('\n');

// ═══════════════════════════════════════════════════════════════════════════
// 1. O carimbo, e de qual commit ele vem
// ═══════════════════════════════════════════════════════════════════════════

test('#2255: o deploy passa PUBLIC_RELEASE_SHA para o build', () => {
  const yml = semComentarios(ler(DEPLOY));
  assert.match(yml, /PUBLIC_RELEASE_SHA=/,
    'o deploy deve exportar PUBLIC_RELEASE_SHA antes do build');
  assert.match(yml, /PUBLIC_RELEASE_BUILT_AT=/,
    'o deploy deve exportar PUBLIC_RELEASE_BUILT_AT');
  assert.match(yml, /PUBLIC_RELEASE_RUN_ID=/,
    'o deploy deve exportar PUBLIC_RELEASE_RUN_ID (leva do sintoma ao log do deploy em um clique)');
});

test('#2255: o carimbo sai do commit PUBLICADO, nao do HEAD do momento (armadilha 1 aplicada ao carimbo)', () => {
  const yml = semComentarios(ler(DEPLOY));

  const linhaCarimbo = yml.split('\n').find((l) => l.includes('PUBLIC_RELEASE_SHA='));
  assert.ok(linhaCarimbo, 'nao achei a linha do carimbo');

  assert.match(linhaCarimbo, /github\.event\.workflow_run\.head_sha/,
    [
      'O carimbo DEVE comecar por `github.event.workflow_run.head_sha`.',
      '',
      'Num `workflow_run`, `github.sha` e o HEAD do branch padrao NO MOMENTO do run, que pode ja ser',
      'outro commit — exatamente a armadilha 1 documentada no cabecalho deste workflow para o',
      '`checkout`. Aplicada ao carimbo, ela publicaria um commit e DECLARARIA outro, o que e pior que',
      'nao carimbar: o numero teria cara de medicao e o detector confirmaria a mentira.',
    ].join('\n'));

  // E o checkout tem de partir da MESMA origem, senao o que foi construido e o que foi declarado
  // divergem por construcao.
  const linhaRef = yml.split('\n').find((l) => /^\s*ref:/.test(l));
  assert.ok(linhaRef, 'nao achei a linha `ref:` do checkout');
  assert.match(linhaRef, /github\.event\.workflow_run\.head_sha/,
    'o checkout e o carimbo tem de partir do mesmo `workflow_run.head_sha`');
});

// ═══════════════════════════════════════════════════════════════════════════
// 2. A rota
// ═══════════════════════════════════════════════════════════════════════════

test('#2255: a rota le o carimbo do BUILD e nao pode ser cacheada', () => {
  const src = ler(ROTA);
  assert.match(src, /import\.meta\.env\.PUBLIC_RELEASE_SHA/,
    'a rota deve ler PUBLIC_RELEASE_SHA de import.meta.env (substituicao no build)');
  assert.match(src, /Cache-Control['"]?\s*:\s*['"][^'"]*no-store/,
    [
      'A rota DEVE responder com `Cache-Control: no-store`.',
      '',
      'Uma resposta cacheada devolve o SHA do build ANTERIOR, e o detector leria "em dia" durante',
      'exatamente o periodo em que a producao estivesse atrasada — o defeito que esta rota existe',
      'para detectar, confirmado pela propria ferramenta de deteccao.',
    ].join('\n'));
  assert.match(src, /stamped/,
    'a resposta deve distinguir "build sem carimbo" de "nao consegui ler" (campo `stamped`)');
});

// ═══════════════════════════════════════════════════════════════════════════
// 3. O detector, e a assimetria que o torna honesto
// ═══════════════════════════════════════════════════════════════════════════

test('#2255: o heartbeat tem o job que compara o publicado com a main', () => {
  const yml = ler(HEARTBEAT);
  assert.match(yml, /^\s{2}monitor_deploy_lag:/m,
    'o heartbeat deve declarar o job monitor_deploy_lag');
  assert.match(yml, /\/api\/version/,
    'o job deve consultar a rota de proveniencia');
  // PISO NA CARENCIA, e nao no valor do cron. O defeito real e alguem baixar a carencia abaixo do
  // caminho normal de publicacao (`CI Validate` ~14 min + deploy ~2 min = ~16 min): a partir dai o
  // job alerta em TODA fusao, e alerta que quase sempre erra treina a ignorar — que e como o sinal
  // morre. Travar o valor do CRON num teste seria atrito sem proteger nada: a cadencia e decisao de
  // janela de deteccao, e mudar ela nao introduz defeito nenhum por si.
  const grace = Number((yml.match(/GRACE_MINUTES:\s*'?(\d+)'?/) || [])[1]);
  assert.ok(Number.isFinite(grace) && grace >= 30,
    `a carencia deve ser >= 30 min (caminho normal de publicacao e ~16 min); achei ${grace}`);
  assert.match(yml, /GRACE_MINUTES/,
    [
      'O detector DEVE ter carencia.',
      '',
      'Atraso curto e NORMAL: o caminho `CI Validate` (~14 min) + deploy (~2 min) deixa a producao',
      'legitimamente atras da main depois de cada merge. Sem carencia o job alerta em TODO merge, e',
      'alerta que quase sempre erra treina a ignorar — que e como o sinal morre.',
    ].join('\n'));
});

test('#2255: "nao consegui medir" NAO pode fechar o alerta (a mentira na direcao perigosa)', () => {
  const yml = ler(HEARTBEAT);

  const i = yml.indexOf('monitor_deploy_lag:');
  assert.ok(i > 0, 'nao achei o job');
  const job = yml.slice(i);

  // O ramo `unreachable` tem de sair ANTES de qualquer escrita em issue.
  const ramo = job.indexOf("state === 'unreachable'");
  assert.ok(ramo > 0, 'o job deve tratar o estado `unreachable` explicitamente');
  const fecha = job.indexOf("state: 'closed'");
  assert.ok(fecha > 0, 'o job deve fechar o alerta quando recupera');
  assert.ok(ramo < fecha,
    'o tratamento de `unreachable` deve vir antes do fechamento, e retornar cedo');

  // ⚠️ A JANELA TEM DE PARAR NO PROXIMO RAMO. A primeira versao desta asserção fatiava de
  // `unreachable` ate `state: 'closed'`, o que engole o ramo `behind` INTEIRO — e o `behind` tem
  // `return` proprio. Ela passava pelo `return` do VIZINHO e nao podia reprovar o defeito que diz
  // vigiar: descoberto ao injetar o defeito e ver o guard continuar verde (13/09/2026).
  const proximoRamo = job.indexOf("state === 'behind'", ramo);
  assert.ok(proximoRamo > ramo, 'esperava o ramo `behind` depois do `unreachable`');
  const trechoUnreachable = job.slice(ramo, proximoRamo);
  assert.match(trechoUnreachable, /\breturn\b/,
    [
      'O ramo `unreachable` DEVE retornar cedo, sem tocar no alerta.',
      '',
      'Tratar "nao consegui medir" como "esta tudo bem" faz o alerta de atraso sumir sozinho toda vez',
      'que o site oscilar. Site fora do ar e problema de OUTRO monitor; este job so pode concluir a',
      'partir de uma leitura que aconteceu.',
    ].join('\n'));

  // E os tres estados tem de existir como tres, nao como dois.
  for (const estado of ['unreachable', 'behind', 'in_sync']) {
    assert.ok(job.includes(estado), `o job deve distinguir o estado \`${estado}\``);
  }
});
