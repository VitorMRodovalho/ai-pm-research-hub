import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// WS-A2: tribes.whatsapp_url and drive_url must not be SELECT-able by anon OR
// authenticated via a direct table read. They are served only through SECURITY
// DEFINER RPCs (function owner bypasses column grants). This closes the
// authenticated-pre-onboarding direct-read bypass the gated RPC alone cannot stop.
const MIGRATION = 'supabase/migrations/20260805000184_wsA2_tribes_anon_column_lockdown.sql';
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

test('WS-A2 static: migration revokes sensitive columns and re-grants only safe ones', () => {
  const body = read(MIGRATION);
  assert.ok(body, 'migration present');
  assert.match(body, /REVOKE SELECT ON public\.tribes FROM anon, authenticated/, 'drops table-level SELECT');
  assert.match(body, /REVOKE SELECT \(whatsapp_url, drive_url\) ON public\.tribes FROM anon, authenticated/, 'drops column-level SELECT on sensitive cols');
  const flat = body.replace(/\s+/g, ' ');
  const grant = flat.match(/GRANT SELECT \(([^)]*)\) ON public\.tribes TO anon, authenticated/);
  assert.ok(grant, 're-grants explicit safe columns to anon/authenticated');
  assert.ok(!/whatsapp_url/.test(grant[1]), 're-grant must not include whatsapp_url');
  assert.ok(!/drive_url/.test(grant[1]), 're-grant must not include drive_url');
});

test('WS-A2 live: anon cannot SELECT whatsapp_url/drive_url but can read safe columns', { skip: anon ? false : 'anon env required' }, async () => {
  const denied = await anon.from('tribes').select('whatsapp_url').limit(1);
  assert.ok(denied.error, 'anon SELECT whatsapp_url must error (permission denied for column)');
  const deniedDrive = await anon.from('tribes').select('drive_url').limit(1);
  assert.ok(deniedDrive.error, 'anon SELECT drive_url must error');
  const ok = await anon.from('tribes').select('id, name, is_active').limit(1);
  assert.ok(!ok.error, `anon SELECT safe columns must succeed: ${ok.error?.message}`);
});

test('WS-A2 live: SECDEF accessor still serves the link post-lockdown (owner bypasses column grants)', { skip: svc ? false : 'Supabase env required' }, async () => {
  // service_role has no auth.uid() → not_authenticated, but the function executes
  // (it would error if the owner had lost column access).
  const { data, error } = await svc.rpc('get_tribe_group_link', { p_tribe_id: 1 });
  assert.ok(!error, `gated RPC executes post-lockdown: ${error?.message}`);
  assert.equal(typeof data?.success, 'boolean', 'gated RPC returns a structured verdict');
});
