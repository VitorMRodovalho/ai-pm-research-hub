// tests/contracts/1910-o-diagnostico-de-ddl-lag-chega-ao-resumo.test.mjs
// Register in BOTH the "test:structural" and "test:contracts" whitelists in package.json (#1109).
/**
 * #1910: o diagnóstico de DDL-lag chega ao RESUMO do job, em vez de morrer no log bruto.
 *
 * O que esta mudança NÃO é. O caminho decidido era "fazer o guard distinguir os dois casos", e a
 * medição mostrou que isso já existia: `tests/helpers/migration-drift-classifier.mjs` separa
 * phantom / prod-ahead / genuine, e o texto diz literalmente "This is NOT drift you authored".
 * Ele até chegou ao log da rodada que a lane viu (run 33263394017).
 *
 * O gargalo era SUPERFÍCIE, não diagnóstico. Medido no check-run daquele commit: `output.title` e
 * `output.summary` vazios. Na interface da PR a lane via "check-invariants failure" e mais nada.
 * Para achar o bloco PROD-AHEAD era preciso abrir a rodada, achar o job e rolar o log. Por isso a
 * lane tentou 4x: nunca viu o texto.
 *
 * E um defeito pior apareceu no caminho: o passo "Summarize result" escrevia
 * ":white_check_mark: Invariants verified against live DB" MESMO COM O JOB VERMELHO, porque só
 * ramificava na existência do secret. Um resumo que afirma sucesso no vermelho é pior do que
 * resumo nenhum.
 *
 * Cross-ref: #1910, ADR-0097, `migration-drift-classifier.mjs` (que produz o texto citado).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';

const ROOT = process.cwd();
const WF = readFileSync(resolve(ROOT, '.github/workflows/invariants-check.yml'), 'utf8');

test('#1910: o resumo ramifica no RESULTADO do teste, não só na existência do secret', () => {
  assert.match(WF, /steps\.invariants\.outcome/,
    'sem ler o outcome do passo, o resumo volta a afirmar sucesso no vermelho');
  assert.match(WF, /id:\s*invariants/, 'o passo do teste precisa de id para o outcome ser legível');
  const posFalha = WF.indexOf('Invariantes reprovaram');
  const posSucesso = WF.indexOf('Invariants verified against live DB');
  assert.ok(posFalha > -1, 'não há ramo de falha no resumo');
  assert.ok(posFalha < posSucesso,
    'o ramo de falha tem de vir ANTES do de sucesso, senão o elif nunca é alcançado');
});

test('#1910: o bloco PROD-AHEAD sobe para o resumo, com a saída nomeada', () => {
  assert.match(WF, /grep -q 'PROD-AHEAD'/,
    'o resumo precisa detectar o caso de DDL-lag na saída do teste');
  assert.match(WF, /NAO e defeito desta PR/,
    'a mensagem tem de dizer explicitamente que provavelmente não é defeito de quem lê');
  assert.match(WF, /db:types[^\n]*\*\*nao\*\* resolve/i,
    'precisa desmentir a saída errada, que é a que a lane tentou 4x');
  assert.match(WF, /rebaseie na/i, 'precisa nomear a saída que resolve');
  assert.match(WF, /Testes que reprovaram/, 'o resumo precisa listar os testes que reprovaram');
});

test('#1910: a saída do teste é capturada sem engolir o código de saída', () => {
  // `npm test | tee` devolve o status do `tee`, não o da suíte: sem `pipefail` o job ficaria
  // VERDE com teste vermelho. Armadilha registrada em
  // `reference-pipe-engole-o-codigo-de-saida-da-suite`.
  assert.match(WF, /set -o pipefail/,
    'sem pipefail o tee engole a falha e o job fica verde com a suíte vermelha');
  assert.match(WF, /tee \/tmp\/invariants-output\.txt/,
    'a saída precisa ser guardada para poder ser citada');
});

test('#1910: o texto citado é PRODUZIDO pelo classificador, não reescrito aqui', () => {
  // Se o resumo reescrevesse a mensagem, ela divergiria do classificador na primeira mudança, e
  // aí existiriam duas verdades sobre o mesmo defeito.
  const clf = readFileSync(resolve(ROOT, 'tests/helpers/migration-drift-classifier.mjs'), 'utf8');
  assert.match(clf, /PROD-AHEAD/,
    'o classificador é a fonte do texto; se ele parar de emitir PROD-AHEAD, o grep do resumo fica mudo');
  assert.match(clf, /not authored drift/,
    'o banner de prod-ahead precisa manter a formulação que o resumo cita');
});

test('#1910: o parsing do resumo casa com o reporter REAL, nos DOIS formatos que existem', () => {
  // ESTE É O TESTE QUE IMPORTA, e o que me pegou ao escrever esta PR.
  //
  // Escrevi `grep -E '^not ok '` supondo que `node --test` emitisse TAP quando a saída vai para um
  // pipe. No meu Node 24 ele NÃO emite: o reporter é `spec` sempre, com marcador de falha e ANSI.
  // O grep saía MUDO, e o resumo mostraria um bloco vazio, ou seja, o mesmo defeito de #1910 numa
  // roupa nova.
  //
  // E a correção ingênua (trocar por um padrão só do `spec`) teria sido pior ainda, porque a CI
  // roda Node 22, onde a saída em pipe É TAP. Medido em 29/08: v22.23.2 na CI, v24.15.0 local.
  // Um padrão que só casa um dos dois sai mudo justamente onde importa.
  //
  // Um regex sobre o YAML não pega nada disso: o comando estaria lá, bem-formado e mudo. Então
  // aqui eu EXECUTO o parsing do workflow contra saídas de verdade, nos dois formatos.
  const sed = WF.match(/sed 's\/[^']*'\s+\/tmp\/invariants-output\.txt/);
  assert.ok(sed, 'não achei a normalização de ANSI no workflow');

  // A extração é ancorada na SEÇÃO, não no conteúdo do padrão: ancorada no literal, trocar o
  // padrão por um mudo reprovaria pelo motivo errado ("não achei o comando") em vez do certo
  // ("o comando não extrai nada").
  const secao = WF.split('Testes que reprovaram')[1] || '';
  const extrator = secao.match(/(grep -E '[^']*'|awk '[^']*')/);
  assert.ok(extrator, 'não achei a extração do bloco de reprovados no workflow');

  const tmp = mkdtempSync(join(tmpdir(), 'guard-1910-'));
  try {
    const fixture = join(tmp, 'reprova.test.mjs');
    writeFileSync(fixture,
      "import test from 'node:test'; import assert from 'node:assert/strict';\n" +
      "test('invariante inventada para o guard', () => assert.equal(1, 2));\n");

    // `NODE_TEST_CONTEXT` precisa sair do ambiente: herdado do runner pai, ele troca o reporter do
    // filho por um formato interno, e a fixture "não reprova" (aconteceu ao escrever isto).
    const env = { ...process.env };
    delete env.NODE_TEST_CONTEXT;
    delete env.NODE_OPTIONS;

    const sedExpr = sed[0].replace(/\s+\/tmp\/invariants-output\.txt$/, '');

    const cenarios = [
      { nome: 'reporter padrao desta maquina', args: ['--test', fixture] },
      { nome: 'tap, que e o da CI no Node 22', args: ['--test', '--test-reporter=tap', fixture] },
    ];

    for (const c of cenarios) {
      const raw = spawnSync(process.execPath, c.args, { encoding: 'utf8', env });
      const bruto = (raw.stdout || '') + (raw.stderr || '');
      assert.ok(/invariante inventada/.test(bruto),
        `[${c.nome}] a fixture não reprovou; o teste não mede nada`);

      const out = spawnSync('bash', ['-c', `${sedExpr} | ${extrator[1]}`],
        { input: bruto, encoding: 'utf8' }).stdout || '';

      assert.ok(out.trim().length > 0,
        `[${c.nome}] o parsing do resumo saiu VAZIO contra a saída real do reporter, que é o defeito de #1910 de novo`);
      assert.doesNotMatch(out, /\[/,
        `[${c.nome}] sobrou código ANSI: o resumo em markdown sairia com lixo`);
    }
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
});
