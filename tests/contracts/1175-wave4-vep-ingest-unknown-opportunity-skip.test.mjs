/**
 * Contract: #1175 Wave 4 — unknown VEP opportunity is SKIPPED by design across the
 * whole import chain (script -> worker /ingest -> vep_opportunities).
 *
 * Grounded 2026-07-08 (import run 8d9b8128): the 07/07 JSON carried 135 applications,
 * 2 from opportunity 72562 (chapter-board vacancy, NOT the Nucleo's — PM decision D1).
 * The worker skipped exactly those 2 because 72562 is not registered in
 * vep_opportunities. D1 was revised on 2026-10-29 (#2827): 72562 is imported, but only
 * its qualified bucket (people the chapter already placed), in the script AND in the
 * worker; its submitted and rejected candidates never reach the upsert. (#1554 later split the single 'opportunity_not_active' scope
 * into 'opportunity_not_found' and 'opportunity_inactive'; the guards below assert
 * the skip BEHAVIOUR, not the label, so a future rename stays legal.)
 *
 * Layers:
 *   (A) offline static guards on the worker source + canonical script copy
 *       (cloudflare-workers/pmi-vep-sync/) — the skip path and the Wave 4 script
 *       reform (allowlist gate, placeholder-secret skip, serviceHistory contract)
 *       must not regress;
 *   (B) DB-aware (skipped without SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY) — the
 *       vep_opportunities registry itself: 62106 historical inactive (D4), and every
 *       ACTIVE row within the Nucleo allowlist.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const WORKER_DIR = resolve(process.cwd(), 'cloudflare-workers/pmi-vep-sync');
const indexSrc = readFileSync(resolve(WORKER_DIR, 'src/index.ts'), 'utf8');
const mapperSrc = readFileSync(resolve(WORKER_DIR, 'src/script-mapper.ts'), 'utf8');
const scriptSrc = readFileSync(resolve(WORKER_DIR, 'scripts/extract_pmi_volunteer.js'), 'utf8');

const NUCLEO_ALLOWLIST = ['64966', '64967', '66470', '72562', '76080', '76631', '76661', '76662', '76663', '76664'];

// ── Layer A: worker source guards ──────────────────────────────────────────────

// #1554 rewrote the labels: the single `opportunity_not_active` scope split into
// `opportunity_not_found` (real gap) and `opportunity_inactive` (expected), and
// the lookup stopped filtering is_active so the loop could tell them apart.
//
// These guards used to assert the OLD scope string and the `.eq('is_active', true)`
// filter — i.e. the shape of the implementation, not the invariant. That would have
// blocked a legitimate refactor while protecting nothing. What #1175 actually needs
// guaranteed is behavioural: neither an unregistered NOR an inactive opportunity may
// reach the upsert. Assert THAT.
test('#1175 W4: /ingest live path skips both unknown AND inactive opportunities before the upsert', () => {
  // Anchor on the APPLY loop. `indexSrc` also contains the dry-run preview loop,
  // whose own !opp / mapScriptToNucleo pair would satisfy every assertion below
  // while the apply path regressed — the any-occurrence guard flaw.
  const applyStart = indexSrc.lastIndexOf('for (const app of body.applications)');
  assert.ok(applyStart > 0, 'apply loop must be findable');
  const applyLoop = indexSrc.slice(applyStart);

  assert.match(applyLoop, /if\s*\(!opp\)\s*\{[\s\S]{0,900}?continue;/,
    'an unregistered opportunity must short-circuit the per-app loop');
  assert.match(applyLoop, /if\s*\(!opp\.is_active\)\s*\{[\s\S]{0,900}?continue;/,
    'an inactive opportunity must short-circuit the per-app loop (62106 must not resurrect)');
  assert.match(applyLoop, /summary\.applications_skipped\+\+/,
    'the skip must count into applications_skipped (surfaced in the import summary)');
  // Both branches must precede the mapper call that builds the upsert payload.
  const notFoundAt = applyLoop.indexOf('scope: \'opportunity_not_found\'');
  const inactiveAt = applyLoop.indexOf('scope: \'opportunity_inactive\'');
  const mapAt = applyLoop.indexOf('const mapped = mapScriptToNucleo(');
  assert.ok(notFoundAt > 0 && inactiveAt > 0 && mapAt > 0, 'all three anchors must exist');
  assert.ok(notFoundAt < mapAt && inactiveAt < mapAt,
    'both skip branches must be evaluated before mapScriptToNucleo builds the upsert payload');
});

test('#1175 W4: dry-run preview reports the same two skips as Apply', () => {
  assert.match(indexSrc, /will_skip\.push\(\{\s*ref:[^}]*reason:\s*'opportunity_not_found'/,
    'dry_run must preview the unregistered-opportunity skip so the admin diff matches Apply');
  assert.match(indexSrc, /will_skip\.push\(\{\s*ref:[^}]*reason:\s*'opportunity_inactive'/,
    'dry_run must preview the closed-opportunity skip so the admin diff matches Apply');
});

// #2827 (D1 revised): an opportunity may import only some VEP buckets. The worker
// enforces it on its own, because an older copy of the script still sends every bucket.
// Comments are masked so the explanation of the filter cannot stand in for the filter.
test('#2827: /ingest drops applications outside their opportunity buckets before resume sync, preview and apply', () => {
  const src = maskJsComments(indexSrc);
  assert.match(src, /const OPPORTUNITY_IMPORT_BUCKETS:\s*Record<string,\s*readonly string\[\]>\s*=\s*\{\s*'72562':\s*\['qualified'\]\s*\};/,
    'the worker map must restrict 72562 to the qualified bucket, and nothing else');

  const handleAt = src.indexOf('async function handleIngest(');
  const filterAt = src.indexOf('body.applications = body.applications.filter(', handleAt);
  assert.ok(handleAt > 0 && filterAt > handleAt, 'the bucket filter must live in handleIngest');
  const filterBlock = src.slice(filterAt, src.indexOf('\n  });', filterAt));
  assert.match(filterBlock,
    /const allowed = OPPORTUNITY_IMPORT_BUCKETS\[String\(app\._opportunityId\)\];\s*if \(!allowed \|\| allowed\.includes\(String\(app\._bucket\)\)\) return true;\s*bucketSkipped\.push\(app\);\s*return false;/,
    'an application is kept only when its opportunity has no restriction or its bucket is allowed; otherwise it is set aside');
  assert.match(src, /for \(const app of bucketSkipped\) \{\s*summary\.applications_skipped\+\+;\s*summary\.notices\.push\(\{\s*scope: 'bucket_not_imported'/,
    'every bucket skip must be counted and reported as a bucket_not_imported notice');

  const resumeAt = src.indexOf('await syncResumesParallel(', handleAt);
  const dryRunAt = src.indexOf('if (body.dry_run === true) {', handleAt);
  const applyAt = src.lastIndexOf('for (const app of body.applications)');
  assert.ok(resumeAt > 0 && dryRunAt > 0 && applyAt > 0, 'all three anchors must exist');
  assert.ok(filterAt < resumeAt && filterAt < dryRunAt && filterAt < applyAt,
    'the filter must run before the resume pre-flight, the dry-run preview and the apply loop');

  assert.match(src, /will_skip: bucketSkipped\.map\(\(app\) => \(\{ ref: String\(app\.applicationId\), reason: 'bucket_not_imported' \}\)\)/,
    'the dry-run preview must list the bucket skips, so the admin diff matches Apply');
});

// ── Layer A: canonical script copy guards (Wave 4 reform must not regress) ─────

test('#1175 W4/F7: canonical script carries the Nucleo opportunity allowlist + LGPD gate', () => {
  assert.match(scriptSrc, new RegExp(String.raw`NUCLEO_OPPORTUNITY_ALLOWLIST:\s*\[` + NUCLEO_ALLOWLIST.join(String.raw`,\s*`) + String.raw`\]`),
    'the script allowlist default must be exactly the Nucleo opportunities in NUCLEO_ALLOWLIST');
  assert.match(scriptSrc, /excludedOpportunityIds/,
    'excluded opportunities must be recorded in meta (LGPD traceability)');
  assert.match(scriptSrc, /meta\.lgpd\s*=/,
    'the generated JSON header must carry the LGPD minimization note (meta.lgpd)');
});

test('#2827: script downloads only the qualified bucket of 72562', () => {
  // Line comments only: one of this script's line comments carries the text '/*', and
  // maskJsComments' block pass would blank everything from there to the next '*/',
  // the CONFIG block included.
  const src = scriptSrc.replace(/^[ \t]*\/\/[^\n]*/gm, '');
  assert.match(src, /NUCLEO_OPPORTUNITY_BUCKETS:\s*\{\s*72562:\s*\['qualified'\]\s*\}/,
    'the script map must restrict 72562 to the qualified bucket, and nothing else');
  const loopAt = src.indexOf('for (const b of buckets(oppId)) {');
  assert.ok(loopAt > 0, 'the bucket sweep loop must be findable');
  const head = src.slice(src.lastIndexOf('for (const oppId of opportunityIds)', loopAt), src.indexOf('fetchJson(', loopAt));
  assert.match(head, /const onlyBuckets = \(CONFIG\.NUCLEO_OPPORTUNITY_BUCKETS \|\| \{\}\)\[String\(oppId\)\];/,
    'the restriction must be read from the config map for THIS opportunity');
  assert.match(head, /for \(const b of buckets\(oppId\)\) \{\s*if \(onlyBuckets && !onlyBuckets\.includes\(b\.name\)\) \{[\s\S]{0,200}?continue;\s*\}/,
    'a bucket outside the restriction must be skipped before its first fetch');
});

