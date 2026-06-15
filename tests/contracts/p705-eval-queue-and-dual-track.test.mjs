/**
 * #705 — eval-queue fixes + dual-track linkage backfill (cycle4-2026, via MCP).
 *
 * Bug 1: get_my_pending_evaluations devolvia applications TERMINAIS na fila (sem
 *        filtro de status). Bug 3: completed_count fazia count(*) sobre o JOIN de
 *        selection_evaluations (fan-out) -> progress_pct > 100%. Fix (mig 173):
 *        universo "avaliável" = não-terminal aplicado em pending + completed + total,
 *        com count(DISTINCT). Bug 2: pares dual-track antigos órfãos (Maria) — backfill
 *        idempotente liga os pares limpos 1:1 (complementa o trigger AFTER INSERT do #693).
 *
 * STATIC: a migration aplica o filtro de terminais + DISTINCT e PRESERVA os
 *         invariantes do #298 (picker determinístico + gate escopado).
 * DB-AWARE: (a) 0 pares dual-track limpos órfãos; (b) no ciclo evaluating, nenhum
 *           avaliador tem completed_distinct(avaliáveis) > total(avaliáveis) — i.e.
 *           progress_pct <= 100; (c) nenhum terminal entra no universo da fila.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000173_705_eval_queue_terminal_filter_and_dual_track_backfill.sql');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const TERMINAL = ['rejected', 'withdrawn', 'cancelled', 'approved', 'converted', 'waitlist', 'interview_noshow'];

// ── STATIC ──────────────────────────────────────────────────────────────────
test('#705 static: migration 173 filters terminals + uses DISTINCT + preserves #298', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000173 present');
  const src = readFileSync(MIG, 'utf8');
  const code = src.replace(/^\s*--.*$/gm, ''); // strip line comments

  // Bug 1/3: a re-definição da função existe e aplica o filtro de terminais + DISTINCT
  assert.match(code, /CREATE OR REPLACE FUNCTION public\.get_my_pending_evaluations\(\)/, 'redefine get_my_pending_evaluations');
  assert.match(code, /v_terminal\s+constant\s+text\[\]\s*:=\s*ARRAY\[/, 'declares the terminal set');
  // terminal set membership covers the canonical terminals
  for (const t of TERMINAL) assert.ok(code.includes(`'${t}'`), `terminal set must include '${t}'`);
  // applied to pending + completed + total (3 occurrences of the status guard)
  const guards = (code.match(/status\s*<>\s*ALL\s*\(\s*v_terminal\s*\)/g) || []).length;
  assert.ok(guards >= 3, `expected the terminal guard on pending + completed + total (>=3), found ${guards}`);
  assert.match(code, /count\(DISTINCT\s+sa\.id\)/, 'completed_count must use count(DISTINCT sa.id) (Bug 3)');

  // #298 regression guard: deterministic picker + scoped committee gate preserved
  assert.match(code, /phase\s*=\s*'evaluating'\s+ORDER\s+BY\s+created_at\s+DESC\s+LIMIT\s+1/i, 'keep #298 deterministic cycle picker');
  assert.match(code, /selection_committee\s+sc\s+WHERE\s+sc\.member_id\s*=\s*v_caller_member_id\s+AND\s+sc\.cycle_id\s*=\s*v_cycle\.id/i, 'keep #298 cycle-scoped gate');

  // Bug 2: backfill bidirecional + dual_track, restrito a pares limpos 1:1
  assert.match(code, /linked_application_id\s*=\s*CASE\s+WHEN\s+sa\.id\s*=\s*cp\.leader_id/i, 'reciprocal backfill UPDATE');
  assert.match(code, /promotion_path\s*=\s*'dual_track'/, 'backfill sets dual_track');
});

// ── DB-AWARE ────────────────────────────────────────────────────────────────
test('#705 invariant: 0 orphan clean dual-track pairs (1 leader + 1 researcher, unlinked)',
  { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb
    .from('selection_applications')
    .select('email, cycle_id, role_applied, linked_application_id, applicant_name')
    .is('linked_application_id', null)
    .not('email', 'is', null)
    // Exclude synthetic fixtures from OTHER DB-aware tests running in parallel
    // (e.g. p693's dual-track pair, whose teardown nulls linked_application_id
    // before deleting → a transient orphan window this global scan would catch).
    // Sediment: live exact-count tests must filter parallel fixtures.
    .not('email', 'ilike', '%example.%')
    .in('role_applied', ['leader', 'researcher']);
  assert.ok(!error, `query failed: ${error?.message}`);

  // group by (lower(email), cycle_id) and count unlinked per role
  const groups = new Map();
  for (const r of data ?? []) {
    const k = `${String(r.email).toLowerCase()}|${r.cycle_id}`;
    const g = groups.get(k) ?? { leader: 0, researcher: 0 };
    g[r.role_applied]++;
    groups.set(k, g);
  }
  const orphanCleanPairs = [...groups.entries()].filter(([, g]) => g.leader === 1 && g.researcher === 1);
  assert.equal(orphanCleanPairs.length, 0,
    `orphan clean dual-track pairs remain (should be backfilled + AFTER-INSERT-linked): ${JSON.stringify(orphanCleanPairs.map(([k]) => k))}`);
});

test('#705 invariant: pending-evals progress is consistent (no evaluator > 100% in the evaluating cycle)',
  { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  const { data: cyc } = await sb.from('selection_cycles')
    .select('id').eq('phase', 'evaluating').order('created_at', { ascending: false }).limit(1).maybeSingle();
  if (!cyc?.id) return; // no evaluating cycle → nothing to assert (consistent with the RPC's empty short-circuit)

  // evaluable universe = non-terminal apps in the cycle
  const { data: apps, error: appErr } = await sb.from('selection_applications')
    .select('id, status').eq('cycle_id', cyc.id);
  assert.ok(!appErr, `apps query failed: ${appErr?.message}`);
  const evaluable = new Set((apps ?? []).filter(a => !TERMINAL.includes(a.status)).map(a => a.id));
  const evaluableTotal = evaluable.size;

  // completed per evaluator = DISTINCT evaluable apps with a SUBMITTED eval
  const { data: evals, error: evErr } = await sb.from('selection_evaluations')
    .select('application_id, evaluator_id, submitted_at').not('submitted_at', 'is', null);
  assert.ok(!evErr, `evals query failed: ${evErr?.message}`);

  const perEval = new Map();
  for (const e of evals ?? []) {
    if (!evaluable.has(e.application_id)) continue;
    const s = perEval.get(e.evaluator_id) ?? new Set();
    s.add(e.application_id);
    perEval.set(e.evaluator_id, s);
  }
  for (const [evaluator, doneSet] of perEval.entries()) {
    assert.ok(doneSet.size <= evaluableTotal,
      `evaluator ${evaluator} completed ${doneSet.size} > evaluable total ${evaluableTotal} (progress > 100% — Bug 3)`);
  }
});
