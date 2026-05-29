/**
 * Contract: p277 — tribe-leader champion-award access (#424 operational unblock).
 *
 * KEY FINDING (live-verified): no DB grant change was needed. Every active tribe_leader already
 * has a `volunteer × leader` engagement, and `engagement_kind_permissions` already seeds
 * (`volunteer`,`leader`,`award_champion`,`initiative`) — so `award_champion`'s RPC gate
 * `can_by_member(caller,'award_champion','initiative', v_target_init_id)` already returns true
 * for a tribe_leader on their own initiative (general surface stays org-scope/GP-only). Per
 * V4_AUTHORITY_MODEL this is NOT a gap — adding a seed would be a redundant privilege-escalation
 * anti-pattern.
 *
 * The ONLY blocker was the FRONTEND: admin/gamification.astro was all-or-nothing on the broad
 * `admin.gamification` permission (which tribe_leader lacks), and opening the whole panel would
 * over-expose org-wide rules + category-activity. This change gives leaders a SCOPED
 * champion-award-only view via a new `champion.award` permission + a 3-way gate, and restricts
 * the surface dropdown to tribe/deliverable for non-org grantors.
 *
 * Frontend-only — no migration.
 * Cross-ref: docs/audit/METRIC_DISPARITY_AUDIT_2026-05-28.md (GI-2) · #424 · award_champion RPC.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const PERMS = resolve(ROOT, 'src/lib/permissions.ts');
const PAGE = resolve(ROOT, 'src/pages/admin/gamification.astro');

const perms = existsSync(PERMS) ? readFileSync(PERMS, 'utf8') : '';
const page = existsSync(PAGE) ? readFileSync(PAGE, 'utf8') : '';

const block = (src, start, end) => {
  const i = src.indexOf(start);
  const j = src.indexOf(end, i + 1);
  return i >= 0 && j > i ? src.slice(i, j) : '';
};

// ===================================================================
// permissions.ts
// ===================================================================

test('p277 #424: champion.award + champion.award_general exist in the Permission union', () => {
  assert.match(perms, /\|\s*'champion\.award'/, 'champion.award must be a Permission');
  assert.match(perms, /\|\s*'champion\.award_general'/, 'champion.award_general must be a Permission');
});

test('p277 #424: tribe_leader gets champion.award but NOT champion.award_general', () => {
  const tl = block(perms, 'tribe_leader: [', 'project_collaborator: [');
  assert.ok(tl, 'tribe_leader block must exist');
  assert.ok(tl.includes("'champion.award'"), 'tribe_leader must hold champion.award (tribe/deliverable surfaces)');
  assert.ok(!tl.includes("'champion.award_general'"), 'tribe_leader must NOT hold champion.award_general (general = org-scope GP only)');
});

test('p277 #424: manager (+ deputy_manager, comms_leader) hold both champion permissions', () => {
  const mgr = block(perms, 'manager: [', 'sponsor: [');
  assert.ok(mgr.includes("'champion.award'") && mgr.includes("'champion.award_general'"), 'manager must hold both champion permissions');
  const dep = block(perms, 'deputy_manager: [', 'curator: [');
  assert.ok(dep.includes("'champion.award'") && dep.includes("'champion.award_general'"), 'deputy_manager must hold both');
  const comms = block(perms, 'comms_leader: [', 'comms_member: [');
  assert.ok(comms.includes("'champion.award'") && comms.includes("'champion.award_general'"), 'comms_leader must hold both');
});

// ===================================================================
// admin/gamification.astro — 3-way gate + scoped view
// ===================================================================

test('p277 #424: applyGate is a 3-way gate (admin → full; champion.award → scoped; else denied)', () => {
  const gate = block(page, 'function applyGate', 'function showChampionAwardOnly');
  assert.match(gate, /hasPermission\(m,\s*'admin\.gamification'\)\)\s*\{\s*showPanel\(\)/, 'admin.gamification → full panel');
  assert.match(gate, /else if\s*\(\s*hasPermission\(m,\s*'champion\.award'\)\)\s*\{\s*showChampionAwardOnly\(\)/, 'champion.award → scoped champion-only view');
  assert.match(gate, /else\s+showDenied\(\)/, 'otherwise denied');
});

test('p277 #424: showChampionAwardOnly hides BOTH org-wide admin sections (rules + activity)', () => {
  // the two sections must be addressable
  assert.match(page, /<section id="gam-rules-section"/, 'rules section needs an id to hide');
  assert.match(page, /<section id="gam-activity-section"/, 'activity section needs an id to hide');
  const fn = block(page, 'function showChampionAwardOnly', 'function restrictSurfaceOptions');
  assert.match(fn, /gam-panel.*classList\.remove\('hidden'\)/s, 'must reveal the panel');
  assert.match(fn, /gam-rules-section.*classList\.add\('hidden'\)/s, 'must hide the rules section (org-wide config)');
  assert.match(fn, /gam-activity-section.*classList\.add\('hidden'\)/s, 'must hide the category-activity section (org-wide member data)');
  assert.match(fn, /loadChampions\(\)/, 'must still load the champions list + grant flow');
});

test('p277 #424: surface dropdown drops "general" for non-org grantors (RPC fail-closed alignment)', () => {
  const fn = block(page, 'function restrictSurfaceOptions', '\n  async function boot');
  assert.match(fn, /!hasPermission\(m,\s*'champion\.award_general'\)/, 'gate on champion.award_general');
  assert.match(fn, /option\[value="general"\].*\.remove\(\)/s, 'must remove the general surface option when not an org grantor');
});

test('p277 #424 forward-defense: scoped view must not reveal the org-wide sections', () => {
  const fn = block(page, 'function showChampionAwardOnly', 'function restrictSurfaceOptions');
  // it must never .remove('hidden') the rules/activity sections (i.e. never reveal them)
  assert.ok(!/gam-rules-section.*classList\.remove/s.test(fn), 'scoped view must not reveal the rules section');
  assert.ok(!/gam-activity-section.*classList\.remove/s.test(fn), 'scoped view must not reveal the activity section');
});
