/**
 * #3100: o portao de filiacao (#2585) chega a selecao.
 *
 * Antes, affiliation_gate so rodava na assinatura do Termo de Voluntariado. Quem nao tinha afiliacao verificada a um
 * capitulo participante era aprovado, ganhava o vinculo volunteer ativo e ficava parado no termo.
 *
 * O QUE ESTE GUARD AFIRMA (sempre sobre a captura VIGENTE de cada funcao)
 *   A. affiliation_gate_first_term e a regra do primeiro termo: quem nao e guest passa como renovacao, guest le
 *      affiliation_gate. E get_my_affiliation_gate delega a ela, sem uma segunda copia da regra;
 *   B. approve_selection_application le o portao DEPOIS do vinculo e das afiliacoes pmi_vep, devolve no resultado e
 *      grava no log, e NAO bloqueia: nenhum desvio de fluxo depende do portao;
 *   C. get_volunteers_with_closed_affiliation_gate tem a audiencia da fila de filiacao (filiacao_director ou
 *      manage_member) e lista vinculo volunteer ativo cujo affiliation_gate nao abriu, com o motivo do proprio portao;
 *   D. grants: o portao do primeiro termo nao e executavel por anon nem authenticated; a lista nao por anon;
 *   E. a tela de selecao avisa nos tres caminhos de aprovacao, so quando a decisao e approved e o portao veio fechado;
 *      a fila de filiacao chama a lista e mostra o motivo;
 *   F. os rotulos existem nos 3 idiomas;
 *   G. (banco) anon nao executa a lista;
 *   H. audiencia 'all_active_operational' (GP, 19/11/2026): guest com vinculo volunteer ativo entra; register_own_presence
 *      e get_my_meetings chamam a mesma funcao; o selo de faltas fica de fora de proposito.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { latestFunctionCapture, maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const cap = (name) => {
  const c = latestFunctionCapture(ROOT, name);
  return { ...c, body: maskLineComments(c.body), block: maskLineComments(c.block), sql: maskLineComments(readFileSync(resolve(ROOT, 'supabase/migrations', c.file), 'utf8')) };
};
const FIRST = cap('affiliation_gate_first_term');
const MY = cap('get_my_affiliation_gate');
const APPROVE = cap('approve_selection_application');
const LIST = cap('get_volunteers_with_closed_affiliation_gate');
const PAGE = maskJsComments(readFileSync(resolve(ROOT, 'src/pages/admin/selection.astro'), 'utf8'));
const ISLAND = maskJsComments(readFileSync(resolve(ROOT, 'src/components/admin/AffiliationQueueIsland.tsx'), 'utf8'));

test('A. a regra do primeiro termo mora num lugar so', () => {
  assert.match(FIRST.body, /RETURN CASE\s+WHEN EXISTS \(SELECT 1 FROM public\.members WHERE id = p_member_id AND operational_role IS DISTINCT FROM 'guest'\)\s+THEN jsonb_build_object\('open', true, 'path', 'renewal'\)\s+ELSE public\.affiliation_gate\(p_member_id\)\s+END;/);
  assert.match(MY.body, /RAISE EXCEPTION 'Not authenticated'[^;]*;\s+END IF;\s+RETURN public\.affiliation_gate_first_term\(v_member_id\);\s+END;/);
  assert.doesNotMatch(MY.body, /public\.affiliation_gate\(/, 'get_my_affiliation_gate nao pode ler o portao cru: seria a segunda copia da regra');
});

test('B. a aprovacao le o portao depois do vinculo, devolve e registra, e nao bloqueia', () => {
  const b = APPROVE.body;
  const leitura = b.indexOf('v_affiliation_gate := public.affiliation_gate_first_term(v_member_id);');
  const vinculo = b.indexOf('INSERT INTO public.engagements (');
  const afiliacao = b.indexOf("PERFORM public.upsert_chapter_affiliation(v_person_id, v_code, 'pmi_vep', false);");
  const log = b.indexOf('INSERT INTO public.data_anomaly_log');
  assert.ok(vinculo > 0 && afiliacao > 0 && leitura > vinculo && leitura > afiliacao && leitura < log,
    `${APPROVE.file}: o portao precisa ser lido depois do vinculo e das afiliacoes, antes do log`);
  const retorno = b.slice(b.lastIndexOf("RETURN jsonb_build_object(\n    'success',            true,"));
  assert.match(retorno, /'entry_chapter_derived',\s+v_entry_derived,\s+'affiliation_gate',\s+v_affiliation_gate\s+\);\s+END;/);
  const ctx = b.slice(log, b.indexOf('RETURN jsonb_build_object(', log));
  assert.match(ctx, /'affiliation_gate',\s+v_affiliation_gate\s+\)\s+\);/);
  assert.equal((b.match(/v_affiliation_gate/g) || []).length, 4, 'v_affiliation_gate: declaracao, leitura, log e retorno; outro uso e desvio de fluxo');
});

test('C. a lista: audiencia da fila de filiacao, vinculo volunteer ativo, portao cru fechado', () => {
  const b = LIST.body;
  assert.match(b, /IF NOT \('filiacao_director' = ANY\(COALESCE\(v_caller_designations, '\{\}'::text\[\]\)\)\)\s+AND NOT public\.can_by_member\(v_caller_id, 'manage_member'\) THEN\s+RAISE EXCEPTION/);
  assert.match(b, /IF v_caller_id IS NULL THEN\s+RAISE EXCEPTION/);
  assert.match(b, /WHERE e\.person_id = m\.person_id AND e\.kind = 'volunteer' AND e\.status = 'active'\s+\) v ON v\.engagement_start IS NOT NULL/);
  assert.match(b, /public\.affiliation_gate\(m\.id\) AS gate[\s\S]*?WHERE NOT COALESCE\(\(x\.gate ->> 'open'\)::boolean, false\)/);
  assert.match(b, /'first_term',\s+x\.operational_role = 'guest',/);
  assert.match(b, /'reason',\s+x\.gate ->> 'reason',/);
  assert.match(LIST.block, /RETURNS jsonb\s+LANGUAGE plpgsql\s+STABLE SECURITY DEFINER\s+SET search_path TO 'public', 'pg_temp'/);
});

test('D. grants', () => {
  assert.match(FIRST.sql, /REVOKE ALL ON FUNCTION public\.affiliation_gate_first_term\(uuid\) FROM PUBLIC, anon, authenticated;/);
  assert.doesNotMatch(FIRST.sql, /GRANT[^;]*affiliation_gate_first_term\(uuid\)[^;]*\b(anon|authenticated)\b/);
  assert.match(LIST.sql, /REVOKE ALL ON FUNCTION public\.get_volunteers_with_closed_affiliation_gate\(\) FROM PUBLIC, anon;\s+GRANT EXECUTE ON FUNCTION public\.get_volunteers_with_closed_affiliation_gate\(\) TO authenticated, service_role;/);
  assert.doesNotMatch(LIST.sql, /GRANT[^;]*get_volunteers_with_closed_affiliation_gate\(\)[^;]*\banon\b/);
  assert.match(APPROVE.sql, /REVOKE ALL ON FUNCTION public\.approve_selection_application\(uuid, jsonb\) FROM PUBLIC, anon;/);
});

test('E. a selecao avisa nos tres caminhos de aprovacao; a fila mostra a lista', () => {
  assert.match(PAGE, /function affiliationGateClosedReason\(data: any\): string \| null \{\s+const gate = data\?\.canonical\?\.affiliation_gate;\s+if \(!gate \|\| gate\.open !== false\) return null;/);
  // modal
  assert.match(PAGE, /const gateReason = newStatus === 'approved' \? affiliationGateClosedReason\(data\) : null;\s+if \(gateReason\) warnAffiliationGate\(row\.applicant_name \|\| '', gateReason\);/);
  // linha
  assert.match(PAGE, /const gateReason = decision === 'approved' \? affiliationGateClosedReason\(data\) : null;\s+if \(gateReason\) warnAffiliationGate\(name, gateReason\);/);
  // lote
  assert.match(PAGE, /if \(decision === 'approved' && affiliationGateClosedReason\(data\)\) \{\s+gateClosed\.push\(/);
  assert.match(PAGE, /if \(gateClosed\.length\) \{[\s\S]{0,400}?alert\(tpl\.replace\('\{n\}', String\(gateClosed\.length\)\)/);
  assert.match(PAGE, /function warnAffiliationGate\(name: string, reason: string\) \{[\s\S]{0,400}?alert\(tpl\.replace\('\{name\}', name\)\.replace\('\{reason\}', affiliationReasonLabel\(reason\)\)\);/);

  assert.match(ISLAND, /sb\.rpc\('get_volunteers_with_closed_affiliation_gate'\)\s+\.then\(\(\{ data: cg \}: any\) => setClosedGate\(Array\.isArray\(cg\) \? cg : \[\]\)\)/);
  assert.match(ISLAND, /\{closedGate\.length > 0 && \(/);
  assert.match(ISLAND, /t\(`comp\.affiliationQueue\.closedGateReason\.\$\{r\.reason \|\| 'unknown'\}`/);
});

test('F. rotulos nos 3 idiomas', () => {
  const keys = [
    'admin.selection.affiliationGateWarn', 'admin.selection.affiliationGateBulkWarn',
    ...['not_affiliated', 'entry_chapter_required', 'unknown'].flatMap((r) => [
      `admin.selection.affiliationGateReason.${r}`, `comp.affiliationQueue.closedGateReason.${r}`]),
    'comp.affiliationQueue.closedGateTitle', 'comp.affiliationQueue.closedGateHint',
    'comp.affiliationQueue.closedGateFirstTerm', 'comp.affiliationQueue.closedGateRenewal',
  ];
  for (const p of ['src/i18n/pt-BR.ts', 'src/i18n/en-US.ts', 'src/i18n/es-LATAM.ts']) {
    const src = readFileSync(resolve(ROOT, p), 'utf8');
    for (const k of keys) assert.match(src, new RegExp(`'${k.replace(/\./g, '\\.')}': '[^']+'`), `${p} ${k}`);
  }
  // os motivos que a tela traduz sao exatamente os que o portao devolve fechado
  const gate = maskLineComments(latestFunctionCapture(ROOT, 'affiliation_gate').body);
  const motivos = new Set([...gate.matchAll(/'reason', (?:'([a-z_]+)'|CASE WHEN v_bucket = 'not_affiliated' THEN '([a-z_]+)' ELSE '([a-z_]+)' END)/g)]
    .flatMap((m) => m.slice(1).filter(Boolean)));
  assert.deepEqual([...motivos].sort(), ['entry_chapter_required', 'not_affiliated', 'unknown']);
});

test('H. audiencia da organizacao: guest com vinculo volunteer ativo entra, pela mesma funcao nas duas leitoras', () => {
  const AUD = cap('_in_all_active_operational');
  assert.match(AUD.body, /SELECT m\.current_cycle_active IS TRUE\s+AND \(m\.operational_role <> 'guest'\s+OR EXISTS \(SELECT 1 FROM public\.engagements e\s+WHERE e\.person_id = m\.person_id AND e\.kind = 'volunteer' AND e\.status = 'active'\)\)\s+FROM public\.members m\s+WHERE m\.id = p_member_id\s+\), false\)/);
  for (const name of ['register_own_presence', 'get_my_meetings']) {
    const b = cap(name).body;
    assert.match(b, /OR \(ar\.target_type = 'all_active_operational'\s+AND public\._in_all_active_operational\(v_member_id\)\)/, `${name}: o ramo all_active_operational chama a regra`);
    assert.doesNotMatch(b, /v_member_role <> 'guest'/, `${name}: a exclusao antiga de guest voltou`);
  }
  assert.match(AUD.sql, /REVOKE ALL ON FUNCTION public\._in_all_active_operational\(uuid\) FROM PUBLIC, anon, authenticated;/);
  // De proposito fora: o selo grava falta pela coorte de v_member_operational_tiers, nao pela audiencia.
  for (const name of ['_seal_event_attendance_apply', 'preview_seal_attendance']) {
    const b = cap(name).body;
    assert.match(b, /vt\.operational_tier IN \('researcher','tribe_leader','manager'\)/, `${name}: coorte do selo`);
    assert.doesNotMatch(b, /_in_all_active_operational/, `${name}: o selo nao segue a audiencia (decisao do #3100)`);
  }
});

const URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const ANON = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;

test('G. (banco) anon nao executa a lista', { skip: URL && ANON ? false : 'SUPABASE_URL + anon key required' }, async () => {
  const r = await fetch(`${URL}/rest/v1/rpc/get_volunteers_with_closed_affiliation_gate`, {
    method: 'POST',
    headers: { apikey: ANON, Authorization: `Bearer ${ANON}`, 'Content-Type': 'application/json' },
    body: '{}',
  });
  // 401/403 = a funcao existe e anon foi negado. 404 seria funcao ausente, e nao pode passar por "negado".
  assert.ok([401, 403].includes(r.status), `anon recebeu HTTP ${r.status}`);
});
