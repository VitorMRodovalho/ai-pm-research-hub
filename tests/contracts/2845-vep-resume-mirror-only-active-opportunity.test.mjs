/**
 * Contract: #2845 — the /ingest resume pre-flight mirrors a CV only when the
 * application's opportunity is registered and active.
 *
 * The pre-flight runs before the per-app loops, and those loops skip an application
 * whose opportunity is missing (opportunity_not_found) or inactive
 * (opportunity_inactive). Before this fix the pre-flight took every application with a
 * resumeUrl, so a skipped candidate still had a PDF written to selection-resumes with
 * no selection_applications row behind it. Measured on an import: PDFs of applications
 * skipped as opportunity_not_found were in the bucket.
 *
 * Comments are masked so the explanation of the filter cannot stand in for the filter.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const src = maskJsComments(readFileSync(
  resolve(process.cwd(), 'cloudflare-workers/pmi-vep-sync/src/index.ts'), 'utf8'));

function preflight() {
  const handleAt = src.indexOf('async function handleIngest(');
  const lookupAt = src.indexOf('oppLookup[String(o.opportunity_id)] = o;', handleAt);
  const syncAt = src.indexOf('await syncResumesParallel(', handleAt);
  const startAt = src.lastIndexOf('if (body.dry_run !== true) {', syncAt);
  assert.ok(handleAt > 0 && lookupAt > handleAt && startAt > lookupAt && syncAt > startAt,
    'the opportunity lookup must be built before the resume pre-flight opens');
  return { block: src.slice(startAt, src.indexOf('\n  }\n', syncAt)), syncAt };
}

test('#2845: only applications of a registered and active opportunity reach the CV mirror', () => {
  const { block } = preflight();
  assert.match(block, /const hasResume = \(a: ScriptApplication\) => !!\(a\.resumeUrl && a\.applicantId\);/,
    'an application has a resume only with both the link and the applicant id');
  assert.match(block,
    /const appsWithResume = body\.applications\.filter\(\s*a => hasResume\(a\) && oppLookup\[String\(a\._opportunityId\)\]\?\.is_active === true\s*\);/,
    'the mirror set requires a resume AND an opportunity row that is active, the same condition that lets the application reach the upsert');
  assert.match(block,
    /await syncResumesParallel\(\s*env\.\w+,\s*env\.\w+,\s*appsWithResume,/,
    'the mirror must receive that filtered set, not body.applications');
});

test('#2845: resumes_skipped_no_url counts only applications without a resume', () => {
  const { block } = preflight();
  assert.match(block, /const appsWithoutResume = body\.applications\.filter\(a => !hasResume\(a\)\)\.length;/,
    'the counter is the applications lacking a link or an applicant id');
  const assigns = [...block.matchAll(/summary\.resumes_skipped_no_url = ([^;]+);/g)].map((m) => m[1].trim());
  assert.deepEqual(assigns, ['appsWithoutResume', 'appsWithoutResume'],
    'both branches report that count, so a skipped opportunity is not reported as a missing link');
});
