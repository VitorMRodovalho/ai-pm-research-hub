// tests/contracts/2454-falha-de-acesso-ao-drive-avisa-quem-age.test.mjs
// Registrar em "test:behavioural" + "test:contracts" (#1109). NAO em test:structural: le o banco,
// e o guard #1908 exige DB-gated na faixa SERIALIZADA (#1509).
/**
 * Falha de acesso ao Drive avisa quem pode agir: o destinatario, quando a falha e dele; a gestao,
 * quando e da conta de servico.
 *
 * O CASO (#2454): as concessoes gravavam 'failed' e ninguem era avisado (o 'succeeded' do cron e so
 * o disparo HTTP). Medido em 24/09/2026: 3 pessoas sem acesso a pasta da iniciativa, as 3 por falha
 * do lado delas (2 sem conta Google, 1 dominio que bloqueia), sem saber.
 *
 * Exercido em transacao desfeita: falha da conta de servico na pasta = aviso aos 2 gestores;
 * regravar a mesma falha = nenhum aviso a mais; na curadoria, falha do destinatario nao vai a gestao
 * e falha da conta de servico vai. As 3 falhas reais receberam o aviso uma vez, na aplicacao.
 *
 * A CLASSIFICACAO e afirmada contra as mensagens REAIS da API guardadas no banco: se a Google mudar
 * o texto, o caso real deixa de cair na classe certa e este teste reprova.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

function sql(body) {
  return body.split('\n').map((l) => { const i = l.indexOf('--'); return i >= 0 ? l.slice(0, i) : l; })
    .join('\n').replace(/\s+/g, ' ');
}

/** O gatilho avisa uma vez: so na transicao para 'failed' (e no INSERT ja falho). */
export function soNaTransicao(body) {
  return /IF NEW\.status = 'failed' AND \(TG_OP = 'INSERT' OR OLD\.status IS DISTINCT FROM 'failed'\) THEN/.test(sql(body));
}

/** O roteamento: destinatario -> a pessoa (so pasta, e so sem acesso por outro e-mail); resto -> gestao. */
export function roteamento(body) {
  const c = sql(body);
  return {
    destinatarioAPessoa: /IF v_class IN \('recipient_no_google', 'recipient_domain_blocked'\) THEN[^]*?create_notification\( p_member_id, 'drive_access_action_needed'/.test(c),
    naoAvisaQuemTemOutroAcesso: /g\.grantee_member_id = p_member_id AND g\.drive_folder_id = p_folder_id AND g\.status = 'granted'\) THEN RETURN v_class;/.test(c),
    contaDeServicoAGestao: /ELSE FOR v_gp IN SELECT m\.id FROM public\.members m WHERE[^]*?can_by_member\(m\.id, 'manage_platform'\) LOOP PERFORM public\.create_notification\( v_gp\.id, 'drive_access_admin_needed'/.test(c),
  };
}

async function corpo(proname) {
  const { data, error } = await sb().rpc('_audit_function_source', { p_proname: proname });
  assert.equal(error, null, `_audit_function_source(${proname}) falhou: ${error?.message ?? ''}`);
  assert.ok(Array.isArray(data) && data.length === 1, `${proname}: esperava 1 sobrecarga, veio ${data?.length}`);
  return data[0].prosrc;
}

const allTrue = (o) => Object.fromEntries(Object.keys(o).map((k) => [k, true]));

test(dbGated ? '#2454: o corpo vivo avisa uma vez e roteia pela classe da falha' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    assert.ok(soNaTransicao(await corpo('trg_drive_membership_grant_failed')), 'o aviso de pasta passou a repetir a cada reconciliacao');
    const r = roteamento(await corpo('_notify_drive_grant_failure'));
    assert.deepEqual(r, allTrue(r), 'o roteamento do aviso de falha mudou');
  });

test(dbGated ? '#2454: as falhas reais guardadas no banco caem na classe certa' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    const { data, error } = await sb().from('drive_membership_grants').select('api_error').eq('status', 'failed');
    assert.equal(error, null);
    // controle negativo: um 403 generico de permissao e da conta de servico
    const { data: ctrl } = await sb().rpc('_drive_grant_failure_class',
      { p_api_error: { status: 403, message: 'The user does not have sufficient permissions for this file.' } });
    assert.equal(ctrl, 'service_account');
    // sem falha real guardada no dia, so o controle roda (a classificacao real e afirmada quando houver)
    if (!data.length) return;
    for (const row of data) {
      const { data: cls, error: e } = await sb().rpc('_drive_grant_failure_class', { p_api_error: row.api_error });
      assert.equal(e, null, `_drive_grant_failure_class indisponivel: ${e?.message ?? ''}`);
      const msg = String(row.api_error?.message ?? '');
      const esperado = /not have a Google Account/i.test(msg) ? 'recipient_no_google'
        : /disabled the ability to receive items/i.test(msg) ? 'recipient_domain_blocked' : 'service_account';
      assert.equal(cls, esperado, `falha real classificada como ${cls}, esperado ${esperado}`);
    }
  });

test('#2454 mutacao: cada detector reprova a forma do defeito, pela MESMA funcao', () => {
  const m = (src, a, b) => { const out = src.replace(a, b); assert.notEqual(out, src, `mutacao nao aplicou: ${a}`); return out; };
  const T = "IF NEW.status = 'failed' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'failed') THEN";
  assert.equal(soNaTransicao(T), true);
  // 1: avisa a cada reconciliacao (sem a transicao)
  assert.equal(soNaTransicao(m(T, " AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'failed')", '')), false);

  const R = `IF v_class IN ('recipient_no_google', 'recipient_domain_blocked') THEN
    IF EXISTS (SELECT 1 FROM public.drive_membership_grants g WHERE g.grantee_member_id = p_member_id AND g.drive_folder_id = p_folder_id AND g.status = 'granted') THEN RETURN v_class; END IF;
    PERFORM public.create_notification( p_member_id, 'drive_access_action_needed', 'x');
  ELSE FOR v_gp IN SELECT m.id FROM public.members m WHERE m.member_status = 'active' AND public.can_by_member(m.id, 'manage_platform')
    LOOP PERFORM public.create_notification( v_gp.id, 'drive_access_admin_needed', 'x'); END LOOP; END IF;`;
  assert.deepEqual(roteamento(R), allTrue(roteamento(R)));
  // 2: avisa a pessoa mesmo quando ela tem acesso por outro e-mail
  assert.equal(roteamento(m(R, " AND g.status = 'granted') THEN RETURN v_class;", " AND false) THEN RETURN v_class;")).naoAvisaQuemTemOutroAcesso, false);
  // 3: falha da conta de servico sem aviso a gestao
  assert.equal(roteamento(m(R, "'drive_access_admin_needed'", "'info'")).contaDeServicoAGestao, false);
  // 4: falha do destinatario vai para a gestao em vez da pessoa
  assert.equal(roteamento(m(R, "create_notification( p_member_id, 'drive_access_action_needed'", "create_notification( v_gp.id, 'drive_access_action_needed'")).destinatarioAPessoa, false);
});
