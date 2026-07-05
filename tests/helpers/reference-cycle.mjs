/**
 * Reference-cycle resolver for DB-live contract tests that assert against a POPULATED cycle.
 *
 * At a cycle boundary the current cycle (cycles.is_current) can be empty, or its window can start
 * in the future: the early C3→C4 turnover (2026-07-05) flipped is_current to cycle_4 whose
 * cycle_start is 2026-07-09. Every cycle-window-scoped aggregate (attendance engagement/reliability,
 * gamification buckets) then reads zero rows, so tests that (correctly) require real data go red on
 * the `main` branch, not just in a PR — blocking CI for everyone. See issue #1123.
 *
 * These tests verify RPC SHAPE + sane values, not the identity of the current cycle. They must run
 * against the most recent cycle that actually carries data — resolved dynamically, never hardcoded
 * (a hardcoded 'cycle_3' would freeze the test and re-break at the next boundary). The resolver
 * walks cycles newest→oldest and returns the first whose window has data; during a new cycle's
 * empty opening it stays on the last populated cycle and auto-advances once the new cycle fills.
 *
 * Cross-ref: issue #1123; SPEC_419_M3_ATTENDANCE_TWO_METRIC.md; #1080.
 */
import assert from 'node:assert/strict';

/**
 * Walk cycles newest→oldest (by cycle_start desc) and return the first cycle_start for which
 * `probe(cycle_start)` resolves truthy. Returns null if no cycle has data.
 * @param {import('@supabase/supabase-js').SupabaseClient} sb service-role client
 * @param {(cycleStart: string) => Promise<boolean>} probe
 */
export async function newestCycleStartWithData(sb, probe) {
  const { data: cycles, error } = await sb
    .from('cycles')
    .select('cycle_start')
    .order('cycle_start', { ascending: false });
  assert.ok(!error, error?.message);
  for (const c of cycles || []) {
    if (c.cycle_start && (await probe(c.cycle_start))) return c.cycle_start;
  }
  return null;
}

/**
 * The most recent cycle whose window carries an operational attendance cohort (i.e. the
 * two-metric engagement summary returns a non-empty cohort with recorded presence). This is the
 * reference window for every get_attendance_*_summary / get_attendance_rate DB-live assertion.
 */
export async function attendanceCycleStart(sb) {
  const start = await newestCycleStartWithData(sb, async (cs) => {
    const { data } = await sb.rpc('get_attendance_engagement_summary', {
      p_scope: 'global',
      p_cycle_start: cs,
    });
    return !!data && Number(data.cohort_n) > 0 && Number(data.present_total) > 0;
  });
  assert.ok(start, 'no cycle window carries an operational attendance cohort — cannot ground a two-metric test');
  return start;
}

/**
 * The most recent cycle whose window carries gamification ledger rows. Reference window for the
 * #1080 bucket-partition invariant (which replicates get_member_cycle_xp's cycle-scoped math).
 */
export async function pointsCycleStart(sb) {
  const start = await newestCycleStartWithData(sb, async (cs) => {
    const { count } = await sb
      .from('gamification_points')
      .select('member_id', { count: 'exact', head: true })
      .gte('created_at', cs);
    return Number(count) > 0;
  });
  assert.ok(start, 'no cycle window carries gamification points');
  return start;
}
