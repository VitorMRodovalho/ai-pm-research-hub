/**
 * #3168: o aviso de filiação pendente (entry_chapter_action_needed) sai também na aprovação, sob o mesmo interruptor
 * do cron (affiliation_nudge_enabled) e com o mesmo dedupe de 30 dias.
 *
 * Trava (sobre a CAPTURA VIGENTE de cada função):
 *   A. o gatilho (affiliation_nudge_on_approval): desligado devolve 'disabled' ANTES de ler qualquer outra coisa; fora
 *      da coorte do cron, 'not_needed'; na coorte sem variante, 'internal_only'; senão o envio único decide entre
 *      'sent' e 'skipped_recent';
 *   B. a coorte e a variante são as do cron: o gatilho lê a mesma coorte do plano e a mesma função de variante;
 *   C. sem duplicar com o cron: o cron e o gatilho chamam o mesmo envio (affiliation_nudge_deliver), e é ele quem
 *      guarda o dedupe; nenhuma das duas funções chama create_notification por fora;
 *   D. a aprovação chama o gatilho depois do portão e do aviso de aprovado, antes do log, e só grava o resultado no log
 *      e no retorno: nenhum desvio de fluxo depende dele;
 *   E. migration: as funções internas não são executáveis por anon nem authenticated, e a pós-condição prova que o
 *      plano do cron não mudou com a variante fatorada.
 *
 * O controle no banco, nos dois sentidos do interruptor, roda numa transação desfeita pela orquestradora (pacote da
 * #3168): mutar o arquivo não exercita a camada viva.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const cap = (n) => maskLineComments(latestFunctionCapture(ROOT, n).body);
const ON_APPROVAL = cap('affiliation_nudge_on_approval');
const DELIVER = cap('affiliation_nudge_deliver');
const PLAN = cap('affiliation_nudge_plan');
const N = cap('nudge_entry_chapter_cohort');
const APPROVE = cap('approve_selection_application');
const MIG = (() => {
  const dir = resolve(ROOT, 'supabase/migrations');
  const f = readdirSync(dir).filter((n) => /^\d{14}_3168_aviso_de_filiacao_na_aprovacao\.sql$/.test(n));
  assert.equal(f.length, 1, 'a migration da #3168 existe uma vez');
  return maskLineComments(readFileSync(resolve(dir, f[0]), 'utf8'));
})();

test('A. desligado devolve disabled antes de tudo; depois coorte, variante e envio', () => {
  assert.match(
    ON_APPROVAL,
    /BEGIN\s+IF NOT public\.affiliation_nudge_enabled\(\) THEN\s+RETURN jsonb_build_object\('status', 'disabled', 'variant', NULL\);\s+END IF;/,
    'o interruptor é a primeira decisão, e desligado retorna',
  );
  const off = ON_APPROVAL.indexOf('IF NOT public.affiliation_nudge_enabled() THEN');
  for (const depois of ['public.affiliation_needs_review(', 'public.affiliation_nudge_variant(', 'public.affiliation_nudge_deliver(']) {
    assert.ok(ON_APPROVAL.indexOf(depois) > off, `${depois} só depois do interruptor`);
  }
  assert.match(ON_APPROVAL, /IF v_variant IS NULL THEN\s+RETURN jsonb_build_object\('status', 'internal_only', 'variant', NULL\);\s+END IF;/);
  assert.match(
    ON_APPROVAL,
    /IF public\.affiliation_nudge_deliver\(p_member_id, v_variant\) THEN\s+RETURN jsonb_build_object\('status', 'sent', 'variant', v_variant\);\s+END IF;\s+RETURN jsonb_build_object\('status', 'skipped_recent', 'variant', v_variant\);/,
  );
});

test('B. a coorte e a variante são as do cron', () => {
  assert.match(
    ON_APPROVAL,
    /IF NOT EXISTS \(SELECT 1 FROM public\.members m WHERE m\.id = p_member_id AND m\.member_status = 'active'\)\s+OR NOT public\.affiliation_needs_review\(p_member_id\) THEN\s+RETURN jsonb_build_object\('status', 'not_needed', 'variant', NULL\);/,
    'fora da coorte (ativo e portão fechado), não avisa',
  );
  assert.match(PLAN, /WHERE m\.member_status = 'active'\s+AND public\.affiliation_needs_review\(m\.id\)/, 'a mesma coorte no plano do cron');
  assert.match(ON_APPROVAL, /v_variant := public\.affiliation_nudge_variant\(p_member_id\);/);
  assert.match(PLAN, /public\.affiliation_nudge_variant\(m\.id\) AS variant/, 'a mesma variante no plano do cron');
  assert.doesNotMatch(ON_APPROVAL, /CASE|affiliation_gate\(|affiliation_vep_snapshot\(/, 'o gatilho não tem cópia da regra da variante');
});

test('C. sem duplicar com o cron: um envio só, com o dedupe dentro', () => {
  assert.match(N, /IF NOT public\.affiliation_nudge_deliver\(v_rec\.member_id, v_rec\.variant\) THEN/, 'o cron envia pelo envio único');
  assert.match(
    DELIVER,
    /IF EXISTS \(\s+SELECT 1 FROM public\.notifications n\s+WHERE n\.recipient_id = p_member_id\s+AND n\.type = 'entry_chapter_action_needed'\s+AND n\.created_at > now\(\) - interval '30 days'\s+\) THEN\s+RETURN false;/,
    'o dedupe lê o tipo nos últimos 30 dias, qualquer que seja a origem (cron ou aprovação)',
  );
  assert.match(DELIVER, /PERFORM public\.create_notification\(\s+p_member_id,\s+'entry_chapter_action_needed',/, 'e grava o mesmo tipo que o dedupe lê');
  for (const [nome, corpo] of [['affiliation_nudge_on_approval', ON_APPROVAL], ['nudge_entry_chapter_cohort', N]]) {
    assert.doesNotMatch(corpo, /create_notification|interval '30 days'/, `${nome} não envia nem deduplica por fora`);
  }
  assert.doesNotMatch(APPROVE, /entry_chapter_action_needed/, 'a aprovação não envia o aviso por fora do gatilho');
});

test('D. a aprovação chama o gatilho depois do portão e do aviso de aprovado, e não desvia por ele', () => {
  const portao = APPROVE.indexOf('v_affiliation_gate := public.affiliation_gate_first_term(v_member_id);');
  const aprovado = APPROVE.indexOf("'selection_approved',");
  const gatilho = APPROVE.indexOf('v_affiliation_nudge := public.affiliation_nudge_on_approval(v_member_id);');
  const log = APPROVE.indexOf('INSERT INTO public.data_anomaly_log');
  assert.ok(portao > 0 && aprovado > portao && gatilho > aprovado && log > gatilho,
    'portão, aviso de aprovado, gatilho e log nessa ordem');
  assert.equal((APPROVE.match(/v_affiliation_nudge\b/g) || []).length, 4,
    'v_affiliation_nudge: declaração, chamada, log e retorno; outro uso é desvio de fluxo');
  assert.match(APPROVE, /'affiliation_gate',\s+v_affiliation_gate,\s+'affiliation_nudge',\s+v_affiliation_nudge\s+\)\s+\);/, 'no log');
  assert.match(APPROVE, /'affiliation_gate',\s+v_affiliation_gate,\s+'affiliation_nudge',\s+v_affiliation_nudge\s+\);\s+END;/, 'no retorno');
});

test('E. migration: internas fechadas e o plano do cron provado igual', () => {
  for (const sig of ['affiliation_nudge_variant\\(uuid\\)', 'affiliation_nudge_deliver\\(uuid, text\\)', 'affiliation_nudge_on_approval\\(uuid\\)']) {
    assert.match(MIG, new RegExp(`REVOKE ALL ON FUNCTION public\\.${sig} FROM PUBLIC, anon, authenticated;`));
    assert.doesNotMatch(MIG, new RegExp(`GRANT[^;]*${sig}[^;]*\\b(anon|authenticated)\\b`), `${sig} é interna`);
  }
  const antes = MIG.indexOf('CREATE TEMP TABLE _3168_plano_antes AS');
  const redefine = MIG.indexOf('CREATE OR REPLACE FUNCTION public.affiliation_nudge_plan()');
  assert.ok(antes > 0 && redefine > antes, 'o plano de antes é guardado antes de o plano ser redefinido');
  const pos = MIG.slice(MIG.indexOf('DO $postcondition$'));
  assert.match(
    pos,
    /EXCEPT ALL SELECT member_id, variant FROM public\.affiliation_nudge_plan\(\)\)\s+UNION ALL\s+\(SELECT member_id, variant FROM public\.affiliation_nudge_plan\(\)\s+EXCEPT ALL SELECT member_id, variant FROM _3168_plano_antes\)/,
    'a diferença é medida nos dois sentidos',
  );
  assert.match(pos, /IF v_diff <> 0 THEN\s+RAISE EXCEPTION/);
  // chamada, não a assinatura citada em has_function_privilege
  assert.doesNotMatch(pos, /affiliation_nudge_on_approval\((?!uuid\))|affiliation_nudge_deliver\((?!uuid, text\))|nudge_entry_chapter_cohort\((?!boolean\))/,
    'a pós-condição não envia: o aviso está ligado em produção');
});
