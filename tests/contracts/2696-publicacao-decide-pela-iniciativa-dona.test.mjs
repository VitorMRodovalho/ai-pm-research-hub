// tests/contracts/2696-publicacao-decide-pela-iniciativa-dona.test.mjs
/**
 * #2696 — admin_manage_publication decide pela iniciativa DONA da publicação, e a escrita direta na
 * tabela fica com quem administra a plataforma.
 *
 * ANTES (medido em 15/10/2026): o portão era `can_by_member(member, 'write_board')` sem recurso, que
 * passa para quem tem write_board em QUALQUER tribo (76 de 101 membros ativos com login). A policy
 * `pub_admin_manage_v4` (FOR ALL) deixava a mesma população escrever direto na tabela pelo
 * PostgREST, sem a RPC. O delete era físico e nada deixava rastro.
 *
 * O que este arquivo prova:
 *   (A) a autoridade se decide sobre a iniciativa da LINHA (ou a informada no create), ANTES de
 *       qualquer escrita, e nunca pelo write_board sem recurso;
 *   (B) apagar exige manage_platform;
 *   (C) cada ação grava admin_audit_log dentro do próprio ramo;
 *   (D) a coleção tem de ser da mesma iniciativa, e create/update gravam as colunas da #2613;
 *   (E) a policy de escrita direta exige superadmin ou manage_platform; a leitura de rascunho segue;
 *   (F) as asserções mordem (reinjeção de cada defeito);
 *   (G) camada VIVA: corpo vivo == captura, e o exercício como membro nos dois sentidos.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

const MIG_DIR = join(ROOT, 'supabase/migrations');
const MIG = (() => {
  const f = readdirSync(MIG_DIR).filter((x) => /_2696_/.test(x));
  return f.length === 1 ? maskLineComments(readFileSync(join(MIG_DIR, f[0]), 'utf8')) : '';
})();

/** A última migration que (re)cria a policy de escrita: é ela que vale, não a de 15/04. */
function ultimaPolicyDeEscrita() {
  const files = readdirSync(MIG_DIR).filter((f) => f.endsWith('.sql')).sort();
  let hit = '';
  for (const f of files) {
    const sql = maskLineComments(readFileSync(join(MIG_DIR, f), 'utf8'));
    const m = sql.match(/CREATE POLICY "?pub_admin_manage_v4"? ON (?:public\.)?public_publications[^;]*;/);
    if (m) hit = m[0];
  }
  return hit;
}

const ACOES = [
  ['create', 'publication.created'],
  ['update', 'publication.updated'],
  ['publish', 'publication.published'],
  ['unpublish', 'publication.unpublished'],
];

/** Recorta o ramo de escrita de uma ação: de `IF|ELSIF p_action = 'x' THEN` até o próximo ELSIF/ELSE. */
function ramo(sql, acao) {
  const re = new RegExp(`(?:IF|ELSIF) p_action = '${acao}' THEN\\s+(?:INSERT INTO public\\.public_publications|UPDATE public\\.public_publications)`);
  const i = sql.search(re);
  if (i < 0) return '';
  const resto = sql.slice(i + 10);
  const fim = resto.search(/\n\s{2}(?:ELSIF|ELSE)\b/);
  return sql.slice(i, i + 10 + (fim < 0 ? resto.length : fim));
}

function ramoDelete(sql) {
  const i = sql.search(/\n\s{2}ELSE\s+DELETE FROM public\.public_publications WHERE id = v_id;/);
  if (i < 0) return '';
  return sql.slice(i, sql.indexOf('END IF;', i));
}

