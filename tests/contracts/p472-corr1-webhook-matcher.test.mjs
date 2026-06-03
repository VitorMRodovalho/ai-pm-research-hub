/**
 * Contract: #472 correction #1 — WEBHOOK MIRROR (production-effect follow-up).
 *
 * corr-1 (migration 20260805000091) hardened the canonical RPC
 * sync_calendar_booking_to_interview, but the LIVE booking ingress is the Astro
 * route src/pages/api/calendar-webhook.ts. This change moves the matching upgrade
 * into production by giving the webhook a shared read-only matcher
 * match_booking_application(guest_email) — exact LOWER(TRIM) email match (no
 * `_`/`%` wildcard trap, since selection_applications.email is `text` and the old
 * `.ilike('email', guest)` mis-matched real addresses like `j_coelho@id.uff.br`),
 * OPEN/ACTIVE cycle scope, a same-member alternate-email bridge (member_emails),
 * and the pre-interview status allow-list — and by resolving interviewer emails
 * via member_emails (citext) instead of members.email only.
 *
 * Two-surface alignment (matcher SQL ⊣ webhook TS) is asserted statically, the
 * same pattern used for the worker↔migration ladder parity in corr-2.
 *
 * Cross-ref: issue #472 (B1); migration 20260805000091 (canonical RPC corr-1);
 * 20260805000096 (this matcher).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000096_472_corr1_webhook_booking_matcher.sql');
const WEBHOOK = resolve(ROOT, 'src/pages/api/calendar-webhook.ts');

const migRaw = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
// strip line comments so asserts match real SQL, not documentation that
// intentionally mentions the old anti-pattern (`.ilike`, the `_` wildcard).
const mig = migRaw.replace(/^\s*--.*$/gm, '');
const webhookRaw = existsSync(WEBHOOK) ? readFileSync(WEBHOOK, 'utf8') : '';
// strip JS/TS comments for forward-defense regexes
const webhook = webhookRaw.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

function fnBody(src, name) {
  const re = new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\b[\\s\\S]*?\\$function\\$([\\s\\S]*?)\\$function\\$`, 'i');
  const m = src.match(re);
  return m ? m[1] : null;
}

// ── STATIC: matcher migration ────────────────────────────────────────────────
test('472-c1-webhook static: matcher migration 20260805000096 exists', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000096 present');
});

test('472-c1-webhook static: matcher uses exact LOWER(TRIM) email match (no ilike wildcard trap)', () => {
  const body = fnBody(mig, 'match_booking_application');
  assert.ok(body, 'match_booking_application defined');
  assert.match(body, /LOWER\(TRIM\(a\.email\)\) = v_guest/, 'exact case-insensitive primary match');
  assert.ok(!/ILIKE/i.test(body), 'matcher must NOT use ILIKE (text column → `_`/`%` wildcard trap)');
});

test('472-c1-webhook static: matcher mirrors corr-1 — cycle scope, member_emails bridge, status allow-list, ordering', () => {
  const body = fnBody(mig, 'match_booking_application');
  assert.match(body, /c\.status IN \('open', 'active'\)/, 'OPEN/ACTIVE cycle scope');
  assert.match(body, /a\.status IN \('submitted', 'screening', 'objective_eval', 'objective_cutoff',\s*'interview_pending', 'interview_scheduled'\)/,
    'pre-interview status allow-list (never re-opens a decided/terminal app)');
  // alternate-email bridge requires the SAME member_id on both sides (no cross-candidate risk)
  assert.match(body, /SELECT me\.member_id INTO v_guest_member_id[\s\S]*?FROM public\.member_emails me\s+WHERE me\.email = v_guest::citext/,
    'resolves the guest email to a member via member_emails');
  assert.match(body, /v_guest_member_id IS NOT NULL\s*\n?\s*AND EXISTS \(\s*\n?\s*SELECT 1 FROM public\.member_emails me2\s+WHERE me2\.member_id = v_guest_member_id/,
    'alternate match requires the application email to belong to the SAME member');
  assert.match(body, /ORDER BY \(LOWER\(TRIM\(a\.email\)\) = v_guest\) DESC,\s*\n?\s*c\.open_date DESC NULLS LAST,\s*\n?\s*a\.created_at DESC/,
    'tie-break: primary > most-recent open cycle > newest application');
});

test('472-c1-webhook static: matcher grant ladder — SERVICE_ROLE ONLY (no authenticated PII enumeration)', () => {
  assert.match(mig, /REVOKE ALL ON FUNCTION public\.match_booking_application\(text\) FROM PUBLIC, anon, authenticated/, 'anon/public/authenticated revoked');
  assert.match(mig, /GRANT EXECUTE ON FUNCTION public\.match_booking_application\(text\) TO service_role\b/, 'granted to service_role only');
  // SECURITY DEFINER + returns applicant_name/status for any email → must NOT reach `authenticated`
  assert.ok(!/GRANT EXECUTE ON FUNCTION public\.match_booking_application\(text\)[^;]*\bauthenticated\b/.test(mig),
    'REGRESSION: matcher granted to authenticated — any member could enumerate candidate PII by email');
  assert.match(migRaw, /NOTIFY pgrst, 'reload schema'/);
});

test('472-c1-webhook static: dead-path RPC sync_calendar_booking_to_interview locked to service_role (corr-1 hardening)', () => {
  assert.match(mig, /REVOKE ALL ON FUNCTION public\.sync_calendar_booking_to_interview\(jsonb\) FROM PUBLIC, anon, authenticated/,
    'inherited anon/authenticated grant revoked on the dead-path RPC');
  assert.match(mig, /GRANT EXECUTE ON FUNCTION public\.sync_calendar_booking_to_interview\(jsonb\) TO service_role\b/, 'granted to service_role only');
});

test('472-c1-webhook static: webhook logs unmatched + synced bookings (corr-5 observability)', () => {
  assert.match(webhook, /action:\s*'calendar_booking_unmatched'/, 'unmatched booking logged → corr-5 consistency cron can detect B1 recurrence');
  assert.match(webhook, /action:\s*'calendar_booking_synced'/, 'synced booking logged → audit parity with the canonical RPC');
});

// ── STATIC: webhook wiring ───────────────────────────────────────────────────
test('472-c1-webhook static: webhook calls match_booking_application (and no longer .ilike on email)', () => {
  assert.ok(existsSync(WEBHOOK), 'calendar-webhook.ts present');
  assert.match(webhook, /\.rpc\('match_booking_application',\s*\{\s*p_guest_email:\s*guest_email/,
    'webhook resolves the candidate via the shared matcher RPC');
  // forward-defense: the buggy primary-only `.ilike('email', ...)` lookup must not return
  assert.ok(!/\.ilike\(\s*'email'/.test(webhook),
    'REGRESSION: webhook re-introduced .ilike(\'email\', ...) — `_`/`%` wildcard trap on a text column (#472 corr.1)');
});

test('472-c1-webhook static: interviewer resolution via member_emails, not members.email', () => {
  assert.match(webhook, /from\('member_emails'\)\s*\n?\s*\.select\('member_id'\)\s*\n?\s*\.in\('email',\s*normalizedInterviewerEmails\)/,
    'interviewers resolved through member_emails (citext, primary + alternates)');
  // forward-defense: the old members.email-only interviewer lookup must not return
  assert.ok(!/from\('members'\)\s*\n?\s*\.select\('id'\)\s*\n?\s*\.in\('email',\s*interviewer_emails\)/.test(webhook),
    'REGRESSION: interviewers resolved via members.email only — misses alternate/personal interviewer emails (#472 corr.1)');
  assert.match(webhook, /matched_by:\s*matchedBy/, 'matched_by surfaced in the response (audit parity with the RPC)');
});

// ── BEHAVIOURAL (DB-gated) ───────────────────────────────────────────────────
test('472-c1-webhook behavioural: matcher returns EMPTY for a non-matching email', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('match_booking_application', { p_guest_email: 'definitely-nobody@example.invalid' });
  assert.ifError(error);
  assert.ok(Array.isArray(data), 'TABLE-returning RPC yields an array');
  assert.equal(data.length, 0, 'no match → empty set (no false attach)');
});

test('472-c1-webhook behavioural: a real open/active pre-interview candidate matches by primary', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // pick any current open/active pre-interview application (deterministic read; skips if cohort empty)
  const { data: apps } = await sb
    .from('selection_applications')
    .select('email, selection_cycles!inner(status)')
    .in('status', ['interview_pending', 'interview_scheduled', 'objective_cutoff', 'submitted'])
    .in('selection_cycles.status', ['open', 'active'])
    .not('email', 'is', null)
    .limit(1);
  const probe = apps?.[0];
  if (!probe) return; // no live cohort — nothing to assert, not a failure
  const { data, error } = await sb.rpc('match_booking_application', { p_guest_email: String(probe.email).toUpperCase() });
  assert.ifError(error);
  assert.equal(data.length, 1, 'a known candidate email resolves to exactly one application');
  assert.equal(data[0].matched_by, 'primary', 'direct email hit is flagged primary (case-insensitive — probed UPPERCASE)');
});
