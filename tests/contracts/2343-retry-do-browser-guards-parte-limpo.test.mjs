/**
 * #2343 fase 2: o retry do browser_guards parte do estado de um JOB NOVO.
 *
 * Medido em 26/09/2026 em dois runs da main que reprovaram: a tentativa 2 subia em ~5,5 s contra
 * ~11 s da 1, sem nenhuma linha do otimizador de dependencias do Vite, e falhava com a mesma
 * assinatura (`Unable to resolve .../BaseLayout.astro` no workerd). Um re-run do JOB, que parte de
 * `npm ci` num checkout limpo, passava. A diferenca entre os dois e o estado de runtime que a
 * tentativa 1 deixa: `node_modules/.vite` e `.wrangler`.
 *
 * Este guard EXERCITA o script (scripts/run_browser_guards_with_retry.sh) com um `npm` falso no PATH:
 * a tentativa 1 cria esse estado e falha com a assinatura; a 2 so passa se o estado tiver sumido.
 * Presenca de string no script nao prova nada; o que prova e o retry passar.
 *
 * Offline: bash e node; nenhum browser, nenhum dev server. Custa o cooldown de 5 s do script.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync, chmodSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const SCRIPT = resolve(process.cwd(), 'scripts/run_browser_guards_with_retry.sh');

const NPM_HERDA_ESTADO = `#!/usr/bin/env bash
# tentativa 1: deixa o estado de runtime e falha com a assinatura do #2343
if [ ! -e "$PWD/.tentativa1" ]; then
  touch "$PWD/.tentativa1"
  mkdir -p node_modules/.vite/deps .wrangler/state
  touch node_modules/.vite/deps/chunk.js .wrangler/state/kv.sqlite
  echo "Unable to resolve [/x/src/layouts/BaseLayout.astro?astro&type=script] workerd/jsg failed"
  exit 1
fi
# tentativa 2: se herdou o estado, falha igual (o que acontecia no CI)
if [ -e node_modules/.vite ] || [ -e .wrangler ]; then
  echo "herdou estado da tentativa 1: Unable to resolve BaseLayout.astro"
  exit 1
fi
echo "ok"
exit 0
`;

const NPM_SEMPRE_FALHA = `#!/usr/bin/env bash
echo "Unable to resolve [/x/src/layouts/BaseLayout.astro] workerd/jsg failed"
exit 1
`;

function rodar(npmFalso) {
  const dir = mkdtempSync(join(tmpdir(), 'bg-retry-'));
  const bin = join(dir, 'bin');
  mkdirSync(bin);
  writeFileSync(join(bin, 'npm'), npmFalso);
  chmodSync(join(bin, 'npm'), 0o755);
  const summary = join(dir, 'summary.md');
  const r = spawnSync('bash', [SCRIPT], {
    cwd: dir,
    encoding: 'utf8',
    env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: dir, GITHUB_STEP_SUMMARY: summary },
  });
  const resumo = existsSync(summary) ? readFileSync(summary, 'utf8') : '';
  rmSync(dir, { recursive: true, force: true });
  return { status: r.status, out: `${r.stdout}${r.stderr}`, resumo };
}

test('#2343: a tentativa 2 parte sem o estado de runtime que a 1 deixou, e por isso passa', () => {
  const r = rodar(NPM_HERDA_ESTADO);
  assert.equal(r.status, 0, `o retry deveria passar partindo de estado limpo; saida:\n${r.out}`);
  assert.match(r.out, /attempt 1 FALHOU — assinatura: workerd-nao-resolve-BaseLayout/, 'a 1 foi classificada');
  assert.match(r.out, /estado de runtime apagado antes do retry: node_modules\/\.vite=1 arquivos, \.wrangler=1 arquivos/,
    'o script diz o que apagou, com a contagem');
  assert.match(r.out, /success on attempt 2/);
  assert.match(r.resumo, /verde na tentativa 2 de 2/);
  assert.match(r.resumo, /passou partindo de estado limpo \(fase 2\)/, 'o resumo do job registra a fase 2');
});

test('#2343 controle: quando as duas tentativas falham, o script reprova e diz isso', () => {
  const r = rodar(NPM_SEMPRE_FALHA);
  assert.equal(r.status, 1, 'o guard tem de conseguir dizer nao');
  assert.match(r.out, /failed after 2 attempts/);
  assert.match(r.resumo, /REPROVOU nas 2 tentativas/);
});
