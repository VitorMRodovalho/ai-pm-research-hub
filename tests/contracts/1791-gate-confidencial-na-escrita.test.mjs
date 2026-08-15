/**
 * #1791 — o gate de visibilidade confidencial (ADR-0105 / #785) na direcao de ESCRITA.
 *
 * O #1784 fechou a LEITURA das tabelas-filhas do card e deixou a escrita registrada como pendencia.
 * As policies de escrita decidiam por capacidade organizacional e nao olhavam o recurso: a classe
 * que o #1778 fechou no checklist.
 *
 * Medido por impersonacao em transacao abortada (15/08/2026), com sujeito que TEM a capacidade e
 * NAO enxerga o board confidencial (nem por engajamento, nem por superadmin, nem por
 * manage_platform):
 *
 *   | porta, no card/board confidencial | antes  | depois          |
 *   |-----------------------------------|--------|-----------------|
 *   | INSERT de papel                   | PASSOU | barrado (42501) |
 *   | INSERT de atividade               | PASSOU | barrado (42501) |
 *   | INSERT de tag                     | PASSOU | barrado (42501) |
 *   | INSERT no log de ciclo de vida    | PASSOU | barrado (42501) |
 *
 * Controle inverso, MESMO sujeito e MESMA transacao, num card nao-confidencial: as quatro portas
 * seguem PASSOU. Populacao que escreve sem enxergar: 66 por write_board, 12 por write.
 *
 * UPDATE e DELETE de linha existente ja estavam barrados por efeito INDIRETO (o Postgres aplica as
 * policies de SELECT ao UPDATE/DELETE que referencia colunas, e o gate do #1784 esconde a linha
 * alvo). O INSERT escapava porque nao le linha nenhuma. Depois deste patch a barreira e explicita
 * nas duas direcoes, em vez de depender de um efeito colateral da leitura.
 *
 * O guard aqui e DERIVADO do catalogo, como o do #1784: `_audit_confidential_write_gate_coverage()`
 * acha as filhas por chave estrangeira. Uma lista de nomes so cobre o que alguem lembrou de escrever
 * nela, e foi exatamente por isso que o helper de leitura ficou verde durante todo o #1784 enquanto
 * quatro portas de INSERT seguiam abertas: ele nunca olhou a escrita.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const MIG_POLICIES = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20260815173644_1791_gate_confidencial_na_direcao_de_escrita.sql'),
  'utf8',
);
const MIG_AUDIT = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20260815173837_1791_audit_cobertura_do_gate_na_escrita.sql'),
  'utf8',
);

/** Filhas do card cuja ESCRITA este patch fecha, com o predicado que resolve o pai. */
const FECHADAS = [
  ['board_item_assignments', 'rls_can_see_item\\(item_id\\)'],
  ['board_item_tag_assignments', 'rls_can_see_item\\(board_item_id\\)'],
  ['board_item_checklists', 'rls_can_see_item\\(board_item_id\\)'],
  ['board_item_event_links', 'rls_can_see_item\\(board_item_id\\)'],
];

/**
 * Linha de base: filhas de board_items/project_boards cuja ESCRITA segue decidindo so por
 * capacidade organizacional. Todas medidas com ZERO linhas ligadas ao board confidencial em
 * 15/08/2026 — contencao por DADO, nao por estrutura. A lista so pode ENCOLHER: o teste falha se
 * aparecer uma tabela nova sem gate de escrita.
 */
const SEM_GATE_ESCRITA_BASELINE = new Set([
  'board_sla_config', 'curation_review_log', 'event_showcases', 'meeting_action_items',
  'pilots', 'public_publications', 'webinars',
]);

test('#1791 mig: cada filha fechada ganha policy RESTRICTIVE FOR ALL com USING e WITH CHECK', () => {
  for (const [tabela, predicado] of FECHADAS) {
    const re = new RegExp(
      `CREATE POLICY \\w+\\s+ON public\\.${tabela} AS RESTRICTIVE FOR ALL\\s+` +
      `USING \\(public\\.${predicado}\\)\\s+WITH CHECK \\(public\\.${predicado}\\)`,
      'i',
    );
    assert.match(MIG_POLICIES, re, `${tabela} precisa de RESTRICTIVE FOR ALL com as duas bordas`);
  }
});

test('#1791 mig: o log de ciclo de vida gateia pelas DUAS pernas, nao so por board_id', () => {
  // board_id e nulavel (o CHECK da tabela exige board_id OU item_id) e rls_can_see_board(NULL) e
  // verdadeiro por construcao: sem a perna de item_id, uma linha com board_id nulo apontando para
  // card confidencial passaria. Hoje sao 0 linhas assim, que e contencao por dado.
  const re = new RegExp(
    'CREATE POLICY \\w+\\s+ON public\\.board_lifecycle_events AS RESTRICTIVE FOR ALL\\s+' +
    'USING \\(public\\.rls_can_see_board\\(board_id\\) AND public\\.rls_can_see_item\\(item_id\\)\\)\\s+' +
    'WITH CHECK \\(public\\.rls_can_see_board\\(board_id\\) AND public\\.rls_can_see_item\\(item_id\\)\\)',
    'i',
  );
  assert.match(MIG_POLICIES, re, 'o log precisa das duas pernas do gate');
});

