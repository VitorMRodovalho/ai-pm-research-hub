/**
 * Contract: #766 H1 — post-promotion journey (first days of the real role).
 *
 * MVP FE-only (PM decision): the static 3-beat "first days" roadmap that used to live as fixed
 * copy (HBLOCK) INSIDE OnboardingChecklist — and vanished with that card once onboarding
 * completed — is promoted to a persistent, stateful island, PostPromotionJourney, mounted as a
 * sibling on /workspace. It reads the real server-side milestones (first_attendance,
 * first_deliverable) to check off each beat and retires itself once both are achieved.
 *
 * Design anchors (SPEC_766_H1_POST_PROMOTION_JOURNEY.md; product-leader + ux-leader GO-with-changes):
 *  - Persistent sibling island (NOT inside the onboarding card) — survives onboarding completion.
 *  - "Achieved" = milestone key present in get_my_milestones() pending ∪ history.
 *  - Exit when first_attendance AND first_deliverable are both achieved (no manual dismiss).
 *  - Gating: non-guest + has tribe (GP excluded) + onboarding all_complete + onboarding_complete
 *    already acknowledged (avoids overlap with the celebration card).
 *  - Beat 3 (trail/XP) is an OPEN cta — no first_xp milestone (PM decision); never auto-checks.
 *  - Grounding rule: no invented numbers/points in the copy.
 *
 * Offline-only (static source assertions); no DB gating.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');

const JOURNEY = read('src/components/onboarding/PostPromotionJourney.tsx');
const ONB = read('src/components/onboarding/OnboardingChecklist.tsx');
const WK = read('src/pages/workspace.astro');

// ── Component exists & reads the canonical RPCs ─────────────────────────────────
test('PostPromotionJourney: component exists', () => {
  assert.ok(JOURNEY, 'PostPromotionJourney.tsx exists');
});

test('PostPromotionJourney: reads onboarding + milestones (existing RPCs, zero DB)', () => {
  assert.match(JOURNEY, /rpc\(['"]get_my_onboarding['"]\)/);
  assert.match(JOURNEY, /rpc\(['"]get_my_milestones['"]\)/);
  // FE-only: it must not introduce any milestone-recording / write RPC.
  assert.ok(!/rpc\(['"]record_milestone/.test(JOURNEY), 'no record_milestone (FE-only)');
  assert.ok(!/rpc\(['"]acknowledge_milestone/.test(JOURNEY), 'no acknowledge_milestone (no new seen-state)');
});

// ── "Achieved" = pending ∪ history ──────────────────────────────────────────────
test('PostPromotionJourney: achieved set unions pending and history', () => {
  assert.match(JOURNEY, /pending/);
  assert.match(JOURNEY, /history/);
  // both arrays feed the achieved-key set
  assert.match(JOURNEY, /\[\s*\.\.\.pending\s*,\s*\.\.\.history\s*\]/);
});

// ── The two trackable beats are the real milestone keys ─────────────────────────
test('PostPromotionJourney: trackable beats are first_attendance + first_deliverable', () => {
  assert.match(JOURNEY, /first_attendance/);
  assert.match(JOURNEY, /first_deliverable/);
  // beat 3 has NO first_xp milestone (PM decision) — it must not reference one as a key
  // (a prose mention in a comment is fine; a quoted milestone key is not).
  assert.ok(!/['"]first_xp['"]/.test(JOURNEY), 'no first_xp milestone key (beat 3 is an open CTA)');
});

// ── Exit criterion: both trackable beats achieved → retire ──────────────────────
test('PostPromotionJourney: retires once both trackable beats are achieved', () => {
  assert.match(JOURNEY, /trackable\.every\(\(b\) => achieved\.has\(b\.key\)\)\)\s*return null/);
});

// ── Gating: non-guest + tribe + onboarding complete + celebration seen ──────────
test('PostPromotionJourney: gated to promoted (non-guest) members with a tribe', () => {
  assert.match(JOURNEY, /opRole === ['"]guest['"]/);
  assert.match(JOURNEY, /tribe_id/);
  // GP (no tribe) is excluded via the tribe check
  assert.match(JOURNEY, /!hasTribe/);
});

test('PostPromotionJourney: requires onboarding all_complete + acknowledged celebration', () => {
  assert.match(JOURNEY, /all_complete === true/);
  // onboarding_complete must be in history (acknowledged), not pending → no overlap with the
  // OnboardingChecklist celebration card (ux R1).
  assert.match(JOURNEY, /onboarding_complete/);
  assert.match(JOURNEY, /celebrationSeen/);
});

// ── Beat 3 is an OPEN cta, never auto-checks ────────────────────────────────────
test('PostPromotionJourney: beat 3 is open (no done-state) with a trail CTA', () => {
  assert.match(JOURNEY, /open:\s*true/);
  assert.match(JOURNEY, /gamification/);
});

// ── a11y: list semantics + state communicated beyond color ──────────────────────
test('PostPromotionJourney: uses list semantics and labels state for a11y', () => {
  assert.match(JOURNEY, /role=['"]list['"]/);
  assert.match(JOURNEY, /role=['"]listitem['"]/);
  assert.match(JOURNEY, /aria-label=\{isDone \? a\.done/);
  assert.match(JOURNEY, /aria-describedby/);
});

// ── Trilingual inline copy (OnboardingChecklist idiom) ──────────────────────────
test('PostPromotionJourney: trilingual inline copy present (pt/en/es)', () => {
  assert.match(JOURNEY, /'pt-BR':/);
  assert.match(JOURNEY, /'en-US':/);
  assert.match(JOURNEY, /'es-LATAM':/);
});

// ── Grounding rule: no invented numbers/points in copy ──────────────────────────
test('PostPromotionJourney: copy has no invented points/percentages', () => {
  // guard against regressions like "+50pts" or "100%" sneaking into the journey copy
  assert.ok(!/\+\s*\d+\s*(pts|pontos|points|puntos)/i.test(JOURNEY), 'no "+N pts" copy');
  assert.ok(!/\b100%/.test(JOURNEY), 'no hardcoded 100% in copy');
});

// ── Mounted on /workspace as a sibling, above BuddyBlock ─────────────────────────
test('workspace: mounts PostPromotionJourney between OnboardingChecklist and BuddyBlock', () => {
  assert.match(WK, /import PostPromotionJourney from/);
  assert.match(WK, /<PostPromotionJourney client:load lang=\{lang\} \/>/);
  const onbIdx = WK.indexOf('<OnboardingChecklist');
  const ppjIdx = WK.indexOf('<PostPromotionJourney');
  const buddyIdx = WK.indexOf('<BuddyBlock');
  assert.ok(onbIdx > -1 && ppjIdx > -1 && buddyIdx > -1, 'all three islands mounted');
  assert.ok(onbIdx < ppjIdx && ppjIdx < buddyIdx, 'order: onboarding → journey → buddy');
});

// ── The static HBLOCK is removed from OnboardingChecklist (no duplicate "first days") ──
test('OnboardingChecklist: static HBLOCK roadmap removed (no duplicate first-days card)', () => {
  assert.ok(!/const HBLOCK\b/.test(ONB), 'HBLOCK const removed');
  assert.ok(!/function hblock\(/.test(ONB), 'hblock() helper removed');
  assert.ok(!/\bh\.beat1\b/.test(ONB), 'no h.beat1 render leftover');
  // the shared attendanceCta label moved into the L dict and the first_meeting step still uses it
  assert.match(ONB, /attendanceCta:/);
  assert.match(ONB, /\{l\.attendanceCta\}/);
});
