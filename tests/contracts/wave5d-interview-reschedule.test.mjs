/**
 * Wave 5d (p86) — Interview Reschedule Flow contract.
 *
 * Spec-grep style: walks the two migration files and asserts the V4 + email
 * dispatch + state guards present in the design.
 *
 * Migrations:
 *   - supabase/migrations/20260516320000_p86_wave5d_interview_reschedule.sql
 *   - supabase/migrations/20260516330000_p86_wave5d_dashboard_returns_interview_status.sql
 *
 * Invariants asserted:
 *   - Schema additions: 4 interview_* columns on selection_applications
 *   - CHECK constraint values + FK to members
 *   - Partial index on interview_status (active rows only)
 *   - campaign_template seed slug='interview_reschedule_request' with 3 langs
 *   - RPC request_interview_reschedule SECURITY DEFINER + search_path pinned
 *   - V4 authority: committee lead OR can_by_member('manage_member')
 *   - State guard: interview_pending OR interview_scheduled
 *   - Email dispatch via campaign_send_one_off (no new EF)
 *   - GRANT EXECUTE to authenticated only
 *   - get_selection_dashboard exposes interview_status + reschedule_reason fields
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIG_PATH = resolve(
  ROOT,
  'supabase/migrations/20260516320000_p86_wave5d_interview_reschedule.sql'
);
const DASHBOARD_MIG_PATH = resolve(
  ROOT,
  'supabase/migrations/20260516330000_p86_wave5d_dashboard_returns_interview_status.sql'
);
const sql = readFileSync(MIG_PATH, 'utf8');
const dashSql = readFileSync(DASHBOARD_MIG_PATH, 'utf8');

test('Wave 5d: selection_applications gains 4 interview_* columns', () => {
  assert.match(sql, /ADD COLUMN IF NOT EXISTS interview_status text NOT NULL DEFAULT 'none'/i);
  assert.match(sql, /ADD COLUMN IF NOT EXISTS interview_reschedule_reason text/i);
  assert.match(sql, /ADD COLUMN IF NOT EXISTS interview_reschedule_requested_at timestamptz/i);
  assert.match(sql, /ADD COLUMN IF NOT EXISTS interview_reschedule_requested_by uuid/i);
});

test('Wave 5d: interview_status CHECK constraint enumerates 5 states', () => {
  assert.match(
    sql,
    /CHECK \(interview_status IN \('none','scheduled','needs_reschedule','completed','rescheduled'\)\)/i
  );
});

test('Wave 5d: requested_by FK to members with ON DELETE SET NULL', () => {
  assert.match(
    sql,
    /FOREIGN KEY \(interview_reschedule_requested_by\) REFERENCES public\.members\(id\) ON DELETE SET NULL/i
  );
});

test('Wave 5d: partial index only on non-default rows', () => {
  assert.match(
    sql,
    /CREATE INDEX IF NOT EXISTS ix_selection_applications_interview_status_active[\s\S]*?WHERE interview_status <> 'none'/i
  );
});

test('Wave 5d: campaign_template interview_reschedule_request seeded with 3 languages', () => {
  assert.match(sql, /'interview_reschedule_request'/);
  assert.match(sql, /'pt',\s*'Vamos remarcar sua entrevista,/i);
  assert.match(sql, /'en',\s*'Let''s reschedule your interview,/i);
  assert.match(sql, /'es',\s*'¿Reagendamos tu entrevista,/i);
  assert.match(sql, /ON CONFLICT \(slug\) DO NOTHING/);
});

test('Wave 5d: RPC is SECURITY DEFINER + search_path pinned', () => {
  assert.match(
    sql,
    /CREATE FUNCTION public\.request_interview_reschedule[\s\S]*?SECURITY DEFINER[\s\S]*?SET search_path TO 'public', 'pg_temp'/i
  );
});

test('Wave 5d: V4 authority — committee lead OR manage_member', () => {
  assert.match(sql, /selection_committee[\s\S]*?role = 'lead'/i);
  assert.match(sql, /can_by_member\(v_caller\.id, 'manage_member'::text\)/);
});

test('Wave 5d: state guard limits to interview_pending or interview_scheduled', () => {
  assert.match(
    sql,
    /v_app\.status NOT IN \('interview_pending', 'interview_scheduled'\)/
  );
});

test('Wave 5d: reason cannot be empty', () => {
  assert.match(sql, /p_reason IS NULL OR length\(trim\(p_reason\)\) = 0/);
});

test('Wave 5d: email dispatch via campaign_send_one_off (no new EF)', () => {
  assert.match(sql, /campaign_send_one_off\(\s*'interview_reschedule_request'/);
  // Should NOT introduce new EF
  assert.doesNotMatch(sql, /net\.http_post\(\s*url := 'https:\/\/[^']*\/functions\/v1\//);
});

test('Wave 5d: cancels scheduled interview row + annotates notes', () => {
  assert.match(sql, /UPDATE public\.selection_interviews[\s\S]*?SET status = 'rescheduled'/i);
  assert.match(sql, /Marked for reschedule by/);
});

test('Wave 5d: GRANT EXECUTE to authenticated only (no anon)', () => {
  assert.match(
    sql,
    /GRANT EXECUTE ON FUNCTION public\.request_interview_reschedule\(uuid, text\) TO authenticated/i
  );
  assert.doesNotMatch(
    sql,
    /GRANT EXECUTE ON FUNCTION public\.request_interview_reschedule\(uuid, text\) TO anon/i
  );
});

test('Wave 5d: rollback documented in migration header', () => {
  assert.match(sql, /Rollback:/i);
  assert.match(sql, /DROP FUNCTION public\.request_interview_reschedule\(uuid, text\)/i);
});

test('Wave 5d: dashboard RPC exposes interview_status + reschedule fields', () => {
  assert.match(dashSql, /'interview_status', a\.interview_status/);
  assert.match(dashSql, /'interview_reschedule_reason', a\.interview_reschedule_reason/);
  assert.match(dashSql, /'interview_reschedule_requested_at', a\.interview_reschedule_requested_at/);
});
