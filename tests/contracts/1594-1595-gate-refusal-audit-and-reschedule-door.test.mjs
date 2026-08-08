// tests/contracts/1594-1595-gate-refusal-audit-and-reschedule-door.test.mjs
//
// #1594 — a auditoria de RECUSA de gate era decorativa.
// #1595 — a porta do REAGENDAMENTO ainda entregava o link cru.
//
// Os dois caem sobre o mesmo core (`_issue_interview_booking_token_core`) escrito no #1584.
//
// O achado do #1594: `gate_attempts` tinha 31 linhas, TODAS `gate_passed = true`. Zero recusas em
// toda a vida da tabela — não por falta de código, mas porque o `INSERT` do log e o `RAISE
// EXCEPTION` que o seguia rodavam na MESMA transação. A linha morria com a exceção que ela deveria
// explicar. É a família da defesa decorativa: o mecanismo existe, o consumidor existe, o dado nunca
// chega.
//
// O achado do #1595: três RPCs vivas e um componente de front entregavam
// `https://calendar.app.google/...` direto — fora do gate por candidato, fora do rodízio do LRD e
// fora de `selection_dispatch_url_log`.
//
// Camada A (estática, sempre roda): migration + front + MCP + i18n + spec.
// Camada B (DB-aware, PULA sem SUPABASE_URL + SERVICE_ROLE_KEY): corpo vivo, ACL e COMPORTAMENTO.
//   ⚠️ um SKIP silencioso lê como verde. Conferir o número de skips, não só `fail 0`.
//
// ⚠️ RESÍDUO DECLARADO da camada B: provar que uma linha de auditoria "sobrevive ao rollback" exige,
// por definição, COMMITAR. Este arquivo grava algumas linhas em `gate_attempts` — que são registros
// VERDADEIROS (uma tentativa de emissão realmente foi feita) — e emite um token de reagendamento que
// é apagado no `finally`. Nenhum e-mail sai: é exatamente o que a metade (a) afirma.
//
// ⚠️ ORDEM IMPORTA na camada B. O teste que chama `notify_selection_cutoff_approved` só roda depois
// de o teste anterior ter PROVADO, para a MESMA candidatura, que o core recusa. Sem essa trava, uma
// regressão no gate faria o próprio teste disparar e-mail para um candidato real.

import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const MIGRATION_PATH = 'supabase/migrations/20260805000509_1594_1595_recusa_auditada_e_porta_reagendamento.sql';
const SPEC_PATH = 'docs/specs/SPEC_INTERVIEW_BOOKING_INTEGRITY.md';
const ADMIN_PATH = 'src/pages/admin/selection.astro';
const MCP_PATH = 'supabase/functions/nucleo-mcp/index.ts';
const PORTAL_PATH = 'src/components/pmi-onboarding/PMIOnboardingPortal.tsx';
const DICTS = ['src/i18n/pt-BR.ts', 'src/i18n/en-US.ts', 'src/i18n/es-LATAM.ts'];

const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');

/**
 * Remove comentários de linha SQL. Guard de AUSÊNCIA tem de olhar só o código: os comentários desta
 * migration citam nominalmente o literal do Google que ela remove, e uma asserção sobre o texto cru
 * transformaria a própria documentação do defeito em falha.
 */
const stripSqlComments = (sql) => sql.replace(/^\s*--.*$/gm, '');

const MIGRATION_SQL = read(MIGRATION_PATH);
const MIGRATION_CODE = stripSqlComments(MIGRATION_SQL);
const ADMIN_SRC = read(ADMIN_PATH);
const MCP_SRC = read(MCP_PATH);
const PORTAL_SRC = read(PORTAL_PATH);
const SPEC_SRC = read(SPEC_PATH);

/** Extrai o bloco `CREATE OR REPLACE FUNCTION public.<name> ... $function$ ... $function$`. */
function fnBlock(sql, name) {
  const re = new RegExp(
    `CREATE OR REPLACE FUNCTION public\\.${name}\\s*\\([\\s\\S]*?\\n\\$function\\$;`,
  );
  return sql.match(re)?.[0] || '';
}

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK
  ? createClient(SUPABASE_URL, SUPABASE_SRK, { auth: { persistSession: false } })
  : null;