function violacoes(corpo) {
  const v = [];
  const sql = maskLineComments(corpo);

  // (A) a iniciativa que decide vem da LINHA nas ações sobre publicação existente.
  if (!/SELECT \* INTO v_row FROM public\.public_publications WHERE id = v_id FOR UPDATE;\s+IF NOT FOUND THEN RAISE EXCEPTION 'publication_not_found'; END IF;\s+v_initiative_id := v_row\.initiative_id;/.test(sql)) {
    v.push('a iniciativa das ações sobre publicação existente não vem da linha');
  }
  // (A) o ramo escopado: write_board NA iniciativa dona, recusando com Unauthorized.
  const iEscopo = sql.search(/ELSIF NOT public\.can_by_member\(v_member_id, 'write_board', 'initiative', v_initiative_id\) THEN\s+RAISE EXCEPTION 'Unauthorized/);
  if (iEscopo < 0) v.push('o portão não exige write_board na iniciativa dona');
  // (A) publicação sem iniciativa: só escopo organization.
  if (!/IF v_initiative_id IS NULL THEN\s+IF NOT public\.can_org_by_member\(v_member_id, 'write_board'\) THEN\s+RAISE EXCEPTION 'Unauthorized/.test(sql)) {
    v.push('publicação sem iniciativa não exige write_board de escopo organization');
  }
  // (A) o portão antigo, sem recurso, não pode voltar.
  if (/can_by_member\(v_member_id, 'write_board'\)/.test(sql)) v.push('voltou o write_board SEM recurso');
  // (A) o portão vem antes de qualquer escrita.
  const iEscrita = sql.search(/INSERT INTO public\.public_publications|UPDATE public\.public_publications|DELETE FROM public\.public_publications/);
  if (iEscopo > 0 && iEscrita > 0 && iEscopo > iEscrita) v.push('o portão vem DEPOIS de uma escrita');

  // (B) apagar exige manage_platform.
  if (!/IF p_action = 'delete' THEN\s+IF NOT v_platform THEN\s+RAISE EXCEPTION 'Unauthorized: delete requires manage_platform'/.test(sql)) {
    v.push('apagar não exige manage_platform');
  }
  if (!/v_platform := public\.can_by_member\(v_member_id, 'manage_platform'\);/.test(sql)) {
    v.push('v_platform não vem de manage_platform');
  }

  // (C) cada ramo grava a própria auditoria, com o autor.
  for (const [acao, evento] of ACOES) {
    const r = ramo(sql, acao);
    if (!r) { v.push(`não achei o ramo ${acao}`); continue; }
    if (!new RegExp(`INSERT INTO public\\.admin_audit_log \\(actor_id, action, target_type, target_id, changes, metadata\\)\\s+VALUES \\(v_member_id, '${evento.replace('.', '\\.')}', 'publication', v_id,`).test(r)) {
      v.push(`o ramo ${acao} não grava ${evento} com o autor`);
    }
  }
  const rd = ramoDelete(sql);
  if (!rd) v.push('não achei o ramo delete');
  else if (!/VALUES \(v_member_id, 'publication\.deleted', 'publication', v_id, to_jsonb\(v_row\),/.test(rd)) {
    v.push('o delete não grava a linha inteira na auditoria');
  }

  // (D) a coleção tem de ser da mesma iniciativa.
  if (!/IF v_collection_initiative IS DISTINCT FROM v_initiative_id THEN\s+RAISE EXCEPTION 'collection_initiative_mismatch/.test(sql)) {
    v.push('a coleção não é validada contra a iniciativa da publicação');
  }
  const rc = ramo(sql, 'create');
  if (!/collection_id, collection_position, slug, license\s+\) VALUES/.test(rc)) v.push('o create não grava as colunas da #2613');
  const ru = ramo(sql, 'update');
  for (const col of ['collection_id', 'collection_position', 'slug', 'license']) {
    if (!new RegExp(`\\b${col} = COALESCE\\(`).test(ru)) v.push(`o update não grava ${col}`);
  }
  return v;
}

function violacoesPolicy(policy) {
  const v = [];
  if (!policy) return ['não achei a policy pub_admin_manage_v4'];
  if (!/FOR ALL TO authenticated\s+USING \(public\.rls_is_superadmin\(\) OR public\.rls_can\('manage_platform'\)\)\s+WITH CHECK \(public\.rls_is_superadmin\(\) OR public\.rls_can\('manage_platform'\)\)/.test(policy)) {
    v.push('a escrita direta não exige superadmin ou manage_platform nas duas bordas');
  }
  if (/write_board|rls_can\('write'\)/.test(policy)) v.push('a policy de escrita voltou a aceitar write/write_board');
  return v;
}

// ── A–D — o corpo capturado ───────────────────────────────────────────────────────────
test('#2696 static: a RPC decide pela iniciativa dona, audita e valida a coleção', () => {
  const { body } = latestFunctionCapture(ROOT, 'admin_manage_publication');
  assert.deepEqual(violacoes(body), []);
});

// ── E — policies ──────────────────────────────────────────────────────────────────────
test('#2696 static: a escrita direta na tabela fica com superadmin/manage_platform', () => {
  assert.deepEqual(violacoesPolicy(ultimaPolicyDeEscrita()), []);
});

test('#2696 static: a leitura de rascunho por write/write_board segue numa policy de SELECT', () => {
  assert.match(MIG, /CREATE POLICY pub_curator_read_v4 ON public\.public_publications FOR SELECT TO authenticated\s+USING \(public\.rls_can\('write'\) OR public\.rls_can\('write_board'\)\);/);
});

test('#2696 static: anon e PUBLIC perdem EXECUTE; o helper de exercício é só do service_role', () => {
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.admin_manage_publication\(text, jsonb\) FROM PUBLIC, anon;/);
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\._test_2696_publication_authority_roundtrip\(\) FROM PUBLIC, anon, authenticated;/);
  assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\._test_2696_publication_authority_roundtrip\(\) TO service_role;/);
  const { block } = latestFunctionCapture(ROOT, 'admin_manage_publication');
  assert.match(block, /SECURITY DEFINER\s+SET search_path TO 'public', 'pg_temp'/);
});

