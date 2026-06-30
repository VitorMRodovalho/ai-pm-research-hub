// tests/contracts/571-pr1-camada5-foundations.test.mjs
//
// #973 (PR-1 of #571) — Camada 5 Material-change backbone: FOUNDATIONS.
// Guards the two cross-cutting primitives: change_class (Material/Editorial)
// + the Brazilian business-day calendar (br_holidays / add_business_days).
//
// Two layers:
//   (A) Static — parses the migration file; always runs (no DB). Catches a
//       copy-paste regression that the file-scoped sediment-268-a guard would
//       miss (it only reads the p269 migration, not this new file).
//   (B) DB-aware — calls the live RPCs/tables; SKIPPED without
//       SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (CI provides them).
//
// SPEC: docs/specs/SPEC_571_CAMADA5_MATERIAL_CHANGE.md §5 PR-1 + §9. ADR-0113.

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIGRATION_PATH = join(
  __dirname,
  '../../supabase/migrations/20260805000301_571_pr1_camada5_change_class_and_business_days.sql',
);

// ─────────────────────────────────────────────────────────────────────────
// (A) Static migration-file guards — always run
// ─────────────────────────────────────────────────────────────────────────
test('PR-1 migration: change_class column + CHECK (editorial|material)', () => {
  const sql = readFileSync(MIGRATION_PATH, 'utf8');
  assert.match(
    sql,
    /ADD COLUMN IF NOT EXISTS change_class text\s+CHECK \(change_class IN \('editorial','material'\)\)/,
    'change_class column with the editorial|material CHECK must be present',
  );
  for (const col of ['summary_pt', 'summary_en', 'summary_es']) {
    assert.match(sql, new RegExp(`ADD COLUMN IF NOT EXISTS ${col} text`), `${col} aviso-30d column missing`);
  }
});

test('PR-1 migration: add_business_days is STABLE, never IMMUTABLE (§9.2)', () => {
  const sql = readFileSync(MIGRATION_PATH, 'utf8');
  const fn = sql.match(/CREATE OR REPLACE FUNCTION public\.add_business_days[\s\S]*?\$function\$;/);
  assert.ok(fn, 'add_business_days definition must exist');
  assert.match(fn[0], /\bSTABLE\b/, 'add_business_days must be STABLE (reads br_holidays)');
  assert.doesNotMatch(fn[0], /\bIMMUTABLE\b/, 'add_business_days must NOT be IMMUTABLE (would allow GENERATED/DEFAULT misuse)');
  assert.match(fn[0], /SET search_path TO 'public', 'pg_temp'/, 'add_business_days must pin search_path');
});

test('PR-1 migration: lock_document_version DROP(2-arg)+CREATE(3-arg DEFAULT NULL)', () => {
  const sql = readFileSync(MIGRATION_PATH, 'utf8');
  assert.match(sql, /DROP FUNCTION IF EXISTS public\.lock_document_version\(uuid, jsonb\);/, 'must DROP the old 2-arg signature');
  assert.match(
    sql,
    /CREATE OR REPLACE FUNCTION public\.lock_document_version\(p_version_id uuid, p_gates jsonb, p_change_class text DEFAULT NULL\)/,
    'must CREATE the 3-arg signature with p_change_class DEFAULT NULL (backward-compatible)',
  );
});

test('PR-1 migration: immutability trigger freezes change_class once locked (§9.2)', () => {
  const sql = readFileSync(MIGRATION_PATH, 'utf8');
  assert.match(
    sql,
    /NEW\.change_class IS DISTINCT FROM OLD\.change_class/,
    'trg_document_version_immutable must block change_class mutation on locked rows',
  );
});

test('PR-1 migration: map_cr_type_to_change_class mapping + search_path', () => {
  const sql = readFileSync(MIGRATION_PATH, 'utf8');
  const fn = sql.match(/CREATE OR REPLACE FUNCTION public\.map_cr_type_to_change_class[\s\S]*?\$function\$;/);
  assert.ok(fn, 'map_cr_type_to_change_class must exist');
  assert.match(fn[0], /WHEN 'editorial'\s+THEN 'editorial'/);
  assert.match(fn[0], /WHEN 'operational' THEN 'material'/);
  assert.match(fn[0], /WHEN 'structural'\s+THEN 'material'/);
  assert.match(fn[0], /WHEN 'emergency'\s+THEN 'material'/);
  assert.match(fn[0], /SET search_path TO 'public', 'pg_temp'/, 'helper must pin search_path (codebase convention)');
});

