/**
 * #2130 E-b (decisoes do GP de 08/10/2026): todo caminho de envio pergunta a UMA funcao quem nao pode receber.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. a regra: reclamacao, supressao do provedor ou bounce permanente sem entrega depois suprime; bounce transitorio
 *      nao; descadastro so quando o chamador pede; a funcao so abre para service_role;
 *   B. a fila do cron nao pega linha de campanha suprimida;
 *   C. linha de aviso marcada 'suppressed' nao conta como e-mail enviado, nem no teto do hub nem no limite por pessoa;
 *   D. avisos: suprimido vira 'suppressed' sem envio; sem ler a supressao, a rodada nao envia;
 *   E. campanha: descadastro vale fora do avulso; suprimido ganha suppressed_at e nao sai; sem ler, volta para a fila;
 *   F. os tres envios em massa filtram a lista antes de enviar;
 *   G. todo EF que chama o provedor esta classificado: consulta a supressao, ou e link pedido pela propria pessoa.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const FN_DIR = resolve(ROOT, 'supabase/functions');
const MIG_DIR = resolve(ROOT, 'supabase/migrations');
const files = readdirSync(MIG_DIR).filter((f) => /^\d{14}_2130_supressao_antes_de_enviar\.sql$/.test(f));
const SQL = files.length === 1 ? maskLineComments(readFileSync(join(MIG_DIR, files[0]), 'utf8')) : '';
const cap = (n) => maskLineComments(latestFunctionCapture(ROOT, n).block);
const ef = (n) => readFileSync(join(FN_DIR, n, 'index.ts'), 'utf8').replace(/^\s*\/\/.*$/gm, '');

const CONSULTA = ['send-notification-email', 'send-campaign', 'send-tribe-broadcast', 'send-allocation-notify', 'send-global-onboarding'];
const PEDIDO_PELA_PESSOA = ['send-email-verification', 'send-account-claim', 'send-competition-email'];

test('a migration existe', () => {
  assert.equal(files.length, 1, `esperava 1 migration, achei ${files.length}`);
});

test('A. a regra de supressao', () => {
  const f = cap('email_suppressed_among');
  assert.match(f, /max\(w\.created_at\) FILTER \(\s+WHERE w\.event_type IN \('email\.complained', 'email\.suppressed'\)\s+OR \(w\.event_type = 'email\.bounced' AND w\.payload #>> '\{data,bounce,type\}' = 'Permanent'\)\s+\) AS last_stop,/);
  assert.match(f, /max\(w\.created_at\) FILTER \(WHERE w\.event_type = 'email\.delivered'\) AS last_ok/);
  assert.match(f, /WHERE \(s\.last_stop IS NOT NULL AND \(s\.last_ok IS NULL OR s\.last_stop > s\.last_ok\)\)\s+OR \(p_include_unsubscribed AND public\._campaign_email_unsubscribed\(a\.email\)\);/);
  assert.match(SQL, /REVOKE ALL ON FUNCTION public\.email_suppressed_among\(text\[\], boolean\) FROM PUBLIC, anon, authenticated;\s+GRANT EXECUTE ON FUNCTION public\.email_suppressed_among\(text\[\], boolean\) TO service_role;/);
});

test('B. a fila do cron nao pega linha suprimida', () => {
  assert.match(cap('process_pending_email_queue'),
    /WHERE cr\.send_id = cs\.id AND cr\.delivered = false AND cr\.unsubscribed = false\s+AND \(cr\.deferred_until IS NULL OR cr\.deferred_until <= now\(\)\)\s+AND cr\.suppressed_at IS NULL\s+\)/);
});

test('C. linha suprimida nao conta como enviada', () => {
  assert.match(cap('email_sends_today'),
    /FROM public\.notifications n, d WHERE n\.email_sent_at >= d\.inicio\s+AND n\.email_delivery_status IS DISTINCT FROM 'deduplicated'\s+AND n\.email_delivery_status IS DISTINCT FROM 'suppressed'\)/);
  assert.match(cap('email_people_sent_today'),
    /AND NOT public\._is_urgent_email_type\(n\.type\)\s+AND n\.email_delivery_status IS DISTINCT FROM 'suppressed'\s+UNION ALL/);
});

test('D. avisos: suprimido nao sai, e sem leitura a rodada nao envia', () => {
  const s = ef('send-notification-email');
  assert.match(s, /const suppressed = await suppressedAmong\(sb, \[\.\.\.groups\.keys\(\)\]\.map\(\(id\) => memberById\.get\(id\)\?\.email\), false\)\s+if \(suppressed === null\) \{\s+return new Response\(JSON\.stringify\(\{ sent: 0, error: 'suppression_unreadable'/);
  assert.match(s, /if \(!suppressed\.has\(normalizeEmail\(memberById\.get\(recipientId\)\.email\)\)\) continue\s+await sb\.from\('notifications'\)\.update\(\{\s+email_sent_at: new Date\(\)\.toISOString\(\),\s+email_delivery_status: 'suppressed',\s+\}\)\.in\('id', items\.map\(\(n: any\) => n\.id\)\)\s+suppressedRows \+= items\.length\s+groups\.delete\(recipientId\)/);
  assert.ok(s.indexOf('suppressedAmong(sb') < s.indexOf('const orderedRecipients'), 'a supressao tem de ser lida antes de ordenar e enviar');
});

// #2586: o avulso de corpo livre a EXTERNO respeita o descadastro como a campanha; a membro e o transacional, nao.
test('E. campanha: descadastro fora do avulso, suppressed_at, e sem leitura volta para a fila', () => {
  const s = ef('send-campaign');
  assert.match(s, /const isOneOff = send\.audience_filter\?\.one_off === true/);
  assert.match(s, /const suppressedSet = await suppressedAmong\(sb, pendingRows\.map\(addressOf\), !isOneOff \|\| freeformToExternal\)\s+if \(suppressedSet === null\) \{\s+await sb\.from\('campaign_sends'\)\.update\(\{ status: 'throttled', error_log: 'suppression_unreadable' \}\)\.eq\('id', sendId\)\s+return json\(\{ error: 'suppression_unreadable', send_id: sendId \}, 503\)/);
  assert.match(s, /if \(suppressedIds\.size > 0\) \{\s+await sb\.from\('campaign_recipients'\)\.update\(\{ suppressed_at: new Date\(\)\.toISOString\(\) \}\)\.in\('id', \[\.\.\.suppressedIds\]\)/);
  assert.match(s, /if \(r\.unsubscribed \|\| r\.delivered\) continue\s+if \(suppressedIds\.has\(r\.id\)\) continue/);
  assert.ok(s.indexOf('suppressedAmong(sb') < s.indexOf("fetch('https://api.resend.com/emails'"), 'a supressao tem de ser lida antes do envio');
});

test('F. os envios em massa filtram a lista antes de enviar', () => {
  const b = ef('send-tribe-broadcast');
  assert.match(b, /const suppressedBcc = await suppressedAmong\(sb, allBccRaw, true\)\s+const allBcc = suppressedBcc === null \? allBccRaw : allBccRaw\.filter\(\(e\) => !suppressedBcc\.has\(normalizeEmail\(e\)\)\)/);
  const a = ef('send-allocation-notify');
  assert.match(a, /const suppressedAlloc = await suppressedAmong\(sb, allocated\.map\(\(m: any\) => m\.email\), false\)/);
  assert.match(a, /const emails = tribeMembers\.map\(\(m: any\) => m\.email\)\s+\.filter\(\(e: string\) => !\(suppressedAlloc && e && suppressedAlloc\.has\(normalizeEmail\(e\)\)\)\)/);
  const o = ef('send-global-onboarding');
  assert.match(o, /const suppressedOnb = await suppressedAmong\(sb, \[\.\.\.Object\.values\(grouped\)\.flatMap\(\(g\) => g\.emails\), \.\.\.mgmtEmails\], false\)/);
  assert.match(o, /const allBcc = \[\.\.\.new Set\(\[\.\.\.group\.emails, \.\.\.mgmtEmails\]\)\]\s+\.filter\(\(e\) => !\(suppressedOnb && suppressedOnb\.has\(normalizeEmail\(e\)\)\)\)/);
});

test('G. todo EF que chama o provedor esta classificado', () => {
  const senders = readdirSync(FN_DIR).filter((d) => {
    const p = join(FN_DIR, d, 'index.ts');
    return existsSync(p) && /'https:\/\/api\.resend\.com\/emails'/.test(readFileSync(p, 'utf8'));
  }).sort();
  assert.deepEqual(senders, [...CONSULTA, ...PEDIDO_PELA_PESSOA].sort(),
    'EF novo chamando o provedor: decida se ele consulta a supressao (CONSULTA) ou e link pedido pela pessoa');
  for (const n of CONSULTA) assert.match(ef(n), /await suppressedAmong\(sb, /, `${n} tem de consultar a supressao`);
  for (const n of PEDIDO_PELA_PESSOA) assert.doesNotMatch(ef(n), /suppressedAmong/, `${n} e link pedido pela pessoa e fica fora`);
  const h = readFileSync(join(FN_DIR, '_shared/suppression.ts'), 'utf8');
  assert.match(h, /if \(error \|\| !Array\.isArray\(data\)\) \{\s+console\.error\('\[suppression\] unreadable:', error\?\.message \?\? 'no value'\)\s+return null\s+\}/);
});
