/**
 * Contract: #419 (ADR-0100) metric 5 / D1 (PR B) — member leaderboard defaults to current cycle.
 *
 * Pairs with the RPC rank fix (migration 20260805000101): now that rank reflects cycle XP, the
 * member-facing board on /gamification defaults its view to the CURRENT CYCLE instead of lifetime.
 * The "Todos os tempos" toggle still switches to the all-time view.
 *
 * The review's HIGH finding: flipping only the JS default would leave the toggle BUTTONS visually
 * showing lifetime as active on first load (the HTML hardcodes the active class). This test locks
 * BOTH the JS default AND the button active-state so they can never desync — mirroring the tribe
 * panel (tr-mode-cycle is the active button because tribeMode also defaults to 'cycle').
 *
 * Scope: the public board (get_public_leaderboard) stays lifetime-by-design and is NOT touched.
 *
 * Cross-ref: PM_DECISION_BRIEF_2026-06-04.md D1; SPEC_419_M4_M8_CANONICAL_METRICS.md §M5; issue #419.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const PAGE = resolve(ROOT, 'src/pages/gamification.astro');
const src = existsSync(PAGE) ? readFileSync(PAGE, 'utf8') : '';

test('PR B: gamification.astro exists', () => {
  assert.ok(existsSync(PAGE), 'src/pages/gamification.astro exists');
});

test('PR B: leaderboardMode defaults to cycle (not lifetime)', () => {
  assert.match(
    src,
    /let leaderboardMode:\s*'cycle'\s*\|\s*'lifetime'\s*=\s*'cycle'\s*;/,
    "leaderboardMode default must be 'cycle'"
  );
  assert.doesNotMatch(
    src,
    /let leaderboardMode:\s*'cycle'\s*\|\s*'lifetime'\s*=\s*'lifetime'\s*;/,
    "leaderboardMode default must not regress to 'lifetime'"
  );
});

test('PR B: lb-mode-cycle button is the active tab on load (matches the cycle default)', () => {
  // The cycle button must carry the active styling (bg-navy text-white), like tr-mode-cycle does.
  const cycleBtn = src.match(/<button id="lb-mode-cycle"[^>]*class="([^"]*)"/);
  assert.ok(cycleBtn, 'lb-mode-cycle button parses');
  assert.match(cycleBtn[1], /bg-navy\b/, 'cycle button has the active background');
  assert.match(cycleBtn[1], /text-white\b/, 'cycle button has the active text colour');
});

test('PR B: lb-mode-lifetime button is the inactive tab on load', () => {
  const lifeBtn = src.match(/<button id="lb-mode-lifetime"[^>]*class="([^"]*)"/);
  assert.ok(lifeBtn, 'lb-mode-lifetime button parses');
  assert.match(lifeBtn[1], /bg-transparent\b/, 'lifetime button is inactive (transparent)');
  assert.doesNotMatch(lifeBtn[1], /bg-navy\b/, 'lifetime button must not carry the active background');
});

test('PR B: button active-state is consistent with the JS default (no desync)', () => {
  // Whatever mode is the JS default, its button must be the visually-active one.
  const def = src.match(/let leaderboardMode:[^=]*=\s*'(cycle|lifetime)'/);
  assert.ok(def, 'leaderboardMode default parses');
  const activeId = def[1] === 'cycle' ? 'lb-mode-cycle' : 'lb-mode-lifetime';
  const inactiveId = def[1] === 'cycle' ? 'lb-mode-lifetime' : 'lb-mode-cycle';
  const active = src.match(new RegExp(`<button id="${activeId}"[^>]*class="([^"]*)"`));
  const inactive = src.match(new RegExp(`<button id="${inactiveId}"[^>]*class="([^"]*)"`));
  assert.ok(active && inactive, 'both leaderboard mode buttons parse');
  assert.match(active[1], /bg-navy/, `${activeId} (the default) must be the active tab`);
  assert.match(inactive[1], /bg-transparent/, `${inactiveId} must be the inactive tab`);
});
