/**
 * Migration-drift classifier — turns "NEW drift" reds into a diagnosis.
 *
 * WHY THIS EXISTS
 * The ADR-0097 / Phase-C gates in `tests/contracts/rpc-migration-coverage.test.mjs`
 * compare the SHARED remote DB against the CHECKOUT's migration files. Three very
 * different situations produce the same red, and only one of them is authored drift:
 *
 *   1. PHANTOM tracking row — `apply_migration` via the Supabase MCP writes a row in
 *      `supabase_migrations.schema_migrations` using the migration NAME we passed, but
 *      stamps it with a WALL-CLOCK version and writes no local file. After the manual
 *      GC-097 sync (`Write` the file under the repo's own version + `migration repair`),
 *      the wall-clock row survives as a duplicate-by-name orphan.
 *      Remedy: DELETE that row by EXACT version (never LIKE) — see
 *      [[reference-gc097-phantom-row-delete-scope-care]].
 *
 *   2. PROD-AHEAD (DDL-lag) — the DDL is already applied to the shared DB but the .sql
 *      has not landed in THIS checkout yet (concurrent DDL PR, or an apply that merges
 *      later). Every other branch, and main itself until the file merges, goes red.
 *      Remedy: land/rebase the file. Nothing to "recover" — see
 *      [[reference-shared-db-drift-gate-serializes-ddl-prs]].
 *
 *   3. GENUINE missing file — the pre-GC-097 class the baselines were built for:
 *      DDL applied without any file, body only in `statements`/`pg_proc`.
 *      Remedy: recover the .sql (or, rarely, extend the baseline with PM ack).
 *
 * Measured on 2026-07-24 over the last 200 CI runs: of 21 non-Dependabot failures,
 * 12 involved this class. The generic message pointed all of them at remedy (3),
 * which is wrong for (1) and (2) — so each occurrence cost a fresh live audit.
 * Classifying does NOT weaken the gate: every class still fails.
 *
 * Pure functions only (no fs, no network) so the logic is guarded offline by
 * `tests/contracts/migration-drift-classifier.test.mjs`.
 */

/** Repo migration versions are numeric strings of mixed length; compare them by value. */
const normalizeVersion = (v) => String(v).padEnd(14, '0');

export function compareVersions(a, b) {
  const na = normalizeVersion(a);
  const nb = normalizeVersion(b);
  return na < nb ? -1 : na > nb ? 1 : 0;
}

/** Highest version present in the checkout, or null when there are no local files. */
export function checkoutHead(localVersions) {
  let head = null;
  for (const v of localVersions) {
    if (head === null || compareVersions(v, head) > 0) head = v;
  }
  return head;
}

/**
 * Tracked versions newer than the checkout's head — i.e. the shared DB carries DDL
 * this checkout does not know about. Empty when the checkout is level with prod.
 */
export function prodAheadVersions({ trackedVersions, localVersions }) {
  const head = checkoutHead(localVersions);
  if (head === null) return [];
  return [...trackedVersions]
    .filter((v) => compareVersions(v, head) > 0)
    .sort(compareVersions);
}

/**
 * Split "tracked but no local .sql" versions into the three remediation classes.
 *
 * @param {object}   input
 * @param {string[]} input.missingVersions - tracked − local, already minus the baseline.
 * @param {Array<{version: string, name?: string}>} input.trackedRows - schema_migrations rows.
 * @param {Set<string>|string[]} input.localVersions - versions parsed off local filenames.
 * @param {Map<string,string>|Set<string>|string[]} input.localNames - names parsed off local
 *        filenames; pass a Map name->version to get the colliding file back in the report.
 * @returns {{phantom: Array, prodAhead: string[], genuine: string[]}}
 */
