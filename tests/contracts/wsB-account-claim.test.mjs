import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// WS-B: self-service account claim for guests whose login email differs from the VEP
// email they applied with. Security invariant: proof-of-possession is sent to the
// MEMBER's registered address (not the claimant's), so only someone controlling that
// inbox can complete the claim — preserving the R3-a / Paulo Alves anti-hijack lesson.
const MIGRATION = 'supabase/migrations/20260805000186_wsB_account_claim_rpcs.sql';
const EF = 'supabase/functions/send-account-claim/index.ts';
const PAGE_START = 'src/pages/claim/start.astro';
const PAGE_CONFIRM = 'src/pages/claim/index.astro';
const NAV = 'src/components/nav/Nav.astro';
const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const svc = SUPABASE_URL && SERVICE_KEY
  ? createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } })
  : null;

test('WS-B static: migration defines both SECDEF claim RPCs with the security properties', () => {
  const body = read(MIGRATION);
  assert.ok(body, 'migration present');
  assert.match(body, /FUNCTION public\.request_account_claim\(p_identifier text\)/, 'request RPC defined');
  assert.match(body, /FUNCTION public\.confirm_account_claim\(p_token text\)/, 'confirm RPC defined');
  // proof-of-possession goes to the MEMBER's email (target_email := member email), never the claimant's
  assert.match(body, /target_email[\s\S]*v_target_email/, 'verification targets the member email');
  // anti-hijack: only UNCLAIMED members can be targeted, and confirm revalidates it (TOCTOU)
  assert.match(body, /auth_id IS NULL/, 'only unclaimed members targeted');
  assert.match(body, /IF v_member\.auth_id IS NOT NULL THEN[\s\S]*already_claimed/, 'confirm revalidates unclaimed (TOCTOU)');
  // anti-enumeration generic response + rate limiting + short TTL
  assert.match(body, /v_generic/, 'generic anti-enumeration response');
  assert.match(body, /rate_limited/, 'rate limiting present');
  assert.match(body, /now\(\) \+ interval '1 hour'/, '1-hour token TTL');
  // audit + grants
  assert.match(body, /members\.auth_id\.claimed_self_service/, 'audit-logged');
  assert.match(body, /REVOKE ALL ON FUNCTION public\.request_account_claim\(text\) FROM PUBLIC/, 'request: PUBLIC revoked');
  assert.match(body, /GRANT EXECUTE ON FUNCTION public\.confirm_account_claim\(text\) TO anon, authenticated, service_role/, 'confirm: anon-capable (token is the credential)');
});

test('WS-B static: edge function is service-role gated and emails the member address', () => {
  const body = read(EF);
  assert.ok(body, 'edge function present');
  assert.match(body, /service_role required/, 'service-role gate');
  assert.match(body, /purpose.*account_claim|'account_claim'/, 'scoped to account_claim rows');
  assert.match(body, /api\.resend\.com/, 'sends via Resend');
  assert.match(body, /dispatched_at/, 'marks dispatched_at (idempotent)');
  assert.match(body, /\/claim\?token=/, 'links to the confirm page');
});

test('WS-B static: claim pages + Nav CTA wired', () => {
  const start = read(PAGE_START);
  const confirm = read(PAGE_CONFIRM);
  const nav = read(NAV);
  assert.match(start, /rpc\('request_account_claim'/, 'start page calls request RPC');
  assert.match(confirm, /rpc\('confirm_account_claim'/, 'confirm page calls confirm RPC');
  assert.match(nav, /\/claim\/start/, 'Nav guest CTA links to the claim flow');
  assert.match(nav, /claim\.cta/, 'Nav exposes the claim CTA label');
});

test('WS-B live: both RPCs exist and fail closed for an unauthenticated/invalid caller', { skip: svc ? false : 'Supabase env required' }, async () => {
  // service_role has no auth.uid() → request must report not_authenticated (fails closed)
  const r = await svc.rpc('request_account_claim', { p_identifier: 'nobody@example.invalid' });
  assert.ok(!r.error, `request executes: ${r.error?.message}`);
  assert.equal(r.data?.success, false, 'no auth.uid() → not a success');
  assert.equal(r.data?.reason, 'not_authenticated', 'request fails closed');

  // confirm with a bogus token → invalid, never links anything
  const c = await svc.rpc('confirm_account_claim', { p_token: 'bogus-token-0000000000000000000000' });
  assert.ok(!c.error, `confirm executes: ${c.error?.message}`);
  assert.equal(c.data?.success, false, 'bogus token is not a success');
  assert.equal(c.data?.reason, 'invalid', 'confirm fails closed on bogus token');
});
