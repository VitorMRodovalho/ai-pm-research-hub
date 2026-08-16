/**
 * Contract: #1572 — aprovar sem NENHUMA avaliação registrada segue sendo estado válido, mas deixa de
 * ser indistinguível de uma aprovação com lastro.
 *
 * O achado (03/08/2026): duas candidaturas do `cycle4-2026` estavam `approved` com zero avaliação e
 * scores nulos, com os membros já onboardados. O ciclo se chama "Aceite Antecipado", então o bypass
 * é intencional por desenho. O defeito nunca foi a decisão, foi a **ausência de trilha**: não havia
 * registro de quem aprovou nem com base em quê, e `selection_cycles.min_evaluators` (2 nos 4 ciclos)
 * nunca era consultado no momento da decisão.
 *
 * Decisão do PM (15/08): manter o estado válido e exigir justificativa (checkbox 1 da issue), em vez
 * de gatear por N avaliações (checkbox 2).
 *
 * ⚠️ ESTE ARQUIVO AFIRMA A REGRA, NUNCA O INSTANTÂNEO. A população decidida-sem-avaliação é
 * recalculada contra os dados vivos a cada execução e só precisa ser NÃO VAZIA — congelar "hoje são
 * 15" mataria o teste amanhã e ensinaria a atualizar o número em vez de ler o defeito.
 *
 * Por que não há chamada real da RPC exercitando a recusa: as três RPCs resolvem o chamador por
 * `auth.uid()`, que é NULL para `service_role`. Uma asserção de envelope mediria a falta de sessão,
 * não o portão. A verificação vem do CATÁLOGO (corpo vivo via `_audit_function_source`) mais o
 * fail-closed observável, que é o padrão da casa (ver 1477-tcv-carveout, 1586b).
 *
 * Efeito colateral: nenhum. Todas as chamadas são leitura ou fail-closed antes de qualquer escrita.
 */

import { describe, it, before } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

/** A migration do #1572 é localizada pelo CONTEÚDO, não por um timestamp fixo: `apply_migration`
 *  carimba a linha de tracking com timestamp próprio, e prender o teste ao nome do arquivo o quebra
 *  na primeira renomeação. */
function migracaoDo1572() {
  if (!existsSync(MIGRATIONS_DIR)) return '';
  const arquivos = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort();
  let achado = '';
  for (const f of arquivos) {
    const sql = readFileSync(resolve(MIGRATIONS_DIR, f), 'utf8');
    if (/early_acceptance_reason/.test(sql) && /ADD COLUMN IF NOT EXISTS early_acceptance_at/.test(sql)) achado = sql;
  }
  return achado;
}

const MIG = migracaoDo1572();

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = dbGated ? createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } }) : null;

const ESCRITORES = ['admin_update_application', 'finalize_decisions', 'admin_decide_dual_track'];

/** Tira comentários antes de assertar: um guard que casa com a própria documentação do conserto
 *  fica verde quando o SQL executável já foi refatorado para longe da regra. */
const semComentarios = (s) => s.replace(/--[^\n]*/g, '');

// ── Offline: a migration carrega a decisão ────────────────────────────────────────────────────────
describe('#1572 — migration', () => {
  it('a migration do aceite antecipado existe', () => {
    assert.ok(MIG, 'nenhuma migration em supabase/migrations declara early_acceptance_at + early_acceptance_reason');
  });

  it('as três colunas nascem juntas, e o carimbo NÃO existe sozinho', () => {
    assert.match(MIG, /ADD COLUMN IF NOT EXISTS early_acceptance_at\s+timestamptz/);
    assert.match(MIG, /ADD COLUMN IF NOT EXISTS early_acceptance_by\s+uuid/);
    assert.match(MIG, /ADD COLUMN IF NOT EXISTS early_acceptance_reason text/);
    // A CHECK é o que impede uma linha carimbada que não diz quem nem por quê.
    assert.match(MIG, /selection_applications_early_acceptance_complete/);
    assert.match(MIG, /early_acceptance_at IS NULL[\s\S]{0,200}early_acceptance_by IS NOT NULL/);
  });

  it('não existe booleano espelho do carimbo', () => {
    // Duas fontes da mesma verdade derivam. `early_acceptance_at IS NOT NULL` É a flag.
    assert.doesNotMatch(semComentarios(MIG), /ADD COLUMN IF NOT EXISTS (is_)?early_acceptance\s+boolean/i);
  });

  it('os três caminhos de escrita são redefinidos na MESMA migration', () => {
    assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.admin_update_application\(/);
    assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.finalize_decisions\(/);
    assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.admin_decide_dual_track\(/);
    // Muda a contagem de parâmetros (4 → 5): sem o DROP fica overload, e o PostgREST resolve a errada.
    assert.match(MIG, /DROP FUNCTION IF EXISTS public\.admin_decide_dual_track\(uuid, text, text, text\)/);
  });

  it('a deriva de EXECUTE some nas duas funções que a migration toca', () => {
    assert.match(MIG, /REVOKE EXECUTE ON FUNCTION public\.finalize_decisions\(uuid, jsonb\) FROM PUBLIC, anon/);
    assert.match(MIG, /REVOKE EXECUTE ON FUNCTION public\.admin_decide_dual_track\([^)]*\) FROM PUBLIC, anon/);
  });

  it('o contador entra no get_selection_health', () => {
    assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.get_selection_health\(/);
    assert.match(MIG, /decided_without_evaluation/);
  });
});

