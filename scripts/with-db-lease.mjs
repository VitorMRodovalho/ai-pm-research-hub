#!/usr/bin/env node
/**
 * #1961 — serializa quem escreve no banco de produção durante a suíte DB-aware.
 *
 * Uso:  node scripts/with-db-lease.mjs -- <comando> [args...]
 *
 * ── Por que um wrapper, e não um preload (`--import`) ──────────────────────────────────
 * Medido em 24/08/2026: `node --test` cria **um processo filho por arquivo de teste**, e um
 * módulo passado em `--import` roda dentro de CADA filho. Sonda com dois arquivos triviais:
 *
 *     PRELOAD pid=862478 ppid=862469 shared=8kgb1w
 *     A       pid=862478 ppid=862469 shared=8kgb1w
 *     PRELOAD pid=862479 ppid=862469 shared=a9r9oh   <- outro pid, outro globalThis
 *     B       pid=862479 ppid=862469 shared=a9r9oh
 *
 * Com os 324 arquivos do balde comportamental, um lease no preload seria adquirido e solto
 * 324 vezes — serializaria arquivo a arquivo e não seguraria a exclusão durante a rodada,
 * que é o ponto. Nem estado em `globalThis` atravessa, então também não há como compartilhar
 * um client Supabase por ali. O wrapper é a única granularidade que corresponde a "uma rodada".
 *
 * ── Por que não `pg_advisory_lock` ────────────────────────────────────────────────────
 * Lock de sessão do Postgres morre com a conexão. Sobre PostgREST cada request pega uma
 * conexão do pool, então o lock seria solto imediatamente (ou ficaria preso numa conexão
 * arbitrária). Daí lease em tabela, com TTL.
 *
 * ── Decisão: falta de lease NÃO reprova ───────────────────────────────────────────────
 * Se o lease não for adquirido dentro do teto de espera, a rodada segue mesmo assim, com
 * aviso alto. Reprovar transformaria contenção em vermelho, que é exatamente o que esta
 * issue existe para eliminar. O aviso é o que permite atribuir um vermelho depois.
 */
import { spawn } from 'node:child_process';
import { hostname } from 'node:os';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const TTL_MINUTES = Number(process.env.DB_LEASE_TTL_MINUTES || 60);
// #1969 — o teto de espera DEPENDE do ambiente, e a razão é orçamento, não gosto.
// Na CI a espera do lease corre DENTRO do `timeout-minutes: 95` do job `validate`, junto com a
// espera da faixa (`wait-for-db-lane`, até 3600s) e o pior `validate` medido (1552s). Com 20 min
// aqui o pior caso ia a 106 min e o job morria por timeout do RUNNER — que, como o próprio
// ci.yml avisa, não imprime a mensagem de teto estourado. Curto na CI cabe: 3600+120+1552 = 88 min.
// E não custa cobertura: `wait-for-db-lane` (#1509) já ordenou os jobs da faixa entre si. O lease
// existe ali para que a sessão LOCAL o enxergue e espere — esse é o eixo que Actions não alcança.
const NA_CI = !!process.env.GITHUB_RUN_ID;
const WAIT_MS = Number(process.env.DB_LEASE_WAIT_MS || (NA_CI ? 120_000 : 20 * 60 * 1000));
const POLL_MS = Number(process.env.DB_LEASE_POLL_MS || 15_000);
const SOURCE = 'test_suite_db_aware';

const argv = process.argv.slice(2);
const sep = argv.indexOf('--');
const cmd = sep === -1 ? argv : argv.slice(sep + 1);
if (cmd.length === 0) {
  console.error('uso: node scripts/with-db-lease.mjs -- <comando> [args...]');
  process.exit(2);
}

/** Identifica o detentor de forma legível para quem for investigar uma espera. */
function holderId() {
  if (process.env.GITHUB_RUN_ID) {
    return `ci:${process.env.GITHUB_WORKFLOW || 'workflow'}:${process.env.GITHUB_RUN_ID}:${process.env.GITHUB_RUN_ATTEMPT || '1'}`;
  }
  return `local:${hostname()}:${process.pid}`;
}
const HOLDER = holderId();

async function rpc(fn, body) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`${fn} -> HTTP ${res.status}: ${(await res.text()).slice(0, 200)}`);
  return res.json();
}

function run() {
  const child = spawn(cmd[0], cmd.slice(1), { stdio: 'inherit' });
  return new Promise((resolve) => {
    child.on('exit', (code, signal) => resolve(signal ? 128 : (code ?? 1)));
    for (const s of ['SIGINT', 'SIGTERM']) process.on(s, () => child.kill(s));
  });
}

async function main() {
  // Sem credenciais a suíte pula os testes de banco: não há o que serializar.
  if (!SUPABASE_URL || !SERVICE_KEY) {
    console.error('[db-lease] sem SUPABASE_URL/SERVICE_ROLE_KEY — nada a serializar, seguindo.');
    process.exit(await run());
  }

  const inicio = Date.now();
  let adquirido = false;
  let ultimoDono = null;

  while (Date.now() - inicio < WAIT_MS) {
    let r;
    try {
      r = await rpc('acquire_test_suite_lease', { p_source: SOURCE, p_holder: HOLDER, p_ttl_minutes: TTL_MINUTES });
    } catch (e) {
      // Indisponibilidade do lease não pode derrubar a suíte: o lease é conveniência, não gate.
      console.error(`[db-lease] falha ao pedir o lease (${e.message}) — seguindo SEM serialização.`);
      break;
    }
    if (r?.acquired) { adquirido = true; break; }
    if (r?.holder !== ultimoDono) {
      ultimoDono = r?.holder;
      console.error(`[db-lease] banco ocupado por "${r?.holder}" até ${r?.expires_at} — esperando (teto ${Math.round(WAIT_MS / 60000)} min).`);
    }
    await new Promise((ok) => setTimeout(ok, POLL_MS));
  }

  if (adquirido) {
    console.error(`[db-lease] lease adquirido por "${HOLDER}" (TTL ${TTL_MINUTES} min).`);
  } else {
    console.error(
      `[db-lease] ⚠️  RODANDO SEM LEASE. Outro escritor está no banco de produção agora ` +
      `(último visto: "${ultimoDono ?? 'desconhecido'}"). Durações e falhas desta rodada NÃO são ` +
      `confiáveis — contenção produz timeout que parece defeito. Ver #1961.`,
    );
  }

  let code = 1;
  try {
    code = await run();
  } finally {
    if (adquirido) {
      try {
        await rpc('release_test_suite_lease', { p_source: SOURCE, p_holder: HOLDER });
        console.error('[db-lease] lease liberado.');
      } catch (e) {
        console.error(`[db-lease] não consegui liberar o lease (${e.message}); o TTL de ${TTL_MINUTES} min o expira.`);
      }
    }
  }
  process.exit(code);
}

main().catch((e) => {
  console.error(`[db-lease] erro inesperado: ${e?.stack || e}`);
  process.exit(1);
});
