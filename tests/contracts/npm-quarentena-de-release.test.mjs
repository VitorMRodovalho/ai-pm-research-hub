// tests/contracts/npm-quarentena-de-release.test.mjs
//
// #2217 — quarentena de release do npm (decisão do GP, 30/10/2026): todo projeto npm do repositório
// resolve só versão publicada há pelo menos 3 dias (`min-release-age=3` no `.npmrc`, npm >= 11.10.0).
//
// Medido em 30/10/2026 com npm 11.19.1, o que vem com o Node 24.22.1 do CI:
//   - `npm install lucide-react@^1.52.0` resolveu 1.62.0 com a quarentena e 1.65.0 sem ela;
//   - `npm install lucide-react@1.65.0`, publicada no mesmo dia, deu ETARGET;
//   - `npm ci` sobre um lock que já fixava 1.65.0 instalou 1.65.0 com exit 0: a quarentena vale quando o
//     lock é GERADO, não quando ele é instalado. O CI não quebra por ela e também não a impõe;
//   - o `.npmrc` da raiz NÃO alcança um projeto com `package.json` próprio (o worker leu `null`). Por isso
//     a regra é por projeto, e o recorte vem do disco, não de uma lista escrita à mão.
//
// Exceção (correção de segurança urgente, só com o OK da orquestradora) é DADO: entra em EXCECOES abaixo,
// com o motivo, e o `.npmrc` ganha a linha `min-release-age-exclude[]=<pacote>`. Sem as duas coisas juntas,
// este guard reprova.

import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';

const ROOT = resolve(process.cwd());
const MIN_DIAS = 3;
const PULAR = new Set(['node_modules', '.git', 'dist', '.astro', '.wrangler', '.vercel', 'coverage']);

/** { '<dir relativo>': ['pacote', ...] } — vazio enquanto não houver exceção aprovada. */
const EXCECOES = {};

/** Diretórios (relativos à raiz) que têm um package.json, lidos do disco. */
function projetos(dir = ROOT, out = []) {
  const entradas = readdirSync(dir, { withFileTypes: true });
  if (entradas.some((e) => e.isFile() && e.name === 'package.json')) out.push(relative(ROOT, dir) || '.');
  for (const e of entradas) if (e.isDirectory() && !PULAR.has(e.name)) projetos(join(dir, e.name), out);
  return out;
}

/** Lê um .npmrc no formato ini do npm: a última atribuição vence; `chave[]=` acumula. */
function lerNpmrc(texto) {
  const valores = new Map();
  for (const bruta of texto.split('\n')) {
    const linha = bruta.trim();
    if (!linha || linha.startsWith('#') || linha.startsWith(';')) continue;
    const i = linha.indexOf('=');
    if (i < 0) continue;
    const chave = linha.slice(0, i).trim();
    const valor = linha.slice(i + 1).trim();
    if (chave.endsWith('[]')) {
      const k = chave.slice(0, -2);
      valores.set(k, [...(valores.get(k) ?? []), valor]);
    } else valores.set(chave, valor);
  }
  return valores;
}

/** Pendências de quarentena para uma lista de projetos { dir, npmrc: texto | null }. */
function pendencias(lista, excecoes = EXCECOES) {
  const out = [];
  for (const { dir, npmrc } of lista) {
    if (npmrc === null) { out.push(`${dir}: sem .npmrc`); continue; }
    const v = lerNpmrc(npmrc);
    const dias = Number(v.get('min-release-age'));
    if (!Number.isInteger(dias) || dias < MIN_DIAS) out.push(`${dir}: min-release-age=${v.get('min-release-age') ?? '(ausente)'}, esperado >= ${MIN_DIAS}`);
    if (v.has('before')) out.push(`${dir}: before=${v.get('before')} sobrepõe a quarentena`);
    const exclui = v.get('min-release-age-exclude') ?? [];
    const aprovadas = excecoes[dir] ?? [];
    for (const p of exclui) if (!aprovadas.includes(p)) out.push(`${dir}: exceção ${p} sem registro em EXCECOES`);
    for (const p of aprovadas) if (!exclui.includes(p)) out.push(`${dir}: EXCECOES lista ${p}, que o .npmrc não exclui`);
  }
  return out;
}

const NO_DISCO = projetos().map((dir) => {
  const f = join(ROOT, dir, '.npmrc');
  return { dir, npmrc: existsSync(f) ? readFileSync(f, 'utf8') : null };
});

test('quarentena: todo projeto npm do repositório resolve só versão com 3 dias ou mais', (t) => {
  t.diagnostic(`projetos com package.json: ${NO_DISCO.map((p) => p.dir).join(', ')}`);
  assert.ok(NO_DISCO.some((p) => p.dir === '.'), 'a raiz não apareceu: o recorte não está lendo o repositório');
  assert.ok(NO_DISCO.length >= 2, `esperados ao menos raiz e worker, achados ${NO_DISCO.length}`);
  assert.deepEqual(pendencias(NO_DISCO), []);
});

// ── mutações ─────────────────────────────────────────────────────────────────────────────────────

const OK = 'legacy-peer-deps=true\n# comentário\nmin-release-age=3\n';

test('quarentena: controle sem mutação passa', () => {
  assert.deepEqual(pendencias([{ dir: '.', npmrc: OK }, { dir: 'w', npmrc: 'min-release-age=3\n' }]), []);
});

const MUTACOES = [
  ['projeto sem .npmrc', [{ dir: 'w', npmrc: null }]],
  ['sem a linha', [{ dir: '.', npmrc: 'legacy-peer-deps=true\n' }]],
  ['só num comentário', [{ dir: '.', npmrc: '# min-release-age=3\n' }]],
  ['janela menor (2)', [{ dir: '.', npmrc: 'min-release-age=2\n' }]],
  ['janela zero', [{ dir: '.', npmrc: 'min-release-age=0\n' }]],
  ['linha posterior relaxa', [{ dir: '.', npmrc: 'min-release-age=3\nmin-release-age=1\n' }]],
  ['before sobrepõe', [{ dir: '.', npmrc: 'min-release-age=3\nbefore=2099-01-01\n' }]],
  ['exceção sem registro', [{ dir: '.', npmrc: 'min-release-age=3\nmin-release-age-exclude[]=eslint\n' }]],
];

for (const [nome, lista] of MUTACOES) {
  test(`quarentena: mutação reprova — ${nome}`, () => {
    assert.notDeepEqual(pendencias(lista), []);
  });
}

test('quarentena: exceção registrada nos dois lugares passa; registrada só no teste reprova', () => {
  const lista = [{ dir: '.', npmrc: 'min-release-age=3\nmin-release-age-exclude[]=eslint\n' }];
  assert.deepEqual(pendencias(lista, { '.': ['eslint'] }), []);
  assert.notDeepEqual(pendencias([{ dir: '.', npmrc: 'min-release-age=3\n' }], { '.': ['eslint'] }), []);
});
