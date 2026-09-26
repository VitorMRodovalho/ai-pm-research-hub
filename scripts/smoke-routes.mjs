// Smoke de rotas: sobe o `astro dev` e exerce as rotas publicas e as telas admin.
//
// #1725 — antes, um unico `timeout-minutes: 2` no workflow cobria DUAS coisas com variancia muito
// diferente: subir o servidor e exercer as rotas. Medido em 10 e 11/08/2026, o boot ficou estavel em
// ~18s (com duas reotimizacoes do vite nas duas vezes), ou seja ~15% do orcamento consumido antes da
// primeira requisicao. Quando o passo morria, morria SEM nenhuma assercao de rota falhar, e o log
// nao dizia quem tinha gasto o tempo.
//
// Agora cada coisa tem orcamento proprio e e reportada:
//   - BOOT_TIMEOUT_MS   quanto o servidor pode levar para responder a primeira vez
//   - ASSERT_TIMEOUT_MS quanto TODAS as assercoes podem levar somadas
//   - REQ_TIMEOUT_MS    quanto UMA requisicao pode levar (antes nao havia: uma rota pendurada
//                       consumia o orcamento inteiro e o erro saia como timeout do passo)
//
// O teto do workflow continua existindo, mas como backstop: estes tres estouram antes e dizem
// exatamente o que aconteceu.
//
// E cada rota se anuncia no log ANTES de ser exercida, para o caso em que o backstop mata o
// processo: ai nenhum dos tres tetos chega a falar, e a ultima linha impressa e a unica pista.

import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { createInterface } from 'node:readline';
import {
  createDevServerWatch,
  assertContentWithResamples,
  SINGLETON_BLOCKED,
} from '../tests/helpers/dev-server-watch.mjs';

// #2485: o destino do /hackathon mora em src/lib/canonical.ts, que e TypeScript; este script roda em
// Node puro, entao le a constante do TEXTO e reprova se ela sumir, em vez de afirmar contra vazio.
const HACKATHON_HOST = readFileSync(new URL('../src/lib/canonical.ts', import.meta.url), 'utf8')
  .match(/export const HACKATHON_HOST\s*=\s*"([^"]+)"/)?.[1];
if (!HACKATHON_HOST) throw new Error('[smoke] HACKATHON_HOST nao encontrado em src/lib/canonical.ts');
const HACKATHON_URL = `https://${HACKATHON_HOST}/`;

const PORT = Number(process.env.SMOKE_PORT || (4300 + Math.floor(Math.random() * 400)));
const BASE = `http://127.0.0.1:${PORT}`;

const BOOT_TIMEOUT_MS = Number(process.env.SMOKE_BOOT_TIMEOUT_MS || 90_000);
const ASSERT_TIMEOUT_MS = Number(process.env.SMOKE_ASSERT_TIMEOUT_MS || 120_000);
const REQ_TIMEOUT_MS = Number(process.env.SMOKE_REQ_TIMEOUT_MS || 15_000);
// Acima disto a rota ganha uma linha de tempo no log. `/` foi medida em 7,6s em 10/08.
const SLOW_ROUTE_MS = Number(process.env.SMOKE_SLOW_ROUTE_MS || 2_000);
// #2308 — quantas amostras A MAIS de uma rota cujo corpo veio sem o marcador. A asercao NAO e
// afrouxada: cada amostra tem de ACHAR o marcador. Isto so tira a sensibilidade a UMA amostra,
// e so faz sentido porque o servidor segue vivo (medido: 17 excecoes e as 28 rotas em 2xx).
const CONTENT_RESAMPLES = Number(process.env.SMOKE_CONTENT_RESAMPLES || 2);
const RESAMPLE_DELAY_MS = Number(process.env.SMOKE_RESAMPLE_DELAY_MS || 750);
// Carencia entre o SIGTERM e o SIGKILL no grupo do dev server.
const GRACE_MS = Number(process.env.SMOKE_GRACE_MS || 2_000);

// Le a saida do dev server para que a falha possa NOMEAR a causa. Ver #2308 e o cabecalho do
// helper: a unidade de atribuicao e a janela da PROPRIA requisicao, nao a presenca no run.
const watch = createDevServerWatch();

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

