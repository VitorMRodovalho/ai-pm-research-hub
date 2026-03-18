import test from 'node:test';
import assert from 'node:assert/strict';
import { parseWebhookEvent, VALID_WEBHOOK_EVENTS } from '../../supabase/functions/_shared/webhook-parser.ts';

test('VALID_WEBHOOK_EVENTS has 5 event types', () => {
  assert.equal(VALID_WEBHOOK_EVENTS.length, 5);
});

test('parseWebhookEvent: delivered event', () => {
  const r = parseWebhookEvent({
    type: 'email.delivered',
    data: { email_id: 'abc123', to: ['user@example.com'] },
  });
  assert.equal(r.eventType, 'email.delivered');
  assert.equal(r.resendId, 'abc123');
  assert.equal(r.recipientEmail, 'user@example.com');
  assert.equal(r.isValid, true);
  assert.equal(r.bounceType, undefined);
});

test('parseWebhookEvent: opened event', () => {
  const r = parseWebhookEvent({
    type: 'email.opened',
    data: { email_id: 'xyz', to: ['a@b.com'] },
  });
  assert.equal(r.isValid, true);
  assert.equal(r.eventType, 'email.opened');
});

test('parseWebhookEvent: clicked event', () => {
  const r = parseWebhookEvent({
    type: 'email.clicked',
    data: { email_id: 'id1', to: ['c@d.com'] },
  });
  assert.equal(r.isValid, true);
});

test('parseWebhookEvent: bounced event with bounce type', () => {
  const r = parseWebhookEvent({
    type: 'email.bounced',
    data: { email_id: 'bounce1', to: ['bad@host.com'], bounce: { type: 'hard' } },
  });
  assert.equal(r.isValid, true);
  assert.equal(r.bounceType, 'hard');
});

test('parseWebhookEvent: bounced event without bounce type defaults to unknown', () => {
  const r = parseWebhookEvent({
    type: 'email.bounced',
    data: { email_id: 'bounce2', to: ['x@y.com'] },
  });
  assert.equal(r.bounceType, 'unknown');
});

test('parseWebhookEvent: complained event', () => {
  const r = parseWebhookEvent({
    type: 'email.complained',
    data: { email_id: 'comp1', to: ['z@w.com'] },
  });
  assert.equal(r.isValid, true);
});

test('parseWebhookEvent: unknown event type is invalid', () => {
  const r = parseWebhookEvent({
    type: 'email.unknown',
    data: { email_id: 'u1', to: ['a@b.com'] },
  });
  assert.equal(r.isValid, false);
});

test('parseWebhookEvent: missing resend_id is invalid', () => {
  const r = parseWebhookEvent({
    type: 'email.delivered',
    data: { to: ['a@b.com'] },
  });
  assert.equal(r.isValid, false);
});

test('parseWebhookEvent: empty payload', () => {
  const r = parseWebhookEvent({});
  assert.equal(r.isValid, false);
  assert.equal(r.eventType, '');
  assert.equal(r.resendId, undefined);
});
