import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// #684 regression lock: the anon-reachable SECDEF functions that carried the always-true
// current_user bypass (the systemic case behind #676/#683) must (a) use the role-GUC
// discriminator and (b) deny anon.
const MIG = 'supabase/migrations/20260805000168_684_secfix_role_gate_anon_reachable.sql';
const MIG_MED = 'supabase/migrations/20260805000169_684_secfix_authenticated_only_md.sql';
const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const anonGated = !!(SUPABASE_URL && ANON_KEY);
const skipMsg = 'Supabase URL + anon key required';

const FIXED = [
  'member_add_alternate_email', 'member_list_emails', 'member_remove_alternate_email',
  'member_set_primary_email', 'member_update_alternate_email_kind', 'detect_inactive_members',
];

test('#684 static: generic role-GUC discriminator + 6 functions adopt it', () => {
  const body = read(MIG);
  assert.ok(body, 'migration present');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\._request_is_rest_caller/);
  assert.match(body, /current_setting\('role', true\), ''\) IN \('authenticated','anon'\)/);
  // every fixed function re-creates with the role-GUC flag (6 service-role + 1 cron-context wording)
  const svc = (body.match(/:= NOT public\._request_is_rest_caller\(\);/g) || []).length;
  assert.equal(svc, 6, `expected 6 fixed gates, found ${svc}`);
  // the broken heuristic must not survive as executable code (comment mentions it; code must not)
  assert.ok(!/THEN\s*\n\s*v_is_service_role := true;/.test(body), 'old member-email bypass branch removed');
  assert.ok(!/v_cron_context := \(current_setting/.test(body), 'old detect_inactive bypass removed');
  // anon revoked on all six
  for (const fn of FIXED) {
    assert.match(body, new RegExp(`REVOKE EXECUTE ON FUNCTION public\\.${fn}\\(`), `anon revoked on ${fn}`);
  }
});

test('#684 static: the 3 authenticated-only MED functions also adopt the role-GUC discriminator', () => {
  const body = read(MIG_MED);
  assert.ok(body, 'follow-up migration present');
  const occ = (body.match(/v_cron_context := NOT public\._request_is_rest_caller\(\);/g) || []).length;
  assert.equal(occ, 3, `expected 3 fixed gates, found ${occ}`);
  assert.ok(!/v_cron_context := \(current_setting/.test(body), 'old current_user heuristic removed');
  for (const fn of ['auto_promote_eligible_leads_for_cycle', 'compute_ai_calibration_stats', 'list_ai_calibration_runs']) {
    assert.match(body, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}\\(`), `${fn} re-emitted`);
  }
});

test('#684 live: anon cannot reach the member-email / inactive-detection functions', { skip: anonGated ? false : skipMsg }, async () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const fake = '00000000-0000-4000-8000-0000000000aa';

  const calls = [
    ['member_set_primary_email', { p_member_id: fake, p_email: 'x@y.z' }],
    ['member_add_alternate_email', { p_member_id: fake, p_email: 'x@y.z', p_kind: 'personal' }],
    ['member_remove_alternate_email', { p_member_id: fake, p_email: 'x@y.z' }],
    ['member_update_alternate_email_kind', { p_member_id: fake, p_email: 'x@y.z', p_new_kind: 'other' }],
    ['member_list_emails', { p_member_id: fake }],
    ['detect_inactive_members', {}],
  ];
  for (const [fn, args] of calls) {
    const { error } = await anon.rpc(fn, args);
    assert.ok(error, `anon must be denied on ${fn}`);
  }
});