const ms = (t) => `${((Date.now() - t) / 1000).toFixed(1)}s`;

/**
 * fetch com teto proprio: uma rota pendurada falha COMO rota, nao como timeout do passo.
 *
 * O log sai ANTES da requisicao de proposito. O teto por requisicao ja nomeia a rota quando ELE
 * dispara, mas o backstop do workflow mata o processo sem passar por aqui — e nesse caminho a
 * ultima linha impressa e a unica pista de onde o passo parou. Era exatamente o que faltava nos
 * dois vermelhos de 10 e 11/08: log do boot, depois silencio ate o `##[error]`.
 */
async function req(path, init = {}) {
  console.log(`[smoke] -> ${path}`);
  const iniciada = Date.now();
  try {
    const res = await fetch(`${BASE}${path}`, { ...init, signal: AbortSignal.timeout(REQ_TIMEOUT_MS) });
    const terminada = Date.now();
    const gasto = terminada - iniciada;
    // So as lentas ganham segunda linha: o sinal util e a rota que destoa, nao as 44 que voam.
    if (gasto > SLOW_ROUTE_MS) {
      console.log(`[smoke]    ${path} respondeu em ${(gasto / 1000).toFixed(1)}s (lenta)`);
    }
    // A janela e o que permite atribuir (ou NAO atribuir) a excecao do dev server a ESTA resposta.
    return { res, inicio: iniciada, fim: terminada };
  } catch (err) {
    if (err?.name === 'TimeoutError' || err?.name === 'AbortError') {
      throw new Error(`${path} nao respondeu em ${REQ_TIMEOUT_MS}ms (rota pendurada)`);
    }
    throw new Error(`${path} falhou na requisicao: ${err?.message || err}`);
  }
}

async function waitForServer() {
  const startedAt = Date.now();
  let ultimoErro = '(nenhuma resposta)';
  while (Date.now() - startedAt < BOOT_TIMEOUT_MS) {
    // #2308 — fast-fail do SINGLETON. O `astro dev` e singleton POR PROJETO: com outro servidor
    // vivo ele recusa e sai, e sem isto o laco abaixo gasta os 90s inteiros para entregar "o
    // servidor nao subiu", que e um diagnostico FALSO — ele nao tentou subir, foi recusado.
    // E a mesma familia do defeito desta issue (a mensagem acusa a coisa errada), e foi medida
    // aqui em 15/09: um `astro dev --port 4488` orfao desde 14/09 09:22 bloqueou o smoke local.
    const bloqueado = watch.primeiro(SINGLETON_BLOCKED);
    if (bloqueado) {
      throw new Error(
        `[smoke] o \`astro dev\` foi RECUSADO, nao esta lento: ja existe outro servidor deste\n` +
        `  projeto vivo. Ele disse: ${bloqueado.detail}\n` +
        '  Isto nao e boot nem rota (#2308). Encerre o servidor antigo (`npx astro dev stop`) e\n' +
        '  rode de novo; esperar os 90s do teto so trocaria esta frase por uma errada.',
      );
    }
    try {
      const res = await fetch(`${BASE}/`, {
        redirect: 'manual',
        signal: AbortSignal.timeout(REQ_TIMEOUT_MS),
      });
      if (res.status >= 200 && res.status < 500) {
        console.log(`[smoke] servidor pronto em ${ms(startedAt)}`);
        return;
      }
      ultimoErro = `status ${res.status}`;
    } catch (err) {
      ultimoErro = err?.message || String(err);
    }
    await sleep(500);
  }
  // A mensagem nomeia o BOOT: sem isso, "timed out" nao distingue servidor lento de rota quebrada.
  throw new Error(
    `[smoke] o servidor nao subiu em ${BOOT_TIMEOUT_MS}ms (ultimo erro: ${ultimoErro}). ` +
      'Isto e boot, nao rota: subir SMOKE_BOOT_TIMEOUT_MS ou investigar o dev server.',
  );
}

async function assertOk(path) {
  const { res } = await req(path);
  if (!res.ok) {
    throw new Error(`Expected ${path} to return 2xx, got ${res.status}`);
  }
}

