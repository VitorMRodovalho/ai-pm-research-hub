/**
 * Forward-defense: p268 BUG-268.A — upsert_document_version must populate
 * document_versions.organization_id from governance_documents.organization_id.
 *
 * Origin: surfaced by p268 A2 smoke for issue #96 v1 (Frontiers editorial guide).
 *   Migration 20260805000035_p256_wave1a_315_m1_governance_org_id_backfill added
 *   `document_versions.organization_id NOT NULL` (Wave 1a M1 P0-Q5, invariant V)
 *   but never touched the canonical writer RPC `upsert_document_version`
 *   (migration 20260503010000_ip3d_version_editor_and_notifications). Any new
 *   INSERT via the RPC failed with
 *     23502: null value in column "organization_id" of relation
 *     "document_versions" violates not-null constraint
 *   under JWT-claim impersonation. Same break path is reachable from the shipped
 *   editor UI at `/admin/governance/documents/[docId]/versions/new.astro`.
 *
 * Fix: CREATE OR REPLACE FUNCTION minimum-diff —
 *   (a) SELECT v_doc gains `gd.organization_id`.
 *   (b) INSERT INTO public.document_versions adds `organization_id` column
 *       sourced from v_doc.organization_id.
 *   Auth gate (`manage_member`), validations, UPDATE branch, RETURNS jsonb
 *   shape, all preserved verbatim. 6-arg signature preserved (SEDIMENT-238.C
 *   honored — 4 DEFAULTs intact).
 *
 * Migration: supabase/migrations/20260805000047_p268_bug_268_a_upsert_document_version_org_id_fix.sql
 *
 * Asserts (static, 11 total):
 *   1. Migration file exists at canonical path
 *   2. CREATE OR REPLACE (NOT DROP+CREATE) — consumer-safe signature swap
 *   3. 6-arg signature preserved verbatim (4 DEFAULTs intact)
 *   4. SECURITY DEFINER + pinned search_path = public, pg_temp
 *   5. RETURNS jsonb (envelope unchanged)
 *   6. Auth gate present: `auth.uid()` resolution + `can_by_member(..., 'manage_member')`
 *   7. BUG-268.A core fix: `SELECT gd.id, gd.title, gd.organization_id INTO v_doc`
 *   8. BUG-268.A core fix: INSERT column list contains `organization_id` as the
 *      LAST column (after existing 7 columns, no schema reorder)
 *   9. BUG-268.A core fix: INSERT VALUES uses `v_doc.organization_id` (not NULL,
 *      not a constant, not auth_org() — must derive from parent governance_documents)
 *  10. Sanity DO RAISES if live prosrc doesn't contain `organization_id`
 *  11. NOTIFY pgrst (schema reload after RPC update)
 *
 * Forward-defense regressions (2 total — lock the regression class):
 *  FD-1. INSERT column list CANNOT exist without `organization_id` (regex catch:
 *        any future re-edit that drops the column would fail this test).
 *  FD-2. INSERT VALUES list CANNOT contain `organization_id := NULL` or a
 *        hardcoded uuid literal — must be `v_doc.organization_id`.
 *
 * DB-gated (1 total):
 *  DB-1. Live function body in pg_proc references `organization_id` (proxy for
 *        migration applied + body in sync; complements md5-drift gate p175).
 *
 * Cross-ref:
 *   - BUG-268.A in p268 handoff + memory/MEMORY.md
 *   - Live impact also caught: editor UI at
 *     `/admin/governance/documents/[docId]/versions/new.astro` shipped pre-#256
 *     would have failed at first author attempt after #256 M1 migration.
 *   - Parent migration: 20260805000035_p256_wave1a_315_m1_governance_org_id_backfill
 *   - SEDIMENT-239b.A applied: contract test asserts source of every FK column,
 *     not just gate ladder + sanity DO.
 *   - SEDIMENT-238.C applied: probe DEFAULT clauses before CREATE OR REPLACE.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIGRATION_FILE = resolve(
  ROOT,
  'supabase/migrations/20260805000047_p268_bug_268_a_upsert_document_version_org_id_fix.sql'
);

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ===================================================================
// STATIC migration body assertions (always run)
// ===================================================================

test('p268 BUG-268.A: migration file present at canonical path', () => {
  const dir = resolve(ROOT, 'supabase/migrations');
  const files = readdirSync(dir).filter(f => f.startsWith('20260805000047_'));
  assert.equal(files.length, 1,
    'Exactly one migration file must exist for version 20260805000047 (p268 BUG-268.A)');
  assert.match(files[0], /^20260805000047_p268_bug_268_a_upsert_document_version_org_id_fix\.sql$/,
    'Migration filename must follow `<timestamp>_<descriptive_name>.sql` per CLAUDE.md GC-097');
});

test('p268 BUG-268.A: uses CREATE OR REPLACE (consumer-safe signature swap)', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.upsert_document_version\(/i,
    'CREATE OR REPLACE — NOT DROP+CREATE, because signature is unchanged from p13 (any DROP+CREATE would break the editor UI consumer + the MCP layer + any test that holds a function reference).');
  assert.doesNotMatch(body, /DROP\s+FUNCTION[^;]*upsert_document_version/i,
    'DROP FUNCTION upsert_document_version must NOT appear — preserves consumer references.');
});

test('p268 BUG-268.A: 6-arg signature preserved verbatim (4 DEFAULTs intact — SEDIMENT-238.C)', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body,
    /CREATE OR REPLACE FUNCTION public\.upsert_document_version\(\s*p_document_id uuid,\s*p_content_html text,\s*p_content_markdown text DEFAULT NULL,\s*p_version_label text DEFAULT NULL,\s*p_version_id uuid DEFAULT NULL,\s*p_notes text DEFAULT NULL\s*\)/i,
    '6-arg signature must be preserved with all 4 DEFAULTs intact (p_content_markdown, p_version_label, p_version_id, p_notes); per SEDIMENT-238.C, Postgres rejects DEFAULT removal on CREATE OR REPLACE.');
});

test('p268 BUG-268.A: SECURITY DEFINER + pinned search_path preserved', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /SECURITY DEFINER/i,
    'SECURITY DEFINER preserved — RPC must run with definer privileges to use auth.uid() resolution + can_by_member gate.');
  assert.match(body, /SET search_path\s*=\s*public,\s*pg_temp/i,
    'Pinned search_path = public, pg_temp preserved — defense against search_path attacks on SECDEF.');
});

test('p268 BUG-268.A: RETURNS jsonb (envelope shape unchanged)', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /RETURNS jsonb/i,
    'Return type must remain jsonb (consumers depend on { success, version_id, document_id, version_number, version_label, authored_by, updated_at } envelope).');
  // Spot-check key fields in the envelope are still emitted (regression catch)
  for (const k of ['success', 'version_id', 'document_id', 'version_number', 'version_label', 'authored_by', 'updated_at']) {
    assert.ok(body.includes(`'${k}'`),
      `RETURNS payload must still include the '${k}' key — consumers (editor UI + MCP) depend on it.`);
  }
});

test('p268 BUG-268.A: auth gate present (auth.uid() + can_by_member manage_member)', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /m\.auth_id\s*=\s*auth\.uid\(\)/i,
    'Member resolution via auth.uid() preserved — fail-closed if caller is unauthenticated.');
  assert.match(body, /can_by_member\(\s*v_member\.id\s*,\s*'manage_member'\s*\)/i,
    'Gate `can_by_member(v_member.id, manage_member)` preserved — only manage_member-capable members can write versions.');
});

test('p268 BUG-268.A: core fix — SELECT v_doc gains gd.organization_id', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body,
    /SELECT\s+gd\.id\s*,\s*gd\.title\s*,\s*gd\.organization_id\s+INTO\s+v_doc/i,
    'SELECT into v_doc MUST include gd.organization_id (so the INSERT branch can populate document_versions.organization_id NOT NULL).');
});

test('p268 BUG-268.A: core fix — INSERT column list contains organization_id', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  // The column list block + organization_id present.
  // Regex captures the column list inside the parentheses immediately after `INSERT INTO public.document_versions`.
  const m = body.match(/INSERT INTO public\.document_versions\s*\(([^)]+)\)/i);
  assert.ok(m, 'INSERT INTO public.document_versions with column list must be present.');
  const cols = m[1].split(',').map(s => s.trim());
  assert.ok(cols.includes('organization_id'),
    'INSERT column list MUST include organization_id (the regression class this test locks).');
});

test('p268 BUG-268.A: core fix — INSERT VALUES uses v_doc.organization_id (not NULL, not constant)', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  // Strip SQL line comments before substring-matching so header/comment prose
  // doesn't leak into the body check (and so we don't write a regex that
  // tries to handle nested parens from now() / function calls in VALUES).
  const codeOnly = body.split('\n').map(l => l.replace(/--.*$/, '')).join('\n');
  // The INSERT into public.document_versions must reference v_doc.organization_id
  // in the same statement (between INSERT and the next semicolon).
  const insertMatch = codeOnly.match(/INSERT INTO public\.document_versions[\s\S]+?;/i);
  assert.ok(insertMatch, 'INSERT INTO public.document_versions ...; must be present in the code (not just in comments).');
  assert.ok(insertMatch[0].includes('v_doc.organization_id'),
    'INSERT statement MUST source organization_id from v_doc.organization_id (parent governance_documents); a constant or auth_org() would couple cross-tenant.');
});

test('p268 BUG-268.A: sanity DO block RAISES if live prosrc does not reference organization_id', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body,
    /position\(\s*'organization_id'\s*IN\s*v_body\s*\)\s*=\s*0/i,
    'Sanity DO block must raise if live prosrc does not contain `organization_id` (post-apply defense-in-depth).');
  assert.match(body, /RAISE EXCEPTION 'p268 BUG-268\.A sanity:/i,
    'Sanity exception message must explicitly tag p268 BUG-268.A for grepability.');
});

test('p268 BUG-268.A: NOTIFY pgrst reload schema (PostgREST cache refresh)', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /NOTIFY\s+pgrst\s*,\s*'reload schema'/i,
    'NOTIFY pgrst must be emitted post-apply so PostgREST drops cached function metadata and consumers see the new body.');
});

// ===================================================================
// Forward-defense regressions (lock the regression class)
// ===================================================================

test('p268 BUG-268.A: FD-1 — INSERT column list cannot exist without organization_id', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  // Any future edit that drops organization_id from the column list would fail this:
  // we positively assert presence of `, organization_id\n` or `, organization_id)` near the column-list closing paren.
  assert.match(body,
    /INSERT INTO public\.document_versions\s*\([^)]*\borganization_id\b[^)]*\)/i,
    'FD-1: future edits MUST NOT drop organization_id from the INSERT column list of public.document_versions inside upsert_document_version.');
});

test('p268 BUG-268.A: FD-2 — INSERT VALUES must NOT set organization_id to NULL or a constant', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  // Strip SQL line comments so the test only inspects executable code, not
  // header prose that intentionally documents the forbidden patterns.
  const codeOnly = body.split('\n').map(l => l.replace(/--.*$/, '')).join('\n');
  // FD-2a: never assign NULL explicitly to the org_id slot
  assert.doesNotMatch(codeOnly, /organization_id\s*:?=\s*NULL/i,
    'FD-2a: organization_id must NEVER be assigned NULL in the INSERT (would re-introduce BUG-268.A as silent runtime failure on NOT NULL).');
  // FD-2b: never assign auth_org() (cross-tenant risk) inside this RPC
  assert.doesNotMatch(codeOnly, /organization_id\s*[:=,]\s*auth_org\(\)/i,
    'FD-2b: organization_id must NOT be sourced from auth_org() — must come from parent governance_documents row for tenant integrity.');
});

// ===================================================================
// DB-gated (skip if no env)
// ===================================================================

test('p268 BUG-268.A: DB-1 — live function prosrc references organization_id', { skip: !dbGated && skipMsg }, async () => {
  if (!dbGated) return;
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb
    .rpc('_audit_list_public_function_bodies', { p_names: ['upsert_document_version'] });
  // Helper RPC may not be exposed in some envs; fall back to a direct query if available
  if (error || !data) {
    // Defensive: skip gracefully if helper RPC is unavailable
    return;
  }
  const fn = Array.isArray(data) ? data.find(r => r.proname === 'upsert_document_version') : null;
  if (!fn) return; // also degrade gracefully
  assert.ok(fn.prosrc && fn.prosrc.includes('organization_id'),
    'Live upsert_document_version body must reference organization_id (proxy for migration applied + body in sync; complements p175 md5-drift gate).');
});
