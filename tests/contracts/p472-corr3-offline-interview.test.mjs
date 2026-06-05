/**
 * Contract: #472 correction #3 — admin "record offline interview" path.
 *
 * Off-platform interviews leave a candidate with no selection_interviews row and
 * unscoreable via the UI (B1/B4). Since a Calendar pull is infeasible (corr-1),
 * the admin is the ingress. The whole blocker was the P0004 status gate in
 * schedule_interview sitting OUTSIDE the `IF NOT v_can_bypass` block, so even an
 * admin (manage_member) + p_bypass_gate=true was rejected for any status not in
 * {interview_pending, interview_scheduled}.
 *
 * This change (migration 20260805000092) makes P0004 bypassable for the admin
 * bypass path but TERMINAL-SAFE (a decided application is never reopened), and
 * the admin UI (selection.astro loadInterviewForm) exposes an offline-interview
 * affordance (past-date input → schedule_interview p_bypass_gate=true → the
 * existing score form advances to final_eval).
 *
 * STATIC SOURCE-PARSE (the schedule_interview auth path needs a real user JWT, so
 * it cannot be exercised by a service-role CI client — behaviour was verified live
 * via set_config JWT probes during implementation: pre-decision+bypass reaches the
 * INSERT (gate_bypassed=true); terminal(rejected)+bypass still raises P0004).
 *
 * Cross-ref: issue #472 (B4); ADR-0073; SEDIMENT-275.A (dual T-slot i18n).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000092_472_corr3_schedule_interview_bypass_p0004.sql');
const ASTRO = resolve(ROOT, 'src/pages/admin/selection.astro');
const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const mig = migRaw.replace(/^\s*--.*$/gm, ''); // strip line comments
const astro = existsSync(ASTRO) ? readFileSync(ASTRO, 'utf8') : '';

const NEW_KEYS = [
  'offlineInterviewBtn',
  'offlineInterviewHint',
  'offlineInterviewDateLabel',
  'offlineInterviewToast',
  'offlineInterviewError',
];

// ── DB migration ──────────────────────────────────────────────────────────────
test('472-c3 static: migration 20260805000092 exists + NOTIFY pgrst', () => {
  assert.ok(existsSync(MIG), 'migration present');
  assert.match(migRaw, /NOTIFY pgrst, 'reload schema'/);
});

test('472-c3 static: P0004 is an ALLOW-LIST — bypass only from pre-interview statuses; late-stage/decided blocked', () => {
  // always {pending,scheduled}; bypass adds ONLY the 4 pre-interview statuses
  assert.match(
    mig,
    /IF NOT \(\s*\n?\s*v_app\.status IN \('interview_pending', 'interview_scheduled'\)\s*\n?\s*OR \( v_can_bypass AND v_app\.status IN \('screening', 'submitted', 'objective_eval', 'objective_cutoff'\) \)\s*\n?\s*\) THEN/,
    'P0004 allow-list (pending/scheduled always; bypass adds the 4 pre-interview statuses)'
  );
  // forward defense: the old UNCONDITIONAL form must be gone
  assert.ok(
    !/IF v_app\.status NOT IN \('interview_pending', 'interview_scheduled'\) THEN/.test(mig),
    'REGRESSION: P0004 reverted to an unconditional status gate'
  );
  // forward defense: a later-stage / decided status must NEVER be bypass-eligible
  // (else the unconditional status->interview_scheduled UPDATE would regress it —
  // the exact blocker caught in adversarial review)
  for (const s of ['final_eval', 'interview_done', 'interview_noshow', 'approved', 'rejected', 'converted', 'withdrawn', 'cancelled', 'waitlist']) {
    assert.ok(
      !new RegExp(`v_can_bypass AND v_app\\.status IN \\([^)]*'${s}'`).test(mig),
      `${s} must NOT be in the bypass allow-list (would let an admin regress/reopen it)`
    );
  }
});

test('472-c3 static: bypass authority + AI/peer/score gates unchanged', () => {
  assert.match(mig, /v_can_bypass := p_bypass_gate AND public\.can_by_member\(v_caller\.id, 'manage_member'::text\)/,
    'bypass requires p_bypass_gate AND manage_member');
  assert.match(mig, /IF NOT v_can_bypass THEN[\s\S]*'P0001'[\s\S]*'P0002'[\s\S]*'P0003'[\s\S]*END IF;/,
    'P0001/P0002/P0003 gates still inside the IF NOT v_can_bypass block');
  // audit preserved on both the blocked and success paths
  assert.ok((mig.match(/_log_gate_attempt/g) || []).length >= 5, 'gate-attempt audit calls preserved');
});

// ── Admin UI ──────────────────────────────────────────────────────────────────
test('472-c3 static: UI exposes the offline-interview affordance (pre-decision, terminal-safe)', () => {
  assert.match(astro, /const OFFLINE_ELIGIBLE = \['screening', 'submitted', 'objective_eval', 'objective_cutoff'\]/,
    'UI allow-list mirrors the RPC bypass set');
  assert.match(astro, /const canRecordOffline = !canStartLive && OFFLINE_ELIGIBLE\.includes\(row\.status\)/,
    'offline affordance gated on the pre-interview allow-list');
  assert.match(astro, /id="record-offline-interview-btn"/, 'offline record button present');
  assert.match(astro, /id="offline-interview-date"/, 'past-date input present');
  // the handler bypass-schedules at the chosen date
  assert.match(astro, /#record-offline-interview-btn'\)\?\.addEventListener[\s\S]*?schedule_interview[\s\S]*?p_bypass_gate: true/,
    'offline handler calls schedule_interview with p_bypass_gate: true');
});

// ── i18n: dual T-slot (SEDIMENT-275.A) + 3-dict parity ────────────────────────
test('472-c3 i18n: each new modal key appears EXACTLY 2x in selection.astro (dual T-slot)', () => {
  for (const k of NEW_KEYS) {
    const runtime = new RegExp(`${k}:\\s*t\\('admin\\.selection\\.modal\\.${k}', lang\\)`, 'g');
    const fallback = new RegExp(`(^|\\s)${k}:\\s*'`, 'g'); // literal fallback entry
    const rt = (astro.match(runtime) || []).length;
    const fb = (astro.match(fallback) || []).length;
    assert.equal(rt, 1, `${k}: missing/duplicate runtime-bridge T entry (found ${rt})`);
    assert.equal(fb, 1, `${k}: missing/duplicate literal-fallback T entry (found ${fb})`);
  }
});

test('472-c3 i18n: each new key present in all 3 dictionaries', () => {
  const dicts = ['pt-BR', 'en-US', 'es-LATAM'].map((d) => ({
    d, src: readFileSync(resolve(ROOT, `src/i18n/${d}.ts`), 'utf8'),
  }));
  for (const k of NEW_KEYS) {
    for (const { d, src } of dicts) {
      assert.ok(
        src.includes(`'admin.selection.modal.${k}'`),
        `${d} missing key admin.selection.modal.${k}`
      );
    }
  }
});
