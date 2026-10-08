/**
 * #2585: portao de filiacao antes do Termo de Voluntariado.
 *
 * Decisao do GP (06/10 e 08/10/2026): o Nucleo e beneficio de filiados a um capitulo participante (ativo em
 * chapter_registry). Caminho A: afiliacao verificada pela VEP; com mais de uma, o membro escolhe o capitulo de entrada.
 * Caminho B, o ultimo ELSE: verificacao manual vigente da Diretoria de Filiacao. 'legacy' sozinho nao abre. Vale para
 * todo primeiro termo (guest) desde 08/10/2026; renovacao nao passa pelo portao.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. caminho A le source = 'pmi_vep' em capitulo ativo do registro, e pede o capitulo de entrada quando ha mais de um;
 *   B. caminho B vem DEPOIS de A, le a verificacao ativa, nao vencida, metodo vep_sync ou sede_manual, em capitulo ativo;
 *   C. nenhuma outra origem de afiliacao (legacy, admin_import, self_declared) abre o portao;
 *   D. o termo (ultima captura) consulta o portao so para guest, ANTES do perfil, devolve affiliation_required, e grava a
 *      afiliacao primaria do portao (A: pmi_vep, B: admin_import) antes de montar o conteudo, relendo o capitulo;
 *   E. get_my_affiliation_gate deixa a renovacao passar; request_affiliation_recheck avisa gestao e Diretoria de
 *      Filiacao uma vez por dia por pessoa;
 *   F. affiliation_gate nao e executavel por anon nem authenticated; as outras duas nao por anon;
 *   G. a tela consulta o portao antes do perfil, trata affiliation_required e o botao chama request_affiliation_recheck;
 *   H. (banco) cada pessoa em pre-onboarding recebe do portao um caminho valido (vep, manual) ou um motivo valido, e
 *      anon nao executa as funcoes. A medicao de 08/10/2026 (5 abertos, 5 fechados) esta na PR, nao aqui: a populacao
 *      muda e o guard nao pode depender dela.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const DIR = resolve(ROOT, 'supabase/migrations');
const files = readdirSync(DIR).filter((f) => /^\d{14}_2585_portao_de_filiacao\.sql$/.test(f));
const SQL = files.length === 1 ? maskLineComments(readFileSync(join(DIR, files[0]), 'utf8')) : '';
const fn = (name) => (SQL.match(new RegExp(String.raw`CREATE OR REPLACE FUNCTION public\.${name}\([\s\S]*?\$function\$[\s\S]*?\$function\$`)) || [''])[0];
const GATE = fn('affiliation_gate');

test('a migration existe', () => {
  assert.equal(files.length, 1, `esperava 1 migration da #2585, achei ${files.length}`);
  assert.ok(GATE.length > 500, 'affiliation_gate nao encontrada');
});

test('A. caminho A: pmi_vep em capitulo ativo, escolha de entrada com mais de um', () => {
  assert.match(GATE, /FROM public\.member_chapter_affiliations a\s+JOIN public\.chapter_registry cr ON cr\.chapter_code = a\.chapter_code AND cr\.is_active\s+WHERE a\.person_id = v_person_id AND a\.source = 'pmi_vep';/);
  assert.match(GATE, /IF array_length\(v_vep, 1\) > 1 AND \(v_entry IS NULL OR NOT v_entry = ANY\(v_vep\)\) THEN\s+RETURN jsonb_build_object\('open', false, 'reason', 'entry_chapter_required'/);
  assert.match(GATE, /RETURN jsonb_build_object\('open', true, 'path', 'vep',/);
});

test('B. caminho B depois de A: verificacao ativa, vigente, metodo fechado, capitulo ativo', () => {
  const a = GATE.indexOf("'path', 'vep'");
  const b = GATE.indexOf("'path', 'manual'");
  assert.ok(a > 0 && b > a, 'o caminho B precisa vir depois do A');
  const bloco = GATE.slice(GATE.indexOf('FROM public.member_affiliation_verifications v'), b);
  assert.match(bloco, /JOIN public\.chapter_registry cr ON cr\.chapter_code = regexp_replace\(v\.chapter_verified, '\^PMI-', ''\) AND cr\.is_active/);
  assert.match(bloco, /AND v\.membership_active\s+AND \(v\.membership_expires_on IS NULL OR v\.membership_expires_on > CURRENT_DATE\)\s+AND v\.method IN \('vep_sync', 'sede_manual'\)/);
});

test('C. nenhuma outra origem de afiliacao abre o portao', () => {
  for (const src of ['legacy', 'admin_import', 'self_declared', 'self_attested']) {
    assert.doesNotMatch(GATE, new RegExp(`'${src}'`), `affiliation_gate menciona '${src}'`);
  }
  assert.equal((GATE.match(/'open', true/g) || []).length, 2, 'o portao so pode abrir pelos caminhos A e B');
});

test('D. o termo consulta o portao (guest, antes do perfil) e grava a afiliacao primaria', () => {
  const cap = latestFunctionCapture(ROOT, 'sign_volunteer_agreement');
  const corpo = maskLineComments(cap.body);
  const portao = corpo.indexOf("v_gate := public.affiliation_gate(v_member.id);");
  const perfil = corpo.indexOf("'error', 'profile_incomplete'");
  const conteudo = corpo.indexOf('v_content := jsonb_build_object(');
  assert.ok(portao > 0 && portao < perfil, `${cap.file}: o portao precisa vir antes do perfil`);
  assert.match(corpo, /IF v_member\.operational_role = 'guest' THEN\s+v_gate := public\.affiliation_gate\(v_member\.id\);\s+IF NOT COALESCE\(\(v_gate ->> 'open'\)::boolean, false\) THEN\s+RETURN jsonb_build_object\(\s+'error', 'affiliation_required',/);
  const grava = corpo.indexOf('PERFORM public.upsert_chapter_affiliation(');
  assert.ok(grava > 0 && grava < conteudo, `${cap.file}: a afiliacao precisa ser gravada antes de montar o termo`);
  assert.match(corpo, /IF v_gate IS NOT NULL THEN\s+PERFORM public\.upsert_chapter_affiliation\(\s+\(SELECT person_id FROM public\.members WHERE id = v_member\.id\),\s+v_gate ->> 'chapter',\s+CASE WHEN v_gate ->> 'path' = 'vep' THEN 'pmi_vep' ELSE 'admin_import' END,\s+true\);\s+SELECT chapter INTO v_member\.chapter FROM public\.members WHERE id = v_member\.id;/);
});

test('E. renovacao passa; o aviso vai a gestao e Diretoria de Filiacao, uma vez por dia', () => {
  const g = fn('get_my_affiliation_gate');
  assert.match(g, /WHEN EXISTS \(SELECT 1 FROM public\.members WHERE id = v_member_id AND operational_role IS DISTINCT FROM 'guest'\)\s+THEN jsonb_build_object\('open', true, 'path', 'renewal'\)\s+ELSE public\.affiliation_gate\(v_member_id\)/);
  // Ajuste de 08/10/2026: o aviso vai so para o administrador da plataforma; a captura vigente esta na migration
  // do ajuste, entao a asserção le a ultima captura.
  const r = maskLineComments(latestFunctionCapture(ROOT, 'request_affiliation_recheck').block);
  assert.match(r, /AND m\.id <> v_member_id\s+AND public\.can_by_member\(m\.id, 'manage_platform'\)\s+AND NOT EXISTS/);
  assert.doesNotMatch(r, /filiacao_director/, 'o aviso nao vai para a designacao de filiacao');
  assert.match(r, /n\.source_type = 'affiliation_recheck'\s+AND n\.source_id = v_member_id AND n\.created_at >= v_inicio/);
});

test('F. grants', () => {
  assert.match(SQL, /REVOKE ALL ON FUNCTION public\.affiliation_gate\(uuid\) FROM PUBLIC, anon, authenticated;/);
  assert.doesNotMatch(SQL, /GRANT[^;]*affiliation_gate\(uuid\)[^;]*\b(anon|authenticated)\b/);
  for (const sig of ['get_my_affiliation_gate\\(\\)', 'request_affiliation_recheck\\(\\)']) {
    assert.match(SQL, new RegExp(`REVOKE ALL ON FUNCTION public\\.${sig} FROM PUBLIC, anon;`));
    assert.match(SQL, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${sig} TO authenticated, service_role;`));
  }
});

test('G. a tela consulta o portao antes do perfil e oferece a saida', () => {
  const page = maskJsComments(readFileSync(resolve(ROOT, 'src/pages/volunteer-agreement.astro'), 'utf8'));
  const gate = page.indexOf("sb.rpc('get_my_affiliation_gate')");
  const perfil = page.indexOf('const requiredFields');
  assert.ok(gate > 0 && gate < perfil, 'o pre-flight do portao precisa vir antes do perfil');
  assert.match(page, /if \(gate && gate\.open === false\) \{ wireGate\(sb, app, gate, lang\); return; \}/);
  assert.match(page, /if \(data\?\.error === 'affiliation_required'\) \{ wireGate\(sb, app, data\.gate, lang\); return; \}/);
  assert.match(page, /sb\.rpc\('request_affiliation_recheck'\)/);
});

const URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const dbGated = !!(URL && SERVICE && ANON);

async function rpc(key, name, body = {}) {
  const r = await fetch(`${URL}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return { status: r.status, body: r.status === 200 ? await r.json() : null };
}

test('H. (banco) caminho ou motivo valido para cada pessoa em pre-onboarding; anon negado', { skip: dbGated ? false : 'SUPABASE_URL + service role + anon key required' }, async () => {
  const r = await fetch(`${URL}/rest/v1/members?select=id&operational_role=eq.guest&is_active=eq.true`, {
    headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}` },
  });
  assert.equal(r.status, 200);
  const guests = await r.json();
  let abertos = 0;
  let fechados = 0;
  for (const g of guests) {
    const res = await rpc(SERVICE, 'affiliation_gate', { p_member_id: g.id });
    assert.equal(res.status, 200, `affiliation_gate voltou ${res.status}`);
    if (res.body.open === true) {
      abertos += 1;
      assert.ok(['vep', 'manual'].includes(res.body.path), `caminho inesperado: ${res.body.path}`);
    } else {
      fechados += 1;
      assert.ok(['entry_chapter_required', 'not_affiliated', 'unknown'].includes(res.body.reason), `motivo inesperado: ${res.body.reason}`);
    }
  }
  if (guests.length > 0) assert.ok(abertos + fechados === guests.length);
  for (const name of ['affiliation_gate', 'get_my_affiliation_gate', 'request_affiliation_recheck']) {
    const res = await rpc(ANON, name, name === 'affiliation_gate' ? { p_member_id: '00000000-0000-0000-0000-000000000000' } : {});
    assert.ok([401, 403, 404].includes(res.status), `${name} como anon voltou ${res.status}`);
  }
});
