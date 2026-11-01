// tests/contracts/preview-gate-eligibles-sem-anon.test.mjs
// DB-aware: as camadas C e D abrem conexão, então o arquivo cai no balde behavioural. A e B são estáticas.
/**
 * preview_gate_eligibles(text, uuid) não é executável por anon.
 *
 * A função é SECURITY DEFINER e não tem portão de sessão. Até a migration *_preview_gate_eligibles_sem_anon
 * nenhuma migration declarava o ACL dela, então valia o default do projeto: EXECUTE para PUBLIC, anon,
 * authenticated e service_role. O único consumidor, src/components/governance/DocumentVersionEditor.tsx,
 * chama com sessão.
 *
 * As camadas:
 *   A (estático) a migration revoga de PUBLIC e de anon e concede a authenticated e service_role, em
 *                comandos de topo (fora de comentário, string e corpo de função).
 *   B (estático) o ACL que sai de TODAS as migrations, na ordem, fecha anon e PUBLIC e mantém
 *                authenticated e service_role. A reconstituição conta o CREATE com a função ausente (ela
 *                nasce com o default do projeto), o DROP FUNCTION, o GRANT e o REVOKE que nomeiam a função
 *                e os que valem para ALL FUNCTIONS IN SCHEMA public. Assim pega um GRANT posterior a anon e
 *                também um DROP + CREATE, que reabriria o default sem nenhum GRANT escrito.
 *   C (vivo)     o privilégio EFETIVO, pelo _audit_function_execute_acl (#1551): anon_exec false e
 *                authenticated_exec true. É has_function_privilege, então conta o que vem por PUBLIC.
 *   D (vivo)     como o consumidor anon: a chamada é recusada com 42501, e não com PGRST202 (função
 *                ausente). Controle positivo: o mesmo cliente anon chama get_homepage_stats.
 *
 * Cross-ref: #1551 (o probe de ACL), #965 (o sweep de SECURITY DEFINER com escrita), #2749 (o mesmo
 * formato para get_public_trail_ranking).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { maskSqlNonCode, splitStatements } from '../helpers/new-relation-grants.mjs';

const MIGRATIONS = join(process.cwd(), 'supabase/migrations');
const FN = 'preview_gate_eligibles';
const SUFIXO = '_preview_gate_eligibles_sem_anon.sql';
// O default do projeto para função nova em public: PUBLIC pelo Postgres, e anon, authenticated e
// service_role pelo ALTER DEFAULT PRIVILEGES do Supabase.
const DEFAULT_DO_PROJETO = ['public', 'anon', 'authenticated', 'service_role'];
const ASSINATURAS = new Set(['text, uuid', 'p_doc_type text, p_submitter_id uuid']);

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const opts = { auth: { persistSession: false } };

const ws = (s) => s.replace(/\s+/g, ' ').trim();
const files = () => readdirSync(MIGRATIONS).filter((f) => f.endsWith('.sql')).sort();
/** Comandos de topo de uma migration, com comentário, string e corpo `$...$` mascarados. */
const comandos = (f) =>
  splitStatements(maskSqlNonCode(readFileSync(join(MIGRATIONS, f), 'utf8'))).map((s) => ws(s.text));

// A função, com ou sem `public.`, e nunca como prefixo de outro identificador (_cache, _for_member).
const NOME = String.raw`(?<![\w$.])(?:public\s*\.\s*)?${FN}(?![\w$])`;
const CREATE = new RegExp(String.raw`^CREATE (?:OR REPLACE )?FUNCTION ${NOME} ?\(([^)]*)\)`, 'i');
const DROP = new RegExp(String.raw`^DROP FUNCTION (?:IF EXISTS )?[^;]*${NOME}`, 'i');
const GRANT = /^GRANT ([\w ,]+?) ON (FUNCTION|ROUTINE|ALL FUNCTIONS IN SCHEMA|ALL ROUTINES IN SCHEMA) (.+) TO (.+)$/i;
const REVOKE = /^REVOKE (GRANT OPTION FOR )?([\w ,]+?) ON (FUNCTION|ROUTINE|ALL FUNCTIONS IN SCHEMA|ALL ROUTINES IN SCHEMA) (.+) FROM (.+)$/i;

