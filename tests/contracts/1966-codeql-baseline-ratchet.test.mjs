// tests/contracts/1966-codeql-baseline-ratchet.test.mjs
// Register in BOTH the "test" and "test:contracts" whitelists in package.json (#1109).
/**
 * #1966 — o ratchet da linha de base do CodeQL.
 *
 * `CodeQL Analysis` roda, reporta e NAO segura nada. Medido em 24/08/2026: 101 alertas
 * abertos, 55 ALTOS, o mais antigo de 08/03 — quase seis meses sem um fechamento por
 * conserto deliberado (a #1958 foi o primeiro). Check que avisa e nao segura vira ruido.
 *
 * Este arquivo NAO chama a API: ele trava a FORMA da base e o wiring do guard. Quem mede
 * o mundo vivo e `.github/workflows/codeql-baseline.yml`, que roda com token. A divisao e
 * deliberada — um teste que precisasse de token viraria skip em toda rodada local, e
 * "skip ≡ pass" e como um ratchet morre sem ninguem notar.
 *
 * Cross-ref: #1966, #1958 (o ALTO real que atravessou o merge porque o check nao segura),
 * #938 e p175 (o mesmo padrao baseline+ratchet ja usado no repo).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const BASE_PATH = resolve(ROOT, 'docs/audit/CODEQL_ALERT_BASELINE_1966.tsv');
const WF_PATH = resolve(ROOT, '.github/workflows/codeql-baseline.yml');
const SCRIPT_PATH = resolve(ROOT, 'scripts/codeql-baseline-check.mjs');

const base = existsSync(BASE_PATH) ? readFileSync(BASE_PATH, 'utf8') : '';
const wf = existsSync(WF_PATH) ? readFileSync(WF_PATH, 'utf8') : '';
const script = existsSync(SCRIPT_PATH) ? readFileSync(SCRIPT_PATH, 'utf8') : '';

function linhas() {
  return base.split('\n').filter((l) => l && !l.startsWith('#')).map((l) => {
    const [n, sev, rule, path] = l.split('\t');
    return { n: Number(n), sev, rule, path };
  });
}

test('#1966: a base existe e o cabeçalho declara o mesmo total que as linhas somam', () => {
  assert.ok(base, 'docs/audit/CODEQL_ALERT_BASELINE_1966.tsv existe');
  const ls = linhas();
  const declarado = Number(base.match(/^# TOTAL_ABERTOS=(\d+)$/m)?.[1]);
  const chaves = Number(base.match(/^# TOTAL_CHAVES=(\d+)$/m)?.[1]);
  const altos = Number(base.match(/^# TOTAL_ALTOS=(\d+)$/m)?.[1]);
  assert.equal(ls.reduce((s, l) => s + l.n, 0), declarado, 'TOTAL_ABERTOS bate com a soma das linhas');
  assert.equal(ls.length, chaves, 'TOTAL_CHAVES bate com o número de linhas');
  assert.equal(ls.filter((l) => l.sev === 'high').reduce((s, l) => s + l.n, 0), altos, 'TOTAL_ALTOS bate');
});

test('#1966: toda linha é bem formada e a chave é rule+caminho (não número de alerta)', () => {
  const ls = linhas();
  assert.ok(ls.length > 0, 'a base não está vazia');
  for (const l of ls) {
    assert.ok(Number.isInteger(l.n) && l.n > 0, `contagem inteira positiva: ${JSON.stringify(l)}`);
    assert.match(l.rule, /^[a-z]+\/[a-z0-9-]+$/, `rule.id no formato do CodeQL: ${l.rule}`);
    assert.ok(l.path && !l.path.startsWith('/'), `caminho relativo ao repo: ${l.path}`);
    assert.ok(['high', 'medium', 'low', 'warning', 'error', 'note'].includes(l.sev), `severidade conhecida: ${l.sev}`);
  }
  // chave única: duas linhas para o mesmo (rule, path) tornariam a contagem ambígua
  const chaves = ls.map((l) => `${l.rule}\t${l.path}`);
  assert.equal(new Set(chaves).size, chaves.length, 'nenhuma chave (rule, caminho) repetida');
});

test('#1966: a base está ORDENADA — senão o diff de um conserto vira ruído', () => {
  const chaves = linhas().map((l) => `${l.rule}\t${l.path}`);
  assert.deepEqual(chaves, [...chaves].sort((a, b) => a.localeCompare(b)),
    'linhas em ordem estável; `--write` reordena, então uma base fora de ordem foi editada à mão');
});

test('#1966: o guard RECUSA rodar sem token — skip aqui seria verde por vacuidade', () => {
  assert.ok(script, 'scripts/codeql-baseline-check.mjs existe');
  assert.match(script, /if \(!TOKEN\)[\s\S]{0,200}process\.exit\(1\)/,
    'sem token o script sai != 0 em vez de passar');
});

test('#1966: zero alerta num ref só conta COM análise — a ambiguidade é tratada', () => {
  // `refs/pull/N/merge` devolveu 0 alertas COM análise existente enquanto a main tinha 101:
  // zero pode ser "limpo" ou "não medido", e confundir os dois é o defeito clássico.
  assert.match(script, /code-scanning\/analyses/, 'o script consulta as análises do ref');
  assert.match(script, /NAO MEDIDO/, 'e distingue "não medido" de "limpo" na mensagem');
});

test('#1966: `--write` só ENCOLHE — nunca congela achado novo', () => {
  assert.match(script, /--write[\s\S]{0,400}novas\.length \|\| cresceram\.length[\s\S]{0,200}process\.exit\(1\)/,
    'com achado novo, --write recusa em vez de silenciar');
});

test('#1966: o script lê TODAS as páginas e recusa truncar', () => {
  // sem --paginate a API devolve 23 de 101 e nada sinaliza truncamento: foi assim que este
  // backlog foi reportado como "4 altos" duas vezes no mesmo dia.
  assert.match(script, /per_page=100&page=\$\{page\}/, 'pagina explicitamente');
  assert.match(script, /recuse em vez de truncar em silencio/, 'e falha alto se estourar o limite de páginas');
});

test('#1966: o workflow roda com permissão de leitura de alertas e chama o guard', () => {
  assert.ok(wf, '.github/workflows/codeql-baseline.yml existe');
  assert.match(wf, /security-events:\s*read/, 'permissão para ler code scanning');
  assert.match(wf, /node scripts\/codeql-baseline-check\.mjs/, 'chama o guard');
  assert.match(wf, /branches:\s*\[main\]/, 'roda no push para a main');
});

test('#1966: o workflow NÃO roda em pull_request, e o motivo está escrito', () => {
  // Medido: o ref de PR carrega o que a PR INTRODUZ, não o conjunto inteiro. Comparar com a
  // base (que é do conjunto inteiro) passaria a impressão de medir e erraria em silêncio.
  // Se alguém ligar `pull_request` aqui sem resolver a semântica, este guard reprova antes.
  assert.doesNotMatch(wf, /^\s*pull_request:/m,
    'gate no nível da PR é decisão de CONFIGURAÇÃO do repo (limiar do check nativo), não deste workflow');
  assert.match(wf, /INTRODUZ, nao o conjunto inteiro/,
    'o motivo da ausência está escrito no arquivo, para não ser "corrigido" por engano');
});
