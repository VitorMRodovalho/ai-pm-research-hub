/**
 * Contract: #1505 — os jobs de CI que falam com o banco de PRODUCAO compartilhado
 * nunca podem rodar em paralelo, nem ser cancelados no meio da escrita.
 *
 * Em 2026-07-28 dois runs de `validate` ocuparam a mesma janela de 7 minutos (main
 * pos-merge 13:18:58→13:25:19; PR #1504 13:19:01→13:25:22) e falharam em subtestes
 * DIFERENTES dos MESMOS arquivos: #1294/#1297 (handoffs), #192 (curation_review_log),
 * #693 (dual-track application), invariantes S e R. O re-run do MESMO commit, isolado,
 * passou em 8m20s com 11/11 checks. O PR nao continha uma linha de SQL.
 *
 * `--test-concurrency=1` (#1261) NAO cobre isso: serializa por PROCESSO, nao por banco.
 * A conclusao do #1487 ("0 = race") tambem continua valida — ela mediu corrida DENTRO
 * de um run. Esta e corrida ENTRE runs.
 *
 * Duas defesas, e as duas precisam sobreviver a refatoracoes de workflow:
 *  1. grupo de concorrencia GLOBAL (sem `github.ref` no nome) nos jobs que tocam o banco,
 *     porque o recurso disputado e o banco e nao o ref;
 *  2. `cancel-in-progress: false`, porque matar a suite no meio deixa fixture pela metade
 *     em prod (`tx=rollback` nao desfaz INSERT de SECURITY DEFINER).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const SHARED_GROUP = 'supabase-shared-db';
// job -> workflow que o define
const DB_JOBS = {
  validate: '.github/workflows/ci.yml',
  'check-invariants': '.github/workflows/invariants-check.yml',
};

/** Le o bloco `concurrency:` de um job, sem depender de parser de YAML. */
function jobConcurrency(text, job) {
  const jobStart = text.indexOf(`\n  ${job}:\n`);
  assert.ok(jobStart >= 0, `job ${job} deve existir no workflow`);
  const next = text.slice(jobStart + 1).search(/\n {2}[a-z_][\w-]*:\n/);
  const block = next === -1 ? text.slice(jobStart) : text.slice(jobStart, jobStart + 1 + next);
  const m = /\n\s*concurrency:\s*\n\s*group:\s*(\S+)\s*\n\s*cancel-in-progress:\s*(\S+)/.exec(block);
  return m ? { group: m[1], cancelInProgress: m[2] } : null;
}

for (const [job, file] of Object.entries(DB_JOBS)) {
  test(`1505: job ${job} entra na fila global do banco`, () => {
    const p = resolve(ROOT, file);
    assert.ok(existsSync(p), `deve existir: ${file}`);
    const c = jobConcurrency(readFileSync(p, 'utf8'), job);
    assert.ok(c, `${job} deve declarar concurrency no NIVEL DO JOB`);
    assert.equal(c.group, SHARED_GROUP,
      `${job} deve usar o grupo global '${SHARED_GROUP}'`);
    assert.doesNotMatch(c.group, /github\.ref/,
      `${job}: grupo por ref nao serializa main contra PR, que foi a colisao do #1505`);
    assert.equal(c.cancelInProgress, 'false',
      `${job}: cancelar em voo deixa fixture pela metade em producao`);
  });
}

test('1505: nenhum workflow que toca o banco cancela run em voo', () => {
  for (const file of new Set(Object.values(DB_JOBS))) {
    const text = readFileSync(resolve(ROOT, file), 'utf8');
    assert.doesNotMatch(text, /cancel-in-progress:\s*true/,
      `${file}: nenhum grupo pode cancelar em voo enquanto a suite escreve em prod (#1505)`);
  }
});

test('1505: os dois jobs compartilham a MESMA fila', () => {
  const groups = Object.entries(DB_JOBS).map(([job, file]) =>
    jobConcurrency(readFileSync(resolve(ROOT, file), 'utf8'), job)?.group);
  assert.equal(new Set(groups).size, 1,
    'filas distintas voltariam a permitir sobreposicao no mesmo banco');
});