test('#1175 W4/F7: script skips the auto-POST when the ingest secret is a placeholder', () => {
  assert.match(scriptSrc, /ingestSecretUsable/,
    'placeholder-secret guard must exist');
  assert.match(scriptSrc, /!\/\^\\s\*<\.\*>\\s\*\$\/\.test\(CONFIG\.NUCLEO_INGEST_SECRET\)/,
    'placeholder detection must reject <...> values (the Phase A unauthorized root cause)');
});

test('#1175 W4: serviceHistory contract — script emits applicationId+roleName, mapper accepts legacy applicantId', () => {
  // Script side (both Phase A and Phase B push sites go through these shapes)
  assert.match(scriptSrc, /applicationId:\s*a\.applicationId/,
    'history rows must carry applicationId (the worker match key)');
  assert.match(scriptSrc, /roleName:\s*h\.roleTitle\s*\|\|\s*h\.title\s*\|\|\s*null/,
    'history rows must carry roleName (the worker role field)');
  // Worker side: fallback for pre-Wave-4 archived exports
  assert.match(mapperSrc, /h\.applicationId\s*==\s*null\s*&&[\s\S]{0,120}String\(h\.applicantId\)\s*===\s*String\(app\.applicantId\)/,
    'mapper must fall back to applicantId matching when rows lack applicationId');
});

