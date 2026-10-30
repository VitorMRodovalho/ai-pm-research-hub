/**
 * #2392 (item da #2542, etapa 0 da ADR-0134): aprovar com menos avaliadores objetivos que o mínimo do
 * ciclo exige justificativa (Aceite Antecipado).
 *
 * Antes, o portão da #1572 só pedia justificativa com ZERO avaliações de qualquer tipo, e uma
 * candidatura com UMA objetiva num ciclo de `min_evaluators = 2` passava calada. Decisão do GP em
 * 02/10/2026: trava daqui para frente, contando também a candidatura ligada (no par `dual_track` a
 * objetiva fica numa das pontas).
 *
 * O QUE ESTE GUARD AFIRMA:
 *   A. `_selection_objective_evaluators` conta avaliador DISTINTO, só objetiva submetida, e segue o
 *      vínculo do par nos dois sentidos.
 *   B. `admin_update_application`: na transição para approved, a contagem do par contra o mínimo do
 *      ciclo da candidatura decide a recusa `early_acceptance_reason_required`, e mínimo vazio conta
 *      como não atingido.
 *   C. `finalize_decisions`: a mesma régua, com o mínimo do ciclo do lote, e a recusa vai para
 *      `refused` sem abortar as outras decisões.
 *   D. o helper não é executável por anon nem authenticated.
 *   E. no banco: o corpo vivo é este, e o helper bate com uma recontagem independente feita aqui,
 *      com controle positivo de que o par muda o número em pelo menos uma candidatura.
 *
 * Asserções amarram CONDIÇÃO ao RESULTADO dentro do bloco que decide, com comentários mascarados. A
 * camada estática lê a definição VIGENTE de cada função (última migration que a define), não um
 * arquivo fixo.
 *
 * Fora do escopo, medido em 30/10/2026: a importação do VEP grava `approved` direto quando a pessoa
 * está ativa no VEP (balde qualified), sem passar por estas funções.
 *
 * Efeito colateral: nenhum. A camada viva só lê.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const HELPER = '_selection_objective_evaluators';

const cap = (name) => latestFunctionCapture(ROOT, name);
const helperCap = cap(HELPER);
const helper = maskLineComments(helperCap.body);
const update = maskLineComments(cap('admin_update_application').body);
const finalize = maskLineComments(cap('finalize_decisions').body);

// ── Regras como regex, reusadas na camada estática e na viva ────────────────────────────────────────

const CONTAGEM = /SELECT count\(DISTINCT e\.evaluator_id\)::integer\s+FROM public\.selection_evaluations e\s+WHERE e\.evaluation_type = 'objective'\s+AND e\.submitted_at IS NOT NULL\s+AND e\.application_id IN \(/;
const PAR_IDA = /SELECT a\.linked_application_id FROM public\.selection_applications a\s+WHERE a\.id = p_application_id AND a\.linked_application_id IS NOT NULL/;
const PAR_VOLTA = /SELECT a\.id FROM public\.selection_applications a\s+WHERE a\.linked_application_id = p_application_id/;

// O ramo de mínimo vazio é opcional em (1) e obrigatório em (2): tirar só ele reprova (2) e mantém (1).
const NULO = String.raw`v_min_evaluators IS NULL OR `;
const cond = (nulo) => (nulo ? NULO : `(?:${NULO})?`) + String.raw`v_objective_evaluators < v_min_evaluators`;

const portaoUnico = (nulo) => new RegExp(
  String.raw`IF v_requested_status = 'approved' AND v_old_status <> 'approved' THEN\s+` +
  String.raw`v_objective_evaluators := public\._selection_objective_evaluators\(p_application_id\);\s+` +
  String.raw`SELECT c\.min_evaluators INTO v_min_evaluators\s+FROM public\.selection_cycles c\s+WHERE c\.id = v_app\.cycle_id;\s+` +
  String.raw`IF ` + cond(nulo) + String.raw` THEN\s+` +
  String.raw`v_early_reason := btrim\(coalesce\(p_data->>'early_acceptance_reason', ''\)\);\s+` +
  String.raw`IF length\(v_early_reason\) < 20 THEN\s+RETURN json_build_object\([\s\S]{0,500}?'code',\s+'early_acceptance_reason_required'`,
);

const MINIMO_DO_LOTE = /SELECT c\.min_evaluators INTO v_min_evaluators\s+FROM public\.selection_cycles c\s+WHERE c\.id = p_cycle_id;/;
const portaoLote = (nulo) => new RegExp(
  String.raw`IF v_status = 'approved' THEN\s+` +
  String.raw`v_objective_evaluators := public\._selection_objective_evaluators\(v_app_id\);\s+` +
  String.raw`IF ` + cond(nulo) + String.raw` THEN\s+` +
  String.raw`v_early_reason := btrim\(coalesce\(v_decision->>'early_acceptance_reason', ''\)\);\s+` +
  String.raw`IF length\(v_early_reason\) < 20 THEN\s+` +
  String.raw`v_refused := v_refused \|\| jsonb_build_array\(jsonb_build_object\(\s+'application_id', v_app_id,\s+'code',\s+'early_acceptance_reason_required'` +
  String.raw`[\s\S]{0,600}?\)\);\s+CONTINUE;`,
);

function afirmaHelper(src) {
  assert.match(src, CONTAGEM, 'conta avaliador distinto, só objetiva submetida');
}
function afirmaPar(src) {
  assert.match(src, PAR_IDA, 'o par inclui a candidatura para onde esta aponta');
  assert.match(src, PAR_VOLTA, 'o par inclui a candidatura que aponta para esta');
}
function afirmaLote(src, nulo) {
  const decide = src.match(portaoLote(nulo));
  assert.ok(decide, 'a contagem do par contra o mínimo decide a recusa no lote');
  const minimo = src.match(MINIMO_DO_LOTE);
  assert.ok(minimo, 'o mínimo vem do ciclo do lote');
  assert.ok(minimo.index < src.indexOf('FOR v_decision IN'), 'o mínimo é lido antes do laço');
}

// ── A. a régua ──────────────────────────────────────────────────────────────────────────────────────

test('A1. o helper conta avaliador distinto, só objetiva submetida', () => {
  afirmaHelper(helper);
});

test('A2. o helper segue o vínculo do par nos dois sentidos', () => {
  afirmaPar(helper);
});

// ── B. caminho de UMA candidatura ───────────────────────────────────────────────────────────────────

test('B1. a contagem do par contra o mínimo do ciclo decide a recusa, antes do UPDATE', () => {
  const m = update.match(portaoUnico(false));
  assert.ok(m, 'na transição para approved, abaixo do mínimo sem justificativa devolve early_acceptance_reason_required');
  const escrita = update.indexOf('UPDATE public.selection_applications SET');
  assert.ok(escrita !== -1 && m.index < escrita, 'a recusa vem antes da primeira escrita');
});

test('B2. mínimo vazio conta como não atingido no caminho de uma candidatura', () => {
  assert.match(update, portaoUnico(true));
});

// ── C. caminho em lote ──────────────────────────────────────────────────────────────────────────────

test('C1. no lote, a mesma régua recusa para refused e segue para a próxima decisão', () => {
  afirmaLote(finalize, false);
});

test('C2. mínimo vazio conta como não atingido no lote', () => {
  afirmaLote(finalize, true);
});

// ── D. ACL do helper ────────────────────────────────────────────────────────────────────────────────

test('D. o helper não é executável por anon nem authenticated', () => {
  const sql = maskLineComments(readFileSync(join(ROOT, 'supabase/migrations', helperCap.file), 'utf8'));
  assert.match(sql, /REVOKE EXECUTE ON FUNCTION public\._selection_objective_evaluators\(uuid\) FROM PUBLIC, anon, authenticated;/);
});

// ── E. banco ────────────────────────────────────────────────────────────────────────────────────────

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skip = dbGated ? false : 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

async function sbClient() {
  const { createClient } = await import('@supabase/supabase-js');
  return createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
}

/** Lê a tabela inteira em páginas: o PostgREST corta em 1000 linhas, e uma recontagem sobre leitura
 *  truncada divergiria do helper sem defeito nenhum nele. */
