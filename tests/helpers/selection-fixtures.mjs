// tests/helpers/selection-fixtures.mjs
//
// #1636 — personas sintéticas para a família do gate de entrevista.
//
// O DEFEITO QUE ESTE ARQUIVO FECHA. Os testes DB-aware do arco #1584/#1594/#1595/#1598/#1640
// escolhiam a candidatura-alvo por PREDICADO sobre a base de produção (`.eq('status',
// 'interview_pending')`, ciclo aberto / ciclo fechado) e chamavam
// `_issue_interview_booking_token_core` com `p_caller_id: null`. Como a metade (b) do #1594 exige
// que a linha de recusa COMMITE, cada `npm test` sedimentava recusas permanentes em prod, sempre
// sobre as MESMAS candidaturas reais.
//
// Medido em 08/08/2026 contra produção: `gate_attempts` com 663 linhas, das quais 627 sem ator,
// espalhadas por 13 candidaturas reais (3 delas concentrando 489). E o caminho de PASSAGEM emitiu
// 4 tokens de agendamento reais que sobreviveram à limpeza do próprio teste (run `31144140275`,
// 07/08 03:23–03:31), vivos até 21/08 apontando para candidaturas reais.
//
// A CONVENÇÃO É A DO #1437, não uma nova. Aquele issue já resolveu esta classe para `members`: um
// e-mail em domínio reservado por RFC 2606 / RFC 6761 nunca alcança uma pessoa, então a linha é
// dado de teste POR CONSTRUÇÃO, seja qual for o nome que carregue. E a invariante que ficou de pé
// lá vale aqui: o problema não é a fixture EXISTIR, é ela PERSISTIR. Por isso este helper não
// varre sobreviventes de corridas anteriores — quem faz isso é o guard do #1636, em vermelho.
// (Varrer aqui seria exatamente o "purgar sobrevivente não é o conserto" que o #1437 já pagou.)
//
// ⚠️ ORDEM DE LIMPEZA NÃO É COSMÉTICA. O grafo de FK de `selection_applications` tem duas
// dependências `NO ACTION` (`selection_dispatch_url_log`, `onboarding_progress`) e uma família
// `CASCADE` (`gate_attempts`, `selection_interviews`, `selection_evaluations`,
// `selection_membership_snapshots`, ...). `onboarding_tokens` não tem FK nenhuma: o vínculo é
// polimórfico (`source_type='pmi_application'` + `source_id`), que é precisamente por que os 4
// tokens de 07/08 sobreviveram sem ninguém notar. Os apagáveis à mão vêm primeiro; o DELETE da
// candidatura leva o resto no CASCADE.

import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

/**
 * Domínios reservados por RFC 2606 / RFC 6761 para documentação e teste. Copiado deliberadamente
 * do `1437-synthetic-member-never-reachable.test.mjs`: é a MESMA regra, e ter duas definições que
 * divergem seria pior do que ter uma repetida.
 */
export const RESERVED_DOMAIN = /@(?:[^@]*\.)?(?:example\.(?:com|org|net)|test|invalid|localhost)$/i;

/** Prefixo do nome. Serve para o humano que topar com a linha num painel entender o que é. */
export const SYNTHETIC_NAME_PREFIX = '__1636_synthetic__';

/** Uma fixture viva por mais que isto é sobrevivente, não trabalho em curso. Mesmo valor do #1437. */
export const GRACE_MINUTES = 30;

/** `true` se a linha é dado de teste por construção (o e-mail não alcança pessoa nenhuma). */
export const isSynthetic = (row) =>
  !!row?.email && RESERVED_DOMAIN.test(row.email);

/**
 * Lista os ciclos de um STATUS, mais recente primeiro. Nunca por `cycle_code` fixo: o código do
 * ciclo anda (`cycle3-2026` → `cycle4-2026`) e um id cravado transforma este helper numa
 * bomba-relógio silenciosa.
 *
 * Ciclo fechado é operacionalmente inerte (nenhum dos três crons de seleção age nele), que é a
 * razão de os testes do arco preferirem ciclo fechado.
 */
export async function listCycleIds(sb, status) {
  const { data, error } = await sb
    .from('selection_cycles')
    .select('id, cycle_code, status')
    .eq('status', status)
    .order('created_at', { ascending: false });
  assert.ifError(error);
  assert.ok(
    data?.length,
    `#1636: nenhum ciclo com status='${status}' — a fixture não tem onde nascer`,
  );
  return data;
}

async function insertSyntheticMember(sb, tag, n) {
  const email = `fixture-1636-eval-${n}-${tag}@example.com`;
  const { data, error } = await sb
    .from('members')
    .insert({
      name: `${SYNTHETIC_NAME_PREFIX} evaluator ${n} ${tag}`,
      email,
      // #1437: `admin_send_campaign` seleciona em `is_active AND current_cycle_active`. Nascer
      // inativo faz a fixture satisfazer aquele guard POR CONSTRUÇÃO, e não por limpeza pontual.
      is_active: false,
      current_cycle_active: false,
    })
    .select('id, email')
    .single();
  assert.ifError(error);
  return data;
}

