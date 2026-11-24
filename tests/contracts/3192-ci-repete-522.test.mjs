/**
 * #3192: um 522 isolado da API do Supabase nao reprova mais o `validate`.
 *
 * Medido em 24/11/2026 nos edge_logs do projeto: a Cloudflare devolve HTTP 522 quando nao consegue
 * abrir conexao com a origem, em request isolado, com ~19,5 s de espera, em qualquer endpoint e sem
 * relacao com a carga. Tres runs do `validate` ficaram vermelhos por um unico 522. A recusa acontece
 * antes de o request chegar a origem, entao repetir nao duplica escrita.
 *
 * O que este guard fixa, cada asserção com a mutacao que a derruba (pacote da lane):
 *   G1  um 522 e repetido, e a chamada devolve o sucesso que vier depois (dbFetch e embrulho global).
 *   G2  nenhum outro status e repetido: 400, 500, 502, 503 e 504 sem PGRST003, 520, 521, 523, 524.
 *   G3  o embrulho global so age nos hosts do Supabase; outro host passa direto.
 *   G4  todo `node --test` da suite carrega o preload, e o preload instala o embrulho de fato.
 *   G5  o 522 repetido entra no orcamento do #1869 e o estoura.
 *   G6  o run-suite zera o orcamento no inicio e imprime, no fim, quantas chamadas foram repetidas por 522.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, appendFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

const ARQUIVO_DO_TESTE = join(tmpdir(), `db-fetch-budget-TESTE-3192-${process.pid}.log`);
process.env.DB_FETCH_BUDGET_FILE = ARQUIVO_DO_TESTE;

const {
  dbFetch, instalarNoFetchGlobal, estadoDoOrcamento, resetarOrcamento, resumoDoOrcamento,
  ORCAMENTO_SATURACAO_MS, TENTATIVAS,
} = await import('../helpers/db-fetch.mjs');

const HOST = 'https://guard-3192.supabase.co';
const PRELOAD = './tests/helpers/db-fetch-preload.mjs';
const resposta = (status, corpo = '{}') => new Response(corpo, { status });

/** Roda `fn` com o `fetch` de baixo trocado por `mock` e o embrulho global instalado por cima. */
async function comEmbrulho(mock, fn) {
  const original = globalThis.fetch;
  globalThis.fetch = mock;
  instalarNoFetchGlobal();
  try { return await fn(); } finally { globalThis.fetch = original; }
}

/** Roda `fn` com o `fetch` trocado por `mock`, sem embrulho: o caminho do `dbFetch` explicito. */
async function semEmbrulho(mock, fn) {
  const original = globalThis.fetch;
  globalThis.fetch = mock;
  try { return await fn(); } finally { globalThis.fetch = original; }
}

const umaVez522 = () => {
  const s = { n: 0 };
  s.mock = async () => (++s.n === 1 ? resposta(522, 'origin unreachable') : resposta(200, '{"ok":true}'));
  return s;
};

test('G1: 522 e repetido, pelo dbFetch e pelo fetch global do Supabase', async () => {
  resetarOrcamento();
  const a = umaVez522();
  const r1 = await semEmbrulho(a.mock, () => dbFetch(`${HOST}/rest/v1/x`, { method: 'POST', body: '{}' }));
  assert.equal(r1.status, 200, 'o dbFetch tem de repetir o 522 e devolver o sucesso seguinte');
  assert.equal(a.n, 2, 'uma repeticao basta quando a segunda responde');

  const b = umaVez522();
  const r2 = await comEmbrulho(b.mock, () => fetch(`${HOST}/rest/v1/rpc/can`, { method: 'POST', body: '{}' }));
  assert.equal(r2.status, 200, 'o fetch global (createClient) tem de repetir o 522');
  assert.equal(b.n, 2);

  // O createClient do supabase-js resolve o fetch global a cada chamada: o embrulho o alcanca sem
  // nenhuma mudanca no teste que o usa.
  const { createClient } = await import('@supabase/supabase-js');
  const d = umaVez522();
  const { data, error } = await comEmbrulho(d.mock, () =>
    createClient(HOST, 'chave-falsa', { auth: { persistSession: false } }).rpc('can', {}));
  assert.equal(error, null, `o createClient recebeu o 522 em vez da repeticao: ${JSON.stringify(error)}`);
  assert.deepEqual(data, { ok: true });
  assert.equal(d.n, 2, 'o createClient tem de passar pela repeticao do embrulho');

  const c = { n: 0 };
  const persistente = async () => { c.n++; return resposta(522); };
  const r3 = await comEmbrulho(persistente, () => fetch(`${HOST}/rest/v1/x`));
  assert.equal(r3.status, 522, '522 persistente continua vermelho: a ultima recusa e devolvida');
  assert.equal(c.n, TENTATIVAS, `tenta ${TENTATIVAS} vezes e para`);
  resetarOrcamento();
});

test('G2: nenhum outro status e repetido', async () => {
  resetarOrcamento();
  for (const status of [400, 401, 404, 409, 500, 502, 503, 504, 520, 521, 523, 524]) {
    for (const via of ['dbFetch', 'global']) {
      const s = { n: 0 };
      const mock = async () => { s.n++; return resposta(status, '{"message":"x"}'); };
      const res = via === 'dbFetch'
        ? await semEmbrulho(mock, () => dbFetch(`${HOST}/rest/v1/x`, { method: 'POST' }))
        : await comEmbrulho(mock, () => fetch(`${HOST}/rest/v1/x`, { method: 'POST' }));
      assert.equal(res.status, status);
      assert.equal(s.n, 1, `${status} via ${via} foi repetido: so PGRST003 e 522 sao retentaveis`);
    }
  }
  assert.equal(estadoDoOrcamento().repeticoesPor522, 0);
});

