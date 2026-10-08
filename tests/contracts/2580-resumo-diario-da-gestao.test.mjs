/**
 * #2580 frente 2, regra 4 (decisoes do GP de 08/10/2026, D4 e C1 a C4): os alertas operacionais da gestao viram um
 * resumo diario, 08h de Brasilia.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. a varredura de alertas so manda e-mail na hora quando ha alerta `critical` (C2);
 *   B. teto diario, "Ja me filiei" e contas nao ligadas nascem `suppress` (sino na hora, e-mail no resumo) (C1, C3);
 *   C. o resumo junta, para quem administra a plataforma, os alertas nao enviados e os avisos `suppress` desses tipos,
 *      carimba o que montou e so carimba os alertas quando algum resumo saiu;
 *   D. agenda 11:00 UTC (08h de Brasilia) e execucao so para service_role;
 *   E. o e-mail tem renderizador proprio e o tipo e individual e deduplicado;
 *   F. (banco) a expectativa de agenda existe e anon nao executa o resumo.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const DIR = resolve(ROOT, 'supabase/migrations');
const files = readdirSync(DIR).filter((f) => /^\d{14}_2580_resumo_diario_da_gestao\.sql$/.test(f));
const SQL = files.length === 1 ? maskLineComments(readFileSync(join(DIR, files[0]), 'utf8')) : '';
const cap = (n) => maskLineComments(latestFunctionCapture(ROOT, n).block);
const EF = maskJsComments(readFileSync(resolve(ROOT, 'supabase/functions/send-notification-email/index.ts'), 'utf8'));

test('a migration existe', () => {
  assert.equal(files.length, 1, `esperava 1 migration, achei ${files.length}`);
});

test('A. a varredura so manda e-mail na hora com alerta critical', () => {
  const b = cap('_alert_sweep_cron');
  assert.match(b, /IF p_deliver_email\s+AND EXISTS \(SELECT 1 FROM public\.alert_deliveries WHERE resolved_at IS NULL AND emailed_at IS NULL\)\s+AND coalesce\(v_tem_critico, false\)\s+THEN/);
  assert.doesNotMatch(b, /interval '20 hours'/, 'o teto de 20 horas saiu: o nao critico vai para o resumo das 08h');
});

test('B. os avisos operacionais nascem suppress', () => {
  for (const fn of ['email_cap_reached', 'request_affiliation_recheck']) {
    assert.match(cap(fn), /'system_alert',[\s\S]*?false,\s+'suppress'\s+FROM public\.members m/, `${fn} nao nasce suppress`);
  }
  assert.match(cap('_delivery_mode_for'), /WHEN 'unlinked_accounts_detected'\s+THEN 'suppress'/);
  assert.match(cap('_delivery_mode_for'), /WHEN 'management_daily_digest'\s+THEN 'transactional_immediate'/);
});

test('C. o resumo junta, carimba o que montou e so carimba alerta quando saiu resumo', () => {
  const b = cap('_management_daily_digest_cron');
  assert.match(b, /v_types\s+text\[\] := ARRAY\['system_alert', 'unlinked_accounts_detected'\];/);
  assert.match(b, /WHERE m\.is_active IS TRUE AND public\.can_by_member\(m\.id, 'manage_platform'\)/);
  assert.match(b, /WHERE n\.recipient_id = v_adm\.id\s+AND n\.delivery_mode = 'suppress'\s+AND n\.type = ANY\(v_types\)\s+AND n\.digest_delivered_at IS NULL/);
  assert.match(b, /IF jsonb_array_length\(v_alerts\) = 0 AND jsonb_array_length\(v_items\) = 0 THEN\s+CONTINUE;/);
  assert.match(b, /'management_daily_digest',[\s\S]*?'transactional_immediate',\s+v_batch\s+\);/);
  assert.match(b, /SET digest_delivered_at = now\(\), digest_batch_id = v_batch\s+WHERE id = ANY\(v_ids\)/);
  assert.match(b, /IF v_sent > 0 THEN\s+UPDATE public\.alert_deliveries SET emailed_at = now\(\)/);
});

test('D. agenda 08h de Brasilia e so service_role', () => {
  assert.match(SQL, /SELECT cron\.schedule\('management-daily-digest', '0 11 \* \* \*', 'SELECT public\._management_daily_digest_cron\(\);'\);/);
  assert.match(SQL, /REVOKE ALL ON FUNCTION public\._management_daily_digest_cron\(\) FROM PUBLIC, anon, authenticated;/);
  assert.match(SQL, /GRANT EXECUTE ON FUNCTION public\._management_daily_digest_cron\(\) TO service_role;/);
});

test('E. o e-mail tem renderizador proprio, individual e deduplicado', () => {
  assert.match(EF, /const MANAGEMENT_DAILY_DIGEST_TYPE = 'management_daily_digest'/);
  assert.match(EF, /const ALWAYS_INDIVIDUAL_TYPES = new Set<string>\(\[[\s\S]*?MANAGEMENT_DAILY_DIGEST_TYPE,[\s\S]*?\]\)/);
  assert.match(EF, /const RICH_DIGEST_TYPES = new Set<string>\(\[[^\]]*MANAGEMENT_DAILY_DIGEST_TYPE\]\)/);
  assert.match(EF, /if \(notification\.type === MANAGEMENT_DAILY_DIGEST_TYPE\) \{\s+return buildManagementDailyDigestHtml\(notification\)/);
  const fn = (EF.match(/function buildManagementDailyDigestHtml[\s\S]*?\n\}\n/) || [''])[0];
  assert.match(fn, /const alerts: any\[\] = Array\.isArray\(payload\.alerts\) \? payload\.alerts : \[\]/);
  assert.match(fn, /const items: any\[\] = Array\.isArray\(payload\.items\) \? payload\.items : \[\]/);
  assert.match(fn, /\$\{alertsHtml\}\s+\$\{itemsHtml\}/);
});

const URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const dbGated = !!(URL && SERVICE);

test('F. (banco) expectativa de agenda e anon barrado', { skip: dbGated ? false : 'SUPABASE_URL + service role required' }, async () => {
  const r = await fetch(`${URL}/rest/v1/digest_cron_expectations?jobname=eq.management-daily-digest&select=expected_schedule,retired_at`, {
    headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}` },
  });
  assert.equal(r.status, 200);
  const rows = await r.json();
  assert.equal(rows.length, 1, 'expectativa de agenda do resumo da gestao ausente');
  assert.equal(rows[0].expected_schedule, '0 11 * * *');
  assert.equal(rows[0].retired_at, null);
  if (ANON) {
    const a = await fetch(`${URL}/rest/v1/rpc/_management_daily_digest_cron`, {
      method: 'POST',
      headers: { apikey: ANON, Authorization: `Bearer ${ANON}`, 'Content-Type': 'application/json' },
      body: '{}',
    });
    assert.notEqual(a.status, 200, 'anon nao deveria executar o resumo da gestao');
  }
});
