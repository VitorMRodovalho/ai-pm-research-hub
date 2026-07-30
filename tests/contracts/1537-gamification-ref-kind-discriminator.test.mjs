import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

/**
 * #1537 item 3, fase 1 — `gamification_points.ref_id` é POLIMÓRFICO: aponta para 9 tabelas diferentes
 * (attendance, events, document_versions, board_items, event_showcases, meeting_artifacts,
 * meeting_action_items, event_agenda_blocks, champions_awarded) sem nenhuma coluna dizendo qual.
 *
 * Isso já custou caro duas vezes: no #1528 uma auditoria que juntava por um lado só devolveu ZERO e quase
 * virou "a issue está errada"; e no #1534 quarenta linhas órfãs sobreviveram meses porque a coluna
 * polimórfica impede FK.
 *
 * A fase 1 fecha a porta para linhas NOVAS (trigger que deriva) e classifica o histórico resolvível. As
 * não-resolvidas ficam com ref_kind NULL DE PROPÓSITO — é a dívida da fase 2, e este guard existe para que
 * ela só possa DIMINUIR.
 *
 * Semântica que os testes protegem: 'none' = categoria sem referência por natureza · <tabela> = resolvida ·
 * NULL = não classificado. Se NULL voltar a significar as duas coisas, o vício original está de volta.
 */

const URL = process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = URL && KEY ? createClient(URL, KEY, { auth: { persistSession: false } }) : null;

// Teto histórico medido em 2026-07-30, logo após o backfill. Só pode CAIR: cada linha resolvida na fase 2
// abaixa este número. Se subir, uma linha nova nasceu órfã e o trigger avisou por RAISE WARNING.
const UNCLASSIFIED_BASELINE = 176;

test('#1537 a coluna ref_kind existe e o backfill classificou o histórico resolvível', { skip: !sb }, async () => {
  const { data, error } = await sb.from('gamification_points').select('ref_kind');
  assert.equal(error, null, `leitura de gamification_points falhou: ${error?.message}`);
  assert.ok(data.length > 0, 'sem linhas para avaliar — o teste não pode passar por vacuidade');

  const kinds = new Set(data.map((r) => r.ref_kind));
  assert.ok(kinds.has('attendance'), "backfill deve ter classificado linhas como 'attendance'");
  assert.ok(kinds.has('none'), "backfill deve ter marcado 'none' nas categorias sem referência");
});

test('#1537 nenhum valor fora do vocabulário do CHECK', { skip: !sb }, async () => {
  const PERMITIDOS = new Set([
    'none', 'attendance', 'event', 'document_version', 'board_item', 'event_showcase',
    'meeting_artifact', 'meeting_action_item', 'event_agenda_block', 'champion_award',
  ]);
  const { data, error } = await sb.from('gamification_points').select('ref_kind');
  assert.equal(error, null, `leitura falhou: ${error?.message}`);
  const invalidos = [...new Set(data.map((r) => r.ref_kind))].filter((k) => k !== null && !PERMITIDOS.has(k));
  assert.deepEqual(invalidos, [], `ref_kind fora do vocabulário: ${invalidos.join(', ')}`);
});

test('#1537 a dívida de não-classificadas não cresce (ratchet)', { skip: !sb }, async () => {
  const { data, error } = await sb
    .from('gamification_points')
    .select('id, category, ref_id, ref_kind')
    .is('ref_kind', null);
  assert.equal(error, null, `leitura falhou: ${error?.message}`);

  // Toda não-classificada TEM de ter ref_id preenchido: ref_id nulo vira 'none', nunca NULL. Se aparecer
  // uma com ref_id nulo, o trigger não rodou (ou foi contornado) e o NULL voltou a ter dois significados.
  const semRef = data.filter((r) => r.ref_id === null);
  assert.deepEqual(
    semRef.map((r) => r.id),
    [],
    'linha com ref_id NULL deveria ter ref_kind = none, não NULL — o trigger não classificou',
  );

  assert.ok(
    data.length <= UNCLASSIFIED_BASELINE,
    `não-classificadas subiram de ${UNCLASSIFIED_BASELINE} para ${data.length}: uma linha nova nasceu ` +
      'apontando para um alvo inexistente (classe do #1534). Investigar antes de mexer no baseline.',
  );

  if (data.length < UNCLASSIFIED_BASELINE) {
    console.warn(
      `[#1537] dívida caiu para ${data.length} (baseline ${UNCLASSIFIED_BASELINE}) — abaixe a constante.`,
    );
  }
});

test('#1537 o trigger deriva ref_kind sem que o chamador precise passar', { skip: !sb }, async () => {
  // DEZ funções inserem em gamification_points; nenhuma passa ref_kind. O valor tem de aparecer sozinho,
  // senão a porta continua aberta para linhas novas não classificadas.
  const { data: att } = await sb.from('attendance').select('id, member_id').limit(1);
  assert.ok(att?.length, 'sem linha de attendance para o teste');

  const { data: inserida, error: insErr } = await sb
    .from('gamification_points')
    .insert({
      member_id: att[0].member_id,
      points: 0,
      reason: 'TESTE #1537 trigger ref_kind',
      category: 'attendance',
      ref_id: att[0].id,
    })
    .select('id, ref_kind')
    .single();

  try {
    assert.equal(insErr, null, `insert falhou: ${insErr?.message}`);
    assert.equal(
      inserida.ref_kind,
      'attendance',
      'o trigger deveria ter derivado ref_kind=attendance sem o chamador informar',
    );
  } finally {
    // A suíte escreve na produção e não faz rollback (tx=rollback não vale para SECDEF), então a limpeza
    // é explícita e roda mesmo se a asserção falhar.
    if (inserida?.id) await sb.from('gamification_points').delete().eq('id', inserida.id);
  }
});
