// tests/contracts/2444-rodizio-de-pareceristas.test.mjs
// Registrar em "test:behavioural" + "test:contracts" (#1109). NAO em test:structural: le o banco,
// e o guard #1908 exige DB-gated na faixa SERIALIZADA (#1509).
/**
 * A curadoria designa dono para o parecer, lembra antes do prazo e escalona no vencimento.
 *
 * O CASO (#2444): o pool aberto deixava o parecer sem dono. Medido em 24/09/2026: 0 designacoes
 * na historia, 0 pareceres nos cards que chegaram a curadoria, prazos vencidos sem lembrete.
 *
 * Exercido em transacao desfeita (24/09/2026), com um card real movido para curation_pending:
 * 2 designados por rodizio, 2 avisos imediatos, 2 eventos reviewer_assigned; lembrete a 1 dia do
 * prazo = 2; no vencimento, 1 substituido (o unico curador livre) e 1 escalonado sem substituto,
 * 4 avisos a quem gere a plataforma (2 x 2); segunda passada = 0 (idempotente).
 *
 * As funcoes de decisao recebem texto puro: sao as MESMAS que julgam o corpo vivo e o adulterado.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

/** Remove comentarios de linha SQL e normaliza espacos. */
function sql(body) {
  return body.split('\n').map((l) => { const i = l.indexOf('--'); return i >= 0 ? l.slice(0, i) : l; })
    .join('\n').replace(/\s+/g, ' ');
}

/** Quem pode ser designado: as DUAS capacidades (designar e dar parecer) e nunca o autor. */
export function elegibilidade(body) {
  const c = sql(body);
  return {
    podeSerDesignado: /can_by_member\(m\.id, 'curate_content'\)/.test(c),
    podeDarParecer: /can_by_member\(m\.id, 'participate_in_governance_review'\)/.test(c),
    comLogin: /m\.auth_id IS NOT NULL/.test(c),
    naoAutor: /bia\.role IN \('author', 'contributor'\)/.test(c) && /m\.id IS DISTINCT FROM \(SELECT bi\.assignee_id/.test(c),
  };
}

/** A entrada na fila: pula arquivado e confidencial, e completa ate o numero exigido. */
export function autoAssign(body) {
  const c = sql(body);
  return {
    pulaArquivado: /IF v_item\.status = 'archived' THEN RETURN 0; END IF;/.test(c),
    pulaConfidencial: /i\.visibility = 'confidential'\) THEN RETURN 0;/.test(c),
    completaAteExigido: /LIMIT greatest\(v_required - v_active, 0\)/.test(c),
    porMenorCarga: /ORDER BY e\.open_load ASC, e\.last_assigned_at ASC NULLS FIRST/.test(c),
  };
}

/** O job: lembra dentro de 2 dias, e no vencimento marca, troca se puder e escalona. */
export function varredura(body) {
  const c = sql(body);
  return {
    lembreteEm2Dias: /ca\.due_at > now\(\) AND ca\.due_at <= now\(\) \+ interval '2 days'/.test(c),
    lembraUmaVez: /ca\.reminded_at IS NULL/.test(c) && /SET reminded_at = now\(\)/.test(c),
    vencidoUmaVez: /ca\.overdue_at IS NULL AND bi\.curation_status = 'curation_pending'[^;]*ca\.due_at <= now\(\)/.test(c)
      && /SET overdue_at = now\(\)/.test(c),
    trocaSeHouverLivre: /IF v_repl IS NOT NULL THEN UPDATE public\.curation_reviewer_assignments SET released_at = now\(\)[^;]*; PERFORM public\._curation_assign_one\(a\.board_item_id, a\.review_round, v_repl, 'reassign', NULL\)/.test(c),
    escalonaAoGp: /can_by_member\(m\.id, 'manage_platform'\) LOOP PERFORM public\.create_notification\( v_gp\.id, 'curation_review_overdue'/.test(c),
  };
}

async function corpo(proname) {
  const { data, error } = await sb().rpc('_audit_function_source', { p_proname: proname });
  assert.equal(error, null, `_audit_function_source(${proname}) falhou: ${error?.message ?? ''}`);
  assert.ok(Array.isArray(data) && data.length === 1, `${proname}: esperava 1 sobrecarga, veio ${data?.length}`);
  return data[0].prosrc;
}

const allTrue = (o) => Object.fromEntries(Object.keys(o).map((k) => [k, true]));

test(dbGated ? '#2444: o corpo vivo do rodizio decide como desenhado' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    const e = elegibilidade(await corpo('_curation_eligible_reviewers'));
    assert.deepEqual(e, allTrue(e), 'elegibilidade de parecerista mudou');
    const a = autoAssign(await corpo('_curation_auto_assign'));
    assert.deepEqual(a, allTrue(a), 'a entrada na fila deixou de designar como desenhado');
    const v = varredura(await corpo('curation_reviewer_sla_sweep'));
    assert.deepEqual(v, allTrue(v), 'o job de prazo deixou de lembrar, trocar ou escalonar');
  });

