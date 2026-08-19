/**
 * Declared exceptions to the schema-invariant contract.
 *
 * WHY THIS EXISTS (#1850)
 * -----------------------
 * `check_schema_invariants()` returns the full invariant set, and sixteen
 * contract tests assert over its output. Twelve of them do it as a BROAD
 * CANARY while testing something else entirely: extraction pipeline,
 * auto-rescue, material chain, invariant R, promotion milestone, version pin.
 * That canary is worth keeping. A new violation anywhere should turn any of
 * them red.
 *
 * What was missing is a way to say "this violation is known, approved, and
 * open on purpose". Without it a single PM-approved open violation turned
 * `validate` red on EVERY PR in the repo, because `validate` is a REQUIRED
 * check while the dedicated `check-invariants` job is not. The borrowed
 * assertions had silently promoted a non-blocking signal into a blocking gate,
 * and the queue froze for a reason unrelated to any of the PRs in it.
 *
 * CONTRACT
 * --------
 *  - An UNDECLARED violation always fails. The canary keeps its teeth.
 *  - A DECLARED violation is tolerated only until its `expires` date. Past
 *    that date it fails again, so an exception cannot outlive its review.
 *  - `INVARIANT_STRICT=1` disables every declaration. The `check-invariants`
 *    workflow sets it, and that is what keeps that job honestly RED while a
 *    violation is open. Muting the required gate must never mute the signal.
 *
 * RATCHET
 * -------
 * When a violation clears, DELETE its entry. These are not baselines to be
 * grown, and the count here only ever goes down. Each entry is a dated promise
 * with an issue behind it.
 */

export const DECLARED_INVARIANT_EXCEPTIONS = [
  {
    invariant: 'U_active_person_has_primary_chapter_affiliation',
    issue: 1850,
    expires: '2026-09-30',
    reason:
      'An approval written by direct SQL bypassed approve_selection_application, '
      + 'so the chapter affiliation was never seeded. Repairing the row by hand '
      + 'would bypass the Diretoria de Filiacao, which owns that data, and the '
      + 'hand-written row would be indistinguishable from a real verification. '
      + 'The PM decided to hold the violation open until verification happens '
      + 'through the process that exists. See #1850.',
  },
];

/** Calendar day (UTC) as YYYY-MM-DD. ISO date strings compare correctly as strings. */
export function toDay(date = new Date()) {
  return date.toISOString().slice(0, 10);
}

export function strictMode(env = process.env) {
  return env.INVARIANT_STRICT === '1';
}

/** An entry stays valid through the whole of its expiry day. */
export function isExpired(exception, today = new Date()) {
  return toDay(today) > exception.expires;
}

/** Declarations in force right now. Empty in strict mode, by design. */
export function activeExceptions(today = new Date(), env = process.env) {
  if (strictMode(env)) return [];
  return DECLARED_INVARIANT_EXCEPTIONS.filter((e) => !isExpired(e, today));
}

/**
 * Violations that should fail the build: everything with violation_count > 0
 * that is not covered by an in-force declaration.
 */
export function unexpectedViolations(rows, today = new Date(), env = process.env) {
  const tolerated = new Set(activeExceptions(today, env).map((e) => e.invariant));
  return (Array.isArray(rows) ? rows : []).filter(
    (r) => Number(r.violation_count) > 0 && !tolerated.has(r.invariant_name),
  );
}

export function describeViolations(rows) {
  return (rows || []).map((r) => `${r.invariant_name}=${r.violation_count}`).join(', ');
}

/** Assertion message that names the offenders AND the declarations in force. */
export function violationsMessage(rows, today = new Date(), env = process.env) {
  const unexpected = unexpectedViolations(rows, today, env);
  const active = activeExceptions(today, env);
  const lines = [`unexpected invariant violations: ${describeViolations(unexpected)}`];
  if (active.length) {
    lines.push(
      `declared exceptions in force: ${active.map((e) => `${e.invariant} (#${e.issue}, expires ${e.expires})`).join('; ')}`,
    );
  }
  if (strictMode(env)) lines.push('INVARIANT_STRICT=1: declarations disabled for this run.');
  return lines.join('\n  ');
}

/**
 * Entries that are declared but no longer violated: the ratchet is ready to
 * move and the entry should be deleted. Surfaced as a warning rather than a
 * failure, so that clearing a violation never freezes the merge queue by
 * surprise. The `expires` date is the forcing function, not this.
 */
export function staleExceptions(rows, today = new Date()) {
  const violated = new Set(
    (Array.isArray(rows) ? rows : [])
      .filter((r) => Number(r.violation_count) > 0)
      .map((r) => r.invariant_name),
  );
  return DECLARED_INVARIANT_EXCEPTIONS.filter(
    (e) => !violated.has(e.invariant) && !isExpired(e, today),
  );
}
