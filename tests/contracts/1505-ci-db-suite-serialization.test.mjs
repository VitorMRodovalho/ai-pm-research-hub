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
 *  1. os jobs que tocam o banco sao SERIALIZADOS entre si, seja qual for o ref, porque o
 *     recurso disputado e o banco e nao o ref;
 *  2. nada e cancelado no meio da escrita, porque matar a suite deixa fixture pela metade
 *     em prod (`tx=rollback` nao desfaz INSERT de SECURITY DEFINER).
 *
 * ATUALIZADO pelo #1509: a serializacao NAO e mais um grupo de concorrencia global. A fila do
 * GitHub guarda um pendente por grupo e CANCELA o anterior quando um terceiro chega, o que
 * fazia `check-invariants` sumir sem executar um step (run 30373280532, zero steps, sobre um
 * commit com DDL). A serializacao passou a ser espera em RUNTIME (`wait-for-db-lane`).
 *
 * Este teste segue medindo a INVARIANTE do #1505 (serializado + nada cancelado). O mecanismo
 * em si — ordem total, teto de espera, permissao de leitura da faixa — e do guard do #1509,
 * para as duas baterias nao virarem copia uma da outra.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const LANE_ACTION = '.github/actions/wait-for-db-lane';
// job -> workflow que o define
const DB_JOBS = {
  validate: '.github/workflows/ci.yml',
  'check-invariants': '.github/workflows/invariants-check.yml',
};

/** Recorta o bloco de um job, sem depender de parser de YAML. */
function jobBlock(text, job) {
  const jobStart = text.indexOf(`\n  ${job}:\n`);
  assert.ok(jobStart >= 0, `job ${job} deve existir no workflow`);
  const next = text.slice(jobStart + 1).search(/\n {2}[a-z_][\w-]*:\n/);
  return next === -1 ? text.slice(jobStart) : text.slice(jobStart, jobStart + 1 + next);
}

for (const [job, file] of Object.entries(DB_JOBS)) {
  test(`1505: job ${job} e serializado contra os outros que tocam o banco`, () => {
    const p = resolve(ROOT, file);
    assert.ok(existsSync(p), `deve existir: ${file}`);
    const block = jobBlock(readFileSync(p, 'utf8'), job);

    assert.match(block, new RegExp(`uses:\\s*\\./${LANE_ACTION.replace(/\//g, '\\/')}`),
      `${job} deve entrar na faixa do banco; sem isso volta a rodar concorrente com o outro job`);

    // Grupo de concorrencia por REF nao serializa main contra PR — foi a colisao do #1505 —
    // e grupo GLOBAL cancela o pendente — foi o sumico do gate no #1509. Nenhum dos dois
    // pode voltar no nivel do job.
    assert.doesNotMatch(block, /\n\s{4}concurrency:/,
      `${job}: a serializacao e por espera em runtime desde o #1509, nao por grupo de concorrencia`);
  });
}

test('1505: nenhum workflow que toca o banco cancela run em voo', () => {
  for (const file of new Set(Object.values(DB_JOBS))) {
    const text = readFileSync(resolve(ROOT, file), 'utf8');
    assert.doesNotMatch(text, /cancel-in-progress:\s*true/,
      `${file}: cancelar em voo deixa fixture pela metade em prod (#1505)`);
  }
});

test('1505: os dois jobs entram na MESMA faixa', () => {
  // Sem esta checagem o par poderia acabar em faixas distintas (uma serializacao que nao
  // serializa nada), que e o equivalente novo de "filas distintas". A identidade da faixa e
  // o default `lane-jobs` da acao, entao os dois jobs precisam estar listados nele.
  const action = readFileSync(resolve(ROOT, LANE_ACTION, 'action.yml'), 'utf8');
  const declared = (action.match(/lane-jobs:[\s\S]*?default:\s*(.+)/)?.[1] || '')
    .trim().split(/\s+/).filter(Boolean);
  for (const job of Object.keys(DB_JOBS)) {
    assert.ok(declared.includes(job),
      `${job} fora do default lane-jobs: ele nao seria enxergado pelos outros e rodaria por cima`);
  }
});
