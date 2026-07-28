/**
 * Contract: #1511 — nenhuma coluna `date` do Postgres pode ser parseada por
 * `new Date()` cru em NENHUM lugar do repo (o guard do #1501 cobria só
 * `src/components/board/`).
 *
 * Os dois defeitos são os do #1501: `new Date('2026-07-27')` devolve MEIA-NOITE UTC,
 * o que (a) recua um dia ao formatar em fuso negativo e (b) marca atraso a partir das
 * 21h da véspera em UTC-3. Medido em 2026-07-28 fora do board: 24 sítios crus em 14
 * arquivos (widget de tarefas, widget de cards, kanban de tribo, board de publicações,
 * filtro de board, atas, dashboard de capítulo, fila de filiação, pipeline de parceiros,
 * perfil, publicações, admin de seleção, RSS).
 *
 * NOTA de método (1): as asserções de comportamento são INDEPENDENTES DE FUSO — afirmam
 * que o componente Y/M/D sobrevive ao parse, propriedade que o parse UTC violava em
 * qualquer offset negativo. Assim o teste não depende do TZ da máquina de CI.
 *
 * NOTA de método (2): o fonte é lido SEM COMENTÁRIOS. Os comentários deste fix citam
 * `new Date` e nomes de coluna, e um regex ingênuo casaria com a prosa.
 *
 * LIMITE CONHECIDO (declarado de propósito): `information_schema` não é exposto via
 * PostgREST, então a lista de colunas abaixo é um retrato medido, não derivado em
 * runtime. Coluna `date` NOVA não entra no guard sozinha. Para re-medir:
 *   SELECT table_name, column_name FROM information_schema.columns
 *   WHERE table_schema='public' AND data_type='date' ORDER BY 1,2;
 * (41 tabelas/views tinham ao menos uma em 2026-07-28.)
 *
 * FORMA ACEITA como alternativa ao helper: concatenar hora explícita
 * (`new Date(col + 'T12:00:00')`). É correta e existia antes do helper em 19 sítios;
 * este guard não a proíbe, só proíbe o parse cru. Centralizá-la é higiene de
 * duplicação, registrada no #1511 como fora de escopo.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const HELPER = resolve(ROOT, 'src/lib/date-only.ts');

// Colunas `date` do schema public (information_schema, 2026-07-28). `date` (events,
// cost_entries, revenue_entries) entra sem sufixo de propósito: é o nome de coluna que
// mais aparece em template de tela.
const DATE_COLUMNS = [
  'acceptance_date', 'actual_completion_date', 'anchor_date', 'application_date',
  'baseline_date', 'birth_date', 'close_date', 'cohort_month', 'cpmai_certified_at',
  'cycle_end', 'cycle_start', 'date', 'due_date', 'end_date', 'first_date',
  'follow_up_date', 'forecast_date', 'holiday_date', 'last_date', 'meeting_date',
  'membership_expires_on', 'metric_date', 'nucleo_contract_end', 'nucleo_contract_start',
  'open_date', 'partnership_date', 'partnership_end', 'partnership_start',
  'presentation_date', 'publication_date', 'report_month', 'retention_until',
  'review_deadline', 'service_first_start_date', 'service_latest_end_date',
  'session_date', 'snapshot_date', 'start_date', 'submission_date', 'target_date',
  'work_created_on',
];

// Sítios corrigidos no #1511: cada um tem de continuar importando o helper. Se um
// arquivo sai da lista sem que o parse volte, o teste acusa — o objetivo é que o
// helper não seja silenciosamente substituído por uma cópia local do mesmo cálculo.
const CONSUMERS = [
  'src/hooks/useBoardFilters.ts',
  'src/components/boards/TribeKanbanIsland.tsx',
  'src/components/boards/PublicationsBoardIsland.tsx',
  'src/components/chapter/ChapterDashboard.tsx',
  'src/components/islands/PartnerPipelineIsland.tsx',
  'src/components/meetings/MeetingsPage.tsx',
  'src/components/workspace/MyCardsWidget.tsx',
  'src/components/workspace/MyTasksIsland.tsx',
  'src/components/admin/AffiliationQueueIsland.tsx',
  'src/pages/publications/feed.xml.ts',
  'src/pages/profile.astro',
  'src/pages/publications.astro',
  'src/pages/admin/selection.astro',
];

function stripComments(src) {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/[^\n]*/g, '$1');
}

function sourceFiles() {
  const out = execSync(
    "git ls-files 'src/*.ts' 'src/*.tsx' 'src/*.astro' 'src/*.js' 'supabase/functions/*.ts'",
    { encoding: 'utf8', cwd: ROOT },
  );
  return out.trim().split('\n').filter(Boolean);
}

function read(file) {
  return stripComments(readFileSync(resolve(ROOT, file), 'utf8'));
}

