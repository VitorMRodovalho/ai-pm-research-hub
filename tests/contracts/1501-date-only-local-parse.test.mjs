/**
 * Contract: #1501 — coluna `date` do Postgres nunca pode ser parseada como instante UTC.
 *
 * `new Date('2026-07-27')` segue a regra ES para ISO date-only e devolve MEIA-NOITE UTC.
 * Em fuso negativo (Brasil, UTC-3) isso retrocede um dia ao formatar ou comparar local:
 * o quadro exibia `target_date = 2026-07-27` como "26 de jul." e marcava atraso a partir
 * das 21h do dia ANTERIOR ao vencimento (~27h de falso atraso, em vermelho).
 *
 * Verificado em 2026-07-28 contra dado vivo: atividade com target_date 2026-07-27
 * renderizada como "26 de jul."; card com due_date 2026-08-03 exibindo "02 de ago." no
 * kanban e "03/08/2026" no modal, ou seja duas datas para o mesmo registro.
 *
 * NOTA de método (1): as asserções de comportamento são INDEPENDENTES DE FUSO. Elas
 * afirmam que o componente Y/M/D sobrevive ao parse, propriedade que a implementação
 * antiga violava em qualquer offset negativo e que a nova satisfaz em todos. Assim o
 * teste não depende do TZ da máquina de CI.
 *
 * NOTA de método (2): o fonte é lido SEM COMENTÁRIOS. Os comentários deste fix citam
 * `new Date` e os nomes das colunas, e um regex ingênuo casaria com a prosa.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const HELPER = resolve(ROOT, 'src/lib/date-only.ts');
const BOARD_DIR = resolve(ROOT, 'src/components/board');
const CONSUMERS = [
  'BoardKanban.tsx',
  'BoardActivitiesView.tsx',
  'TableView.tsx',
  'CalendarView.tsx',
  'TimelineView.tsx',
  'CardDetail.tsx',
];
const DATE_COLUMNS = ['due_date', 'target_date', 'baseline_date', 'forecast_date', 'actual_completion_date'];

function stripComments(src) {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/[^\n]*/g, '$1');
}

function readCode(file) {
  const p = resolve(BOARD_DIR, file);
  assert.ok(existsSync(p), `deve existir: ${p}`);
  return stripComments(readFileSync(p, 'utf8'));
}

// ── Comportamento do helper (sem depender do fuso da máquina) ────────────────

// Importa o .ts direto: a suíte roda com --experimental-strip-types.
const { parseDateOnly, formatDateOnly, isOverdueDateOnly } = await import(HELPER);

test('1501: parseDateOnly preserva ano/mes/dia em QUALQUER fuso', () => {
  const d = parseDateOnly('2026-07-27');
  assert.equal(d.getFullYear(), 2026);
  assert.equal(d.getMonth(), 6, 'julho');
  assert.equal(d.getDate(), 27, 'o dia nao pode retroceder');
  // A implementacao antiga falhava exatamente aqui em offset negativo.
  assert.equal(new Date('2026-07-27').getTime() === d.getTime(), new Date().getTimezoneOffset() === 0,
    'so coincide com o parse UTC quando a maquina esta em UTC');
});

test('1501: formatDateOnly imprime o mesmo dia que veio do banco', () => {
  assert.equal(formatDateOnly('2026-08-03', { day: '2-digit', month: '2-digit', year: 'numeric' }), '03/08/2026');
  assert.equal(formatDateOnly('2026-07-27', { day: '2-digit', month: '2-digit', year: 'numeric' }), '27/07/2026');
});

test('1501: formatDateOnly tolera nulo sem quebrar a celula', () => {
  for (const v of [null, undefined, '']) assert.equal(formatDateOnly(v), '');
});

test('1501: o que vence hoje NAO esta atrasado', () => {
  const venceHoje = '2026-07-27';
  assert.equal(isOverdueDateOnly(venceHoje, new Date(2026, 6, 27, 0, 0, 1)), false, 'nem a 00:00:01');
  assert.equal(isOverdueDateOnly(venceHoje, new Date(2026, 6, 27, 23, 59, 59)), false, 'nem no ultimo minuto');
  assert.equal(isOverdueDateOnly(venceHoje, new Date(2026, 6, 26, 21, 0, 0)), false,
    'nem as 21h da vespera, que era o inicio do falso atraso');
});

test('1501: atraso comeca depois de virar o dia local', () => {
  assert.equal(isOverdueDateOnly('2026-07-27', new Date(2026, 6, 28, 0, 0, 1)), true);
  assert.equal(isOverdueDateOnly(null), false, 'sem data nao ha atraso');
});

// ── Consumidores ────────────────────────────────────────────────────────────

test('1501: nenhum componente de board parseia coluna date com new Date()', () => {
  for (const file of CONSUMERS) {
    const code = readCode(file);
    for (const col of DATE_COLUMNS) {
      const re = new RegExp(`new Date\\(\\s*[A-Za-z_$][\\w$]*\\.${col}`);
      assert.doesNotMatch(code, re,
        `${file}: ${col} e coluna date e nao pode passar por new Date() (#1501)`);
    }
  }
});

test('1501: os consumidores importam o helper compartilhado', () => {
  for (const file of CONSUMERS) {
    assert.match(readCode(file), /from\s+'\.\.\/\.\.\/lib\/date-only'/,
      `${file} deve usar src/lib/date-only`);
  }
});

test('1501: a marcacao de atraso usa fim do dia, nao comparacao crua', () => {
  for (const file of ['BoardKanban.tsx', 'BoardActivitiesView.tsx']) {
    const code = readCode(file);
    assert.match(code, /isOverdueDateOnly\(/, `${file} deve usar isOverdueDateOnly`);
    // Restrito as colunas `date`: para timestamptz (curation_due_at) comparar contra
    // `new Date()` e o comportamento CORRETO e nao pode ser proibido aqui.
    for (const col of DATE_COLUMNS) {
      assert.doesNotMatch(code, new RegExp(`\\.${col}[^;\\n]*<\\s*new Date\\(\\)`),
        `${file}: ${col} e coluna date e nao pode ser comparada crua contra agora (#1501)`);
    }
  }
});

test('1501: timestamptz continua com new Date(), que e o tratamento correto', () => {
  // completed_at/curation_due_at carregam instante+offset: converter e o comportamento
  // certo, e aplicar parseDateOnly neles seria a regressao inversa.
  const code = readCode('BoardActivitiesView.tsx');
  assert.match(code, /new Date\(a\.completed_at\)/,
    'completed_at e timestamptz e deve seguir em new Date()');
});