export function classifyMissingFileDrift({
  missingVersions,
  trackedRows,
  localVersions,
  localNames,
}) {
  const nameByVersion = new Map(
    (trackedRows ?? []).map((r) => [String(r.version), r.name ?? null])
  );
  const localNameMap =
    localNames instanceof Map
      ? localNames
      : new Map([...(localNames ?? [])].map((n) => [n, null]));
  const versions = localVersions instanceof Set ? localVersions : new Set(localVersions ?? []);
  const head = checkoutHead(versions);

  const phantom = [];
  const prodAhead = [];
  const genuine = [];

  for (const version of [...missingVersions].sort(compareVersions)) {
    const name = nameByVersion.get(String(version)) ?? null;
    if (name && localNameMap.has(name)) {
      phantom.push({ version, name, localVersion: localNameMap.get(name) ?? null });
    } else if (head !== null && compareVersions(version, head) > 0) {
      prodAhead.push(version);
    } else {
      genuine.push(version);
    }
  }

  return { phantom, prodAhead, genuine };
}

/**
 * Render the classified drift as remediation text. Each class gets the action that
 * actually resolves it, instead of one generic "write the .sql or extend the baseline".
 */
export function formatMissingFileDriftReport({ phantom, prodAhead, genuine }, opts = {}) {
  const { baselinePath = '<baseline file>', baselineConstant = 'MIGRATION_FILE_DRIFT_BASELINE_SIZE' } = opts;
  const blocks = [];

  if (phantom.length > 0) {
    blocks.push(
      `LIKELY PHANTOM tracking row(s) — ${phantom.length}\n` +
        `  A local migration file already carries this exact NAME under a different version,\n` +
        `  which is the residue signature of apply_migration via MCP (it reuses the name we\n` +
        `  pass but stamps a wall-clock version and writes no file).\n` +
        `  CONFIRM FIRST — name reuse also happens legitimately in the pre-GC-097 history\n` +
        `  (522 duplicate names live in schema_migrations as of 2026-07-24). Check that the\n` +
        `  local file below really captures the same DDL before deleting anything; if it does\n` +
        `  not, this is a GENUINE missing file and the row must be kept.\n` +
        `  Then delete by EXACT version (never LIKE — it would take the real row too):\n` +
        phantom
          .map(
            (p) =>
              `    ${p.name}\n` +
              `      tracked row : ${p.version}  (no local file)\n` +
              `      local file  : ${p.localVersion ? `${p.localVersion}_${p.name}.sql` : '<same name, version unknown>'}\n` +
              `      DELETE FROM supabase_migrations.schema_migrations WHERE version = '${p.version}';`
          )
          .join('\n')
    );
  }

  if (prodAhead.length > 0) {
    blocks.push(
      `PROD-AHEAD / DDL-lag — ${prodAhead.length}\n` +
        `  These version(s) are NEWER than this checkout's migration head: the shared DB\n` +
        `  already has the DDL, the .sql has not landed here yet. This is NOT drift you\n` +
        `  authored, and writing a recovery file would duplicate the real migration.\n` +
        `  Fix: land the .sql in this PR, or rebase onto the branch that carries it.\n` +
        `  DDL on a shared DB serializes PRs (apply -> merge -> apply).\n` +
        prodAhead.map((v) => `    ${v}`).join('\n')
    );
  }

  if (genuine.length > 0) {
    blocks.push(
      `GENUINE missing file — ${genuine.length}\n` +
        `  Tracked, older than the checkout head, and no local file claims the name.\n` +
        `  Fix: (a) write the .sql from the tracked body\n` +
        `       (SELECT statements FROM supabase_migrations.schema_migrations WHERE version='<v>'), or\n` +
        `       (b) extend ${baselinePath} with PM ack + bump ${baselineConstant} (rare).\n` +
        genuine.map((v) => `    ${v}`).join('\n')
    );
  }

  return blocks.join('\n\n');
}

/**
 * Banner prepended to body-hash drift failures when the checkout is behind prod.
 * Live bodies legitimately diverge from the checkout's captures in that state, so the
 * reader should reconcile the lag BEFORE treating the entries as authored drift.
 */
export function prodAheadBanner(ahead, head) {
  if (!ahead || ahead.length === 0) return '';
  return (
    `PROD-AHEAD: the shared DB carries ${ahead.length} migration version(s) newer than ` +
    `this checkout's head (${head}):\n  ${ahead.join('\n  ')}\n` +
    `Live bodies are EXPECTED to diverge from this checkout's captures while that lag ` +
    `exists (DDL-lag, not authored drift). Land/rebase the missing .sql first, then re-read ` +
    `the entries below.\n\n`
  );
}
