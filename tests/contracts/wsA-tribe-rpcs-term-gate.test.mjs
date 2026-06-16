import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';

// WS-A3: enforce the volunteer-term gate on tribe access.
//  - select_tribe blocks pre-onboarding members (the access-granting action).
//  - exec_tribe_dashboard no longer returns whatsapp_url (group link is served only
//    by the term-gated get_tribe_group_link RPC). drive_url stays.
//  - TribeDashboardIsland renders the WhatsApp link from the gated RPC, not the payload.
const MIGRATION = 'supabase/migrations/20260805000185_wsA3_tribe_rpcs_term_gate.sql';
const ISLAND = 'src/components/islands/TribeDashboardIsland.tsx';
const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');

test('WS-A3 static: select_tribe gates on member_is_pre_onboarding', () => {
  const body = read(MIGRATION);
  assert.ok(body, 'migration present');
  const sel = body.slice(body.indexOf('FUNCTION public.select_tribe'), body.indexOf('FUNCTION public.exec_tribe_dashboard'));
  assert.ok(sel.length > 0, 'select_tribe block found');
  assert.match(sel, /member_is_pre_onboarding/, 'select_tribe checks pre-onboarding');
  assert.match(sel, /Assine o termo de voluntário/, 'returns the term-required error');
});

test('WS-A3 static: exec_tribe_dashboard drops whatsapp_url but keeps drive_url', () => {
  const body = read(MIGRATION);
  const exec = body.slice(body.indexOf('FUNCTION public.exec_tribe_dashboard'));
  assert.ok(exec.length > 0, 'exec_tribe_dashboard block found');
  // the tribe JSON must not surface the group link any more
  assert.ok(!/'whatsapp_url',\s*v_tribe\.whatsapp_url/.test(exec), 'whatsapp_url removed from the tribe JSON');
  assert.match(exec, /'drive_url',\s*v_tribe\.drive_url/, 'drive_url is preserved');
});

test('WS-A3 static: dashboard island fetches the gated link, not the payload field', () => {
  const body = read(ISLAND);
  assert.ok(body, 'island present');
  assert.match(body, /rpc\('get_tribe_group_link'/, 'island uses the gated RPC');
  assert.ok(!/tribe\.whatsapp_url/.test(body), 'island no longer reads tribe.whatsapp_url from the payload');
});