const papeis = (s) =>
  s.replace(/ (?:WITH GRANT OPTION|GRANTED BY \S+|CASCADE|RESTRICT)\b.*$/i, '')
    .split(',').map((r) => r.trim().replace(/"/g, '').toLowerCase()).filter(Boolean);
const daExecute = (privs) => /\b(?:EXECUTE|ALL)\b/i.test(privs);
const alcanca = (alvo, alvoTxt) =>
  /^ALL /i.test(alvo)
    ? alvoTxt.split(',').some((s) => /^public$/i.test(s.trim().replace(/"/g, '')))
    : new RegExp(NOME, 'i').test(alvoTxt);

/** Reconstitui, migration a migration, quem tem EXECUTE na função. null = a função não existe. */
function aclReconstituido() {
  let acl = null;
  const eventos = [];
  for (const f of files()) {
    for (const c of comandos(f)) {
      let m;
      if ((m = CREATE.exec(c))) {
        const sig = ws(m[1]).toLowerCase();
        eventos.push(`${f}: CREATE (${sig})${acl ? '' : ', nasce com o default'}`);
        assert.ok(ASSINATURAS.has(sig),
          `${f}: CREATE de ${FN}(${sig}). É uma assinatura nova, que nasce com o default do projeto ` +
          '(EXECUTE para PUBLIC e anon). Declare o ACL dela e acrescente a assinatura a este guard.');
        if (!acl) acl = new Set(DEFAULT_DO_PROJETO);
      } else if (DROP.test(c)) {
        eventos.push(`${f}: DROP`);
        acl = null;
      } else if ((m = GRANT.exec(c))) {
        if (!acl || !daExecute(m[1]) || !alcanca(m[2], m[3])) continue;
        eventos.push(`${f}: GRANT a ${papeis(m[4]).join(', ')}`);
        for (const r of papeis(m[4])) acl.add(r);
      } else if ((m = REVOKE.exec(c))) {
        if (!acl || m[1] || !daExecute(m[2]) || !alcanca(m[3], m[4])) continue;
        eventos.push(`${f}: REVOKE de ${papeis(m[5]).join(', ')}`);
        for (const r of papeis(m[5])) acl.delete(r);
      }
    }
  }
  return { acl, eventos };
}

// ═══════════════════════════════════════════════════════════════════════════
test('A · a migration fecha EXECUTE de PUBLIC e anon e declara authenticated e service_role', () => {
  const achados = files().filter((f) => f.endsWith(SUFIXO));
  assert.equal(achados.length, 1, `esperada uma migration *${SUFIXO}, achei ${achados.length}`);
  const c = comandos(achados[0]);

  assert.ok(c.includes(`REVOKE ALL ON FUNCTION public.${FN}(text, uuid) FROM PUBLIC, anon`),
    `${achados[0]}: falta, como comando de topo, o REVOKE de PUBLIC e anon. Só PUBLIC não fecha: o ` +
    'default do projeto dá EXECUTE a anon explicitamente.');
  assert.ok(c.includes(`GRANT EXECUTE ON FUNCTION public.${FN}(text, uuid) TO authenticated, service_role`),
    `${achados[0]}: falta, como comando de topo, o GRANT a authenticated e service_role. O editor de ` +
    'governança chama com sessão.');
});

test('B · o ACL que sai de todas as migrations fecha anon e PUBLIC e mantém authenticated e service_role', () => {
  const { acl, eventos } = aclReconstituido();
  const historico = `\n  ${eventos.join('\n  ')}`;
  assert.ok(acl, `${FN} não existe ao fim das migrations.${historico}`);
  assert.ok(!acl.has('anon'), `anon tem EXECUTE em ${FN} ao fim das migrations.${historico}`);
  assert.ok(!acl.has('public'),
    `PUBLIC tem EXECUTE em ${FN} ao fim das migrations, e anon herda de PUBLIC.${historico}`);
  assert.ok(acl.has('authenticated'),
    `authenticated perdeu EXECUTE em ${FN}: o editor de governança deixa de mostrar os signatários.${historico}`);
  assert.ok(acl.has('service_role'), `service_role perdeu EXECUTE em ${FN}.${historico}`);
});

// ═══════════════════════════════════════════════════════════════════════════
test('C · o privilégio efetivo: anon não executa, authenticated executa',
  { skip: !dbGated && skipMsg }, async () => {
  const svc = createClient(SUPABASE_URL, SUPABASE_KEY, opts);
  const { data, error } = await svc.rpc('_audit_function_execute_acl', { p_names: [FN] });
  assert.ifError(error);
  assert.equal(data.length, 1, `esperada uma assinatura de ${FN}, achei ${data.length}`);
  assert.equal(data[0].identity_args, 'p_doc_type text, p_submitter_id uuid');
  assert.equal(data[0].anon_exec, false, `anon executa ${FN}(${data[0].identity_args})`);
  assert.equal(data[0].authenticated_exec, true,
    `authenticated não executa ${FN}: o editor de governança deixa de mostrar os signatários`);
});

test('D · como anon, a chamada é recusada por permissão; o controle anon passa',
  { skip: (!SUPABASE_URL || !ANON_KEY) && 'Skipped: SUPABASE_URL + anon key required' }, async () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY, opts);
  const ctrl = await anon.rpc('get_homepage_stats');
  assert.equal(ctrl.error, null,
    `controle positivo falhou: o cliente anon não chama nem uma RPC pública (${ctrl.error?.code})`);

  const { error } = await anon.rpc(FN, { p_doc_type: 'cooperation_agreement', p_submitter_id: null });
  assert.ok(error, `anon executa ${FN}`);
  assert.notEqual(error.code, 'PGRST202',
    `anon foi barrado porque ${FN} não existe no schema cache, não pelo ACL`);
  assert.equal(error.code, '42501', `anon recebeu ${error.code}, e o esperado é 42501 (permissão)`);
});
