/**
 * Contract: #1175 Wave 4 — unknown VEP opportunity is SKIPPED by design across the
 * whole import chain (script -> worker /ingest -> vep_opportunities).
 *
 * Grounded 2026-07-08 (import run 8d9b8128): the 07/07 JSON carried 135 applications,
 * 2 from opportunity 72562 (chapter-board vacancy, NOT the Nucleo's — PM decision D1).
 * The worker skipped exactly those 2 with scope 'opportunity_not_active' because the
 * gate is vep_opportunities.is_active=true (lookup built by getActiveOpportunities).
 *
 * Layers:
 *   (A) offline static guards on the worker source + canonical script copy
 *       (cloudflare-workers/pmi-vep-sync/) — the skip path and the Wave 4 script
 *       reform (allowlist gate, placeholder-secret skip, serviceHistory contract)
 *       must not regress;
 *   (B) DB-aware (skipped without SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY) — the
 *       vep_opportunities registry itself: 72562 absent (D1), 62106 historical
 *       inactive (D4), and every ACTIVE row within the Nucleo allowlist.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const WORKER_DIR = resolve(process.cwd(), 'cloudflare-workers/pmi-vep-sync');
const indexSrc = readFileSync(resolve(WORKER_DIR, 'src/index.ts'), 'utf8');
const mapperSrc = readFileSync(resolve(WORKER_DIR, 'src/script-mapper.ts'), 'utf8');
const dbSrc = readFileSync(resolve(WORKER_DIR, 'src/db.ts'), 'utf8');
const scriptSrc = readFileSync(resolve(WORKER_DIR, 'scripts/extract_pmi_volunteer.js'), 'utf8');

const NUCLEO_ALLOWLIST = ['64966', '64967', '66470'];

// ── Layer A: worker source guards ──────────────────────────────────────────────

test('#1175 W4: /ingest live path skips unknown opportunities with scope opportunity_not_active', () => {
  assert.match(indexSrc, /scope:\s*'opportunity_not_active'/,
    "the skip block must tag errors with scope 'opportunity_not_active'");
  assert.match(indexSrc, /summary\.applications_skipped\+\+/,
    'the skip must count into applications_skipped (surfaced in the import summary)');
  // The lookup that defines "known" is ACTIVE rows only — is_active=false (62106
  // historical) must not resurrect an opportunity into the import path.
  assert.match(dbSrc, /from\('vep_opportunities'\)[\s\S]{0,200}\.eq\('is_active',\s*true\)/,
    'getActiveOpportunities must filter is_active=true');
});

test('#1175 W4: dry-run preview reports the same skip (reason opportunity_not_active)', () => {
  assert.match(indexSrc, /will_skip\.push\(\{\s*ref:[^}]*reason:\s*'opportunity_not_active'/,
    'dry_run path must preview the identical skip so the admin UI diff matches Apply');
});

// ── Layer A: canonical script copy guards (Wave 4 reform must not regress) ─────

test('#1175 W4/F7: canonical script carries the Nucleo opportunity allowlist + LGPD gate', () => {
  assert.match(scriptSrc, /NUCLEO_OPPORTUNITY_ALLOWLIST:\s*\[64966,\s*64967,\s*66470\]/,
    'allowlist default must be the 3 Nucleo opportunities');
  assert.match(scriptSrc, /excludedOpportunityIds/,
    'excluded opportunities must be recorded in meta (LGPD traceability)');
  assert.match(scriptSrc, /meta\.lgpd\s*=/,
    'the generated JSON header must carry the LGPD minimization note (meta.lgpd)');
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

test('#1175 W4: vep_opportunities registry — 72562 absent (D1), 62106 inactive (D4), actives within allowlist', { skip: dbGated ? false : skipMsg }, async () => {
  const { createClient } = await import('@supabase/supabase-js');
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  const { data, error } = await sb
    .from('vep_opportunities')
    .select('opportunity_id, is_active');
  assert.ifError(error);
  const rows = data ?? [];

  // D1: the chapter-board vacancy must never be registered (its candidates are not imported)
  assert.ok(!rows.some((r) => String(r.opportunity_id) === '72562'),
    'opportunity 72562 must NOT exist in vep_opportunities (PM decision D1, 2026-07-08)');

  // D4: cycle-1 historical opportunity is registered but inactive (non-importable)
  const hist = rows.find((r) => String(r.opportunity_id) === '62106');
  assert.ok(hist, '62106 must exist as the historical cycle-1 row (D4)');
  assert.equal(hist.is_active, false, '62106 must stay is_active=false');

  // Allowlist coherence: every ACTIVE opportunity is one of the Nucleo's 3
  const actives = rows.filter((r) => r.is_active).map((r) => String(r.opportunity_id));
  for (const id of actives) {
    assert.ok(NUCLEO_ALLOWLIST.includes(id),
      `active opportunity ${id} is outside the Nucleo allowlist ${NUCLEO_ALLOWLIST.join('/')}`);
  }
});
