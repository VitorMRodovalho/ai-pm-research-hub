// tests/contracts/2427-convite-de-acesso-fora-do-funil.test.mjs
// Registrar em "test:behavioural" + "test:contracts" (#1109). NAO em test:structural: le o banco,
// e o guard #1908 exige DB-gated na faixa SERIALIZADA (#1509).
/**
 * Membro criado FORA do funil tem porta de entrada: o GP oferece o convite de acesso.
 *
 * O CASO (#2427): criar membro e liga-lo a uma iniciativa da AUTORIDADE, nao da CONTA. Os dois
 * caminhos de acesso que existiam nao alcancam quem nasce pela tela do GP ou por SQL:
 * `request_account_claim` exige a pessoa ja logada, e `request_portal_account_setup` exige o
 * token do portal, que so existe para candidatura aprovada. O detector irmao
 * (`2427-vinculo-ativo-sem-porta-de-entrada`) conta quem ficou preso; este guard afirma a porta.
 *
 * O que decide, e onde cada asserção morde:
 *  1. RPC `admin_send_member_access`: o portao `manage_member` levanta ANTES de qualquer efeito;
 *     quem ja tem login volta `already_linked` (convidar criaria uma SEGUNDA identidade); inativo
 *     volta `inactive`; teto de 3 por hora; o payload do pg_net carrega SO o id.
 *  2. EF `send-portal-account-setup`, ramo `member_id`: so envia com um pedido recente da RPC no
 *     audit, conferido ANTES de gerar o link. Sem isso, qualquer chamada service_role convidaria.
 *  3. Tela: a criacao devolve o id e oferece o convite; membro ativo sem login ganha o botao.
 *
 * As funcoes de decisao recebem texto puro: sao as MESMAS que julgam o corpo vivo e o adulterado
 * das mutacoes.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
// O CI exporta SUPABASE_ANON_KEY (#1518); o .env local usa o nome PUBLIC_.
const ANON_KEY = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;
const dbGated = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

const EF = readFileSync('supabase/functions/send-portal-account-setup/index.ts', 'utf8');
const PAGE = readFileSync('src/pages/admin/member/[id].astro', 'utf8');

/** Remove comentarios de linha SQL e normaliza espacos. */
function sqlCode(body) {
  return body.split('\n').map((l) => { const i = l.indexOf('--'); return i >= 0 ? l.slice(0, i) : l; })
    .join('\n').replace(/\s+/g, ' ');
}

/** Posicao do primeiro efeito (audit ou despacho). Tudo que protege tem de vir antes dela. */
function primeiroEfeito(code) {
  const ix = [code.indexOf('INSERT INTO public.admin_audit_log'), code.indexOf('net.http_post')].filter((i) => i >= 0);
  return ix.length ? Math.min(...ix) : -1;
}

