// #224 forward-defense: the admin /admin/selection JSON import flow must
// surface worker errors[] inline (grouped by scope) instead of the generic
// "ver detalhes no cron_run_log do worker" hint. The worker /ingest response
// envelope must carry run_id + ingest_result_warning so the admin UI can
// correlate to cron_run_log and disambiguate the Phase A export-side
// ingestResult.error from the current Apply call's status.
//
// Bug history: PM saw "1 erro(s) — ver detalhes no cron_run_log do worker"
// repeatedly between 2026-05-19 → 2026-05-21 on cycle4-2026 applies. The
// underlying error was issueOnboardingToken NOT NULL on organization_id;
// 3 candidates missed welcome emails. The generic UI message hid this
// pattern (filed separately as BUG-224.A).
//
// Strategy: static source-level contract. Asserts the helpers are present
// in selection.astro source and the worker envelope types include the new
// fields. If a future change regresses the renderer or strips the worker
// fields, this test fails before deploy.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = process.cwd();
const SELECTION_ASTRO = join(ROOT, 'src', 'pages', 'admin', 'selection.astro');
const WORKER_TYPES = join(ROOT, 'cloudflare-workers', 'pmi-vep-sync', 'src', 'types.ts');
const WORKER_INDEX = join(ROOT, 'cloudflare-workers', 'pmi-vep-sync', 'src', 'index.ts');