// ── F — as asserções mordem ───────────────────────────────────────────────────────────
const MUTACOES = [
  ['portão volta a ser sem recurso',
    (b) => b.replace("ELSIF NOT public.can_by_member(v_member_id, 'write_board', 'initiative', v_initiative_id) THEN",
      "ELSIF NOT public.can_by_member(v_member_id, 'write_board') THEN")],
  ['a iniciativa deixa de vir da linha',
    (b) => b.replace('v_initiative_id := v_row.initiative_id;', "v_initiative_id := NULLIF(p_data->>'initiative_id', '')::uuid;")],
  ['delete sem manage_platform',
    (b) => b.replace("IF NOT v_platform THEN\n      RAISE EXCEPTION 'Unauthorized: delete requires manage_platform';\n    END IF;", 'NULL;')],
  ['sem iniciativa aceita qualquer write_board',
    (b) => b.replace("IF NOT public.can_org_by_member(v_member_id, 'write_board') THEN", "IF NOT public.can_by_member(v_member_id, 'write_board') THEN")],
  ['unpublish sem auditoria',
    (b) => b.replace("VALUES (v_member_id, 'publication.unpublished', 'publication', v_id,", "VALUES (v_member_id, 'publication.other', 'publication', v_id,")],
  ['delete sem a linha na auditoria',
    (b) => b.replace("VALUES (v_member_id, 'publication.deleted', 'publication', v_id, to_jsonb(v_row),", "VALUES (v_member_id, 'publication.deleted', 'publication', v_id, '{}'::jsonb,")],
  ['coleção de outra iniciativa aceita',
    (b) => b.replace("IF v_collection_initiative IS DISTINCT FROM v_initiative_id THEN\n        RAISE EXCEPTION 'collection_initiative_mismatch: the collection belongs to another initiative';\n      END IF;", '')],
  ['update deixa de gravar license',
    (b) => b.replace("license = COALESCE(NULLIF(p_data->>'license', ''), license),", '')],
];

