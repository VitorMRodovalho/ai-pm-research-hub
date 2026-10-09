/**
 * #1742 — a fila do banco consulta a API menos vezes e usa o teto inteiro de espera pela cota.
 *
 * MEDIDO em 09/10/2026: com 4-5 jobs na fila do banco por 20-60 min, a `wait-for-db-lane` (uma
 * consulta a cada 15s, com 1 + N chamadas cada) esgotou a cota do token do Actions duas vezes no
 * mesmo dia. Os jobs falharam fechados e cada reexecucao pos mais um job na fila: o ciclo se
 * realimentava. E o guard desistia cedo demais: duas PRs morreram as 07:00:56Z dizendo "nao voltou
 * dentro de 900s" depois de esperar 35s, porque um reset alem do que restava do teto fazia o guard
 * falhar na hora em vez de esperar o resto.
 *
 * Dois consertos, e o que cada um prova aqui:
 *   1. INTERVALOS — os padroes da acao passam a 60s/120s (backoff apos 5 ciclos) e o teto de
 *      espera pela cota a 3600s. Afirmado no bloco de cada input, nome amarrado ao valor.
 *   2. TETO INTEIRO — um reset alem do que resta faz esperar o RESTO e tentar de novo; esgotado o
 *      teto, continua falhando fechado (o #1923 (2) segue afirmando isso). Prova por execucao,
 *      contra o `gh` falso do harness, com mutacao que restaura o comportamento antigo.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const ROOT = process.cwd();
const HARNESS = resolve(ROOT, 'tests/helpers/lane-guard-harness.sh');
const ACTION = resolve(ROOT, '.github/actions/wait-for-db-lane/action.yml');

function run(cenario, env = {}) {
  const work = mkdtempSync(join(tmpdir(), 'lane-guard-1742-'));
  const raw = execFileSync('bash', [HARNESS, cenario, work], {
    encoding: 'utf8', env: { ...process.env, ...env }, timeout: 120_000,
  });
  return { exit: Number(raw.match(/exit=(\d+)/)?.[1] ?? NaN), out: readFileSync(join(work, 'out.log'), 'utf8') };
}

/** Valor default do input `nome`, lido dentro do bloco do proprio input. */
function inputDefault(src, nome) {
  const bloco = src.match(new RegExp(`\\n  ${nome}:\\n([\\s\\S]*?)(?=\\n  [a-z][a-z-]*:\\n|\\nruns:)`));
  assert.ok(bloco, `input ${nome} sumiu da acao`);
  return bloco[1].match(/\n    default: '([^']*)'/)?.[1];
}

test('#1742 (1) a fila consulta a cada 60s/120s e espera a cota por ate 3600s', () => {
  const src = readFileSync(ACTION, 'utf8');
  assert.equal(inputDefault(src, 'poll-seconds'), '60');
  assert.equal(inputDefault(src, 'poll-seconds-long'), '120');
  assert.equal(inputDefault(src, 'poll-backoff-after'), '5');
  assert.equal(inputDefault(src, 'rate-limit-max-wait-seconds'), '3600');
});

test('#1742 (2) reset alem do que resta do teto: espera o resto e segue, em vez de desistir', () => {
  const r = run('cota-reset-longe');
  assert.equal(r.exit, 0, `a cota voltou dentro do teto e o job deveria seguir:\n${r.out}`);
  assert.match(r.out, /aguardando 4s ate o reset — total 6s\/6s/, 'a segunda espera tem de ser o RESTO do teto (6 - 2)');
});

test('#1742 (2) mutacao: o calculo antigo desiste com teto sobrando', () => {
  const src = readFileSync(ACTION, 'utf8');
  const mut = src.replace('[ "$wait_s" -gt "$rl_left" ] && wait_s="$rl_left"',
    '[ "$wait_s" -gt "$RL_MAX_WAIT" ] && wait_s="$RL_MAX_WAIT"; [ $(( rl_waited + wait_s )) -gt "$RL_MAX_WAIT" ] && { echo "::error::cota da API esgotada e nao voltou dentro de ${RL_MAX_WAIT}s" >&2; return 1; }');
  assert.notEqual(mut, src, 'mutacao nao aplicou');
  const p = join(mkdtempSync(join(tmpdir(), 'acao-mut-')), 'action.yml');
  writeFileSync(p, mut);
  const r = run('cota-reset-longe', { ACTION_FILE: p });
  assert.equal(r.exit, 1, `o calculo antigo deveria desistir aqui:\n${r.out}`);
});
