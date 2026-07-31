import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

/**
 * #1537 item 3 — `gamification_points.ref_id` é POLIMÓRFICO: aponta para DOZE tabelas diferentes sem
 * nenhuma coluna dizendo qual (ver VOCABULARIO abaixo, que é a lista viva).
 *
 * Isso já custou caro duas vezes: no #1528 uma auditoria que juntava por um lado só devolveu ZERO e quase
 * virou "a issue está errada"; e no #1534 quarenta linhas órfãs sobreviveram meses porque a coluna
 * polimórfica impede FK.
 *
 * A fase 1 fechou a porta para linhas NOVAS (trigger que deriva) e classificou o histórico resolvível. As
 * não-resolvidas ficam com ref_kind NULL DE PROPÓSITO — é a dívida da fase 2, e este guard existe para que
 * ela só possa DIMINUIR.
 *
 * A fase 2a corrigiu o próprio vocabulário: a fase 1 listou NOVE tabelas e leu as 176 sobras como dívida de
 * DADO, mas 134 delas resolviam em três tabelas que faltavam na lista (approval_signoffs, document_comments,
 * initiatives). Duas lições viraram guard aqui:
 *   1. lista incompleta faz referência boa parecer órfã — por isso o teste `nenhuma não-classificada resolve`
 *      abaixo varre TODAS as tabelas do vocabulário antes de aceitar uma linha como dívida real;
 *   2. um ratchet apoiado nesse engano quebra pela OPERAÇÃO NORMAL: como as três tabelas seguem em uso, cada
 *      ratificação assinada nascia NULL e teria estourado o teto de 176 sem nenhuma regressão real.
 *
 * Semântica que os testes protegem: 'none' = categoria sem referência por natureza · <tabela> = resolvida ·
 * NULL = não classificado. Se NULL voltar a significar as duas coisas, o vício original está de volta.
 */

const URL = process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = URL && KEY ? createClient(URL, KEY, { auth: { persistSession: false } }) : null;

/** ref_kind → tabela que ele discrimina. Espelha o CHECK e a cascata do trigger derivador. */
const VOCABULARIO = {
  attendance: 'attendance',
  event: 'events',
  document_version: 'document_versions',
  board_item: 'board_items',
  event_showcase: 'event_showcases',
  meeting_artifact: 'meeting_artifacts',
  meeting_action_item: 'meeting_action_items',
  event_agenda_block: 'event_agenda_blocks',
  champion_award: 'champions_awarded',
  approval_signoff: 'approval_signoffs',
  document_comment: 'document_comments',
  initiative: 'initiatives',
};

/**
 * ZERO ESTRITO desde a fase 2b. A escada foi 176 (fase 1) → 42 (fase 2a, quando 134 se revelaram vocabulário
 * faltando e não dívida) → 0 (fase 2b, quando as 42 órfãs REAIS ganharam `ref_kind = 'orphan'`).
 *
 * O ratchet só volta a admitir número maior que zero se alguém decidir que órfã nova é aceitável — e essa é
 * a decisão que este teto existe para forçar a acontecer explicitamente, em vez de a linha se esconder atrás
 * de um teto herdado.
 */
const UNCLASSIFIED_BASELINE = 0;

/**
 * As 42 revisadas em 2026-07-30 (#1534): alvo confirmadamente inexistente em TODO o schema, mérito
 * preservado por decisão do PM. Contagem congelada de propósito — se aparecer uma 43ª com 'orphan', alguém
 * concedeu o veredito humano sem revisão, que é o único jeito de este balde crescer.
 */
const ORPHAN_REVIEWED = 42;

test('#1537 a coluna ref_kind existe e o backfill classificou o histórico resolvível', { skip: !sb }, async () => {
  const { data, error } = await sb.from('gamification_points').select('ref_kind');
  assert.equal(error, null, `leitura de gamification_points falhou: ${error?.message}`);
  assert.ok(data.length > 0, 'sem linhas para avaliar — o teste não pode passar por vacuidade');

  const kinds = new Set(data.map((r) => r.ref_kind));
  assert.ok(kinds.has('attendance'), "backfill deve ter classificado linhas como 'attendance'");
  assert.ok(kinds.has('none'), "backfill deve ter marcado 'none' nas categorias sem referência");
  // Fase 2a: sem isto, reverter a migration do vocabulário devolveria as 98 ratificações ao balde NULL e
  // o único sintoma seria o ratchet — que ninguém lê enquanto estiver "verde por estar abaixo do teto".
  assert.ok(kinds.has('approval_signoff'), "fase 2a: ratificações devem estar em 'approval_signoff'");
});

