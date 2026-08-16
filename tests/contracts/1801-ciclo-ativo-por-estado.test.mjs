/**
 * #1801 — "o ciclo ativo" nao pode ser resolvido por `created_at`.
 *
 * `selection_cycles.created_at` e a data de escrita da LINHA, nao a do ciclo. O backfill do
 * `cycle2-2025` entrou em 2026-07-13 e tornou a linha de um ciclo FECHADO de 2025 a mais nova da
 * tabela; todo `ORDER BY created_at DESC LIMIT 1` passou a apontar para ele.
 *
 * Medido em 16/08/2026, pelo caminho real do chamador (impersonacao em transacao abortada):
 *
 *   | superficie                        | antes (cycle2-2025) | depois (cycle4-2026) |
 *   |-----------------------------------|--------------------:|---------------------:|
 *   | get_selection_pipeline_metrics    |    8 candidaturas   |                   81 |
 *   | get_evaluator_calibration_stats   |  0 avaliacoes / 0   |            238 / 2   |
 *   | get_diversity_dashboard           |     8 / 6 aprovados |              81 / 57 |
 *   | get_selection_rankings            |  0 / 0 (lista vazia)|              56 / 10 |
 *   | get_entry_chapter_diagnosis       |            6 linhas |                   57 |
 *   | get_chapter_selection_summary.last|          30/11/2025 |           30/06/2026 |
 *
 * O guard e um RATCHET DERIVADO do catalogo (`_audit_selection_cycle_resolution`, que acha as
 * escolhas de ciclo em `pg_proc`) em vez de uma lista de nomes: a issue listava 10 funcoes e o
 * catalogo tinha 12 — `get_entry_chapter_diagnosis` e o ramo `last` do
 * `get_chapter_selection_summary` nao estavam na lista de ninguem.
 *
 * Linha de base: ZERO. Nao ha excecao a manter.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const MIG = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20260816020027_1801_ciclo_ativo_por_estado_na_classe_inteira.sql'),
  'utf8',
);
/**
 * So o SQL EXECUTAVEL. Duas classes de prosa saem antes: as linhas `--` do cabecalho e os blocos
 * `COMMENT ON`, porque as duas CITAM o padrao que esta sendo removido — o COMMENT do helper diz, em
 * portugues, para nunca resolver o ciclo por data de escrita, e a frase contem literalmente a
 * clausula proibida. Guard que le prosa acusa a propria documentacao.
 */
