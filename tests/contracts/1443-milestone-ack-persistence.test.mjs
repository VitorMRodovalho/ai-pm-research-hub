// #1443 — milestone/onboarding celebration cards must persist their "seen" ack reliably.
//
// Bug (grounded 2026-07-20, 52/89 active members = 58% affected): the celebration cards reappeared on
// every page load after "Fechar". Two root causes, both static-checkable:
//   1. acknowledge_milestone was called fire-and-forget (no await) — a fast mobile tap + navigation
//      dropped the in-flight write.
//   2. the primary CTA (a link) navigated WITHOUT acknowledging — only the Fechar button did.
//
// This guard locks the fix so neither can silently regress: the ack call must be awaited, and the CTA
// must acknowledge before it navigates.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const MC = readFileSync('src/components/milestones/MilestoneCelebration.tsx', 'utf8');
const OC = readFileSync('src/components/onboarding/OnboardingChecklist.tsx', 'utf8');

test('#1443 MilestoneCelebration: acknowledge is awaited (not fire-and-forget)', () => {
  assert.match(MC, /await sb\.rpc\('acknowledge_milestone', \{ p_milestone_key/,
    'the acknowledge rpc must be awaited');
  assert.match(MC, /const dismiss = useCallback\(async \(\)/, 'dismiss is async so it can await the ack');
});

test('#1443 MilestoneCelebration: the CTA acknowledges before navigating', () => {
  // the CTA <a> must have an onClick that acknowledges + preventDefault (not a bare navigating link)
  assert.match(MC, /onClick=\{async \(e\) => \{[\s\S]*?e\.preventDefault\(\)[\s\S]*?await acknowledge\(current\)[\s\S]*?window\.location\.href = href/,
    'CTA onClick must acknowledge(current) before navigating');
});

test('#1443 OnboardingChecklist: celebration ack is awaited on both Fechar and the CTA', () => {
  assert.match(OC, /await sb\.rpc\('acknowledge_milestone', \{ p_milestone_key: 'onboarding_complete' \}\)/,
    'onboarding_complete ack must be awaited');
  assert.match(OC, /const dismissCelebration = async \(\)/, 'dismissCelebration is async');
  assert.match(OC, /onClick=\{async \(e\) => \{ e\.preventDefault\(\); await acknowledgeOnboarding\(\); window\.location\.href = ctaHref/,
    'onboarding CTA must acknowledge before navigating');
});
