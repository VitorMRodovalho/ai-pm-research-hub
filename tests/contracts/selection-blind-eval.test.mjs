/**
 * W124 Phase 2 Contract Test: Blind Evaluation + Scoring Engine
 * Static analysis of migration SQL to verify:
 * - RPCs exist with correct signatures and SECURITY DEFINER
 * - Blind review enforcement (no cross-evaluator score leakage)
 * - PERT consolidation formula: (2*min + 4*avg + 2*max) / 8
 * - Cutoff at 75% of median
 * - Calibration alert (divergence > 3 points)
 * - Committee authorization checks
 * - Rankings calculation with chapter + overall
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
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${escaped}\\s*\\([^)]*\\)[\\s\\S]*?AS\\s+\\$(\\w*)\\$([\\s\\S]*?)\\$\\1\\$`,
    'gi'
  );
  const matches = [...allSQL.matchAll(regex)];
  return matches.length > 0 ? matches[matches.length - 1][2] : null;
}

// ─── RPC existence + SECURITY DEFINER ───

const PHASE2_RPCS = [
  'get_evaluation_form',
  'submit_evaluation',
  'get_evaluation_results',
  'calculate_rankings',
];

for (const rpcName of PHASE2_RPCS) {
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

  test(`RPC ${rpcName} checks committee membership or superadmin`, () => {
    const body = findFunctionBody(rpcName);
    const checksCommittee = /selection_committee/i.test(body);
    const checksSuperadmin = /is_superadmin/i.test(body);
    assert.ok(checksCommittee || checksSuperadmin,
      `RPC ${rpcName} must check selection_committee or is_superadmin`);
  });
}

// ─── Blind review enforcement ───

test('get_evaluation_form does NOT return other evaluators scores', () => {
  const body = findFunctionBody('get_evaluation_form');
  // Should only select evaluator's own scores (evaluator_id = v_caller.id)
  assert.ok(/evaluator_id\s*=\s*v_caller\.id/i.test(body),
    'get_evaluation_form must filter evaluations by caller id only');
  // Should NOT aggregate all evaluations
  assert.ok(!/jsonb_agg.*selection_evaluations/i.test(body),
    'get_evaluation_form must NOT aggregate all evaluations (blind)');
});

test('get_evaluation_results enforces blind until all submit', () => {
  const body = findFunctionBody('get_evaluation_results');
  // Must check submitted count >= min_evaluators before revealing
  assert.ok(/min_evaluators/i.test(body),
    'get_evaluation_results must check min_evaluators threshold');
  assert.ok(/RAISE\s+EXCEPTION.*blind/i.test(body),
    'get_evaluation_results must RAISE EXCEPTION for premature access');
});

test('submit_evaluation prevents re-submission of locked evaluation', () => {
  const body = findFunctionBody('submit_evaluation');
  assert.ok(/submitted_at\s+IS\s+NOT\s+NULL/i.test(body),
    'submit_evaluation must check submitted_at for lock enforcement');
  assert.ok(/RAISE\s+EXCEPTION.*locked/i.test(body),
    'submit_evaluation must RAISE EXCEPTION on locked re-submission');
});

// ─── PERT consolidation formula ───

test('submit_evaluation uses PERT formula (2*min + 4*avg + 2*max) / 8', () => {
  const body = findFunctionBody('submit_evaluation');
  // Check for the PERT formula components
  assert.ok(/2\s*\*\s*v_min/i.test(body), 'PERT must include 2*min');
  assert.ok(/4\s*\*\s*v_avg/i.test(body), 'PERT must include 4*avg');
  assert.ok(/2\s*\*\s*v_max/i.test(body), 'PERT must include 2*max');
  assert.ok(/\/\s*8/i.test(body), 'PERT must divide by 8');
});

test('get_evaluation_results computes PERT per evaluation type', () => {
  const body = findFunctionBody('get_evaluation_results');
  // Should compute PERT for objective, interview, and leader_extra
  const pertMatches = body.match(/2\s*\*\s*MIN\(weighted_subtotal\)\s*\+\s*4\s*\*\s*AVG\(weighted_subtotal\)\s*\+\s*2\s*\*\s*MAX\(weighted_subtotal\)/gi);
  assert.ok(pertMatches && pertMatches.length >= 2,
    'get_evaluation_results must compute PERT for at least objective + interview types');
});

// ─── Cutoff at 75% of median ───

test('submit_evaluation calculates cutoff as 75% of median', () => {
  const body = findFunctionBody('submit_evaluation');
  assert.ok(/PERCENTILE_CONT\s*\(\s*0\.5\s*\)/i.test(body),
    'submit_evaluation must use PERCENTILE_CONT(0.5) for median');
  assert.ok(/\*\s*0\.75/i.test(body),
    'submit_evaluation must apply 0.75 multiplier for cutoff');
});

test('calculate_rankings uses 75% of median as cutoff', () => {
  const body = findFunctionBody('calculate_rankings');
  assert.ok(/PERCENTILE_CONT\s*\(\s*0\.5\s*\)/i.test(body),
    'calculate_rankings must compute median');
  assert.ok(/\*\s*0\.75/i.test(body),
    'calculate_rankings must apply 0.75 cutoff');
});

// ─── Calibration alert (divergence > 3 points) ───

test('get_evaluation_results detects divergence > 3 and flags calibration alerts', () => {
  const body = findFunctionBody('get_evaluation_results');
  assert.ok(/divergence/i.test(body),
    'get_evaluation_results must calculate divergence');
  assert.ok(/>\s*3/i.test(body),
    'get_evaluation_results must check divergence > 3');
  assert.ok(/calibration_alert/i.test(body),
    'get_evaluation_results must include calibration_alerts in response');
});

// ─── Rankings ───

test('calculate_rankings computes both chapter and overall rankings', () => {
  const body = findFunctionBody('calculate_rankings');
  assert.ok(/PARTITION\s+BY\s+chapter/i.test(body),
    'calculate_rankings must partition by chapter for chapter ranking');
  assert.ok(/ROW_NUMBER\(\)\s+OVER\s*\(\s*ORDER\s+BY\s+final_score\s+DESC\)/i.test(body),
    'calculate_rankings must rank overall by final_score DESC');
  assert.ok(/rank_overall/i.test(body), 'Must update rank_overall');
  assert.ok(/rank_chapter/i.test(body), 'Must update rank_chapter');
});

test('calculate_rankings recommends approve/waitlist/reject based on cutoff', () => {
  const body = findFunctionBody('calculate_rankings');
  assert.ok(/'approve'/i.test(body), 'Must include approve recommendation');
  assert.ok(/'waitlist'/i.test(body), 'Must include waitlist recommendation');
  assert.ok(/'reject'/i.test(body), 'Must include reject recommendation');
});

test('calculate_rankings flags convert_to_leader for 90th percentile researchers', () => {
  const body = findFunctionBody('calculate_rankings');
  assert.ok(/PERCENTILE_CONT\s*\(\s*0\.9\s*\)/i.test(body),
    'calculate_rankings must compute 90th percentile for leader conversion');
  assert.ok(/convert_to_leader/i.test(body),
    'calculate_rankings must flag convert_to_leader');
});

// ─── Weighted subtotal calculation ───

test('submit_evaluation validates all criteria have scores', () => {
  const body = findFunctionBody('submit_evaluation');
  assert.ok(/RAISE\s+EXCEPTION.*Missing\s+score/i.test(body),
    'submit_evaluation must raise exception for missing scores');
});

test('submit_evaluation calculates weighted subtotal from criteria weights', () => {
  const body = findFunctionBody('submit_evaluation');
  assert.ok(/v_weight\s*\*\s*v_score/i.test(body) || /v_weighted_sum/i.test(body),
    'submit_evaluation must compute weighted subtotal');
});

// ─── Score auto-advance ───

test('submit_evaluation auto-advances objective_eval to interview_pending or objective_cutoff', () => {
  const body = findFunctionBody('submit_evaluation');
  assert.ok(/'interview_pending'/i.test(body),
    'submit_evaluation must advance to interview_pending on pass');
  assert.ok(/'objective_cutoff'/i.test(body),
    'submit_evaluation must advance to objective_cutoff on fail');
});

test('submit_evaluation updates final_score for interview type', () => {
  const body = findFunctionBody('submit_evaluation');
  assert.ok(/final_score\s*=.*objective_score_avg.*interview/i.test(body)
    || /final_score\s*=.*\+\s*v_pert_score/i.test(body),
    'submit_evaluation must compute final_score from objective + interview');
});

// ─── Schema contract ───

test('selection_evaluations has UNIQUE constraint for blind review', () => {
  assert.ok(
    /UNIQUE\s*\(\s*application_id\s*,\s*evaluator_id\s*,\s*evaluation_type\s*\)/i.test(allSQL),
    'selection_evaluations must have UNIQUE(application_id, evaluator_id, evaluation_type)'
  );
});

test('selection_evaluations has submitted_at for lock enforcement', () => {
  assert.ok(
    /submitted_at\s+timestamptz/i.test(allSQL),
    'selection_evaluations must have submitted_at timestamptz column'
  );
});

test('selection_applications has denormalized score columns', () => {
  const cols = ['objective_score_avg', 'interview_score', 'final_score', 'rank_chapter', 'rank_overall'];
  for (const col of cols) {
    assert.ok(
      new RegExp(`${col}\\s+(numeric|int)`, 'i').test(allSQL),
      `selection_applications must have ${col} column`
    );
  }
});
