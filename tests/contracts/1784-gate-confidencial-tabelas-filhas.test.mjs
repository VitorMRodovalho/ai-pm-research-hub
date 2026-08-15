/**
 * #1784 — o gate de visibilidade confidencial (ADR-0105 / #785) nas tabelas-filhas do card.
 *
 * O #785 PR-2 colocou o gate nas 8 tabelas dependentes de iniciativa, e o invariante AJ guarda
 * essas 8 por NOME. As tabelas-filhas do card ficaram de fora das duas coisas: a leitura delas
 * decidia apenas por "e membro autoritativo", e board_item_event_links por USING (true).
 *
 * Medido por impersonacao em transacao abortada (15/08/2026), com um membro que NAO enxerga o
 * board confidencial e TEM write_board:
 *
 *   | leitura                          | antes | depois |
 *   |----------------------------------|------:|-------:|
 *   | board_item_assignments do board  |    25 |      0 |
 *   | board_lifecycle_events do board  |   100 |      0 |
 *   | board_items / checklists (controle, ja gateados) | 0 | 0 |
 *   | mesmas tabelas fora do confidencial (controle inverso) | 893 / 3236 | 893 / 3236 |
 *
 * O guard aqui e DERIVADO do catalogo (`_audit_confidential_gate_coverage`, que acha as filhas por
 * chave estrangeira) em vez de repetir uma lista: uma lista so cobre o que alguem lembrou de
 * escrever nela, que e exatamente por que estas seis passaram despercebidas.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const MIG_POLICIES = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20260815124636_1784_gate_confidencial_nas_tabelas_filhas_do_card.sql'),
  'utf8',
);
const MIG_AUDIT = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20260815125156_1784_audit_cobertura_do_gate_confidencial_derivada_por_fk.sql'),
  'utf8',
);

/** Filhas do proprio card corrigidas por este patch, com a coluna que resolve o pai. */
const CORRIGIDAS = [
  ['board_item_assignments', 'rls_can_see_item\\(item_id\\)'],
  ['board_item_files', 'rls_can_see_item\\(board_item_id\\)'],
  ['board_item_tag_assignments', 'rls_can_see_item\\(board_item_id\\)'],
  ['board_item_event_links', 'rls_can_see_item\\(board_item_id\\)'],
  ['board_lifecycle_events', 'rls_can_see_board\\(board_id\\)'],
  ['board_drive_links', 'rls_can_see_board\\(board_id\\)'],
];

/**
 * Linha de base: filhas de board_items/project_boards que seguem SEM gate. Todas medidas com
 * ZERO linhas ligadas ao board confidencial em 15/08/2026 — contencao por dado, nao por
 * estrutura. A lista so pode ENCOLHER: o teste falha se aparecer uma tabela nova sem gate.
 */
const SEM_GATE_BASELINE = new Set([
  'board_sla_config', 'content_products', 'event_showcases', 'meeting_action_items',
  'partner_cards', 'pilots', 'public_publications', 'publication_submission_events',
  'publication_submissions', 'webinars',
]);

test('#1784 mig: cada tabela-filha corrigida ganha policy RESTRICTIVE de SELECT', () => {
  for (const [tabela, predicado] of CORRIGIDAS) {
    const re = new RegExp(
      `CREATE POLICY \\w+\\s+ON public\\.${tabela} AS RESTRICTIVE FOR SELECT\\s+USING \\(public\\.${predicado}\\)`,
      'i',
    );
    assert.match(MIG_POLICIES, re, `${tabela} precisa de policy RESTRICTIVE FOR SELECT chamando o helper do gate`);
  }
});

test('#1784 mig: o USING (true) de board_item_event_links foi trocado, e nenhum novo foi introduzido', () => {
  // o unico USING (true) do dominio era a permissiva de vinculo com evento
  assert.match(
    MIG_POLICIES,
    /CREATE POLICY board_item_event_links_select_authenticated[\s\S]{0,160}rls_is_authoritative_member\(\)/i,
    'a permissiva de event_links precisa exigir membro autoritativo',
  );
  // so o SQL: o cabecalho da migration CITA o USING (true) que estava sendo removido
  const sqlOnly = MIG_POLICIES.split('\n').filter(l => !l.trim().startsWith('--')).join('\n');
  assert.doesNotMatch(sqlOnly, /USING\s*\(\s*true\s*\)/i, 'a migration do gate nunca pode introduzir USING (true)');
});

