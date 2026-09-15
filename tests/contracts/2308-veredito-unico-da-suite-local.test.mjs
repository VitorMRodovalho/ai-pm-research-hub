import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { parseSumario } from '../../scripts/test-verdict.mjs';

/**
 * O defeito que este guard protege (2026-09-15): `npm test` e
 * `test:structural && test:behavioural` — DOIS blocos, DOIS sumarios. Um leitor que espera
 * pelo PRIMEIRO marcador de termino le metade da suite. Aconteceu: "3673 testes, 0 falhas"
 * entrou numa mensagem de commit enquanto o bloco 2, ainda rodando, terminaria com 19 falhas.
 *
 * O CI nao sofre disso (roda os dois blocos como jobs SEPARADOS), entao o conserto e uma
 * ferramenta local: `npm run test:verdict`. `npm test` fica como esta, porque o guard do
 * #1908 exige que ele continue casando com os dois nomes.
 *
 * Os tres casos abaixo sao o defeito original, o caso feliz e o caso que me enganou DUAS
 * vezes — o bloco que morre sem reportar nada.
 */

const DUAS_SAIDAS = [
  'ℹ tests 3673', 'ℹ suites 0', 'ℹ pass 3673', 'ℹ fail 0', 'ℹ skipped 0', 'ℹ duration_ms 18321',
  'ℹ tests 3676', 'ℹ suites 0', 'ℹ pass 3649', 'ℹ fail 19', 'ℹ skipped 8', 'ℹ duration_ms 976314',
].join('\n');

test('#2308 o parser le o ULTIMO sumario, nao o primeiro — que e o defeito original', () => {
  const s = parseSumario(DUAS_SAIDAS);
  assert.equal(s.fail, 19, 'ler o primeiro sumario devolveria 0 falhas: e exatamente o erro que motivou o script');
  assert.equal(s.tests, 3676);
  assert.equal(s.skipped, 8);
});

test('#2308 um bloco que NAO reporta devolve null, e null nao e aprovacao', () => {
  // Ausencia de sumario e o terceiro estado. Um leitor que so procura "fail 0" leria o
  // silencio de um bloco morto como sucesso — foi o que aconteceu quando o behavioural
  // foi morto no meio e o log terminou sem sumario nenhum.
  assert.equal(parseSumario('rodando...\n✔ um teste\n(morreu aqui)'), null);
  assert.equal(parseSumario(''), null);
  // controle positivo: a mesma funcao ACHA quando ha o que achar
  assert.notEqual(parseSumario('ℹ tests 7\nℹ pass 7\nℹ fail 0'), null);
});

test('#2308 campos ausentes viram 0, mas `tests` ausente ainda invalida o bloco inteiro', () => {
  const s = parseSumario('ℹ tests 5\nℹ pass 5');
  assert.equal(s.fail, 0, 'sem linha de fail, conta zero');
  assert.equal(s.skipped, 0);
  assert.equal(parseSumario('ℹ pass 5\nℹ fail 0'), null,
    'sem `tests` nao da para afirmar que o bloco rodou — e null, nao um sumario com zeros');
});

test('#2308 o script existe, e declara os DOIS blocos que npm test encadeia', () => {
  const p = 'scripts/test-verdict.mjs';
  assert.ok(existsSync(p));
  const src = readFileSync(p, 'utf8');
  assert.match(src, /'test:structural'/, 'o veredito tem de cobrir o bloco estrutural');
  assert.match(src, /'test:behavioural'/, 'o veredito tem de cobrir o bloco comportamental');
  assert.match(src, /SEM SUMARIO/, 'o terceiro estado precisa aparecer na saida, nao so na logica');
  assert.match(src, /process\.exit\(2\)/, 'inconclusivo sai com codigo PROPRIO, distinto de reprovado (1)');
});

test('#2308 package.json expoe test:verdict e NAO trocou o test que o #1908 protege', () => {
  const pkg = JSON.parse(readFileSync('package.json', 'utf8'));
  assert.equal(pkg.scripts['test:verdict'], 'node scripts/test-verdict.mjs');
  // O #1908 exige que `test` continue casando com os dois nomes; trocar `test` pelo wrapper
  // quebraria aquele guard, e por isso o veredito e um script NOVO, nao uma substituicao.
  assert.match(pkg.scripts['test'], /test:structural/);
  assert.match(pkg.scripts['test'], /test:behavioural/);
});