// ── Comportamento dos helpers novos (sem depender do fuso da máquina) ────────

const { daysUntilDateOnly, isDateOnlyString } = await import(HELPER);

test('1511: daysUntilDateOnly conta DIAS DE CALENDARIO, nao instantes', () => {
  // Qualquer hora dentro do dia do vencimento devolve 0 — a conta antiga
  // (ceil((UTCmidnight - now)/86400000)) devolvia -1 depois das 21h em UTC-3.
  for (const h of [0, 9, 21, 23]) {
    assert.equal(daysUntilDateOnly('2026-07-28', new Date(2026, 6, 28, h, 30)), 0,
      `${h}h do proprio dia nao pode contar como dia vencido`);
  }
  assert.equal(daysUntilDateOnly('2026-07-28', new Date(2026, 6, 27, 21, 0)), 1, 'vespera as 21h');
  assert.equal(daysUntilDateOnly('2026-07-28', new Date(2026, 6, 29, 0, 1)), -1, 'dia seguinte');
  assert.equal(daysUntilDateOnly('2026-08-27', new Date(2026, 6, 28, 12, 0)), 30, 'um mes a frente');
  assert.equal(daysUntilDateOnly(null), null, 'sem data nao ha contagem');
});

test('1511: daysUntilDateOnly atravessa a virada do horario de verao sem perder um dia', () => {
  // A subtração é feita em UTC sobre os componentes Y/M/D; se fosse feita em
  // milissegundos locais, uma janela com mudança de offset perderia/ganharia um dia.
  assert.equal(daysUntilDateOnly('2026-11-30', new Date(2026, 9, 31, 12, 0)), 30);
  assert.equal(daysUntilDateOnly('2026-03-01', new Date(2026, 1, 1, 12, 0)), 28);
});

test('1511: isDateOnlyString separa coluna date de instante', () => {
  assert.equal(isDateOnlyString('2026-07-28'), true);
  assert.equal(isDateOnlyString('2026-07-28T00:00:00Z'), false, 'instante nao e coluna date');
  assert.equal(isDateOnlyString('2026-07-28 13:11:54+00'), false, 'timestamptz do Postgres');
  for (const v of [null, undefined, 42, new Date()]) assert.equal(isDateOnlyString(v), false);
});

// ── Guard repo-wide ─────────────────────────────────────────────────────────

test('1511: nenhum arquivo parseia coluna `date` com new Date() cru', () => {
  const violations = [];
  for (const file of sourceFiles()) {
    const code = read(file);
    for (const col of DATE_COLUMNS) {
      // Aceita quebra de linha dentro da chamada; a forma com hora concatenada
      // (`col + 'T12:00:00'`) é correta e sai da conta.
      const re = new RegExp(`new Date\\(\\s*([^()]*?\\.${col}\\b[^()]*?)\\)`, 'g');
      let m;
      while ((m = re.exec(code))) {
        const arg = m[1];
        if (/\+\s*['"`]T/.test(arg)) continue;
        const line = code.slice(0, m.index).split('\n').length;
        violations.push(`${file}:${line} — new Date(${arg.trim().slice(0, 70)})`);
      }
    }
  }
  assert.deepEqual(violations, [],
    'coluna `date` parseada como instante UTC (#1501/#1511) — use src/lib/date-only ' +
    `(parseDateOnly / formatDateOnly / isOverdueDateOnly / daysUntilDateOnly):\n${violations.join('\n')}`);
});

test('1511: os sitios corrigidos seguem no helper compartilhado', () => {
  for (const file of CONSUMERS) {
    assert.match(read(file), /from\s+'(\.\.\/)+lib\/date-only'/,
      `${file} deve importar src/lib/date-only em vez de recalcular o parse`);
  }
});

test('1511: superficie de familia MISTA mantem o discriminador', () => {
  // Dois lugares recebem coluna `date` E timestamptz no mesmo campo. Sem o
  // discriminador, um dos dois lados fica errado — inclusive na direção inversa
  // (aplicar parse date-only em instante troca o dia em fuso negativo).
  for (const file of ['src/pages/admin/selection.astro', 'src/components/admin/AffiliationQueueIsland.tsx']) {
    const code = read(file);
    assert.match(code, /isDateOnlyString\(/, `${file} deve discriminar as duas familias`);
    assert.match(code, /new Date\(raw\)|Date\.parse\(raw\)/,
      `${file} deve preservar o parse de INSTANTE no ramo do timestamptz`);
  }
});

test('1511: timestamptz continua em new Date(), que e o tratamento correto', () => {
  // A regressão inversa: aplicar o helper em created_at/completed_at, que carregam
  // instante + offset, deslocaria o dia em vez de corrigi-lo.
  assert.match(read('src/pages/profile.astro'), /new Date\(p\.created_at\)/,
    'created_at e timestamptz e deve seguir em new Date()');
});
