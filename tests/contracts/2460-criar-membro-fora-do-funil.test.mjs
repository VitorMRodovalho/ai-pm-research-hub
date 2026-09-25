// tests/contracts/2460-criar-membro-fora-do-funil.test.mjs
// Registrar em "test:behavioural" + "test:contracts" (#1109). NAO em test:structural: le o banco,
// e o guard #1908 exige DB-gated na faixa SERIALIZADA (#1509).
/**
 * Criar membro fora do funil passa por UMA porta, e ela grava a identidade inteira.
 *
 * O CASO (#2460): nao havia caminho oficial para o GP criar alguem que nao passou pela selecao.
 *  - A tela /admin/member/new fazia INSERT direto em members: sem persons, sem filiacao de
 *    capitulo. Medido em 25/09/2026: 2 membros de 27/08 sem person_id (sem person, ninguem pode
 *    ser vinculado a iniciativa).
 *  - Os convidados do Hackathon (24/09) entraram por DML manual; faltou a filiacao primaria e a
 *    invariante U (severidade high) derrubou o check-invariants da #2462.
 *
 * O guard afirma, sobre o corpo VIVO de admin_create_member, cada condicao junto com o que ela
 * produz: o portao manage_member levanta excecao; o e-mail e procurado nas cinco identidades; a
 * filiacao e gravada como primaria; um vinculo recusado DESFAZ tudo (RAISE, nao RETURN); a
 * auditoria e gravada. E que anon nao executa, que a tela chama a RPC em vez do INSERT, e que o
 * MCP trata a recusa por estado como erro.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const dbGated = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

const PAGE = readFileSync('src/pages/admin/member/[id].astro', 'utf8');
const MCP = readFileSync('supabase/functions/nucleo-mcp/index.ts', 'utf8');

function sql(body) {
  return body.split('\n').map((l) => { const i = l.indexOf('--'); return i >= 0 ? l.slice(0, i) : l; })
    .join('\n').replace(/\s+/g, ' ');
}

/** Cada condicao amarrada ao resultado que ela produz, no corpo da RPC. */
export function rpc(body) {
  const c = sql(body);
  return {
    portaoLevanta: /IF NOT public\.can_by_member\(v_caller, 'manage_member'\) THEN RAISE EXCEPTION/.test(c),
    dupMembro: /lower\(m\.email\) = v_email OR v_email = ANY \(SELECT lower\(x\) FROM unnest\(m\.secondary_emails\) x\)/.test(c),
    dupMemberEmails: /FROM public\.member_emails me WHERE lower\(me\.email\) = v_email/.test(c),
    dupPessoa: /lower\(p\.email\) = v_email OR v_email = ANY \(SELECT lower\(x\) FROM unnest\(p\.secondary_emails\) x\)\) THEN RETURN jsonb_build_object\('success', false, 'state', 'email_exists'\)/.test(c),
    pessoaNoMembro: /INSERT INTO public\.members \([^)]*person_id[^)]*\) VALUES \([^)]*v_person_id/.test(c),
    filiacaoPrimaria: /PERFORM public\.upsert_chapter_affiliation\(v_person_id, v_code, 'admin_import', true\)/.test(c),
    vinculoRecusadoDesfaz: /IF \(v_eng ->> 'ok'\) IS DISTINCT FROM 'true' THEN RAISE EXCEPTION/.test(c),
    auditoria: /INSERT INTO public\.admin_audit_log \([^)]*\) VALUES \( v_caller, 'member\.created_by_admin', 'member', v_member_id/.test(c),
  };
}

