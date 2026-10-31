// tests/contracts/2217-worker-pmi-vep-sync-no-ci.test.mjs
// So le arquivo; nao toca o banco.
/**
 * #2217: o typecheck, os testes e o lint do worker `cloudflare-workers/pmi-vep-sync` rodam no CI.
 *
 * Ate aqui o worker tinha os tres scripts e nenhum workflow que os rodasse. E o lint nunca tinha
 * checado nada: sem config propria, herdava a da raiz, que nao da parser TypeScript aos arquivos do
 * worker, e os 15 `.ts` do `src` davam erro fatal de parse (#2879). Um portao que existe mas nao
 * roda no CI nao protege nada, e um que roda mas nao pode reprovar tambem nao.
 *
 * Este guard amarra as quatro pontas da fiacao:
 *   1. o job roda DENTRO do diretorio do worker, instala a arvore dele e chama os tres scripts
 *      depois do `npm ci`, sem `continue-on-error` nem `if:` que o pule;
 *   2. o workflow reporta em toda PR, sem filtro de `paths`;
 *   3. cada script do worker chama a ferramenta certa;
 *   4. a config de lint do worker da o parser TypeScript aos `.ts`, e todo pacote que ela importa
 *      esta nas `devDependencies` do worker. O job instala SO a arvore do worker: um import que
 *      hoje resolve pelo `node_modules` da raiz quebraria la.
 *
 * Comentarios (YAML e JS) saem antes de qualquer assercao, para nao asserir sobre prosa.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const DIR = 'cloudflare-workers/pmi-vep-sync';
const WF = resolve(ROOT, '.github/workflows/worker-pmi-vep-sync.yml');
const PKG = resolve(ROOT, DIR, 'package.json');
const ESLINT = resolve(ROOT, DIR, 'eslint.config.mjs');

/** Remove comentarios YAML (mesma forma dos guards #1509 e #2774). */
function semComentarios(src) {
  return src.replace(/(^|\s)#[^\n]*/g, '$1');
}

/**
 * Remove so comentario `//` que abre a linha. O `maskJsComments` dos helpers nao serve aqui (#2882): ele
 * le o `/**` de dentro do glob `'node_modules/**'` como abertura de bloco e apaga ate o `*\/` de
 * `'**\/*.ts'`, justamente o trecho que este guard precisa ler.
 */
function semComentariosDeLinha(src) {
  return src.replace(/^([ \t]*)\/\/[^\n]*/gm, '$1');
}

/** Corpo de uma chave de topo do YAML (`on:`, `jobs:`), ate a proxima chave de topo. */
function blocoDeTopo(src, chave) {
  const linhas = src.split('\n');
  const ini = linhas.findIndex((l) => new RegExp(`^${chave}:\\s*$`).test(l));
  if (ini === -1) return null;
  const fim = linhas.findIndex((l, i) => i > ini && /^\S/.test(l));
  return linhas.slice(ini + 1, fim === -1 ? undefined : fim).join('\n');
}

/** Jobs: chave com 2 espacos dentro de `jobs:`. */
function jobs(src) {
  const out = [];
  let atual = null;
  for (const l of (blocoDeTopo(src, 'jobs') ?? '').split('\n')) {
    const m = l.match(/^ {2}([A-Za-z0-9_-]+):\s*$/);
    if (m) { atual = { job: m[1], texto: '' }; out.push(atual); continue; }
    if (atual) atual.texto += `${l}\n`;
  }
  return out;
}

const wf = semComentarios(readFileSync(WF, 'utf8'));
const pkg = JSON.parse(readFileSync(PKG, 'utf8'));

/** O job cujo `defaults.run.working-directory` e o diretorio do worker. */
function jobDoWorker() {
  const wd = new RegExp(`^ {4}defaults:\\s*\\n {6}run:\\s*\\n {8}working-directory:[ \\t]*['"]?${DIR}['"]?[ \\t]*$`, 'm');
  const achados = jobs(wf).filter((j) => wd.test(j.texto));
  assert.equal(achados.length, 1, `esperado 1 job com defaults.run.working-directory ${DIR}, achados ${achados.length}`);
  return achados[0];
}

test('2217: o job do worker instala a arvore dele e roda typecheck, testes e lint depois do npm ci', () => {
  const { job, texto } = jobDoWorker();
  // `run:` de passo: `- run:` no recuo do item, ou `run:` dentro dele. O `run:` de `defaults` nao
  // tem valor na linha e fica de fora.
  const comandos = [...texto.matchAll(/^(?: {6}- | {8})run:[ \t]*(\S[^\n]*)$/gm)].map((m) => m[1].trim());
  const lista = JSON.stringify(comandos);
  const ci = comandos.indexOf('npm ci');
  assert.ok(ci !== -1, `${job}: nenhum passo roda \`npm ci\` (comandos: ${lista})`);
  for (const c of ['npm run typecheck', 'npm test', 'npm run lint']) {
    assert.ok(comandos.indexOf(c) > ci, `${job}: \`${c}\` ausente ou antes do \`npm ci\` (comandos: ${lista})`);
  }
  assert.equal((texto.match(/working-directory:/g) ?? []).length, 1,
    `${job}: um passo com working-directory proprio roda fora do worker`);
  assert.doesNotMatch(texto, /continue-on-error:\s*true/, `${job}: continue-on-error deixa o portao passar vermelho`);
  assert.doesNotMatch(texto, /^\s+(?:-\s+)?if:/m, `${job}: um if: no job ou num passo pode pular o portao`);
});

test('2217: o workflow reporta em toda PR, sem filtro de caminho', () => {
  const on = blocoDeTopo(wf, 'on');
  assert.ok(on !== null, 'workflow sem bloco `on:` em forma de mapa');
  const pr = on.match(/^ {2}pull_request:[^\n]*\n?((?: {4,}[^\n]*(?:\n|$))*)/m);
  assert.ok(pr, '`on:` nao dispara em pull_request');
  assert.doesNotMatch(pr[1], /^\s+paths(?:-ignore)?:/m,
    'pull_request com filtro de paths deixa a PR que nao toca o worker esperando um status que nao chega');
});

test('2217: cada script do worker chama a ferramenta certa', () => {
  const s = pkg.scripts ?? {};
  assert.match(s.typecheck ?? '', /^tsc --noEmit(\s|$)/, `typecheck do worker nao e \`tsc --noEmit\`: ${s.typecheck}`);
  assert.match(s.test ?? '', /^vitest run(\s|$)/, `test do worker nao e \`vitest run\`: ${s.test}`);
  assert.match(s.lint ?? '', /^eslint\s+src(\s|$)/, `lint do worker nao roda eslint sobre src: ${s.lint}`);
});

test('2217: a config de lint do worker da o parser TypeScript aos .ts e declara o que importa', () => {
  const cfg = semComentariosDeLinha(readFileSync(ESLINT, 'utf8'));
  const imp = cfg.match(/^import\s+(\w+)\s+from\s+'@typescript-eslint\/parser';$/m);
  assert.ok(imp, 'a config do worker nao importa o @typescript-eslint/parser');
  // `files` e `parser` no MESMO objeto: entre os dois nao fecha chave.
  assert.match(cfg, new RegExp(`files:\\s*\\[\\s*'\\*\\*/\\*\\.ts'\\s*\\][^}]*?parser:\\s*${imp[1]}\\b`),
    'nenhum objeto da config da o parser TypeScript a **/*.ts');

  const dev = pkg.devDependencies ?? {};
  const pacotes = [...cfg.matchAll(/^import\s+[^'\n]+\s+from\s+'([^'.][^']*)';$/gm)]
    .map((m) => m[1])
    .filter((p) => !p.startsWith('node:'))
    .map((p) => p.split('/').slice(0, p.startsWith('@') ? 2 : 1).join('/'));
  assert.ok(pacotes.length >= 2, `o recorte de imports achou ${pacotes.length}: a config mudou de forma`);
  for (const p of [...pacotes, 'eslint']) {
    assert.ok(Object.hasOwn(dev, p), `${p} e usado pelo lint do worker e falta nas devDependencies dele`);
  }
});
