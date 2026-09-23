// tests/contracts/2437-rpcs-de-versao-de-governanca-tem-portao-de-leitura.test.mjs
// Registrar em "test:behavioural" + "test:contracts" (#1109). NAO em test:structural: le o banco,
// e o guard #1908 exige DB-gated na faixa SERIALIZADA (#1509).
/**
 * As RPCs que devolvem conteudo de versao de documento de governanca passam pelo portao de leitura.
 *
 * O CASO (#2437): `get_chain_workflow_detail`, `get_next_draft_version` e
 * `get_previous_locked_version` sao SECURITY DEFINER e nao conferiam quem chama. Quem tinha um id
 * lia o texto; a do rascunho, inclusive sem login. A correcao poe as tres atras de um helper unico,
 * `_can_read_governance_version`, com a mesma regra dos leitores que ja tinham portao.
 *
 * O que este guard afirma, e por que assim:
 *  - no CORPO VIVO de cada uma, a chamada ao helper existe FORA de comentario e vem ANTES do
 *    retorno que carrega content_html. Presenca solta de string nao prova nada: a string sobrevive
 *    em comentario (regra do CLAUDE.md, tres incidentes em 17/09);
 *  - o helper nega conta sem membro e trata audit_restricted antes do bypass de manage_member;
 *  - EXERCIDO como consumidor: com a chave anon, get_next_draft_version tem de ser recusada.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY;
const dbGated = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

const GUARDADAS = ['get_chain_workflow_detail', 'get_next_draft_version', 'get_previous_locked_version'];

function semComentarioSql(body) {
  return body.split('\n').map((l) => { const i = l.indexOf('--'); return i >= 0 ? l.slice(0, i) : l; }).join('\n');
}

/**
 * O portao existe e vem antes do retorno com conteudo? Liga a CONDICAO (NOT helper) ao RESULTADO
 * (um RETURN) e exige que isso aconteca antes do RETURN que carrega content_html.
 */
export function portaoAntesDoConteudo(body) {
  const code = semComentarioSql(body);
  const portao = code.search(/IF\s+NOT\s+public\._can_read_governance_version\([^)]*\)\s+THEN\s+RETURN\b/);
  // A INSTRUCAO de retorno que carrega content_html (recortada por ';'), nao o primeiro RETURN da funcao:
  // os RETURN de erro vem antes do portao e nao devolvem conteudo.
  let conteudo = -1;
  let pos = 0;
  for (const stmt of code.split(';')) {
    if (/^\s*RETURN\s+jsonb_build_object\(/.test(stmt) && stmt.includes("'content_html'")) {
      conteudo = pos + stmt.search(/RETURN/);
      break;
    }
    pos += stmt.length + 1;
  }
  return portao >= 0 && conteudo >= 0 && portao < conteudo;
}

/** O helper nega sem membro ativo, e trata audit_restricted ANTES do bypass de manage_member. */
export function helperNegaCertoNaOrdemCerta(body) {
  const code = semComentarioSql(body);
  const semMembro = /IF\s+v_member\s+IS\s+NULL\s+THEN\s+RETURN\s+false/.test(code);
  const audit = code.search(/visibility_class\s*=\s*'audit_restricted'\s+THEN\s+RETURN\s+public\.can_by_member\(v_member,\s*'manage_platform'\)/);
  const admin = code.search(/IF\s+public\.can_by_member\(v_member,\s*'manage_member'\)\s+THEN\s+RETURN\s+true/);
  return semMembro && audit >= 0 && admin >= 0 && audit < admin;
}

async function corpo(proname) {
  const { data, error } = await sb().rpc('_audit_function_source', { p_proname: proname });
  assert.equal(error, null, `_audit_function_source(${proname}) falhou: ${error?.message ?? ''}`);
  assert.ok(Array.isArray(data) && data.length === 1, `${proname}: esperava 1 sobrecarga, veio ${data?.length}`);
  const body = data[0]?.prosrc;
  assert.ok(typeof body === 'string' && body.length > 0, `${proname}: introspeccao sem corpo`);
  return body;
}