/** A tela cria pela RPC, e nao por INSERT direto em members. */
export function tela(src) {
  const c = maskJsComments(src);
  return {
    chamaRpc: /sb\.rpc\('admin_create_member', \{/.test(c),
    semInsertDireto: !/from\('members'\)\.insert\(/.test(c),
    recusaVira: /!created\?\.success\) \{\s*result = \{ error: T\.createError\[created\?\.state\]/.test(c),
  };
}

/** O MCP mapeia create para a RPC e trata success!==true como recusa. */
export function mcp(src) {
  const c = maskJsComments(src);
  return {
    mapeia: /case "create":\s*rpc = "admin_create_member";/.test(c),
    recusa: /params\.action === "create" && \(data as any\)\?\.success !== true\) \{[^}]*return invalid\(/.test(c),
    admin: /const ADMIN = new Set\(\[[^\]]*"create"\]\)/.test(c),
  };
}

const allTrue = (o) => Object.fromEntries(Object.keys(o).map((k) => [k, true]));

async function corpo(proname) {
  const { data, error } = await sb().rpc('_audit_function_source', { p_proname: proname });
  assert.equal(error, null, `_audit_function_source(${proname}) falhou: ${error?.message ?? ''}`);
  assert.ok(Array.isArray(data) && data.length === 1, `${proname}: esperava 1 sobrecarga, veio ${data?.length}`);
  return data[0].prosrc;
}

test(dbGated ? '#2460: a RPC grava a identidade inteira e desfaz tudo se o vinculo for recusado' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    const r = rpc(await corpo('admin_create_member'));
    assert.deepEqual(r, allTrue(r));
  });

test(dbGated && ANON_KEY ? '#2460: anon nao executa admin_create_member' : `SKIP: ${skipMsg} + anon key`,
  { skip: !(dbGated && ANON_KEY) }, async () => {
    const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
    const { data, error } = await anon.rpc('admin_create_member', { p_name: 'x', p_email: 'x@example.invalid' });
    assert.equal(data, null, 'anon recebeu dado de admin_create_member');
    // 42501 = permission denied (EXECUTE revogado). "Not authenticated" tambem seria recusa, mas
    // provaria que o EXECUTE continua aberto a anon, que e o que este teste existe para impedir.
    assert.equal(error?.code, '42501', `anon deveria ser barrado no EXECUTE, veio: ${error?.code} ${error?.message}`);
  });

test('#2460: a tela cria pela RPC e o MCP trata a recusa', () => {
  const t = tela(PAGE);
  assert.deepEqual(t, allTrue(t));
  const m = mcp(MCP);
  assert.deepEqual(m, allTrue(m));
});

test('#2460 mutacao: cada detector reprova a forma do defeito, pela MESMA funcao', () => {
  const mu = (src, a, b) => { const out = src.replace(a, b); assert.notEqual(out, src, `mutacao nao aplicou: ${a}`); return out; };
  const B = readFileSync('supabase/migrations/' + readdirMig(), 'utf8');
  const body = B.slice(B.indexOf('AS $function$'), B.indexOf('$function$;'));
  assert.deepEqual(rpc(body), allTrue(rpc(body)), 'controle: o corpo da migration passa inteiro');
  assert.equal(rpc(mu(body, "IF NOT public.can_by_member(v_caller, 'manage_member') THEN\n    RAISE EXCEPTION", "IF NOT public.can_by_member(v_caller, 'manage_member') THEN\n    RETURN NULL; RAISE EXCEPTION")).portaoLevanta, false);
  assert.equal(rpc(mu(body, "SELECT me.member_id INTO v_existing FROM public.member_emails me WHERE lower(me.email) = v_email LIMIT 1;", '')).dupMemberEmails, false);
  assert.equal(rpc(mu(body, "'admin_import', true)", "'admin_import', false)")).filiacaoPrimaria, false);
  assert.equal(rpc(mu(body, "IF (v_eng ->> 'ok') IS DISTINCT FROM 'true' THEN\n      -- Desfaz", "IF (v_eng ->> 'ok') IS DISTINCT FROM 'true' THEN RETURN v_eng;\n      -- Desfaz")).vinculoRecusadoDesfaz, false);
  assert.equal(rpc(mu(body, "'member.created_by_admin'", "'member.created'")).auditoria, false);
  assert.equal(tela(mu(PAGE, "sb.rpc('admin_create_member', {", "sb.from('members').insert({")).semInsertDireto, false);
  assert.equal(mcp(mu(MCP, 'params.action === "create" && (data as any)?.success !== true', 'false && (data as any)?.success !== true')).recusa, false);
});

function readdirMig() {
  const files = readdirSync('supabase/migrations').filter((f) => /_2460_criar_membro_fora_do_funil\.sql$/.test(f));
  assert.equal(files.length, 1, `esperava 1 migration da #2460, achou ${files.length}`);
  return files[0];
}
