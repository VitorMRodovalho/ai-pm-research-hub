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
  assert.match(OC, /onClick=\{async \(e\) => \{[\s\S]*?e\.preventDefault\(\); await acknowledgeOnboarding\(\); window\.location\.href = ctaHref/,
    'onboarding CTA must acknowledge before navigating');
});

// The two assertions below cover defects found while reviewing THIS fix, not the original bug.
// Both are ways the fix itself could regress, so they belong with it rather than in a follow-up.

test('#1443 both CTAs preserve ctrl/cmd/shift+click (open in new tab)', () => {
  // Calling preventDefault unconditionally hijacks a modified click into a same-tab navigation.
  // On a modified click THIS page does not navigate, so the ack cannot be cancelled and the
  // handler must bail out before preventDefault.
  for (const [name, src] of [['MilestoneCelebration', MC], ['OnboardingChecklist', OC]]) {
    const handler = src.slice(src.indexOf('onClick={async (e)'));
    const modifierIdx = handler.search(/e\.metaKey \|\| e\.ctrlKey \|\| e\.shiftKey \|\| e\.altKey/);
    const preventIdx = handler.indexOf('e.preventDefault()');
    assert.ok(modifierIdx !== -1, `${name}: CTA must detect a modified click`);
    assert.ok(modifierIdx < preventIdx,
      `${name}: the modified-click bail-out must come BEFORE preventDefault`);
  }
});

test('#1443 dismiss acknowledges BEFORE hiding the card, in both components', () => {
  // Hiding first re-opens the very race this issue is about: the user closes, navigates, and the
  // in-flight write dies. MilestoneCelebration awaits then advances; OnboardingChecklist must match.
  const oc = OC.slice(OC.indexOf('const dismissCelebration'));
  const ackIdx = oc.indexOf('await acknowledgeOnboarding()');
  const hideIdx = oc.indexOf('setCelebrationPending(false)');
  assert.ok(ackIdx !== -1 && hideIdx !== -1, 'dismissCelebration must ack and hide');
  assert.ok(ackIdx < hideIdx, 'the ack must be awaited BEFORE the card is hidden');

  const mc = MC.slice(MC.indexOf('const dismiss = useCallback'));
  assert.ok(mc.indexOf('await acknowledge(current)') < mc.indexOf('advance(current)'),
    'MilestoneCelebration must await the ack before advancing the queue');
});
