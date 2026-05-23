// p227 — Issue #298 forward-defense contract test
// Locks in the fix from migration 20260805000007:
//   1. Cycle picker uses ORDER BY created_at DESC (deterministic)
//   2. Authorization gate scoped to picked cycle (sc.cycle_id = v_cycle.id)
//   3. Legacy permissive gate (JOIN selection_cycles ON phase='evaluating') is gone
//   4. Empty-cycle short-circuit precedes gate (no info leak)
//
// Cross-ref: docs/audit/CYCLE4_TRUST_AUDIT_P226.md (Code Bug A), PR #297 (audit doc),
//            GitHub issue #298.

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import fs from 'node:fs';
import path from 'node:path';

const MIGRATION_PATH = path.join(
  'supabase',
  'migrations',
  '20260805000007_p227_issue_298_get_my_pending_evaluations_cycle_deterministic.sql',
);

describe('#298: get_my_pending_evaluations() deterministic cycle picker + cycle-scoped gate', () => {
  let body = '';

  it('migration file exists', () => {
    assert.ok(
      fs.existsSync(MIGRATION_PATH),
      `expected migration at ${MIGRATION_PATH}`,
    );
    body = fs.readFileSync(MIGRATION_PATH, 'utf8');
    assert.ok(body.length > 0, 'migration body should not be empty');
  });

  it('picks newest evaluating cycle via ORDER BY created_at DESC (#298 fix part 1)', () => {
    // Match the cycle picker SELECT with ORDER BY clause between phase filter and LIMIT.
    const pattern =
      /SELECT\s+\*\s+INTO\s+v_cycle\s+FROM\s+public\.selection_cycles\s+WHERE\s+phase\s*=\s*'evaluating'\s+ORDER\s+BY\s+created_at\s+DESC\s+LIMIT\s+1/i;
    assert.match(body, pattern,
      'cycle picker must use ORDER BY created_at DESC for determinism');
  });

  it('authorization gate is scoped to the picked cycle (sc.cycle_id = v_cycle.id)', () => {
    assert.match(body, /sc\.cycle_id\s*=\s*v_cycle\.id/,
      'gate must scope membership lookup to picked cycle (sc.cycle_id = v_cycle.id)');
  });

  it('removes the legacy permissive gate using JOIN on selection_cycles + phase filter', () => {
    // The legacy gate was:
    //   IF NOT EXISTS (
    //     SELECT 1 FROM public.selection_committee sc
    //     JOIN public.selection_cycles c ON c.id = sc.cycle_id
    //     WHERE sc.member_id = v_caller_member_id AND c.phase = 'evaluating'
    //   )
    // This pattern allowed caller on ANY evaluating committee to pass, even when
    // the picker selected a different cycle. The new gate must NOT contain that JOIN.
    const legacyPattern =
      /JOIN\s+public\.selection_cycles\s+c\s+ON\s+c\.id\s*=\s*sc\.cycle_id/i;
    assert.doesNotMatch(body, legacyPattern,
      'legacy permissive gate (JOIN selection_cycles c) must not be re-introduced');
  });

  it('raises the cycle-scoped Unauthorized message', () => {
    assert.match(
      body,
      /RAISE EXCEPTION 'Unauthorized: caller is not on this cycle committee'/,
      'must raise cycle-scoped Unauthorized when caller not on picked cycle committee',
    );
  });

  it('retains can_by_member manage_member admin bypass', () => {
    assert.match(
      body,
      /public\.can_by_member\(v_caller_member_id,\s*'manage_member'\)/,
      'admin (manage_member) must retain bypass past the cycle-scoped gate',
    );
  });

  it('empty-cycle short-circuit precedes the authorization gate (no info leak)', () => {
    // Order required: picker -> empty-cycle check -> gate -> compute -> return
    // Strip SQL line comments first so descriptive header comments that quote the
    // patterns don't confuse position lookups.
    const codeOnly = body
      .split('\n')
      .filter((line) => !line.trim().startsWith('--'))
      .join('\n');
    const pickerIdx = codeOnly.search(
      /SELECT\s+\*\s+INTO\s+v_cycle[\s\S]*?ORDER\s+BY\s+created_at\s+DESC\s+LIMIT\s+1/i,
    );
    const emptyCheckIdx = codeOnly.search(
      /IF\s+v_cycle\.id\s+IS\s+NULL\s+THEN/i,
    );
    const gateIdx = codeOnly.search(
      /IF\s+NOT\s+EXISTS\s*\(\s*SELECT\s+1\s+FROM\s+public\.selection_committee/i,
    );
    assert.ok(pickerIdx > 0, 'cycle picker line found in code');
    assert.ok(emptyCheckIdx > 0, 'empty-cycle check found in code');
    assert.ok(gateIdx > 0, 'authorization gate found in code');
    assert.ok(
      emptyCheckIdx > pickerIdx,
      'empty-cycle check (IF v_cycle.id IS NULL) must come after picker',
    );
    assert.ok(
      gateIdx > emptyCheckIdx,
      'authorization gate must come after empty-cycle short-circuit',
    );
  });

  it('NOTIFY pgrst is issued for PostgREST schema cache reload', () => {
    assert.match(
      body,
      /NOTIFY\s+pgrst,\s*'reload schema'/i,
      'migration must issue NOTIFY pgrst at end (RPC signature reload)',
    );
  });
});