async function ler(sb, tabela, colunas) {
  const linhas = [];
  for (let de = 0; ; de += 1000) {
    const { data, error } = await sb.from(tabela).select(colunas).order('id').range(de, de + 999);
    assert.ifError(error);
    linhas.push(...data);
    if (data.length < 1000) break;
  }
  return linhas;
}

async function corpoVivo(sb, name) {
  const { data, error } = await sb.rpc('_audit_function_source', { p_proname: name });
  assert.ifError(error);
  assert.equal(data?.length, 1, `${name} precisa existir no banco com uma assinatura só`);
  // Sem esta checagem um prosrc vazio faria todo match reprovar por falta de leitura, não pela regra.
  assert.ok(typeof data[0].prosrc === 'string' && data[0].prosrc.length > 100, `corpo vivo de ${name} precisa ser legível`);
  return maskLineComments(data[0].prosrc);
}

test('E1. o corpo VIVO das três funções carrega a régua', { skip }, async () => {
  const sb = await sbClient();
  const h = await corpoVivo(sb, HELPER);
  afirmaHelper(h);
  afirmaPar(h);
  assert.match(await corpoVivo(sb, 'admin_update_application'), portaoUnico(true));
  afirmaLote(await corpoVivo(sb, 'finalize_decisions'), true);
});