test('PR-1 migration: br_holidays RLS enabled + NOTIFY pgrst at end', () => {
  const sql = readFileSync(MIGRATION_PATH, 'utf8');
  assert.match(sql, /ALTER TABLE public\.br_holidays ENABLE ROW LEVEL SECURITY/, 'br_holidays must enable RLS (GC-162)');
  assert.match(sql, /NOTIFY pgrst, 'reload schema'/, 'must reload PostgREST schema cache');
});

// ─────────────────────────────────────────────────────────────────────────
// (B) DB-aware guards — require live DB
// ─────────────────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

async function rpc(name, body) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`rpc ${name} failed: HTTP ${res.status} — ${await res.text()}`);
  return res.json();
}

async function select(path) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` },
  });
  if (!res.ok) throw new Error(`select ${path} failed: HTTP ${res.status} — ${await res.text()}`);
  return res.json();
}

// noon BRT inputs → UTC date == BRT calendar date, so toISOString().slice(0,10) is the BRT day.
const goDate = (iso) => new Date(iso).toISOString().slice(0, 10);

test('add_business_days skips Tiradentes (Mon Apr 20 +1 → Wed Apr 22)', { skip: !canRun && skipMsg }, async () => {
  const out = await rpc('add_business_days', { p_start: '2026-04-20T12:00:00-03:00', p_days: 1 });
  assert.equal(goDate(out), '2026-04-22', 'must skip Tiradentes (Tue Apr 21)');
});

test('add_business_days skips Carnaval Mon+Tue (Fri Feb 13 +1 → Wed Feb 18)', { skip: !canRun && skipMsg }, async () => {
  const out = await rpc('add_business_days', { p_start: '2026-02-13T12:00:00-03:00', p_days: 1 });
  assert.equal(goDate(out), '2026-02-18', 'must skip weekend + Carnaval segunda (Feb 16) + terça (Feb 17)');
});

test('business_days_between(Mon Apr 20, Fri Apr 24) = 3 (Tiradentes excluded)', { skip: !canRun && skipMsg }, async () => {
  const n = await rpc('business_days_between', { p_from: '2026-04-20T12:00:00-03:00', p_to: '2026-04-24T12:00:00-03:00' });
  assert.equal(n, 3, 'Apr 22/23/24 are business days; Apr 21 (Tiradentes) excluded');
});

test('map_cr_type_to_change_class: editorial→editorial, others→material, NULL→null', { skip: !canRun && skipMsg }, async () => {
  assert.equal(await rpc('map_cr_type_to_change_class', { p_cr_type: 'editorial' }), 'editorial');
  assert.equal(await rpc('map_cr_type_to_change_class', { p_cr_type: 'operational' }), 'material');
  assert.equal(await rpc('map_cr_type_to_change_class', { p_cr_type: 'structural' }), 'material');
  assert.equal(await rpc('map_cr_type_to_change_class', { p_cr_type: 'emergency' }), 'material');
  assert.equal(await rpc('map_cr_type_to_change_class', { p_cr_type: null }), null);
});

test('br_holidays seeded: 60 national + 24 GO = 84, incl Tiradentes 2026', { skip: !canRun && skipMsg }, async () => {
  const rows = await select('br_holidays?select=scope,holiday_date');
  assert.equal(rows.length, 84, 'expected 84 seeded holidays (2025–2030)');
  const national = rows.filter((r) => r.scope === 'national').length;
  const go = rows.filter((r) => r.scope === 'GO').length;
  assert.equal(national, 60, 'expected 60 national rows');
  assert.equal(go, 24, 'expected 24 GO rows');
  assert.ok(rows.some((r) => r.holiday_date === '2026-04-21'), 'Tiradentes 2026-04-21 must be seeded');
});

test('gd.version reconciliation: policy no longer a stale draft marker', { skip: !canRun && skipMsg }, async () => {
  const rows = await select('governance_documents?doc_type=eq.policy&select=version');
  assert.ok(rows.length >= 1, 'policy governance_document must exist');
  for (const r of rows) {
    assert.doesNotMatch(r.version || '', /draft/i, `policy gd.version must not be a stale draft marker (got "${r.version}")`);
  }
});