test('#1537 nenhum valor fora do vocabulário do CHECK', { skip: !sb }, async () => {
  // 'none' e 'orphan' não estão em VOCABULARIO porque não discriminam tabela nenhuma: 'none' é ausência de
  // referência por natureza, 'orphan' é veredito humano sobre alvo inexistente.
  const PERMITIDOS = new Set(['none', 'orphan', ...Object.keys(VOCABULARIO)]);
  const { data, error } = await sb.from('gamification_points').select('ref_kind');
  assert.equal(error, null, `leitura falhou: ${error?.message}`);
  const invalidos = [...new Set(data.map((r) => r.ref_kind))].filter((k) => k !== null && !PERMITIDOS.has(k));
  assert.deepEqual(invalidos, [], `ref_kind fora do vocabulário: ${invalidos.join(', ')}`);
});

test("#1537 as 'orphan' continuam sem alvo, e são exatamente as revisadas", { skip: !sb }, async () => {
  // 'orphan' é um veredito sobre o mundo ("este alvo não existe"), e veredito sobre o mundo tem de ser
  // reconferido, não arquivado. Se uma document_version apagada for restaurada, a linha deixa de ser órfã e
  // precisa voltar a ser classificada — este teste é quem avisa.
  const { data, error } = await sb
    .from('gamification_points')
    .select('id, category, ref_id')
    .eq('ref_kind', 'orphan');
  assert.equal(error, null, `leitura falhou: ${error?.message}`);

  assert.equal(
    data.length,
    ORPHAN_REVIEWED,
    `'orphan' tem ${data.length} linhas, revisadas foram ${ORPHAN_REVIEWED}. Crescer aqui significa que ` +
      "alguém concedeu o veredito humano sem revisão — 'orphan' nunca é atribuído pelo trigger.",
  );

  const refs = [...new Set(data.map((r) => r.ref_id).filter(Boolean))];
  const ressuscitados = [];
  for (const [kind, tabela] of Object.entries(VOCABULARIO)) {
    const { data: achados, error: errTab } = await sb.from(tabela).select('id').in('id', refs);
    assert.equal(errTab, null, `leitura de ${tabela} falhou: ${errTab?.message}`);
    for (const linha of achados ?? []) ressuscitados.push(`${linha.id} voltou a existir em ${tabela} (=> ${kind})`);
  }

  assert.deepEqual(
    ressuscitados,
    [],
    "linha marcada 'orphan' tem alvo que EXISTE agora — o veredito caducou, reclassificar:\n" +
      ressuscitados.join('\n'),
  );
});

test('#1537 nenhuma não-classificada resolve em tabela do vocabulário', { skip: !sb }, async () => {
  // ESTE é o guard que a fase 1 não tinha, e a razão de 134 referências boas terem passado por órfãs. Uma
  // linha só pode ser chamada de dívida depois de NÃO ser encontrada em NENHUMA das tabelas do vocabulário.
  // Se alguma for encontrada, o defeito está no trigger/backfill (lista incompleta ou ordem), não no dado.
  const { data, error } = await sb
    .from('gamification_points')
    .select('id, category, ref_id')
    .is('ref_kind', null)
    .not('ref_id', 'is', null);
  assert.equal(error, null, `leitura falhou: ${error?.message}`);

  const refs = [...new Set(data.map((r) => r.ref_id))];
  if (refs.length === 0) return; // dívida zerada: nada a verificar, e o ratchet abaixo cobre o resto

  const resolviveis = [];
  for (const [kind, tabela] of Object.entries(VOCABULARIO)) {
    const { data: achados, error: errTab } = await sb.from(tabela).select('id').in('id', refs);
    assert.equal(errTab, null, `leitura de ${tabela} falhou: ${errTab?.message}`);
    for (const linha of achados ?? []) resolviveis.push(`${linha.id} existe em ${tabela} (=> ${kind})`);
  }

  assert.deepEqual(
    resolviveis,
    [],
    'linha marcada como não-classificada tem alvo EXISTENTE — o trigger deixou de classificá-la:\n' +
      resolviveis.join('\n'),
  );
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

  assert.deepEqual(
    data.map((r) => `${r.id} (${r.category}, ref_id=${r.ref_id})`),
    [],
    `não-classificadas deveriam ser ${UNCLASSIFIED_BASELINE} e são ${data.length}: uma linha nova nasceu ` +
      'apontando para alvo inexistente (classe do #1534). Duas saídas, nenhuma é mexer no teto: (a) o alvo ' +
      'existe e falta vocabulário — corrigir o trigger; (b) o alvo não existe — revisar e, se o mérito for ' +
      "para manter, marcar 'orphan' pelo id exato numa migration, como a fase 2b fez com as 42.",
  );
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