const SQL_ONLY = MIG
  .replace(/COMMENT ON [\s\S]*?';/g, '')
  .split('\n').filter(l => !l.trim().startsWith('--')).join('\n');

/** As que resolviam o ciclo padrao e passaram a delegar ao helper. */
const DELEGAM_AO_HELPER = [
  'get_diversity_dashboard',
  'get_entry_chapter_diagnosis',
  'get_evaluator_calibration_stats',
  'get_selection_pipeline_metrics',
  'get_selection_rankings',
  '_test_invariants_with_synthetic_breach',
];

test('#1801 mig: o helper canonico ordena por ESTADO, com created_at so no fim', () => {
  assert.match(SQL_ONLY, /CREATE OR REPLACE FUNCTION public\.selection_active_cycle_id\(\)\s*\n\s*RETURNS uuid/i);
  // as tres chaves, nesta ordem: status aberto > data do fato > data da linha
  assert.match(
    SQL_ONLY,
    /ORDER BY \(c\.status = 'open'\) DESC,\s*c\.open_date\s+DESC NULLS LAST,\s*c\.created_at DESC\s*LIMIT 1/i,
    'o helper precisa preferir status open, depois open_date, e so entao created_at',
  );
});

test('#1801 mig: cada funcao da classe delega ao helper em vez de repetir a ordenacao', () => {
  for (const fn of DELEGAM_AO_HELPER) {
    const corpo = SQL_ONLY.slice(SQL_ONLY.indexOf(`FUNCTION public.${fn}(`));
    assert.ok(
      corpo.slice(0, corpo.indexOf('$function$;') + 12).includes('public.selection_active_cycle_id()'),
      `${fn} precisa resolver o ciclo pelo helper`,
    );
  }
});

test('#1801 mig: nenhuma escolha de ciclo sobrou com created_at como PRIMEIRA chave', () => {
  // o defeito tem forma propria: ORDER BY <alias?>created_at ... LIMIT 1 escolhendo UMA linha.
  // created_at como ultimo desempate e legitimo e nao pode acusar.
  assert.doesNotMatch(
    SQL_ONLY,
    /ORDER BY\s+(?:[a-z_]+\.)?created_at\s+DESC\s*\n?\s*LIMIT\s+1/i,
    'a migration nunca pode reintroduzir a resolucao por data de escrita da linha',
  );
});

test('#1801 mig: o helper e a auditoria nascem fechados (CREATE FUNCTION concede a PUBLIC)', () => {
  assert.match(SQL_ONLY, /REVOKE ALL ON FUNCTION public\.selection_active_cycle_id\(\) FROM PUBLIC, anon/i);
  assert.match(SQL_ONLY, /GRANT EXECUTE ON FUNCTION public\.selection_active_cycle_id\(\) TO authenticated, service_role/i);
  assert.match(SQL_ONLY, /REVOKE ALL ON FUNCTION public\._audit_selection_cycle_resolution\(\) FROM PUBLIC, anon, authenticated/i);
  assert.match(SQL_ONLY, /GRANT EXECUTE ON FUNCTION public\._audit_selection_cycle_resolution\(\) TO service_role/i);
});

test('#1801 mig: o ratchet e derivado de pg_proc, nao de lista de nomes', () => {
  assert.match(SQL_ONLY, /FROM pg_proc p\s*\n\s*JOIN pg_namespace n/i, 'a cobertura precisa sair do catalogo');
  assert.match(SQL_ONLY, /SECURITY DEFINER\s*\nSET search_path TO 'public', 'pg_temp'\s*\nAS \$function\$\s*\n\s*WITH fragmento/i);
});

test('#1801 mig: get_my_pending_evaluations mantem o portao escopado no ciclo escolhido (#298)', () => {
  // trocar QUAL ciclo e escolhido tambem troca QUEM pode ler; o portao do #298 nao pode ter saido junto.
  assert.match(SQL_ONLY, /sc\.cycle_id = v_cycle\.id/, 'o portao do #298 segue escopado no ciclo escolhido');
  assert.match(SQL_ONLY, /RAISE EXCEPTION 'Unauthorized: caller is not on this cycle committee'/);
  assert.match(SQL_ONLY, /WHERE phase = 'evaluating'\s*\n\s*AND status <> 'closed'/i, 'ciclo fechado nao pode capturar a fila');
});

// ─── portao de DB ────────────────────────────────────────────────────────────────────────────────

const dbGated = process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY;
const skipMsg = 'requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';
const sb = () => createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

test('#1801 DB: RATCHET — nenhuma funcao resolve ciclo por created_at (linha de base ZERO)', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('_audit_selection_cycle_resolution');
  assert.ifError(error);
  assert.ok(Array.isArray(data) && data.length > 0, 'o auditor precisa devolver linhas (senao o guard esta cego)');
  const violam = data.filter(r => r.resolve_por_created_at);
  assert.deepEqual(
    violam.map(r => `${r.funcao}(${r.args})`), [],
    'funcao escolhendo UM ciclo por created_at. `created_at` e a data de escrita da linha: ' +
    'use public.selection_active_cycle_id(), ou ordene por estado antes da data.',
  );
});

test('#1801 DB: o helper resolve o ciclo ABERTO, nao a linha mais nova', { skip: dbGated ? false : skipMsg }, async () => {
  const c = sb();
  const { data: ativo, error: e1 } = await c.rpc('selection_active_cycle_id');
  assert.ifError(e1);
  assert.ok(ativo, 'o helper precisa devolver um ciclo');

  const { data: abertos, error: e2 } = await c.from('selection_cycles').select('id,cycle_code').eq('status', 'open');
  assert.ifError(e2);
  if (abertos.length > 0) {
    assert.ok(
      abertos.some(r => r.id === ativo),
      `o helper devolveu um ciclo que nao esta aberto (abertos: ${abertos.map(r => r.cycle_code).join(', ')})`,
    );
  }

  // e o contraste que motivou a issue: a linha mais nova NAO e o ciclo ativo.
  const { data: maisNova, error: e3 } = await c
    .from('selection_cycles').select('id,cycle_code,status').order('created_at', { ascending: false }).limit(1);
  assert.ifError(e3);
  if (maisNova[0] && maisNova[0].status !== 'open' && abertos.length > 0) {
    assert.notEqual(ativo, maisNova[0].id, 'a linha mais nova esta fechada e nao pode ser o ciclo ativo');
  }
});
