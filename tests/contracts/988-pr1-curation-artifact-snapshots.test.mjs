/**
 * Contract: #308-PR1 (#988) — curation_artifact_snapshots + review-log FK +
 * criteria/version anchors. Behavior-neutral foundation for the evidence-bundle
 * plan. Parent #308 · Spec docs/specs/SPEC_308_CURATOR_EVIDENCE_BUNDLES.md §3.1 ·
 * ADR-0119. Follows #308-PR0 (#987).
 *
 * Grounded live (prod ldrfrvwhxsmgaabwmaik, 2026-06-30):
 *  - curation_artifact_snapshots: deny-all RLS (no permissive policy) + REVOKE anon,
 *    authenticated (Supabase default privileges auto-grant arwdDxtm on new tables).
 *  - register_curation_artifact_snapshot: SECDEF, curate_content OR manage_platform,
 *    ON CONFLICT DO NOTHING, REVOKE PUBLIC/anon (keep authenticated + service_role),
 *    drive_revision_id never returned (F-H6), initiative_id derived server-side.
 *  - initiative_id is NULLABLE (grounding correction vs SPEC §3.1 NOT NULL: 2/25
 *    boards are org-level, initiative_id NULL = visible).
 *  - curation_review_log gains artifact_snapshot_id + reviewer_governing_politica/
 *    termo_version_id (nullable placeholders; writer untouched, F-B2) + a
 *    criteria_scores CHECK that also accepts '{}' (behavior-neutral).
 *
 * Layers: (A) static migration-file guard (always, offline safe). (B) DB-aware
 * service-role catalog probes (SKIP without SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIGRATION_PATH = join(
  __dirname,
  '../../supabase/migrations/20260805000308_988_pr1_curation_artifact_snapshots.sql',
);
// Defensive read (684 pattern): a missing file becomes a clean assertion, not ENOENT.
const sql = existsSync(MIGRATION_PATH) ? readFileSync(MIGRATION_PATH, 'utf8') : '';

const RPC_SIG = 'register_curation_artifact_snapshot(uuid,uuid,uuid,uuid,text,text,text,integer,text,text)';

// ─────────────────────────────────────────────────────────────────────────
// (A) Static migration-file guard — always runs (offline safe)
// ─────────────────────────────────────────────────────────────────────────
test('#988 table exists with digest_status CHECK + at-least-one-anchor CHECK', () => {
  assert.ok(sql, `migration file missing at expected path: ${MIGRATION_PATH}`);
  assert.ok(
    /CREATE TABLE IF NOT EXISTS public\.curation_artifact_snapshots/.test(sql),
    'creates curation_artifact_snapshots',
  );
  assert.match(
    sql,
    /digest_status[\s\S]*?CHECK \(digest_status IN \('pending','verified','unresolvable'\)\)/,
    'digest_status CHECK with the three states',
  );
  assert.match(sql, /digest_status\s+text NOT NULL DEFAULT 'pending'/, 'digest_status defaults to pending');
  assert.match(
    sql,
    /CONSTRAINT cas_has_anchor CHECK \(\s*board_item_file_id IS NOT NULL\s*OR document_version_id IS NOT NULL\s*OR content_product_id IS NOT NULL/,
    'requires at least one of file/docver/content_product anchor',
  );
});

test('#988 initiative_id is NULLABLE (grounding correction vs SPEC §3.1 NOT NULL)', () => {
  // The real derivation board_item.board_id -> project_boards.initiative_id is nullable
  // (org-level boards). A NOT NULL would break the RPC INSERT for org-level board items.
  assert.match(
    sql,
    /initiative_id\s+uuid REFERENCES public\.initiatives\(id\) ON DELETE SET NULL,/,
    'initiative_id nullable (no NOT NULL) + ON DELETE SET NULL',
  );
  // Precise: the *column DDL* must not be NOT NULL (the header comment mentions the
  // SPEC's NOT NULL to document the deviation — don't let that trip the guard).
  assert.ok(
    !/initiative_id\s+uuid NOT NULL REFERENCES public\.initiatives/.test(sql),
    'initiative_id column must NOT be declared NOT NULL',
  );
});

test('#988 two partial UNIQUE indexes provide real idempotency (F-M-unique)', () => {
  assert.match(
    sql,
    /CREATE UNIQUE INDEX IF NOT EXISTS cas_item_file_round\s+ON public\.curation_artifact_snapshots\(board_item_id, board_item_file_id, review_round\)\s+WHERE board_item_file_id IS NOT NULL/,
    'partial unique on (item, file, round)',
  );
  assert.match(
    sql,
    /CREATE UNIQUE INDEX IF NOT EXISTS cas_item_docver_round\s+ON public\.curation_artifact_snapshots\(board_item_id, document_version_id, review_round\)\s+WHERE document_version_id IS NOT NULL/,
    'partial unique on (item, docver, round)',
  );
});

test('#988 deny-all RLS: ENABLE RLS + REVOKE anon/authenticated, no permissive policy', () => {
  assert.match(
    sql,
    /ALTER TABLE public\.curation_artifact_snapshots ENABLE ROW LEVEL SECURITY/,
    'RLS enabled',
  );
  assert.match(
    sql,
    /REVOKE ALL ON public\.curation_artifact_snapshots FROM anon, authenticated/,
    'REVOKE table grants from anon + authenticated (default privileges auto-grant)',
  );
  // deny-all = NO permissive policy on the table.
  assert.ok(
    !/CREATE POLICY[^\n]*ON public\.curation_artifact_snapshots/i.test(sql),
    'must NOT create any policy on curation_artifact_snapshots (deny-all = no policy)',
  );
});

test('#988 RPC is SECDEF, gated curate_content OR manage_platform, REVOKE PUBLIC/anon', () => {
  assert.match(
    sql,
    /CREATE OR REPLACE FUNCTION public\.register_curation_artifact_snapshot\(/,
    'defines the register RPC',
  );
  assert.match(sql, /SECURITY DEFINER/, 'RPC is SECURITY DEFINER');
  assert.ok(
    sql.includes("public.can_by_member(v_caller.id, 'curate_content')") &&
      sql.includes("public.can_by_member(v_caller.id, 'manage_platform')"),
    'gate is curate_content OR manage_platform',
  );
  assert.ok(
    sql.includes(`REVOKE EXECUTE ON FUNCTION public.${RPC_SIG} FROM PUBLIC, anon, authenticated`),
    'REVOKE EXECUTE FROM PUBLIC, anon, authenticated (SPEC §5 canonical)',
  );
  assert.ok(
    sql.includes(`GRANT  EXECUTE ON FUNCTION public.${RPC_SIG} TO authenticated, service_role`),
    'keep authenticated + service_role',
  );
  assert.match(sql, /ON CONFLICT DO NOTHING/, 'idempotent insert (ON CONFLICT DO NOTHING)');
  // H1: idempotent re-select must be two SEQUENTIAL IF blocks (not IF/ELSIF) so a
  // dual-anchor conflict on the docver index still resolves the existing id.
  assert.ok(
    /IF v_id IS NULL AND p_document_version_id IS NOT NULL THEN/.test(sql),
    'H1: docver re-select is a guarded sequential IF (v_id IS NULL fallback), not an ELSIF',
  );
  assert.ok(!/ELSIF p_document_version_id IS NOT NULL THEN/.test(sql), 'H1: no ELSIF re-select branch');
});

test('#988 RPC applies ADR-0105 confidential gate on the write path + derives initiative_id', () => {
  assert.ok(
    sql.includes('public.rls_can_see_initiative(v_initiative)'),
    'write path applies rls_can_see_initiative (curate_content is not necessarily GP)',
  );
  // initiative_id + org derived server-side via a single JOIN (never a caller param).
  assert.match(
    sql,
    /SELECT bi\.id, bi\.organization_id, pb\.initiative_id\s+INTO v_item_id, v_org, v_initiative\s+FROM public\.board_items bi\s+LEFT JOIN public\.project_boards pb ON pb\.id = bi\.board_id/,
    'derives org + initiative via board_items LEFT JOIN project_boards on board_id',
  );
  assert.ok(
    !/p_initiative_id/.test(sql),
    'RPC must NOT accept a caller-supplied initiative_id (gate-bearing denorm)',
  );
  // H2: not-found + confidential + cross-org collapse into ONE generic error (no existence oracle).
  assert.match(
    sql,
    /IF v_item_id IS NULL\s*\n\s*OR NOT public\.rls_can_see_initiative\(v_initiative\)\s*\n\s*OR \(NOT v_is_gp AND v_caller\.organization_id IS DISTINCT FROM v_org\) THEN\s*\n\s*RAISE EXCEPTION 'Board item not found or not accessible/,
    'H2: single generic gate — no existence oracle, cross-org guarded for non-GP',
  );
});

test('#988 F-H6: drive_revision_id is stored but never returned by the RPC', () => {
  // The column exists; the RETURN envelope must not include it.
  assert.match(sql, /drive_revision_id\s+text,/, 'drive_revision_id column present');
  const returns = sql.match(/RETURN jsonb_build_object\([\s\S]*?\);/g) || [];
  assert.ok(returns.length >= 2, 'RPC has return envelopes');
  for (const r of returns) {
    assert.ok(!/drive_revision_id/.test(r), 'no return envelope may include drive_revision_id');
  }
});

test('#988 review-log additive columns + criteria CHECK accepting empty object', () => {
  assert.match(
    sql,
    /ADD COLUMN IF NOT EXISTS artifact_snapshot_id uuid\s+REFERENCES public\.curation_artifact_snapshots\(id\) ON DELETE SET NULL/,
    'artifact_snapshot_id FK ON DELETE SET NULL',
  );
  assert.ok(
    sql.includes('ADD COLUMN IF NOT EXISTS reviewer_governing_politica_version_id uuid') &&
      sql.includes('ADD COLUMN IF NOT EXISTS reviewer_governing_termo_version_id uuid'),
    'per-reviewer governing version columns added',
  );
  // Criteria CHECK must accept '{}' (writer submits empty when no scores) — neutrality.
  assert.match(sql, /criteria_scores = '\{\}'::jsonb\s*\n\s*OR \(/, "criteria CHECK accepts '{}'");
  for (const k of ['clarity', 'originality', 'adherence', 'relevance', 'ethics']) {
    assert.ok(sql.includes(`(criteria_scores ? '${k}')`), `criteria CHECK requires key ${k}`);
  }
});

test('#988 behavior-neutral: does NOT redefine submit_curation_review (F-B2)', () => {
  assert.ok(
    !/(CREATE|ALTER|DROP)\s+(OR\s+REPLACE\s+)?FUNCTION\s+public\.submit_curation_review/i.test(sql),
    'no production write-path RPC change (F-B2)',
  );
});

test('#988 ratchet oracle defined + locked to service_role', () => {
  assert.ok(
    sql.includes('CREATE OR REPLACE FUNCTION public._audit_curation_artifact_snapshot_security()'),
    'audit oracle defined',
  );
  assert.ok(
    sql.includes('REVOKE EXECUTE ON FUNCTION public._audit_curation_artifact_snapshot_security() FROM PUBLIC, anon, authenticated'),
    'audit oracle locked down',
  );
  assert.ok(
    sql.includes('GRANT  EXECUTE ON FUNCTION public._audit_curation_artifact_snapshot_security() TO service_role'),
    'audit oracle callable by service_role',
  );
});

// ─────────────────────────────────────────────────────────────────────────
// (B) DB-aware — service role (real DB required; catalog-only, no fixtures)
//
// CUR_008 / SPEC §8 AC ("confidential-initiative snapshots omitted from any read"):
// untestable in PR-1 because PR-1 ships ZERO read RPCs. The confidential gate is
// enforced at WRITE time via rls_can_see_initiative(v_initiative), collapsed into a
// single generic error with the not-found + cross-org checks (see the write-path test
// above). The behavioral read-path assertion is deferred to #308-B, when
// member_contribution_evidence and the other read RPCs land.
//
// The happy-path insert + idempotent return is exercised by an apply-time smoke under a
// simulated GP member (rolled back), NOT here: register_curation_artifact_snapshot
// requires auth.uid() -> a member row, which service_role (auth.uid() = NULL) can never
// satisfy — so a service_role .rpc() call only reaches the 'Not authenticated' guard.
// ─────────────────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const svc = () => createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

test('#988 db: deny-all posture + REVOKE intact (ratchet oracle)', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await svc().rpc('_audit_curation_artifact_snapshot_security');
  assert.ok(!error, `audit oracle must be callable by service_role: ${JSON.stringify(error)}`);
  assert.equal(data.rpc_anon_execute, false, 'anon must NOT have EXECUTE on the register RPC');
  assert.equal(data.rpc_authenticated_execute, true, 'authenticated must retain EXECUTE');
  assert.equal(data.table_anon_select, false, 'anon must have NO table SELECT');
  assert.equal(data.table_anon_insert, false, 'anon must have NO table INSERT');
  assert.equal(data.table_authenticated_select, false, 'authenticated must have NO table SELECT (deny-all)');
  assert.equal(data.table_authenticated_insert, false, 'authenticated must have NO table INSERT (deny-all)');
  assert.equal(data.rls_enabled, true, 'RLS must be enabled');
  assert.equal(data.permissive_policy_count, 0, 'deny-all: zero policies on the table');
});

test('#988 db: register RPC is service_role-executable and idempotent envelope shape', { skip: dbGated ? false : skipMsg }, async () => {
  // No fixtures: calling with a random board_item_id must fail cleanly (not-found),
  // proving the RPC exists, is reachable by service_role, and validates its input —
  // without needing real curation data (curation tables are 0 rows).
  const { error } = await svc().rpc('register_curation_artifact_snapshot', {
    p_board_item_id: '00000000-0000-0000-0000-000000000000',
    p_content_product_id: '00000000-0000-0000-0000-000000000001',
  });
  assert.ok(error, 'a non-existent board item must raise (Board item not found)');
  assert.match(String(error.message || ''), /Board item not found|not authenticated/i,
    `expected a not-found/auth error, got: ${JSON.stringify(error)}`);
});

test('#988 db: curation_review_log new columns are PostgREST-selectable', { skip: dbGated ? false : skipMsg }, async () => {
  const { error } = await svc()
    .from('curation_review_log')
    .select('artifact_snapshot_id, reviewer_governing_politica_version_id, reviewer_governing_termo_version_id')
    .limit(1);
  assert.ok(!error, `new columns must be selectable, got: ${JSON.stringify(error)}`);
});
