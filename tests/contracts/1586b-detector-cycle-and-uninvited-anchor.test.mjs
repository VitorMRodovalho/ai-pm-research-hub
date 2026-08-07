/**
 * Contract: #1586(b) — o detector do funil seletivo estava cego por DUAS causas independentes,
 * e consertar uma só continuaria devolvendo zero.
 * Migration: supabase/migrations/20260807000100_1586b_detector_ve_o_ciclo_certo_e_o_elegivel_sem_convite.sql
 *
 * Causa 1 (ciclo errado): `active_cycle` resolvia por `ORDER BY created_at DESC LIMIT 1`. O
 * backfill de `cycle2-2025` em 13/07/2026 (dados de 2025, linha nova) virou "o mais recente" e o
 * detector passou a varrer um ciclo FECHADO de 8 candidaturas em vez do aberto com 81.
 *
 * Causa 2 (anchor): os dois buckets ancoram em `cutoff_approved_email_sent_at`, NULL exatamente
 * para quem nunca recebeu convite — a coorte que mais precisa do alerta é a única invisível.
 *
 * ⚠️ ESTE ARQUIVO AFIRMA A REGRA, NUNCA O INSTANTÂNEO. Um teste que gravasse "hoje são 2
 * candidaturas" morre no dia seguinte e ensina a equipe a atualizar o número em vez de ler o
 * defeito (foi exatamente o que o #1635 teve de desfazer em p246-229b). Aqui a coorte esperada é
 * RECALCULADA contra os dados vivos a cada execução e comparada com o que o detector reporta.
 *
 * Efeito colateral: nenhum. Todas as chamadas usam `p_dry_run := true`, que não insere
 * notificação. O detector é read-only nesse modo.
 */

import { describe, it, before } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG_PATH = 'supabase/migrations/20260807000100_1586b_detector_ve_o_ciclo_certo_e_o_elegivel_sem_convite.sql';
const MIG = existsSync(resolve(ROOT, MIG_PATH)) ? readFileSync(resolve(ROOT, MIG_PATH), 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = dbGated ? createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } }) : null;

const FN = 'detect_stuck_selection_funnel';

