/**
 * #503 — gamification.astro "Meus Pontos" panel: the value rendered under the
 * current-cycle label must be the CYCLE aggregate, not lifetime.
 *
 * Bug: `const cyclePoints = leaderboardData.find(...)?.total_points` (lifetime)
 * was rendered at the mpCurrentCycleLabel slot, so the footer showed lifetime XP
 * labeled as this cycle's XP. get_gamification_leaderboard RETURNS both
 * total_points (lifetime) and cycle_points (cycle) — the panel must read
 * .cycle_points for the cycle slot. One-word fix; this guard locks the
 * cycle/lifetime confusion class that has recurred across #419/#501/#502/#503.
 *
 * Cross-ref: #419 (Bucket-B M5), #501 (RPC rank fix), #502 (board default flip).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const SRC = readFileSync(resolve(process.cwd(), 'src/pages/gamification.astro'), 'utf8');

// (bounded-distance match — the .find((m) => ...) arrow has nested parens, so a [^)]* group stops early)
test('#503: no cyclePoints is sourced from .total_points (the lifetime/cycle mislabel)', () => {
  assert.doesNotMatch(
    SRC,
    /cyclePoints\s*=\s*leaderboardData[\s\S]{0,100}?\?\.total_points/,
    'a variable named cyclePoints must never read .total_points (lifetime) — it renders under the cycle label.'
  );
});

test('#503: cyclePoints reads .cycle_points from leaderboardData', () => {
  assert.match(
    SRC,
    /cyclePoints\s*=\s*leaderboardData[\s\S]{0,100}?\?\.cycle_points/,
    'cyclePoints must source the cycle aggregate (cycle_points) from get_gamification_leaderboard.'
  );
});

test('#503: the current-cycle label slot renders cyclePoints (cycle), lifetime label renders total', () => {
  // mpCurrentCycleLabel slot is followed by the cyclePoints value
  assert.match(
    SRC,
    /mpCurrentCycleLabel[\s\S]{0,120}\$\{cyclePoints\}/,
    'mpCurrentCycleLabel must render ${cyclePoints} (the cycle aggregate).'
  );
  // lifetime label slot is preceded by the lifetime `total`
  assert.match(
    SRC,
    /\$\{total\}[\s\S]{0,200}mpLifetimeLabel/,
    'mpLifetimeLabel must render the lifetime ${total} (not swapped with the cycle value).'
  );
});