// ── Corpo VIVO: o portão está no banco, não só no arquivo ─────────────────────────────────────────
describe('#1572 — corpo vivo dos caminhos de decisão', () => {
  const corpos = new Map();

  before(async () => {
    if (!dbGated) return;
    for (const fn of [...ESCRITORES, 'get_selection_health']) {
      const { data, error } = await sb.rpc('_audit_function_source', { p_proname: fn });
      assert.ifError(error);
      assert.ok(data?.length > 0, `${fn} não existe no banco`);
      // Sem esta asserção um prosrc vazio faria os assert.match abaixo falharem por ausência de
      // leitura, e os doesNotMatch passarem pelo mesmo motivo.
      assert.ok(typeof data[0].prosrc === 'string' && data[0].prosrc.length > 200, `corpo vivo de ${fn} precisa ser legível`);
      corpos.set(fn, semComentarios(data[0].prosrc));
    }
  });

  it('admin_update_application conta avaliação de QUALQUER tipo e recusa sem justificativa', { skip: dbGated ? false : skipMsg }, () => {
    const src = corpos.get('admin_update_application');
    assert.match(src, /FROM public\.selection_evaluations/);
    assert.match(src, /early_acceptance_reason_required/);
    // O portão cobre a TRANSIÇÃO para approved, não o estado: reaprovar quem já está aprovado não
    // pode voltar a pedir justificativa.
    assert.match(src, /v_requested_status = 'approved' AND v_old_status <> 'approved'/);
    // A contagem não pode filtrar por evaluation_type: `peer_eval_count` do dashboard só conta
    // 'objective', e essa é justamente a divergência que faria a UI esconder o campo.
    const trecho = src.match(/SELECT count\(\*\) INTO v_eval_count[\s\S]{0,240}/);
    assert.ok(trecho, 'a contagem de avaliações precisa existir para ser auditada');
    assert.doesNotMatch(trecho[0], /evaluation_type/);
  });

  it('a recusa acontece ANTES do UPDATE de status', { skip: dbGated ? false : skipMsg }, () => {
    const src = corpos.get('admin_update_application');
    const posRecusa = src.indexOf('early_acceptance_reason_required');
    const posUpdate = src.indexOf('UPDATE public.selection_applications SET');
    assert.ok(posRecusa > 0 && posUpdate > 0, 'recusa e UPDATE precisam existir');
    assert.ok(
      posRecusa < posUpdate,
      'a recusa depois do UPDATE deixaria a candidatura aprovada sem o carimbo que a explica',
    );
  });

  it('o carimbo só entra quando o approved realmente pegou', { skip: dbGated ? false : skipMsg }, () => {
    const src = corpos.get('admin_update_application');
    // O gate do #1613 pode suprimir o status pedido. Carimbar antes de ler o RETURNING registraria
    // um aceite antecipado que não aconteceu.
    const posSuprimido = src.indexOf('v_gate_suppressed :=');
    const posCarimbo = src.indexOf('early_acceptance_at     = now()');
    assert.ok(posSuprimido > 0 && posCarimbo > 0, 'gate #1613 e carimbo precisam existir');
    assert.ok(posCarimbo > posSuprimido, 'o carimbo tem de vir depois de saber se o status pegou');
  });

  it('finalize_decisions aplica a mesma régua e devolve o que NÃO aplicou', { skip: dbGated ? false : skipMsg }, () => {
    const src = corpos.get('finalize_decisions');
    assert.match(src, /early_acceptance_reason_required/);
    // Sem `refused` no retorno o lote devolve um `approved` menor e ninguém sabe quais ficaram fora.
    assert.match(src, /'refused'/);
    assert.match(src, /canonical_approval_failed/);
  });

  it('admin_decide_dual_track repassa a justificativa e CONFERE as duas pontas', { skip: dbGated ? false : skipMsg }, () => {
    const src = corpos.get('admin_decide_dual_track');
    assert.match(src, /early_acceptance_reason/);
    // O defeito pré-existente: os retornos iam para variável e ninguém os lia, então `{"error":...}`
    // virava `success: true` na tela.
    assert.match(src, /v_researcher_result->>'error'/);
    assert.match(src, /v_leader_result->>'error'/);
    assert.match(src, /RAISE EXCEPTION/);
  });

  it('get_selection_health separa justificado de não justificado', { skip: dbGated ? false : skipMsg }, () => {
    const src = corpos.get('get_selection_health');
    assert.match(src, /approved_without_evaluation/);
    assert.match(src, /approved_without_evaluation_justified/);
    assert.match(src, /rejected_without_evaluation/);
    // O sinal olha o ciclo ATIVO: contar o histórico prenderia o painel em amarelo pelas linhas de
    // 2025, que já não têm como ganhar justificativa.
    assert.match(src, /v_unjustified_active/);
  });

  it('#1801 — o ciclo ATIVO resolve por STATUS, e não pela data de escrita da linha', { skip: dbGated ? false : skipMsg }, () => {
    // Sem isto o contador acima aponta para o ciclo errado e o amarelo fica preso: `created_at` é a
    // data de ESCRITA, e o backfill do cycle2-2025 (13/07/2026) tornou um ciclo FECHADO a linha mais
    // nova da tabela. Mesma causa 1 da #1586(b), em outra função.
    const src = corpos.get('get_selection_health');
    assert.match(src, /\(c\.status = 'open'\) DESC/);
    // Um segundo ciclo aberto não pode sumir calado: a função devolve UM ciclo, mas conta quantos há.
    assert.match(src, /v_open_cycles/);
    assert.match(src, /'open_cycles'/);
  });
});

