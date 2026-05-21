/**
 * BUG-227.A forward-defense — no RLS policy may pass auth.uid() directly to can()
 *
 * Background: Issue #227 (p209/#226 Phase A) — the original selection-resumes
 * storage policy used `can(auth.uid(), 'view_pii')`. That argument is wrong:
 * `can()` expects `persons.id`, but `auth.uid()` returns `auth.users.id`,
 * which equals `members.auth_id`, NOT `persons.id`. The clause never matched
 * → bucket appeared empty for ALL authenticated users (silent 400 on download).
 *
 * Phase A fix (migration 20260802000000) replaced the policy with
 * `rls_can('view_pii')` — a SECURITY DEFINER wrapper that does the
 * `auth.uid() → persons.id` translation internally. Confirmed live at p211:
 * `pg_policies` shows 0 policies with the buggy pattern.
 *
 * This test is the canonical forward-defense:
 *   1. Phase A migration must exist and use rls_can('view_pii') for the
 *      selection_resumes_read_view_pii policy.
 *   2. NO migration created after the Phase A cutover (20260802000000) may
 *      introduce a CREATE POLICY block whose USING/WITH CHECK clause calls
 *      `can(auth.uid(), ...)` literally.
 *
 * Why static / allowlist by cutover: 4 historical migrations legitimately
 * contain `can(auth.uid()` text (the original p195 policy + Phase A drop +
 * p178 drift capture + an old V4 phase7 RPC). Grepping ALL migrations would
 * false-flag these. Cutover at the Phase A timestamp catches only NEW
 * regressions.
 *
 * Why not behavioural live pg_policies query: PostgREST does not expose
 * system catalogs; adding a SECDEF helper just for this test is overkill.
 * Live audit lives in the /audit skill instead.
 *
 * Cross-ref: Issue #227; P162 log #108 RESOLVED-227.A; migration
 * 20260802000000_p209_issue_226_phase_a_storage_policy_use_rls_can.sql;
 * commit `658e09de` (PR #228 Phase A); ADR-0007 (V4 canonical authority).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const MIGRATIONS_DIR = resolve(process.cwd(), 'supabase/migrations');
const CUTOVER = '20260802000000'; // Phase A SECDEF — anything after MUST not regress
const PHASE_A_FILE = '20260802000000_p209_issue_226_phase_a_storage_policy_use_rls_can.sql';

function listMigrations() {
  return readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort();
}

function isAfterCutover(filename) {
  const version = filename.match(/^(\d{14})/)?.[1];
  return version && version > CUTOVER;
}

function stripSqlLineComments(sql) {
  // Don't false-flag a `can(auth.uid()` reference inside a rollback comment.
  return sql
    .split('\n')
    .map((line) => {
      const commentIdx = line.indexOf('--');
      return commentIdx >= 0 ? line.slice(0, commentIdx) : line;
    })
    .join('\n');
}

test('Phase A SECDEF migration exists and uses rls_can() for selection_resumes_read_view_pii', () => {
  const sql = readFileSync(join(MIGRATIONS_DIR, PHASE_A_FILE), 'utf8');
  assert.match(
    sql,
    /DROP POLICY IF EXISTS selection_resumes_read_view_pii ON storage\.objects/i,
    'Phase A migration must DROP the pre-fix policy'
  );
  assert.match(
    sql,
    /CREATE POLICY selection_resumes_read_view_pii ON storage\.objects/i,
    'Phase A migration must CREATE the corrected policy'
  );
  assert.match(
    sql,
    /rls_can\(\s*['"]view_pii['"]\s*\)/i,
    'Phase A migration must use rls_can(\'view_pii\') wrapper, not can(auth.uid(), ...)'
  );
});

test('No post-cutover migration may pass auth.uid() directly to can() in an RLS policy', () => {
  const files = listMigrations().filter(isAfterCutover);
  const offenders = [];

  for (const file of files) {
    const raw = readFileSync(join(MIGRATIONS_DIR, file), 'utf8');
    const sql = stripSqlLineComments(raw);

    // Pattern: CREATE POLICY ... USING (... can(auth.uid() ...) or
    //         CREATE POLICY ... WITH CHECK (... can(auth.uid() ...)
    // Match across newlines because policy bodies are often multi-line.
    const policyBlocks = sql.match(
      /CREATE\s+POLICY[\s\S]*?(?:;|$)/gi
    ) ?? [];

    for (const block of policyBlocks) {
      if (/\bcan\s*\(\s*auth\.uid\s*\(\s*\)/i.test(block)) {
        offenders.push({ file, snippet: block.slice(0, 200) });
      }
    }
  }

  if (offenders.length > 0) {
    const detail = offenders
      .map((o) => `  - ${o.file}\n    ${o.snippet.replace(/\n/g, '\n    ')}`)
      .join('\n\n');
    assert.fail(
      `BUG-227.A regression: ${offenders.length} post-cutover migration(s) ` +
      `pass auth.uid() directly to can() inside a CREATE POLICY block. ` +
      `Use rls_can('action') wrapper instead (translates auth.uid() → persons.id).\n\n${detail}`
    );
  }
});
