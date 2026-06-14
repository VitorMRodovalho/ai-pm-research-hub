import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// Regression lock for the #676 Slice 4 (A) security fix: the v_cron heuristic must NOT
// rely on current_user (always = SECDEF owner 'postgres'), which made the manage_platform/
// leader gate a no-op for authenticated callers. The reliable discriminator is the request
// role GUC, centralized in _recurring_request_is_rest().
const MIG = 'supabase/migrations/20260805000167_676_secfix_role_gate_plus_reconcile_cron.sql';
const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const anonGated = !!(SUPABASE_URL && ANON_KEY);
const skipMsg = 'Supabase URL + anon key required';

test('#676 secfix static: all 6 gated RPCs use the role-GUC discriminator', () => {
  const body = read(MIG);
  assert.ok(body, 'migration present');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\._recurring_request_is_rest/);
  assert.match(body, /current_setting\('role', true\), ''\) IN \('authenticated','anon'\)/, 'role-GUC based');
  // every gated function must adopt the fixed discriminator (reconcile, reconcile_all,
  // drift, admin_list, update, create = 6 occurrences)
  const occurrences = (body.match(/v_cron := NOT public\._recurring_request_is_rest\(\);/g) || []).length;
  assert.equal(occurrences, 6, `expected 6 fixed gates, found ${occurrences}`);
  // the broken pattern must not survive as executable code in any of these functions
  assert.ok(!/v_cron := \(current_setting\('role', true\) IN/.test(body), 'old current_user heuristic removed');
});

test('#676 secfix static: reconcile cron wrapper + weekly schedule present', () => {
  const body = read(MIG);
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.reconcile_recurring_meetings_cron/);
  assert.match(body, /cron\.schedule\(\s*'reconcile-recurring-meetings-weekly'/);
  assert.match(body, /reconcile_recurring_meetings_cron\(\) FROM PUBLIC, anon, authenticated/, 'cron wrapper not REST-callable');
  assert.match(body, /admin_audit_log/, 'cron run is logged');
});

test('#676 secfix live: anon is denied on read + write RPCs (gate enforced, not just grants)', { skip: anonGated ? false : skipMsg }, async () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });

  const r1 = await anon.rpc('get_recurring_meeting_admin_list');
  assert.ok(r1.error, 'anon cannot read admin list');

  const r2 = await anon.rpc('get_recurring_meeting_drift');
  assert.ok(r2.error, 'anon cannot read drift');

  const r3 = await anon.rpc('update_recurring_meeting_rule', {
    p_rule_id: '00000000-0000-4000-8000-0000000000aa', p_patch: { status: 'paused' },
  });
  assert.ok(r3.error, 'anon cannot update a rule');

  const r4 = await anon.rpc('create_recurring_meeting_rule', {
    p_payload: { initiative_id: '00000000-0000-4000-8000-0000000000aa', day_of_week: 1, time_start: '10:00', frequency: 'weekly' },
  });
  assert.ok(r4.error, 'anon cannot create a rule');

  const r5 = await anon.rpc('reconcile_recurring_meetings_cron');
  assert.ok(r5.error, 'anon cannot trigger the cron wrapper');
});
