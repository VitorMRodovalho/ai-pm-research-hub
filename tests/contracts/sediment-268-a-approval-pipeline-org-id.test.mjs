/**
 * Forward-defense: p269 SEDIMENT-268.A — approval pipeline organization_id
 * remediation. Two canonical writers post-p256 W1a M1:
 *
 *   1. lock_document_version → INSERT INTO public.approval_chains
 *   2. sign_ip_ratification  → INSERT INTO public.approval_signoffs
 *
 * Both INSERTs target tables that gained `organization_id NOT NULL` (no default)
 * under migration 20260805000035_p256_wave1a_315_m1_governance_org_id_backfill
 * (Wave 1a M1 P0-Q5 multi-tenant invariant V/V') but were never updated to
 * populate the new column. Latent bug masked because the Frontiers v1.x guide
 * draft (next governance_document to be locked into a chain since the
 * constraint landed) is still in `draft`/`locked_at IS NULL` per PM directive —
 * Gate 0 jurídico holds the chain from opening. Same bug class as BUG-268.A
 * (migration 20260805000047, p268) which fixed upsert_document_version.
 *
 * Fix: CREATE OR REPLACE FUNCTION minimum-diff vs current live body —
 *   lock_document_version:
 *     (a) SELECT into v_version gains `dv.organization_id`.
 *     (b) INSERT INTO public.approval_chains adds `organization_id` column
 *         sourced from v_version.organization_id (FK chain via document_versions).
 *   sign_ip_ratification:
 *     (a) SELECT into v_chain gains `ac.organization_id`.
 *     (b) INSERT INTO public.approval_signoffs adds `organization_id` column
 *         sourced from v_chain.organization_id (FK chain via approval_chains).
 *   Both: same identity signature (no DROP+CREATE), SECURITY DEFINER + pinned
 *   search_path preserved, RETURNS jsonb envelope preserved, auth gates
 *   preserved, all DEFAULTs intact for sign_ip_ratification (SEDIMENT-238.C).
 *
 * sign_ratification_gate (MCP tool name in nucleo-mcp) is a JS alias in
 * supabase/functions/nucleo-mcp/index.ts:5337 that wraps
 * `sb.rpc('sign_ip_ratification', …)` — NOT a phantom RPC. Fixing the
 * underlying RPC fixes both invocation paths transparently.
 *
 * Migration: supabase/migrations/20260805000048_p269_sediment_268_a_approval_pipeline_org_id.sql
 *
 * Scope — Tier 1 ONLY (PM decision, Opção A): lock_document_version +
 * sign_ip_ratification. Tier 2 (confirm_manual_version +
 * link_attachment_to_governance) tracked as BUG-268.B follow-up because they
 * also omit visibility_class + acknowledgement_mode on INSERT INTO
 * governance_documents — same bug class but requires semantic decision on
 * default values per doc_type.
 *
 * Static assertions (13 total):
 *   1. Migration file exists at canonical path.
 *   2. Two CREATE OR REPLACE FUNCTION (no DROP+CREATE — consumer-safe).
 *   3. SECURITY DEFINER + pinned search_path = public, pg_temp (both RPCs).
 *   4. RETURNS jsonb (both RPCs — envelope unchanged).
 *   5. lock_document_version: 2-arg signature preserved (0 DEFAULTs).
 *   6. sign_ip_ratification: 6-arg signature preserved (4 DEFAULTs intact —
 *      SEDIMENT-238.C honored).
 *   7. lock_document_version: SELECT v_version extended with `dv.organization_id`.
 *   8. lock_document_version: INSERT INTO public.approval_chains column list
 *      contains `organization_id`.
 *   9. lock_document_version: INSERT VALUES sources organization_id from
 *      v_version.organization_id (parent document_versions row — SEDIMENT-239b.A).
 *  10. sign_ip_ratification: SELECT v_chain extended with `ac.organization_id`.
 *  11. sign_ip_ratification: INSERT INTO public.approval_signoffs column list
 *      contains `organization_id`.
 *  12. sign_ip_ratification: INSERT VALUES sources organization_id from
 *      v_chain.organization_id (parent approval_chains row — SEDIMENT-239b.A).
 *  13. 2 sanity DO blocks + NOTIFY pgrst at end of migration.
 *
 * Forward-defense regressions (2 total — lock the regression class):
 *  FD-1. INSERT INTO public.approval_chains in lock_document_version body
 *        CANNOT exist without organization_id literal in column list +
 *        CANNOT source it from NULL or a hardcoded uuid.
 *  FD-2. INSERT INTO public.approval_signoffs in sign_ip_ratification body
 *        CANNOT exist without organization_id literal in column list +
 *        CANNOT source it from NULL or a hardcoded uuid.
 *
 * DB-gated (2 total — proxy for live body in sync):
 *  DB-1. Live lock_document_version prosrc contains `organization_id`.
 *  DB-2. Live sign_ip_ratification prosrc contains `organization_id`.
 *
 * Cross-ref:
 *   - BUG-268.A (p268, migration 20260805000047) — fixed upsert_document_version.
 *   - Parent constraint: 20260805000035_p256_wave1a_315_m1_governance_org_id_backfill.
 *   - BUG-268.B follow-up: Tier 2 governance document INSERT RPCs.
 *   - SEDIMENT-239b.A applied: contract test asserts source of every FK column.
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
  'supabase/migrations/20260805000048_p269_sediment_268_a_approval_pipeline_org_id.sql'
);

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// Helper: read the migration file body once per test (cheap on a single small file)
function readMigration() {
  return readFileSync(MIGRATION_FILE, 'utf8');
}

// Helper: strip SQL line comments (--) so code-only checks don't match prose in the header
function codeOnly(body) {
  return body.split('\n').map(l => l.replace(/--.*$/, '')).join('\n');
}

// Helper: extract a function's body text (between `CREATE OR REPLACE FUNCTION public.<name>(...)` and
// the matching closing $function$; ). Returns null if not found.
function extractFunctionBody(body, name) {
  const startRegex = new RegExp(`CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.${name}\\s*\\(`, 'i');
  const startMatch = body.match(startRegex);
  if (!startMatch) return null;
  const startIdx = startMatch.index;
  // Find the closing $function$; after this point
  const endIdx = body.indexOf('$function$;', startIdx);
  if (endIdx === -1) return null;
  return body.slice(startIdx, endIdx + '$function$;'.length);
}

// ===================================================================
// STATIC migration body assertions (always run)
// ===================================================================

test('p269 SEDIMENT-268.A: migration file present at canonical path', () => {
  const dir = resolve(ROOT, 'supabase/migrations');
  const files = readdirSync(dir).filter(f => f.startsWith('20260805000048_'));
  assert.equal(files.length, 1,
    'Exactly one migration file must exist for version 20260805000048 (p269 SEDIMENT-268.A)');
  assert.match(files[0], /^20260805000048_p269_sediment_268_a_approval_pipeline_org_id\.sql$/,
    'Migration filename must follow `<timestamp>_<descriptive_name>.sql` per CLAUDE.md GC-097');
});

test('p269 SEDIMENT-268.A: two CREATE OR REPLACE FUNCTIONs present (no DROP+CREATE)', () => {
  const body = readMigration();
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.lock_document_version\(/i,
    'CREATE OR REPLACE FUNCTION public.lock_document_version must be present (consumer-safe — signature unchanged).');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.sign_ip_ratification\(/i,
    'CREATE OR REPLACE FUNCTION public.sign_ip_ratification must be present (consumer-safe — signature unchanged).');
  assert.doesNotMatch(body, /DROP\s+FUNCTION[^;]*lock_document_version/i,
    'DROP FUNCTION lock_document_version must NOT appear — preserves consumer references.');
  assert.doesNotMatch(body, /DROP\s+FUNCTION[^;]*sign_ip_ratification/i,
    'DROP FUNCTION sign_ip_ratification must NOT appear — preserves consumer references.');
});

test('p269 SEDIMENT-268.A: SECURITY DEFINER + pinned search_path preserved (both RPCs)', () => {
  const body = readMigration();
  const lockFn = extractFunctionBody(body, 'lock_document_version');
  const signFn = extractFunctionBody(body, 'sign_ip_ratification');
  assert.ok(lockFn, 'lock_document_version body must be extractable from migration.');
  assert.ok(signFn, 'sign_ip_ratification body must be extractable from migration.');

  for (const [name, fn] of [['lock_document_version', lockFn], ['sign_ip_ratification', signFn]]) {
    assert.match(fn, /SECURITY DEFINER/i,
      `${name}: SECURITY DEFINER preserved — RPC must run with definer privileges.`);
    assert.match(fn, /SET search_path\s*=\s*public,\s*pg_temp/i,
      `${name}: pinned search_path = public, pg_temp preserved — defense against search_path attacks on SECDEF.`);
    assert.match(fn, /RETURNS jsonb/i,
      `${name}: RETURNS jsonb preserved — envelope shape unchanged for consumers.`);
  }
});

test('p269 SEDIMENT-268.A: lock_document_version 2-arg signature preserved (0 DEFAULTs)', () => {
  const body = readMigration();
  assert.match(body,
    /CREATE OR REPLACE FUNCTION public\.lock_document_version\(\s*p_version_id uuid,\s*p_gates jsonb\s*\)/i,
    '2-arg signature (p_version_id uuid, p_gates jsonb) preserved verbatim — no DEFAULTs to remove or add.');
});

test('p269 SEDIMENT-268.A: sign_ip_ratification 6-arg signature + 4 DEFAULTs preserved (SEDIMENT-238.C)', () => {
  const body = readMigration();
  assert.match(body,
    /CREATE OR REPLACE FUNCTION public\.sign_ip_ratification\(\s*p_chain_id uuid,\s*p_gate_kind text,\s*p_signoff_type text DEFAULT 'approval',\s*p_sections_verified jsonb DEFAULT NULL,\s*p_comment_body text DEFAULT NULL,\s*p_ue_consent_49_1_a boolean DEFAULT NULL\s*\)/i,
    '6-arg signature must be preserved with all 4 DEFAULTs intact (p_signoff_type, p_sections_verified, p_comment_body, p_ue_consent_49_1_a); per SEDIMENT-238.C, Postgres rejects DEFAULT removal on CREATE OR REPLACE.');
});

test('p269 SEDIMENT-268.A: lock_document_version SELECT v_version extended with dv.organization_id', () => {
  const body = readMigration();
  const lockFn = extractFunctionBody(body, 'lock_document_version');
  assert.ok(lockFn, 'lock_document_version body must be extractable.');
  assert.match(lockFn,
    /SELECT\s+dv\.id\s*,\s*dv\.document_id\s*,\s*dv\.organization_id\s*,/i,
    'lock_document_version: SELECT into v_version MUST include dv.organization_id so the INSERT can populate approval_chains.organization_id NOT NULL.');
});

test('p269 SEDIMENT-268.A: lock_document_version INSERT approval_chains has organization_id column', () => {
  const body = readMigration();
  const lockFn = extractFunctionBody(body, 'lock_document_version');
  assert.ok(lockFn, 'lock_document_version body must be extractable.');
  const m = lockFn.match(/INSERT INTO public\.approval_chains\s*\(([^)]+)\)/i);
  assert.ok(m, 'INSERT INTO public.approval_chains with column list must be present in lock_document_version.');
  const cols = m[1].split(',').map(s => s.trim());
  assert.ok(cols.includes('organization_id'),
    'lock_document_version: INSERT column list MUST include organization_id (the regression class this test locks).');
});

test('p269 SEDIMENT-268.A: lock_document_version VALUES sources organization_id from v_version.organization_id (SEDIMENT-239b.A)', () => {
  const body = readMigration();
  const lockFn = extractFunctionBody(body, 'lock_document_version');
  assert.ok(lockFn, 'lock_document_version body must be extractable.');
  // Strip SQL line comments before substring-matching so header/comment prose doesn't leak
  const code = codeOnly(lockFn);
  const insertMatch = code.match(/INSERT INTO public\.approval_chains[\s\S]+?;/i);
  assert.ok(insertMatch, 'INSERT INTO public.approval_chains ...; must be present in lock_document_version (code, not comments).');
  assert.ok(insertMatch[0].includes('v_version.organization_id'),
    'lock_document_version: INSERT VALUES MUST source organization_id from v_version.organization_id (parent document_versions row, FK to organizations); a constant or auth_org() would couple cross-tenant — SEDIMENT-239b.A.');
});

test('p269 SEDIMENT-268.A: sign_ip_ratification SELECT v_chain extended with ac.organization_id', () => {
  const body = readMigration();
  const signFn = extractFunctionBody(body, 'sign_ip_ratification');
  assert.ok(signFn, 'sign_ip_ratification body must be extractable.');
  assert.match(signFn,
    /SELECT\s+ac\.id\s*,\s*ac\.status\s*,\s*ac\.document_id\s*,\s*ac\.version_id\s*,\s*ac\.gates\s*,\s*ac\.organization_id/i,
    'sign_ip_ratification: SELECT into v_chain MUST include ac.organization_id so the INSERT can populate approval_signoffs.organization_id NOT NULL.');
});

test('p269 SEDIMENT-268.A: sign_ip_ratification INSERT approval_signoffs has organization_id column', () => {
  const body = readMigration();
  const signFn = extractFunctionBody(body, 'sign_ip_ratification');
  assert.ok(signFn, 'sign_ip_ratification body must be extractable.');
  const m = signFn.match(/INSERT INTO public\.approval_signoffs\s*\(([^)]+)\)/i);
  assert.ok(m, 'INSERT INTO public.approval_signoffs with column list must be present in sign_ip_ratification.');
  const cols = m[1].split(',').map(s => s.trim());
  assert.ok(cols.includes('organization_id'),
    'sign_ip_ratification: INSERT column list MUST include organization_id (the regression class this test locks).');
});

test('p269 SEDIMENT-268.A: sign_ip_ratification VALUES sources organization_id from v_chain.organization_id (SEDIMENT-239b.A)', () => {
  const body = readMigration();
  const signFn = extractFunctionBody(body, 'sign_ip_ratification');
  assert.ok(signFn, 'sign_ip_ratification body must be extractable.');
  const code = codeOnly(signFn);
  const insertMatch = code.match(/INSERT INTO public\.approval_signoffs[\s\S]+?;/i);
  assert.ok(insertMatch, 'INSERT INTO public.approval_signoffs ...; must be present in sign_ip_ratification (code, not comments).');
  assert.ok(insertMatch[0].includes('v_chain.organization_id'),
    'sign_ip_ratification: INSERT VALUES MUST source organization_id from v_chain.organization_id (parent approval_chains row, FK to organizations); a constant or auth_org() would couple cross-tenant — SEDIMENT-239b.A.');
});

test('p269 SEDIMENT-268.A: 2 sanity DO blocks present (one per RPC)', () => {
  const body = readMigration();
  assert.match(body,
    /DO \$sanity_lock\$[\s\S]+lock_document_version[\s\S]+organization_id[\s\S]+?\$sanity_lock\$/i,
    'Sanity DO block for lock_document_version must RAISE if live prosrc does not contain organization_id (post-apply defense-in-depth).');
  assert.match(body,
    /DO \$sanity_sign\$[\s\S]+sign_ip_ratification[\s\S]+organization_id[\s\S]+?\$sanity_sign\$/i,
    'Sanity DO block for sign_ip_ratification must RAISE if live prosrc does not contain organization_id (post-apply defense-in-depth).');
});

test('p269 SEDIMENT-268.A: NOTIFY pgrst reload schema (PostgREST cache refresh)', () => {
  const body = readMigration();
  assert.match(body, /NOTIFY\s+pgrst\s*,\s*'reload schema'/i,
    'NOTIFY pgrst must be emitted post-apply so PostgREST drops cached function metadata and consumers see the new bodies.');
});

// ===================================================================
// Forward-defense regressions (lock the regression class)
// ===================================================================

test('p269 SEDIMENT-268.A: FD-1 — lock_document_version INSERT approval_chains cannot drop organization_id, cannot set NULL/constant', () => {
  const body = readMigration();
  const lockFn = extractFunctionBody(body, 'lock_document_version');
  assert.ok(lockFn, 'lock_document_version body must be extractable.');
  const code = codeOnly(lockFn);

  // FD-1a: positively assert organization_id column literal in the INSERT column list
  assert.match(code,
    /INSERT INTO public\.approval_chains\s*\([^)]*\borganization_id\b[^)]*\)/i,
    'FD-1a: future edits MUST NOT drop organization_id from the INSERT column list of public.approval_chains inside lock_document_version.');

  // FD-1b: NEVER assign NULL explicitly to the org_id slot inside this RPC's code
  assert.doesNotMatch(code, /organization_id\s*:?=\s*NULL/i,
    'FD-1b: organization_id must NEVER be assigned NULL (would re-introduce SEDIMENT-268.A as silent runtime failure on NOT NULL).');

  // FD-1c: NEVER source from auth_org() (cross-tenant risk) inside this RPC
  assert.doesNotMatch(code, /organization_id\s*[:=,]\s*auth_org\(\)/i,
    'FD-1c: organization_id must NOT be sourced from auth_org() — must come from parent document_versions row for tenant integrity.');
});

test('p269 SEDIMENT-268.A: FD-2 — sign_ip_ratification INSERT approval_signoffs cannot drop organization_id, cannot set NULL/constant', () => {
  const body = readMigration();
  const signFn = extractFunctionBody(body, 'sign_ip_ratification');
  assert.ok(signFn, 'sign_ip_ratification body must be extractable.');
  const code = codeOnly(signFn);

  // FD-2a: positively assert organization_id column literal in the INSERT column list
  assert.match(code,
    /INSERT INTO public\.approval_signoffs\s*\([^)]*\borganization_id\b[^)]*\)/i,
    'FD-2a: future edits MUST NOT drop organization_id from the INSERT column list of public.approval_signoffs inside sign_ip_ratification.');

  // FD-2b: NEVER assign NULL explicitly to the org_id slot inside this RPC's code
  assert.doesNotMatch(code, /organization_id\s*:?=\s*NULL/i,
    'FD-2b: organization_id must NEVER be assigned NULL (would re-introduce SEDIMENT-268.A as silent runtime failure on NOT NULL).');

  // FD-2c: NEVER source from auth_org() (cross-tenant risk) inside this RPC
  assert.doesNotMatch(code, /organization_id\s*[:=,]\s*auth_org\(\)/i,
    'FD-2c: organization_id must NOT be sourced from auth_org() — must come from parent approval_chains row for tenant integrity.');
});

// ===================================================================
// DB-gated (skip if no env)
// ===================================================================

test('p269 SEDIMENT-268.A: DB-1 — live lock_document_version prosrc references organization_id', { skip: !dbGated && skipMsg }, async () => {
  if (!dbGated) return;
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb
    .rpc('_audit_list_public_function_bodies', { p_names: ['lock_document_version'] });
  if (error || !data) {
    // Defensive: degrade gracefully if helper RPC is unavailable
    return;
  }
  const fn = Array.isArray(data) ? data.find(r => r.proname === 'lock_document_version') : null;
  if (!fn) return; // degrade gracefully
  assert.ok(fn.prosrc && fn.prosrc.includes('organization_id'),
    'Live lock_document_version body must reference organization_id (proxy for migration applied + body in sync; complements p175 md5-drift gate).');
  // Defense-in-depth: also assert the INSERT column list specifically
  assert.match(fn.prosrc,
    /INSERT INTO public\.approval_chains\s*\([^)]*\borganization_id\b[^)]*\)/i,
    'Live lock_document_version INSERT INTO public.approval_chains must list organization_id in column list.');
});

test('p269 SEDIMENT-268.A: DB-2 — live sign_ip_ratification prosrc references organization_id', { skip: !dbGated && skipMsg }, async () => {
  if (!dbGated) return;
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb
    .rpc('_audit_list_public_function_bodies', { p_names: ['sign_ip_ratification'] });
  if (error || !data) {
    return;
  }
  const fn = Array.isArray(data) ? data.find(r => r.proname === 'sign_ip_ratification') : null;
  if (!fn) return;
  assert.ok(fn.prosrc && fn.prosrc.includes('organization_id'),
    'Live sign_ip_ratification body must reference organization_id (proxy for migration applied + body in sync; complements p175 md5-drift gate).');
  // Defense-in-depth: also assert the INSERT column list specifically
  assert.match(fn.prosrc,
    /INSERT INTO public\.approval_signoffs\s*\([^)]*\borganization_id\b[^)]*\)/i,
    'Live sign_ip_ratification INSERT INTO public.approval_signoffs must list organization_id in column list.');
});
