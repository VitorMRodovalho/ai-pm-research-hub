/**
 * Contract: #2843 — the extraction script reads its opportunity allowlist from the
 * platform instead of a hard-coded list.
 *
 * The script runs from a local copy outside the repository, so a copy older than a new
 * opportunity treated it as "outside the allowlist" in the LGPD modal while the row was
 * already active in vep_opportunities. The worker now serves GET /opportunities (ids of
 * the active rows + the bucket restriction it enforces at ingest), and the script reads
 * it before the allowlist gate. The hard-coded lists stay as the fallback.
 *
 * Layers:
 *   (A) worker source: the public route exists, filters is_active, and leaves the
 *       worker with the id and the bucket restriction only;
 *   (B) script: the platform block is EXECUTED with stubbed responses, so each
 *       assertion binds a response to the allowlist it produces, including the
 *       fallbacks (an empty allowlist would switch the gate off).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const WORKER_DIR = resolve(process.cwd(), 'cloudflare-workers/pmi-vep-sync');
const indexSrc = maskJsComments(readFileSync(resolve(WORKER_DIR, 'src/index.ts'), 'utf8'));
const scriptSrc = readFileSync(resolve(WORKER_DIR, 'scripts/extract_pmi_volunteer.js'), 'utf8');

// ── Layer A: worker ─────────────────────────────────────────────────────────────

test('#2843: worker serves GET /opportunities before the 404 fallback', () => {
  const routeAt = indexSrc.search(
    /if \(req\.method === 'GET' && url\.pathname === '\/opportunities'\) \{\s*return handleOpportunities\(env\);\s*\}/);
  const notFoundAt = indexSrc.indexOf("error: 'not_found'");
  assert.ok(routeAt > 0, 'the GET /opportunities route must call handleOpportunities');
  assert.ok(notFoundAt > routeAt, 'the route must be matched before the 404 fallback');
});

test('#2843: /opportunities returns only active rows, with the id and the bucket restriction alone', () => {
  const start = indexSrc.indexOf('async function handleOpportunities(');
  assert.ok(start > 0, 'handleOpportunities must exist');
  const fn = indexSrc.slice(start, indexSrc.indexOf('\n}\n', start));

  assert.match(fn,
    /\.filter\(\(o\) => o\.is_active\)\s*\.map\(\(o\) => \(\{\s*opportunity_id: String\(o\.opportunity_id\),\s*import_buckets: OPPORTUNITY_IMPORT_BUCKETS\[String\(o\.opportunity_id\)\] \?\? null\s*\}\)\)/,
    'inactive rows are dropped first, and each row leaves with exactly two fields: the id and the restriction the ingest enforces');
  assert.match(fn, /return jsonResponse\(\{ opportunities \}, 200\);/,
    'the body carries the mapped list and nothing else');

  const catchBlock = fn.slice(fn.indexOf('catch ('), fn.indexOf('const opportunities ='));
  assert.match(catchBlock, /return jsonResponse\(\{ error: 'opportunities_unavailable' \}, 503\);/,
    'a database failure answers 503, so the script falls back');
  assert.doesNotMatch(catchBlock.slice(catchBlock.indexOf('return jsonResponse')), /e\.message/,
    'the database error stays in the log, never in the public body');
});

// ── Layer B: script ─────────────────────────────────────────────────────────────

const BEGIN = '// >>> #2843 platform-allowlist';
const END = '// <<< #2843 platform-allowlist';

function platformBlock() {
  const a = scriptSrc.indexOf(BEGIN);
  const b = scriptSrc.indexOf(END);
  assert.ok(a > 0 && b > a, 'the platform-allowlist block must be delimited');
  return scriptSrc.slice(a, b);
}

const AsyncFunction = (async () => {}).constructor;

async function runBlock(response, { url = 'https://worker.example/opportunities' } = {}) {
  const CONFIG = {
    NUCLEO_OPPORTUNITIES_URL: url,
    NUCLEO_OPPORTUNITY_ALLOWLIST: [111, 222],
    NUCLEO_OPPORTUNITY_BUCKETS: { 222: ['qualified'] },
  };
  const calls = [];
  const fetchJson = async (u) => {
    calls.push(u);
    if (response instanceof Error) throw response;
    return response;
  };
  const logs = [];
  const quiet = { log: (m) => logs.push(['log', m]), warn: (m) => logs.push(['warn', m]) };
  const run = new AsyncFunction('CONFIG', 'fetchJson', 'console', platformBlock() + '\nreturn allowlistSource;');
  const source = await run(CONFIG, fetchJson, quiet);
  return { CONFIG, source, calls, logs };
}

test('#2843: a valid platform list replaces the allowlist and the bucket map', async () => {
  const r = await runBlock({ opportunities: [
    { opportunity_id: '64966', import_buckets: null },
    { opportunity_id: '72562', import_buckets: ['qualified'] },
    { opportunity_id: '76664', import_buckets: null },
  ] });
  assert.deepEqual(r.calls, ['https://worker.example/opportunities']);
  assert.equal(r.source, 'platform');
  assert.deepEqual(r.CONFIG.NUCLEO_OPPORTUNITY_ALLOWLIST, [64966, 72562, 76664]);
  assert.deepEqual(r.CONFIG.NUCLEO_OPPORTUNITY_BUCKETS, { 72562: ['qualified'] },
    'only restricted opportunities enter the bucket map, and the fallback map is not kept');
});

test('#2843: any unusable answer keeps the hard-coded lists and warns', async () => {
  const cases = {
    'fetch fails': new Error('HTTP 404'),
    'empty list': { opportunities: [] },
    'no list': { error: 'opportunities_unavailable' },
    'non-numeric id': { opportunities: [{ opportunity_id: 'abc', import_buckets: null }] },
    'buckets not an array': { opportunities: [{ opportunity_id: '72562', import_buckets: 'qualified' }] },
    'one bad row among good ones': { opportunities: [
      { opportunity_id: '64966', import_buckets: null },
      { opportunity_id: '64967' },
    ] },
  };
  for (const [name, response] of Object.entries(cases)) {
    const r = await runBlock(response);
    assert.equal(r.source, 'config', `${name}: the source must stay config`);
    assert.deepEqual(r.CONFIG.NUCLEO_OPPORTUNITY_ALLOWLIST, [111, 222], `${name}: the allowlist must stay the fallback`);
    assert.deepEqual(r.CONFIG.NUCLEO_OPPORTUNITY_BUCKETS, { 222: ['qualified'] }, `${name}: the bucket map must stay the fallback`);
    assert.ok(r.logs.some(([lvl]) => lvl === 'warn'), `${name}: the fallback must be announced in the console`);
  }
});

test('#2843: without a URL the script does not call out and keeps the hard-coded lists', async () => {
  const r = await runBlock({ opportunities: [{ opportunity_id: '1', import_buckets: null }] }, { url: '' });
  assert.deepEqual(r.calls, []);
  assert.equal(r.source, 'config');
  assert.deepEqual(r.CONFIG.NUCLEO_OPPORTUNITY_ALLOWLIST, [111, 222]);
});

test('#2843: the block runs before the allowlist gate, points at the ingest worker, and its source reaches meta.lgpd', () => {
  const blockAt = scriptSrc.indexOf(BEGIN);
  const historicalAt = scriptSrc.indexOf('const historicalIds = ');
  const gateAt = scriptSrc.indexOf('const allowlistSet = new Set([');
  assert.ok(historicalAt > 0 && blockAt > historicalAt && gateAt > blockAt,
    'the platform read must come after the discovery and before the gate builds its set');

  const ingest = scriptSrc.match(/NUCLEO_INGEST_URL: '(https:\/\/[^/']+)\/ingest'/);
  const opportunities = scriptSrc.match(/NUCLEO_OPPORTUNITIES_URL: '([^']+)'/);
  assert.ok(ingest && opportunities, 'both worker URLs must be findable');
  assert.equal(opportunities[1], `${ingest[1]}/opportunities`,
    'the opportunities URL must be the same worker as the ingest');

  assert.match(scriptSrc, /meta\.lgpd = \{[\s\S]{0,1500}?allowlist_source: allowlistSource,/,
    'the JSON header must record where the allowlist came from');
});
