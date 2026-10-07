/**
 * #740: os convites dos grupos de WhatsApp do Núcleo (onboarding e geral) vêm do banco, por uma RPC
 * com portão, e nunca do código. Quem entra num grupo vê o telefone dos participantes, e este
 * repositório e o bundle do front são públicos. Mesmo padrão do get_tribe_group_link (WS-A1).
 *
 * O QUE ESTE GUARD AFIRMA:
 *   A. a migration cria get_community_group_link(p_group text) como SECURITY DEFINER com search_path
 *      fixo, tira o EXECUTE de PUBLIC e anon, dá a authenticated e service_role, e não carrega convite;
 *   B. cada portão da função devolve a recusa certa: sem login, grupo fora da lista, membro inativo,
 *      grupo geral antes do termo (exceto admin da plataforma) e convite ausente ou fora do formato;
 *   C. o convite sai de site_config pela chave 'whatsapp_group_' || p_group, e só um convite de grupo
 *      do WhatsApp é devolvido;
 *   D. nenhum convite de grupo do WhatsApp mora em src/ (o bundle);
 *   E. o pré-onboarding pede o grupo de onboarding à RPC e só mostra o bloco quando ela devolve o link;
 *   F. a tela de sucesso do termo e o card do workspace pedem o grupo geral à RPC;
 *   G. ao vivo: anon não recebe link, e sem membro autenticado a função falha fechada.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIG_DIR = resolve(ROOT, 'supabase/migrations');
const migFiles = readdirSync(MIG_DIR).filter((f) => f.endsWith('_740_convites_whatsapp_pelo_banco.sql'));
const RAW_SQL = migFiles.length === 1 ? readFileSync(join(MIG_DIR, migFiles[0]), 'utf8') : '';
const SQL = maskLineComments(RAW_SQL);
// O bloco que decide: o corpo da função, entre os dois $function$.
const BODY = (SQL.match(/AS \$function\$([\s\S]*?)\$function\$/) || ['', ''])[1];
const HEADER = (SQL.match(/CREATE FUNCTION public\.get_community_group_link\(p_group text\)[\s\S]*?AS \$function\$/) || [''])[0];

const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const maskHtmlComments = (s) => s.replace(/<!--[\s\S]*?-->/g, (m) => m.replace(/[^\n]/g, ' '));
const INVITE_RE = /chat\.whatsapp\.com\/[A-Za-z0-9]{10,}/;

const PRE = maskJsComments(read('src/components/onboarding/PreOnboardingChecklist.tsx'));
const TERM = maskHtmlComments(maskJsComments(read('src/pages/volunteer-agreement.astro')));
const CARD = maskJsComments(read('src/components/onboarding/GeneralGroupCard.tsx'));
const WORKSPACE = maskHtmlComments(read('src/pages/workspace.astro'));

const RECUSA = (reason) => `RETURN jsonb_build_object\\('success', false, 'reason', '${reason}'\\);`;

test('A: migration única, SECDEF com search_path, EXECUTE só para authenticated e service_role, sem convite', () => {
  assert.equal(migFiles.length, 1, `uma migration *_740_convites_whatsapp_pelo_banco.sql (achadas: ${migFiles.length})`);
  assert.ok(HEADER, 'CREATE FUNCTION public.get_community_group_link(p_group text)');
  assert.match(HEADER, /RETURNS jsonb\s+LANGUAGE plpgsql\s+SECURITY DEFINER\s+SET search_path TO 'public', 'pg_temp'\s+AS \$function\$/);
  assert.match(SQL, /REVOKE ALL ON FUNCTION public\.get_community_group_link\(text\) FROM PUBLIC, anon;/);
  assert.match(SQL, /GRANT EXECUTE ON FUNCTION public\.get_community_group_link\(text\) TO authenticated, service_role;/);
  assert.doesNotMatch(RAW_SQL, INVITE_RE, 'o convite fica fora do repositório');
});

test('B: cada portão devolve a sua recusa', () => {
  assert.ok(BODY, 'corpo da função');
  assert.match(BODY, new RegExp(`IF v_uid IS NULL THEN\\s+${RECUSA('not_authenticated')}`));
  assert.match(BODY, new RegExp(`IF p_group IS NULL OR p_group NOT IN \\('onboarding', 'general'\\) THEN\\s+${RECUSA('invalid_group')}`));
  assert.match(BODY, new RegExp(`IF v_member_id IS NULL THEN\\s+${RECUSA('not_authenticated')}`));
  assert.match(BODY, new RegExp(`IF v_is_active IS DISTINCT FROM true THEN\\s+${RECUSA('inactive')}`));
  assert.match(
    BODY,
    new RegExp(
      "IF p_group = 'general' AND NOT public\\.can_by_member\\(v_member_id, 'manage_platform'\\) THEN\\s+" +
      'SELECT id INTO v_person_id FROM public\\.persons WHERE legacy_member_id = v_member_id;\\s+' +
      'IF v_person_id IS NULL OR public\\.member_is_pre_onboarding\\(v_person_id, v_member_status\\) THEN\\s+' +
      RECUSA('pre_onboarding'),
    ),
    'grupo geral só depois do termo, falhando fechado sem pessoa',
  );
});

test('C: o convite vem de site_config e só um convite de grupo do WhatsApp sai', () => {
  assert.match(BODY, /SELECT value #>> '\{\}' INTO v_link\s+FROM public\.site_config\s+WHERE key = 'whatsapp_group_' \|\| p_group;/);
  assert.match(
    BODY,
    new RegExp(`IF v_link IS NULL OR v_link !~ '\\^https://chat\\\\\\.whatsapp\\\\\\.com/[^']*' THEN\\s+${RECUSA('no_link')}`),
  );
  assert.match(BODY, /RETURN jsonb_build_object\('success', true, 'whatsapp_url', v_link\);/);
});

test('D: nenhum convite de grupo do WhatsApp em src/', () => {
  const achados = [];
  const walk = (dir) => {
    for (const nome of readdirSync(dir)) {
      const p = join(dir, nome);
      if (statSync(p).isDirectory()) walk(p);
      else if (/\.(ts|tsx|js|mjs|astro|json)$/.test(nome) && INVITE_RE.test(readFileSync(p, 'utf8'))) achados.push(p.slice(ROOT.length + 1));
    }
  };
  walk(resolve(ROOT, 'src'));
  assert.deepEqual(achados, [], 'convite de grupo no bundle');
});

test('E: o pré-onboarding pede o grupo de onboarding à RPC e só mostra o bloco com link', () => {
  assert.match(PRE, /sb\.rpc\('get_community_group_link', \{ p_group: 'onboarding' \}\)/);
  assert.match(PRE, /if \(groupRes\.data\?\.success && groupRes\.data\.whatsapp_url\) \{\s+setGroupUrl\(groupRes\.data\.whatsapp_url\);/);
  assert.match(PRE, /\{groupUrl && \(\s+<div[^>]*>[\s\S]*?href=\{groupUrl\}/, 'o bloco e o link dependem do retorno da RPC');
});

test('F: a tela do termo e o card do workspace pedem o grupo geral à RPC', () => {
  assert.match(TERM, /sb\.rpc\('get_community_group_link', \{ p_group: 'general' \}\);\s+if \(gRes\?\.success && gRes\.whatsapp_url\) generalLink = gRes\.whatsapp_url;/);
  assert.match(TERM, /renderSuccess\(data, lang, \{ tribeLink, generalLink \}\)/);
  assert.match(TERM, /\$\{generalLink \? `\s+<a href="\$\{encodeURI\(generalLink\)\}"/);
  assert.match(CARD, /sb\.rpc\('get_community_group_link', \{ p_group: 'general' \}\);\s+if \(data\?\.success && data\.whatsapp_url\) setUrl\(data\.whatsapp_url\);/);
  assert.match(CARD, /if \(hidden \|\| !url\) return null;/);
  assert.match(WORKSPACE, /<GeneralGroupCard client:load lang=\{lang\} \/>/);
});

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;
const svc = SUPABASE_URL && SERVICE_KEY ? createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } }) : null;
const anon = SUPABASE_URL && ANON_KEY ? createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } }) : null;

test('G1 ao vivo: anon não recebe link de nenhum dos dois grupos', { skip: anon ? false : 'anon env required' }, async () => {
  for (const p_group of ['onboarding', 'general']) {
    const { data, error } = await anon.rpc('get_community_group_link', { p_group });
    if (error) {
      assert.match(error.message, /permission|denied/i, `anon barrado em ${p_group}: ${error.message}`);
    } else {
      assert.equal(data?.success, false, `anon sem sucesso em ${p_group}`);
      assert.ok(!data?.whatsapp_url, `anon sem link em ${p_group}`);
    }
  }
});

test('G2 ao vivo: sem membro autenticado a função falha fechada', { skip: svc ? false : 'Supabase env required' }, async () => {
  // service_role não tem auth.uid(): prova que a função existe, executa e falha fechada. Os ramos por
  // motivo (pre_onboarding, inactive, sucesso) são exercidos com impersonação no execute_sql da PR.
  const { data, error } = await svc.rpc('get_community_group_link', { p_group: 'general' });
  assert.ok(!error, `service_role executa: ${error?.message}`);
  assert.equal(data?.success, false);
  assert.equal(data?.reason, 'not_authenticated');
  assert.ok(!data?.whatsapp_url, 'nunca devolve link sem membro autenticado');
});