// ── Offline: a migration carrega a decisão ───────────────────────────────────
describe('#1586(b) — migration', () => {
  it('a migration existe no timestamp canônico', () => {
    assert.ok(MIG, `migration precisa existir em ${MIG_PATH}`);
  });

  it('redefine o detector e semeia a política de grace própria', () => {
    assert.match(MIG, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${FN}\\(`));
    assert.match(MIG, /INSERT INTO public\.sla_policies/);
    assert.match(MIG, /'eligible_uninvited_grace'/);
  });

  it('o limiar novo NÃO reusa o grace do candidato (10 dias é a família errada)', () => {
    // `interview_booking_grace` mede "já convidado, falta o candidato agendar" (bola do candidato).
    // O bucket novo mede "a organização não convidou" — família de `stuck_scheduled_grace` (48h).
    assert.match(MIG, /v_uninvited_grace\s*:=\s*interval '2 days'/);
  });
});

// ── Corpo VIVO: as duas causas, cada uma com seu guard ───────────────────────
describe('#1586(b) — corpo vivo do detector', () => {
  let src = '';

  before(async () => {
    if (!dbGated) return;
    const { data, error } = await sb.rpc('_audit_function_source', { p_proname: FN });
    assert.ifError(error);
    assert.ok(data?.length > 0, `${FN} não existe no banco`);
    src = data[0].prosrc;
    // Sem esta asserção, um `prosrc` vazio faria os `assert.doesNotMatch` abaixo passarem por
    // ausência — o guard acusaria sucesso justamente quando não leu nada.
    assert.ok(typeof src === 'string' && src.length > 200, 'corpo vivo do detector precisa ser legível');
  });

  it('causa 1: o ciclo é escolhido por STATUS, não por created_at', { skip: dbGated ? false : skipMsg }, () => {
    const cte = src.match(/WITH active_cycle AS \(([\s\S]*?)\)\s*,/);
    assert.ok(cte, 'a CTE active_cycle precisa existir para ser auditada');
    // Comentários mencionam `created_at` para EXPLICAR o bug: assertar sobre o texto cru faria o
    // guard acusar a própria documentação do conserto. Só SQL executável entra na verificação.
    const corpo = cte[1].replace(/--[^\n]*/g, '');

    assert.match(corpo, /status\s*=\s*'open'/, 'active_cycle precisa filtrar por status = open');
    // Guard de REGRESSÃO, o que de fato quebrou: `created_at` é data de escrita da linha, e um
    // backfill histórico a torna a mais nova. Nenhuma ordenação por ele pode voltar a esta CTE.
    assert.doesNotMatch(corpo, /created_at/i,
      'active_cycle não pode voltar a depender de created_at — foi o backfill de cycle2-2025 que sequestrou a seleção');
  });

  it('causa 2: existe bucket ancorado em elegibilidade, não no carimbo de convite', { skip: dbGated ? false : skipMsg }, () => {
    assert.match(src, /selection_candidate_eligible_uninvited/, 'bucket C precisa existir');
    assert.match(src, /cutoff_approved_email_sent_at IS NULL/,
      'o bucket novo precisa casar justamente quem NÃO tem carimbo');
    assert.match(src, /eligible_at\s*<\s*now\(\)\s*-\s*v_uninvited_grace/,
      'o relógio do bucket novo é a elegibilidade, não o convite');
  });

  it('o bucket novo entra na janela de idempotência (senão renotifica todo dia)', { skip: dbGated ? false : skipMsg }, () => {
    const janela = src.match(/AND n\.type IN \(([\s\S]*?)\)/);
    assert.ok(janela, 'a janela de idempotência precisa existir');
    assert.match(janela[1], /selection_candidate_eligible_uninvited/,
      'um type fora da janela de 7 dias é notificação diária repetida ao GP');
  });
});

// ── Runtime: a REGRA, recalculada contra os dados vivos ──────────────────────
describe('#1586(b) — o detector conta a coorte que a regra define', () => {
  let esperado = null;   // ids calculados independentemente do detector
  let reportado = null;  // o que o detector devolveu

  before(async () => {
    if (!dbGated) return;

    const { data: grace } = await sb
      .from('sla_policies').select('value_interval').eq('policy_key', 'eligible_uninvited_grace').maybeSingle();
    // Fallback idêntico ao da função, para o teste não divergir do corpo se a row sumir.
    const graceMs = (grace?.value_interval ?? '2 days').includes('day')
      ? parseInt(grace?.value_interval ?? '2', 10) * 86400000
      : 2 * 86400000;

    const { data: cycles } = await sb.from('selection_cycles').select('id').eq('status', 'open');
    const openIds = (cycles ?? []).map((c) => c.id);

    const { data: apps } = await sb
      .from('selection_applications')
      .select('id, objective_score_avg')
      .in('cycle_id', openIds.length ? openIds : ['00000000-0000-0000-0000-000000000000'])
      .eq('status', 'interview_pending')
      .is('cutoff_approved_email_sent_at', null)
      .is('interview_reschedule_requested_at', null)
      .not('objective_score_avg', 'is', null);

    const ids = [];
    for (const a of apps ?? []) {
      const { count: nInterviews } = await sb
        .from('selection_interviews').select('id', { count: 'exact', head: true }).eq('application_id', a.id);
      if ((nInterviews ?? 0) > 0) continue;

      const { count: nDispatch } = await sb
        .from('selection_dispatch_url_log').select('id', { count: 'exact', head: true }).eq('application_id', a.id);
      if ((nDispatch ?? 0) > 0) continue;

      const { data: evs } = await sb
        .from('selection_evaluations').select('created_at')
        .eq('application_id', a.id).order('created_at', { ascending: true }).limit(2);
      if ((evs?.length ?? 0) < 2) continue;

      const eligibleAt = new Date(evs[1].created_at).getTime();
      if (Date.now() - eligibleAt <= graceMs) continue;
      ids.push(a.id);
    }
    esperado = ids;

    const { data: run, error } = await sb.rpc(FN, { p_dry_run: true });
    assert.ifError(error);
    reportado = run;
  });

  it('o retorno expõe a contagem do bucket novo', { skip: dbGated ? false : skipMsg }, () => {
    assert.ok(
      Object.prototype.hasOwnProperty.call(reportado ?? {}, 'eligible_uninvited_apps'),
      'sem a chave no retorno, o cron roda e ninguém consegue ler o que ele achou',
    );
  });

  it('a contagem bate com a coorte recalculada agora (regra, não instantâneo)', { skip: dbGated ? false : skipMsg }, () => {
    assert.equal(
      reportado.eligible_uninvited_apps, esperado.length,
      `detector reportou ${reportado?.eligible_uninvited_apps}, a regra sobre os dados vivos dá ${esperado.length}`,
    );
    if (esperado.length === 0) {
      // Dizer alto: igualdade 0 === 0 passa sem exercer nada, e skip lê como verde.
      console.log('[1586b] nenhuma candidatura elegível-e-não-convidada agora — a asserção de contagem não foi exercida');
    }
  });

  it('o detector varre o ciclo ABERTO (mata a regressão do backfill)', { skip: dbGated ? false : skipMsg }, async () => {
    // Prova de que causa 1 não voltou, medida pelo EFEITO e não pelo texto: se a seleção
    // regredisse para `created_at DESC`, o detector olharia o ciclo fechado e a coorte do ciclo
    // aberto — recalculada acima — deixaria de ser contada.
    const { data: maisNovoPorCreatedAt } = await sb
      .from('selection_cycles').select('status').order('created_at', { ascending: false }).limit(1).maybeSingle();

    if (maisNovoPorCreatedAt?.status === 'open') {
      console.log('[1586b] o ciclo mais novo por created_at está aberto — este guard não distingue as duas leituras hoje');
      return;
    }
    // O ciclo mais novo por created_at é FECHADO: a leitura antiga daria zero necessariamente.
    // Então qualquer contagem > 0 só é possível pela leitura nova. E se a coorte esperada for 0,
    // o guard de texto do bloco anterior é quem segura a regressão.
    assert.equal(reportado.eligible_uninvited_apps, esperado.length);
  });
});
