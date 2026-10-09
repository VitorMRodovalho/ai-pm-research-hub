/**
 * #2565 decisao (a) / ADR-0100: as metricas resolvem o ciclo corrente.
 *
 * Medido em 09/10: o ciclo corrente era cycle_4, mas /admin/portfolio e o relatorio pediam o ciclo 3
 * fixo, e get_annual_kpis / get_cycle_report contavam em janelas cravadas que nao eram a de ciclo algum.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. sem ciclo informado, as duas funcoes usam cycles.is_current, e a janela vem da linha do ciclo;
 *   B. nenhuma data cravada nem ano fixo sobra nos corpos; metas filtradas por ciclo E ano resolvidos;
 *   C. as telas nao mandam mais um ciclo fixo.
 *
 * Asserções amarram CONDIÇÃO ao RESULTADO dentro do bloco que decide, com comentários mascarados.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const FNS = ['get_annual_kpis', 'get_cycle_report'];
const cap = Object.fromEntries(FNS.map((f) => [f, latestFunctionCapture(ROOT, f)]));
const body = (f) => maskLineComments(cap[f].body);

for (const f of FNS) {
  test(`A. ${f}: sem ciclo informado, vale o ciclo corrente, com a janela dele`, () => {
    assert.match(cap[f].block, new RegExp(`FUNCTION public\\.${f}\\(p_cycle integer DEFAULT NULL::integer`), 'o padrao do ciclo e "nenhum"');
    const b = body(f);
    assert.match(b,
      /v_cycle := coalesce\(p_cycle,\s+\(SELECT substring\(c\.cycle_code FROM '\^cycle_\(\[0-9\]\+\)\$'\)::integer FROM public\.cycles c\s+WHERE c\.is_current ORDER BY c\.cycle_start DESC LIMIT 1\)\);\s+IF v_cycle IS NULL THEN\s+RAISE EXCEPTION/);
    assert.match(b,
      /SELECT c\.cycle_start, coalesce\(c\.cycle_end, CURRENT_DATE\)\s+INTO v_cycle_start, v_cycle_end\s+FROM public\.cycles c WHERE c\.cycle_code = 'cycle_' \|\| v_cycle;\s+IF v_cycle_start IS NULL THEN\s+RAISE EXCEPTION/);
    // o ciclo resolvido vem depois do portao de acesso
    assert.ok(b.indexOf("RAISE EXCEPTION 'Unauthorized'") < b.indexOf('v_cycle := coalesce(p_cycle'), 'resolve depois do portao');
  });

  test(`B. ${f}: sem data cravada nem ano fixo; metas por ciclo e ano resolvidos`, () => {
    const b = body(f);
    assert.doesNotMatch(b, /'20\d\d-\d\d-\d\d'/, 'nenhuma data literal');
    assert.doesNotMatch(b, /\byear\s*=\s*20\d\d\b|p_year integer DEFAULT 20\d\d/, 'nenhum ano fixo');
    assert.match(b, /FROM public\.annual_kpi_targets k\s+WHERE k\.cycle = v_cycle AND k\.year = v_year/, 'metas do ciclo resolvido');
  });
}

test('B. o ano das metas vem do ciclo resolvido', () => {
  assert.match(cap.get_annual_kpis.block, /p_year integer DEFAULT NULL::integer\)/, 'o padrao do ano e "nenhum"');
  assert.match(body('get_annual_kpis'), /v_year := coalesce\(p_year, extract\(year FROM v_cycle_start\)::integer\);/);
  assert.match(body('get_cycle_report'), /v_year := extract\(year FROM v_cycle_start\)::integer;/);
  assert.match(body('get_annual_kpis'), /'cpmai_certified_count', public\.get_cpmai_certified_goal_count\(v_year\),/, 'CPMAI no ano das metas');
});

test('B. as contagens usam a janela do ciclo resolvido, ate hoje', () => {
  const a = body('get_annual_kpis');
  assert.match(a, /'webinars_realized_count', public\.get_webinars_count\(v_cycle_start, LEAST\(v_cycle_end, CURRENT_DATE\), 'realized'\),/);
  assert.match(a, /FROM public\.events e WHERE e\.date BETWEEN v_cycle_start AND LEAST\(v_cycle_end, CURRENT_DATE\) AND NOT EXISTS/);
  assert.match(body('get_cycle_report'), /FROM public\.events e WHERE e\.date BETWEEN v_cycle_start AND LEAST\(v_cycle_end, CURRENT_DATE\) AND NOT/);
});

test('C. o MCP nao manda ciclo nem ano fixos a essas funcoes', () => {
  const mcp = maskJsComments(readFileSync(resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8'));
  assert.match(mcp, /sb\.rpc\("get_annual_kpis", \{ p_cycle: params\.cycle \?\? null, p_year: params\.year \?\? null \}\)/);
  assert.match(mcp, /sb\.rpc\("get_cycle_report", \{ p_cycle: params\.cycle \?\? null \}\)/);
  assert.doesNotMatch(mcp, /sb\.rpc\("get_(annual_kpis|cycle_report)", \{[^}]*\?\? (\d|"cycle)/);
});

test('C. as telas nao mandam ciclo fixo', () => {
  const portfolio = maskJsComments(readFileSync(resolve(ROOT, 'src/pages/admin/portfolio.astro'), 'utf8'));
  const report = maskJsComments(readFileSync(resolve(ROOT, 'src/components/report/ReportPage.tsx'), 'utf8'));
  assert.match(portfolio, /sb\.rpc\('get_annual_kpis', \{\}\)/);
  assert.match(report, /sb\.rpc\('get_cycle_report', \{\}\)/);
  for (const src of [portfolio, report]) assert.doesNotMatch(src, /rpc\('get_(annual_kpis|cycle_report)', \{[^}]*p_cycle/);
});