test('E2. o helper bate com a recontagem independente, e o par muda o número em pelo menos uma', { skip }, async () => {
  const sb = await sbClient();
  const apps = await ler(sb, 'selection_applications', 'id, linked_application_id');
  const evals = await ler(sb, 'selection_evaluations', 'application_id, evaluator_id, evaluation_type, submitted_at');
  assert.ok(apps.length > 0 && evals.length > 0, 'a leitura precisa trazer candidaturas e avaliações');

  // Recontagem feita aqui, sem passar pelo helper: objetivas submetidas por candidatura, em avaliador.
  const objetivas = new Map();
  for (const e of evals) {
    if (e.evaluation_type !== 'objective' || e.submitted_at == null || e.evaluator_id == null) continue;
    if (!objetivas.has(e.application_id)) objetivas.set(e.application_id, new Set());
    objetivas.get(e.application_id).add(e.evaluator_id);
  }
  const apontamPara = new Map();
  for (const a of apps) {
    if (!a.linked_application_id) continue;
    if (!apontamPara.has(a.linked_application_id)) apontamPara.set(a.linked_application_id, []);
    apontamPara.get(a.linked_application_id).push(a.id);
  }
  const esperado = (a) => {
    const par = new Set([a.id, ...(a.linked_application_id ? [a.linked_application_id] : []), ...(apontamPara.get(a.id) ?? [])]);
    const quem = new Set();
    for (const id of par) for (const ev of objetivas.get(id) ?? []) quem.add(ev);
    return { par: quem.size, propria: objetivas.get(a.id)?.size ?? 0 };
  };

  const divergentes = [];
  let parMudou = 0;
  for (let i = 0; i < apps.length; i += 20) {
    const lote = apps.slice(i, i + 20);
    const vivos = await Promise.all(lote.map(async (a) => {
      const { data, error } = await sb.rpc(HELPER, { p_application_id: a.id });
      assert.ifError(error);
      return data;
    }));
    lote.forEach((a, k) => {
      const exp = esperado(a);
      if (vivos[k] !== exp.par) divergentes.push(`${a.id.slice(0, 8)}: helper ${vivos[k]}, recontagem ${exp.par}`);
      if (exp.par !== exp.propria) parMudou += 1;
    });
  }

  assert.deepEqual(divergentes, [], 'o helper diverge da recontagem independente');
  // Controle positivo: sem nenhuma candidatura em que o par muda o número, a soma do par passaria
  // verde mesmo se o helper ignorasse o vínculo.
  assert.ok(parMudou >= 1, 'nenhuma candidatura em que o par muda a contagem: o teste perdeu o objeto');
});