// ─────────────────────────────────────────────────────────────────────────────
// Camada A — estática
// ─────────────────────────────────────────────────────────────────────────────
describe('#1594/#1595 A — camada estática (migration, front, MCP, i18n, spec)', () => {
  it('a migration existe no timestamp canônico', () => {
    assert.ok(existsSync(MIGRATION_PATH), `migration esperada em ${MIGRATION_PATH}`);
    assert.ok(MIGRATION_SQL.length > 0, 'migration não pode estar vazia');
  });

  it('#1594 — no core, cada recusa RETORNA; nenhuma delas levanta', () => {
    const core = fnBlock(MIGRATION_CODE, '_issue_interview_booking_token_core');
    assert.ok(core, 'bloco do core não encontrado');
    for (const code of ['P0001', 'P0002', 'P0003']) {
      assert.match(
        core,
        new RegExp(`'gate_failed_code', '${code}'`),
        `${code} tem de virar retorno estruturado`,
      );
    }
    // Invariante UNIVERSAL: nenhum RAISE dentro do bloco dos gates. `assert.doesNotMatch` afirma
    // ausência; `assert.match` se satisfaria com uma ocorrência qualquer e não serve aqui.
    const gateBlock = core.match(/IF v_gate_mode = 'full' THEN[\s\S]*?\n  END IF;/)?.[0] || '';
    assert.ok(gateBlock, 'bloco `IF v_gate_mode = \'full\'` não encontrado');
    assert.doesNotMatch(
      gateBlock,
      /RAISE EXCEPTION/,
      'um RAISE aqui desfaz o INSERT de _log_gate_attempt — é o defeito inteiro da #1594',
    );
    // ...e cada recusa continua ANTES do RETURN, isto é, o log é chamado nas três.
    assert.equal(
      (gateBlock.match(/_log_gate_attempt/g) || []).length,
      3,
      'as três recusas do core têm de registrar a tentativa',
    );
  });

  it('#1594 — em schedule_interview, as QUATRO recusas retornam em vez de levantar', () => {
    const fn = fnBlock(MIGRATION_CODE, 'schedule_interview');
    assert.ok(fn, 'bloco de schedule_interview não encontrado');
    for (const code of ['P0001', 'P0002', 'P0003', 'P0004']) {
      assert.match(fn, new RegExp(`'gate_failed_code', '${code}'`), `${code} tem de retornar`);
    }
    // Cada `_log_gate_attempt` com gate_passed=false não pode ser seguido de RAISE.
    const refusals = fn.split(/PERFORM public\._log_gate_attempt\(/).slice(1);
    for (const chunk of refusals) {
      const upToNextStatement = chunk.split(/\n    END IF;|\n  END IF;/)[0];
      if (!/false,\s*\n\s*'P000/.test(upToNextStatement)) continue;
      assert.doesNotMatch(
        upToNextStatement,
        /RAISE EXCEPTION/,
        'recusa de schedule_interview ainda levanta — a linha de auditoria morre no rollback',
      );
    }
    // p472 corr.3: os 3 gates continuam DENTRO do IF NOT v_can_bypass, e a allow-list P0004 fica.
    assert.match(fn, /IF NOT v_can_bypass THEN[\s\S]*'P0001'[\s\S]*'P0002'[\s\S]*'P0003'[\s\S]*END IF;/);
    assert.match(
      fn,
      /v_can_bypass AND v_app\.status IN \('screening', 'submitted', 'objective_eval', 'objective_cutoff'\)/,
      'allow-list P0004 do #472 corr.3 preservada',
    );
  });

  it('#1594 — o despacho aborta o e-mail por RETORNO, e o RETURN vem antes do envio', () => {
    const fn = fnBlock(MIGRATION_CODE, 'notify_selection_cutoff_approved');
    assert.ok(fn, 'bloco de notify_selection_cutoff_approved não encontrado');
    assert.match(fn, /'reason', 'gate_refused'/, 'a recusa tem de ter envelope próprio');
    const refuseIdx = fn.search(/'reason', 'gate_refused'/);
    const sendIdx = fn.search(/campaign_send_one_off/);
    const stampIdx = fn.search(/SET cutoff_approved_email_sent_at = now\(\)/);
    assert.ok(refuseIdx > 0 && sendIdx > refuseIdx, 'o abort tem de vir ANTES do envio');
    assert.ok(stampIdx > refuseIdx, 'o abort tem de vir ANTES do carimbo de idempotência');
    // #1450 preservado (o teste daquele arco também afirma isto).
    assert.match(fn, /objective_score_avg IS NULL/);
    assert.match(fn, /GATE_NO_SCORE/);
  });

  it('#1594 — o cron conta recusa separado de despacho', () => {
    const fn = fnBlock(MIGRATION_CODE, '_selection_cutoff_pending_cron');
    assert.ok(fn, 'bloco do cron não encontrado');
    assert.match(fn, /v_refused/, 'sem contador próprio a recusa entraria como despacho');
    assert.match(fn, /'refused_count', v_refused/);
    assert.doesNotMatch(
      fn,
      /PERFORM public\.notify_selection_cutoff_approved/,
      'PERFORM cego voltaria a contar recusa como e-mail enviado',
    );
  });

  it('#1595 — o core ganha o modo reuse_prior com motivo próprio e nível de prova', () => {
    const core = fnBlock(MIGRATION_CODE, '_issue_interview_booking_token_core');
    assert.match(core, /'reuse_prior'/);
    assert.match(core, /'gate_reuse_reason', 'GATE_REUSED_PRIOR'/, 'pular calado é o que a decisão proíbe');
    for (const tier of ['dispatch_log', 'prior_token', 'interview_row_only']) {
      assert.match(core, new RegExp(`'${tier}'`), `nível de prova ${tier} tem de ser registrado`);
    }
    // O gatilho é a existência de entrevista; o bypass explícito continua acima dele.
    assert.match(core, /WHEN p_bypass_granted THEN 'bypass'[\s\S]*WHEN v_has_interview\s+THEN 'reuse_prior'/);
  });

  it('#1595 — existe UMA fonte de despacho, e as internas novas revogam de anon/authenticated', () => {
    assert.match(MIGRATION_CODE, /CREATE OR REPLACE FUNCTION public\._dispatch_interview_booking_link/);
    for (const fn of ['_dispatch_interview_booking_link', '_issue_interview_booking_token_core']) {
      assert.match(
        MIGRATION_CODE,
        new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn}\\([^)]*\\) FROM PUBLIC, anon, authenticated`),
        `${fn}: o default-privileges do Supabase concede a anon/authenticated — revogar só de ` +
          `PUBLIC não remove nada`,
      );
    }
    // Os quatro caminhos de despacho passam pelo helper (é o que impede a quinta porta paralela).
    for (const caller of [
      'notify_selection_cutoff_approved',
      'mark_interview_status',
      'request_interview_reschedule',
      'process_pending_reschedule_nudges',
      'request_interview_booking_link_via_token',
    ]) {
      const fn = fnBlock(MIGRATION_CODE, caller);
      assert.ok(fn, `bloco de ${caller} não encontrado`);
      assert.match(
        fn,
        /public\._dispatch_interview_booking_link\(/,
        `${caller} tem de despachar pela fonte única`,
      );
    }
  });

  it('#1595 — o literal do Google sumiu do CÓDIGO da migration e do portal do candidato', () => {
    assert.doesNotMatch(
      MIGRATION_CODE,
      /calendar\.app\.google/,
      'o literal ignorava o gate, o LRD e o log de despacho',
    );
    assert.ok(existsSync(PORTAL_PATH), `componente esperado em ${PORTAL_PATH}`);
    assert.doesNotMatch(PORTAL_SRC, /calendar\.app\.google/);
    assert.match(
      PORTAL_SRC,
      /request_interview_booking_link_via_token/,
      'o portal tem de pedir o link governado',
    );
    // A emissão é ato explícito do candidato, não efeito de renderizar (cada chamada despacha).
    assert.doesNotMatch(
      PORTAL_SRC,
      /useEffect\([^)]*requestBookingLink/,
      'emitir no mount faria toda visita gravar despacho e girar o LRD',
    );
  });

  it('#1594 — os consumidores tratam success:false (senão recusa lê como sucesso)', () => {
    // admin: cada RPC de gate tem de checar o envelope, não só `error`.
    const adminChecks = (ADMIN_SRC.match(/data\?\.success === false/g) || []).length;
    assert.ok(
      adminChecks >= 5,
      `admin/selection.astro deveria checar success:false em todas as chamadas gateadas (achou ${adminChecks})`,
    );
    // MCP: tool cru + envelope semântico + o despacho de cutoff.
    const mcpChecks = (MCP_SRC.match(/\(data as any\)\?\.success === false/g) || []).length;
    assert.ok(
      mcpChecks >= 4,
      `nucleo-mcp deveria transformar success:false em erro (achou ${mcpChecks})`,
    );
  });

  it('as chaves novas do portal existem nos TRÊS dicionários', () => {
    for (const dict of DICTS) {
      assert.ok(existsSync(dict), `dicionário ausente: ${dict}`);
      const src = readFileSync(dict, 'utf8');
      for (const key of [
        'pmi.onboarding.interviewScheduleLoading',
        'pmi.onboarding.interviewScheduleOpenLink',
        'pmi.onboarding.interviewScheduleUnavailable',
      ]) {
        assert.ok(src.includes(`'${key}'`), `${dict} não tem a chave ${key}`);
      }
    }
  });

  it('a spec §4.0 deixou de afirmar o que não existe', () => {
    assert.ok(SPEC_SRC.length > 0, 'spec não encontrada');
    assert.match(
      SPEC_SRC,
      /CORREÇÃO \(#1594/,
      'a spec afirmava "toda tentativa, sucesso ou falha, é registrada" — foi a premissa errada que ' +
        'se propagou para o corpo da #1584 e precisa estar corrigida no MESMO PR',
    );
    assert.doesNotMatch(
      SPEC_SRC,
      /e \*\*toda\*\* tentativa, sucesso ou falha, é registrada/,
      'a afirmação falsa original não pode sobreviver',
    );
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Camada B — DB-aware (corpo vivo, ACL, comportamento)
// ─────────────────────────────────────────────────────────────────────────────
describe('#1594/#1595 B — camada DB-aware', { skip: !sb ? 'sem SUPABASE_URL + SERVICE_ROLE_KEY' : false }, () => {
  // Candidatura de recusa: ciclo FECHADO e já decidida (operacionalmente inerte), sem entrevista
  // (modo full), e sem convite já despachado.
  //
  // ⚠️ #1640 — o predicado MUDOU. Ele ancorava na ausência de consentimento de IA, que recusava por
  // P0001. Esse gate saiu (a ausência de consentimento de terceira finalidade não pode negar efeito
  // ao processo seletivo), e manter o predicado antigo faria este teste EMITIR um token real para um
  // candidato real em vez de observar uma recusa. A âncora agora é o peer-review incompleto (P0002),
  // que continua sendo requisito de conclusão do processo objetivo.
  let refuseApp = null;
  let refuseProven = false;   // trava do teste que chama o despacho de verdade
  const mintedTokens = [];

  before(async () => {
    const { data, error } = await sb
      .from('selection_applications')
      .select('id, email, objective_score_avg, cycle_id, selection_cycles!inner(cycle_code, status)')
      .eq('selection_cycles.status', 'closed')
      .is('cutoff_approved_email_sent_at', null)
      .not('email', 'is', null)
      .limit(120);
    assert.ifError(error);

    for (const app of data ?? []) {
      const { count } = await sb
        .from('selection_interviews')
        .select('id', { count: 'exact', head: true })
        .eq('application_id', app.id);
      if ((count ?? 0) > 0) continue;                       // precisa ser modo `full`
      const { count: evals } = await sb
        .from('selection_evaluations')
        .select('id', { count: 'exact', head: true })
        .eq('application_id', app.id);
      if ((evals ?? 0) >= 2) continue;                      // senão o core PASSA e emite token real
      const { data: res } = await sb.rpc('resolve_interview_booking_url', { p_application_id: app.id });
      const row = Array.isArray(res) ? res[0] : res;
      if (!row?.url) continue;                              // senão o caminho é P0020, não recusa
      refuseApp = app;
      break;
    }
  });

  after(async () => {
    // O token de reagendamento é o único resíduo removível; a linha de gate_attempts é registro
    // verdadeiro de uma tentativa que de fato aconteceu, e fica.
    for (const t of mintedTokens) {
      await sb.from('onboarding_tokens').delete().eq('token', t);
    }
  });

  it('GUARD DE CLASSE — nenhuma função viva de public carrega o link cru do Google', async () => {
    // Por CLASSE, não por nome. Um guard que enumera as três funções conhecidas não impede a
    // quarta de nascer — e o defeito da #1595 é exatamente uma quarta porta que nasceu sozinha.
    const { data, error } = await sb.rpc('_audit_functions_matching', {
      p_pattern: 'calendar\\.app\\.google',
    });
    assert.ifError(error);
    const offenders = (data ?? []).map((r) => `${r.proname}(${r.identity_args})`);
    assert.deepEqual(offenders, [], `RPCs vivas ainda entregam o link cru: ${offenders.join(', ')}`);
  });

  it('o helper de classe está fechado para anon e authenticated', async () => {
    const { data, error } = await sb.rpc('_audit_function_execute_acl', {
      p_names: ['_audit_functions_matching'],
    });
    assert.ifError(error);
    assert.equal(data.length, 1, '_audit_functions_matching precisa existir');
    assert.equal(data[0].anon_exec, false);
    assert.equal(data[0].authenticated_exec, false);
  });

  it('as funções internas de despacho não são alcançáveis por anon nem authenticated', async () => {
    const { data, error } = await sb.rpc('_audit_function_execute_acl', {
      p_names: ['_dispatch_interview_booking_link', '_issue_interview_booking_token_core'],
    });
    assert.ifError(error);
    assert.ok(data.length >= 2, 'ambas as funções precisam existir no banco');
    for (const row of data) {
      assert.equal(row.anon_exec, false, `${row.proname} não pode ser executável por anon`);
      assert.equal(row.authenticated_exec, false, `${row.proname} não pode ser executável por authenticated`);
    }
  });

  it('#1594 metade (b) — a recusa PRODUZ linha em gate_attempts que sobrevive', async () => {
    if (!refuseApp) {
      // Dizer alto: sem candidatura que recuse, a asserção não foi exercida (skip lê como verde).
      console.log('[1594] nenhuma candidatura de ciclo fechado recusa em modo full — asserção não exercida');
      return;
    }

    const { count: before, error: e0 } = await sb
      .from('gate_attempts')
      .select('id', { count: 'exact', head: true })
      .eq('application_id', refuseApp.id)
      .eq('gate_passed', false);
    assert.ifError(e0);

    const { data, error } = await sb.rpc('_issue_interview_booking_token_core', {
      p_application_id: refuseApp.id,
      p_bypass_granted: false,
      p_caller_id: null,
      p_bypass_requested: false,
    });
    // A recusa NÃO pode chegar como exceção: é isso que desfazia o INSERT.
    assert.ifError(error);
    assert.equal(data?.success, false, 'o core tinha de recusar esta candidatura');
    assert.equal(data?.gate_failed_code, 'P0002');   // #1640: era P0001; a âncora agora é peer-review
    assert.equal(data?.gate_mode, 'full');

    const { data: rows, count: after, error: e1 } = await sb
      .from('gate_attempts')
      .select('gate_failed_code, gate_failed_reason, payload', { count: 'exact' })
      .eq('application_id', refuseApp.id)
      .eq('gate_passed', false)
      .order('attempted_at', { ascending: false })
      .limit(1);
    assert.ifError(e1);
    assert.equal(
      after,
      (before ?? 0) + 1,
      'a linha de recusa não sobreviveu — é exatamente o defeito que a #1594 descreve',
    );
    assert.equal(rows[0].gate_failed_code, 'P0002');
    assert.equal(rows[0].gate_failed_reason, 'GATE_NO_PEER_REVIEW');
    assert.equal(rows[0].payload?.gate_mode, 'full');

    refuseProven = true;
  });

  it('#1594 metade (a) — na recusa, NENHUM e-mail sai pelo despacho de cutoff', async () => {
    if (!refuseApp || !refuseProven) {
      // Trava deliberada: sem a prova de que o core recusa ESTA candidatura, chamar o despacho
      // arriscaria mandar convite real para um candidato real.
      console.log('[1594] metade (a) não exercida: a recusa do core não foi provada nesta corrida');
      return;
    }

    const dispatchedRows = async () => {
      const { count, error } = await sb
        .from('admin_audit_log')
        .select('id', { count: 'exact', head: true })
        .eq('action', 'selection.cutoff_approved_email_dispatched')
        .eq('target_id', refuseApp.id);
      assert.ifError(error);
      return count ?? 0;
    };
    const before = await dispatchedRows();

    const { data, error } = await sb.rpc('notify_selection_cutoff_approved', {
      p_application_id: refuseApp.id,
    });
    assert.ifError(error);
    assert.equal(data?.success, false, 'o despacho tinha de abortar');
    assert.equal(data?.email_sent, false);
    assert.equal(data?.reason, 'gate_refused');
    assert.equal(data?.gate_failed_code, 'P0002');   // #1640: era P0001

    assert.equal(await dispatchedRows(), before, 'saiu e-mail numa recusa de gate');

    // Prova escopada na candidatura: notify só carimba depois de enviar.
    const { data: app, error: e2 } = await sb
      .from('selection_applications')
      .select('cutoff_approved_email_sent_at')
      .eq('id', refuseApp.id)
      .single();
    assert.ifError(e2);
    assert.equal(app.cutoff_approved_email_sent_at, null, 'a idempotência foi carimbada sem envio');

    // E a recusa deixou rastro: o despacho recusado também registra tentativa.
    const { count: refusals, error: e3 } = await sb
      .from('gate_attempts')
      .select('id', { count: 'exact', head: true })
      .eq('application_id', refuseApp.id)
      .eq('gate_passed', false);
    assert.ifError(e3);
    assert.ok(refusals >= 2, 'a segunda tentativa (via despacho) também tem de estar registrada');
  });

  it('#1595 — quem já tem entrevista entra em reuse_prior e NÃO reavalia os 3 gates', async () => {
    // A porta do reagendamento existe para quem já foi convocado uma vez. Medido em 2026-08-05: os
    // candidatos nessa situação FALHAM P0002/P0003 hoje, então reaplicar os gates barraria
    // exatamente a população que a porta serve.
    const { data: interviews, error: e0 } = await sb
      .from('selection_interviews')
      .select('application_id')
      .limit(200);
    assert.ifError(e0);

    let target = null;
    for (const iv of interviews ?? []) {
      const { count: evals } = await sb
        .from('selection_evaluations')
        .select('id', { count: 'exact', head: true })
        .eq('application_id', iv.application_id);
      const { data: app } = await sb
        .from('selection_applications')
        .select('id, objective_score_avg, consent_ai_analysis_at')
        .eq('id', iv.application_id)
        .single();
      if (!app) continue;
      // Só serve quem FALHARIA no modo full — senão o teste não distingue reuse de aprovação.
      const wouldFailFull =
        app.consent_ai_analysis_at === null || (evals ?? 0) < 2 || app.objective_score_avg === null;
      if (wouldFailFull) { target = app; break; }
    }

    if (!target) {
      console.log('[1595] nenhum candidato com entrevista falharia no modo full — asserção não exercida');
      return;
    }

    const { data, error } = await sb.rpc('_issue_interview_booking_token_core', {
      p_application_id: target.id,
      p_bypass_granted: false,
      p_caller_id: null,
      p_bypass_requested: false,
    });
    assert.ifError(error);
    if (data?.token) mintedTokens.push(data.token);

    assert.equal(data?.success, true, 'reagendamento barrado — a porta existe justamente para este caso');
    assert.equal(data?.gate_mode, 'reuse_prior');
    assert.equal(data?.gate_bypassed, false, 'reuse não é bypass: não exige manage_member');
    // O nível de prova é registrado, mas NÃO é fixo: uma corrida anterior pode ter subido o tier
    // de `interview_row_only` para `prior_token`. Afirmar o valor exato seria afirmar o histórico.
    assert.ok(
      ['dispatch_log', 'prior_token', 'interview_row_only'].includes(data?.prior_evidence),
      `nível de prova inesperado: ${data?.prior_evidence}`,
    );

    // ...e o skip ficou AUDITADO, que é a condição inegociável da decisão.
    const { data: rows, error: e1 } = await sb
      .from('gate_attempts')
      .select('gate_passed, payload')
      .eq('application_id', target.id)
      .order('attempted_at', { ascending: false })
      .limit(1);
    assert.ifError(e1);
    assert.equal(rows[0].gate_passed, true);
    assert.equal(rows[0].payload?.gate_mode, 'reuse_prior');
    assert.equal(
      rows[0].payload?.gate_reuse_reason,
      'GATE_REUSED_PRIOR',
      'pular calado devolve o reagendamento à condição de caminho não auditado',
    );
  });

  it('a leitura de auditoria expõe gate_mode (senão o skip é invisível na única tela que o leria)', async () => {
    const { data, error } = await sb.rpc('_audit_function_source', {
      p_proname: 'get_application_gate_attempts',
    });
    assert.ifError(error);
    assert.ok(data?.length > 0, 'get_application_gate_attempts não existe no banco');
    for (const r of data) {
      assert.match(r.prosrc, /gate_mode/, 'a superfície de leitura tem de distinguir reuse de full');
      assert.match(
        r.prosrc,
        /COALESCE\(ga\.payload->>'gate_mode', 'full'\)/,
        'tentativas anteriores ao #1595 não têm gate_mode — o default tem de ser o que elas foram',
      );
    }
  });
});
