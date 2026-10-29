// tests/contracts/2806-send-push-ef.test.mjs
/**
 * #2806, envio do push (supabase/functions/send-push/index.ts). Quem recebe esta testado em
 * tests/edge-functions/send-push-plan.test.mjs; este guard prende a LIGACAO no handler, que teste de unidade nao ve:
 *
 *   1. o portao de service_role e a primeira instrucao, antes de qualquer segredo ou consulta;
 *   2. sem chaves VAPID ou sem a lista de hosts de push, a EF devolve ANTES de reivindicar a fila;
 *   3. a reivindicacao e um UPDATE condicional (push_dispatched_at IS NULL) dos avisos imediatos, e e o RETORNO
 *      dele, nao outra leitura, que alimenta planSends: duas execucoes simultaneas nunca enviam o mesmo aviso;
 *   4. o POST para o servico de push nao segue redirecionamento (sairia da lista de hosts);
 *   5. a resposta de sucesso so tem contagens;
 *   6. a resposta 500 leva so o codigo do erro: a mensagem vai para o log (CodeQL js/stack-trace-exposure).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const SRC = maskJsComments(readFileSync(resolve(process.cwd(), 'supabase/functions/send-push/index.ts'), 'utf8'));
const HANDLER = SRC.slice(SRC.indexOf('Deno.serve(async (req) => {'));
const CLAIM = /const \{ data: claimed, error: claimErr \} = await sb\s+\.from\('notifications'\)\s+\.update\(\{ push_dispatched_at: new Date\(\)\.toISOString\(\) \}\)\s+\.eq\('delivery_mode', IMMEDIATE\)\s+\.is\('push_dispatched_at', null\)\s+\.select\(/;

test('#2806 send-push: o portao de service_role e a primeira instrucao do handler', () => {
  assert.ok(HANDLER.length > 0, 'Deno.serve ausente');
  assert.match(HANDLER, /^Deno\.serve\(async \(req\) => \{\s+if \(!\(await isServiceRoleToken\(SUPABASE_URL, bearerFrom\(req\)\)\)\) \{\s+return json\(\{ error: 'unauthorized', detail: 'service-role only' \}, 401\)/);
});

test('#2806 send-push: sem chaves VAPID ou sem lista de hosts, sai antes de reivindicar', () => {
  const claimAt = HANDLER.search(CLAIM);
  assert.ok(claimAt > 0, 'reivindicacao nao encontrada');
  const vapid = HANDLER.search(/if \(!vapidPublic \|\| !vapidPrivate \|\| !vapidSubject\) return json\(\{ error: 'vapid_not_configured' \}, 500\)/);
  const hosts = HANDLER.search(/if \(hosts\.length === 0\) return json\(\{ error: 'push_service_hosts_missing' \}, 500\)/);
  assert.ok(vapid > 0 && vapid < claimAt, 'o teste das chaves tem de vir antes da reivindicacao');
  assert.ok(hosts > 0 && hosts < claimAt, 'o teste da lista de hosts tem de vir antes da reivindicacao');
});

test('#2806 send-push: a reivindicacao condicional dos imediatos e o que alimenta o plano', () => {
  assert.match(SRC, /const IMMEDIATE = 'transactional_immediate'\n/);
  assert.match(HANDLER, CLAIM);
  assert.equal(HANDLER.split(".from('notifications')").length - 1, 1, 'uma unica operacao sobre notifications: a reivindicacao');
  assert.match(HANDLER, /const notifications = \(claimed \?\? \[\]\) as PendingNotification\[\]/);
  assert.match(HANDLER, /planSends\(\{\s+notifications,/);
});

test('#2806 send-push: o POST nao segue redirecionamento', () => {
  const start = SRC.indexOf('const res = await fetch(s.subscription.endpoint, {');
  assert.ok(start > 0, 'fetch do envio nao encontrado');
  const call = SRC.slice(start, SRC.indexOf('\n    })', start));
  assert.match(call, /method: 'POST',/);
  assert.match(call, /redirect: 'manual',/);
});

test('#2806 send-push: a resposta de sucesso so tem contagens', () => {
  const start = HANDLER.indexOf('return json({\n      claimed: notifications.length,');
  assert.ok(start > 0, 'resposta de sucesso nao encontrada');
  const block = HANDLER.slice(start, HANDLER.indexOf('\n    })', start));
  const keys = [...block.matchAll(/^\s{6}(\w+)[:,]/gm)].map((m) => m[1]).sort();
  assert.deepEqual(keys, ['bookkeeping_errors', 'claimed', 'failed', 'gone', 'sent', 'skips']);
});

test('#2806 send-push: a resposta 500 nao leva a mensagem do erro, que vai para o log', () => {
  const start = HANDLER.lastIndexOf('} catch (e) {');
  assert.ok(start > 0, 'catch do handler nao encontrado');
  assert.match(HANDLER.slice(start), /^\} catch \(e\) \{\s+const m = e instanceof Error \? e\.message : String\(e\)\s+console\.error\('\[send-push\] FATAL:', m\)\s+return json\(\{ error: 'send_push_failed' \}, 500\)\s+\}\s+\}\)\s*$/);
  // e nenhuma resposta do handler (o argumento inteiro de cada json(), fora das strings) cita o erro, a mensagem
  // dele, o stack ou String(...)
  const code = HANDLER.replace(/'[^'\n]*'/g, "''").replace(/`[^`]*`/g, '``');
  const calls = [];
  for (let i = code.indexOf('json('); i >= 0; i = code.indexOf('json(', i + 1)) {
    let depth = 0, j = i + 4;
    do { if (code[j] === '(') depth++; else if (code[j] === ')') depth--; j++; } while (depth > 0 && j < code.length);
    calls.push(code.slice(i, j));
  }
  assert.ok(calls.length >= 5, `respostas do handler: ${calls.length}`);
  for (const c of calls) assert.doesNotMatch(c, /\be\b|\bm\b|\.message|String\(|\.stack/, c);
});
