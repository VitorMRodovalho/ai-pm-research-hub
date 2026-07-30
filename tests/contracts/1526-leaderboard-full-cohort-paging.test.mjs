import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const PAGE = 'src/pages/gamification.astro';

/**
 * #1526 — `get_gamification_leaderboard` defaults to `p_limit = 50` and clamps server-side.
 * The gamification page used to call it with NO arguments from three places, so it saw only the
 * first page: 50 of 87 eligible members at the time of measurement, with no pagination and no
 * "showing N of M" notice.
 *
 * The cut was never only cosmetic. The same `leaderboardData` array feeds:
 *   - the individual ranking (rows simply missing, and the invisible ones had no way to know);
 *   - the TRIBE aggregation in loadTribeRanking(), which summed points over a truncated cohort;
 *   - the achievement checks in loadAchievements().
 * It was also asymmetric: the RPC cut by LIFETIME points even when the UI was on the cycle tab,
 * so which members fell out depended on a ranking the user was not looking at.
 *
 * Guard: every call to the RPC from the page must carry paging arguments, i.e. go through the
 * helper that walks `total_count` to completion. This asserts the CONSUMER pattern (how the page
 * reaches the data), never the definition site of the helper, so renaming or relocating the helper
 * stays legal — only reintroducing an unpaged call fails.
 */

const src = readFileSync(resolve(ROOT, PAGE), 'utf8');

test('#1526 no unpaged call to get_gamification_leaderboard survives in the gamification page', () => {
  // Every textual invocation of the RPC (sb.rpc('get_gamification_leaderboard'...)).
  const calls = [...src.matchAll(/sb\.rpc\(\s*['"]get_gamification_leaderboard['"]([\s\S]{0,220}?)\)/g)];

  assert.ok(
    calls.length > 0,
    `expected at least one get_gamification_leaderboard call in ${PAGE}; if the page stopped using ` +
      'the RPC entirely, retire this guard deliberately rather than letting it pass vacuously',
  );

  for (const [match, tail] of calls) {
    assert.match(
      tail,
      /p_offset/,
      `unpaged leaderboard call found in ${PAGE}: ${match.slice(0, 120)}\n` +
        'Calling the RPC without p_limit/p_offset silently takes only the first 50 rows, which also ' +
        'truncates the tribe aggregation and the achievement checks (#1526). Route it through the ' +
        'paging helper that consumes total_count.',
    );
  }
});

test('#1526 the paging loop advances by what the server returned and is bounded', () => {
  // The stride must come from the response, not from a client-side copy of the server clamp,
  // and the loop must have a hard page bound so a misbehaving total_count cannot spin forever.
  assert.match(
    src,
    /p_offset:\s*rows\.length/,
    'the paging loop must advance p_offset by the rows actually collected, so the server-side ' +
      'clamp remains the single source of truth for page size',
  );
  assert.match(
    src,
    /total_count/,
    'the paging loop must read total_count to know when the cohort is complete',
  );
  assert.match(
    src,
    /LEADERBOARD_MAX_PAGES/,
    'the paging loop must carry an explicit page bound (runaway guard)',
  );
});
