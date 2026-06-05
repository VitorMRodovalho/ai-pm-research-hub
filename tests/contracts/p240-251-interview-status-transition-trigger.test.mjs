/**
 * Forward-defense: p240 #251 — interview status transition gap.
 *
 * Origin: PM reproduced 2026-05-24 (#251 reopened): Luíse Quintana +
 *   William Junio (researcher) + 8 others in cycle4-2026 were labelled
 *   'Aguardando Entrevista' in /admin/selection despite having completed
 *   interviews + submitted interview evals.
 *
 * Root cause (3 silent gates):
 *   - schedule_interview() canonical path advances status correctly, but
 *     the calendar webhook (#116) + direct UI flows bypass it.
 *   - mark_interview_status() has precondition status IN ('interview_scheduled',
 *     'interview_done') that silently no-ops when row is still 'interview_pending'.
 *   - submit_interview_scores() advances to 'final_eval' ONLY when ALL
 *     interviewer_ids submitted (Vitor + Fabricio; only Vitor submitted).
 *
 * Fix: AFTER INSERT OR UPDATE OF (status, conducted_at) trigger on
 *   selection_interviews syncs the parent app status based on the row's
 *   canonical evidence, never overwriting terminal statuses.
 *
 * Migration: supabase/migrations/20260805000025_p240_251_interview_status_transition_trigger.sql
 *
 * Asserts:
 *   - Static (12): migration file present + trigger fn SECDEF/search_path +
 *     AFTER INSERT OR UPDATE OF status,conducted_at + terminal no-op guard +
 *     conducted/completed branch (→ interview_done) + scheduled/rescheduled
 *     branch (→ interview_scheduled) + precondition WHERE clause restricts
 *     allowed source statuses + REVOKE EXECUTE FROM PUBLIC + backfill scope
 *     cycle4 + cycle3-b2 + audit canonical action + sanity DO RAISES +
 *     NOTIFY pgrst.
 *   - DB-gated (2): live trigger registered + post-backfill stale-count = 0
 *     in cycle4 + cycle3-b2.
 *
 * Cross-ref:
 *   - GH #251
 *   - p226 audit (Henrique/Fabricio precursor): docs/audit/CYCLE4_TRUST_AUDIT_P226.md
 *   - sibling trigger trg_sync_interview_to_event (selection_interviews → events)
 *   - V4 authority: selection_applications.status drift was observable but
 *     never enforced as an invariant; trigger fills the gap until #260-style
 *     observability surfaces a cron-side health signal.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIGRATION_FILE = resolve(
  ROOT,
  'supabase/migrations/20260805000025_p240_251_interview_status_transition_trigger.sql'
);

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ===================================================================
// STATIC migration body assertions (always run — forward-defense)
// ===================================================================

test('p240 #251: migration file present at canonical path', () => {
  const dir = resolve(ROOT, 'supabase/migrations');
  const files = readdirSync(dir).filter(f => f.startsWith('20260805000025_'));
  assert.equal(files.length, 1,
    'Exactly one migration file must exist for version 20260805000025 (p240 #251)');
  assert.match(files[0], /^20260805000025_p240_251_interview_status_transition_trigger\.sql$/,
    'Migration filename must follow `<timestamp>_<descriptive_name>.sql` per CLAUDE.md GC-097');
});

test('p240 #251: trigger function declared with SECURITY DEFINER + pinned search_path', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\._trg_sync_interview_to_app_status\(\)/i,
    'Trigger function name must be canonical _trg_sync_interview_to_app_status');
  assert.match(body, /SECURITY DEFINER/i,
    'Trigger function must be SECURITY DEFINER (UPDATEs selection_applications under elevated context; ' +
    'webhook role may not own selection_applications RLS scope)');
  assert.match(body, /SET search_path TO 'public', 'pg_temp'/i,
    'Trigger function must pin search_path to public + pg_temp (CLAUDE.md GC-097 search_path injection defense)');
});

test('p240 #251: trigger is AFTER INSERT OR UPDATE OF status,conducted_at on selection_interviews', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /DROP TRIGGER IF EXISTS trg_sync_interview_to_app_status ON public\.selection_interviews/i,
    'Migration must DROP trigger IF EXISTS before CREATE (idempotent re-apply per p219+p233 pattern)');
  assert.match(body, /CREATE TRIGGER trg_sync_interview_to_app_status\s+AFTER INSERT OR UPDATE OF status,\s*conducted_at ON public\.selection_interviews/i,
    'Trigger must be AFTER INSERT OR UPDATE OF (status, conducted_at) on selection_interviews — ' +
    'narrow scope to avoid firing on benign noise UPDATEs (calendar_event_id, reminder_sent_at_1h, etc.)');
});

test('p240 #251: trigger body has terminal-status no-op guard (PM directive: never touch terminal)', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  // All seven terminal/locked statuses must be present in the early-return guard.
  // PM-approved 2026-05-24: trigger nunca toca terminal — preserves audit trail of final decisions.
  for (const term of ['approved', 'rejected', 'converted', 'withdrawn', 'cancelled', 'waitlist', 'final_eval']) {
    assert.match(body, new RegExp(`'${term}'`),
      `Terminal-status guard must include '${term}' (PM directive: trigger nunca toca terminal)`);
  }
  assert.match(body, /IF v_app_status IS NULL OR v_app_status IN \(\s*'approved'[\s\S]{0,300}'final_eval'\s*\)\s*THEN\s+RETURN NEW;/i,
    'Terminal guard must early-return NEW (no-op) when v_app_status is NULL or in terminal list');
});

test('p240 #251: conducted_at OR status=completed branch advances app to interview_done', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /IF NEW\.conducted_at IS NOT NULL OR NEW\.status = 'completed' THEN[\s\S]{0,500}UPDATE public\.selection_applications[\s\S]{0,200}SET status = 'interview_done'/i,
    'When interview row has conducted_at set OR status=completed, app status must advance to interview_done');
  assert.match(body, /WHERE id = NEW\.application_id[\s\S]{0,200}AND status IN \(\s*'screening',\s*'objective_eval',\s*'objective_cutoff',\s*'interview_pending',\s*'interview_scheduled'\s*\)/i,
    'interview_done UPDATE must restrict source statuses (precondition prevents stomping decisions made elsewhere)');
});

test('p240 #251: scheduled/rescheduled branch advances app to interview_scheduled', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /IF NEW\.status IN \(\s*'scheduled',\s*'rescheduled'\s*\) THEN[\s\S]{0,500}UPDATE public\.selection_applications[\s\S]{0,200}SET status = 'interview_scheduled'/i,
    'When interview row is scheduled/rescheduled (not yet conducted), app status must advance to interview_scheduled');
  // The scheduled branch precondition is narrower (excludes interview_scheduled itself
  // and definitely excludes interview_done — once conducted, scheduling a different row
  // doesn't regress the app state).
  assert.match(body, /AND status IN \(\s*'screening',\s*'objective_eval',\s*'objective_cutoff',\s*'interview_pending'\s*\)/i,
    'interview_scheduled UPDATE must NOT include interview_scheduled/interview_done in source statuses ' +
    '(prevents regressing already-conducted apps when a follow-up row is inserted)');
});

test('p240 #251: trigger function is REVOKEd from PUBLIC (SECDEF hygiene)', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /REVOKE EXECUTE ON FUNCTION public\._trg_sync_interview_to_app_status\(\) FROM PUBLIC/i,
    'SECDEF trigger functions must be REVOKEd from PUBLIC (defense-in-depth; only trigger machinery should invoke)');
});

test('p240 #251: backfill scope covers cycle4-2026 + cycle3-2026-b2 (PM-approved)', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /WITH cy AS \(\s*SELECT id FROM public\.selection_cycles\s+WHERE cycle_code IN \(\s*'cycle4-2026',\s*'cycle3-2026-b2'\s*\)/i,
    'Backfill scope must be cycle4-2026 + cycle3-2026-b2 (PM directive 2026-05-24; both cycles in phase=evaluating)');
  assert.match(body, /UPDATE public\.selection_applications a[\s\S]{0,300}FROM fix f[\s\S]{0,200}WHERE f\.id = a\.id[\s\S]{0,200}AND f\.target_status <> a\.status/i,
    'Backfill UPDATE must be idempotent (only writes when target_status differs from current)');
  // Forward-defense: the CTE must use the same evidence ladder as the trigger
  // (interview eval submitted → interview_done > interview conducted → interview_done >
  // interview scheduled → interview_scheduled). If this ladder ever drifts from the
  // trigger body, the trigger will not heal what the backfill produces (and vice versa).
  assert.match(body, /selection_evaluations e[\s\S]{0,300}evaluation_type\s*=\s*'interview'[\s\S]{0,100}submitted_at IS NOT NULL[\s\S]{0,300}THEN 'interview_done'/i,
    'Backfill evidence ladder must mirror trigger (interview eval submitted → interview_done)');
});

test('p240 #251: backfill audit uses canonical action + correct admin_audit_log shape', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /INSERT INTO public\.admin_audit_log[\s\S]{0,200}\(action,\s*actor_id,\s*target_type,\s*target_id/i,
    'Audit INSERT must use actor_id + target_type columns (admin_audit_log live schema; ' +
    'NOT actor_member_id / target_kind — those don\'t exist on this table)');
  assert.match(body, /'p240_251_backfill_interview_status'/i,
    'Backfill audit action must be canonical p240_251_backfill_interview_status');
  assert.match(body, /'reason',\s*'p240_251_interview_status_transition_backfill'/i,
    'Audit metadata.reason must be descriptive enough for grep-recovery');
  assert.match(body, /'migration',\s*'20260805000025'/i,
    'Audit metadata.migration must reference this migration version (targeted rollback)');
});

test('p240 #251: sanity DO block RAISES EXCEPTION on any residual drift', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /RAISE EXCEPTION 'p240 #251 backfill drift:/i,
    'Sanity DO block must RAISE EXCEPTION (fails loud at apply time, not silently at runtime)');
  assert.match(body, /v_count int/i,
    'Sanity block must declare v_count for the drift counter');
  // The sanity must check the exact goal metric: 0 apps in interview_pending
  // with a submitted interview evaluation. This is the metric that motivated #251.
  assert.match(body, /FROM public\.selection_applications a[\s\S]{0,500}AND a\.status = 'interview_pending'[\s\S]{0,500}evaluation_type\s*=\s*'interview'[\s\S]{0,100}submitted_at IS NOT NULL/i,
    'Sanity query must check apps in interview_pending with submitted interview eval (the #251 goal metric)');
});

test('p240 #251: migration reloads PostgREST schema cache', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /NOTIFY pgrst,\s*'reload schema'/i,
    'Migration must NOTIFY pgrst reload schema (CLAUDE.md GC-097)');
});

// ===================================================================
// DB-GATED assertions (require SUPABASE_URL + SERVICE_ROLE_KEY)
// ===================================================================

function makeClient() {
  return createClient(SUPABASE_URL, SUPABASE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

test('p240 #251 (live): backfill audit rows present (proxy for trigger + backfill deploy)',
  { skip: !dbGated && skipMsg },
  async () => {
    const sb = makeClient();
    // Proxy: the migration ships trigger + backfill atomically. If the backfill
    // wrote audit rows with action='p240_251_backfill_interview_status', the
    // migration was applied AND the trigger was created (same migration body).
    // admin_audit_log is exposed via PostgREST (unlike supabase_migrations).
    // Post-deploy MCP smoke (logged in handoff_p240) verified 14 rows live;
    // we assert >= 1 here to remain robust under future re-applies / pruning.
    const { data, error } = await sb
      .from('admin_audit_log')
      .select('id, metadata')
      .eq('action', 'p240_251_backfill_interview_status')
      .limit(20);
    assert.ok(!error, `admin_audit_log probe failed: ${error?.message}`);
    assert.ok(data && data.length >= 1,
      'At least one admin_audit_log row with action=p240_251_backfill_interview_status must exist ' +
      '(if absent, the migration was never applied or the backfill block never ran — re-run apply_migration). ' +
      'Post-deploy smoke verified 14 rows (10 cycle4 + 4 cycle3-b2).');
    // All audit rows should carry the migration tag for forensic traceability.
    const rowsWithTag = (data || []).filter(r => r.metadata?.migration === '20260805000025');
    assert.ok(rowsWithTag.length === data.length,
      `All p240_251_backfill_interview_status audit rows must tag metadata.migration='20260805000025'; ` +
      `got ${rowsWithTag.length}/${data.length} tagged.`);
  }
);

test('p240 #251 (live): post-backfill 0 apps in interview_pending with submitted interview eval',
  { skip: !dbGated && skipMsg },
  async () => {
    const sb = makeClient();
    // Resolve cycle ids for scope.
    const { data: cycles, error: e0 } = await sb
      .from('selection_cycles')
      .select('id, cycle_code')
      .in('cycle_code', ['cycle4-2026', 'cycle3-2026-b2']);
    assert.ok(!e0, `selection_cycles query failed: ${e0?.message}`);
    const cycleIds = (cycles || []).map(c => c.id);
    assert.ok(cycleIds.length >= 1,
      'At least one of cycle4-2026 / cycle3-2026-b2 must exist (backfill scope sanity)');

    // Apps still in interview_pending within scope.
    const { data: pending, error: e1 } = await sb
      .from('selection_applications')
      .select('id')
      .eq('status', 'interview_pending')
      .in('cycle_id', cycleIds);
    assert.ok(!e1, `selection_applications query failed: ${e1?.message}`);

    if (!pending || pending.length === 0) {
      return; // trivially 0 drift
    }

    // Which of those have a submitted interview eval?
    const { data: evals, error: e2 } = await sb
      .from('selection_evaluations')
      .select('application_id')
      .eq('evaluation_type', 'interview')
      .not('submitted_at', 'is', null)
      .in('application_id', pending.map(p => p.id));
    assert.ok(!e2, `selection_evaluations query failed: ${e2?.message}`);

    const driftCount = (evals || []).length;
    assert.strictEqual(
      driftCount,
      0,
      `Expected 0 apps in interview_pending with submitted interview eval (post-backfill); got ${driftCount}. ` +
      `Backfill in 20260805000025 should have flipped all such rows to interview_done. ` +
      `Trigger should also keep this invariant true going forward.`
    );
  }
);
