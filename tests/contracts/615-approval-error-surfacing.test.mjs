// #615 forward-defense: the bulk decision handler in /admin/selection must surface the real
// PostgREST error.message when an approval RPC fails, instead of swallowing it into a generic
// "N erro(s)" count. The #603 root cause (approve_selection_application referencing a missing
// selection_cycles.end_date + NOT NULL members.chapter) was diagnosed blind precisely because
// executeBulkDecision's catch was `catch { fail++; }` — the error was discarded before the toast.
//
// Strategy: static source-level contract. Asserts the handler captures the error binding and
// that the failure-path toast interpolates the captured message. If a future edit reverts to a
// bare `catch { fail++; }` or drops the message from the toast, this test fails before deploy.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = process.cwd();
const SELECTION_ASTRO = join(ROOT, 'src', 'pages', 'admin', 'selection.astro');

function executeBulkDecisionBody() {
  const src = readFileSync(SELECTION_ASTRO, 'utf8');
  const start = src.indexOf('async function executeBulkDecision');
  assert.ok(start >= 0, 'executeBulkDecision must exist in selection.astro');
  // slice to the next top-level function declaration so the assertions are scoped to this handler
  const after = src.indexOf('\n  async function ', start + 1);
  const altAfter = src.indexOf('\n  function ', start + 1);
  const end = Math.min(...[after, altAfter].filter(i => i > start));
  return src.slice(start, Number.isFinite(end) ? end : src.length);
}

test('#615 executeBulkDecision binds the caught error (not a bare catch)', () => {
  const body = executeBulkDecisionBody();
  assert.ok(
    /catch\s*\(\s*e\s*:\s*any\s*\)/.test(body),
    'executeBulkDecision must bind the caught error (catch (e: any)), not `catch {`'
  );
  assert.ok(
    !/catch\s*\{\s*fail\+\+;\s*\}/.test(body),
    'executeBulkDecision must NOT use the bare `catch { fail++; }` that swallowed the PostgREST message'
  );
});

test('#615 executeBulkDecision surfaces the captured error.message in the failure toast', () => {
  const body = executeBulkDecisionBody();
  assert.ok(
    /firstError\s*=\s*e\?\.message/.test(body),
    'executeBulkDecision must capture e.message into the error accumulator'
  );
  assert.ok(
    /toast\(`[^`]*\$\{firstError[^`]*`,\s*'error'\)/.test(body),
    'the failure-path toast must interpolate the captured firstError and use the error variant'
  );
});
