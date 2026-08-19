/**
 * #1850 — o mecanismo de excecao declarada, e a prova de que ele nao apaga o sinal.
 *
 * Contexto. Uma violacao de invariante mantida aberta POR DECISAO derrubava 18
 * testes do `validate`, que e required. Doze deles nem eram sobre o invariante
 * violado: usavam "0 total violations" como canario enquanto testavam outra
 * coisa. O repositorio ja tinha decidido deixar o job dedicado
 * (`check-invariants`) FORA dos required, e as asseveracoes emprestadas
 * recolocaram o mesmo sinal dentro do required, sem que ninguem escolhesse isso.
 *
 * Estes testes rodam offline. Eles guardam as tres propriedades que fazem o
 * mecanismo ser uma excecao declarada e nao um silenciador:
 *
 *   1. violacao NAO declarada continua reprovando;
 *   2. declaracao vence, e depois da data volta a reprovar;
 *   3. `INVARIANT_STRICT=1` desliga toda declaracao, e o workflow do
 *      `check-invariants` passa essa variavel.
 *
 * A terceira e a que importa mais: sem ela o mecanismo vira mudo em todo lugar.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  DECLARED_INVARIANT_EXCEPTIONS,
  unexpectedViolations,
  activeExceptions,
  staleExceptions,
  isExpired,
  strictMode,
} from '../helpers/invariant-exceptions.mjs';

const LENIENT = {};
const STRICT = { INVARIANT_STRICT: '1' };
const rowsWith = (name, count) => [{ invariant_name: name, violation_count: count }];

test('#1850: toda declaracao traz issue, data de expiracao e motivo', () => {
  assert.ok(Array.isArray(DECLARED_INVARIANT_EXCEPTIONS), 'a declaracao e uma lista');
  for (const e of DECLARED_INVARIANT_EXCEPTIONS) {
    assert.match(e.invariant, /^[A-Z][A-Za-z0-9_]+$/, `nome de invariante invalido: ${e.invariant}`);
    assert.ok(Number.isInteger(e.issue) && e.issue > 0, `${e.invariant}: issue obrigatoria`);
    assert.match(e.expires, /^\d{4}-\d{2}-\d{2}$/, `${e.invariant}: expires deve ser YYYY-MM-DD`);
    assert.ok(!Number.isNaN(Date.parse(e.expires)), `${e.invariant}: expires nao e data valida`);
    assert.ok(typeof e.reason === 'string' && e.reason.length >= 40,
      `${e.invariant}: motivo precisa explicar a decisao, nao so apontar a issue`);
  }
});

test('#1850: violacao NAO declarada continua reprovando', () => {
  const novos = rowsWith('Q_invariante_que_ninguem_declarou', 3);
  assert.equal(unexpectedViolations(novos, new Date('2026-08-19'), LENIENT).length, 1,
    'o canario tem que continuar mordendo violacao nova');
});

test('#1850: violacao declarada e tolerada ate a data, e reprova depois', () => {
  const e = DECLARED_INVARIANT_EXCEPTIONS[0];
  assert.ok(e, 'este teste pressupoe ao menos uma declaracao; se a lista zerou, remova-o');
  const rows = rowsWith(e.invariant, 1);
  const vespera = new Date(`${e.expires}T00:00:00Z`);
  vespera.setUTCDate(vespera.getUTCDate() - 1);
  const depois = new Date(`${e.expires}T00:00:00Z`);
  depois.setUTCDate(depois.getUTCDate() + 1);

  assert.equal(unexpectedViolations(rows, vespera, LENIENT).length, 0, 'vespera: tolerada');
  assert.equal(unexpectedViolations(rows, new Date(`${e.expires}T23:59:59Z`), LENIENT).length, 0,
    'o dia da expiracao inteiro ainda vale');
  assert.equal(unexpectedViolations(rows, depois, LENIENT).length, 1,
    'depois da data a violacao volta a reprovar');
  assert.equal(isExpired(e, depois), true);
  assert.equal(isExpired(e, vespera), false);
});

test('#1850: INVARIANT_STRICT=1 desliga TODA declaracao', () => {
  assert.equal(strictMode(STRICT), true);
  assert.equal(strictMode(LENIENT), false);
  for (const e of DECLARED_INVARIANT_EXCEPTIONS) {
    const rows = rowsWith(e.invariant, 1);
    assert.equal(unexpectedViolations(rows, new Date('2026-08-19'), STRICT).length, 1,
      `${e.invariant} nao pode ser tolerada em modo estrito`);
  }
  assert.equal(activeExceptions(new Date('2026-08-19'), STRICT).length, 0);
});

/**
 * O guard que sustenta o desenho. Ele examina o workflow de verdade e devolve o
 * que examinou, para nao passar por ausencia de arquivo nem por regex que nao casou.
 */
test('#1850: o workflow check-invariants roda em modo estrito', () => {
  const path = '.github/workflows/invariants-check.yml';
  const yml = readFileSync(path, 'utf8');
  const examinado = {
    arquivo: path,
    tem_step_de_contrato: /npm run test:contracts:db/.test(yml),
    tem_invariant_strict: /INVARIANT_STRICT:\s*['"]?1['"]?/.test(yml),
  };
  assert.equal(examinado.tem_step_de_contrato, true,
    `${path} precisa rodar test:contracts:db. Examinado: ${JSON.stringify(examinado)}`);
  assert.equal(examinado.tem_invariant_strict, true,
    'sem INVARIANT_STRICT=1 o job dedicado tolera a mesma violacao que o `validate`, '
    + `e o sinal honesto desaparece. Examinado: ${JSON.stringify(examinado)}`);
});

test('#1850: staleExceptions aponta a declaracao que ja pode sair', () => {
  const e = DECLARED_INVARIANT_EXCEPTIONS[0];
  assert.ok(e);
  const limpo = [{ invariant_name: e.invariant, violation_count: 0 }];
  const sujo = rowsWith(e.invariant, 1);
  const vespera = new Date(`${e.expires}T00:00:00Z`);
  vespera.setUTCDate(vespera.getUTCDate() - 1);
  assert.equal(staleExceptions(limpo, vespera).length, 1, 'sem violacao viva, a entrada esta madura para sair');
  assert.equal(staleExceptions(sujo, vespera).length, 0, 'com violacao viva, a entrada segue necessaria');
});
