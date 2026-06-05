/**
 * #511 contract test — sibling self-service RPCs honor alternate emails
 *
 * Gap (sweep sibling of #447): five self-service RPCs resolved the candidate's
 *   application by the member's PRIMARY email only —
 *       WHERE lower(trim(a.email)) = lower(trim(v_caller.email))   (4 RPCs)
 *       WHERE sa.email = v_member_email                            (export_my_data)
 *   so an application whose canonical `selection_applications.email` is a
 *   reconciled ALTERNATE (post-#445 member_emails) was invisible on the
 *   candidate's own surface — and, for `export_my_data()`, OMITTED FROM THE
 *   LGPD Art.18 data export entirely.
 *
 * Affected RPCs (all fixed in migration 20260805000110):
 *   export_my_data(), get_my_selection_result(), get_my_evaluation_feedback(),
 *   update_my_application(jsonb), upload_my_resume(text,text).
 *
 * Fix: expand each match to the caller's primary email UNION their
 *   member_emails alternates — the exact #447 pattern.
 *
 * Why static + DB-gated (not a behavioural impersonation test):
 *   all five are SECURITY DEFINER and gate on auth.uid(); the service-role test
 *   client cannot impersonate a member (auth.uid() is null), so — per house
 *   convention (p239b, p447) — the bodies are asserted statically + forward-
 *   defended, and the security premise (no email maps to >1 member) is asserted
 *   as a DB-gated invariant. Liveness is asserted by calling each RPC as
 *   service-role and checking it gates gracefully (no member row → not_authenticated).
 *
 * Cross-ref: #511, #447 (get_my_application_status, the original), #445/#477
 *   (member_emails alternates), member_emails_email_key UNIQUE (global uniqueness).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const FIX_FILE = '20260805000110_p511_sibling_rpcs_alt_email.sql';

const RPCS = [
  'export_my_data',
  'get_my_selection_result',
  'get_my_evaluation_feedback',
  'update_my_application',
  'upload_my_resume',
];

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

// ── (A) the fix redeclares all 5 RPCs ───────────────────────────────────────────
test('#511: fix migration exists and redeclares all 5 sibling RPCs', () => {
  assert.ok(FIX, 'fix migration file present');
  for (const fn of RPCS) {
    const re = new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}\\b`);
    assert.match(fixCode, re, `${fn} must be redeclared in the fix migration`);
  }
});

// ── (B) every match is an IN(...) over primary UNION member_emails alternates ────
test('#511: every RPC matches by IN(...) over primary UNION member_emails alternates', () => {
  // membership test against a set, not a bare scalar equality
  const inClauses = fixCode.match(/WHERE lower\(trim\((?:a|sa)\.email\)\) IN \(/g) || [];
  assert.ok(inClauses.length >= 5, `expected >=5 IN(...) email matches, found ${inClauses.length}`);
  // 4 RPCs key off v_caller.id, export_my_data keys off v_member_id
  const callerAlts = fixCode.match(/FROM public\.member_emails me\s+WHERE me\.member_id = v_caller\.id/g) || [];
  const exportAlts = fixCode.match(/FROM public\.member_emails me\s+WHERE me\.member_id = v_member_id/g) || [];
  assert.strictEqual(callerAlts.length, 4, `expected 4 v_caller.id alternate clauses, found ${callerAlts.length}`);
  assert.strictEqual(exportAlts.length, 1, `expected 1 v_member_id alternate clause (export_my_data), found ${exportAlts.length}`);
  // primary side preserved (members.email)
  assert.match(fixCode, /FROM public\.members m\s+WHERE m\.id = v_caller\.id/);
  assert.match(fixCode, /FROM public\.members m\s+WHERE m\.id = v_member_id/);
});

test('#511: the old primary-only predicates are gone (regression form)', () => {
  assert.ok(
    !/lower\(trim\(a\.email\)\)\s*=\s*lower\(trim\(v_caller\.email\)\)/.test(fixCode),
    'must not match by primary email only (bare equality)'
  );
  assert.ok(
    !/sa\.email\s*=\s*v_member_email/.test(fixCode),
    'export_my_data must not match by members.email scalar (sa.email = v_member_email)'
  );
});

// ── (C) forward-defense: latest declaration of each RPC keeps the alternate match ─
test('#511: latest migration declaring each RPC keeps the alternate-email UNION', () => {
  for (const fn of RPCS) {
    const re = new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}\\b`);
    const decls = migrations.filter((m) => re.test(m.content));
    assert.ok(decls.length >= 1, `at least one declaration of ${fn} exists`);
    const latest = decls[decls.length - 1]; // readdir sorted ascending → last = highest version
    assert.strictEqual(latest.name, FIX_FILE, `latest declarer of ${fn} should be ${FIX_FILE}, got ${latest.name}`);
    const latestCode = stripComments(latest.content);
    assert.match(latestCode, /FROM public\.member_emails me\s+WHERE me\.member_id =/,
      `a later migration must not revert ${fn} to primary-email-only matching`);
  }
});

// ── (D) DB-gated: each RPC is live and gates gracefully for service-role ──────────
test('DB: all 5 sibling RPCs are live and gate on auth.uid() (no member → not_authenticated)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  // RPCs that RETURN {error:'not_authenticated'} jsonb (no throw)
  for (const fn of ['get_my_selection_result', 'get_my_evaluation_feedback']) {
    const { data, error } = await sb.rpc(fn);
    assert.ok(!error, `${fn} must not throw for service-role: ${error?.message}`);
    assert.strictEqual(data?.error, 'not_authenticated', `${fn} should return not_authenticated jsonb`);
  }

  // RPCs that RAISE 'Not authenticated' (PostgREST surfaces as error)
  const raises = [
    ['export_my_data', undefined],
    ['update_my_application', { p_fields: {} }],
    ['upload_my_resume', { p_url: 'https://example.com/x.pdf' }],
  ];
  for (const [fn, args] of raises) {
    const { error } = args ? await sb.rpc(fn, args) : await sb.rpc(fn);
    assert.ok(error, `${fn} should RAISE for service-role (auth.uid null)`);
    assert.match(error.message, /authenticated/i, `${fn} should fail with an auth message, got: ${error?.message}`);
  }
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
