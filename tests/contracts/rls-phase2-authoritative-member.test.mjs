/**
 * Contract: RLS Phase 2 — the remaining rls_is_member() SELECT policies require AUTHORITATIVE
 * membership (LGPD / #867 follow-up to Phase 1 #869).
 *
 * Finding (verified live, audit docs/audit/RLS_PHASE2_RLS_IS_MEMBER_AUDIT_2026-06-24.md):
 * 23 SELECT policies still gated on rls_is_member() = EXISTS(member row for auth.uid()) — row-existence
 * only — so pre-onboarding GUESTS (operational_role='guest') read the FULL collaborative dataset on
 * every table, identical to a real member. A two-sided live probe confirmed: after the swap a guest
 * drops to 0 rows on the tightened tables while the 40 authoritative members are unchanged.
 *
 * Fix (migration 20260805000246): swap rls_is_member() -> rls_is_authoritative_member() on:
 *   - Group A/B (plain swap, no guest-reachable direct read)
 *   - Group C (own-row carve-out: gamification_points/attendance/publication_submissions keep a
 *     guest/member SELF-read on /profile + /gamification via "OR <owner_col> IN (own member id)")
 *   - Group D (course_progress: own-row preserved by the separate 'Auth update progress' policy)
 *   - Group E (publication_series: also fix role divergence {public}->{authenticated})
 *   - events is intentionally LEFT (events_select_org_scope is PERMISSIVE and backfills; semi-public)
 *   - REVOKE latent anon SELECT grants on 5 tables (events anon grant kept — load-bearing)
 *
 * Asserts (static, always run) + forward-defense (no later migration reverts to bare rls_is_member()).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const FIX = '20260805000246_rls_phase2_authoritative_member.sql';
const FIX_FILE = resolve(MIGRATIONS_DIR, FIX);

// Plain-swap policies (Group A/B/D/E): USING must reference rls_is_authoritative_member(), never bare rls_is_member().
const PLAIN_SWAP = [
  ['board_items_read_members', 'board_items'],
  ['assignments_read_members', 'board_item_assignments'],
  ['checklists_read_members', 'board_item_checklists'],
  ['tag_assignments_read_members', 'board_item_tag_assignments'],
  ['project_boards_read_members', 'project_boards'],
  ['audience_rules_read_members', 'event_audience_rules'],
  ['invited_read_members', 'event_invited_members'],
  ['event_tags_read_members', 'event_tag_assignments'],
  ['webinars_read_authenticated', 'webinars'],
  ['wle_read_members', 'webinar_lifecycle_events'],
  ['sub_authors_read_members', 'publication_submission_authors'],
  ['sub_events_read_members', 'publication_submission_events'],
  ['partners_read_members', 'partner_entities'],
  ['cr_read_members', 'change_requests'],
  ['drive_file_discoveries_read_authenticated', 'drive_file_discoveries'],
  ['initiative_drive_links_read_authenticated', 'initiative_drive_links'],
  ['board_item_files_read_authenticated', 'board_item_files'],
  ['board_drive_links_read_authenticated', 'board_drive_links'],
  ['course_progress_read_members', 'course_progress'],
  ['publication_series_read_members', 'publication_series'],
];

// Own-row carve-out policies (Group C): authoritative OR self-row.
const CARVE_OUT = [
  ['gamification_read_members', 'gamification_points'],
  ['attendance_read_members', 'attendance'],
  ['submissions_read_members', 'publication_submissions'],
];

const ANON_REVOKE_TABLES = [
  'board_item_files', 'board_drive_links', 'drive_file_discoveries',
  'gamification_points', 'initiative_drive_links',
];

function alterBlock(body, policy, table) {
  const re = new RegExp(`ALTER\\s+POLICY\\s+${policy}\\s+ON\\s+public\\.${table}\\b[\\s\\S]*?;`, 'i');
  return body.match(re)?.[0] || '';
}

test('rls-phase2: fix migration exists', () => {
  assert.ok(existsSync(FIX_FILE), `migration must exist at ${FIX_FILE}`);
});

test('rls-phase2: plain-swap policies gate on rls_is_authoritative_member (not bare rls_is_member)', () => {
  const body = readFileSync(FIX_FILE, 'utf8');
  for (const [policy, table] of PLAIN_SWAP) {
    const block = alterBlock(body, policy, table);
    assert.ok(block, `ALTER POLICY ${policy} ON public.${table} must be present`);
    assert.match(block, /rls_is_authoritative_member\(\)/i, `${policy} must use rls_is_authoritative_member()`);
    assert.doesNotMatch(block, /[^_]rls_is_member\s*\(/i, `${policy} must not keep bare rls_is_member()`);
  }
});

test('rls-phase2: own-row carve-out policies keep authoritative OR self-row', () => {
  const body = readFileSync(FIX_FILE, 'utf8');
  for (const [policy, table] of CARVE_OUT) {
    const block = alterBlock(body, policy, table);
    assert.ok(block, `ALTER POLICY ${policy} ON public.${table} must be present`);
    assert.match(block, /rls_is_authoritative_member\(\)/i, `${policy} must include the authoritative branch`);
    assert.match(block, /IN\s*\(\s*SELECT[\s\S]*?auth_id\s*=\s*auth\.uid\(\)/i, `${policy} must keep the own-row self-read branch`);
  }
});

test('rls-phase2: board_item_files keeps its deleted_at guard', () => {
  const body = readFileSync(FIX_FILE, 'utf8');
  const block = alterBlock(body, 'board_item_files_read_authenticated', 'board_item_files');
  assert.match(block, /deleted_at\s+IS\s+NULL/i, 'board_item_files must keep deleted_at IS NULL');
});

test('rls-phase2: webinars keeps its public-status OR branch', () => {
  const body = readFileSync(FIX_FILE, 'utf8');
  const block = alterBlock(body, 'webinars_read_authenticated', 'webinars');
  assert.match(block, /status\s*=\s*ANY/i, 'webinars must keep the public confirmed/completed OR branch');
});

test('rls-phase2: publication_series read policy is scoped TO authenticated (role divergence fix)', () => {
  const body = readFileSync(FIX_FILE, 'utf8');
  const block = alterBlock(body, 'publication_series_read_members', 'publication_series');
  assert.match(block, /TO\s+authenticated/i, 'publication_series_read_members must be scoped TO authenticated');
});

test('rls-phase2: latent anon SELECT grants revoked on 5 tables', () => {
  const body = readFileSync(FIX_FILE, 'utf8');
  for (const t of ANON_REVOKE_TABLES) {
    assert.match(body, new RegExp(`REVOKE\\s+SELECT\\s+ON\\s+public\\.${t}\\s+FROM\\s+anon`, 'i'),
      `must REVOKE SELECT ON public.${t} FROM anon`);
  }
});

test('rls-phase2: events_read_authenticated is intentionally LEFT untouched', () => {
  const body = readFileSync(FIX_FILE, 'utf8');
  assert.doesNotMatch(body, /ALTER\s+POLICY\s+events_read_authenticated/i,
    'events is LEAVE (org_scope permissive backfills); the migration must not tighten it');
});

function subsequentMigrations() {
  const all = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql')).sort();
  const idx = all.indexOf(FIX);
  assert.ok(idx >= 0, 'fix migration must be in the registry');
  return all.slice(idx + 1).map((f) => ({ name: f, body: readFileSync(resolve(MIGRATIONS_DIR, f), 'utf8') }));
}

test('rls-phase2: no later migration reverts a tightened read policy to bare rls_is_member()', () => {
  const all = [...PLAIN_SWAP, ...CARVE_OUT];
  const offenders = [];
  for (const m of subsequentMigrations()) {
    for (const [policy, table] of all) {
      const re = new RegExp(`(ALTER|CREATE)\\s+POLICY\\s+"?${policy}"?\\s+ON\\s+public\\.${table}\\b[\\s\\S]*?;`, 'ig');
      for (const block of m.body.match(re) || []) {
        if (/[^_]rls_is_member\s*\(/i.test(block) && !/rls_is_authoritative_member/i.test(block)) {
          offenders.push(`${m.name}:${policy}`);
        }
      }
    }
  }
  assert.equal(offenders.length, 0,
    `tightened policies must keep the authoritative gate. Offenders: ${offenders.join(', ')}`);
});
