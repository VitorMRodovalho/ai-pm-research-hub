/**
 * W124 Phase 3 Contract Test: Interview + Decision + Conversion
 * Static analysis of migration SQL to verify:
 * - RPCs exist with correct signatures and SECURITY DEFINER
 * - Interview scheduling + score submission + status marking
 * - finalize_decisions bulk processing with auto-member creation
 * - Conversion flow (researcher → leader) with 3-gate pattern
 * - Notification triggers for selection events
 * - Onboarding step creation for approved candidates
 * - Diversity snapshot on finalization
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

function loadAllMigrations() {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql')).sort();
  return files.map(f => ({
    name: f,
    content: readFileSync(join(MIGRATIONS_DIR, f), 'utf8'),
  }));
}

const migrations = loadAllMigrations();
const allSQL = migrations.map(m => m.content).join('\n');

function findFunctionBody(funcName) {
  const escaped = funcName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${escaped}\\s*\\([^)]*\\)[\\s\\S]*?\\$\\$([\\s\\S]*?)\\$\\$`,
    'gi'
  );
  const matches = [...allSQL.matchAll(regex)];
  return matches.length > 0 ? matches[matches.length - 1][1] : null;
}

// ─── RPC existence + SECURITY DEFINER ───

const PHASE3_RPCS = [
  'schedule_interview',
  'submit_interview_scores',
  'mark_interview_status',
  'finalize_decisions',
];

for (const rpcName of PHASE3_RPCS) {
  test(`RPC ${rpcName} exists in migrations`, () => {
    const body = findFunctionBody(rpcName);
    assert.ok(body, `RPC ${rpcName} not found in migrations`);
  });

  test(`RPC ${rpcName} is SECURITY DEFINER`, () => {
    const pattern = new RegExp(`${rpcName}[\\s\\S]*?SECURITY\\s+DEFINER`, 'i');
    assert.ok(pattern.test(allSQL), `RPC ${rpcName} must be SECURITY DEFINER`);
  });

  test(`RPC ${rpcName} has GRANT EXECUTE to authenticated`, () => {
    const pattern = new RegExp(`GRANT\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+(?:public\\.)?${rpcName}`, 'i');
    assert.ok(pattern.test(allSQL), `RPC ${rpcName} must GRANT EXECUTE to authenticated`);
  });
}

// ─── schedule_interview ───

test('schedule_interview requires committee lead or superadmin', () => {
  const body = findFunctionBody('schedule_interview');
  assert.ok(/selection_committee/i.test(body), 'Must check selection_committee');
  assert.ok(/role\s*=\s*'lead'/i.test(body), 'Must require lead role');
  assert.ok(/is_superadmin/i.test(body), 'Must check is_superadmin');
});

test('schedule_interview validates application is interview_pending or interview_scheduled', () => {
  const body = findFunctionBody('schedule_interview');
  assert.ok(/'interview_pending'/i.test(body), 'Must check interview_pending status');
});

test('schedule_interview creates interview record with scheduled status', () => {
  const body = findFunctionBody('schedule_interview');
  assert.ok(/INSERT\s+INTO\s+(?:public\.)?selection_interviews/i.test(body),
    'Must INSERT into selection_interviews');
  assert.ok(/'scheduled'/i.test(body), 'Must set status to scheduled');
});

test('schedule_interview updates application status to interview_scheduled', () => {
  const body = findFunctionBody('schedule_interview');
  assert.ok(/UPDATE\s+(?:public\.)?selection_applications[\s\S]*?'interview_scheduled'/i.test(body),
    'Must update application to interview_scheduled');
});

test('schedule_interview sends notification to interviewers', () => {
  const body = findFunctionBody('schedule_interview');
  assert.ok(/create_notification[\s\S]*?selection_interview_scheduled/i.test(body),
    'Must send selection_interview_scheduled notification');
  assert.ok(/FOREACH\s+v_interviewer_id\s+IN\s+ARRAY/i.test(body),
    'Must iterate over interviewer_ids array');
});

// ─── submit_interview_scores ───

test('submit_interview_scores verifies caller is an assigned interviewer', () => {
  const body = findFunctionBody('submit_interview_scores');
  assert.ok(/v_caller\.id\s*=\s*ANY\s*\(\s*v_interview\.interviewer_ids\s*\)/i.test(body),
    'Must check caller is in interviewer_ids');
});

test('submit_interview_scores validates all criteria have scores', () => {
  const body = findFunctionBody('submit_interview_scores');
  assert.ok(/RAISE\s+EXCEPTION.*Missing\s+score/i.test(body),
    'Must raise exception for missing scores');
});

test('submit_interview_scores uses PERT formula on completion', () => {
  const body = findFunctionBody('submit_interview_scores');
  assert.ok(/2\s*\*\s*v_min/i.test(body), 'PERT must include 2*min');
  assert.ok(/4\s*\*\s*v_avg/i.test(body), 'PERT must include 4*avg');
  assert.ok(/2\s*\*\s*v_max/i.test(body), 'PERT must include 2*max');
  assert.ok(/\/\s*8/i.test(body), 'PERT must divide by 8');
});

test('submit_interview_scores computes final_score = objective + interview', () => {
  const body = findFunctionBody('submit_interview_scores');
  assert.ok(/final_score\s*=\s*COALESCE\s*\(\s*objective_score_avg/i.test(body),
    'Must compute final_score from objective_score_avg + interview');
});

test('submit_interview_scores advances to final_eval when all submit', () => {
  const body = findFunctionBody('submit_interview_scores');
  assert.ok(/'final_eval'/i.test(body), 'Must advance to final_eval');
});

test('submit_interview_scores marks interview as completed', () => {
  const body = findFunctionBody('submit_interview_scores');
  assert.ok(/UPDATE\s+(?:public\.)?selection_interviews[\s\S]*?'completed'/i.test(body),
    'Must mark interview as completed');
});

test('submit_interview_scores notifies committee lead on completion', () => {
  const body = findFunctionBody('submit_interview_scores');
  assert.ok(/create_notification[\s\S]*?selection_evaluation_complete/i.test(body),
    'Must notify committee lead with selection_evaluation_complete');
});

// ─── mark_interview_status ───

test('mark_interview_status validates status values', () => {
  const body = findFunctionBody('mark_interview_status');
  assert.ok(/'noshow'/i.test(body), 'Must accept noshow');
  assert.ok(/'cancelled'/i.test(body), 'Must accept cancelled');
  assert.ok(/'rescheduled'/i.test(body), 'Must accept rescheduled');
});

test('mark_interview_status updates application status on noshow', () => {
  const body = findFunctionBody('mark_interview_status');
  assert.ok(/'interview_noshow'/i.test(body), 'Must set interview_noshow');
});

test('mark_interview_status notifies GP on no-show', () => {
  const body = findFunctionBody('mark_interview_status');
  assert.ok(/create_notification[\s\S]*?selection_interview_noshow/i.test(body),
    'Must send selection_interview_noshow notification');
});

test('mark_interview_status allows interviewer, lead, or superadmin', () => {
  const body = findFunctionBody('mark_interview_status');
  assert.ok(/interviewer_ids/i.test(body), 'Must check interviewer_ids');
  assert.ok(/is_superadmin/i.test(body), 'Must check is_superadmin');
  assert.ok(/role\s*=\s*'lead'/i.test(body), 'Must check lead role');
});

// ─── finalize_decisions ───

test('finalize_decisions requires committee lead or superadmin', () => {
  const body = findFunctionBody('finalize_decisions');
  assert.ok(/selection_committee[\s\S]*?role\s*=\s*'lead'/i.test(body),
    'Must require committee lead');
  assert.ok(/is_superadmin/i.test(body), 'Must check is_superadmin');
});

test('finalize_decisions processes bulk decisions from jsonb array', () => {
  const body = findFunctionBody('finalize_decisions');
  assert.ok(/jsonb_array_elements\s*\(\s*p_decisions\s*\)/i.test(body),
    'Must iterate over p_decisions jsonb array');
});

test('finalize_decisions auto-creates member for approved candidates', () => {
  const body = findFunctionBody('finalize_decisions');
  assert.ok(/INSERT\s+INTO\s+(?:public\.)?members/i.test(body),
    'Must INSERT into members for approved candidates');
  assert.ok(/v_app\.applicant_name/i.test(body), 'Must use applicant_name for member name');
  assert.ok(/v_app\.email/i.test(body), 'Must use applicant email');
  assert.ok(/v_app\.chapter/i.test(body), 'Must use applicant chapter');
});

test('finalize_decisions reactivates existing inactive members', () => {
  const body = findFunctionBody('finalize_decisions');
  assert.ok(/is_active\s*=\s*true/i.test(body), 'Must set is_active = true');
  assert.ok(/current_cycle_active\s*=\s*true/i.test(body), 'Must set current_cycle_active = true');
});

test('finalize_decisions handles conversion flow (researcher → leader)', () => {
  const body = findFunctionBody('finalize_decisions');
  assert.ok(/convert_to/i.test(body), 'Must handle convert_to field');
  assert.ok(/'converted'/i.test(body), 'Must set status to converted');
  assert.ok(/converted_from/i.test(body), 'Must track converted_from');
  assert.ok(/converted_to/i.test(body), 'Must track converted_to');
  assert.ok(/conversion_reason/i.test(body), 'Must store conversion_reason');
});

test('finalize_decisions sends conversion offer notification', () => {
  const body = findFunctionBody('finalize_decisions');
  assert.ok(/create_notification[\s\S]*?selection_conversion_offer/i.test(body),
    'Must notify candidate with selection_conversion_offer');
});

test('finalize_decisions creates onboarding steps for approved candidates', () => {
  const body = findFunctionBody('finalize_decisions');
  assert.ok(/INSERT\s+INTO\s+(?:public\.)?onboarding_progress/i.test(body),
    'Must create onboarding_progress records');
  assert.ok(/sla_deadline/i.test(body), 'Must set sla_deadline');
  assert.ok(/onboarding_steps/i.test(body), 'Must use cycle onboarding_steps config');
});

test('finalize_decisions notifies approved members', () => {
  const body = findFunctionBody('finalize_decisions');
  assert.ok(/create_notification[\s\S]*?selection_approved/i.test(body),
    'Must send selection_approved notification');
});

test('finalize_decisions takes diversity snapshot', () => {
  const body = findFunctionBody('finalize_decisions');
  assert.ok(/INSERT\s+INTO\s+(?:public\.)?selection_diversity_snapshots/i.test(body),
    'Must create diversity snapshot');
  assert.ok(/'approved'/i.test(body), 'Must snapshot approved candidates');
  assert.ok(/by_chapter/i.test(body), 'Must include chapter breakdown');
  assert.ok(/by_gender/i.test(body), 'Must include gender breakdown');
});

test('finalize_decisions returns summary counts', () => {
  const body = findFunctionBody('finalize_decisions');
  assert.ok(/v_approved_count/i.test(body), 'Must count approved');
  assert.ok(/v_rejected_count/i.test(body), 'Must count rejected');
  assert.ok(/v_waitlisted_count/i.test(body), 'Must count waitlisted');
  assert.ok(/v_converted_count/i.test(body), 'Must count converted');
  assert.ok(/v_created_members/i.test(body), 'Must count created members');
});

// ─── Notification types defined ───

const SELECTION_NOTIFICATION_TYPES = [
  'selection_interview_scheduled',
  'selection_evaluation_complete',
  'selection_interview_noshow',
  'selection_approved',
  'selection_conversion_offer',
];

for (const notifType of SELECTION_NOTIFICATION_TYPES) {
  test(`Notification type '${notifType}' is used in selection RPCs`, () => {
    assert.ok(
      allSQL.includes(`'${notifType}'`),
      `Notification type '${notifType}' must be used in migration SQL`
    );
  });
}

// ─── Interview schema contract ───

test('selection_interviews table has interviewer_ids uuid array', () => {
  assert.ok(
    /interviewer_ids\s+uuid\[\]/i.test(allSQL),
    'selection_interviews must have interviewer_ids uuid[] column'
  );
});

test('selection_interviews status includes all required values', () => {
  const statuses = ['pending', 'scheduled', 'completed', 'noshow', 'cancelled', 'rescheduled'];
  for (const s of statuses) {
    assert.ok(
      new RegExp(`'${s}'`, 'i').test(allSQL),
      `selection_interviews status must include '${s}'`
    );
  }
});
