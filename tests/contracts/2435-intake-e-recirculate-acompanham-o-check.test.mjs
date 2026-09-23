// tests/contracts/2435-intake-e-recirculate-acompanham-o-check.test.mjs
// Registrar em "test:behavioural" + "test:contracts" (#1109). NAO em test:structural: le o banco,
// e o guard #1908 exige DB-gated na faixa SERIALIZADA (#1509).
/**
 * Todo tipo do CHECK de governance_documents tem braco no intake e opcao na tela; e a
 * recirculacao passa a classe adiante.
 *
 * O CASO (#2435): tres pontos nao cresceram junto com `governance_documents_doc_type_check`.
 *  1. o CASE de `acknowledgement_mode` do `create_governance_document_intake` conhecia 11 tipos;
 *     os outros caiam no ELSE 'informational' (os irmaos de 11/06 sao 'legal_signature');
 *  2. `DOC_TYPES` do wizard listava 11: nao havia como criar pela tela um termo de cessao;
 *  3. `recirculate_governance_doc` chamava o lock com 2 argumentos, e a versao recirculada
 *     nascia com change_class NULL, congelada pelo trg_document_version_immutable.
 *
 * ⚠️ POR QUE DERIVAR DO CHECK, E NAO DE UMA LISTA: o p258 mantinha a lista de tipos escrita a
 * mao, e foi ela que ficou para tras. Mesma classe da #2119. Aqui a fonte e o CHECK vivo
 * (`_audit_doc_type_check_values`), entao o proximo tipo que entrar no CHECK reprova este guard
 * ate ganhar braco no intake e opcao na tela.
 *
 * As funcoes de decisao recebem dado puro: sao as MESMAS que julgam o estado real e o adulterado
 * das mutacoes.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

const WIZARD = readFileSync('src/components/governance/DocumentIntakeWizard.tsx', 'utf8');
const MODES = ['informational', 'binding', 'legal_signature'];

/** Remove comentarios de linha SQL, para que um braco citado em comentario nao conte. */
function semComentarioSql(body) {
  return body.split('\n').map((l) => { const i = l.indexOf('--'); return i >= 0 ? l.slice(0, i) : l; }).join('\n');
}

/** Os bracos do CASE de acknowledgement_mode, como mapa tipo -> modo, recortados DO bloco que decide. */
export function bracosDoIntake(body) {
  const code = semComentarioSql(body);
  const bloco = code.match(/v_acknowledgement_mode\s*:=\s*CASE\s+v_doc_type([\s\S]*?)\bEND\s*;/);
  if (!bloco) return null;
  const mapa = {};
  for (const m of bloco[1].matchAll(/WHEN\s+'([a-z_]+)'\s+THEN\s+'([a-z_]+)'/g)) mapa[m[1]] = m[2];
  return mapa;
}

/** Tipos do CHECK sem braco explicito no intake (o ELSE nao conta: foi ele que escondeu o defeito). */
export function semBraco(tipos, mapa) {
  return tipos.filter((t) => !(t in mapa)).sort();
}

/** Lista de tipos e espelho de modos declarados no wizard, recortados das DECLARACOES. */
export function doWizard(src) {
  const lista = src.match(/const DOC_TYPES:[^=]*=\s*\[([\s\S]*?)\];/);
  const espelho = src.match(/const ACK_DEFAULTS:[^=]*=\s*\{([\s\S]*?)\};/);
  const semComent = (s) => s.split('\n').map((l) => { const i = l.indexOf('//'); return i >= 0 ? l.slice(0, i) : l; }).join('\n');
  const tipos = lista ? [...semComent(lista[1]).matchAll(/'([a-z_]+)'/g)].map((m) => m[1]) : [];
  const ack = {};
  if (espelho) for (const m of semComent(espelho[1]).matchAll(/([a-z_]+):\s*'([a-z_]+)'/g)) ack[m[1]] = m[2];
  return { tipos, ack };
}

/** A recirculacao passa a classe da versao substituida ao lock? Afirma a CHAMADA inteira. */
export function recirculaComClasse(body) {
  const code = semComentarioSql(body).replace(/\s+/g, ' ');
  const le = /SELECT dv\.id, dv\.version_label, dv\.version_number, dv\.change_class INTO v_current_version/.test(code);
  const passa = /lock_document_version\(\s*v_draft\.id\s*,\s*v_chain\.gates\s*,\s*v_current_version\.change_class\s*\)/.test(code);
  return le && passa;
}

async function corpo(proname) {
  const { data, error } = await sb().rpc('_audit_function_source', { p_proname: proname });
  assert.equal(error, null, `_audit_function_source(${proname}) falhou: ${error?.message ?? ''}`);
  assert.ok(Array.isArray(data) && data.length === 1, `${proname}: esperava 1 sobrecarga, veio ${data?.length}`);
  const body = data[0]?.prosrc;
  assert.ok(typeof body === 'string' && body.length > 0, `${proname}: introspeccao sem corpo`);
  return body;
}

