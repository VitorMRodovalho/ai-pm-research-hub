/**
 * Contract: #1476 Onda 1 — tribe belonging derives from ACTIVE ENGAGEMENT (canonical set
 * `v_tribe_active_members`), NOT from the `operational_role` display cache.
 *
 * Migration: supabase/migrations/20260805000484_1476_wave1_tribe_membership_canonical.sql
 *
 * Root cause: ~16 functions used `operational_role NOT IN ('sponsor','chapter_liaison','guest','none')`
 * as a proxy for tribe membership. A member who is BOTH a chapter focal point AND an active tribe
 * researcher has the cache resolved to 'chapter_liaison' ("governança vence") and is erased from the
 * tribe's grids/counts despite an active volunteer engagement. Symptom: get_tribe_attendance_grid(7)
 * returned 5 members while the real roster was 6 (the researcher's attendance was silently swallowed).
 *
 * Fix (Onda 1, tribe-scoped only — org-wide/write-path + the #1437 canonical metric are Onda 2):
 * a single canonical view `v_tribe_active_members` (engagement SSOT) consumed by the 6 tribe-scoped
 * functions. Behaviour proven live via impersonated QA in the PR: tribe 7 grid 5 -> 6; count deltas
 * limited to tribes 1 (7->8) and 7 (5->6), every other tribe unchanged.
 *
 * These are STATIC assertions on the migration file (the DB behaviour depends on auth.uid() and live
 * engagement rows, so it can't be driven from a service-role client without mutating prod).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');

const MIG = 'supabase/migrations/20260805000484_1476_wave1_tribe_membership_canonical.sql';
const mig = read(MIG);

// The 6 tribe-scoped functions rebased onto the canonical set in Onda 1.
const TRIBE_FUNCTIONS = [
  'count_tribe_slots',
  'get_tribe_attendance_grid',
  'get_tribe_events_timeline',
  'request_tribe_assignment',
  'review_tribe_request',
  'exec_cycle_report',
];

test('#1476: migration present', () => {
  assert.ok(existsSync(resolve(ROOT, MIG)), 'migration file present');
});

test('#1476: canonical view exists with the load-bearing security posture', () => {
  assert.match(mig, /CREATE OR REPLACE VIEW public\.v_tribe_active_members AS/, 'view defined');
  // engagement is the SSOT: active volunteer engagement in a research_tribe initiative
  assert.match(mig, /e\.kind = 'volunteer'/, 'gated on volunteer engagement');
  assert.match(mig, /e\.status = 'active'/, 'gated on active engagement');
  assert.match(mig, /i\.kind = 'research_tribe'/, 'scoped to research_tribe initiatives');
  // #1422 lesson: security_invoker=on + REVOKE from anon/authenticated is load-bearing
  assert.match(mig, /ALTER VIEW public\.v_tribe_active_members SET \(security_invoker = on\)/, 'security_invoker=on');
  assert.match(mig, /REVOKE ALL ON public\.v_tribe_active_members FROM PUBLIC, anon, authenticated/, 'revoked from low-priv roles');
});

test('#1476: all 6 tribe-scoped functions are recaptured and consume the canonical set', () => {
  for (const fn of TRIBE_FUNCTIONS) {
    const re = new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}\\(`);
    assert.match(mig, re, `${fn} recaptured in the migration`);
  }
  // every function body references the canonical view (no per-site engagement predicate duplication)
  const viewRefs = (mig.match(/v_tribe_active_members/g) || []).length;
  assert.ok(viewRefs >= 7, `canonical view referenced in each consumer (found ${viewRefs})`);
});

test('#1476: no operational_role label filter survives as a tribe-membership proxy', () => {
  // The only operational_role NOT IN(...) mention allowed is in the header comment describing the bug.
  const codeLines = mig.split('\n').filter((l) => !l.trimStart().startsWith('--'));
  const offending = codeLines.filter((l) => /operational_role\s+NOT IN/.test(l));
  assert.equal(offending.length, 0, `no residual label-based membership filter (found: ${offending.join(' | ')})`);
});

test('#1476: exec_cycle_report rebases BOTH member-count sites (overcount + undercount)', () => {
  // Both the v_tribes member_count and the v_att_by_tribe members_count now derive from the canonical set.
  const both = (mig.match(/SELECT count\(\*\) FROM public\.v_tribe_active_members v WHERE v\.legacy_tribe_id = t\.id/g) || []).length;
  assert.ok(both >= 2, `both exec_cycle_report count sites rebased (found ${both})`);
});
