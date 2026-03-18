import test from 'node:test';
import assert from 'node:assert/strict';

/**
 * Integration smoke tests for deployed Edge Functions.
 * Requires: SUPABASE_URL + SUPABASE_ANON_KEY env vars.
 * Safe operations only — no side effects.
 *
 * Skip in CI: these require network access to deployed EFs.
 */

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;

const canRun = !!(SUPABASE_URL && SUPABASE_ANON_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_ANON_KEY required for smoke tests';

async function efPost(slug, body = {}) {
  const url = `${SUPABASE_URL}/functions/v1/${slug}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
    },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = null; }
  return { status: res.status, json, text };
}

test('smoke: sync-credly-all rejects anon token', { skip: !canRun && skipMsg }, async () => {
  const { status } = await efPost('sync-credly-all', {});
  // Anon key should be rejected (401 or 403)
  assert.ok([401, 403].includes(status), `Expected 401/403, got ${status}`);
});

test('smoke: verify-credly rejects invalid member_id', { skip: !canRun && skipMsg }, async () => {
  const { status, json } = await efPost('verify-credly', { member_id: '00000000-0000-0000-0000-000000000000' });
  // Should return 400 (no Credly URL) or 500 (member not found)
  assert.ok([400, 500].includes(status), `Expected 400/500, got ${status}`);
  assert.ok(json !== null, 'Response should be valid JSON');
});

test('smoke: resend-webhook handles unknown event', { skip: !canRun && skipMsg }, async () => {
  const { status, json } = await efPost('resend-webhook', { type: 'test.ping', data: {} });
  // Webhook handler should accept the request (200) or reject missing fields (400)
  assert.ok([200, 400].includes(status), `Expected 200/400, got ${status}`);
  assert.ok(json !== null, 'Response should be valid JSON');
});

test('smoke: send-campaign rejects anon token', { skip: !canRun && skipMsg }, async () => {
  const { status } = await efPost('send-campaign', {});
  assert.ok([401, 403].includes(status), `Expected 401/403, got ${status}`);
});

test('smoke: get-comms-metrics responds', { skip: !canRun && skipMsg }, async () => {
  const { status, json } = await efPost('get-comms-metrics', {});
  // JWT-verified: anon key should work for read-only
  assert.ok([200, 405].includes(status), `Expected 200/405, got ${status}`);
});
