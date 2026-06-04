import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

// p282 #411 Wave 2 — interview-invite cron automation
//   2a: notify_selection_cutoff_approved cron-aware gate (mig 105) + _selection_cutoff_pending_cron
//       + get_cutoff_dispatch_health (mig 106)
//   2b: _selection_stuck_scheduled_rescue_cron (mig 107)

const MIG105 = 'supabase/migrations/20260805000105_p282_411_w2a_notify_cutoff_cron_aware_gate.sql';
const MIG106 = 'supabase/migrations/20260805000106_p282_411_w2a_cutoff_pending_cron_and_health.sql';
const MIG107 = 'supabase/migrations/20260805000107_p282_411_w2b_stuck_scheduled_rescue_cron.sql';

for (const p of [MIG105, MIG106, MIG107]) {
  if (!existsSync(p)) throw new Error(`missing migration ${p}`);
}
const M105 = readFileSync(MIG105, 'utf8');
const M106 = readFileSync(MIG106, 'utf8');
const M107 = readFileSync(MIG107, 'utf8');

describe('p282 #411 Wave 2a — notify cron-aware gate (mig 105)', () => {
  it('body-only CREATE OR REPLACE (same signature, no DROP — SEDIMENT-238.C)', () => {
    assert.match(M105, /CREATE OR REPLACE FUNCTION public\.notify_selection_cutoff_approved\(p_application_id uuid\)/);
    assert.doesNotMatch(M105, /DROP FUNCTION[^;]*notify_selection_cutoff_approved/);
    assert.match(M105, /SET search_path = public/);
  });
  it('ADR-0028 cron bypass: no-JWT or service_role context skips the per-caller gate', () => {
    assert.match(M105, /current_setting\('request\.jwt\.claims', true\) IS NULL OR auth\.role\(\) = 'service_role'/);
    assert.match(M105, /v_is_cron := true/);
    assert.match(M105, /IF NOT v_is_cron THEN/);
  });
  it('authenticated ghost still RAISEs (member not found)', () => {
    assert.match(M105, /RAISE EXCEPTION 'Unauthorized: member not found'/);
  });
  it('preserves the manual authority gate (committee lead OR manage_member)', () => {
    assert.match(M105, /can_by_member\(v_caller\.id, 'manage_member'::text\)/);
    assert.match(M105, /role = 'lead'/);
  });
  it('audit metadata gains dispatch_source (cron|manual); actor_id stays v_caller.id', () => {
    assert.match(M105, /'dispatch_source', CASE WHEN v_is_cron THEN 'cron' ELSE 'manual' END/);
    assert.match(M105, /v_caller\.id,\s*\n\s*'selection\.cutoff_approved_email_dispatched'/);
  });
  it('preserves idempotency early-return + LRD routing + campaign_send_one_off', () => {
    assert.match(M105, /reason', 'already_sent'/);
    assert.match(M105, /selection_dispatch_url_log/);
    assert.match(M105, /campaign_send_one_off/);
  });
});

describe('p282 #411 Wave 2a — cutoff-pending cron + health RPC (mig 106)', () => {
  it('_selection_cutoff_pending_cron is SECDEF search_path=\'\' service_role-only', () => {
    assert.match(M106, /CREATE OR REPLACE FUNCTION public\._selection_cutoff_pending_cron\(\)/);
    assert.match(M106, /SECURITY DEFINER\s*\n\s*SET search_path = ''/);
    assert.match(M106, /GRANT EXECUTE ON FUNCTION public\._selection_cutoff_pending_cron\(\) TO service_role/);
    assert.match(M106, /REVOKE ALL ON FUNCTION public\._selection_cutoff_pending_cron\(\) FROM PUBLIC, anon, authenticated/);
  });
  it('STRICT above-target predicate + pre-flight idempotency + LIMIT 50', () => {
    assert.match(M106, /a\.objective_score_avg >= a\.pert_target_score/);
    assert.match(M106, /a\.cutoff_approved_email_sent_at IS NULL/);
    assert.match(M106, /c\.status = 'open'/);
    assert.match(M106, /LIMIT 50/);
  });
  it('per-row BEGIN/EXCEPTION isolation calling notify_selection_cutoff_approved', () => {
    assert.match(M106, /PERFORM public\.notify_selection_cutoff_approved\(v_app\.app_id\)/);
    assert.match(M106, /BEGIN[\s\S]*?EXCEPTION WHEN OTHERS THEN[\s\S]*?v_errors := v_errors \+ 1/);
  });
  it('aggregate audit row selection.cutoff_pending_cron_run (actor_id NULL)', () => {
    assert.match(M106, /'selection\.cutoff_pending_cron_run'/);
    assert.match(M106, /VALUES \(\s*\n\s*NULL, 'selection\.cutoff_pending_cron_run'/);
  });
  it('scheduled daily 14:00 UTC', () => {
    assert.match(M106, /cron\.schedule\(\s*\n?\s*'selection-cutoff-pending-daily',\s*\n?\s*'0 14 \* \* \*'/);
  });
  it('get_cutoff_dispatch_health gated on view_internal_analytics + reads BOTH cron actions', () => {
    assert.match(M106, /CREATE OR REPLACE FUNCTION public\.get_cutoff_dispatch_health\(\)/);
    assert.match(M106, /can_by_member\(v_caller_id, 'view_internal_analytics'\)/);
    assert.match(M106, /selection\.cutoff_pending_cron_run/);
    assert.match(M106, /selection\.stuck_rescue_cron_run/);
    assert.match(M106, /health_signal/);
  });
});

describe('p282 #411 Wave 2b — stuck-scheduled rescue cron (mig 107)', () => {
  it('_selection_stuck_scheduled_rescue_cron is SECDEF search_path=\'\' service_role-only', () => {
    assert.match(M107, /CREATE OR REPLACE FUNCTION public\._selection_stuck_scheduled_rescue_cron\(\)/);
    assert.match(M107, /SECURITY DEFINER\s*\n\s*SET search_path = ''/);
    assert.match(M107, /GRANT EXECUTE ON FUNCTION public\._selection_stuck_scheduled_rescue_cron\(\) TO service_role/);
  });
  it('48h grace + app.status=interview_scheduled (matches rescue RPC guard) + LIMIT 20', () => {
    assert.match(M107, /a\.status = 'interview_scheduled'/);
    assert.match(M107, /si\.scheduled_at < now\(\) - interval '48 hours'/);
    assert.match(M107, /si\.conducted_at IS NULL/);
    assert.match(M107, /LIMIT 20/);
  });
  it('per-row BEGIN/EXCEPTION calling selection_rescue_stuck_interview', () => {
    assert.match(M107, /PERFORM public\.selection_rescue_stuck_interview\(v_app\.app_id\)/);
    assert.match(M107, /EXCEPTION WHEN OTHERS THEN[\s\S]*?v_errors := v_errors \+ 1/);
  });
  it('aggregate audit row selection.stuck_rescue_cron_run + scheduled 15:00 UTC', () => {
    assert.match(M107, /'selection\.stuck_rescue_cron_run'/);
    assert.match(M107, /cron\.schedule\(\s*\n?\s*'selection-stuck-scheduled-rescue-daily',\s*\n?\s*'0 15 \* \* \*'/);
  });
});
