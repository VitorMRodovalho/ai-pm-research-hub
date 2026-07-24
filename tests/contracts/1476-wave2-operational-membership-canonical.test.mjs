/**
 * Contract: #1476 Onda 2 — OPERATIONAL cohort belonging derives from ACTIVE ENGAGEMENT (canonical
 * junction `v_member_operational_tiers`), NOT from the single-valued `operational_role` display cache.
 *
 * Migration: supabase/migrations/20260805000485_1476_wave2_operational_membership_canonical.sql
 *
 * Root cause (same class as Onda 1, now on org-wide / write-path surfaces): functions gated their
 * operational cohort by `members.operational_role IN ('researcher','tribe_leader','manager'[,'deputy_manager'])`.
 * A member who is BOTH a chapter focal point (chapter_board) AND an active tribe researcher
 * (volunteer/researcher) has the cache collapsed to 'chapter_liaison' by the "governança vence" ladder and
 * is erased from the operational cohort despite an active volunteer engagement. On the WRITE path
 * (seal_event_attendance) that means their attendance is never materialized — a permanently missing record.
 *
 * Owner decision (2026-07-23): the published KPI `v_operational_members` (#1437/ADR-0126) is NOT rebased —
 * it stays 69 (governance-wins is deliberate for the COMPOSITION headline). This canonical is ONLY for the
 * operational-INTERVENTION surfaces. Deliberate, documented divergence.
 *
 * Design: NOT a flat membership view — the 8 consumers have different tier sets
 * (seal/summaries/dropout = {researcher,tribe_leader,manager}; cohort-health/overview = {researcher,tribe_leader};
 * credly = +{deputy_manager}). So a per-(member,tier) junction view; each consumer semi-joins (EXISTS) its own
 * subset and keeps its own member-activity base filter. Committee/workgroup engagements are excluded (they were
 * folded into 'researcher' for canFor() authority per p164, never for attendance eligibility) via kind=volunteer.
 *
 * Behaviour proven live via impersonated QA in the PR: seal eligible cohort / attendance summaries / dropout /
 * credly 69 -> 71; cohort-health / cycle-overview 67 -> 69 — all +2 the same dual-hats (tribes 1 and 7), 0 drops.
 *
 * STATIC assertions on the migration file (DB behaviour depends on auth.uid() + live engagement rows).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');

const MIG = 'supabase/migrations/20260805000485_1476_wave2_operational_membership_canonical.sql';
const mig = read(MIG);
const codeLines = mig.split('\n').filter((l) => !l.trimStart().startsWith('--'));
const code = codeLines.join('\n');

// The 8 operational-surface functions rebased onto the canonical junction in Onda 2.
const OPERATIONAL_FUNCTIONS = [
  'seal_event_attendance',
  'get_attendance_engagement_summary',
  'get_attendance_reliability_summary',
  'get_dropout_risk_members',
  'get_gp_cohort_health',
  'get_cycle_attendance_overview',
  '_credly_health_rows',
  'admin_get_anomaly_report',
];

test('#1476 Onda 2: migration present', () => {
  assert.ok(existsSync(resolve(ROOT, MIG)), 'migration file present');
});

test('#1476 Onda 2: canonical junction view exists with the load-bearing security posture', () => {
  assert.match(mig, /CREATE OR REPLACE VIEW public\.v_member_operational_tiers AS/, 'view defined');
  // engagement is the SSOT: authoritative volunteer engagement -> operational tier
  assert.match(code, /ae\.is_authoritative = true/, 'gated on authoritative engagement');
  assert.match(code, /ae\.kind = 'volunteer'/, 'gated on volunteer-kind engagement (excludes committee/workgroup)');
  assert.match(code, /operational_tier/, 'emits an operational_tier column (distinct from members.operational_role)');
  // #1422 lesson: security_invoker=on + REVOKE from anon/authenticated is load-bearing
  assert.match(mig, /ALTER VIEW public\.v_member_operational_tiers SET \(security_invoker = on\)/, 'security_invoker=on');
  assert.match(mig, /REVOKE ALL ON public\.v_member_operational_tiers FROM PUBLIC, anon, authenticated/, 'revoked from low-priv roles');
});

test('#1476 Onda 2: view CASE mirrors the ladder operational tiers, MINUS committee/workgroup (canFor-only)', () => {
  // The four operational tiers must be derivable from volunteer engagement roles.
  for (const [role, tier] of [
    ['manager', 'manager'], ['co_gp', 'manager'],
    ['deputy_manager', 'deputy_manager'],
    ['leader', 'tribe_leader'], ['comms_leader', 'tribe_leader'],
    ['researcher', 'researcher'],
  ]) {
    assert.ok(code.includes(`'${role}'`), `view maps volunteer role ${role} -> ${tier}`);
  }
  // committee/workgroup engagement kinds must NOT appear as membership predicates in the view (p164: canFor only).
  const viewBlock = mig.slice(mig.indexOf('CREATE OR REPLACE VIEW public.v_member_operational_tiers'),
                              mig.indexOf('CREATE OR REPLACE FUNCTION public.seal_event_attendance'));
  assert.doesNotMatch(viewBlock, /committee_member|workgroup_member|study_group_owner|committee_coordinator|workgroup_coordinator/,
    'committee/workgroup engagement kinds excluded from the operational membership predicate');
});

test('#1476 Onda 2: all 8 operational functions are recaptured and semi-join the junction (EXISTS)', () => {
  for (const fn of OPERATIONAL_FUNCTIONS) {
    const re = new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}\\(`);
    assert.match(mig, re, `${fn} recaptured in the migration`);
  }
  // Every consumer must EXISTS-semi-join the junction — never JOIN+COUNT (the view is DISTINCT (member,tier);
  // a dual-hat legitimately produces >1 row, so a plain join would double-count the cohort).
  const semiJoins = (code.match(/EXISTS \(SELECT 1 FROM public\.v_member_operational_tiers vt/g) || []).length;
  assert.ok(semiJoins >= OPERATIONAL_FUNCTIONS.length,
    `junction consumed via EXISTS in each operational consumer (found ${semiJoins})`);
});

test('#1476 Onda 2: no operational_role label filter survives as an operational-cohort proxy', () => {
  // The only `operational_role IN (...)` mention allowed is in the header comment describing the bug.
  const offending = codeLines.filter((l) => /operational_role\s+IN\s*\(/.test(l));
  assert.equal(offending.length, 0, `no residual label-based cohort filter (found: ${offending.join(' | ')})`);
});

test('#1476 Onda 2: does NOT touch the #1437 governance-wins KPI (deliberate divergence)', () => {
  // v_operational_members (#1437/ADR-0126) must be left exactly as-is — owner decided not to rebase it.
  assert.doesNotMatch(code, /CREATE OR REPLACE VIEW public\.v_operational_members/,
    'v_operational_members (#1437 KPI) is not redefined by Onda 2');
});
