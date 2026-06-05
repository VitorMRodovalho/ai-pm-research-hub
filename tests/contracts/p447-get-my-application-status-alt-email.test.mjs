/**
 * #447 contract test — get_my_application_status honors alternate emails
 *
 * Gap (sibling of #444, discovered during #445/#477 member_emails work):
 *   `get_my_application_status()` matched the candidate's application by the
 *   member's PRIMARY email only:
 *       WHERE lower(trim(a.email)) = lower(trim(v_caller.email))
 *   So an application whose canonical `selection_applications.email` is a
 *   reconciled ALTERNATE of the candidate (legitimate post-member_emails)
 *   was invisible in that candidate's own self-view — even with invariant R
 *   green and the app↔member link intact. Live case: Paulo / app 6259ced2
 *   (point-remediated in PR #446; the RPC narrowness remained for any future case).
 *
 * Fix (migration 20260805000108): expand the match to the caller's primary
 *   email UNION their member_emails alternates.
 *
 * Why static + DB-gated (not a behavioural impersonation test):
 *   get_my_application_status is SECURITY DEFINER and gates on auth.uid(); the
 *   service-role test client cannot impersonate a member (auth.uid() is null),
 *   so — per house convention (p239b, p277-419-m5-d1, p277-triage invariant-R) —
 *   the body is asserted statically + forward-defended, and the security premise
 *   (no email maps to >1 member) is asserted as a DB-gated invariant.
 *
 * Cross-ref: #447, #444/#446 (clobber remediation), #445/#477 (invariant R honors
 *   alternates), member_emails_email_key UNIQUE (global alternate uniqueness).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const FIX_FILE = '20260805000108_p447_get_my_application_status_alt_email_match.sql';

const stripComments = (s) => s.replace(/--[^\n]*/g, '');

function loadMigrations() {
  const files = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort();
  return files.map((f) => ({ name: f, content: readFileSync(join(MIGRATIONS_DIR, f), 'utf8') }));
}
const migrations = loadMigrations();
const FIX = readFileSync(join(MIGRATIONS_DIR, FIX_FILE), 'utf8');
const fixCode = stripComments(FIX);

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── (A) the fix body matches primary OR alternate ──────────────────────────────
test('#447: fix migration exists and redeclares get_my_application_status', () => {
  assert.ok(FIX, 'fix migration file present');
  assert.match(fixCode, /CREATE OR REPLACE FUNCTION public\.get_my_application_status\(\)/);
});

test('#447: match is an IN(...) over primary UNION member_emails alternates', () => {
  // membership test against a set, not a bare scalar equality
  assert.match(fixCode, /WHERE lower\(trim\(a\.email\)\) IN \(/);
  // primary preserved (caller's members.email)
  assert.match(fixCode, /FROM public\.members m\s+WHERE m\.id = v_caller\.id/);
  // new alternate clause (caller's member_emails)
  assert.match(fixCode, /FROM public\.member_emails me\s+WHERE me\.member_id = v_caller\.id/);
  // the two are unioned
  assert.match(fixCode, /\bUNION\b/);
});

test('#447: the old primary-only scalar equality is gone (regression form)', () => {
  // the pre-#447 narrow match must not be the operative clause anymore
  assert.ok(
    !/lower\(trim\(a\.email\)\)\s*=\s*lower\(trim\(v_caller\.email\)\)/.test(fixCode),
    'must not match by primary email only (bare equality)'
  );
});

// ── (B) forward-defense: latest declaration must keep the alternate match ───────
test('#447: latest migration declaring the RPC keeps the alternate-email UNION', () => {
  const decls = migrations.filter((m) =>
    /CREATE OR REPLACE FUNCTION public\.get_my_application_status\b/.test(m.content)
  );
  assert.ok(decls.length >= 1, 'at least one declaration exists');
  const latest = decls[decls.length - 1]; // readdir sorted ascending → last = highest version
  assert.strictEqual(latest.name, FIX_FILE, `latest declarer should be ${FIX_FILE}, got ${latest.name}`);
  const latestCode = stripComments(latest.content);
  assert.match(latestCode, /FROM public\.member_emails me\s+WHERE me\.member_id = v_caller\.id/,
    'a later migration must not revert get_my_application_status to primary-email-only matching');
});

// ── (C) DB-gated ────────────────────────────────────────────────────────────────
test('DB: get_my_application_status is live and graceful for service-role (auth.uid null)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // service-role has no member row → returns {error:'not_authenticated'} jsonb, NOT a 500/raise.
  const { data, error } = await sb.rpc('get_my_application_status');
  assert.ok(!error, `RPC must not throw: ${error?.message}`);
  assert.strictEqual(data?.error, 'not_authenticated');
});

test('DB: no email maps to >1 member — leak-safety premise for the UNION match', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data: members, error: e1 } = await sb.from('members').select('id,email').not('email', 'is', null);
  assert.ok(!e1, e1?.message);
  const { data: alts, error: e2 } = await sb.from('member_emails').select('member_id,email');
  assert.ok(!e2, e2?.message);

  const map = new Map(); // lower(email) → Set(member_id)
  const add = (em, mid) => {
    if (!em) return;
    const k = String(em).trim().toLowerCase();
    if (!map.has(k)) map.set(k, new Set());
    map.get(k).add(mid);
  };
  for (const m of members) add(m.email, m.id);
  for (const a of alts) add(a.email, a.member_id);

  const collisions = [...map.values()].filter((s) => s.size > 1).length;
  assert.strictEqual(collisions, 0,
    `${collisions} email(s) map to >1 member — the UNION could surface another person's application`);
});
