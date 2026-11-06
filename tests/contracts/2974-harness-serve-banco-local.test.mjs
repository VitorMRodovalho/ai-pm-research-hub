/**
 * #2974: os harnesses que sobem o `astro dev` no CI só falam com um banco local.
 *
 * O @astrojs/cloudflare sobrescreve o ambiente do processo com as [vars] do wrangler.toml, que trazem o
 * PUBLIC_SUPABASE_URL de produção, e o .dev.vars ou o .env ganham dessas [vars]. Um PUBLIC_SUPABASE_URL falso no env
 * do passo não chega à página. Por isso há duas peças:
 *   1. O CI escreve um .dev.vars com a URL e a chave falsas antes de cada passo que sobe o servidor.
 *   2. browser-guards e smoke-routes leem o valor que o dev server SERVE (tests/helpers/served-db-url.mjs) antes de
 *      qualquer página, e recusam com saída 3 ("não medido") se o host não for 127.0.0.1 ou localhost. O retry do
 *      browser_guards não repete uma recusa.
 *
 * A · a decisão, sobre a primeira linha do módulo e o define:vars transcritos do dev server, mais a URL do wrangler.toml
 * B · a ordem dentro dos dois harnesses, recortada do bloco que decide, com os comentários mascarados
 * C · o retry, EXERCIDO com um npm falso que sai com 3, e o controle que sai com 1
 * D · o ci.yml, lido como YAML: os passos que sobem o servidor saem do arquivo, e o passo do .dev.vars, EXECUTADO num
 *     diretório temporário, escreve um valor que a própria decisão chama de local
 * E · o .gitignore, exercido pelo git check-ignore
 *
 * Offline: node, bash e git. O efeito com o dev server de verdade fica fora daqui: a árvore com o .env de produção
 * recusa com 3 antes de abrir o navegador, e a árvore com o .dev.vars falso roda.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { load } from 'js-yaml';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';
import {
  CAMINHO_SEM_SSR,
  ILEGIVEL,
  LOCAL,
  NAO_LOCAL,
  SAIDA_NAO_MEDIDO,
  avaliarModuloCliente,
  avaliarUrl,
  conferirSsr,
  mensagemNaoMedido,
} from '../helpers/served-db-url.mjs';

const ROOT = process.cwd();
const ler = (rel) => readFileSync(resolve(ROOT, rel), 'utf8');

// Transcrição fiel do que o dev server serviu com o .dev.vars falso: a 1ª linha de /src/lib/supabase.ts transformado
// pelo Vite (o objeto do import.meta.env) e a linha que USA o valor, que não pode contar como segunda ocorrência.
const VALOR_LOCAL = 'http://127.0.0.1:9999';
const MODULO_SERVIDO =
  'import.meta.env = {"ASSETS_PREFIX": undefined, "BASE_URL": "/", "DEV": true, "MODE": "development", "PROD": false, ' +
  '"PUBLIC_SUPABASE_ANON_KEY": "mock-key-for-build", "PUBLIC_SUPABASE_URL": "http://127.0.0.1:9999", ' +
  '"SITE": "https://nucleoia.org", "SSR": false};import { createClient } from ' +
  '"/node_modules/.vite/deps/@supabase_supabase-js.js?v=c409ea7d";\n' +
  '\tconst envUrl = (import.meta.env.PUBLIC_SUPABASE_URL || _runtimeSupabaseConfig.url || ' +
  'readRuntimePublicEnv("__PUBLIC_SUPABASE_URL") || FALLBACK_SUPABASE_URL).trim();\n';
// E o define:vars do Nav no HTML da mesma rodada.
const SSR_SERVIDO =
  '<script>(function(){const NAV_PUBLIC_SUPABASE_URL = "http://127.0.0.1:9999";\n' +
  "  window.__PUBLIC_SUPABASE_URL = NAV_PUBLIC_SUPABASE_URL || '';\n";

function trocar(texto, de, para) {
  assert.equal(texto.split(de).length, 2, `controle: o trecho a trocar tem de ocorrer uma vez (${de})`);
  return texto.replace(de, para);
}
const moduloCom = (v) => trocar(MODULO_SERVIDO, `"PUBLIC_SUPABASE_URL": "${VALOR_LOCAL}"`, `"PUBLIC_SUPABASE_URL": ${JSON.stringify(v)}`);
const ssrCom = (v) => trocar(SSR_SERVIDO, `NAV_PUBLIC_SUPABASE_URL = "${VALOR_LOCAL}"`, `NAV_PUBLIC_SUPABASE_URL = ${JSON.stringify(v)}`);

// A URL de produção sai do próprio wrangler.toml, que é de onde o dev server a tira.
const URL_DO_WRANGLER = ler('wrangler.toml').match(/^PUBLIC_SUPABASE_URL\s*=\s*"([^"]+)"/m)?.[1];

// ═══════════════════════════════════════════════════════════════════════════
test('A1 · o valor local servido segue', () => {
  const r = avaliarModuloCliente(MODULO_SERVIDO);
  assert.equal(r.estado, LOCAL, r.motivo);
  assert.equal(r.valor, VALOR_LOCAL);
  assert.equal(avaliarUrl('http://localhost:54321').estado, LOCAL, 'o localhost do playwright.config.ts é local');
});

test('A2 · a URL de produção do wrangler.toml recusa', () => {
  assert.ok(URL_DO_WRANGLER, 'controle: o wrangler.toml perdeu o PUBLIC_SUPABASE_URL; este teste não teria o que recusar');
  const r = avaliarModuloCliente(moduloCom(URL_DO_WRANGLER));
  assert.equal(r.estado, NAO_LOCAL);
  assert.equal(r.host, new URL(URL_DO_WRANGLER).hostname);
  assert.match(mensagemNaoMedido('browser-guards', r), /^browser-guards: não medido: o dev server serve PUBLIC_SUPABASE_URL em \S+, que não é local\./);
});

test('A3 · o host sai de new URL: o que só começa com 127.0.0.1 ou localhost recusa', () => {
  for (const v of ['http://127.0.0.1.exemplo.com', 'http://localhost.exemplo.com:9999', 'https://exemplo.com/?h=127.0.0.1']) {
    assert.equal(avaliarModuloCliente(moduloCom(v)).estado, NAO_LOCAL, v);
  }
});

test('A4 · vazio, ausente, duplicado ou fora de URL é ilegível, e ilegível também recusa', () => {
  assert.equal(avaliarModuloCliente(moduloCom('')).estado, ILEGIVEL, 'vazio cai no fallback de produção');
  assert.equal(avaliarModuloCliente(moduloCom('   ')).estado, ILEGIVEL);
  assert.equal(avaliarModuloCliente(moduloCom('nao-e-url')).estado, ILEGIVEL);
  assert.equal(avaliarModuloCliente('export const x = 1;').estado, ILEGIVEL, 'módulo sem o valor');
  assert.equal(avaliarModuloCliente('').estado, ILEGIVEL, 'resposta vazia');
  const duplicado = `${MODULO_SERVIDO}{"PUBLIC_SUPABASE_URL": "${URL_DO_WRANGLER}"}`;
  assert.equal(avaliarModuloCliente(duplicado).estado, ILEGIVEL, 'duas ocorrências: a guarda não escolhe uma');
  assert.notEqual(ILEGIVEL, LOCAL);
});

test('A5 · o SSR tem de servir o mesmo valor que o cliente recebeu, e local', () => {
  assert.equal(conferirSsr(SSR_SERVIDO, VALOR_LOCAL).estado, LOCAL);
  assert.equal(conferirSsr(ssrCom(URL_DO_WRANGLER), VALOR_LOCAL).estado, ILEGIVEL, 'SSR diferente do cliente');
  assert.equal(conferirSsr(ssrCom(URL_DO_WRANGLER), URL_DO_WRANGLER).estado, NAO_LOCAL, 'iguais, mas de produção');
  assert.equal(conferirSsr('<html></html>', VALOR_LOCAL).estado, ILEGIVEL, 'página sem o define:vars');
});

// ═══════════════════════════════════════════════════════════════════════════
// B · recorta a função pelo nome, do cabeçalho até a chave que fecha no começo da linha.
function corpo(src, cabecalho) {
  const i = src.indexOf(cabecalho);
  assert.ok(i >= 0, `controle: não achei "${cabecalho}"`);
  const fim = src.indexOf('\n}\n', i);
  assert.ok(fim > i, `controle: "${cabecalho}" não fecha`);
  return src.slice(i, fim + 2);
}

const HARNESSES = [
  {
    arq: 'tests/browser-guards.test.mjs',
    recusa: (x) => `await recusarNaoMedido\\(${x}\\);`,
    prontidao: /await fetch\(`\$\{base\}\$\{caminho\}`, \{ redirect: 'manual' \}\);\s*if \(res\.status >= 200 && res\.status < 500\) return res;/,
    primeiraPagina: 'chromium.launch(',
  },
  {
    arq: 'scripts/smoke-routes.mjs',
    recusa: (x) => `throw naoMedido\\(${x}\\);`,
    prontidao: /await fetch\(`\$\{BASE\}\$\{caminho\}`, \{[\s\S]*?\}\);\s*if \(res\.status >= 200 && res\.status < 500\) \{[\s\S]*?return res;\s*\}/,
    primeiraPagina: 'assercoes()',
  },
];

for (const h of HARNESSES) {
  test(`B · ${h.arq}: o banco servido é conferido antes da primeira página, e a recusa mata o servidor`, () => {
    const src = maskJsComments(ler(h.arq));
    assert.equal(CAMINHO_SEM_SSR, '/src/lib/supabase.ts', 'a primeira sonda é o módulo do cliente, sem SSR');

    const guarda = corpo(src, 'async function exigirBancoLocal() {');
    assert.match(guarda, new RegExp(
      String.raw`^async function exigirBancoLocal\(\) \{\s*` +
      String.raw`const modulo = await waitForServer\(CAMINHO_SEM_SSR\);\s*` +
      String.raw`const cliente = avaliarModuloCliente\(await modulo\.text\(\)\);\s*` +
      String.raw`if \(cliente\.estado !== LOCAL\) ${h.recusa('cliente')}\s*` +
      String.raw`const pagina = await waitForServer\('/'\);\s*` +
      String.raw`const ssr = conferirSsr\(await pagina\.text\(\), cliente\.valor\);\s*` +
      String.raw`if \(ssr\.estado !== LOCAL\) ${h.recusa('ssr')}\s*\}`,
    ), 'a ordem é, sem nada antes nem entre: módulo sem SSR, recusa se não for local, só então a página `/`, e o SSR tem de bater');

    assert.match(corpo(src, 'async function waitForServer(caminho) {'), h.prontidao,
      'a sonda tem de usar o caminho recebido e devolver a resposta: sem isso a primeira sonda volta a ser `/`');

    const fora = src.replace(guarda, '');
    assert.equal(fora.match(/waitForServer\(/g)?.length, 1,
      'fora da guarda só pode sobrar a definição: qualquer outra sonda de `/` roda o SSR antes da conferência');

    const run = corpo(src, 'async function run() {');
    const iGuarda = run.indexOf('await exigirBancoLocal();');
    assert.ok(iGuarda >= 0, 'o run() não chama a guarda');
    assert.ok(iGuarda < run.indexOf(h.primeiraPagina), `a guarda tem de vir antes de ${h.primeiraPagina}`);
  });
}

test('B · browser-guards: recusar é dizer não medido, matar o grupo e sair com 3', () => {
  const src = maskJsComments(ler('tests/browser-guards.test.mjs'));
  assert.match(corpo(src, 'async function recusarNaoMedido(avaliacao) {'),
    /console\.error\(mensagemNaoMedido\('browser-guards', avaliacao\)\);\s*await matarServidor\(\);\s*process\.exit\(SAIDA_NAO_MEDIDO\);\s*\}/);
  assert.equal(SAIDA_NAO_MEDIDO, 3);
});

test('B · smoke-routes: a recusa leva a saída 3, o finally mata o servidor e o catch sai com ela', () => {
  const src = maskJsComments(ler('scripts/smoke-routes.mjs'));
  assert.match(corpo(src, 'function naoMedido(avaliacao) {'),
    /return Object\.assign\(new Error\(mensagemNaoMedido\('\[smoke\]', avaliacao\)\), \{ saida: SAIDA_NAO_MEDIDO \}\);\s*\}/);
  const run = corpo(src, 'async function run() {');
  assert.match(run, /try \{\s*await exigirBancoLocal\(\);[\s\S]*\} finally \{\s*await matarServidor\(\);\s*\}\s*\}$/,
    'a guarda roda dentro do try cujo finally mata o servidor');
  assert.match(src, /run\(\)\.catch\(\(err\) => \{\s*console\.error\(err\.message \|\| err\);\s*process\.exit\(err\?\.saida \?\? 1\);\s*\}\);/);
});

// ═══════════════════════════════════════════════════════════════════════════
const RETRY = resolve(ROOT, 'scripts/run_browser_guards_with_retry.sh');

function rodarRetry(npmFalso) {
  const dir = mkdtempSync(join(tmpdir(), 'bg-banco-'));
  const bin = join(dir, 'bin');
  mkdirSync(bin);
  writeFileSync(join(bin, 'npm'), npmFalso);
  chmodSync(join(bin, 'npm'), 0o755);
  const summary = join(dir, 'summary.md');
  const r = spawnSync('bash', [RETRY], {
    cwd: dir,
    encoding: 'utf8',
    env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: dir, GITHUB_STEP_SUMMARY: summary },
  });
  const resumo = existsSync(summary) ? readFileSync(summary, 'utf8') : '';
  rmSync(dir, { recursive: true, force: true });
  return { status: r.status, out: `${r.stdout}${r.stderr}`, resumo };
}

test('C · o retry não repete uma recusa: saída 3 na tentativa 1 sai com 3, sem tentativa 2', () => {
  const r = rodarRetry('#!/usr/bin/env bash\necho "browser-guards: não medido: o dev server serve PUBLIC_SUPABASE_URL em x"\nexit 3\n');
  assert.equal(r.status, 3, r.out);
  assert.match(r.out, /NAO MEDIDO na tentativa 1/);
  assert.doesNotMatch(r.out, /attempt 2\/2/, 'a tentativa 2 subiria o mesmo servidor com o mesmo valor');
  assert.match(r.resumo, /browser_guards NAO MEDIDO/);
});

test('C controle · uma falha comum (saída 1) ainda tem retry', () => {
  const r = rodarRetry('#!/usr/bin/env bash\necho "falha comum"\nexit 1\n');
  assert.equal(r.status, 1, r.out);
  assert.match(r.out, /attempt 2\/2/, 'o instrumento tem de conseguir dizer o outro estado');
  assert.doesNotMatch(r.out, /NAO MEDIDO/);
});

// ═══════════════════════════════════════════════════════════════════════════
// D · os passos que sobem o `astro dev` saem do ci.yml, não de uma lista escrita aqui.
const SOBE_SERVIDOR = /npm run (?:smoke:routes|test:visual|test:browser|dev)\b|run_browser_guards_with_retry\.sh|astro dev/;
const ESCREVE_DEV_VARS = /(?:^|[^\w.])>\s*\.dev\.vars\s*$/;

function executarPasso(run) {
  const dir = mkdtempSync(join(tmpdir(), 'devvars-'));
  const r = spawnSync('bash', ['-ec', run], { cwd: dir, encoding: 'utf8' });
  const arq = join(dir, '.dev.vars');
  const conteudo = existsSync(arq) ? readFileSync(arq, 'utf8') : null;
  rmSync(dir, { recursive: true, force: true });
  return { status: r.status, conteudo };
}

test('D · em todo job do CI que sobe o dev server, o .dev.vars falso vem antes', () => {
  const ci = load(ler('.github/workflows/ci.yml'));
  const achados = [];
  for (const [job, def] of Object.entries(ci.jobs)) {
    (def.steps || []).forEach((passo, i) => {
      if (typeof passo.run === 'string' && SOBE_SERVIDOR.test(passo.run)) achados.push({ job, i, passos: def.steps });
    });
  }
  assert.deepEqual(achados.map((a) => a.job).sort(), ['browser_guards', 'validate', 'visual_dark_mode'],
    'controle: a enumeração tem de achar os três passos que sobem o servidor hoje');

  for (const { job, i, passos } of achados) {
    const antes = passos.slice(0, i).filter((p) => typeof p.run === 'string' && ESCREVE_DEV_VARS.test(p.run.trim()));
    assert.equal(antes.length, 1, `${job}: falta o passo que escreve o .dev.vars antes de "${passos[i].name}"`);
    const r = executarPasso(antes[0].run);
    assert.equal(r.status, 0, `${job}: o passo do .dev.vars falhou`);
    const vars = Object.fromEntries((r.conteudo || '').split('\n').filter(Boolean).map((l) => l.split(/=(.*)/s).slice(0, 2)));
    assert.equal(avaliarUrl(vars.PUBLIC_SUPABASE_URL).estado, LOCAL, `${job}: o .dev.vars não aponta para um banco local`);
    assert.equal(vars.PUBLIC_SUPABASE_ANON_KEY, 'mock-key-for-build', `${job}: o .dev.vars não traz a chave falsa`);
    const depois = passos.slice(passos.indexOf(antes[0]) + 1, i);
    assert.ok(!depois.some((p) => /\.dev\.vars/.test(p.run || '')), `${job}: um passo entre os dois mexe no .dev.vars`);
  }
});

// ═══════════════════════════════════════════════════════════════════════════
test('E · o .dev.vars fica fora do git', () => {
  const ignora = (p) => spawnSync('git', ['check-ignore', '-q', p], { cwd: ROOT }).status;
  assert.equal(ignora('.dev.vars'), 0, 'o .dev.vars tem de estar no .gitignore');
  assert.equal(ignora('wrangler.toml'), 1, 'controle: um arquivo versionado não é ignorado');
});