async function assertRedirect(path, expectedLocation) {
  const { res } = await req(path, { redirect: 'manual' });
  if (!(res.status >= 300 && res.status < 400)) {
    throw new Error(`Expected ${path} to redirect, got ${res.status}`);
  }
  const location = res.headers.get('location');
  if (location !== expectedLocation) {
    throw new Error(`Expected ${path} redirect to ${expectedLocation}, got ${location || '(none)'}`);
  }
}

/**
 * #2308 — a assercao de CONTEUDO, que e a unica que le o corpo, e por isso a unica que sofre com a
 * pagina que volta 2xx sem ser a pagina.
 *
 * Duas coisas, e a ordem importa:
 *
 *   1. RE-AMOSTRAR. Medido em 15/09 no job 104185959684: a excecao de resolucao do BaseLayout NAO
 *      mata o dev server (ela apareceu 17 vezes e as 28 rotas de `assertOk` responderam 2xx do
 *      comeco ao fim). Entao pedir a rota de novo e uma SEGUNDA AMOSTRA de um servidor vivo, nao
 *      um afrouxamento: cada amostra tem de achar o marcador por merito proprio. Um marcador
 *      genuinamente ausente da pagina falha em TODAS as amostras — e o teste D do guard injeta
 *      exatamente esse defeito para provar que ainda reprova.
 *
 *   2. CLASSIFICAR. Se nenhuma amostra trouxe o marcador, a mensagem diz o que foi MEDIDO em vez
 *      de acusar a rota. Ver `explainContentFailure`: ela tem tres saidas, e "nao consegui ler a
 *      saida do dev server" e uma delas, porque nao-medido nao pode virar medido-zero.
 *
 * ⚠️ E a re-amostragem que SALVA e anunciada em voz alta, com token estavel. Um verde que so
 * aconteceu na segunda tentativa precisa ser CONTAVEL depois; senao a intermitencia desaparece do
 * registro e a #2308 volta a ser descoberta do zero, como ja aconteceu 78 vezes com o alerta.
 */
async function assertContains(path, fragment) {
  await assertContentWithResamples({
    path,
    fragment,
    watch,
    tentativas: 1 + Math.max(0, CONTENT_RESAMPLES),
    pedir: () => req(path),
    esperar: () => sleep(RESAMPLE_DELAY_MS),
    log: (linha) => console.log(linha),
  });
}

async function assercoes() {
  await assertOk('/');
  await assertOk('/attendance');
  await assertOk('/gamification');
  await assertOk('/artifacts');
  await assertOk('/profile');
  await assertOk('/help');
  await assertOk('/admin');
  await assertOk('/admin/curatorship');
  await assertOk('/admin/analytics');
  await assertOk('/admin/portfolio');
  await assertOk('/admin/cycle-report');
  await assertOk('/admin/governance-v2');
  await assertOk('/admin/comms-ops');
  await assertOk('/admin/selection');
  await assertOk('/admin/comms');
  await assertOk('/admin/webinars');
  await assertOk('/admin/partnerships');
  await assertOk('/admin/sustainability');
  await assertOk('/admin/chapter-report');
  await assertOk('/notifications');
  await assertOk('/publications');
  await assertOk('/projects');
  await assertOk('/en');
  await assertOk('/es');

  await assertOk('/teams');
  await assertOk('/workspace');
  await assertOk('/en/workspace');
  await assertOk('/es/workspace');
  await assertContains('/admin/selection', 'id="sel-denied"');
  await assertContains('/admin/analytics', 'id="analytics-denied"');
  await assertContains('/admin/curatorship', 'id="cur-denied"');
  await assertContains('/admin/comms', 'id="comms-denied"');
  await assertContains('/admin/portfolio', 'id="portfolio-denied"');
  await assertContains('/admin/governance-v2', 'id="boardgov-denied"');
  await assertContains('/admin/comms-ops', 'id="commsops-denied"');
  await assertContains('/admin/partnerships', 'id="partnerships-denied"');
  await assertContains('/admin/sustainability', 'id="sust-denied"');
  await assertContains('/admin/chapter-report', 'id="chr-denied"');
  await assertContains('/webinars', 'Webinars'); // public SSR page (GC-160)
  await assertContains('/tribe/1', 'id="tribe-denied"');
  await assertRedirect('/rank', '/gamification');
  await assertRedirect('/ranks', '/gamification');
  // #2485: a entrada do hackathon leva ao site externo, nos tres locales.
  await assertRedirect('/hackathon', HACKATHON_URL);
  await assertRedirect('/en/hackathon', HACKATHON_URL);
  await assertRedirect('/es/hackathon', HACKATHON_URL);
}

