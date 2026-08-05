/**
 * Contract: #1608 — o retry da fila de e-mail cobre a segunda forma de cota da
 * Resend, e para de ressuscitar envio antigo.
 *
 * Dois defeitos, e o segundo é o que fazia a correção do primeiro ser perigosa:
 *
 *  1. `process_pending_email_queue()` só reprocessava `campaign_sends` com
 *     `status='failed'` quando o `error_log` casava `%rate_limit_exceeded%`. A
 *     Resend devolve `daily_quota_exceeded` quando o limite é o diário, e esse
 *     não casava.
 *  2. Não havia limite de IDADE. Corrigir só o vocabulário faria o cron (que roda
 *     a cada 30 min) despachar, no tick seguinte, dois envios de 2026-07-04 cujo assunto é
 *     "agende sua entrevista neste fim de semana" — para candidaturas medidas em
 *     2026-08-05 como já DECIDIDAS (uma `approved` com entrevista, outra
 *     `rejected`). O conserto teria criado o dano.
 *
 * O comportamental abaixo exercita a lógica REAL via `email_send_retry_eligible`
 * com valores sintéticos. Ele NÃO insere linha em `campaign_sends`: o cron roda a
 * cada 30 min e um `failed` recente com destinatário não entregue dispararia um
 * e-mail de verdade (`reference-test-data-that-survives-cleanup-becomes-a-real-entity`).
 * Duplicar o predicado dentro do teste seria a outra saída, e produziria um teste
 * que passa enquanto a função diverge.
 *
 * Cross-ref: issue #1608; migration 20260805000513.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000513_1608_retry_cobre_cota_diaria_e_para_de_ressuscitar.sql');
const PKG = resolve(ROOT, 'package.json');

const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
// comentários fora: o cabeçalho cita de propósito o predicado antigo que a
// migration remove, e as forward-defenses abaixo casariam nele.
const mig = migRaw.replace(/^\s*--.*$/gm, '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── STATIC ───────────────────────────────────────────────────────────────────
test('1608 static: migration 20260805000513 existe', () => {
  assert.ok(existsSync(MIG), 'migration presente');
});

test('1608 static: o vocabulário retentável é DADO, e cobre as DUAS formas de cota', () => {
  const m = mig.match(/unnest\(ARRAY\[([^\]]+)\]\)/);
  assert.ok(m, 'a allow-list existe como array, não como literal solto no WHERE');
  const nomes = m[1].split(',').map(s => s.trim().replace(/^'|'$/g, ''));
  assert.ok(nomes.includes('rate_limit_exceeded'), 'a forma por segundo continua coberta');
  assert.ok(nomes.includes('daily_quota_exceeded'), 'a forma diária passa a ser coberta — o defeito do #1608');
});

test('1608 static: existe limite de idade, e ele é a metade que impede o dano', () => {
  assert.match(mig, /p_created_at >= now\(\) - interval '24 hours'/,
    'sem o limite de idade, corrigir o vocabulário ressuscita envio de 32 dias');
});

test('1608 static: a fila consulta o predicado nomeado, não um ILIKE inline', () => {
  const corpo = mig.match(/CREATE OR REPLACE FUNCTION public\.process_pending_email_queue[\s\S]*?\$function\$([\s\S]*?)\$function\$/)[1];
  assert.match(corpo, /public\.email_send_retry_eligible\(cs\.status, cs\.error_log, cs\.created_at\)/,
    'a fila delega a decisão ao predicado nomeado');
  // forward-defense: o predicado antigo não pode voltar
  assert.ok(!/cs\.error_log ILIKE '%rate_limit_exceeded%'/.test(corpo),
    'REGRESSÃO: o ILIKE inline voltou — ele ignora daily_quota_exceeded e não olha idade');
});

test('1608 static: escada de grants — o predicado não alcança anon', () => {
  assert.match(mig, /REVOKE ALL ON FUNCTION public\.email_send_retry_eligible\(text, text, timestamptz\) FROM PUBLIC, anon/);
  assert.ok(!/GRANT EXECUTE ON FUNCTION public\.email_send_retry_eligible\([^)]*\)[^;]*\banon\b/.test(mig),
    'REGRESSÃO: predicado concedido a anon');
  assert.match(migRaw, /NOTIFY pgrst, 'reload schema'/);
});

test('1608 guard: o teste está registrado nas DUAS listas do package.json', () => {
  const pkg = readFileSync(PKG, 'utf8');
  const hits = (pkg.match(/1608-email-retry-quota-and-staleness\.test\.mjs/g) || []).length;
  assert.equal(hits, 2, 'precisa estar em "test" E em "test:contracts" — senão nunca roda em CI');
});

// ── COMPORTAMENTAL (DB-gated) ────────────────────────────────────────────────
const CASOS = [
  { nome: 'cota diária recente — O DEFEITO CORRIGIDO', status: 'failed', log: '{"name":"daily_quota_exceeded"}', idadeH: 1,   esperado: true },
  { nome: 'rate limit recente — não regrediu',          status: 'failed', log: '{"name":"rate_limit_exceeded"}',  idadeH: 2,   esperado: true },
  { nome: 'cota diária com 32 dias — LIMITE DE IDADE',  status: 'failed', log: '{"name":"daily_quota_exceeded"}', idadeH: 768, esperado: false },
  { nome: 'erro permanente 401 recente — não alarga',   status: 'failed', log: 'Edge Function 401 — fixed in v2', idadeH: 1,   esperado: false },
  { nome: 'envio já entregue',                          status: 'sent',   log: '{"name":"daily_quota_exceeded"}', idadeH: 1,   esperado: false },
  { nome: 'sem error_log',                              status: 'failed', log: null,                              idadeH: 1,   esperado: false },
];

test('1608 behavioural: o predicado decide os 6 casos corretamente (sem escrever linha nenhuma)',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    for (const c of CASOS) {
      const quando = new Date(Date.now() - c.idadeH * 3600_000).toISOString();
      const { data, error } = await sb.rpc('email_send_retry_eligible', {
        p_status: c.status, p_error_log: c.log, p_created_at: quando,
      });
      assert.ifError(error);
      assert.equal(data, c.esperado, `caso "${c.nome}": esperado ${c.esperado}, obtido ${data}`);
    }
  });

test('1608 behavioural: nenhum envio falho em repouso hoje é retentável (os 2 de 04/07 ficam fora)',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { data: falhos, error } = await sb
      .from('campaign_sends')
      .select('id, status, error_log, created_at')
      .eq('status', 'failed');
    assert.ifError(error);
    if (!falhos?.length) return; // coorte vazia — nada a afirmar

    // invariante universal: ITERAR, não confiar num único match
    for (const s of falhos) {
      const { data: elegivel, error: e2 } = await sb.rpc('email_send_retry_eligible', {
        p_status: s.status, p_error_log: s.error_log, p_created_at: s.created_at,
      });
      assert.ifError(e2);
      const idadeH = (Date.now() - new Date(s.created_at).getTime()) / 3600_000;
      if (idadeH > 24) {
        assert.equal(elegivel, false,
          `envio ${s.id} tem ${Math.round(idadeH)}h e foi marcado retentável — o limite de idade não está valendo`);
      }
    }
  });