for (const [nome, mutar] of MUTACOES) {
  test(`#2696 static: reprova — ${nome}`, () => {
    const { body } = latestFunctionCapture(ROOT, 'admin_manage_publication');
    const adulterado = mutar(body);
    assert.notEqual(adulterado, body, `a mutação "${nome}" não mudou o corpo`);
    assert.ok(violacoes(adulterado).length > 0, `o guard não reprovou "${nome}"`);
  });
}

test('#2696 static: reprova a policy que volta a aceitar write_board na escrita', () => {
  const p = ultimaPolicyDeEscrita();
  const adulterada = p.replace("public.rls_is_superadmin() OR public.rls_can('manage_platform'))\n  WITH",
    "public.rls_is_superadmin() OR public.rls_can('manage_platform') OR public.rls_can('write_board'))\n  WITH");
  assert.notEqual(adulterada, p);
  assert.ok(violacoesPolicy(adulterada).length > 0);
});

// ── G — camada viva ───────────────────────────────────────────────────────────────────
test('#2696 db: corpos VIVOS batem com as capturas', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('_audit_list_public_function_bodies');
  assert.ifError(error);
  for (const name of ['admin_manage_publication', '_test_2696_publication_authority_roundtrip']) {
    const c = latestFunctionCapture(ROOT, name);
    const md5 = createHash('md5').update(c.body.replace(/\s+/g, ' ')).digest('hex');
    const vivas = (data ?? []).filter((f) => f.proname === name);
    assert.equal(vivas.length, 1, `${name}: esperava 1 viva, achei ${vivas.length}`);
    assert.equal(vivas[0].body_md5, md5, `${name}: corpo vivo divergiu de ${c.file}`);
  }
});

test('#2696 db: membro de OUTRA iniciativa é recusado; o dono passa e deixa rastro', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('_test_2696_publication_authority_roundtrip');
  assert.equal(error, null, `exercício falhou: ${error?.message}`);

  // CONTROLE POSITIVO primeiro: se o dono não passar, o instrumento está quebrado e a recusa do
  // membro de fora não prova nada.
  assert.equal(data.owner_update.allowed, true, `controle positivo: o dono tem de editar (${data.owner_update.error ?? ''})`);
  assert.equal(data.owner_update.title_has_canary, true, 'controle positivo: a edição do dono tem de chegar na linha');
  assert.equal(data.owner_update.audit_rows, 1, 'a edição do dono tem de gravar exatamente 1 linha de auditoria');

  assert.equal(data.outsider_update.allowed, false, 'membro de outra iniciativa não pode editar');
  assert.match(data.outsider_update.error, /^Unauthorized/);
  assert.equal(data.outsider_unpublish.allowed, false, 'membro de outra iniciativa não pode despublicar');
  assert.match(data.outsider_unpublish.error, /^Unauthorized/);

  assert.equal(data.owner_delete.allowed, false, 'apagar exige manage_platform, nem o dono apaga');
  assert.match(data.owner_delete.error, /^Unauthorized: delete requires manage_platform/);
  assert.equal(data.owner_delete.row_still_there, true);
});

test('#2696 db: o exercício não deixa rastro em produção', { skip: dbGated ? false : skipMsg }, async () => {
  const c = sb();
  // Consultas NOVAS (o helper já retornou): a sub-transação tem de ter voltado atrás.
  const pubs = await c.from('public_publications').select('id', { count: 'exact', head: true }).like('title', '%__test_2696_%');
  assert.equal(pubs.error, null, pubs.error?.message);
  assert.equal(pubs.count, 0, 'o canário ficou no título de uma publicação');
  const audit = await c.from('admin_audit_log').select('id', { count: 'exact', head: true })
    .like('action', 'publication.%').filter('changes->input->>title', 'like', '%__test_2696_%');
  assert.equal(audit.error, null, audit.error?.message);
  assert.equal(audit.count, 0, 'o canário ficou na auditoria');
});