async function run() {
  // `detached` poe o filho num grupo de processos PROPRIO, para que o kill abaixo alcance a arvore
  // inteira. Sem isso, `dev.kill()` mata so o `npm`, e o `astro dev` que ele criou sobrevive
  // reparentado ao init — medido ao exercer este script, e valia tanto para o `finally` quanto para
  // o handler de sinal. Um servidor orfao segura a porta e o stdout do passo.
  // #2308 — `stdio: 'inherit'` entrega a saida direto ao passo e NAO deixa ninguem classifica-la.
  // Era por isso que o vermelho chegava como "Expected /admin/<rota> to contain ..." com a excecao
  // do vite impressa um segundo antes, no mesmo log, sem ninguem cruzar as duas. Agora a saida e
  // LIDA e re-emitida byte a byte (o log do passo continua identico ao que era) e cada linha passa
  // pelo classificador. A irma `tests/browser-guards.test.mjs` ja fazia isto desde a #2279.
  const dev = spawn(
    'npm',
    ['run', 'dev', '--', '--host', '127.0.0.1', '--port', String(PORT)],
    { stdio: ['ignore', 'pipe', 'pipe'], shell: false, detached: true }
  );

  for (const [fluxo, saida] of [[dev.stdout, process.stdout], [dev.stderr, process.stderr]]) {
    if (!fluxo) continue;
    createInterface({ input: fluxo, crlfDelay: Infinity }).on('line', (linha) => {
      saida.write(`${linha}\n`); // o passo continua vendo TUDO o que via com `inherit`
      watch.observe(linha);
    });
  }

  const sinalizarGrupo = (sinal) => {
    try {
      process.kill(-dev.pid, sinal); // negativo = o GRUPO, nao so o npm
      return true;
    } catch {
      return false; // grupo ja encerrado
    }
  };

  // Medido ao exercer o script: com SIGTERM no grupo, o `npm` morre e o `astro dev` NAO — ele fica
  // vivo, reparentado ao init, segurando a porta e o stdout. Educado nao basta: escala-se.
  const matarServidor = async () => {
    if (!sinalizarGrupo('SIGTERM')) return;
    await sleep(GRACE_MS);
    sinalizarGrupo('SIGKILL');
  };

  // O `finally` abaixo cobre falha e sucesso, mas NAO cobre o passo ser morto por fora — e esse e
  // justamente o caminho do backstop do workflow. Sem isto o `astro dev` sobrevive ao pai: medido
  // ao exercer este script (o filho ficou de pe segurando o stdout depois do `timeout`).
  const encerrar = (codigo) => () => {
    // O `await` aqui e o que da tempo ao SIGKILL: sair na hora deixaria o orfao de pe outra vez.
    matarServidor().finally(() => process.exit(codigo));
  };
  process.once('SIGTERM', encerrar(143));
  process.once('SIGINT', encerrar(130));

  try {
    await waitForServer();

    // Orcamento PROPRIO das assercoes: estourar aqui e um diagnostico ("as rotas nao terminaram"),
    // enquanto estourar no teto do workflow nao diz nada sobre qual das duas fases travou.
    const t0 = Date.now();
    let timer;
    const teto = new Promise((_, reject) => {
      timer = setTimeout(
        () => reject(new Error(
          `[smoke] as assercoes nao terminaram em ${ASSERT_TIMEOUT_MS}ms. ` +
            'Isto e rota, nao boot: o servidor ja tinha respondido.',
        )),
        ASSERT_TIMEOUT_MS,
      );
    });
    try {
      await Promise.race([assercoes(), teto]);
    } finally {
      clearTimeout(timer);
    }

    console.log(`[smoke] Route smoke tests passed (assercoes em ${ms(t0)}).`);
  } finally {
    await matarServidor();
  }
}

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