/**
 * Cria uma candidatura sintética com a FORMA que o gate exige, e devolve um handle com `cleanup()`.
 *
 * Os gates vivos do core (medidos em 08/08/2026, pós-#1640) são dois, e ambos leem só colunas e
 * contagens da própria candidatura — por isso a forma é inteiramente construtível:
 *
 *   P0002 GATE_NO_PEER_REVIEW  ← `count(selection_evaluations) < 2`
 *   P0003 GATE_NO_SCORE        ← `objective_score_avg IS NULL`
 *
 * ...e o MODO é decidido antes deles: existir linha em `selection_interviews` faz o modo virar
 * `reuse_prior`, que pula os dois. `evaluations: 2` precisa de dois avaliadores DISTINTOS —
 * `selection_evaluations` tem UNIQUE (application_id, evaluator_id, evaluation_type).
 *
 * @param {object} sb cliente supabase-js com service role
 * @param {object} opts
 * @param {'open'|'closed'} opts.cycleStatus  ciclo onde a fixture nasce
 * @param {string}  [opts.status]             `selection_applications.status`
 * @param {number}  [opts.evaluations]        quantas avaliações objetivas criar (0 → P0002)
 * @param {number|null} [opts.objectiveScore] `objective_score_avg` (null → P0003)
 * @param {boolean} [opts.withInterview]      cria linha de entrevista (→ modo `reuse_prior`)
 * @param {string}  [opts.interviewStatus]    status da linha de entrevista
 * @param {boolean} [opts.consentAi]          carimba `consent_ai_analysis_at`
 * @param {boolean} [opts.aiAnalysis]         preenche `ai_analysis`
 * @param {number}  [opts.rescueCount]        `interview_auto_rescue_count`
 * @param {string|null} [opts.cutoffEmailSentAt] `cutoff_approved_email_sent_at`
 * @param {boolean} [opts.requireBookingUrl]  exige que o ciclo resolva URL de agendamento
 * @param {string}  [opts.label]              rótulo humano, entra no nome
 */