test(dbGated ? '#2437: as tres RPCs checam o portao antes de devolver conteudo' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    const sem = [];
    for (const fn of GUARDADAS) if (!portaoAntesDoConteudo(await corpo(fn))) sem.push(fn);
    assert.deepEqual(sem, [], 'RPC de versao devolve conteudo sem passar pelo portao de leitura (#2437)');
  });

test(dbGated ? '#2437: o helper nega conta sem membro e respeita audit_restricted' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    assert.ok(helperNegaCertoNaOrdemCerta(await corpo('_can_read_governance_version')),
      '_can_read_governance_version perdeu a negacao de conta sem membro ou deixou manage_member passar audit_restricted (#2437)');
  });

test(dbGated && ANON_KEY ? '#2437: exercido como anon, o rascunho e recusado' : 'SKIP: anon key ausente',
  { skip: !(dbGated && ANON_KEY) }, async () => {
    // Controle: existe versao para pedir (senao a recusa poderia ser so "nada encontrado").
    const { data: ver, error: e1 } = await sb().from('document_versions').select('id').limit(1);
    assert.equal(e1, null, e1?.message);
    assert.ok(ver?.length === 1, 'sem versao nenhuma na base para exercer a chamada');
    const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
    const { data, error } = await anon.rpc('get_next_draft_version', { p_version_id: ver[0].id });
    assert.ok(error, `anon executou get_next_draft_version e recebeu ${JSON.stringify(data)?.slice(0, 80)} (#2437)`);
  });

test('#2437 mutacao: os detectores reprovam cada forma do defeito, pela MESMA funcao', () => {
  const OK = `
    IF v_draft.id IS NULL THEN RETURN jsonb_build_object('exists', false); END IF;
    IF NOT public._can_read_governance_version(v_draft.id) THEN
      RETURN jsonb_build_object('exists', false);
    END IF;
    RETURN jsonb_build_object('exists', true, 'content_html', v_draft.content_html);`;
  assert.equal(portaoAntesDoConteudo(OK), true);
  // mutacao 1: portao removido
  assert.equal(portaoAntesDoConteudo(OK.replace(/IF NOT public\._can_read_governance_version[\s\S]*?END IF;/, '')), false);
  // mutacao 2: portao so em comentario
  assert.equal(portaoAntesDoConteudo(OK.replace('IF NOT public._can_read', '-- IF NOT public._can_read')), false);
  // mutacao 3: portao DEPOIS do retorno com conteudo (inalcancavel)
  const depois = `RETURN jsonb_build_object('exists', true, 'content_html', v_draft.content_html);
    IF NOT public._can_read_governance_version(v_draft.id) THEN RETURN jsonb_build_object('exists', false); END IF;`;
  assert.equal(portaoAntesDoConteudo(depois), false);
  // mutacao 4: chamada ao helper sem consequencia (sem RETURN ligado a condicao)
  const semConsequencia = OK.replace(
    /(IF NOT public\._can_read_governance_version\(v_draft\.id\) THEN)\s+RETURN jsonb_build_object\('exists', false\);/,
    '$1 NULL;');
  assert.notEqual(semConsequencia, OK, 'a mutacao 4 nao alterou o texto: ela nao testaria nada');
  assert.equal(portaoAntesDoConteudo(semConsequencia), false);

  const H = `
    IF v_member IS NULL THEN RETURN false; END IF;
    IF v_doc.visibility_class = 'audit_restricted' THEN
      RETURN public.can_by_member(v_member, 'manage_platform');
    END IF;
    IF public.can_by_member(v_member, 'manage_member') THEN RETURN true; END IF;`;
  assert.equal(helperNegaCertoNaOrdemCerta(H), true);
  // mutacao 5: conta sem membro passa
  assert.equal(helperNegaCertoNaOrdemCerta(H.replace('THEN RETURN false', 'THEN NULL')), false);
  // mutacao 6: manage_member antes de audit_restricted (admin comum leria audit_restricted)
  const invertido = `
    IF v_member IS NULL THEN RETURN false; END IF;
    IF public.can_by_member(v_member, 'manage_member') THEN RETURN true; END IF;
    IF v_doc.visibility_class = 'audit_restricted' THEN
      RETURN public.can_by_member(v_member, 'manage_platform');
    END IF;`;
  assert.equal(helperNegaCertoNaOrdemCerta(invertido), false);
});