test(dbGated ? '#2435: todo tipo do CHECK tem braco no intake e opcao, com o mesmo modo, na tela' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    const { data: tipos, error } = await sb().rpc('_audit_doc_type_check_values');
    assert.equal(error, null, `_audit_doc_type_check_values indisponivel: ${error?.message ?? ''}`);
    // Controle: o CHECK tem de vir cheio, senao "nenhum tipo sem braco" passaria por vacuidade.
    assert.ok(Array.isArray(tipos) && tipos.length >= 16, `CHECK veio com ${tipos?.length} tipos`);

    const mapa = bracosDoIntake(await corpo('create_governance_document_intake'));
    assert.ok(mapa, 'nao achei o CASE de acknowledgement_mode no corpo vivo do intake');
    assert.deepEqual(semBraco(tipos, mapa), [],
      'tipo do CHECK sem braco explicito no intake: cairia no ELSE informational (#2435)');
    for (const m of Object.values(mapa)) assert.ok(MODES.includes(m), `modo desconhecido no intake: ${m}`);

    const w = doWizard(WIZARD);
    assert.deepEqual(tipos.filter((t) => !w.tipos.includes(t)).sort(), [],
      'tipo do CHECK sem opcao na tela de intake: nao ha como criar esse documento pela tela (#2435)');
    const divergentes = tipos.filter((t) => w.ack[t] !== mapa[t]).map((t) => `${t}: tela=${w.ack[t]} intake=${mapa[t]}`);
    assert.deepEqual(divergentes, [], 'o espelho ACK_DEFAULTS da tela diverge do intake vivo (#2435)');
  });

test(dbGated ? '#2435: a recirculacao herda a change_class da versao substituida' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    assert.ok(recirculaComClasse(await corpo('recirculate_governance_doc')),
      'recirculate_governance_doc voltou a chamar o lock sem a classe: a versao recirculada nasce NULL e congela (#2435)');
  });

test('#2435 mutacao: cada detector reprova a forma do defeito, pela MESMA funcao', () => {
  const INTAKE_OK = `
    v_acknowledgement_mode := CASE v_doc_type
      WHEN 'policy'          THEN 'binding'
      WHEN 'assignment_term' THEN 'legal_signature'
      ELSE 'informational'
    END;`;
  // controle positivo
  assert.deepEqual(semBraco(['policy', 'assignment_term'], bracosDoIntake(INTAKE_OK)), []);
  // mutacao 1: braco removido -> o tipo aparece como sem braco (o ELSE nao salva)
  const sem = INTAKE_OK.replace("WHEN 'assignment_term' THEN 'legal_signature'", '');
  assert.deepEqual(semBraco(['policy', 'assignment_term'], bracosDoIntake(sem)), ['assignment_term']);
  // mutacao 2: braco so em comentario nao conta
  const comentado = INTAKE_OK.replace("WHEN 'assignment_term'", "-- WHEN 'assignment_term'");
  assert.deepEqual(semBraco(['policy', 'assignment_term'], bracosDoIntake(comentado)), ['assignment_term']);
  // mutacao 3: CASE ausente -> null, e o teste real falha alto em vez de passar vazio
  assert.equal(bracosDoIntake('SELECT 1;'), null);

  const WIZ_OK = `const DOC_TYPES: DocType[] = [\n  'policy',\n  'assignment_term',\n];\nconst ACK_DEFAULTS: Record<DocType, AcknowledgementMode> = {\n  policy: 'binding',\n  assignment_term: 'legal_signature',\n};`;
  assert.deepEqual(doWizard(WIZ_OK).tipos, ['policy', 'assignment_term']);
  // mutacao 4: tipo so em comentario da lista nao conta como opcao
  assert.deepEqual(doWizard(WIZ_OK.replace("  'assignment_term',", "  // 'assignment_term',")).tipos, ['policy']);
  // mutacao 5: espelho divergente e visivel
  assert.equal(doWizard(WIZ_OK.replace("assignment_term: 'legal_signature'", "assignment_term: 'informational'")).ack.assignment_term, 'informational');

  const REC_OK = `SELECT dv.id, dv.version_label, dv.version_number, dv.change_class INTO v_current_version
    v_lock_result := public.lock_document_version(v_draft.id, v_chain.gates, v_current_version.change_class);`;
  assert.equal(recirculaComClasse(REC_OK), true);
  // mutacao 6: lock com 2 argumentos (o defeito original)
  assert.equal(recirculaComClasse(REC_OK.replace(', v_current_version.change_class)', ')')), false);
  // mutacao 7: le a classe mas nao passa
  assert.equal(recirculaComClasse(REC_OK.replace('v_current_version.change_class);', 'NULL);')), false);
  // mutacao 8: passa a classe mas nao a le (campo sempre NULL no record)
  assert.equal(recirculaComClasse(REC_OK.replace(', dv.change_class INTO', ' INTO')), false);
  // mutacao 9: a chamada certa so em comentario nao conta
  const comentLock = `SELECT dv.id, dv.version_label, dv.version_number, dv.change_class INTO v_current_version
    -- lock_document_version(v_draft.id, v_chain.gates, v_current_version.change_class)
    v_lock_result := public.lock_document_version(v_draft.id, v_chain.gates);`;
  assert.equal(recirculaComClasse(comentLock), false);
});