/** Cada regra da RPC, como condicao LIGADA ao resultado, antes do primeiro efeito. */
export function regrasDaRpc(body) {
  const code = sqlCode(body);
  const efeito = primeiroEfeito(code);
  const antes = (re) => { const m = code.match(re); return !!m && efeito > 0 && m.index < efeito; };
  const http = code.match(/net\.http_post\((.*?)\);/);
  const payload = http ? (http[1].match(/body\s*:=\s*(jsonb_build_object\([^)]*\))/) || [])[1] : null;
  return {
    portao: antes(/IF NOT public\.can_by_member\( ?v_caller ?, ?'manage_member' ?\) THEN RAISE EXCEPTION/),
    jaTemLogin: antes(/IF v_member\.auth_id IS NOT NULL THEN RETURN jsonb_build_object\( ?'success' ?, ?false ?, ?'state' ?, ?'already_linked'/),
    inativo: antes(/IF v_member\.is_active IS NOT TRUE OR v_member\.member_status IS DISTINCT FROM 'active' THEN RETURN jsonb_build_object\( ?'success' ?, ?false ?, ?'state' ?, ?'inactive'/),
    teto: antes(/action = 'member\.access_invite_requested' AND target_id = v_member\.id AND created_at > now\(\) - interval '1 hour'; IF v_recent >= 3 THEN RETURN jsonb_build_object\( ?'success' ?, ?false ?, ?'state' ?, ?'rate_limited'/),
    payloadSoId: payload === "jsonb_build_object('member_id', v_member.id)",
  };
}

/** O ramo member_id da EF: despachado pelo corpo, e o pedido conferido ANTES do link. */
export function efExigePedido(src) {
  const code = maskJsComments(src);
  const despacha = /if \(memberIdParam\) \{[\s\S]{0,200}?return await handleMemberInvite\(sb, memberIdParam\)/.test(code);
  const ini = code.indexOf('async function handleMemberInvite(');
  if (ini < 0) return { despacha, pedidoAntesDoLink: false, template: false };
  const fim = code.indexOf('\n}\n', ini);
  const fn = code.slice(ini, fim);
  const consulta = fn.search(/\.eq\('action', 'member\.access_invite_requested'\)/);
  const recusa = fn.search(/if \(!reqRow\) return json\(/);
  const link = fn.search(/actionLinkFor\(sb, email\)/);
  return {
    despacha,
    pedidoAntesDoLink: consulta > 0 && recusa > consulta && link > recusa,
    template: /p_template_slug: 'member_access_invite'/.test(fn),
  };
}

/** A tela: a criacao devolve o id e oferece o convite; o botao aparece para ativo sem login. */
export function telaOferece(src) {
  const code = maskJsComments(src);
  return {
    criaComId: /\.from\('members'\)\.insert\(\{[\s\S]*?\}\)\.select\('id'\)\.single\(\)/.test(code),
    ofereceAoCriar: /if \(isNew && result\?\.id && confirm\([^)]*\)\)\) \{\s*await sendAccessInvite\(result\.id\)/.test(code),
    chamaRpc: /sb\.rpc\('admin_send_member_access', \{ p_member_id: id \}\)/.test(code),
    botao: /!isNew && m\?\.is_active && !m\?\.auth_id \? `<button type="button" class="btn-send-access-invite/.test(code),
  };
}

test(dbGated ? '#2427: o corpo vivo de admin_send_member_access decide antes de agir' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    const { data, error } = await sb().rpc('_audit_function_source', { p_proname: 'admin_send_member_access' });
    assert.equal(error, null, `_audit_function_source falhou: ${error?.message ?? ''}`);
    assert.ok(Array.isArray(data) && data.length === 1, `esperava 1 sobrecarga, veio ${data?.length}`);
    const r = regrasDaRpc(data[0].prosrc);
    assert.deepEqual(r, { portao: true, jaTemLogin: true, inativo: true, teto: true, payloadSoId: true },
      'uma regra da RPC de convite sumiu ou passou para depois do efeito (#2427)');
  });

test(dbGated ? '#2427: sem sessao a RPC recusa, e o template existe nas 3 linguas' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    // service_role nao tem auth.uid(): o portao tem de recusar ANTES de gravar ou despachar.
    const { error } = await sb().rpc('admin_send_member_access', { p_member_id: '00000000-0000-0000-0000-000000000000' });
    assert.ok(error, 'a RPC aceitou uma chamada sem membro autenticado');
    assert.match(String(error.message), /Not authenticated/, `recusou pelo motivo errado: ${error.message}`);

    const { data: tpl, error: tErr } = await sb().from('campaign_templates')
      .select('subject, body_html, body_text').eq('slug', 'member_access_invite').maybeSingle();
    assert.equal(tErr, null);
    assert.ok(tpl, 'template member_access_invite ausente: a EF enviaria para um slug inexistente');
    for (const lang of ['pt', 'en', 'es']) {
      for (const campo of ['subject', 'body_html', 'body_text']) {
        assert.ok(tpl[campo]?.[lang], `template sem ${campo}.${lang}`);
      }
      for (const v of ['{{first_name}}', '{{access_url}}', '{{expires_in_minutes}}']) {
        assert.ok(tpl.body_html[lang].includes(v), `body_html.${lang} sem ${v}`);
      }
    }
  });

test(dbGated && ANON_KEY ? '#2427: exercida como anon, a RPC e barrada por permissao' : 'SKIP: anon key ausente',
  { skip: !(dbGated && ANON_KEY) }, async () => {
    const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
    const { data, error } = await anon.rpc('admin_send_member_access', { p_member_id: '00000000-0000-0000-0000-000000000000' });
    assert.ok(error, `anon executou admin_send_member_access (devolveu ${JSON.stringify(data)})`);
    assert.doesNotMatch(String(error.message), /does not exist|not find the function/i,
      `a funcao sumiu: verde pela ausencia, nao pelo portao (${error.message})`);
  });

test('#2427: a EF so envia convite de membro com pedido recente, e a tela oferece o convite', () => {
  assert.deepEqual(efExigePedido(EF), { despacha: true, pedidoAntesDoLink: true, template: true });
  assert.deepEqual(telaOferece(PAGE), { criaComId: true, ofereceAoCriar: true, chamaRpc: true, botao: true });
});

test('#2427 mutacao: cada detector reprova a forma do defeito, pela MESMA funcao', () => {
  const RPC_OK = `
  BEGIN
    IF NOT public.can_by_member(v_caller, 'manage_member') THEN
      RAISE EXCEPTION 'Access denied';
    END IF;
    IF v_member.is_active IS NOT TRUE OR v_member.member_status IS DISTINCT FROM 'active' THEN
      RETURN jsonb_build_object('success', false, 'state', 'inactive');
    END IF;
    IF v_member.auth_id IS NOT NULL THEN
      RETURN jsonb_build_object(
        'success', false, 'state', 'already_linked');
    END IF;
    SELECT count(*) INTO v_recent FROM public.admin_audit_log
     WHERE action = 'member.access_invite_requested'
       AND target_id = v_member.id
       AND created_at > now() - interval '1 hour';
    IF v_recent >= 3 THEN
      RETURN jsonb_build_object('success', false, 'state', 'rate_limited');
    END IF;
    INSERT INTO public.admin_audit_log (actor_id) VALUES (v_caller);
    PERFORM net.http_post(
      url := 'x',
      body := jsonb_build_object('member_id', v_member.id)
    );
  END;`;
  const TUDO = { portao: true, jaTemLogin: true, inativo: true, teto: true, payloadSoId: true };
  const mut = (a, b) => { const m = RPC_OK.replace(a, b); assert.notEqual(m, RPC_OK, `mutacao nao aplicou: ${a}`); return regrasDaRpc(m); };
  // controle positivo
  assert.deepEqual(regrasDaRpc(RPC_OK), TUDO);
  // 1: portao removido
  assert.equal(mut("IF NOT public.can_by_member(v_caller, 'manage_member') THEN", "IF false THEN").portao, false);
  // 2: portao so em comentario
  assert.equal(mut("    IF NOT public.can_by_member", "    -- IF NOT public.can_by_member").portao, false);
  // 3: recusa de quem ja tem login removida (o convite criaria uma segunda identidade)
  assert.equal(mut("IF v_member.auth_id IS NOT NULL THEN", "IF false THEN").jaTemLogin, false);
  // 4: recusa de inativo removida
  assert.equal(mut("v_member.is_active IS NOT TRUE OR ", "").inativo, false);
  // 5: teto afrouxado
  assert.equal(mut('v_recent >= 3', 'v_recent >= 30').teto, false);
  // 6: teto contando a acao errada (nunca acumula)
  assert.equal(mut("action = 'member.access_invite_requested'", "action = 'member.access_invite_sent'").teto, false);
  // 7: payload carregando o e-mail (destinatario escolhido fora do servidor)
  assert.equal(mut("jsonb_build_object('member_id', v_member.id)", "jsonb_build_object('member_id', v_member.id, 'email', p_email)").payloadSoId, false);
  // 8: recusa DEPOIS do efeito nao protege
  const tarde = RPC_OK.replace(/ {4}IF v_member\.auth_id IS NOT NULL THEN[\s\S]*?END IF;\n/, '')
    .replace('  END;', "    IF v_member.auth_id IS NOT NULL THEN RETURN jsonb_build_object('success', false, 'state', 'already_linked'); END IF;\n  END;");
  assert.notEqual(tarde, RPC_OK);
  assert.equal(regrasDaRpc(tarde).jaTemLogin, false);

  // EF
  assert.deepEqual(efExigePedido(EF), { despacha: true, pedidoAntesDoLink: true, template: true });
  const efMut = (a, b) => { const m = EF.replace(a, b); assert.notEqual(m, EF, `mutacao EF nao aplicou: ${a}`); return efExigePedido(m); };
  // 9: recusa sem pedido removida
  assert.equal(efMut('if (!reqRow) return json(', 'if (false) return json(').pedidoAntesDoLink, false);
  // 10: consulta do pedido so em comentario
  assert.equal(efMut(".eq('action', 'member.access_invite_requested')", "// .eq('action', 'member.access_invite_requested')\n").pedidoAntesDoLink, false);
  // 11: template do portal no lugar do convite (texto diria "voce pediu pelo portal")
  assert.equal(efMut("p_template_slug: 'member_access_invite'", "p_template_slug: 'portal_account_setup'").template, false);
  // 12: ramo nao despachado
  assert.equal(efMut('return await handleMemberInvite(sb, memberIdParam)', "return json({ error: 'off' }, 400)").despacha, false);

  // Tela
  const telaMut = (a, b) => { const m = PAGE.replace(a, b); assert.notEqual(m, PAGE, `mutacao tela nao aplicou: ${a}`); return telaOferece(m); };
  // 13: criacao sem devolver o id
  assert.equal(telaMut(".select('id').single();", ';').criaComId, false);
  // 14: convite nao oferecido ao criar
  assert.equal(telaMut('await sendAccessInvite(result.id)', 'void 0').ofereceAoCriar, false);
  // 15: botao sem a condicao de "sem login"
  assert.equal(telaMut('!isNew && m?.is_active && !m?.auth_id ?', '!isNew && m?.is_active ?').botao, false);
});
