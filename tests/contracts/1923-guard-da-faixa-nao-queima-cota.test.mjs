/**
 * #1923 — o guard da faixa do banco parou de queimar a cota da API de que ele mesmo depende.
 *
 * O INCIDENTE, medido em 22/08/2026. Entre 03:12:17Z e 03:16:18Z, SETE jobs de faixa morreram em
 * runs INDEPENDENTES (#1914, #1918, #1919, #1920 e o push da propria main), todos na mesma
 * mensagem: `falhei em ler a faixa apos 3 tentativas`. Nenhum executou uma assercao. A pagina de
 * status do GitHub nao registrava incidente. Falha simultanea em runs independentes nao e flake
 * por job: e recurso COMPARTILHADO esgotado.
 *
 * O recurso era a cota de API do `GITHUB_TOKEN`, que e por repositorio. O guard consultava
 * `actions/runs` e depois `runs/{id}/jobs` para CADA run ativo, a cada ~18s, POR job em espera.
 * Medidos 278 ciclos de espera entre 02:48 e 03:13 com 4 PRs em voo; a cada ciclo, 1 + (todos os
 * runs ativos) chamadas. Um unico PR abre seis workflows, dos quais dois tem job de faixa.
 *
 * Os tres consertos, e o que cada um prova aqui:
 *
 *   1. FILTRO — so runs de workflow que contem job de faixa viram chamada a `/jobs`. A lista e
 *      DERIVADA de `.github/workflows` (grep pela propria acao), nunca escrita a mao: uma lista de
 *      nomes que envelhece faria o guard ignorar um workflow novo e liberar dois jobs no banco ao
 *      mesmo tempo, que e o estrago do #1509 reintroduzido por uma otimizacao. Falhando a
 *      derivacao, varre tudo — degrada para caro-e-correto, nunca para barato-e-errado.
 *
 *   2. COTA E TERCEIRA CLASSE — blip de TLS melhora em segundos, token sem escopo nao melhora
 *      nunca, cota esgotada melhora em MINUTOS. As 3 tentativas em ~20s foram dimensionadas para a
 *      primeira e so aceleravam o vermelho na terceira. Agora espera ate o reset. O que NAO muda:
 *      estourado o teto, FALHA FECHADO.
 *
 *   3. O ERRO APARECE — antes ia para `/dev/null`, e a causa deste incidente teve de ser inferida.
 *
 * Este arquivo NAO afirma sobre strings: ele executa o script embutido na acao contra um `gh`
 * falso (`tests/helpers/lane-guard-harness.sh`) e conta as chamadas. Hermetico, sem rede e sem
 * banco.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const ROOT = process.cwd();
const HARNESS = resolve(ROOT, 'tests/helpers/lane-guard-harness.sh');
const ACTION = resolve(ROOT, '.github/actions/wait-for-db-lane/action.yml');

/** Roda um cenario e devolve {exit, jobsCalls, runsCalls, out}. */
function run(cenario, env = {}) {
  const work = mkdtempSync(join(tmpdir(), 'lane-guard-'));
  const raw = execFileSync('bash', [HARNESS, cenario, work], {
    encoding: 'utf8',
    env: { ...process.env, ...env },
    timeout: 120_000,
  });
  const num = (re) => Number(raw.match(re)?.[1] ?? NaN);
  return {
    exit: num(/exit=(\d+)/),
    jobsCalls: num(/jobs_calls=(\d+)/),
    runsCalls: num(/runs_calls=(\d+)/),
    out: readFileSync(join(work, 'out.log'), 'utf8'),
  };
}

test('#1923 controle positivo: a acao e o harness existem', () => {
  assert.ok(existsSync(ACTION), 'a acao wait-for-db-lane sumiu');
  assert.ok(existsSync(HARNESS), 'o harness sumiu — os testes abaixo passariam por vacuo');
});

test('#1923 (1) so os workflows COM job de faixa viram chamada a /jobs', () => {
  // O cenario expoe 5 runs ativos, 2 deles de workflow que chama a acao. Antes do conserto o
  // guard consultava os 5. A assercao e sobre o NUMERO, nao sobre a presenca do filtro: um
  // filtro escrito e nao aplicado passaria numa checagem de string e reprova aqui.
  const r = run('filtro');
  assert.equal(r.exit, 0, `o caminho feliz deveria sair 0:\n${r.out}`);
  assert.equal(r.runsCalls, 1, 'um ciclo deveria listar os runs uma vez so');
  assert.equal(
    r.jobsCalls, 2,
    `esperava 2 chamadas a /jobs (ci.yml + invariants-check.yml) e vieram ${r.jobsCalls}. `
    + '5 significa que o filtro sumiu e o custo por ciclo voltou a ser O(todos os runs).',
  );
});

test('#1923 (1) a lista de workflows e DERIVADA do repo, nao escrita a mao', () => {
  const r = run('filtro');
  assert.match(
    r.out, /workflows com job de faixa \(derivados do repo\): .*ci\.yml/,
    'o guard tem de dizer quais workflows derivou; sem isso nao da para saber se filtrou certo',
  );
  // A INVERSA que importa: nomes de workflow como literal na acao seriam lista que envelhece.
  const src = readFileSync(ACTION, 'utf8').replace(/^\s*#.*$/gm, '');
  assert.doesNotMatch(
    src, /lane[-_]workflows\s*=\s*["'][^"']*\.yml/,
    'a lista de workflows de faixa virou literal: um workflow novo passaria despercebido e dois '
    + 'jobs entrariam juntos no banco (#1509)',
  );
});

test('#1923 (2) cota esgotada ESPERA o reset em vez de morrer em 20s', () => {
  const r = run('cota-recupera');
  assert.equal(r.exit, 0, `a cota voltou e o job deveria seguir:\n${r.out}`);
  assert.match(r.out, /cota da API esgotada; aguardando \d+s ate o reset/,
    'a espera por cota tem de aparecer no log, senao o proximo diagnostico volta a ser inferencia');
  assert.doesNotMatch(r.out, /falhei em ler a faixa apos/,
    'cota esgotada nao pode ser tratada como as outras falhas: era exatamente esse o defeito');
});

test('#1923 (2) esgotado o teto de cota, o guard FALHA FECHADO', () => {
  // A regra do #1509 e inegociavel, e um conserto de disponibilidade e o jeito classico de
  // quebra-la sem querer. Se esta assercao cair, o guard passou a liberar o banco sem ter lido a
  // faixa, e duas suites escrevem em producao ao mesmo tempo.
  const r = run('cota-nao-volta');
  assert.equal(r.exit, 1, `cota que nao volta tem de reprovar o job, nao libera-lo:\n${r.out}`);
  assert.equal(r.jobsCalls, 0, 'nao pode ter avancado para consultar jobs sem ler a lista de runs');
  assert.match(r.out, /::error::cota da API esgotada e nao voltou dentro de \d+s/,
    'a falha tem de NOMEAR a cota; "falhei em ler a faixa" foi o que obrigou a inferir a causa');
});

test('#1923 (3) a mensagem da API aparece no log, em vez de ir para /dev/null', () => {
  const r = run('erro-permanente', { API_RETRIES: '2' });
  assert.equal(r.exit, 1, 'erro permanente continua reprovando');
  assert.match(r.out, /Bad credentials/,
    'o erro real da API tem de chegar ao log: sem ele, diagnosticar custou correlacionar 7 jobs');
  assert.match(r.out, /falhei em ler a faixa apos 2 tentativas/,
    'o caminho de erro permanente nao pode ter mudado de comportamento');
});