test('selection.astro defines renderWorkerErrorsBlock helper (#224)', () => {
  const src = readFileSync(SELECTION_ASTRO, 'utf8');
  assert.ok(
    /function\s+renderWorkerErrorsBlock\s*\(/.test(src),
    'renderWorkerErrorsBlock helper must exist (groups worker errors by scope)'
  );
});

test('selection.astro defines renderIngestResultWarning helper (#224)', () => {
  const src = readFileSync(SELECTION_ASTRO, 'utf8');
  assert.ok(
    /function\s+renderIngestResultWarning\s*\(/.test(src),
    'renderIngestResultWarning helper must exist (Phase A source-export warning)'
  );
});

test('selection.astro defines renderCorrelationFooter helper (#224)', () => {
  const src = readFileSync(SELECTION_ASTRO, 'utf8');
  assert.ok(
    /function\s+renderCorrelationFooter\s*\(/.test(src),
    'renderCorrelationFooter helper must exist (cycle_code + run_id + applied_at)'
  );
});

test('selection.astro renderJsonApplyResult calls error/warning/correlation helpers (#224)', () => {
  const src = readFileSync(SELECTION_ASTRO, 'utf8');
  // Locate renderJsonApplyResult body block (between function header and the
  // next top-level function declaration in the same indent level).
  const m = src.match(/function\s+renderJsonApplyResult\s*\(([\s\S]*?)\n  function\s/);
  assert.ok(m, 'renderJsonApplyResult function block must be findable');
  const body = m[1];
  assert.ok(
    /renderWorkerErrorsBlock\s*\(\s*d\.errors/.test(body),
    'renderJsonApplyResult must invoke renderWorkerErrorsBlock(d.errors ...)'
  );
  assert.ok(
    /renderIngestResultWarning\s*\(\s*d\.ingest_result_warning/.test(body),
    'renderJsonApplyResult must invoke renderIngestResultWarning(d.ingest_result_warning)'
  );
  assert.ok(
    /renderCorrelationFooter\s*\(\s*d\s*,/.test(body),
    'renderJsonApplyResult must invoke renderCorrelationFooter(d, ...)'
  );
});

test('selection.astro removed legacy "ver detalhes no cron_run_log do worker" generic hint (#224)', () => {
  const src = readFileSync(SELECTION_ASTRO, 'utf8');
  assert.ok(
    !/ver detalhes no cron_run_log do worker/.test(src),
    'Generic "ver detalhes no cron_run_log do worker" message must be replaced by inline error rendering'
  );
});

test('pmi-vep-sync types.ts declares run_id on IngestSummary + IngestDryRunSummary (#224)', () => {
  const src = readFileSync(WORKER_TYPES, 'utf8');
  // Both interfaces should have the field declared. Allow either string|null,
  // optional `?`, or any nullable variant.
  const dryRunBlock = src.match(/interface\s+IngestDryRunSummary\s*\{[\s\S]*?\n\}/);
  const applyBlock = src.match(/interface\s+IngestSummary\s*\{[\s\S]*?\n\}/);
  assert.ok(dryRunBlock, 'IngestDryRunSummary interface must be findable');
  assert.ok(applyBlock, 'IngestSummary interface must be findable');
  assert.ok(
    /run_id\??\s*:/.test(dryRunBlock[0]),
    'IngestDryRunSummary must declare run_id field'
  );
  assert.ok(
    /run_id\??\s*:/.test(applyBlock[0]),
    'IngestSummary must declare run_id field'
  );
});

test('pmi-vep-sync types.ts declares ingest_result_warning on IngestSummary + IngestDryRunSummary (#224)', () => {
  const src = readFileSync(WORKER_TYPES, 'utf8');
  const dryRunBlock = src.match(/interface\s+IngestDryRunSummary\s*\{[\s\S]*?\n\}/);
  const applyBlock = src.match(/interface\s+IngestSummary\s*\{[\s\S]*?\n\}/);
  assert.ok(dryRunBlock, 'IngestDryRunSummary interface must be findable');
  assert.ok(applyBlock, 'IngestSummary interface must be findable');
  assert.ok(
    /ingest_result_warning\??\s*:/.test(dryRunBlock[0]),
    'IngestDryRunSummary must declare ingest_result_warning field'
  );
  assert.ok(
    /ingest_result_warning\??\s*:/.test(applyBlock[0]),
    'IngestSummary must declare ingest_result_warning field'
  );
});

test('pmi-vep-sync index.ts stamps run_id + ingest_result_warning in both code paths (#224)', () => {
  const src = readFileSync(WORKER_INDEX, 'utf8');
  // Dry-run path: stamp before "return jsonResponse(dryDiff, 200)"
  const dryRunStampPattern = /dryDiff\.run_id\s*=\s*runId/;
  const dryRunWarningPattern = /dryDiff\.ingest_result_warning\s*=\s*body\.ingestResult/;
  // Apply path: stamp before "return jsonResponse(summary, 200)"
  const applyStampPattern = /summary\.run_id\s*=\s*runId/;
  const applyWarningPattern = /summary\.ingest_result_warning\s*=\s*body\.ingestResult/;
  assert.ok(
    dryRunStampPattern.test(src),
    'Dry-run path must stamp dryDiff.run_id = runId'
  );
  assert.ok(
    dryRunWarningPattern.test(src),
    'Dry-run path must stamp dryDiff.ingest_result_warning = body.ingestResult ?? null'
  );
  assert.ok(
    applyStampPattern.test(src),
    'Apply path must stamp summary.run_id = runId'
  );
  assert.ok(
    applyWarningPattern.test(src),
    'Apply path must stamp summary.ingest_result_warning = body.ingestResult ?? null'
  );
});

test('selection.astro SEL_I18N bundle exposes importJson labels (#224)', () => {
  const src = readFileSync(SELECTION_ASTRO, 'utf8');
  // The SEL_I18N bundle must include the 6 new keys so the inline TS
  // helpers can read them via window.__SEL_I18N.importJson.
  const expectedKeys = [
    'admin.selection.importJsonResultPartialTitle',
    'admin.selection.importJsonCorrelationRunId',
    'admin.selection.importJsonCorrelationCycle',
    'admin.selection.importJsonCorrelationApplied',
    'admin.selection.importJsonErrorsHeader',
    'admin.selection.importJsonIngestResultWarning',
  ];
  for (const k of expectedKeys) {
    assert.ok(
      new RegExp(`t\\(\\s*'${k.replace(/\./g, '\\.')}'`).test(src),
      `SEL_I18N must include t('${k}', lang) so importJson labels reach client`
    );
  }
});
