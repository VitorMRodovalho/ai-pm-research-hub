import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// WS-A1: the tribe WhatsApp GROUP link is served only via the gated
// get_tribe_group_link RPC — active + term-signed + in-that-tribe (or platform admin).
// Pre-onboarding members are blocked. Anon gets nothing.
const MIGRATION = 'supabase/migrations/20260805000183_wsA1_get_tribe_group_link.sql';
const TRIBE_PAGE = 'src/pages/tribe/[id].astro';
const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;
const svc = SUPABASE_URL && SERVICE_KEY
  ? createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } })
  : null;
const anon = SUPABASE_URL && ANON_KEY
  ? createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } })
  : null;

test('WS-A1 static: migration defines a term-gated SECDEF accessor with PUBLIC revoked', () => {
  const body = read(MIGRATION);
  assert.ok(body, 'migration present');
  assert.match(body, /CREATE FUNCTION public\.get_tribe_group_link\(p_tribe_id integer\)/, 'function defined');
  assert.match(body, /SECURITY DEFINER/, 'SECURITY DEFINER');
  assert.match(body, /member_is_pre_onboarding/, 'gates on pre-onboarding (term signed)');
  assert.match(body, /get_member_tribe/, 'gates on tribe membership');
  assert.match(body, /REVOKE ALL ON FUNCTION public\.get_tribe_group_link\(integer\) FROM PUBLIC/, 'PUBLIC revoked');
  assert.match(body, /GRANT EXECUTE ON FUNCTION public\.get_tribe_group_link\(integer\) TO authenticated, service_role/, 'granted to authenticated + service_role');
});

test('WS-A1 static: tribe page serves the link via the RPC, not a direct column read', () => {
  const body = read(TRIBE_PAGE);
  assert.ok(body, 'tribe page present');
  assert.match(body, /rpc\('get_tribe_group_link'/, 'CTA uses the gated RPC');
  assert.ok(!/_tribe\??\.whatsapp_url/.test(body), 'tribe page no longer reads _tribe.whatsapp_url');
});

test('WS-A1 live: anon cannot execute get_tribe_group_link', { skip: anon ? false : 'anon env required' }, async () => {
  const { data, error } = await anon.rpc('get_tribe_group_link', { p_tribe_id: 1 });
  // Either RLS/permission denies execution, or the SECDEF returns not_authenticated — never a link.
  if (error) {
    assert.ok(/permission|denied|not.*exist/i.test(error.message), `anon blocked: ${error.message}`);
  } else {
    assert.equal(data?.success, false, 'anon must not get success');
    assert.ok(!data?.whatsapp_url, 'anon must not receive a link');
  }
});

test('WS-A1 live: function runs and fails closed without an authenticated member', { skip: svc ? false : 'Supabase env required' }, async () => {
  // service_role has no auth.uid() → not_authenticated (proves the function executes
  // and fails closed). The per-reason gate branches (pre_onboarding / not_in_tribe /
  // success) are verified by impersonated set_config JWT during manual QA, since
  // supabase-js cannot set request.jwt.claims + call the RPC in one transaction.
  const { data, error } = await svc.rpc('get_tribe_group_link', { p_tribe_id: 1 });
  assert.ok(!error, `service_role should execute: ${error?.message}`);
  assert.equal(data?.success, false, 'no auth.uid() → not a success');
  assert.equal(data?.reason, 'not_authenticated', 'fails closed with not_authenticated');
  assert.ok(!data?.whatsapp_url, 'never returns a link without an authenticated member');
});
