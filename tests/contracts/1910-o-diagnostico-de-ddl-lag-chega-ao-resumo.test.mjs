// tests/contracts/1910-o-diagnostico-de-ddl-lag-chega-ao-resumo.test.mjs
// Register in BOTH the "test:structural" and "test:contracts" whitelists in package.json (#1109).
/**
 * #1910 — o diagnóstico de DDL-lag chega ao resumo do job, em vez de morrer no log bruto.
 *
 * ⚠️ O QUE ESTA MUDANÇA **NÃO** É. O caminho decidido pelo PM (29/08) era "fazer o guard distinguir
 * os dois casos" — e a medição mostrou que **isso já existia**:
 * `tests/helpers/migration-drift-classifier.mjs` separa phantom / prod-ahead / genuine, e o texto
 * diz literalmente *"This is NOT drift you authored"*. Ele até chegou ao log da rodada que a lane
 * viu (run 33263394017).
 *
 * O gargalo era **superfície**, não diagnóstico. Medido no check-run daquele commit:
 * `output.title` e `output.summary` vazios — na interface da PR a lane via
 * "check-invariants — failure" e mais nada. Para achar o bloco PROD-AHEAD era preciso abrir a
 * rodada, achar o job e rolar o log. Por isso a lane tentou 4x: **nunca viu o texto**.
 *
 * ⚠️ E UM DEFEITO PIOR APARECEU NO CAMINHO: o passo "Summarize result" escrevia
 * ":white_check_mark: Invariants verified against live DB" **mesmo com o job vermelho** — ele só
 * ramificava na existência do secret, nunca no resultado do teste. Um resumo que afirma sucesso no
 * vermelho é pior do que resumo nenhum.
 *
 * Cross-ref: #1910, ADR-0097, e `migration-drift-classifier.mjs` (que produz o texto que este
 * resumo agora cita).
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
  // O ramo de sucesso não pode ser o único caminho não-skip.
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
  assert.match(WF, /db:types.*nao.*resolve/i,
    'precisa desmentir a saída errada, que é o que a lane tentou 4x');
  assert.match(WF, /rebaseie na/i, 'precisa nomear a saída que resolve');
});

test('#1910: o parsing do resumo casa com o reporter REAL, não com um formato imaginado', () => {
  // ⚠️ ESTE É O TESTE QUE IMPORTA, e o que me pegou ao escrever esta PR.
  // Eu tinha escrito `grep -E '^not ok '` supondo que `node --test` emitisse TAP quando a saída
  // vai para um pipe. **Não emite**: no Node 24 o reporter é `spec` sempre, com marcador `✖` e
  // códigos ANSI. O grep saía MUDO, e o resumo mostraria um bloco vazio — ou seja, o mesmo
  // defeito de #1910 (o diagnóstico não chega a quem lê), só que numa roupa nova.
  //
  // Um regex sobre o YAML não pega isso: o comando estaria lá, bem-formado, e mudo.
  // Então aqui eu EXECUTO o parsing que o workflow usa, contra uma saída de verdade.
  const sed = WF.match(/sed 's\/[^']*'\s+\/tmp\/invariants-output\.txt/);
  assert.ok(sed, 'não achei a normalização de ANSI no workflow');
  // A extração é ancorada na SEÇÃO ("Testes que reprovaram"), não no conteúdo do padrão: se eu
  // ancorasse no literal `failing tests`, trocar o padrão por um mudo faria o teste reprovar pelo
  // motivo errado ("não achei o comando") em vez do certo ("o comando não extrai nada").
  const secao = WF.split('Testes que reprovaram')[1] || '';
  const awkCmd = secao.match(/awk '([^']*)'/);
  assert.ok(awkCmd, 'não achei a extração do bloco de reprovados no workflow');

  const tmp = mkdtempSync(join(tmpdir(), 'guard-1910-'));
  try {
    const fixture = join(tmp, 'reprova.test.mjs');
    writeFileSync(fixture,
      "import test from 'node:test'; import assert from 'node:assert/strict';\n" +
      "test('invariante inventada para o guard', () => assert.equal(1, 2));\n");
    // stdio 'pipe' => stdout NÃO é TTY, exatamente como no runner do CI.
    // ⚠️ `NODE_TEST_CONTEXT` precisa sair do ambiente: herdado do runner pai, ele troca o reporter
    // do filho por um formato interno, e a fixture "não reprova" (foi o que aconteceu aqui).
    const env = { ...process.env };
    delete env.NODE_TEST_CONTEXT;
    delete env.NODE_OPTIONS;
    const raw = spawnSync(process.execPath, ['--test', fixture], { encoding: 'utf8', env });
    const bruto = (raw.stdout || '') + (raw.stderr || '');
    assert.ok(/invariante inventada/.test(bruto), 'a fixture não reprovou; o teste não mede nada');

    // roda o MESMO par sed|awk que o workflow roda
    const sedExpr = sed[0].replace(/\s+\/tmp\/invariants-output\.txt$/, '');
    const out = spawnSync('bash', ['-c', `${sedExpr} | awk '${awkCmd[1]}'`],
      { input: bruto, encoding: 'utf8' }).stdout || '';

    assert.ok(out.trim().length > 0,
      'o parsing do resumo saiu VAZIO contra a saída real do reporter — é o defeito de #1910 de novo');
    assert.match(out, /invariante inventada/,
      'o bloco extraído não nomeia o teste que reprovou, então não diagnostica nada');
    assert.doesNotMatch(out, /\u001b\[/, 'sobrou código ANSI: o resumo em markdown sairia com lixo');
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
});

test('#1910: a saída do teste é capturada sem engolir o código de saída', () => {
  // `npm test | tee` devolve o status do `tee`, não o da suíte: sem `pipefail` o job ficaria
  // VERDE com teste vermelho. É a armadilha registrada em
  // `reference-pipe-engole-o-codigo-de-saida-da-suite`.
  assert.match(WF, /set -o pipefail/,
    'sem pipefail o tee engole a falha e o job fica verde com a suíte vermelha');
  assert.match(WF, /tee \/tmp\/invariants-output\.txt/, 'a saída precisa ser guardada para ser citada');
  assert.match(WF, /failing tests/,
    'o resumo precisa listar os testes que reprovaram');
});

test('#1910: o texto citado é PRODUZIDO pelo classificador, não reescrito aqui', () => {
  // Se o resumo reescrevesse a mensagem, ela divergiria do classificador na primeira mudança —
  // e aí existiriam duas verdades sobre o mesmo defeito.
  const clf = readFileSync(resolve(ROOT, 'tests/helpers/migration-drift-classifier.mjs'), 'utf8');
  assert.match(clf, /PROD-AHEAD/,
    'o classificador é a fonte do texto; se ele parar de emitir PROD-AHEAD, o grep do resumo fica mudo');
  // ⚠️ A frase vive PARTIDA entre duas linhas do template (`NOT drift you\n` + `authored`), então
  // um regex pela frase inteira não casa — foi o que me pegou ao escrever este teste. Afirmo o
  // trecho contíguo que existe, e a variante da linha 179, que é a que o banner emite.
  assert.match(clf, /NOT drift you/,
    'a frase que carrega o diagnóstico saiu do classificador — o resumo apenas a eleva');
  assert.match(clf, /not authored drift/,
    'o banner de prod-ahead precisa manter a formulação que o resumo cita');
});
