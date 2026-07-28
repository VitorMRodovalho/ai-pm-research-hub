/**
 * Contract: #1509 — a serialização dos jobs que falam com o banco de produção acontece em
 * RUNTIME, não na fila de concorrência do GitHub.
 *
 * O #1505 pôs `validate` (ci.yml) e `check-invariants` (invariants-check.yml) no mesmo grupo
 * global `supabase-shared-db`. A intenção estava certa — os dois escrevem/leem a mesma base de
 * produção e não podem se sobrepor — mas a fila do GitHub guarda UM pendente por grupo e
 * CANCELA o anterior quando um terceiro chega. Medido em 2026-07-28: run 30373280532, commit
 * 1fbf630c (que aplicava DDL), job `check-invariants` com conclusion `cancelled` e ZERO steps
 * executados. O gate não rodou, e `cancelled` não lê como vermelho.
 *
 * A troca foi por espera em runtime: todos os jobs iniciam, consultam a faixa e aguardam a vez
 * numa ordem total. Nenhum é descartado, então "não rodou" deixa de ser um estado silencioso.
 *
 * Este teste trava as três pernas que, se soltas, devolvem o buraco:
 *
 * 1. o grupo cancelável não pode voltar (nem aqui nem em workflow novo);
 * 2. todo job da faixa precisa CHAMAR a espera e ter `actions: read` — sem a permissão a
 *    consulta 403a, e sem a chamada a serialização simplesmente não existe;
 * 3. a espera não pode engolir erro de API nem "desistir passando" — se a faixa não puder ser
 *    lida, o job PARA, porque uma faixa que parece vazia por falha de leitura é pior que a
 *    fila que ela substituiu.
 *
 * Estático. Comentários YAML são removidos antes de qualquer asserção: os comentários deste fix
 * citam `supabase-shared-db` justamente para explicar por que ele saiu, e um regex ingênuo
 * casaria com a explicação.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const WF_DIR = resolve(ROOT, '.github/workflows');
const ACTION = resolve(ROOT, '.github/actions/wait-for-db-lane/action.yml');

/** Jobs que disputam o banco: chave do job no workflow -> arquivo. */
const LANE = [
  { job: 'validate', file: 'ci.yml' },
  { job: 'check-invariants', file: 'invariants-check.yml' },
];