test('#1791 mig: a policy nunca troca o predicado por USING (true)', () => {
  const sqlOnly = MIG_POLICIES.split('\n').filter(l => !l.trim().startsWith('--')).join('\n');
  assert.doesNotMatch(sqlOnly, /USING\s*\(\s*true\s*\)/i);
  assert.doesNotMatch(sqlOnly, /WITH CHECK\s*\(\s*true\s*\)/i);
});

test('#1791 mig: o helper de auditoria da escrita nao fica exposto a anon nem a authenticated', () => {
  assert.match(MIG_AUDIT, /REVOKE ALL ON FUNCTION public\._audit_confidential_write_gate_coverage\(\) FROM PUBLIC, anon, authenticated/i);
  assert.match(MIG_AUDIT, /GRANT EXECUTE ON FUNCTION public\._audit_confidential_write_gate_coverage\(\) TO service_role/i);
  assert.match(MIG_AUDIT, /SECURITY DEFINER/i);
  assert.match(MIG_AUDIT, /SET search_path TO 'public', 'pg_temp'/i);
});

test('#1791 mig: a cobertura da escrita e derivada por FK, nao por lista de nomes', () => {
  assert.match(MIG_AUDIT, /pg_constraint[\s\S]{0,400}contype = 'f'/i, 'o conjunto precisa sair de chave estrangeira');
  assert.match(MIG_AUDIT, /cf\.relname IN \('board_items', 'project_boards'\)/i);
});

test('#1791 mig: o helper olha as DUAS bordas do predicado de escrita', () => {
  // INSERT decide por WITH CHECK e DELETE por USING. Um helper que so lesse `qual` classificaria
  // como ausente uma policy que gateia o INSERT, e vice-versa.
  assert.match(MIG_AUDIT, /coalesce\(p\.qual, ''\) \|\| ' ' \|\| coalesce\(p\.with_check, ''\)/i);
  assert.match(MIG_AUDIT, /p\.cmd IN \('ALL', 'INSERT', 'UPDATE', 'DELETE'\)/i);
});

const dbGated = process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY;
const skipMsg = 'requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';
const sb = () => createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

test('#1791 DB: toda filha do card carrega o gate de ESCRITA de forma explicita', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('_audit_confidential_write_gate_coverage');
  assert.ifError(error);
  assert.ok(Array.isArray(data) && data.length > 0, 'o helper precisa devolver linhas');
  for (const [tabela] of [...FECHADAS, ['board_lifecycle_events']]) {
    const linhas = data.filter(r => r.tabela === tabela);
    assert.ok(linhas.length > 0, `${tabela} precisa aparecer entre as filhas derivadas por FK`);
    for (const l of linhas) {
      assert.equal(l.forma, 'explicito', `${tabela} perdeu o gate de escrita (forma=${l.forma})`);
    }
  }
});

test('#1791 DB: o card decide por rls_can_for_initiative, e as portas fechadas seguem fechadas', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('_audit_confidential_write_gate_coverage');
  assert.ifError(error);
  const forma = t => [...new Set(data.filter(r => r.tabela === t).map(r => r.forma))];
  // board_items nao usa restritiva: o gate vive no proprio predicado permissivo desde o #785.
  assert.deepEqual(forma('board_items'), ['no_predicado'], 'board_items gateia dentro do predicado');
  // sem policy permissiva de escrita = porta do PostgREST fechada, nao ha o que gatear.
  for (const t of ['board_item_comments', 'board_item_files', 'board_drive_links']) {
    assert.deepEqual(forma(t), ['sem_escrita'], `${t} nao deveria ter porta de escrita aberta`);
  }
});

test('#1791 DB: nenhuma filha NOVA sem gate de escrita (a linha de base so encolhe)', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('_audit_confidential_write_gate_coverage');
  assert.ifError(error);
  const ausentes = [...new Set(data.filter(r => r.forma === 'ausente').map(r => r.tabela))];
  const novas = ausentes.filter(t => !SEM_GATE_ESCRITA_BASELINE.has(t));
  assert.deepEqual(
    novas, [],
    `filha sem gate de escrita fora da linha de base: ${novas.join(', ')}. ` +
    'Ou ela recebe o gate, ou entra na base com a medicao de quantas linhas confidenciais ela guarda.',
  );
});

test('#1791 DB: o helper de leitura do #1784 continua verde, e o invariante AJ tambem', { skip: dbGated ? false : skipMsg }, async () => {
  const c = sb();
  const { data: leitura, error: e1 } = await c.rpc('_audit_confidential_gate_coverage');
  assert.ifError(e1);
  const semGateLeitura = [...new Set(leitura.filter(r => r.forma === 'ausente').map(r => r.tabela))];
  for (const t of ['board_item_assignments', 'board_item_tag_assignments', 'board_item_checklists',
                   'board_item_event_links', 'board_lifecycle_events']) {
    assert.ok(!semGateLeitura.includes(t), `${t} nao pode perder o gate de LEITURA do #1784`);
  }
  const { data: inv, error: e2 } = await c.rpc('check_schema_invariants');
  assert.ifError(e2);
  const aj = inv.find(r => r.invariant_name === 'AJ_confidential_visibility_gate_present');
  assert.ok(aj, 'o invariante AJ precisa existir');
  assert.equal(aj.violation_count, 0);
});