test('#1784 mig: o helper de auditoria nao fica exposto a anon nem a authenticated', () => {
  assert.match(MIG_AUDIT, /REVOKE ALL ON FUNCTION public\._audit_confidential_gate_coverage\(\) FROM PUBLIC, anon, authenticated/i);
  assert.match(MIG_AUDIT, /GRANT EXECUTE ON FUNCTION public\._audit_confidential_gate_coverage\(\) TO service_role/i);
  assert.match(MIG_AUDIT, /SECURITY DEFINER/i);
  assert.match(MIG_AUDIT, /SET search_path TO 'public', 'pg_temp'/i);
});

test('#1784 mig: a cobertura e derivada por FK, nao por lista de nomes', () => {
  assert.match(MIG_AUDIT, /pg_constraint[\s\S]{0,400}contype = 'f'/i, 'o conjunto precisa sair de chave estrangeira');
  assert.match(MIG_AUDIT, /cf\.relname IN \('board_items', 'project_boards'\)/i);
});

const dbGated = process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY;
const skipMsg = 'requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';
const sb = () => createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

test('#1784 DB: toda tabela-filha do card carrega o gate de forma explicita', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('_audit_confidential_gate_coverage');
  assert.ifError(error);
  assert.ok(Array.isArray(data) && data.length > 0, 'o helper precisa devolver linhas');
  for (const [tabela] of CORRIGIDAS) {
    const linhas = data.filter(r => r.tabela === tabela);
    assert.ok(linhas.length > 0, `${tabela} precisa aparecer entre as filhas derivadas por FK`);
    for (const l of linhas) {
      assert.equal(l.forma, 'explicito', `${tabela} perdeu o gate (forma=${l.forma})`);
    }
  }
});

test('#1784 DB: comments segue gateado pelo pai, e board_items e checklists pelo helper', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('_audit_confidential_gate_coverage');
  assert.ifError(error);
  const forma = t => data.filter(r => r.tabela === t).map(r => r.forma);
  // #1791 promoveu checklists de 'transitivo' para 'explicito': ao fechar a direcao de escrita, a
  // policy virou FOR ALL com o predicado explicito, e a leitura deixou de depender do EXISTS sobre
  // o pai. 'explicito' e mais forte que 'transitivo', nunca mais fraco.
  assert.deepEqual(forma('board_item_checklists'), ['explicito'], 'checklists ganharam o predicado explicito no #1791');
  assert.deepEqual(forma('board_item_comments'), ['transitivo'], 'comments dependem do EXISTS sobre o pai');
  assert.ok(forma('board_items').every(f => f === 'explicito'), 'board_items e o gate do #785 PR-2');
});

test('#1784 DB: nenhuma tabela-filha NOVA sem gate (a linha de base so encolhe)', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('_audit_confidential_gate_coverage');
  assert.ifError(error);
  const ausentes = [...new Set(data.filter(r => r.forma === 'ausente').map(r => r.tabela))];
  const novas = ausentes.filter(t => !SEM_GATE_BASELINE.has(t));
  assert.deepEqual(
    novas, [],
    `tabela-filha sem gate fora da linha de base: ${novas.join(', ')}. ` +
    'Ou ela recebe o gate, ou entra na base com a medicao de quantas linhas confidenciais ela guarda.',
  );
});

test('#1784 DB: o invariante AJ do #785 continua verde (o patch nao mexeu nas 8 originais)', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('check_schema_invariants');
  assert.ifError(error);
  const aj = data.find(r => r.invariant_name === 'AJ_confidential_visibility_gate_present');
  assert.ok(aj, 'o invariante AJ precisa existir');
  assert.equal(aj.violation_count, 0);
});
