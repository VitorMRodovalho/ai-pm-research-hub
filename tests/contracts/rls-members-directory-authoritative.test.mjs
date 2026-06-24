/**
 * Contract: members directory read requires AUTHORITATIVE membership (LGPD / #867 follow-up).
 *
 * Finding (verified live): members_read_by_members previously used
 *   USING (is_active = true AND rls_is_member())
 * and rls_is_member() = EXISTS(member row for auth.uid()) — row-existence only.
 * So ANY authenticated member-row holder, including pre-onboarding GUESTS
 * (operational_role='guest', unsigned volunteer term, non-authoritative), could read
 * the full member directory PII (email/phone/pmi_id/address/birth_date) via a hand-crafted
 * members?select=*. This is independent of the #867 nav fix but the cohort that triggers it
 * is exactly the guest wave the nav fix activates.
 *
 * Fix (migration 20260805000243): introduce rls_is_authoritative_member() (active member with
 * operational_role <> 'guest') and gate members_read_by_members on it. Own-row reads remain via
 * members_select_own (auth_id=auth.uid()); admin/stakeholder/tribe-leader reads are separate
 * permissive policies, untouched.
 *
 * Asserts (static, always run):
 *   - helper rls_is_authoritative_member declared SECDEF + pinned search_path + non-guest predicate
 *   - members_read_by_members policy gates on rls_is_authoritative_member (not bare rls_is_member)
 * Forward-defense:
 *   - no later migration recreates members_read_by_members on bare rls_is_member()
 *   - no later migration loosens the helper to drop the non-guest condition
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const FIX = '20260805000243_rls_harden_members_read_authoritative.sql';
const FIX_FILE = resolve(MIGRATIONS_DIR, FIX);

test('rls-members-auth: fix migration exists', () => {
  assert.ok(existsSync(FIX_FILE), `migration must exist at ${FIX_FILE}`);
});

test('rls-members-auth: rls_is_authoritative_member declared SECDEF + pinned search_path', () => {
  const body = readFileSync(FIX_FILE, 'utf8');
  assert.match(
    body,
    /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.rls_is_authoritative_member\s*\(\s*\)\s+RETURNS\s+boolean[\s\S]*?SECURITY\s+DEFINER[\s\S]*?SET\s+search_path\s+TO\s+'public',\s*'pg_temp'/i,
    'helper must be SECURITY DEFINER with pinned search_path'
  );
});

test('rls-members-auth: helper requires active, non-guest (authoritative) member', () => {
  const body = readFileSync(FIX_FILE, 'utf8');
  assert.match(body, /m\.auth_id\s*=\s*auth\.uid\(\)/i, 'helper must key on auth.uid()');
  assert.match(body, /m\.is_active\s*=\s*true/i, 'helper must require is_active');
  assert.match(body, /m\.operational_role\s*<>\s*'guest'/i, 'helper must exclude guest (require authoritative engagement)');
});

test('rls-members-auth: members_read_by_members gates on rls_is_authoritative_member (not bare rls_is_member)', () => {
  const body = readFileSync(FIX_FILE, 'utf8');
  assert.match(
    body,
    /CREATE\s+POLICY\s+members_read_by_members\s+ON\s+public\.members[\s\S]*?USING\s*\(\s*is_active\s*=\s*true\s+AND\s+public\.rls_is_authoritative_member\(\)\s*\)/i,
    'members_read_by_members must USING (is_active AND rls_is_authoritative_member())'
  );
  // and it must NOT reintroduce the loose bare rls_is_member() in the policy
  const policyBlock = body.match(/CREATE\s+POLICY\s+members_read_by_members[\s\S]*?;/i)?.[0] || '';
  assert.doesNotMatch(policyBlock, /rls_is_member\s*\(\s*\)/i, 'members_read_by_members must not use bare rls_is_member()');
});

function subsequentMigrations() {
  const all = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort();
  const idx = all.indexOf(FIX);
  assert.ok(idx >= 0, 'fix migration must be in the registry');
  return all.slice(idx + 1).map((f) => ({ name: f, body: readFileSync(resolve(MIGRATIONS_DIR, f), 'utf8') }));
}

test('rls-members-auth: no later migration recreates members_read_by_members on bare rls_is_member()', () => {
  const offenders = subsequentMigrations().filter((m) => {
    const block = m.body.match(/CREATE\s+POLICY\s+members_read_by_members[\s\S]*?;/i)?.[0];
    if (!block) return false;
    return /rls_is_member\s*\(\s*\)/i.test(block) && !/rls_is_authoritative_member/i.test(block);
  });
  assert.equal(offenders.length, 0,
    `members_read_by_members must keep the authoritative gate. Offenders: ${offenders.map((m) => m.name).join(', ')}`);
});

test('rls-members-auth: no later migration loosens rls_is_authoritative_member (drops non-guest check)', () => {
  const offenders = subsequentMigrations().filter((m) => {
    const block = m.body.match(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.rls_is_authoritative_member[\s\S]*?\$function\$/i)?.[0];
    if (!block) return false;
    return !/operational_role\s*<>\s*'guest'/i.test(block);
  });
  assert.equal(offenders.length, 0,
    `rls_is_authoritative_member must keep the non-guest predicate. Offenders: ${offenders.map((m) => m.name).join(', ')}`);
});
