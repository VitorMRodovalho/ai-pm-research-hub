/**
 * Contract: #625 follow-up / ADR-0104 — entry-chapter adoption nudge (EntryChapterNudge island).
 *
 * The /profile entry-chapter card already exists (set_my_entry_chapter, Wave 3b-i), but adoption
 * among the established membership was 0/48 live (2026-06-18) — the screen is passive. This island
 * PULLS the member to it: a dismissible /workspace banner that deep-links to the card.
 *
 * Design anchors (PM decision 2026-06-18 — FE-only, no new DB state):
 *  - Self-gating mirrors what the /profile card can act on, so the nudge never dead-ends:
 *    non-guest active member with >= 1 BR affiliation and no entry chapter chosen yet.
 *  - Eligibility derived from get_my_chapter_affiliations() (BR-only RPC) — the same read /profile
 *    uses; is_entry === true on any row ⇒ already chose ⇒ hide.
 *  - FE-only: the island READS but never writes. The write (set_my_entry_chapter) stays on /profile.
 *  - Dismiss is a localStorage flag ("not now"), not a DB seen-state.
 *  - Deep-link: /profile#entry-chapter-card, with a stable anchor + scroll-on-hash on /profile.
 *
 * Offline-only (static source assertions); no DB gating.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');

const NUDGE = read('src/components/onboarding/EntryChapterNudge.tsx');
const WK = read('src/pages/workspace.astro');
const PROFILE = read('src/pages/profile.astro');

// ── Component exists & reads the canonical affiliations RPC ──────────────────────
test('EntryChapterNudge: component exists', () => {
  assert.ok(NUDGE, 'EntryChapterNudge.tsx exists');
});

test('EntryChapterNudge: derives eligibility from get_my_chapter_affiliations (existing RPC)', () => {
  assert.match(NUDGE, /rpc\(['"]get_my_chapter_affiliations['"]\)/);
});

// ── FE-only: reads, never writes ────────────────────────────────────────────────
test('EntryChapterNudge: FE-only — never calls the write RPC (that stays on /profile)', () => {
  assert.ok(!/rpc\(['"]set_my_entry_chapter['"]\)/.test(NUDGE), 'no set_my_entry_chapter write');
  assert.ok(!/rpc\(['"]upsert_chapter_affiliation['"]\)/.test(NUDGE), 'no affiliation write');
});

// ── Self-gating: non-guest, active, has BR affiliation, none is entry yet ────────
test('EntryChapterNudge: excludes guests and non-active members', () => {
  assert.match(NUDGE, /operational_role === ['"]guest['"]/);
  assert.match(NUDGE, /member_status !== ['"]active['"]/);
});

test('EntryChapterNudge: requires >= 1 affiliation and hides once an entry chapter exists', () => {
  // dead-end guard: no affiliations → do not show
  assert.match(NUDGE, /affils\.length === 0/);
  // already chose → some row is_entry → do not show
  assert.match(NUDGE, /is_entry === true/);
});

// ── Dismiss is a per-device localStorage flag with TTL, not DB state ─────────────
test('EntryChapterNudge: dismiss uses localStorage with a TTL (no new DB seen-state)', () => {
  assert.match(NUDGE, /localStorage\.getItem/);
  assert.match(NUDGE, /localStorage\.setItem/);
  // TTL so a fat-finger dismiss does not silence the nudge forever (ux-leader R2)
  assert.match(NUDGE, /DISMISS_TTL_MS/);
});

// ── Deep-link to the existing /profile card (hash-preserving, not via lang redirect) ──
test('EntryChapterNudge: deep-links to the /profile entry-chapter anchor', () => {
  assert.match(NUDGE, /#entry-chapter-card/);
  // must NOT use the /en|/es redirect prefix — meta-refresh drops the hash (GAP-625.A)
  assert.ok(!/\/en\/profile#|\/es\/profile#/.test(NUDGE), 'no locale-prefixed profile path');
});

// ── a11y + trilingual inline copy (OnboardingChecklist/H1 idiom) ─────────────────
test('EntryChapterNudge: region role with aria-label + trilingual inline copy', () => {
  assert.match(NUDGE, /role=['"]region['"]/);
  assert.match(NUDGE, /aria-label=/);
  assert.match(NUDGE, /'pt-BR':/);
  assert.match(NUDGE, /'en-US':/);
  assert.match(NUDGE, /'es-LATAM':/);
});

// ── Mounted on /workspace as a sibling, BEFORE BuddyBlock (governance > social, R1) ──
test('workspace: mounts EntryChapterNudge before BuddyBlock', () => {
  assert.match(WK, /import EntryChapterNudge from/);
  assert.match(WK, /<EntryChapterNudge client:load lang=\{lang\} \/>/);
  const buddyIdx = WK.indexOf('<BuddyBlock');
  const nudgeIdx = WK.indexOf('<EntryChapterNudge');
  assert.ok(buddyIdx > -1 && nudgeIdx > -1, 'both islands mounted');
  // ux-leader R1: governance one-click action outranks the optional social pointer.
  assert.ok(nudgeIdx < buddyIdx, 'order: entry-chapter nudge → buddy');
});

// ── /profile provides the stable anchor + scroll-on-hash for the deep-link ───────
test('profile: entry-chapter card has the deep-link anchor id', () => {
  assert.match(PROFILE, /id="entry-chapter-card"/);
});

test('profile: scrolls the entry-chapter card into view on the deep-link hash', () => {
  assert.match(PROFILE, /location\.hash === ['"]#entry-chapter-card['"]/);
  assert.match(PROFILE, /scrollIntoView/);
});
