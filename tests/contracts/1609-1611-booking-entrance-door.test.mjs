/**
 * Contract: #1609 + #1611 — a porta de ENTRADA do agendamento.
 *
 * #1611 — `match_booking_application` devolvia conjunto VAZIO nos três casos de
 * recusa (não existe candidatura / status fora da allow-list / ciclo fechado), e
 * o webhook gravava os três sob a MESMA ação `calendar_booking_unmatched`. Isso
 * pôs dois fatos operacionais opostos no mesmo balde: "a plataforma tem um
 * buraco" (acionável) e "a plataforma funcionou" (a recusa está correta por
 * desenho). A RPC passa a devolver SEMPRE uma linha, com o motivo.
 *
 * #1609 — não havia contador, backoff nem corte: cada retentativa do Apps Script
 * de origem gravava uma linha nova. Medido em 2026-08-05: 16.722 linhas de
 * auditoria para 11 reservas (~1.093 por evento; 5.693 no pior evento), contra
 * ~1,5 linhas por evento que casou. Agora a tentativa é contada em
 * `selection_booking_attempts` e só vira linha de log quando
 * `record_booking_attempt` autoriza.
 *
 * O teste comportamental abaixo é a MUTAÇÃO que prova a defesa: 12 tentativas do
 * mesmo par (evento, convidado) têm de produzir UMA linha de contador e no
 * máximo duas autorizações de auditoria — a primeira aparição e o corte.
 *
 * Cross-ref: issues #1609, #1611; migration 20260805000512;
 * SPEC_INTERVIEW_BOOKING_INTEGRITY R3.2/R4.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000512_1609_1611_porta_entrada_agendamento.sql');
const WEBHOOK = resolve(ROOT, 'src/pages/api/calendar-webhook.ts');
const PKG = resolve(ROOT, 'package.json');

const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
// comentários fora: as asserções têm de casar SQL real, não a documentação que
// menciona de propósito o anti-padrão que o arquivo remove.
const mig = migRaw.replace(/^\s*--.*$/gm, '');
const webhookRaw = existsSync(WEBHOOK) ? readFileSync(WEBHOOK, 'utf8') : '';
const webhook = webhookRaw.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// Sonda sintética e auto-identificável. `.invalid` é reservado por RFC 2606, de
// modo que nunca colide com um e-mail real de candidato — e a limpeza roda no
// INÍCIO e no FIM, porque um dado de teste que sobrevive à limpeza vira uma
// entidade real (aqui: uma linha permanente na fila de exceção do GP).
const PROBE_EVENT = 'contract-test-1609@probe.invalid';
const PROBE_GUEST = 'contract-probe-1609@example.invalid';

async function purgeProbe(sb) {
  await sb.from('selection_booking_attempts').delete().eq('calendar_event_id', PROBE_EVENT);
}

// ── STATIC: a migration ──────────────────────────────────────────────────────
test('1609/1611 static: migration 20260805000512 existe', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000512 presente');
});

test('1611 static: o matcher devolve match_outcome e nunca mais conjunto vazio', () => {
  assert.match(mig, /DROP FUNCTION IF EXISTS public\.match_booking_application\(text\);/,
    'mudança de FORMA de retorno exige DROP + CREATE, não CREATE OR REPLACE');
  assert.match(mig, /match_outcome\s+text/, 'coluna do motivo declarada no RETURNS TABLE');
  for (const outcome of ['matched', 'status_not_allowed', 'cycle_closed', 'no_application']) {
    assert.ok(mig.includes(`'${outcome}'`), `desfecho ${outcome} presente no matcher`);
  }
  // o `matched` só existe com ciclo aberto/ativo E status na allow-list — se esta
  // conjunção afrouxar, uma candidatura já decidida volta a ser reaberta por uma
  // reserva de calendário, que é exatamente o que a allow-list existe para impedir.
  assert.match(mig, /WHEN c\.status IN \('open', 'active'\) AND a\.status = ANY \(v_allow\) THEN 'matched'/,
    'matched exige ciclo aberto/ativo E status na allow-list');
  assert.match(mig, /v_allow text\[\] := ARRAY\['submitted', 'screening', 'objective_eval', 'objective_cutoff',\s*\n?\s*'interview_pending', 'interview_scheduled'\]/,
    'allow-list pré-entrevista preservada (nunca reabre candidatura decidida)');
});

test('1609 static: o contador existe, tem chave por par e RLS ligada', () => {
  assert.match(mig, /CREATE TABLE IF NOT EXISTS public\.selection_booking_attempts/);
  assert.match(mig, /UNIQUE \(calendar_event_id, guest_email\)/,
    'a chave é o PAR — um mesmo evento carrega mais de um convidado (medido: 6 dos 27 eventos)');
  assert.match(mig, /ALTER TABLE public\.selection_booking_attempts ENABLE ROW LEVEL SECURITY/,
    'tabela com e-mail de candidato (PII) sem RLS seria violação de LGPD/GC-162');
  assert.match(mig, /REVOKE ALL ON TABLE public\.selection_booking_attempts FROM PUBLIC, anon, authenticated/);
});

test('1609 static: existe corte, e ele é um número — não "logar sempre"', () => {
  assert.match(mig, /c_audit_cut constant integer := (\d+);/, 'o corte é uma constante explícita');
  const cut = Number(mig.match(/c_audit_cut constant integer := (\d+);/)[1]);
  assert.ok(cut > 0 && cut <= 50, `corte fora de faixa plausível: ${cut}`);
  assert.match(mig, /WHEN ba\.attempts \+ 1 >= c_audit_cut\s*THEN now\(\)/, 'o corte grava suppressed_at');
  assert.match(mig, /should_audit := \(v_row\.attempts = 1\)/, 'a primeira aparição sempre audita');
});

test('1609/1611 static: escada de grants — escrita service_role, leitura gateada', () => {
  assert.match(mig, /REVOKE ALL ON FUNCTION public\.match_booking_application\(text\) FROM PUBLIC, anon, authenticated/);
  assert.match(mig, /GRANT EXECUTE ON FUNCTION public\.match_booking_application\(text\) TO service_role;/);
  assert.match(mig, /REVOKE ALL ON FUNCTION public\.record_booking_attempt\(text, text, text, timestamptz\) FROM PUBLIC, anon, authenticated/);
  // REVOKE só de PUBLIC não fecha nada: o Supabase concede EXECUTE a
  // anon/authenticated EXPLICITAMENTE via ALTER DEFAULT PRIVILEGES.
  assert.ok(!/GRANT EXECUTE ON FUNCTION public\.match_booking_application\(text\)[^;]*\bauthenticated\b/.test(mig),
    'REGRESSÃO: matcher alcançável por authenticated — enumeração de PII de candidato por e-mail');
  assert.ok(!/GRANT EXECUTE ON FUNCTION public\.record_booking_attempt\([^)]*\)[^;]*\banon\b/.test(mig),
    'REGRESSÃO: contador (escrita) alcançável por anon');
  assert.match(mig, /REVOKE ALL ON FUNCTION public\.get_booking_exception_queue\(boolean\) FROM PUBLIC, anon/);
  assert.match(mig, /GRANT EXECUTE ON FUNCTION public\.get_booking_exception_queue\(boolean\) TO authenticated, service_role;/);
  assert.match(migRaw, /NOTIFY pgrst, 'reload schema'/);
});

test('1611 static: o consumidor contaminado foi corrigido junto (classe (e) do relatório)', () => {
  // Inventariar os consumidores É parte da mudança. O relatório de consistência
  // contava LINHAS de admin_audit_log; medido em 05/08, dizia 3.277 anomalias com
  // ZERO candidaturas quebradas.
  assert.match(mig, /CREATE OR REPLACE FUNCTION public\.selection_consistency_report/,
    'o único consumidor SQL do balde foi reescrito no mesmo PR');
  const report = mig.match(/CREATE OR REPLACE FUNCTION public\.selection_consistency_report[\s\S]*?\$function\$([\s\S]*?)\$function\$/)[1];
  assert.match(report, /FROM public\.selection_booking_attempts ba\s+WHERE ba\.last_outcome = 'no_application'/,
    'classe (e) lê o contador e SÓ o desfecho acionável');
  assert.ok(!/rows_e AS \([\s\S]*?FROM public\.admin_audit_log/.test(report),
    'REGRESSÃO: classe (e) voltou a contar linhas de admin_audit_log');
});

// ── STATIC: o webhook ────────────────────────────────────────────────────────
test('1611 static: o webhook tem uma ação de audit POR desfecho', () => {
  assert.ok(existsSync(WEBHOOK), 'calendar-webhook.ts presente');
  assert.match(webhook, /no_application:\s*'calendar_booking_unmatched'/);
  assert.match(webhook, /status_not_allowed:\s*'calendar_booking_already_decided'/);
  assert.match(webhook, /cycle_closed:\s*'calendar_booking_stale_cycle'/);
  assert.match(webhook, /action:\s*'calendar_booking_synced'/, 'o sucesso continua auditado');
});

test('1609 static: o webhook conta a tentativa e só audita quando autorizado', () => {
  assert.match(webhook, /\.rpc\('record_booking_attempt',\s*\{/, 'a tentativa é contabilizada');
  assert.match(webhook, /if \(attempt\?\.should_audit !== false\)/,
    'a linha de auditoria é condicionada ao contador');
  // forward-defense: o INSERT incondicional que produziu as 16.722 linhas
  const unconditional = /if \(!matched\) \{[\s\S]{0,200}?await sb\.from\('admin_audit_log'\)\.insert/;
  assert.ok(!unconditional.test(webhook),
    'REGRESSÃO: o webhook voltou a gravar admin_audit_log a cada tentativa recusada');
});

test('1611 static: a resposta 404 diz o motivo E se vale retentar', () => {
  assert.match(webhook, /reason:\s*outcome/, 'o motivo volta no corpo da 404');
  assert.match(webhook, /retryable:\s*isRetryable\(outcome\)/, 'a origem sabe quando desistir');
  // O invariante do #1611 é o que NÃO é retentável, não a lista do que é: uma candidatura
  // decidida e um ciclo fechado não mudam sozinhos, então reenviar é tempestade garantida.
  // O #1613 acrescentou `objective_phase_incomplete`, que MUDA sozinho (o comitê termina a
  // avaliação) e por isso É retentável — sob o mesmo corte de 10 do contador.
  const retryBody = webhook.match(/function isRetryable\(outcome: string\): boolean \{([\s\S]*?)\n\}/)?.[1];
  assert.ok(retryBody, 'isRetryable localizada');
  assert.match(retryBody, /outcome === 'no_application'/, 'o buraco real segue retentável');
  for (const naoRetentavel of ['status_not_allowed', 'cycle_closed']) {
    assert.ok(!retryBody.includes(naoRetentavel),
      `REGRESSÃO: ${naoRetentavel} virou retentável — recusa correta por desenho não muda sozinha`);
  }
});

test('1609/1611 guard: o teste está registrado nas DUAS listas do package.json', () => {
  const pkg = readFileSync(PKG, 'utf8');
  const hits = (pkg.match(/1609-1611-booking-entrance-door\.test\.mjs/g) || []).length;
  assert.equal(hits, 2, 'precisa estar em "test" E em "test:contracts" — senão nunca roda em CI');
});

// ── COMPORTAMENTAL (DB-gated) ────────────────────────────────────────────────
test('1611 behavioural: e-mail que não resolve nada devolve UMA linha, não conjunto vazio',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { data, error } = await sb.rpc('match_booking_application', { p_guest_email: 'definitely-nobody@example.invalid' });
    assert.ifError(error);
    assert.equal(data.length, 1, 'sempre exatamente uma linha (antes: conjunto vazio, indistinguível dos outros dois casos)');
    assert.equal(data[0].match_outcome, 'no_application');
    assert.equal(data[0].application_id, null, 'sem candidatura, sem id — nada a promover');
  });

test('1611 behavioural: candidatura JÁ DECIDIDA com e-mail correto NÃO é unmatched (aceite do #1611)',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    // qualquer candidatura de ciclo aberto/ativo com status FORA da allow-list
    const { data: apps } = await sb
      .from('selection_applications')
      .select('email, status, selection_cycles!inner(status)')
      .in('status', ['final_eval', 'interview_done', 'approved', 'rejected'])
      .in('selection_cycles.status', ['open', 'active'])
      .not('email', 'is', null)
      .limit(1);
    const probe = apps?.[0];
    if (!probe) return; // coorte vazia — nada a afirmar, não é falha
    const { data, error } = await sb.rpc('match_booking_application', { p_guest_email: String(probe.email) });
    assert.ifError(error);
    assert.equal(data.length, 1);
    assert.equal(data[0].match_outcome, 'status_not_allowed',
      'uma candidatura decidida é RECUSA CORRETA, não "não achei candidatura"');
    assert.notEqual(data[0].application_id, null,
      'a identidade vai junto — é o que deixa o GP ver na fila que a recusa foi correta');
  });

test('1611 behavioural: candidato pré-entrevista continua casando por primary (não regrediu)',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { data: apps } = await sb
      .from('selection_applications')
      .select('email, selection_cycles!inner(status)')
      .in('status', ['interview_pending', 'interview_scheduled', 'objective_cutoff', 'submitted'])
      .in('selection_cycles.status', ['open', 'active'])
      .not('email', 'is', null)
      .limit(1);
    const probe = apps?.[0];
    if (!probe) return;
    const { data, error } = await sb.rpc('match_booking_application', { p_guest_email: String(probe.email).toUpperCase() });
    assert.ifError(error);
    assert.equal(data.length, 1);
    assert.equal(data[0].match_outcome, 'matched');
    assert.equal(data[0].matched_by, 'primary', 'match direto é primary (sondado em MAIÚSCULAS)');
  });

test('1609 behavioural: 12 tentativas do mesmo par = 1 linha de contador e no máximo 2 autorizações de log',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    await purgeProbe(sb); // limpa resto de execução anterior antes de medir
    try {
      const audits = [];
      for (let i = 0; i < 12; i++) {
        const { data, error } = await sb.rpc('record_booking_attempt', {
          p_calendar_event_id: PROBE_EVENT,
          p_guest_email: PROBE_GUEST,
          p_outcome: 'no_application',
          p_scheduled_at: null,
        });
        assert.ifError(error);
        const row = Array.isArray(data) ? data[0] : data;
        assert.equal(row.attempts, i + 1, 'o contador anda a cada tentativa');
        if (row.should_audit) audits.push(i + 1);
      }

      const { data: rows } = await sb.from('selection_booking_attempts')
        .select('attempts, suppressed_at, last_outcome')
        .eq('calendar_event_id', PROBE_EVENT);
      assert.equal(rows.length, 1, 'UMA linha por par — este é o coração do #1609');
      assert.equal(rows[0].attempts, 12);
      assert.notEqual(rows[0].suppressed_at, null, 'o corte disparou');

      assert.deepEqual(audits, [1, 10],
        `só a primeira aparição e o corte autorizam log; autorizou em ${JSON.stringify(audits)}`);

      // a resolução tem de reabrir o log: o par que casa SAI da fila.
      const { data: okData } = await sb.rpc('record_booking_attempt', {
        p_calendar_event_id: PROBE_EVENT,
        p_guest_email: PROBE_GUEST,
        p_outcome: 'matched',
        p_scheduled_at: null,
      });
      const okRow = Array.isArray(okData) ? okData[0] : okData;
      assert.equal(okRow.should_audit, true, 'a resolução volta a auditar mesmo depois do corte');
      const { data: after } = await sb.from('selection_booking_attempts')
        .select('resolved_at, suppressed_at').eq('calendar_event_id', PROBE_EVENT);
      assert.notEqual(after[0].resolved_at, null, 'resolved_at marca a saída da fila');
      assert.equal(after[0].suppressed_at, null, 'a supressão é zerada por uma resolução');
    } finally {
      await purgeProbe(sb);
    }
  });

test('1609 behavioural: outcome inválido é RECUSADO, não gravado calado',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { error } = await sb.rpc('record_booking_attempt', {
      p_calendar_event_id: PROBE_EVENT,
      p_guest_email: PROBE_GUEST,
      p_outcome: 'nao_existe',
      p_scheduled_at: null,
    });
    assert.ok(error, 'um vocabulário desconhecido tem de levantar, não virar linha órfã');
    await purgeProbe(sb);
  });

test('R4.3 behavioural: a fila de exceção é legível sem varrer admin_audit_log',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { data, error } = await sb.rpc('get_booking_exception_queue', { p_include_resolved: false });
    assert.ifError(error);
    assert.ok(Array.isArray(data), 'a fila responde como tabela');
    for (const r of data) {
      assert.ok(['no_application', 'status_not_allowed', 'cycle_closed', 'matched'].includes(r.last_outcome),
        `desfecho fora do vocabulário: ${r.last_outcome}`);
      // `actionable` é a separação que o #1611 pede: só o buraco real.
      assert.equal(r.actionable, r.last_outcome === 'no_application' && r.resolved_at === null);
    }
  });
