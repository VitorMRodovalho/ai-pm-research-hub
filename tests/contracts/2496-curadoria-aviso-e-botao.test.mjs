/**
 * Contract #2496 — curadoria: a tribo é avisada na ENTRADA em curadoria, e o botão de parecer do
 * card segue a regra de `submit_curation_review`.
 *
 * Medido em 2026-09-27, no único item em `curation_pending`:
 *   - a tribo recebia só `card_moved` (digest_weekly), com o código cru do status e link genérico;
 *     nenhuma das 3 pessoas recebeu e-mail, e quem tinha dois papéis no card recebia em dobro;
 *   - o botão "Submeter Parecer" do card seguia `canManageBoard || designação curator/co_gp`:
 *     os 2 revisores designados não o viam, e a liderança e os autores do próprio item o viam.
 *
 * Asserções amarram CONDIÇÃO ao RESULTADO dentro do bloco que decide, com comentários mascarados.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const notify = maskLineComments(latestFunctionCapture(ROOT, 'notify_on_curation_status_change').body);
const delivery = maskLineComments(latestFunctionCapture(ROOT, '_delivery_mode_for').body);
const catalog = JSON.parse(readFileSync(resolve(ROOT, 'docs/adr/ADR-0022-notification-types-catalog.json'), 'utf8'));
const perms = maskJsComments(readFileSync(resolve(ROOT, 'src/hooks/useBoardPermissions.ts'), 'utf8'));
const card = maskJsComments(readFileSync(resolve(ROOT, 'src/components/board/CardDetail.tsx'), 'utf8'));

/** O bloco `IF NEW.curation_status ... END IF;` que contém a âncora (sem IF aninhado nesses blocos). */
function ifBlockContaining(body, anchor) {
  const at = body.indexOf(anchor);
  assert.ok(at !== -1, `âncora ausente do corpo vigente: ${anchor}`);
  const start = body.lastIndexOf('IF NEW.curation_status', at);
  const end = body.indexOf('END IF;', at);
  assert.ok(start !== -1 && end !== -1, `bloco IF em volta de ${anchor} não encontrado`);
  return body.slice(start, end);
}

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── Aviso à tribo ───────────────────────────────────────────────────────────────────────────────
// #2621: o bloco do aviso à tribo passou a cobrir também as DECISÕES da curadoria (classe em
// `v_kind`, tipo em `v_type`, um laço só). As decisões são afirmadas em 2621-decisao-da-curadoria-*.
function tribeBlock() {
  const start = notify.indexOf('IF v_kind IS NOT NULL THEN');
  const end = notify.lastIndexOf('RETURN NEW;');
  assert.ok(start !== -1 && end > start, 'bloco do aviso à tribo ausente do corpo vigente');
  return notify.slice(start, end);
}

test('#2496: a TRANSIÇÃO para curation_pending emite curation_submitted_to_tribe', () => {
  const block = tribeBlock();
  assert.match(notify,
    /v_kind := CASE\s+WHEN NEW\.curation_status = 'curation_pending'\s+AND OLD\.curation_status IS DISTINCT FROM 'curation_pending'\s+THEN 'entrada'/,
    'a entrada só é reconhecida na transição (idempotente)');
  assert.match(block, /v_type := CASE v_kind\s+WHEN 'entrada'\s+THEN 'curation_submitted_to_tribe'/,
    'a entrada vira o tipo do aviso à tribo');
  assert.match(block,
    /PERFORM create_notification\(\s*v_recipient\.member_id,\s*v_type,/,
    'cada destinatário do laço recebe o tipo da classe');
});

test('#2496: destinatários = participantes ∪ liderança ativa da iniciativa, só pessoas ativas', () => {
  const block = tribeBlock();
  assert.match(block,
    /FOR v_recipient IN\s+SELECT r\.member_id\s+FROM \(\s*SELECT bia\.member_id FROM board_item_assignments bia WHERE bia\.item_id = NEW\.id\s+UNION\s+SELECT m\.id FROM engagements e JOIN members m ON m\.person_id = e\.person_id[\s\S]*?e\.initiative_id = v_initiative_id\s+AND e\.status = 'active'\s+AND e\.role = 'leader'\s*\) r\s+JOIN members mr ON mr\.id = r\.member_id\s+WHERE mr\.member_status = 'active'\s+LOOP/,
    'UNION (não UNION ALL) dá uma linha por pessoa; a liderança vem do engajamento ativo');
  assert.match(block,
    /WHEN v_tribe_id IS NOT NULL\s+THEN '\/tribe\/' \|\| v_tribe_id \|\| '\?tab=board'/,
    'o link leva ao board da tribo');
});

test('#2496: card_moved deixa a ENTRADA para o aviso novo e não duplica pessoa', () => {
  const block = ifBlockContaining(notify, "'card_moved'");
  assert.match(block,
    /AND NEW\.curation_status != 'curation_pending' THEN\s+FOR v_assignee IN\s+SELECT DISTINCT bia\.member_id FROM board_item_assignments bia WHERE bia\.item_id = NEW\.id/,
    'o laço genérico exclui a transição de entrada e usa DISTINCT');
});

test('#2496: _delivery_mode_for manda o tipo novo para e-mail imediato', () => {
  assert.match(delivery, /WHEN 'curation_submitted_to_tribe'\s+THEN 'transactional_immediate'/);
  assert.equal(catalog.types.curation_submitted_to_tribe?.delivery_mode, 'transactional_immediate',
    'catálogo ADR-0022 declara o tipo como imediato');
});

// ── Botão de parecer no card ────────────────────────────────────────────────────────────────────
test('#2496: canCurate do board segue participate_in_governance_review, sem regra V3', () => {
  assert.match(perms,
    /const canReviewCuration = !sim\.active && canFor\('participate_in_governance_review'\);/,
    'mesma regra da função submit_curation_review, suprimida sob simulação');
  assert.match(perms, /canCurate: canReviewCuration,/, 'canCurate devolve exatamente essa regra');
  assert.doesNotMatch(perms, /includes\('curator'\)/, 'a designação V3 curator não decide mais nada aqui');
});

test('#2496: o botão some para a própria tribo do card', () => {
  assert.match(card,
    /const isOwnTribeOfCard =\s*\(!!cardInitiativeId && permissions\.member\?\.initiative_id === cardInitiativeId\)\s*\|\| \(cardTribeId !== null && permissions\.member\?\.tribe_id === cardTribeId\);/,
    'tribo/iniciativa do membro igual à do card');
  assert.match(card,
    /const isCurator = permissions\.canCurate && !isCardAssignee && !isOwnTribeOfCard;/,
    'participante e membro da tribo ficam de fora');
  assert.match(card,
    /\{isCurator && isCurationItem && !showReviewForm && \(\s*<button onClick=\{\(\) => setShowReviewForm\(true\)\}/,
    'é esse gate que decide o botão "Submeter Parecer"');
});

// ── Banco vivo ──────────────────────────────────────────────────────────────────────────────────
test('#2496 db: _delivery_mode_for(curation_submitted_to_tribe) = transactional_immediate',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { data, error } = await sb.rpc('_delivery_mode_for', { p_type: 'curation_submitted_to_tribe' });
    assert.ifError(error);
    assert.equal(data, 'transactional_immediate');
    // controle: a mesma chamada sabe dizer "não" para um tipo fora do catálogo
    const ctrl = await sb.rpc('_delivery_mode_for', { p_type: '__tipo_inexistente__' });
    assert.ifError(ctrl.error);
    assert.equal(ctrl.data, 'digest_weekly');
  });
