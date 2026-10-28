// #2806: quem recebe push (supabase/functions/send-push/plan.ts). Cada regra tem um caso que a dispara e o
// controle positivo mostra que, sem regra nenhuma, o envio acontece.
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  planSends, isAllowedPushHost, classifyStatus, safePushPath, buildPayload, STALE_AFTER_MS,
} from '../../supabase/functions/send-push/plan.ts';

const NOW = Date.parse('2026-10-28T20:00:00Z');
const HOSTS = ['push.apple.com', 'fcm.googleapis.com', 'updates.push.services.mozilla.com', 'notify.windows.com'];
const iso = (msAgo) => new Date(NOW - msAgo).toISOString();

const notif = (over = {}) => ({
  id: 'n1', recipient_id: 'm1', type: 'curation_review_assigned', title: 'Revisao atribuida',
  link: '/admin/curatorship', created_at: iso(60_000), is_read: false, read_at: null, ...over,
});
const member = (over = {}) => ({ id: 'm1', is_active: true, notify_delivery_mode_pref: 'immediate', ...over });
const sub = (over = {}) => ({
  id: 's1', member_id: 'm1', endpoint: 'https://fcm.googleapis.com/fcm/send/abc', p256dh: 'k', auth_secret: 'a',
  created_at: iso(3_600_000 * 24), disabled_at: null, failure_count: 0, ...over,
});
const plan = (over = {}) => planSends({
  notifications: [notif()], members: [member()], prefs: [], subscriptions: [sub()], hosts: HOSTS, nowMs: NOW, ...over,
});

test('#2806 push: controle positivo, um aviso e uma inscricao geram um envio', () => {
  const { sends, skips } = plan();
  assert.equal(sends.length, 1);
  assert.equal(sends[0].subscription.id, 's1');
  assert.equal(Object.values(skips).reduce((a, b) => a + b, 0), 0);
});

test('#2806 push: aviso com mais de 1 h nao sai', () => {
  assert.equal(plan({ notifications: [notif({ created_at: iso(STALE_AFTER_MS + 1000) })] }).skips.stale, 1);
  assert.equal(plan({ notifications: [notif({ created_at: iso(STALE_AFTER_MS - 1000) })] }).sends.length, 1);
  assert.equal(plan({ notifications: [notif({ created_at: 'nao e data' })] }).skips.stale, 1, 'data ilegivel conta como velha');
});

test('#2806 push: membro inativo ou ausente nao recebe', () => {
  assert.equal(plan({ members: [member({ is_active: false })] }).skips.inactive, 1);
  assert.equal(plan({ members: [member({ is_active: null })] }).skips.inactive, 1);
  assert.equal(plan({ members: [] }).skips.inactive, 1);
});

test('#2806 push: suppress_all e tipo silenciado sao respeitados', () => {
  assert.equal(plan({ members: [member({ notify_delivery_mode_pref: 'suppress_all' })] }).skips.suppressed, 1);
  assert.equal(plan({ prefs: [{ member_id: 'm1', muted_types: ['curation_review_assigned'] }] }).skips.muted, 1);
  assert.equal(plan({ prefs: [{ member_id: 'm1', muted_types: ['outro_tipo'] }] }).sends.length, 1);
});

test('#2806 push: aviso ja lido nao sai', () => {
  assert.equal(plan({ notifications: [notif({ is_read: true })] }).skips.read, 1);
  assert.equal(plan({ notifications: [notif({ read_at: iso(1000) })] }).skips.read, 1);
});

test('#2806 push: aviso anterior a inscricao nunca vai para ela', () => {
  const r = plan({ subscriptions: [sub({ created_at: iso(30_000) })] });
  assert.equal(r.sends.length, 0);
  assert.equal(r.skips.subscriptionNewer, 1);
});

test('#2806 push: inscricao desativada ou de outro membro nao conta', () => {
  assert.equal(plan({ subscriptions: [sub({ disabled_at: iso(1000) })] }).skips.noSubscription, 1);
  assert.equal(plan({ subscriptions: [sub({ member_id: 'm2' })] }).skips.noSubscription, 1);
});

test('#2806 push: um aviso vai para cada aparelho do membro, so nos hosts da lista', () => {
  const r = plan({ subscriptions: [sub(), sub({ id: 's2', endpoint: 'https://web.push.apple.com/QK' }), sub({ id: 's3', endpoint: 'https://evil.example/x' })] });
  assert.deepEqual(r.sends.map((s) => s.subscription.id), ['s1', 's2']);
  assert.equal(r.skips.hostNotAllowed, 1);
});

test('#2806 push: lista de hosts recusa imitacao, http, porta e credencial na URL', () => {
  const ok = ['https://fcm.googleapis.com/fcm/send/a', 'https://web.push.apple.com/a', 'https://wns2-par02p.notify.windows.com/w/?token=a',
    'https://updates.push.services.mozilla.com/wpush/v2/a'];
  for (const u of ok) assert.equal(isAllowedPushHost(u, HOSTS), true, u);
  // credencial na URL montada por propriedade: o texto "usuario@host" seria lido como e-mail pela varredura de PII
  const withCreds = new URL('https://fcm.googleapis.com/a');
  withCreds.username = 'user';
  withCreds.password = 'pw';
  const bad = ['http://fcm.googleapis.com/a', 'https://fcm.googleapis.com.evil.example/a', 'https://evilpush.apple.com/a',
    'https://fcm.googleapis.com:8443/a', withCreds.href, 'nao e url', 'https://notify.windows.com.evil/a'];
  for (const u of bad) assert.equal(isAllowedPushHost(u, HOSTS), false, u);
  assert.equal(isAllowedPushHost('https://fcm.googleapis.com/a', []), false, 'lista vazia nao libera nada');
  assert.equal(isAllowedPushHost('https://web.push.apple.com/a', ['*.push.apple.com']), true, 'aceita a forma *.dominio');
});

test('#2806 push: 404 e 410 encerram a inscricao, 2xx e sucesso, o resto e falha', () => {
  assert.equal(classifyStatus(201), 'ok');
  assert.equal(classifyStatus(200), 'ok');
  assert.equal(classifyStatus(404), 'gone');
  assert.equal(classifyStatus(410), 'gone');
  for (const s of [0, 301, 400, 403, 413, 429, 500, 503]) assert.equal(classifyStatus(s), 'fail', String(s));
});

test('#2806 push: link so como caminho do proprio site', () => {
  assert.equal(safePushPath('/admin/curatorship?x=1#y'), '/admin/curatorship?x=1#y');
  for (const l of [null, '', 'https://nucleoia.vitormr.dev/x', '//evil.example/x', 'javascript:alert(1)', '/a\\b', '/a b', 'admin']) {
    assert.equal(safePushPath(l), '/notifications', String(l));
  }
});

test('#2806 push: a mensagem leva titulo, caminho e id, nunca o corpo', () => {
  const p = JSON.parse(buildPayload({ ...notif({ title: 'x'.repeat(300) }), body: 'dado do corpo' }));
  assert.deepEqual(Object.keys(p).sort(), ['tag', 'title', 'url']);
  assert.equal(p.title.length, 120);
  assert.equal(p.url, '/admin/curatorship');
  assert.equal(p.tag, 'n1');
});
