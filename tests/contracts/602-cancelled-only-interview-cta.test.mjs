/**
 * Contract: #602 — cancelled-only interviews must NOT hide the "Iniciar avaliação ao vivo" CTA.
 *
 * Bug (live, 2026-06-08, Rafael Bellotti): a candidate whose ONLY interview row was
 * `cancelled` (status reset to `interview_pending`) could not be evaluated — the
 * start-CTA / cutoff-invite / offline paths were gated on `!interviews?.length`, so one
 * cancelled row was enough to skip the branch, and the else-branch picked the cancelled
 * row as "active" (no scoring affordance, no re-start path). 2 live-funnel candidates
 * were trapped at fix time (grounded 2026-06-10).
 *
 * Fix (frontend-only): gate on "no ACTIONABLE interview" — actionable = status NOT in
 * TERMINAL (cancelled/noshow/rescheduled). The terminal history stays visible in that
 * branch via the shared buildInterviewHistoryHtml helper (acceptance criterion 2).
 *
 * This is a static source contract (no DB): it locks the gate predicate, the forward
 * defense against the old length-based gate, the shared history rendering in BOTH
 * branches, and the CTA/cutoff/offline affordances.
 *
 * Cross-ref: issue #602; p109 Onda 4 (CTA origin); p271 #411 W1a (cutoff invite);
 * p152 W4 (history timeline).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const PAGE = resolve(ROOT, 'src/pages/admin/selection.astro');
const src = existsSync(PAGE) ? readFileSync(PAGE, 'utf8') : '';

const TERMINAL_EXPECTED = ['cancelled', 'noshow', 'rescheduled'];

test('602 static: selection.astro exists', () => {
  assert.ok(existsSync(PAGE), 'admin selection page present');
});

test('602 static: TERMINAL_INTERVIEW_STATUSES declared with exactly the 3 terminal statuses', () => {
  const m = src.match(/const TERMINAL_INTERVIEW_STATUSES = \[([^\]]+)\]/);
  assert.ok(m, 'TERMINAL_INTERVIEW_STATUSES declared');
  const listed = [...m[1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]);
  assert.deepEqual(listed, TERMINAL_EXPECTED,
    'terminal set is exactly cancelled/noshow/rescheduled — scheduled & completed stay actionable');
});

test('602 static: gate is hasActionableInterview, derived from the terminal set', () => {
  assert.match(src,
    /const hasActionableInterview = interviews\.some\(\(i: any\) => !TERMINAL_INTERVIEW_STATUSES\.includes\(i\.status\)\)/,
    'actionable predicate = some row whose status is NOT terminal');
  assert.match(src, /if \(!hasActionableInterview\) \{/,
    'start-CTA branch gated on the actionable predicate');
});

test('602 forward-defense: the old zero-rows gate is gone', () => {
  assert.ok(!/if \(!interviews\?\.length\)/.test(src),
    'the `!interviews?.length` gate must not return — one cancelled row would re-hide the CTA');
});

test('602 static: terminal history stays visible in the no-actionable branch (null active id)', () => {
  // Acceptance criterion 2: cancelled rows remain visible as history next to the CTA.
  // (Loose match — whitespace-independent; council code-reviewer LOW.)
  assert.match(src, /buildInterviewHistoryHtml\(interviews,\s*null\)/,
    'no-actionable branch appends the history timeline with no active row');
});

test('602 static: history renders BEFORE the start-live CTA (context before decision — council UX HIGH)', () => {
  const historyAt = src.indexOf('buildInterviewHistoryHtml(interviews, null)');
  const ctaAt = src.indexOf('id="start-live-interview-btn"');
  assert.ok(historyAt > -1 && ctaAt > -1, 'both anchors present');
  assert.ok(historyAt < ctaAt,
    'admin must see WHY there is no active interview before choosing a recovery action');
});

test('602 static: live-CTA heading is contextual — never claims "sem entrevista" over visible history (council UX HIGH)', () => {
  assert.match(src, /interviews\.length\s*\n?\s*\? 'Nenhuma entrevista ativa — as anteriores foram encerradas'\s*\n?\s*: 'Sem entrevista agendada'/,
    'heading ternary: terminal-history variant vs zero-rows variant');
});

test('602 static: start-live with prior terminal rows is confirm-gated (council gp-leader MEDIUM)', () => {
  assert.match(src, /if \(interviews\.length && !confirm\(`Candidato tem \$\{interviews\.length\} entrevista\(s\) anterior\(es\) encerrada\(s\)/,
    'one accidental click must not create yet another interview row; zero-rows path stays frictionless');
});

test('602 static: history builder is shared — defined once, used by both branches', () => {
  const defs = src.match(/const buildInterviewHistoryHtml = \(/g) || [];
  assert.equal(defs.length, 1, 'single definition of the history builder');
  assert.match(src, /buildInterviewHistoryHtml\(interviews, interview\.id\)/,
    'actionable branch renders history bound to the active interview');
  // The old inline duplicate (separate statusBadgeColor const) must not survive.
  assert.ok(!/const statusBadgeColor = /.test(src),
    'badge-color map lives only inside the shared helper (interviewStatusBadgeColor)');
  assert.match(src, /const interviewStatusBadgeColor = /, 'shared badge-color helper present');
});

test('602 static: per-row action buttons still render ONLY for scheduled rows', () => {
  assert.match(src, /const actions = intv\.status === 'scheduled'/,
    'terminal rows render with no per-row actions (so the no-actionable branch never emits unwired buttons)');
});

test('602 static: recovery affordances intact (CTA, cutoff invite, offline record)', () => {
  assert.match(src, /id="start-live-interview-btn"/, 'live-start CTA present');
  assert.match(src, /Iniciar avaliação ao vivo/, 'CTA label present');
  assert.match(src, /id="cutoff-invite-btn"/, 'cutoff-invite dispatch button present');
  assert.match(src, /id="record-offline-interview-btn"/, 'offline record path present');
  // Both trapped live states must be able to reach the live-start CTA.
  assert.match(src,
    /const canStartLive = \['interview_pending', 'interview_scheduled', 'interview_done'\]\.includes\(row\.status\)/,
    'canStartLive covers interview_pending AND interview_scheduled (both observed trap states)');
});

test('602 behavioural: gate predicate replayed from source against the trap scenarios', () => {
  // Extract the terminal list from the SOURCE (not this file) and replay the predicate,
  // so a source-side edit to the set is exercised here.
  const m = src.match(/const TERMINAL_INTERVIEW_STATUSES = \[([^\]]+)\]/);
  const TERMINAL = [...m[1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]);
  const hasActionable = (rows) => rows.some((i) => !TERMINAL.includes(i.status));

  // Rafael scenario: single cancelled row → branch must offer the CTA.
  assert.equal(hasActionable([{ status: 'cancelled' }]), false, 'cancelled-only → no actionable → CTA branch');
  // ca50… scenario: 3 terminal rows (cancelled/noshow/rescheduled) → CTA branch.
  assert.equal(
    hasActionable([{ status: 'cancelled' }, { status: 'noshow' }, { status: 'rescheduled' }]),
    false, 'all-terminal mix → CTA branch');
  // Regressions: an actionable row must keep the normal scoring branch.
  assert.equal(hasActionable([{ status: 'cancelled' }, { status: 'scheduled' }]), true,
    'cancelled + scheduled → actionable branch (scoring)');
  assert.equal(hasActionable([{ status: 'completed' }]), true, 'completed → actionable branch');
  // 'pending' is DB-valid (schema default) but no write RPC creates it — documented dead path.
  assert.equal(hasActionable([{ status: 'pending' }]), true,
    'pending → actionable branch (legacy schema default; no live rows today)');
  // Zero rows is the degenerate case of no-actionable (same branch as before the fix).
  assert.equal(hasActionable([]), false, 'no rows → hasActionable=false → CTA branch (degenerate no-actionable case)');
});