// ── Superfície viva: colunas, ACL e fail-closed ───────────────────────────────────────────────────
describe('#1572 — superfície', () => {
  it('as três colunas existem na tabela', { skip: dbGated ? false : skipMsg }, async () => {
    const { error } = await sb
      .from('selection_applications')
      .select('id, early_acceptance_at, early_acceptance_by, early_acceptance_reason')
      .limit(1);
    assert.ifError(error);
  });

  it('nem finalize_decisions nem admin_decide_dual_track são executáveis por anon', { skip: dbGated ? false : skipMsg }, async () => {
    const { data, error } = await sb.rpc('_audit_function_execute_acl', {
      p_names: ['finalize_decisions', 'admin_decide_dual_track'],
    });
    assert.ifError(error);
    assert.ok(data?.length >= 2, 'as duas funções precisam aparecer no audit de ACL');
    for (const linha of data) {
      assert.equal(linha.anon_exec, false, `${linha.proname} não pode ter EXECUTE para anon (deriva da #1592)`);
      assert.equal(linha.authenticated_exec, true, `${linha.proname} precisa seguir alcançável pelo GP logado`);
    }
  });

  it('os três escritores seguem fail-closed para quem não tem sessão', { skip: dbGated ? false : skipMsg }, async () => {
    // service_role tem auth.uid() nulo: a resposta esperada é a recusa de autoria, o que prova que a
    // função existe, está publicada e barra antes de escrever. NÃO prova o portão do #1572 — isso
    // vem do catálogo acima.
    const { data, error } = await sb.rpc('admin_update_application', {
      p_application_id: '00000000-0000-0000-0000-000000000000',
      p_data: { status: 'approved' },
    });
    assert.ifError(error);
    assert.equal(data?.error, 'Unauthorized');
  });

  it('#1801 — a armadilha do created_at é load-bearing nos dados de hoje', { skip: dbGated ? false : skipMsg }, async () => {
    // O guard estático acima só vale enquanto a inversão existir de fato. Aqui se confirma que a
    // linha mais nova por `created_at` NÃO é o ciclo aberto — se um dia deixar de ser, este teste
    // avisa que a trava perdeu o objeto em vez de seguir verde por acaso.
    const { data, error } = await sb
      .from('selection_cycles')
      .select('cycle_code, status, created_at')
      .order('created_at', { ascending: false });
    assert.ifError(error);
    assert.ok(data?.length >= 2, 'precisa de ao menos dois ciclos para a inversão existir');

    const abertos = data.filter((c) => c.status === 'open');
    if (abertos.length === 0) return;  // sem ciclo aberto a resolução cai no fallback, e tudo bem

    assert.notEqual(
      data[0].status,
      'open',
      'a inversão sumiu: o mais novo por created_at voltou a ser o aberto, e o guard do #1801 perdeu o objeto',
    );
  });

  it('a população decidida sem avaliação é NÃO VAZIA (o portão é load-bearing)', { skip: dbGated ? false : skipMsg }, async () => {
    const { data: decididas, error: e1 } = await sb
      .from('selection_applications')
      .select('id')
      .in('status', ['approved', 'converted', 'rejected']);
    assert.ifError(e1);

    const { data: avaliadas, error: e2 } = await sb.from('selection_evaluations').select('application_id');
    assert.ifError(e2);

    const comAvaliacao = new Set((avaliadas ?? []).map((r) => r.application_id));
    const semAvaliacao = (decididas ?? []).filter((r) => !comAvaliacao.has(r.id));

    assert.ok(
      semAvaliacao.length >= 1,
      'sem nenhuma decisão sem avaliação nos dados, o portão vira decoração e este contrato perde o objeto',
    );
  });
});
