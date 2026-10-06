/**
 * O portfólio segue o ciclo corrente (#2565 2A, decisão (g); ADR-0100 §2.1).
 *
 * O QUE ESTE GUARD AFIRMA, sempre na captura vigente de cada função:
 *   A. Todo card novo sem ciclo recebe o ciclo corrente, por um gatilho BEFORE INSERT; os caminhos de
 *      criação não gravam ciclo literal; a cópia nasce no ciclo corrente e o espelho herda o da origem.
 *   B. A regra da visão de um ciclo mora num lugar só (_in_cycle_view): card aberto entra só na visão
 *      do ciclo corrente; card concluído entra na visão do ciclo em cuja janela foi concluído.
 *   C. As quatro leituras do portfólio usam essa regra em todo recorte, resolvem a janela depois da
 *      trava de acesso, não têm o ciclo 3 como padrão e não filtram mais pelo ciclo gravado.
 *   D. Tela, MCP e script não pedem o ciclo 3.
 *   E. (banco) A regra e a leitura valem no ar: tabela-verdade da regra, e todo card devolvido pelo
 *      painel cabe na visão pedida.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const cap = (n) => maskLineComments(latestFunctionCapture(ROOT, n).block);
const src = (p) => maskJsComments(readFileSync(join(ROOT, p), 'utf8'));
const count = (s, re) => (s.match(re) || []).length;

test('A: o ciclo corrente sai de cycles.is_current, pela chave cycle_code', () => {
  assert.match(
    cap('current_cycle_number'),
    /SELECT substring\(c\.cycle_code from '\^cycle_\(\[0-9\]\{1,6\}\)\$'\)::int\s+FROM public\.cycles c\s+WHERE c\.is_current IS TRUE\s+ORDER BY c\.sort_order DESC\s+LIMIT 1;/,
  );
});

test('A: todo card novo sem ciclo recebe o ciclo corrente, por gatilho', () => {
  assert.match(
    cap('_trg_board_items_stamp_cycle'),
    /IF NEW\.cycle IS NULL THEN\s+NEW\.cycle := public\.current_cycle_number\(\);\s+END IF;\s+RETURN NEW;/,
  );
  const dir = join(ROOT, 'supabase/migrations');
  let last = null;
  for (const f of readdirSync(dir).filter((x) => x.endsWith('.sql')).sort()) {
    const s = maskLineComments(readFileSync(join(dir, f), 'utf8'));
    if (/CREATE TRIGGER trg_board_items_stamp_cycle\s+BEFORE INSERT ON public\.board_items\s+FOR EACH ROW EXECUTE FUNCTION public\._trg_board_items_stamp_cycle\(\);/.test(s)) {
      last = { f, vivo: true };
    } else if (/DROP TRIGGER (IF EXISTS )?trg_board_items_stamp_cycle/.test(s)) {
      last = { f, vivo: false };
    }
  }
  assert.ok(last?.vivo, 'o gatilho BEFORE INSERT existe e nenhuma migration posterior o derruba');
});

test('A: criação sem ciclo literal; a cópia nasce no corrente; o espelho herda o da origem', () => {
  assert.match(
    cap('create_board_item'),
    /INSERT INTO board_items \(board_id, title, description, assignee_id, tags, due_date, position, status, created_by\)\s+VALUES \(p_board_id, p_title, p_description, COALESCE\(p_assignee_id, v_caller\.id\), p_tags, p_due_date, v_max_pos, p_status, v_caller\.id\)/,
  );
  assert.match(
    cap('duplicate_board_item'),
    /INSERT INTO board_items \(\s+board_id, title, description, tags, labels, checklist, attachments, position, status\s+\)\s+SELECT v_board_id, title \|\| ' \(cópia\)', description, tags, labels, checklist, attachments, v_max_pos, 'backlog'/,
  );
  assert.match(
    cap('create_mirror_card'),
    /mirror_source_id, is_mirror, position, cycle\s+\) VALUES \([\s\S]*?v_max_pos,\s+v_source\.cycle\s+\)/,
  );
});

test('B: a regra da visão do ciclo mora num lugar só', () => {
  assert.match(
    cap('_in_cycle_view'),
    /CASE\s+WHEN p_completed IS NULL THEN coalesce\(p_is_current, false\)\s+ELSE p_completed >= p_start AND \(p_end IS NULL OR p_completed <= p_end\)\s+END/,
  );
  assert.match(
    cap('_cycle_window'),
    /WHERE c\.cycle_code = 'cycle_' \|\| COALESCE\(p_cycle, public\.current_cycle_number\(\)\)::text/,
  );
});

const BI = /public\._in_cycle_view\(bi\.actual_completion_date, v_is_current, v_start, v_end\)/g;
const READERS = [
  {
    nome: 'get_portfolio_dashboard',
    assinatura: /FUNCTION public\.get_portfolio_dashboard\(p_cycle integer DEFAULT NULL::integer\)/,
    trava: /IF public\._request_is_rest_caller\(\) AND NOT public\.rls_is_authoritative_member\(\) THEN\s+RETURN NULL;/,
    janela: 'FROM public._cycle_window(p_cycle) w;',
    regra: BI,
    recortes: 5,
  },
  {
    nome: 'get_portfolio_planned_vs_actual',
    assinatura: /FUNCTION public\.get_portfolio_planned_vs_actual\(p_cycle integer DEFAULT NULL::integer\)/,
    trava: /IF NOT FOUND THEN RETURN '\[\]'::jsonb; END IF;/,
    janela: 'FROM public._cycle_window(p_cycle) w;',
    regra: BI,
    recortes: 1,
  },
  {
    nome: 'get_portfolio_items',
    assinatura: /p_cycle_code text DEFAULT NULL::text\)/,
    trava: /IF NOT \(can_by_member\(v_member_id, 'view_internal_analytics'\) OR can_by_member\(v_member_id, 'view_chapter_dashboards'\) OR can_by_member\(v_member_id, 'view_aggregate_analytics'\)\) THEN\s+RAISE EXCEPTION/,
    janela: 'FROM public._cycle_window(v_cycle) w;',
    regra: BI,
    recortes: 1,
  },
  {
    nome: 'audit_portfolio_flag_tag_gaps',
    assinatura: /p_dashboard_cycle integer DEFAULT NULL::integer\s+\)/,
    trava: /IF NOT public\.can_by_member\(v_caller_id, 'manage_platform'\) THEN\s+RAISE EXCEPTION/,
    janela: 'FROM public._cycle_window(p_dashboard_cycle) w;',
    regra: /public\._in_cycle_view\(s\.actual_completion_date, v_is_current, v_start, v_end\) IS NOT TRUE/g,
    recortes: 1,
  },
];

for (const r of READERS) {
  test(`C: ${r.nome} lê a visão do ciclo, depois da trava, sem o ciclo 3 de padrão`, () => {
    const b = cap(r.nome);
    assert.match(b, r.assinatura, 'sem ciclo pedido, vale o corrente');
    assert.doesNotMatch(b, /DEFAULT 3\b/, 'o ciclo 3 não é padrão');
    const t = b.search(r.trava);
    assert.ok(t >= 0, 'a trava de acesso continua');
    assert.ok(b.indexOf(r.janela) > t, 'a janela é resolvida depois da trava');
    assert.equal(count(b, r.regra), r.recortes, 'todo recorte usa a regra da visão');
    assert.doesNotMatch(
      b,
      /bi\.cycle = p_cycle|s\.cycle IS DISTINCT FROM p_dashboard_cycle|c\.cycle_code = p_cycle_code/,
      'nenhum recorte pelo ciclo gravado',
    );
  });
}

test('C: o painel devolve o ciclo resolvido e a janela, e tira toda tag de ciclo dos tipos', () => {
  const b = cap('get_portfolio_dashboard');
  assert.match(b, /'cycle', COALESCE\(v_cycle, p_cycle\),\s+'window_start', v_start,\s+'window_end', v_end,/);
  assert.equal(count(b, /tg\.name <> 'entregavel_lider' AND tg\.name !~ '\^ciclo_\[0-9\]\+\$'/g), 2);
  assert.doesNotMatch(b, /'ciclo_3'/);
});

test('C: a lista por ciclo só aceita o código canônico; outro código não vira o ciclo corrente', () => {
  assert.match(
    cap('get_portfolio_items'),
    /IF p_cycle_code IS NOT NULL THEN\s+v_cycle := substring\(p_cycle_code from '\^cycle_\(\[0-9\]\{1,6\}\)\$'\)::int;\s+IF v_cycle IS NOT NULL THEN\s+SELECT w\.is_current, w\.window_start, w\.window_end\s+INTO v_is_current, v_start, v_end\s+FROM public\._cycle_window\(v_cycle\) w;/,
  );
});

test('D: tela, MCP e script não pedem o ciclo 3', () => {
  const hook = src('src/hooks/usePortfolio.ts');
  assert.match(hook, /export function usePortfolio\(cycle: number \| null = null\)/);
  assert.match(hook, /sb\.rpc\('get_portfolio_dashboard', \{ p_cycle: cycle \}\)/);
  const dash = src('src/components/portfolio/PortfolioDashboard.tsx');
  assert.match(dash, /= usePortfolio\(\);/);
  assert.match(dash, /<PortfolioGantt artifacts=\{filtered\} windowStart=\{data\.window_start\} windowEnd=\{data\.window_end\} \/>/);
  assert.match(src('src/components/portfolio/PlannedVsActualSection.tsx'), /sb\.rpc\('get_portfolio_planned_vs_actual', \{\}\)/);
  const gantt = src('src/components/portfolio/PortfolioGantt.tsx');
  assert.doesNotMatch(gantt, /2026-03-01|2026-12-31/, 'a régua não fixa o ciclo 3');
  assert.match(gantt, /let cycleStart = parseDate\(windowStart\);/);
  const mcp = src('supabase/functions/nucleo-mcp/index.ts');
  assert.equal(count(mcp, /sb\.rpc\("get_portfolio_planned_vs_actual", \{ p_cycle: params\.cycle \?\? null \}\)/g), 1);
  assert.equal(count(mcp, /rpc = "get_portfolio_planned_vs_actual"; rpcArgs = \{ p_cycle: params\.cycle \?\? null \}/g), 1);
  assert.doesNotMatch(mcp, /get_portfolio_planned_vs_actual[^\n]*\?\? 3/);
  assert.match(
    src('scripts/audit-portfolio-flags-tags.mjs'),
    /const cycleOpt = getOpt\('cycle', null\);\nconst dashboardCycle = cycleOpt === null \? null : Number\(cycleOpt\);/,
  );
});

// ── E. banco ────────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const skip = !(SUPABASE_URL && KEY) && 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

async function rpc(name, body) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) assert.fail(`${name}: HTTP ${res.status} ${text}`);
  return JSON.parse(text);
}

async function rest(path) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { headers: { apikey: KEY, Authorization: `Bearer ${KEY}` } });
  const text = await res.text();
  if (!res.ok) assert.fail(`GET ${path}: HTTP ${res.status} ${text}`);
  return JSON.parse(text);
}

test('E: tabela-verdade da regra da visão', { skip }, async () => {
  const casos = [
    [{ p_completed: null, p_is_current: true, p_start: '2026-07-09', p_end: null }, true],
    [{ p_completed: null, p_is_current: false, p_start: '2026-03-01', p_end: '2026-07-08' }, false],
    [{ p_completed: '2026-08-01', p_is_current: true, p_start: '2026-07-09', p_end: null }, true],
    [{ p_completed: '2026-07-08', p_is_current: true, p_start: '2026-07-09', p_end: null }, false],
    [{ p_completed: '2026-05-01', p_is_current: false, p_start: '2026-03-01', p_end: '2026-07-08' }, true],
    [{ p_completed: '2026-07-09', p_is_current: false, p_start: '2026-03-01', p_end: '2026-07-08' }, false],
  ];
  const erros = [];
  for (const [args, esperado] of casos) {
    const got = await rpc('_in_cycle_view', args);
    if (got !== esperado) erros.push(`${JSON.stringify(args)} -> ${got}, esperado ${esperado}`);
  }
  assert.deepEqual(erros, []);
});

test('E: todo card devolvido pelo painel cabe na visão pedida', { skip }, async () => {
  const cycles = await rest('cycles?select=cycle_code,is_current,cycle_start,cycle_end');
  const atual = cycles.find((c) => c.is_current === true);
  assert.ok(atual, 'existe ciclo corrente');
  const n = Number(atual.cycle_code.replace(/^cycle_/, ''));

  const d = await rpc('get_portfolio_dashboard', {});
  assert.equal(d.cycle, n, 'sem ciclo pedido, o painel resolve o ciclo corrente');
  assert.equal(d.window_start, atual.cycle_start);
  const fora = (d.artifacts || []).filter(
    (a) => a.actual_completion_date !== null && a.actual_completion_date < atual.cycle_start,
  );
  assert.deepEqual(fora.map((a) => a.id), [], 'concluído antes da janela não entra na visão corrente');

  const anterior = cycles.find((c) => c.cycle_code === 'cycle_3');
  if (anterior) {
    const p = await rpc('get_portfolio_dashboard', { p_cycle: 3 });
    const errados = (p.artifacts || []).filter(
      (a) => a.actual_completion_date === null
        || a.actual_completion_date < anterior.cycle_start
        || (anterior.cycle_end && a.actual_completion_date > anterior.cycle_end),
    );
    assert.deepEqual(errados.map((a) => a.id), [], 'a visão de um ciclo passado só tem o concluído na janela dele');
  }
});