test(dbGated ? '#2444: os avisos do rodizio saem na hora, nao no digest semanal' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    for (const t of ['curation_review_assigned', 'curation_review_overdue']) {
      const { data, error } = await sb().rpc('_delivery_mode_for', { p_type: t });
      assert.equal(error, null, `_delivery_mode_for indisponivel: ${error?.message ?? ''}`);
      assert.equal(data, 'transactional_immediate', `${t} cairia em ${data}`);
    }
    // controle: o ELSE continua sendo digest_weekly, entao o teste sabe dizer nao
    const { data: outro } = await sb().rpc('_delivery_mode_for', { p_type: 'tipo_que_nao_existe_2444' });
    assert.equal(outro, 'digest_weekly');
  });

test('#2444 mutacao: cada detector reprova a forma do defeito, pela MESMA funcao', () => {
  // toda mutacao tem de MUDAR o texto; uma que nao aplica le como "detector aprovou"
  const m = (src, a, b) => { const out = src.replace(a, b); assert.notEqual(out, src, `mutacao nao aplicou: ${a}`); return out; };
  const ELEG = `WHERE m.member_status = 'active' AND m.auth_id IS NOT NULL
     AND public.can_by_member(m.id, 'curate_content')
     AND public.can_by_member(m.id, 'participate_in_governance_review')
     AND m.id IS DISTINCT FROM (SELECT bi.assignee_id FROM public.board_items bi WHERE bi.id = p_item_id)
     AND NOT EXISTS (SELECT 1 FROM public.board_item_assignments bia WHERE bia.item_id = p_item_id
        AND bia.member_id = m.id AND bia.role IN ('author', 'contributor'))`;
  assert.deepEqual(elegibilidade(ELEG), allTrue(elegibilidade(ELEG)));
  // 1: designar quem nao pode dar parecer (a submit_curation_review recusaria)
  assert.equal(elegibilidade(m(ELEG, "AND public.can_by_member(m.id, 'participate_in_governance_review')", '')).podeDarParecer, false);
  // 2: autor pode ser designado
  assert.equal(elegibilidade(m(ELEG, "bia.role IN ('author', 'contributor')", "bia.role IN ('reviewer')")).naoAutor, false);
  // 3: regra so em comentario
  assert.equal(elegibilidade(m(ELEG, "WHERE m.member_status = 'active' AND m.auth_id IS NOT NULL", "WHERE m.member_status = 'active' -- AND m.auth_id IS NOT NULL")).comLogin, false);

  const AUTO = `IF v_item.status = 'archived' THEN RETURN 0; END IF;
    IF EXISTS (SELECT 1 FROM x WHERE pb.id = v_item.board_id AND i.visibility = 'confidential') THEN RETURN 0; END IF;
    SELECT e.member_id FROM f e ORDER BY e.open_load ASC, e.last_assigned_at ASC NULLS FIRST, e.member_id
     LIMIT greatest(v_required - v_active, 0)`;
  assert.deepEqual(autoAssign(AUTO), allTrue(autoAssign(AUTO)));
  // 4: card arquivado volta a receber designacao
  assert.equal(autoAssign(m(AUTO, "IF v_item.status = 'archived' THEN RETURN 0; END IF;", '')).pulaArquivado, false);
  // 5: designa um numero fixo, ignorando quem ja esta ativo
  assert.equal(autoAssign(m(AUTO, 'LIMIT greatest(v_required - v_active, 0)', 'LIMIT 2')).completaAteExigido, false);

  const SWEEP = `WHERE ca.released_at IS NULL AND ca.reminded_at IS NULL AND ca.overdue_at IS NULL
       AND ca.due_at > now() AND ca.due_at <= now() + interval '2 days' LOOP
    UPDATE public.curation_reviewer_assignments SET reminded_at = now() WHERE id = a.id;
    WHERE ca.released_at IS NULL AND ca.overdue_at IS NULL AND bi.curation_status = 'curation_pending' AND ca.due_at <= now() LOOP
    UPDATE public.curation_reviewer_assignments SET overdue_at = now() WHERE id = a.id;
    IF v_repl IS NOT NULL THEN UPDATE public.curation_reviewer_assignments SET released_at = now() WHERE id = a.id;
      PERFORM public._curation_assign_one(a.board_item_id, a.review_round, v_repl, 'reassign', NULL);
    END IF;
    FOR v_gp IN SELECT m.id FROM public.members m WHERE public.can_by_member(m.id, 'manage_platform')
    LOOP PERFORM public.create_notification( v_gp.id, 'curation_review_overdue', 'x');`;
  assert.deepEqual(varredura(SWEEP), allTrue(varredura(SWEEP)));
  // 6: lembrete sem teto de uma vez (lembraria todo dia)
  assert.equal(varredura(m(SWEEP, 'SET reminded_at = now()', 'SET due_at = due_at')).lembraUmaVez, false);
  // 7: vencido sem marca (escalonaria todo dia)
  assert.equal(varredura(m(SWEEP, 'SET overdue_at = now()', 'SET due_at = due_at')).vencidoUmaVez, false);
  // 8: vencido sem aviso a quem gere
  assert.equal(varredura(m(SWEEP, "'curation_review_overdue'", "'info'")).escalonaAoGp, false);
  // 9: troca sem liberar o anterior (o vencido seguiria contando como designado)
  assert.equal(varredura(m(SWEEP, 'IF v_repl IS NOT NULL THEN UPDATE public.curation_reviewer_assignments SET released_at = now() WHERE id = a.id;', 'IF v_repl IS NOT NULL THEN')).trocaSeHouverLivre, false);
});