test('G3: o embrulho global nao toca host fora do Supabase', async () => {
  resetarOrcamento();
  const s = { n: 0 };
  const mock = async () => { s.n++; return resposta(522); };
  const res = await comEmbrulho(mock, () => fetch('https://exemplo.invalid/x'));
  assert.equal(res.status, 522);
  assert.equal(s.n, 1, 'outro host passa direto ao fetch original, sem repeticao');
});

/** Todas as invocacoes de `node ... --test` do package.json, dos workflows e do run-suite. */
function invocacoesDoNodeTest() {
  const achadas = [];
  const pkg = JSON.parse(readFileSync('package.json', 'utf8'));
  for (const [nome, cmd] of Object.entries(pkg.scripts)) {
    for (const m of cmd.matchAll(/\bnode\b[^&|;]*?--test\b/g)) achadas.push([`package.json:${nome}`, m[0]]);
  }
  for (const f of readdirSync('.github/workflows')) {
    const y = readFileSync(`.github/workflows/${f}`, 'utf8');
    for (const m of y.matchAll(/^[^#\n]*\bnode\b[^\n&|;]*?--test\b/gm)) achadas.push([f, m[0]]);
  }
  const runner = readFileSync('scripts/run-suite.mjs', 'utf8');
  for (const b of ['structural', 'behavioural', 'contracts']) {
    const m = runner.match(new RegExp(`\\n  ${b}: \\[([^\\]]*)\\]`));
    achadas.push([`run-suite:${b}`, m ? m[1] : '<balde ausente>']);
  }
  return achadas;
}

test('G4: todo `node --test` da suite carrega o preload, e o preload instala o embrulho', () => {
  const inv = invocacoesDoNodeTest();
  assert.ok(inv.length >= 7, `a enumeracao achou so ${inv.length}: o instrumento quebrou`);
  const sem = inv.filter(([, cmd]) => !(/--import['",\s]+\.\/tests\/helpers\/db-fetch-preload\.mjs/.test(cmd)
    && cmd.indexOf('db-fetch-preload') < cmd.indexOf('--test')));
  assert.deepEqual(sem, [], 'estas invocacoes rodam testes sem a repeticao do 522 (#3192)');

  const probe = 'const f=globalThis.fetch; process.stdout.write(String(f !== undefined && Object.getOwnPropertySymbols(f).some(s => s.description === "nucleo.db-fetch.embrulho")))';
  const com = spawnSync(process.execPath, ['--import', PRELOAD, '-e', probe], { encoding: 'utf8' });
  const semPreload = spawnSync(process.execPath, ['-e', probe], { encoding: 'utf8' });
  assert.equal(com.stdout, 'true', `com o preload o fetch global tem de estar embrulhado. stderr: ${com.stderr}`);
  assert.equal(semPreload.stdout, 'false', 'controle: sem o preload nao ha embrulho (o probe sabe dizer nao)');
});

test('G5: o 522 repetido entra no orcamento do #1869 e o estoura', async () => {
  resetarOrcamento();
  const a = umaVez522();
  await comEmbrulho(a.mock, () => fetch(`${HOST}/rest/v1/x`));
  const e = estadoDoOrcamento();
  assert.equal(e.repeticoesPor522, 1, 'o 522 repetido tem de ser contado');
  assert.equal(e.eventosDeSaturacao, 0, 'e nao como saturacao de pool');
  assert.equal(e.gastoTotalMs, e.gastoEm522Ms + e.gastoEmSaturacaoMs);

  resetarOrcamento();
  appendFileSync(ARQUIVO_DO_TESTE, `${ORCAMENTO_SATURACAO_MS + 1} 522\n`);
  assert.equal(estadoDoOrcamento().estourado, true, 'tempo perdido em 522 estoura o orcamento');
  let tocou = false;
  await assert.rejects(
    () => semEmbrulho(async () => { tocou = true; return resposta(200); }, () => dbFetch(`${HOST}/x`)),
    (err) => /1 foram recusadas com HTTP 522/.test(err.message),
  );
  assert.equal(tocou, false);
  resetarOrcamento();
});

test('G6: o run-suite zera o orcamento e o resumo diz quantas chamadas foram repetidas por 522', () => {
  resetarOrcamento();
  appendFileSync(ARQUIVO_DO_TESTE, '19500 522\n19400 522\n61000\n');
  assert.match(resumoDoOrcamento(), /\b2 chamada\(s\) repetida\(s\) por HTTP 522 \(38\.9 s perdidos\), 1 por saturacao/);
  resetarOrcamento();

  const runner = readFileSync('scripts/run-suite.mjs', 'utf8').replace(/^\s*\/\/.*$/gm, '');
  const antesDoSpawn = runner.slice(0, runner.indexOf('spawn(cmd'));
  assert.match(antesDoSpawn, /resetarOrcamento\(\);\s*const \[cmd, \.\.\.args\]/, 'o orcamento zera antes de a corrida comecar');
  const noFim = (runner.match(/child\.on\('exit',[\s\S]*?process\.exit\(/) || [''])[0];
  assert.match(noFim, /const resumo = `[^`]*\$\{resumoDoOrcamento\(\)\}`;\s*console\.error\(resumo\);/,
    'ao terminar, o run-suite imprime o resumo do orcamento');
  assert.match(noFim, /appendFileSync\(process\.env\.GITHUB_STEP_SUMMARY, `\$\{resumo\}/, 'e o leva ao resumo do job');
});
