/**
 * #2580 frente 2, regra 2 (decisao do GP de 08/10/2026, D3): um unico resumo semanal por pessoa, segunda 09h de
 * Brasilia; a parte de lider entra no mesmo resumo.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. o resumo de membro classifica o resumo de lider pendente na secao 'leadership' e a devolve;
 *   B. o orquestrador conta a secao 'leadership' (lider cujo unico conteudo e a lideranca ainda recebe);
 *   C. o gerador de lider grava digest_weekly so para quem esta na audiencia do resumo semanal, com o mesmo
 *      predicado do orquestrador; quem nao esta continua com o e-mail proprio;
 *   D. agenda: lider segunda 11:50 UTC, membro segunda 12:00 UTC (o lider roda antes);
 *   E. o e-mail desenha a secao de lideranca a partir do payload do lider;
 *   F. (banco) a expectativa de agenda dos dois jobs foi atualizada.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const DIR = resolve(ROOT, 'supabase/migrations');
const files = readdirSync(DIR).filter((f) => /^\d{14}_2580_resumo_semanal_unico\.sql$/.test(f));
const SQL = files.length === 1 ? maskLineComments(readFileSync(join(DIR, files[0]), 'utf8')) : '';
const cap = (n) => maskLineComments(latestFunctionCapture(ROOT, n).block);
const EF = maskJsComments(readFileSync(resolve(ROOT, 'supabase/functions/send-notification-email/index.ts'), 'utf8'));

const AUDIENCE = [/is_active = true/, /notify_weekly_digest = true/, /notify_delivery_mode_pref IN \('weekly_digest', 'custom_per_type'\)/];

test('a migration existe', () => {
  assert.equal(files.length, 1, `esperava 1 migration, achei ${files.length}`);
});

test('A. o resumo de lider pendente vira a secao leadership', () => {
  const b = cap('get_weekly_member_digest');
  assert.match(b, /WHEN n\.type = 'weekly_tribe_digest_leader' THEN 'leadership'\s+ELSE 'other_notifications'/);
  assert.match(b, /'leadership', COALESCE\(v_notif->'leadership', '\[\]'::jsonb\)/);
});

test('B. o orquestrador conta a secao leadership', () => {
  const b = cap('generate_weekly_member_digest_cron');
  assert.match(b, /v_has_content :=[\s\S]*?OR jsonb_array_length\(v_digest->'sections'->'leadership'\) > 0[\s\S]*?;/);
  const where = (b.match(/FROM public\.members\s+WHERE([\s\S]*?)LOOP/) || ['', ''])[1];
  for (const re of AUDIENCE) assert.match(where, re, `audiencia do orquestrador sem ${re}`);
});

test('C. o gerador de lider grava digest_weekly so para a audiencia do resumo semanal', () => {
  const b = cap('generate_weekly_leader_digest_cron');
  const caseExpr = (b.match(/CASE WHEN mm\.([\s\S]*?)END,\s+v_batch_id\s+FROM to_send t\s+JOIN public\.members mm ON mm\.id = t\.leader_id/) || ['', ''])[1];
  assert.ok(caseExpr, 'CASE do delivery_mode amarrado ao lider do to_send');
  for (const re of AUDIENCE) assert.match(caseExpr, re, `predicado do lider sem ${re}`);
  assert.match(caseExpr, /THEN 'digest_weekly'\s+ELSE 'transactional_immediate'\s*$/);
});

test('D. agenda: lider 11:50 UTC e membro 12:00 UTC, segunda', () => {
  assert.match(SQL, /PERFORM cron\.alter_job\(job_id := v_leader, schedule := '50 11 \* \* 1'\);/);
  assert.match(SQL, /PERFORM cron\.alter_job\(job_id := v_member, schedule := '0 12 \* \* 1'\);/);
  assert.match(SQL, /SELECT jobid INTO v_leader FROM cron\.job WHERE jobname = 'send-weekly-leader-digest';/);
  assert.match(SQL, /SELECT jobid INTO v_member FROM cron\.job WHERE jobname = 'send-weekly-member-digest';/);
  assert.match(SQL, /IF v_leader IS NULL OR v_member IS NULL THEN\s+RAISE EXCEPTION/);
});

test('E. o e-mail desenha a lideranca a partir do payload do lider', () => {
  assert.match(EF, /const leadership = sections\.leadership \|\| \[\]/);
  assert.match(EF, /if \(Array\.isArray\(lp\?\.initiatives\)\) leaderInitiatives\.push\(\.\.\.lp\.initiatives\)/);
  assert.match(EF, /const leadershipHtml = leaderInitiatives\.length === 0 \? '' : `[\s\S]*?buildLeaderInitiativeBodyHtml\(lp\)[\s\S]*?`\n/);
  assert.match(EF, /sectionBlock\('📋 Seus cards'[^\n]*\n\s+\$\{leadershipHtml\}/);
  assert.match(EF, /const totalItems = [^\n]*\+ leaderInitiatives\.length\n/);
});

const URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(URL && SERVICE);

test('F. (banco) a expectativa de agenda dos dois jobs', { skip: dbGated ? false : 'SUPABASE_URL + service role required' }, async () => {
  const r = await fetch(`${URL}/rest/v1/digest_cron_expectations?select=jobname,expected_schedule,retired_at`, {
    headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}` },
  });
  assert.equal(r.status, 200);
  const rows = Object.fromEntries((await r.json()).map((x) => [x.jobname, x]));
  assert.equal(rows['send-weekly-leader-digest']?.expected_schedule, '50 11 * * 1');
  assert.equal(rows['send-weekly-member-digest']?.expected_schedule, '0 12 * * 1');
  // controle: o aposentado nao foi tocado
  assert.equal(rows['weekly-card-digest-saturday']?.expected_schedule, '0 12 * * 6');
});
