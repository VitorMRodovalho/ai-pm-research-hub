// tests/contracts/2004-opt-out-nao-pula-a-fase-objetiva.test.mjs
// Register in BOTH the "test:behavioural" and "test:contracts" whitelists in package.json (#1109).
/**
 * #2004 — escolher entrevista ao vivo deixa de saltar a fase objetiva.
 *
 * SINTOMA (PM, 26/08): um candidato em "Aguardando Entrevista" com ZERO avaliação objetiva, os três
 * scores NULL, nenhuma linha em `selection_interviews`, sem bypass de admin e sem resgate.
 *
 * MECANISMO: `opt_out_all_pillars` roda como `anon` — o candidato abre o link do token, e isso é
 * intencional — e promovia para `interview_pending` a partir de QUATRO status sem olhar avaliação.
 * O portão do #1613 existe e está correto, mas guarda a entrada em `interview_scheduled`;
 * `interview_pending` é o estado ambíguo (pré-entrada E pós-cancelamento), e o opt-out escrevia
 * exatamente ali, por baixo.
 *
 * DECISÃO DO PM (28/08): opção C, portão primeiro. Origem passa a ser só `submitted`.
 *
 * ⚠️ POR QUE `submitted` APENAS NÃO QUEBRA O FLUXO LEGÍTIMO — e por que isso é medição, não
 * suposição. Histórico completo das transições para `interview_pending` em 28/08:
 *
 *     (null)                8 transições, 8 já tinham avaliação   <- fase objetiva
 *     interview_scheduled   1 transição,  1 já tinha avaliação    <- retorno de cancelamento
 *     submitted             1 transição,  0 tinham avaliação      <- o opt-out, o caso da issue
 *
 * Ninguém NUNCA optou a partir de `screening`, `objective_eval` ou `objective_cutoff`. A restrição
 * remove superfície que nunca foi exercida.
 *
 * Cross-ref: #2004, #1613 (o portão que guarda a OUTRA transição), #2012 (recusa que não commita
 * não existe — daí a recusa registrada aqui).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

const FN = latestFunctionCapture(ROOT, 'opt_out_all_pillars');

// O caso historico da issue segue em producao: a decisao foi sobre o PORTAO, e mover a candidatura
// de alguem e ato sobre pessoa real, que cabe ao PM. O guard e um ratchet: pode cair, nunca subir.
const BASELINE_SEM_AVALIACAO = 1;

test('#2004 estático: promove SÓ de submitted', () => {
  assert.ok(FN, 'opt_out_all_pillars não foi capturada por nenhuma migration');
  const b = FN.body;
  assert.match(b, /IF v_app_status = 'submitted' THEN/,
    'a promoção precisa ser condicionada a submitted, e só');
  // A lista antiga aceitava quatro origens. Se ela voltar, o salto volta com ela.
  assert.doesNotMatch(b, /v_app_status IN \(\s*'submitted'\s*,\s*'screening'/,
    'a lista de quatro origens voltou — de objective_eval em diante, promover pula a régua');
});

test('#2004 estático: a recusa deixa rastro, em vez de silêncio', () => {
  const b = FN.body;
  assert.match(b, /opt_out_promotion_refused/,
    'sem registro, "alguém tentou saltar" é indistinguível de "ninguém tentou" (#2012)');
  assert.match(b, /admin_audit_log/, 'a recusa vai para a auditoria, não para um contador em memória');
});

test('#2004 estático: a ESCOLHA do candidato continua registrada em qualquer status', () => {
  // O portão limita a PROMOÇÃO, não o direito de escolher entrevista ao vivo. Se alguém "consertar"
  // movendo o INSERT dos 5 pilares para dentro do IF, o candidato perde o registro da própria opção.
  const b = FN.body;
  const insertPos = b.indexOf('INSERT INTO pmi_video_screenings');
  const gatePos = b.indexOf("IF v_app_status = 'submitted' THEN");
  assert.ok(insertPos > -1 && gatePos > -1, 'não achei o insert dos pilares ou o portão');
  assert.ok(insertPos < gatePos,
    'o registro do opt-out foi para dentro do portão: quem não é promovido perderia o registro da escolha');
});

test('#2004 vivo: ninguém NOVO chega a interview_pending sem avaliação (ratchet)',
  { skip: dbGated ? false : skipMsg }, async () => {
  const s = sb();
  const { data: cycles } = await s.from('selection_cycles').select('id').eq('status', 'open');
  const ids = (cycles ?? []).map((c) => c.id);
  assert.ok(ids.length > 0, 'nenhum ciclo aberto — o guard passaria por vacuidade');

  const { data: apps, error } = await s
    .from('selection_applications').select('id').eq('status', 'interview_pending').in('cycle_id', ids);
  assert.ok(!error, error?.message);
  assert.ok((apps ?? []).length > 0, 'ninguém em interview_pending — o guard não mediria nada');

  const { data: evals } = await s
    .from('selection_evaluations').select('application_id').in('application_id', (apps ?? []).map((a) => a.id));
  const comAvaliacao = new Set((evals ?? []).map((e) => e.application_id));
  const sem = (apps ?? []).filter((a) => !comAvaliacao.has(a.id));

  assert.ok(sem.length <= BASELINE_SEM_AVALIACAO,
    `${sem.length} candidaturas em interview_pending sem NENHUMA avaliação objetiva ` +
    `(baseline ${BASELINE_SEM_AVALIACAO}). O portão fechou a entrada nova; se este número SUBIU, ` +
    `existe outro caminho promovendo sem régua.`);

  // CONTROLE POSITIVO: o zero-ou-um só vale se a leitura de avaliações funciona. Se NINGUÉM tivesse
  // avaliação, a lista acima seria toda a população e o teste falharia por outro motivo — este
  // número mostra que a junção enxerga.
  assert.ok(comAvaliacao.size > 0,
    'nenhuma candidatura em interview_pending tem avaliação — a junção não está medindo');
});
