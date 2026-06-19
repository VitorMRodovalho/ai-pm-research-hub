/**
 * Contract: F2 #740 follow-up — Credly adoption nudge (CredlyNudge island).
 *
 * The /profile Credly field + 3-step inline guide already exist ("W4 Block F — Credly guide", PR
 * #762), but the screen is passive. Live grounding 2026-06-19: 8/8 research-tribe members without a
 * credly_url are active researchers — they surface no PMI badges, so earn no badge XP. This island
 * PULLS them to the field: a dismissible /workspace banner that deep-links to it.
 *
 * Design anchors (PM decision 2026-06-19 — FE-only, no new DB state; mirrors EntryChapterNudge #625):
 *  - Self-gating mirrors what the /profile Credly field can act on, so the nudge never dead-ends, and
 *    is scoped to the measured cohort: active, non-guest, non-alumni, research-tribe member with no
 *    credly_url. All signals come from the in-memory nav member (get_member_by_auth already returns
 *    credly_url / operational_role / member_status / tribe_id) — the island makes NO network call.
 *  - FE-only: the island READS but never writes. The write (member_self_update) stays on /profile.
 *  - Dismiss is a localStorage flag ("not now") with a TTL, not a DB seen-state.
 *  - Deep-link: /profile#credly, with scroll-on-hash + guide-open on /profile.
 *
 * Offline-only (static source assertions); no DB gating.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');

const NUDGE = read('src/components/onboarding/CredlyNudge.tsx');
const WK = read('src/pages/workspace.astro');
const PROFILE = read('src/pages/profile.astro');

// ── Component exists ─────────────────────────────────────────────────────────────
test('CredlyNudge: component exists', () => {
  assert.ok(NUDGE, 'CredlyNudge.tsx exists');
});

// ── In-memory eligibility: no network call (nav member already carries credly_url) ──
test('CredlyNudge: derives eligibility from the in-memory nav member (no RPC)', () => {
  assert.match(NUDGE, /navGetMember/);
  assert.match(NUDGE, /credly_url/);
  // The whole point: the member object already has credly_url, so the island never queries.
  assert.ok(!/\.rpc\(/.test(NUDGE), 'no rpc() call — eligibility is in-memory');
});

// ── FE-only: reads, never writes ─────────────────────────────────────────────────
test('CredlyNudge: FE-only — never calls the write RPC (that stays on /profile)', () => {
  assert.ok(!/member_self_update/.test(NUDGE), 'no member_self_update write');
  assert.ok(!/link_my_credly_badge/.test(NUDGE), 'no link_my_credly_badge write');
});

// ── Self-gating: active, non-guest, non-alumni, research-tribe, no credly yet ─────
test('CredlyNudge: excludes guests, alumni and non-active members', () => {
  assert.match(NUDGE, /operational_role === ['"]guest['"]/);
  assert.match(NUDGE, /operational_role === ['"]alumni['"]/);
  assert.match(NUDGE, /member_status !== ['"]active['"]/);
});

test('CredlyNudge: scoped to research-tribe members and hides once a credly_url exists', () => {
  // engaged cohort gate (the measured 8): must be in a tribe
  assert.match(NUDGE, /!m\.tribe_id/);
  // already linked → do not show
  assert.match(NUDGE, /hasCredly/);
});

// ── Dismiss is a per-device localStorage flag with TTL, not DB state ──────────────
test('CredlyNudge: dismiss uses localStorage with a TTL (no new DB seen-state)', () => {
  assert.match(NUDGE, /localStorage\.getItem/);
  assert.match(NUDGE, /localStorage\.setItem/);
  assert.match(NUDGE, /DISMISS_TTL_MS/);
});

// ── Deep-link to the existing /profile Credly field (hash-preserving, not via redirect) ──
test('CredlyNudge: deep-links to the /profile Credly anchor', () => {
  assert.match(NUDGE, /#credly/);
  // must NOT use the /en|/es redirect prefix — meta-refresh drops the hash (GAP-625.A)
  assert.ok(!/\/en\/profile#|\/es\/profile#/.test(NUDGE), 'no locale-prefixed profile path');
});

// ── a11y + trilingual inline copy (sibling-island idiom) ─────────────────────────
test('CredlyNudge: region role with aria-label + trilingual inline copy', () => {
  assert.match(NUDGE, /role=['"]region['"]/);
  assert.match(NUDGE, /aria-label=/);
  assert.match(NUDGE, /'pt-BR':/);
  assert.match(NUDGE, /'en-US':/);
  assert.match(NUDGE, /'es-LATAM':/);
});

// ── Mounted on /workspace as a sibling, BEFORE BuddyBlock (governance/XP > social) ──
test('workspace: mounts CredlyNudge before BuddyBlock', () => {
  assert.match(WK, /import CredlyNudge from/);
  assert.match(WK, /<CredlyNudge client:load lang=\{lang\} \/>/);
  const buddyIdx = WK.indexOf('<BuddyBlock');
  const nudgeIdx = WK.indexOf('<CredlyNudge');
  assert.ok(buddyIdx > -1 && nudgeIdx > -1, 'both islands mounted');
  assert.ok(nudgeIdx < buddyIdx, 'order: credly nudge → buddy');
});

// ── /profile provides the deep-link target + scroll-on-hash ───────────────────────
test('profile: Credly field has the deep-link target id', () => {
  assert.match(PROFILE, /id="self-credly"/);
});

test('profile: scrolls the Credly field into view on the deep-link hash', () => {
  assert.match(PROFILE, /location\.hash === ['"]#credly['"]/);
  assert.match(PROFILE, /scrollToCredly/);
  // arriving via the nudge opens the inline 3-step guide so the steps are visible
  assert.match(PROFILE, /\.open = true/);
});
