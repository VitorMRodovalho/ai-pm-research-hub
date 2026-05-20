/**
 * Contract test for issue #177 (p203) — pending agreement visibility queue.
 *
 * Verifies via static migration analysis that:
 *   - get_pending_agreement_engagements() exists and is SECURITY DEFINER.
 *   - Returns auth gate ('not_authenticated' / 'not_authorized') before data.
 *   - Filters on status='active' + requires_agreement IS TRUE +
 *     agreement_certificate_id IS NULL (matches PM's pending_agreement CTE
 *     in P202_VOLUNTEER_LIFECYCLE_SQL_AUDIT.md §2/3).
 *   - Returns the spec fields from P202_VOLUNTEER_LIFECYCLE_REMEDIATION_SPEC §2:
 *     engagement_id, person_id, member_id, kind, role, initiative_id,
 *     start_date, agreement_certificate_id, notification status (as
 *     has_agreement_notification), and a next_action label.
 *   - next_action distinguishes volunteer kind (existing flow can issue) from
 *     ambassador/study_group_* (special kind — needs PM template decision).
 *
 * Pattern: matches selection-interview-decision.test.mjs (read-all SQL, regex).
 * Hard-fails offline (no DB env required).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

function loadAllMigrations() {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql')).sort();
  return files.map(f => readFileSync(join(MIGRATIONS_DIR, f), 'utf8'));
}

const allSQL = loadAllMigrations().join('\n');

function latestFunctionBody(funcName) {
  const escaped = funcName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${escaped}\\s*\\([^)]*\\)[\\s\\S]*?AS\\s+\\$(\\w*)\\$([\\s\\S]*?)\\$\\1\\$`,
    'gi'
  );
  const matches = [...allSQL.matchAll(regex)];
  return matches.length > 0 ? matches[matches.length - 1][2] : null;
}

test('get_pending_agreement_engagements() exists in migrations', () => {
  const body = latestFunctionBody('get_pending_agreement_engagements');
  assert.ok(body, 'function body not found in migrations');
});

test('get_pending_agreement_engagements is SECURITY DEFINER', () => {
  const re = /get_pending_agreement_engagements[\s\S]*?SECURITY\s+DEFINER/i;
  assert.ok(re.test(allSQL), 'must be SECURITY DEFINER for cross-member visibility');
});

test('get_pending_agreement_engagements gates on auth.uid() and manage_member', () => {
  const body = latestFunctionBody('get_pending_agreement_engagements');
  assert.match(body, /auth\.uid\(\)/i, 'must read auth.uid()');
  assert.match(body, /not_authenticated/i, 'must return not_authenticated for anon/missing caller');
  assert.match(body, /can_by_member\([^,]*,\s*'manage_member'\)/i, 'must use can_by_member(manage_member)');
  assert.match(body, /not_authorized/i, 'must return not_authorized when gate fails');
});

test('get_pending_agreement_engagements filters status=active + requires_agreement=true + cert IS NULL', () => {
  const body = latestFunctionBody('get_pending_agreement_engagements');
  assert.match(body, /status\s*=\s*'active'/i, 'must filter ae.status = active');
  assert.match(body, /requires_agreement\s+IS\s+TRUE/i, 'must filter requires_agreement IS TRUE');
  assert.match(body, /agreement_certificate_id\s+IS\s+NULL/i, 'must filter agreement_certificate_id IS NULL');
});

test('get_pending_agreement_engagements returns the spec fields', () => {
  const body = latestFunctionBody('get_pending_agreement_engagements');
  const fields = [
    'engagement_id',
    'person_id',
    'member_id',
    'kind',
    'role',
    'initiative_id',
    'start_date',
    'agreement_certificate_id',
    'has_agreement_notification',
    'next_action',
  ];
  for (const f of fields) {
    assert.ok(
      body.includes(`'${f}'`),
      `pending row must include '${f}' key (per P202_VOLUNTEER_LIFECYCLE_REMEDIATION_SPEC §2)`
    );
  }
});

test('get_pending_agreement_engagements next_action routes volunteer vs special kinds', () => {
  const body = latestFunctionBody('get_pending_agreement_engagements');
  assert.match(body, /WHEN\s+ae\.kind\s*=\s*'volunteer'\s+THEN\s+'notify_member_to_sign_volunteer_term'/i,
    'volunteer kind must route to notify-to-sign (existing flow works)');
  assert.match(body, /ambassador[\s\S]*?study_group_owner[\s\S]*?study_group_participant[\s\S]*?'decide_template_for_kind_then_issue'/i,
    'special kinds must route to PM template decision');
});

test('get_pending_agreement_engagements is visibility-only — no INSERT/UPDATE/DELETE side effects', () => {
  const body = latestFunctionBody('get_pending_agreement_engagements');
  assert.doesNotMatch(body, /\bINSERT\s+INTO\b/i, 'must NOT issue agreements or notifications');
  assert.doesNotMatch(body, /\bUPDATE\s+(?:public\.)?(?:certificates|engagements|auth_engagements|notifications|admin_audit_log)\b/i,
    'must NOT mutate state');
  assert.doesNotMatch(body, /\bDELETE\s+FROM\b/i, 'must NOT delete rows');
});

test('get_pending_agreement_engagements has GRANT EXECUTE TO authenticated', () => {
  const re = /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+(?:public\.)?get_pending_agreement_engagements\(\)\s+TO\s+authenticated/i;
  assert.ok(re.test(allSQL), 'must GRANT EXECUTE TO authenticated');
});
