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

// O guard e um ratchet: pode cair, nunca subir.
//
// Baseline 1 -> 0 em 04/09/2026, e a queda e o ratchet fazendo o trabalho dele. Em 03/09 o mesmo
// caminho promoveu uma SEGUNDA candidatura e o numero subiu para 2, o que mostrou que deixar o caso
// historico parado em `interview_pending` nao era neutro: era manter viva a leitura de que uma
// candidatura sem avaliacao naquele estado e tolerada. Decisao do GP (04/09): as duas voltaram a
// `submitted` via `admin_update_application`, com os 5 pilares de opt-out PRESERVADOS (a escolha do
// candidato continua registrada; o que voltou atras foi so a promocao) e rastro em `admin_audit_log`
// sob `selection.optout_promotion_reverted`.
//
// Por que a devolucao teve de ser um ato explicito: `recompute_application_status` e SO-PARA-FRENTE
// (`can_r > cur_r`), e com zero avaliacoes objetivas o status canonico sai NULL, entao a candidatura
// e filtrada fora do reconciliador. Nenhuma rodada de auto-cura iria desfazer isso.
const BASELINE_SEM_AVALIACAO = 0;

// ⚠️ Esta asserção MUDOU em 03/09/2026, e a mudança é a correção da decisão de 28/08.
//
// A opção C restringiu a origem da promoção a `submitted`, e o guard afirmava exatamente isso
// (`IF v_app_status = 'submitted' THEN`). Só que a medição que embasou a decisão, transcrita no
// cabeçalho acima, mostra que `submitted` era a ÚNICA origem com ZERO avaliação: foram removidas
// quatro origens nunca exercidas e mantida a única que produzia o salto. Em 03/09 o mesmo caminho
// repetiu e o ratchet subiu de 1 para 2.
//
// A decisão nova é mais simples: o opt-out não promove de origem nenhuma.
//
// Por que a asserção deixou de casar a FORMA do IF: um guard textual não distingue "promover a
// partir da lista" de "recusar a partir da lista" — as duas escrevem a mesma string em direções
// opostas (classe do guard que classifica uma direção e fica verde na outra). Então o guard passa
// a exigir a AUSÊNCIA do que só existe para promover: o nome do estado e a escrita na tabela.
test('#2004 estático: o opt-out NÃO promove, de origem nenhuma', () => {
  assert.ok(FN, 'opt_out_all_pillars não foi capturada por nenhuma migration');
  // Comentários fora ANTES de medir: o texto que explica o anti-padrão cita o anti-padrão, e um
  // guard que casa o próprio comentário reprova (ou passa) pelo motivo errado (#1910).
  const code = FN.body.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');
  assert.doesNotMatch(code, /interview_pending/,
    'o corpo executável voltou a citar o estado de aguardando entrevista — aqui só há um motivo para citá-lo: promover');
  assert.doesNotMatch(code, /UPDATE\s+selection_applications/i,
    'o opt-out voltou a escrever em selection_applications: a promoção foi reintroduzida');
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
  const rastroPos = b.indexOf('opt_out_promotion_refused');
  assert.ok(insertPos > -1 && rastroPos > -1, 'não achei o insert dos pilares ou o rastro da recusa');
  assert.ok(insertPos < rastroPos,
    'o registro dos 5 pilares saiu de antes do rastro: a escolha do candidato tem de ser gravada primeiro');
  // O INSERT dos pilares não pode ficar condicionado a status nenhum: opt-out é direito do
  // candidato em qualquer estado, e só a PROMOÇÃO era o que estava sob portão.
  const antesDoInsert = b.slice(0, insertPos);
  assert.doesNotMatch(antesDoInsert, /IF\s+v_app_status/,
    'apareceu um IF sobre status antes do insert dos pilares: a escolha voltou a ficar condicionada');
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
