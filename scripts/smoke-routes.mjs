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

const PORT = Number(process.env.SMOKE_PORT || (4300 + Math.floor(Math.random() * 400)));
const BASE = `http://127.0.0.1:${PORT}`;

const BOOT_TIMEOUT_MS = Number(process.env.SMOKE_BOOT_TIMEOUT_MS || 90_000);
const ASSERT_TIMEOUT_MS = Number(process.env.SMOKE_ASSERT_TIMEOUT_MS || 120_000);
const REQ_TIMEOUT_MS = Number(process.env.SMOKE_REQ_TIMEOUT_MS || 15_000);
// Acima disto a rota ganha uma linha de tempo no log. `/` foi medida em 7,6s em 10/08.
const SLOW_ROUTE_MS = Number(process.env.SMOKE_SLOW_ROUTE_MS || 2_000);
// Carencia entre o SIGTERM e o SIGKILL no grupo do dev server.
const GRACE_MS = Number(process.env.SMOKE_GRACE_MS || 2_000);

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
    const gasto = Date.now() - iniciada;
    // So as lentas ganham segunda linha: o sinal util e a rota que destoa, nao as 44 que voam.
    if (gasto > SLOW_ROUTE_MS) {
      console.log(`[smoke]    ${path} respondeu em ${(gasto / 1000).toFixed(1)}s (lenta)`);
    }
    return res;
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
  const res = await req(path);
  if (!res.ok) {
    throw new Error(`Expected ${path} to return 2xx, got ${res.status}`);
  }
}

async function assertRedirect(path, expectedLocation) {
  const res = await req(path, { redirect: 'manual' });
  if (!(res.status >= 300 && res.status < 400)) {
    throw new Error(`Expected ${path} to redirect, got ${res.status}`);
  }
  const location = res.headers.get('location');
  if (location !== expectedLocation) {
    throw new Error(`Expected ${path} redirect to ${expectedLocation}, got ${location || '(none)'}`);
  }
}

async function assertContains(path, fragment) {
  const res = await req(path);
  if (!res.ok) {
    throw new Error(`Expected ${path} to return 2xx for content check, got ${res.status}`);
  }
  const body = await res.text();
  if (!body.includes(fragment)) {
    throw new Error(`Expected ${path} to contain "${fragment}"`);
  }
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
}

async function run() {
  // `detached` poe o filho num grupo de processos PROPRIO, para que o kill abaixo alcance a arvore
  // inteira. Sem isso, `dev.kill()` mata so o `npm`, e o `astro dev` que ele criou sobrevive
  // reparentado ao init — medido ao exercer este script, e valia tanto para o `finally` quanto para
  // o handler de sinal. Um servidor orfao segura a porta e o stdout do passo.
  const dev = spawn(
    'npm',
    ['run', 'dev', '--', '--host', '127.0.0.1', '--port', String(PORT)],
    { stdio: 'inherit', shell: false, detached: true }
  );

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