// ── Layer B: DB-aware registry state (skip offline) ────────────────────────────

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#1175 W4: vep_opportunities registry — 62106 inactive (D4), actives within allowlist', { skip: dbGated ? false : skipMsg }, async () => {
  const { createClient } = await import('@supabase/supabase-js');
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  const { data, error } = await sb
    .from('vep_opportunities')
    .select('opportunity_id, is_active');
  assert.ifError(error);
  const rows = data ?? [];

  // D1 (2026-07-08, revised 2026-10-29 in #2827): 72562 may be registered and active.
  // What keeps its submitted and rejected candidates out is the bucket filter guarded in
  // Layer A, not the absence of the row.

  // D4: cycle-1 historical opportunity is registered but inactive (non-importable)
  const hist = rows.find((r) => String(r.opportunity_id) === '62106');
  assert.ok(hist, '62106 must exist as the historical cycle-1 row (D4)');
  assert.equal(hist.is_active, false, '62106 must stay is_active=false');

  // Allowlist coherence: every ACTIVE opportunity is in the allowlist
  const actives = rows.filter((r) => r.is_active).map((r) => String(r.opportunity_id));
  for (const id of actives) {
    assert.ok(NUCLEO_ALLOWLIST.includes(id),
      `active opportunity ${id} is outside the Nucleo allowlist ${NUCLEO_ALLOWLIST.join('/')}`);
  }
});