export async function createSyntheticApplication(sb, opts = {}) {
  const {
    cycleStatus = 'closed',
    status = 'submitted',
    evaluations = 0,
    objectiveScore = null,
    withInterview = false,
    interviewStatus = 'pending',
    consentAi = false,
    aiAnalysis = false,
    rescueCount = 0,
    cutoffEmailSentAt = null,
    requireBookingUrl = false,
    label = 'fixture',
  } = opts;

  // Sufixo único por fixture. Runs de CI compartilham o banco de produção (#1505/#1261), então
  // duas corridas simultâneas TÊM de conseguir criar a sua sem colidir — e o e-mail único também
  // é o que mantém `_trg_auto_link_dual_track` e `_trg_link_renewal_application` inertes: os dois
  // casam por `lower(email)` contra linhas reais, e nenhum e-mail real vive em `@example.com`.
  const tag = randomUUID().slice(0, 8);
  const cycles = await listCycleIds(sb, cycleStatus);
  const memberIds = [];

  const email = `fixture-1636-${label}-${tag}@example.com`;
  const { data: app, error } = await sb
    .from('selection_applications')
    .insert({
      cycle_id: cycles[0].id,
      applicant_name: `${SYNTHETIC_NAME_PREFIX} ${label} ${tag}`,
      email,
      status,
      // `objective_score_avg` NÃO entra aqui — ver o UPDATE no fim. Inserir a nota agora e criar
      // avaliações depois faz o `trg_recompute_app_pert` recalcular a coluna a partir das
      // avaliações e devolvê-la a NULL (elas não têm `submitted_at` nem `weighted_subtotal`),
      // e o gate então recusa por P0003 quando o teste pediu passagem. Medido em 08/08/2026.
      consent_ai_analysis_at: consentAi ? new Date().toISOString() : null,
      ai_analysis: aiAnalysis ? { synthetic: true, issue: 1636 } : null,
      interview_auto_rescue_count: rescueCount,
      cutoff_approved_email_sent_at: cutoffEmailSentAt,
    })
    .select('*')
    .single();
  assert.ifError(error);
  assert.ok(app?.id, '#1636: a fixture não foi criada');

  /** Apaga tudo o que a fixture gerou. Levanta se sobrar qualquer coisa. */
  async function cleanup() {
    // 1. sem FK nenhuma (vínculo polimórfico) — é o que sobreviveu calado em 07/08.
    const t = await sb.from('onboarding_tokens').delete().eq('source_id', app.id);
    assert.ifError(t.error);
    // 2. FK `NO ACTION`: se ficar, o DELETE lá embaixo falha (e é bom que falhe alto).
    const d = await sb.from('selection_dispatch_url_log').delete().eq('application_id', app.id);
    assert.ifError(d.error);
    const p = await sb.from('onboarding_progress').delete().eq('application_id', app.id);
    assert.ifError(p.error);
    // 3. auditoria sobre uma candidatura que nunca existiu não é auditoria, é ruído.
    const l = await sb.from('admin_audit_log').delete().eq('target_id', app.id);
    assert.ifError(l.error);
    // 4. o CASCADE leva gate_attempts, selection_interviews e selection_evaluations junto.
    const a = await sb.from('selection_applications').delete().eq('id', app.id);
    assert.ifError(a.error);
    for (const id of memberIds) {
      const m = await sb.from('members').delete().eq('id', id);
      assert.ifError(m.error);
    }

    // Confirmar o EFEITO, não a ausência de erro: um DELETE que não casa linha nenhuma volta
    // `error: null` e o `.delete()` do PostgREST não distingue "apagou" de "não achou".
    const { count, error: e } = await sb
      .from('selection_applications')
      .select('id', { count: 'exact', head: true })
      .eq('id', app.id);
    assert.ifError(e);
    assert.equal(count, 0, `#1636: a fixture ${app.id} sobreviveu à própria limpeza`);
  }

  let cycleId = cycles[0].id;

  try {
    // O ciclo tem de RESOLVER URL de agendamento quando o teste for exercer o despacho: sem URL,
    // `notify_selection_cutoff_approved` sai por P0020 e a asserção sobre a RECUSA DE GATE (P0002)
    // nunca é exercida — o teste ficaria verde afirmando outra coisa.
    //
    // A resolução é decidida pelo CICLO (comitê da trilha `researcher`, com fallback para
    // `selection_cycles.interview_booking_url`), não pela candidatura. Medido em 08/08/2026: dos 3
    // ciclos fechados, o mais recente (`cycle2-2025`) não resolve nada — pegar "o último fechado"
    // daria P0020. Em vez de reimplementar a regra aqui (duas cópias divergem), o helper PERGUNTA
    // ao SSOT: move a fixture de ciclo e sonda `resolve_interview_booking_url` até resolver.
    if (requireBookingUrl) {
      let resolved = null;
      for (const c of cycles) {
        if (c.id !== cycleId) {
          const { error: mvErr } = await sb
            .from('selection_applications')
            .update({ cycle_id: c.id })
            .eq('id', app.id);
          assert.ifError(mvErr);
          cycleId = c.id;
        }
        const { data: res, error: rErr } = await sb.rpc('resolve_interview_booking_url', {
          p_application_id: app.id,
        });
        assert.ifError(rErr);
        const row = Array.isArray(res) ? res[0] : res;
        if (row?.url) { resolved = row.url; break; }
      }
      assert.ok(
        resolved,
        `#1636: nenhum ciclo '${cycleStatus}' resolve URL de agendamento — a fixture sairia por ` +
          'P0020 e a asserção sobre recusa de gate não seria exercida',
      );
    }

    for (let i = 0; i < evaluations; i += 1) {
      const m = await insertSyntheticMember(sb, tag, i);
      memberIds.push(m.id);
      const { error: eErr } = await sb.from('selection_evaluations').insert({
        application_id: app.id,
        evaluator_id: m.id,
        evaluation_type: 'objective',
        scores: { synthetic: true },
      });
      assert.ifError(eErr);
    }

    if (withInterview) {
      const { error: iErr } = await sb.from('selection_interviews').insert({
        application_id: app.id,
        interviewer_ids: [],
        status: interviewStatus,
      });
      assert.ifError(iErr);
    }
  } catch (err) {
    // Fixture pela metade é pior do que fixture nenhuma: ela ainda é uma linha em prod, e o teste
    // que a usar vai afirmar sobre uma forma que não é a pedida.
    await cleanup().catch(() => {});
    throw err;
  }

  // A nota vai POR ÚLTIMO, depois de as avaliações existirem. O gate lê a COLUNA
  // (`objective_score_avg IS NULL` → P0003); como ela chegou lá é assunto do pipeline de
  // pontuação, e amarrar a fixture àquele pipeline faria o teste do GATE ficar vermelho a cada
  // mudança na fórmula de score — que é outro assunto.
  if (objectiveScore !== null && objectiveScore !== undefined) {
    const { error: sErr } = await sb
      .from('selection_applications')
      .update({ objective_score_avg: objectiveScore })
      .eq('id', app.id);
    assert.ifError(sErr);
  }

  // Reler a linha VIVA: o `requireBookingUrl` pode ter movido o ciclo, e os triggers de INSERT
  // (`_trg_link_renewal_application`, `_trg_auto_link_dual_track`) podem ter escrito colunas que o
  // payload não mandou. Devolver o retorno do INSERT faria o teste afirmar sobre um retrato velho.
  const { data: fresh, error: fErr } = await sb
    .from('selection_applications')
    .select('*')
    .eq('id', app.id)
    .single();
  assert.ifError(fErr);

  return { id: app.id, email, cycleId, application: fresh, memberIds, cleanup };
}
