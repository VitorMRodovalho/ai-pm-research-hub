/**
 * #2580 frente 2, regra 1 (decisao do GP de 08/10/2026): no maximo 1 e-mail por pessoa por dia, salvo os urgentes.
 *
 * D2: urgentes = selection_approved, selection_interview_scheduled, selection_reschedule_escalated,
 * selection_termo_due, affiliation_renewal_d7_urgent, e desde 10/10 tracker_pii_found. Excesso (decisao b): fica pendente e sai num unico e-mail a partir
 * das 07h de Brasilia do dia seguinte.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. a lista de urgentes e a mesma no banco (_is_urgent_email_type) e na Edge Function (URGENT_EMAIL_TYPES), e e
 *      exatamente a da D2;
 *   B. email_people_sent_today conta, desde o inicio do dia de Brasilia, notificacoes enviadas (todo status menos
 *      'deduplicated') que nao sao urgentes, e campanhas entregues a membros;
 *   C. a Edge Function le a contagem por pessoa e, sem conseguir ler, nao libera nada nao urgente;
 *   D. urgentes saem todos; do resto sai no maximo um envio por pessoa, so com a janela aberta (07h) e com contagem
 *      zero; o que sobra so e contado como retido (nao recebe email_sent_at);
 *   E. as duas funcoes so executam para service_role;
 *   F. (banco) a lista viva bate com a D2, e a contagem viva responde.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const DIR = resolve(ROOT, 'supabase/migrations');
const files = readdirSync(DIR).filter((f) => /^\d{14}_2580_um_email_por_pessoa_por_dia\.sql$/.test(f));
const SQL = files.length === 1 ? maskLineComments(readFileSync(join(DIR, files[0]), 'utf8')) : '';
// A lista viva vem da ultima captura (a migration do cutoff a redefine).
const URGENT_CAP = () => maskLineComments(latestFunctionCapture(ROOT, '_is_urgent_email_type').block);
const fn = (name) => (SQL.match(new RegExp(String.raw`CREATE OR REPLACE FUNCTION public\.${name}\([\s\S]*?\$function\$[\s\S]*?\$function\$`)) || [''])[0];
const EF = maskJsComments(readFileSync(resolve(ROOT, 'supabase/functions/send-notification-email/index.ts'), 'utf8'));

// D2 + selection_cutoff_approved (decisao do GP de 08/10/2026, convite para marcar a entrevista depois do corte).
// tracker_pii_found entrou em 10/10/2026 (decisao do GP): o dado pessoal achado no tracker publico segue publico
// enquanto ninguem age.
const D2 = ['affiliation_renewal_d7_urgent', 'selection_approved', 'selection_cutoff_approved', 'selection_interview_scheduled', 'selection_reschedule_escalated', 'selection_termo_due', 'tracker_pii_found'];

test('a migration existe', () => {
  assert.equal(files.length, 1, `esperava 1 migration, achei ${files.length}`);
});

test('A. a lista de urgentes e a da D2, igual no banco e na Edge Function', () => {
  const sqlList = (URGENT_CAP().match(/p_type IN \(([\s\S]*?)\);/) || ['', ''])[1];
  const sqlTypes = [...sqlList.matchAll(/'([a-z0-9_]+)'/g)].map((m) => m[1]).sort();
  assert.deepEqual(sqlTypes, D2, 'lista do banco diferente da D2');
  const efList = (EF.match(/const URGENT_EMAIL_TYPES = new Set<string>\(\[([\s\S]*?)\]\)/) || ['', ''])[1];
  const efTypes = [...efList.matchAll(/'([a-z0-9_]+)'/g)].map((m) => m[1]).sort();
  assert.deepEqual(efTypes, D2, 'lista da Edge Function diferente da D2');
});

test('B. a contagem por pessoa: dia de Brasilia, envios reais nao urgentes, mais campanhas', () => {
  const c = fn('email_people_sent_today');
  assert.match(c, /date_trunc\('day', now\(\) AT TIME ZONE 'America\/Sao_Paulo'\) AT TIME ZONE 'America\/Sao_Paulo'/);
  assert.match(c, /AND n\.email_sent_at >= inicio\.t\s+AND n\.email_delivery_status IS DISTINCT FROM 'deduplicated'\s+AND NOT public\._is_urgent_email_type\(n\.type\)/);
  assert.match(c, /AND r\.delivered\s+AND COALESCE\(r\.delivered_at, s\.sent_at\) >= inicio\.t/);
});

test('C. sem ler a contagem, nada nao urgente sai', () => {
  assert.match(EF, /sb\.rpc\('email_people_sent_today', \{\s+p_member_ids: \[\.\.\.groups\.keys\(\)\],\s+\}\)/);
  assert.match(EF, /const releaseOpen = perPersonReadable && hourInBrasilia\(new Date\(\)\) >= RELEASE_HOUR_BRT/);
  assert.match(EF, /const RELEASE_HOUR_BRT = 7\b/);
  assert.match(EF, /timeZone: 'America\/Sao_Paulo'/);
});

test('D. urgentes saem todos; do resto, um envio por pessoa por dia; o excesso fica retido', () => {
  assert.match(EF, /const urgentRows = kept\.filter\(\(n: any\) => URGENT_EMAIL_TYPES\.has\(n\.type\)\)/);
  assert.match(EF, /const normalAllowed = releaseOpen && \(sentTodayByPerson\[recipientId\] \?\? 0\) < 1/);
  assert.match(EF, /const sends = \[\.\.\.buildSends\(urgentRows\), \.\.\.\(normalAllowed \? normalSends\.slice\(0, 1\) : \[\]\)\]/);
  assert.match(EF, /for \(const s of \(normalAllowed \? normalSends\.slice\(1\) : normalSends\)\) held \+= s\.ids\.length/);
  // o retido nao recebe email_sent_at: as escritas sao a do aceite, a da dedup e a da supressao (#2130)
  const updates = EF.match(/email_sent_at: /g) || [];
  assert.equal(updates.length, 3, `esperava 3 escritas de email_sent_at (aceite, dedup e supressao), achei ${updates.length}`);
});

test('E. as duas funcoes so para service_role', () => {
  for (const sig of ['_is_urgent_email_type\\(text\\)', 'email_people_sent_today\\(uuid\\[\\]\\)']) {
    assert.match(SQL, new RegExp(`REVOKE ALL ON FUNCTION public\\.${sig} FROM PUBLIC, anon, authenticated;`));
    assert.match(SQL, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${sig} TO service_role;`));
  }
});

const URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(URL && SERVICE);

async function rpc(name, body) {
  const r = await fetch(`${URL}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return { status: r.status, body: r.status === 200 ? await r.json() : await r.text() };
}

test('F. (banco) a lista viva bate com a D2; a contagem responde', { skip: dbGated ? false : 'SUPABASE_URL + service role required' }, async () => {
  for (const t of D2) {
    const r = await rpc('_is_urgent_email_type', { p_type: t });
    assert.equal(r.status, 200);
    assert.equal(r.body, true, `${t} deveria ser urgente`);
  }
  // controle: o instrumento sabe dizer nao
  for (const t of ['curation_review_assigned', 'weekly_member_digest', 'system_alert']) {
    const r = await rpc('_is_urgent_email_type', { p_type: t });
    assert.equal(r.body, false, `${t} nao deveria ser urgente`);
  }
  const c = await rpc('email_people_sent_today', { p_member_ids: ['00000000-0000-0000-0000-000000000000'] });
  assert.equal(c.status, 200);
  assert.deepEqual(c.body, {});
});
