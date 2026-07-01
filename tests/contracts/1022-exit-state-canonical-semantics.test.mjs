/**
 * #1022 — member exit-state semantics: canonical alumni metric (A), dead-metric removal (B),
 * `observer` retired as an offboard target (C), and inactive-reversibility reaffirmed (D, no change).
 *
 * Static guards (offline) over the migration + FE + i18n. Non-no-op: against the pre-#1022 live bodies
 * these fail — the loose alumni OR-variant is present, `observers_active` is present, and
 * admin_offboard_member accepts `p_new_status='observer'`. The behavioral proof (adoption alumni 22→21;
 * admin_offboard_member rejects 'observer' with 'Invalid status') was run out-of-band via live query +
 * RAISE-rollback smoke, documented in the PR. Live==file for both bodies is enforced by the Phase C
 * body-drift gate (neither function is on the p175 allowlist).
 *
 * Cross-ref: #1022, ADR-0071 Amendment 3, #976 (Camada 5 inactive reversibility), #625/#692.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const R = (p) => { const f = join(__dirname, p); return existsSync(f) ? readFileSync(f, 'utf8') : ''; };

const MIG = R('../../supabase/migrations/20260805000315_1022_exit_state_canonical_semantics.sql');
const ADOPTION = R('../../src/pages/admin/adoption.astro');
const ISLAND = R('../../src/components/admin/members/MemberListIsland.tsx');
const DICTS = {
  'pt-BR': R('../../src/i18n/pt-BR.ts'),
  'en-US': R('../../src/i18n/en-US.ts'),
  'es-LATAM': R('../../src/i18n/es-LATAM.ts'),
};
// executable SQL only (strip `-- ...` comment lines; the header/notes name the loose def + observer).
const code = MIG.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');

test('#1022 migration exists, touches the two SECDEF functions, and does NOT change validate_status_transition (Part D)', () => {
  assert.ok(MIG, `migration file missing at expected path`);
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.get_adoption_dashboard\(\)/);
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.admin_offboard_member\(/);
  // Part D reframe: inactive stays REVERSIBLE — validate_status_transition must not be redefined here.
  assert.doesNotMatch(code, /CREATE OR REPLACE FUNCTION public\.validate_status_transition/,
    'Part D: validate_status_transition must NOT change (blocking inactive→active would break #976 reaccept)');
});

test("#1022-A alumni is canonical (member_status='alumni'), not the loose OR-variant", () => {
  assert.match(code, /'alumni',\s*\(SELECT count\(\*\) FROM members WHERE member_status = 'alumni'\)/);
  assert.doesNotMatch(code, /NOT is_active AND operational_role IN \('alumni','observer','guest'\)/,
    'the loose alumni definition must be gone');
});

test('#1022-B dead metric observers_active removed from RPC + page + all 3 i18n dicts', () => {
  assert.doesNotMatch(code, /observers_active/, 'observers_active must be gone from the RPC body');
  assert.doesNotMatch(ADOPTION, /observers_active/, 'adoption.astro must not read observers_active');
  assert.doesNotMatch(ADOPTION, /lifecycleObservers/, 'adoption.astro must not reference the removed key');
  for (const [lang, src] of Object.entries(DICTS)) {
    assert.doesNotMatch(src, /admin\.adoption\.lifecycleObservers/, `${lang} still declares lifecycleObservers`);
  }
});

test('#1022-A alumni card relabeled away from "Alumni/Inativos" to strict "Alumni" (3 dicts)', () => {
  for (const [lang, src] of Object.entries(DICTS)) {
    assert.match(src, /'admin\.adoption\.lifecycleAlumni': 'Alumni'/, `${lang} lifecycleAlumni not relabeled`);
  }
});

test('#1022-C admin_offboard_member retires observer as an offboard target', () => {
  assert.match(code, /p_new_status NOT IN \('alumni','inactive'\)/);
  assert.doesNotMatch(code, /p_new_status NOT IN \('observer','alumni','inactive'\)/,
    'observer must be removed from the allowed offboard targets');
  assert.doesNotMatch(code, /WHEN 'observer'\s+THEN 'observer'/,
    'the observer role CASE branch must be dropped');
});

test('#1022-C offboard UI drops observer (default + picker), but keeps historical display', () => {
  assert.match(ISLAND, /useState\('alumni'\)/, 'offboard default target should be alumni');
  assert.doesNotMatch(ISLAND, /setOffboardStatus\('observer'\)/, 'no code path should set observer as target');
  assert.match(ISLAND, /\(\['alumni', 'inactive'\] as const\)/, 'picker offers only alumni/inactive');
  assert.doesNotMatch(ISLAND, /\(\['observer', 'alumni', 'inactive'\] as const\)/);
  // enum retained for historical rows: the membership badge still renders a past observer (p625-c1 contract).
  assert.match(ISLAND, /case 'observer':/, 'membershipBadge must keep the observer display branch');
});
