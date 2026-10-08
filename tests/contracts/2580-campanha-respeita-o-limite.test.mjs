/**
 * #2580 frente 2, regra 5 (decisao do GP de 08/10/2026): campanha tambem respeita a regra 1, no maximo um e-mail por
 * pessoa por dia.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. campaign_defer_recipients adia so o que nao foi entregue, para as 07h de Brasilia do dia seguinte, e so executa
 *      para service_role; campaign_sends aceita 'throttled';
 *   B. o cron so retoma envio com destinatario pendente que ja pode sair (deferred_until vencido ou vazio);
 *   C. a Edge Function nao reenvia a quem ja foi entregue, le a contagem por pessoa e, sem ler, nao envia a membro;
 *   D. membro que ja recebeu hoje (ou nesta mesma rodada) e adiado; o adiado vencido sai sem olhar a contagem;
 *   E. com adiado ou esperando, o envio fica 'throttled' (o cron o retoma);
 *   F. (banco) anon nao executa; service_role recebe 07h de Brasilia do dia seguinte.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const DIR = resolve(ROOT, 'supabase/migrations');
const files = readdirSync(DIR).filter((f) => /^\d{14}_2580_campanha_respeita_o_limite_por_pessoa\.sql$/.test(f));
const SQL = files.length === 1 ? maskLineComments(readFileSync(join(DIR, files[0]), 'utf8')) : '';
const cap = (n) => maskLineComments(latestFunctionCapture(ROOT, n).block);
const EF = maskJsComments(readFileSync(resolve(ROOT, 'supabase/functions/send-campaign/index.ts'), 'utf8'));

test('a migration existe', () => {
  assert.equal(files.length, 1, `esperava 1 migration, achei ${files.length}`);
});

test('A. adiamento: so o nao entregue, 07h do dia seguinte, so service_role; throttled e status valido', () => {
  const b = cap('campaign_defer_recipients');
  assert.match(b, /v_release timestamptz := \(date_trunc\('day', now\(\) AT TIME ZONE 'America\/Sao_Paulo'\) \+ interval '1 day 7 hours'\) AT TIME ZONE 'America\/Sao_Paulo';/);
  assert.match(b, /SET deferred_until = v_release,[\s\S]*?WHERE id = ANY\(p_recipient_ids\)\s+AND delivered = false;/);
  assert.match(SQL, /REVOKE ALL ON FUNCTION public\.campaign_defer_recipients\(uuid\[\]\) FROM PUBLIC, anon, authenticated;/);
  assert.match(SQL, /GRANT EXECUTE ON FUNCTION public\.campaign_defer_recipients\(uuid\[\]\) TO service_role;/);
  assert.match(SQL, /ADD CONSTRAINT campaign_sends_status_check\s+CHECK \(status = ANY \(ARRAY\[[^\]]*'throttled'::text\]\)\)/);
});

test('B. o cron so retoma destinatario que ja pode sair', () => {
  const b = cap('process_pending_email_queue');
  assert.match(b, /WHERE cr\.send_id = cs\.id AND cr\.delivered = false AND cr\.unsubscribed = false\s+AND \(cr\.deferred_until IS NULL OR cr\.deferred_until <= now\(\)\)/);
});

test('C. nao reenvia ao entregue; sem ler a contagem, membro espera', () => {
  assert.match(EF, /\.select\('id, member_id, external_email, external_name, language, unsubscribed, unsubscribe_token, delivered, deferred_until'\)/);
  assert.match(EF, /if \(r\.unsubscribed \|\| r\.delivered\) continue/);
  assert.match(EF, /await sb\.rpc\('email_people_sent_today', \{\s+p_member_ids: pendingMemberIds,\s+\}\)/);
  assert.match(EF, /\} else if \(!perPersonReadable\) \{\s+waiting\+\+\s+continue\s+\}/);
});

test('D. quem ja recebeu hoje e adiado; o adiado vencido sai', () => {
  assert.match(EF, /if \(r\.deferred_until\) \{\s+if \(Date\.parse\(r\.deferred_until\) > Date\.now\(\)\) \{ waiting\+\+; continue \}\s+\}/);
  assert.match(EF, /\} else if \(\(sentTodayByPerson\[r\.member_id\] \?\? 0\) >= 1 \|\| sentThisRun\.has\(r\.member_id\)\) \{\s+toDefer\.push\(r\.id\)\s+continue\s+\}/);
  assert.match(EF, /delivered\+\+\s+if \(r\.member_id\) sentThisRun\.add\(r\.member_id\)/);
  assert.match(EF, /await sb\.rpc\('campaign_defer_recipients', \{ p_recipient_ids: toDefer \}\)/);
});

test('E. com adiado ou esperando, o envio fica throttled', () => {
  assert.match(EF, /const pendingLater = waiting \+ toDefer\.length/);
  assert.match(EF, /const finalStatus = pendingLater > 0 \? 'throttled' : \(delivered > 0 \|\| alreadyDelivered\) \? 'sent' : 'failed'/);
});

const URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const dbGated = !!(URL && SERVICE);

async function rpc(key, name, body) {
  const r = await fetch(`${URL}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return { status: r.status, body: r.status === 200 ? await r.json() : await r.text() };
}

test('F. (banco) service_role recebe 07h de Brasilia do dia seguinte; anon nao executa', { skip: dbGated ? false : 'SUPABASE_URL + service role required' }, async () => {
  // lista vazia: nao grava nada, so devolve o instante
  const r = await rpc(SERVICE, 'campaign_defer_recipients', { p_recipient_ids: [] });
  assert.equal(r.status, 200, String(r.body));
  const rel = new Date(r.body);
  assert.equal(rel.getUTCHours(), 10, `esperava 10h UTC (07h de Brasilia), veio ${r.body}`);
  const hours = (rel.getTime() - Date.now()) / 3600e3;
  assert.ok(hours >= 7 && hours <= 31, `liberacao fora do dia seguinte: ${r.body}`);
  if (ANON) {
    const a = await rpc(ANON, 'campaign_defer_recipients', { p_recipient_ids: [] });
    assert.notEqual(a.status, 200, 'anon nao deveria executar');
  }
});
