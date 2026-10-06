/**
 * Teto diário de e-mails do hub, num lugar só, contando só o que o hub envia (#2580, frente 1).
 *
 * A conta da Resend passou para o plano Pro, sem cota diária e dividida com outros projetos. O teto do hub
 * virou rede de segurança contra disparo descontrolado: mora em site_config ('email_daily_cap'), e a fila
 * de campanhas e as duas Edge Functions de e-mail leem dali.
 *
 * O QUE ESTE GUARD AFIRMA (captura vigente de cada função e fonte das Edge Functions):
 *   A. o valor nasce em site_config (250), e a leitura cai em 100 sem a chave ou com valor não numérico;
 *   B. a contagem do dia é a do hub: notificações (um e-mail por envio da Resend) e campanhas entregues,
 *      no dia de Brasília;
 *   C. o alerta vai para o sininho de quem gere a plataforma, uma vez por dia;
 *   D. a fila de campanhas lê o teto e a contagem, e alerta ao ficar sem vaga;
 *   E. a Edge Function de campanhas lê o teto e a contagem do banco, não envia se não conseguir ler, e
 *      alerta ao bater no teto; não sobra teto fixo nem variável de ambiente;
 *   F. as três funções novas não executam para PUBLIC, anon nem authenticated.
 * A Edge Function de notificações é coberta pelo guard da #1424.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const cap = (n) => maskLineComments(latestFunctionCapture(ROOT, n).block);
const DIR = join(ROOT, 'supabase/migrations');
const MIG = readdirSync(DIR).filter((f) => /_2580_teto_diario_de_email_do_hub\.sql$/.test(f));
const migSql = () => maskLineComments(readFileSync(join(DIR, MIG[0]), 'utf8'));

test('A: o teto nasce em site_config e a leitura tem piso seguro', () => {
  assert.equal(MIG.length, 1, 'uma migration da #2580');
  assert.match(migSql(),
    /INSERT INTO public\.site_config \(key, value\) VALUES \('email_daily_cap', '250'::jsonb\)\s+ON CONFLICT \(key\) DO NOTHING;/);
  assert.match(cap('email_daily_cap'),
    /SELECT COALESCE\(\s+\(SELECT CASE WHEN jsonb_typeof\(c\.value\) = 'number' THEN \(c\.value #>> '\{\}'\)::int END\s+FROM public\.site_config c WHERE c\.key = 'email_daily_cap'\),\s+100\);/);
});

test('B: a contagem do dia é a do hub, no dia de Brasília', () => {
  const b = cap('email_sends_today');
  assert.match(b, /date_trunc\('day', now\(\) AT TIME ZONE 'America\/Sao_Paulo'\) AT TIME ZONE 'America\/Sao_Paulo' AS inicio/);
  assert.match(b, /count\(DISTINCT coalesce\(n\.resend_id, n\.id::text\)\)\s+FROM public\.notifications n, d WHERE n\.email_sent_at >= d\.inicio/);
  assert.match(b, /FROM public\.campaign_recipients cr, d\s+WHERE cr\.delivered IS TRUE AND cr\.delivered_at >= d\.inicio/);
  assert.doesNotMatch(b, /email_webhook_events/, 'os eventos da conta inteira incluem outros projetos');
});

test('C: o alerta vai para quem gere a plataforma, uma vez por dia', () => {
  const b = cap('email_cap_reached');
  assert.match(b, /SECURITY DEFINER/);
  assert.match(b, /INSERT INTO public\.notifications \(recipient_id, type, title, body, link, source_type, is_read, delivery_mode\)/);
  assert.match(b, /'system_alert',/);
  assert.match(b, /AND public\.can_by_member\(m\.id, 'manage_platform'\)/);
  assert.match(b,
    /AND NOT EXISTS \(\s+SELECT 1 FROM public\.notifications n\s+WHERE n\.recipient_id = m\.id AND n\.source_type = 'email_daily_cap' AND n\.created_at >= v_inicio\s+\)/);
});

test('D: a fila de campanhas lê o teto e a contagem do hub, e alerta sem vaga', () => {
  const b = cap('process_pending_email_queue');
  assert.match(b, /v_daily_limit int := public\.email_daily_cap\(\);/);
  assert.match(b, /v_today_count := public\.email_sends_today\(\);/);
  assert.match(b, /IF v_slots = 0 THEN\s+PERFORM public\.email_cap_reached\('fila de campanhas'\);\s+RETURN/);
  assert.doesNotMatch(b, /v_daily_limit int := \d+/, 'sem teto fixo');
});

test('E: a Edge Function de campanhas lê o teto do banco e não envia sem ele', () => {
  const ef = maskJsComments(readFileSync(join(ROOT, 'supabase/functions/send-campaign/index.ts'), 'utf8'));
  assert.match(ef, /await sb\.rpc\('email_daily_cap'\)/);
  assert.match(ef, /await sb\.rpc\('email_sends_today'\)/);
  assert.match(ef,
    /if \(capErr \|\| todayErr \|\| typeof capData !== 'number' \|\| typeof todayData !== 'number'\) \{\s+return json\(\{ error: 'email_cap_unreadable'[^\n]*\}, 503\)/);
  assert.match(ef, /if \(todayCount >= DAILY_LIMIT\) \{\s+await sb\.rpc\('email_cap_reached', \{ p_lane: 'campanhas' \}\)/);
  assert.doesNotMatch(ef, /SEND_CAMPAIGN_DAILY_LIMIT/, 'sem variável de ambiente concorrendo com o banco');
  assert.doesNotMatch(ef, /DAILY_LIMIT\s*=\s*parseInt/, 'sem teto fixo');
});

test('F: as funções novas não executam para PUBLIC, anon nem authenticated', () => {
  const sql = migSql();
  for (const sig of ['email_daily_cap()', 'email_sends_today()', 'email_cap_reached(text)']) {
    const esc = sig.replace(/[()]/g, (c) => '\\' + c);
    assert.match(sql, new RegExp(`REVOKE ALL ON FUNCTION public\\.${esc} FROM PUBLIC, anon, authenticated;`), `${sig}: revoga`);
    assert.match(sql, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${esc} TO service_role;`), `${sig}: só service_role`);
  }
});