/** Remove comentários YAML (# até o fim da linha) para não asserir sobre prosa. */
function stripYamlComments(src) {
  return src.replace(/(^|\s)#[^\n]*/g, '$1');
}

function readWorkflow(file) {
  const path = resolve(WF_DIR, file);
  assert.ok(existsSync(path), `workflow deve existir: ${file}`);
  return stripYamlComments(readFileSync(path, 'utf8'));
}

/**
 * Recorta o bloco de um job (da chave até o próximo job no mesmo nível).
 * A sentinela cobre o job que é o ÚLTIMO do arquivo — sem ela o recorte depende de existir
 * algo depois, e o teste passaria a falhar por "bloco não encontrado" em vez de pelo que mede.
 */
function jobBlock(src, job) {
  const re = new RegExp(`^  ${job}:\\n([\\s\\S]*?)(?=^\\S|^  \\S)`, 'm');
  return `${src}\nFIM_DO_ARQUIVO:\n`.match(re)?.[1] || '';
}

// ── 1. O grupo cancelável não pode voltar ────────────────────────────────────

test('1509: nenhum workflow volta a usar o grupo de concorrencia cancelavel', () => {
  const offenders = readdirSync(WF_DIR)
    .filter((f) => /\.ya?ml$/.test(f))
    .filter((f) => /supabase-shared-db/.test(stripYamlComments(readFileSync(resolve(WF_DIR, f), 'utf8'))));

  assert.deepEqual(offenders, [],
    'grupo de concorrencia global cancela o job PENDENTE quando um terceiro chega (#1509); a serializacao e por espera em runtime');
});

// ── 2. Todo job da faixa chama a espera e consegue ler a faixa ───────────────

for (const { job, file } of LANE) {
  test(`1509: ${job} (${file}) chama a espera da faixa e pode consultar a API`, () => {
    const src = readWorkflow(file);
    const block = jobBlock(src, job);
    assert.ok(block, `bloco do job ${job} deve existir em ${file}`);

    assert.match(block, /uses:\s*\.\/\.github\/actions\/wait-for-db-lane/,
      `${job} deve chamar wait-for-db-lane, senao nao ha serializacao alguma`);
    assert.match(block, /permissions:[\s\S]*?actions:\s*read/,
      `${job} precisa de actions: read, senao a consulta da faixa 403a e o job para`);

    // A identidade do job na faixa vem de GITHUB_JOB, que e a CHAVE do job. Um `name:`
    // proprio faz a API reportar outro nome, o job nunca se reconhece como o primeiro e
    // espera ate o teto. Travado aqui porque o sintoma seria um timeout obscuro.
    assert.doesNotMatch(block, /^\s{4}name:\s/m,
      `${job} nao pode ter name: proprio — a faixa casa pela chave do job`);

    // A espera precisa vir antes de qualquer step que fale com o banco.
    const idxWait = block.indexOf('wait-for-db-lane');
    const idxDb = block.search(/SUPABASE_SERVICE_ROLE_KEY|npm run test/);
    assert.ok(idxDb === -1 || idxWait < idxDb,
      `em ${job} a espera deve preceder o primeiro step que toca o banco`);
  });
}

// ── 2b. A espera tem de caber no orçamento do job ────────────────────────────

test('1509: o teto de espera cabe dentro do timeout de cada job da faixa', () => {
  const maxWait = Number(
    readFileSync(ACTION, 'utf8').match(/max-wait-seconds:[\s\S]*?default:\s*'(\d+)'/)?.[1],
  );
  assert.ok(Number.isFinite(maxWait), 'o default de max-wait-seconds deve ser legivel');

  for (const { job, file } of LANE) {
    const block = jobBlock(readWorkflow(file), job);
    const timeout = Number(block.match(/timeout-minutes:\s*(\d+)/)?.[1]);
    assert.ok(Number.isFinite(timeout), `${job} deve declarar timeout-minutes`);

    // A espera corre DENTRO do orçamento do job. Se o teto de espera não couber, o runner
    // mata o job por timeout antes de o script imprimir a mensagem de teto estourado — e um
    // job morto pelo runner é de novo um gate que não rodou por motivo obscuro, que é
    // exatamente o estado que o #1509 existe para eliminar. Observado ao vivo no primeiro
    // run deste PR: check-invariants tinha timeout-minutes 5 contra 900s de teto de espera.
    assert.ok(timeout * 60 > maxWait,
      `${job}: timeout-minutes=${timeout} (${timeout * 60}s) nao cobre o teto de espera de ${maxWait}s`);
  }
});

// ── 3. A espera não pode falhar passando ─────────────────────────────────────

test('1509: a acao existe e declara a faixa igual aos jobs reais', () => {
  assert.ok(existsSync(ACTION), 'a acao composta wait-for-db-lane deve existir');
  const src = readFileSync(ACTION, 'utf8');
  const dflt = src.match(/lane-jobs:[\s\S]*?default:\s*(.+)/)?.[1]?.trim() || '';
  const declared = dflt.split(/\s+/).filter(Boolean).sort();
  assert.deepEqual(declared, LANE.map((l) => l.job).sort(),
    'o default de lane-jobs deve listar exatamente os jobs que tocam o banco');
});

test('1509: falha de leitura da faixa PARA o job, nao o libera', () => {
  const src = stripYamlComments(readFileSync(ACTION, 'utf8'));

  const runsQuery = src.match(/runs=\$\([\s\S]*?\)\n/)?.[0] || '';
  assert.ok(runsQuery, 'a consulta da faixa deve existir na acao');
  assert.doesNotMatch(runsQuery, /\|\|\s*true/,
    'engolir erro da API faz a faixa parecer vazia e todos entrarem juntos no banco');

  assert.match(src, /set -euo pipefail/,
    'o script deve abortar no primeiro erro');
  assert.match(src, /::error::[\s\S]*?\n\s*exit 1/,
    'estourado o teto de espera, o job deve FALHAR — nunca seguir para o banco');
});
