/**
 * Forward-defense: BUG-219.A Phase 2 — wire participate_in_governance_review
 * carve-out into get_chain_for_pdf + get_chain_audit_report.
 *
 * Origin: p219 close session, PM smoke (2026-05-22) of advogada Angelina
 * receiving "negativa de acesso" trying to open governance review links sent
 * via gmail on 2026-05-13. Discovery: migration p195 (20260710000000) shipped
 * the can() carve-out and engagement_kind_permissions seed for
 * external_reviewer, but consumer RPCs were never updated to consume it. The
 * carve-out has been silently dormant since 2026-05-10.
 *
 * Fix (p220 Phase 2): migration 20260804000000 broadens the auth gate in both
 * read-only governance review endpoints from strict can_by_member(manage_member)
 * to (manage_member OR participate_in_governance_review). Write/destructive
 * RPCs (lock_document_version, recirculate_governance_doc,
 * delete_document_version_draft) keep strict manage_member.
 *
 * Cross-ref:
 *   - supabase/migrations/20260804000000_p220_bug_219_a_external_reviewer_rpc_carve_out.sql
 *   - supabase/migrations/20260710000000_p195_can_carve_out_governance_review.sql (the carve-out
 *     definition in public.can() that was never wired into consumer surface)
 *   - supabase/migrations/20260518130000_p130_t15_external_reviewer_engagement_kind.sql (kind seed)
 *   - ADR-0007 (V4 Authority via can_by_member)
 *   - ADR-0016 (governance review chains)
 *   - P162 BUG-219.A
 *
 * Static-only bundle (no DB env required):
 *   1. Migration file registered at canonical timestamp/name
 *   2. Both read RPCs gate on (manage_member OR participate_in_governance_review)
 *   3. Error message references both gate names (string symmetry for audit)
 *   4. Write/destructive RPCs untouched in this migration (scope guard)
 *   5. Migration header references p195 carve-out and external_reviewer kind
 *
 * Behavioural smoke lives separately (live MCP execute_sql before merge —
 * carve-out impersonation requires JWT context not available in node:test).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIGRATION_FILE = resolve(
  ROOT,
  'supabase/migrations/20260804000000_p220_bug_219_a_external_reviewer_rpc_carve_out.sql'
);

test('p220 BUG-219.A Phase 2 migration file is registered per canonical name', () => {
  const dir = resolve(ROOT, 'supabase/migrations');
  const files = readdirSync(dir).filter(f => f.startsWith('20260804000000_'));
  assert.equal(files.length, 1,
    'Exactly one migration file must exist for version 20260804000000 (p220 BUG-219.A Phase 2)');
  assert.match(files[0], /^20260804000000_p220_bug_219_a_external_reviewer_rpc_carve_out\.sql$/,
    'Migration filename must follow `<timestamp>_p220_bug_219_a_external_reviewer_rpc_carve_out.sql`');
});

test('p220 BUG-219.A Phase 2: get_chain_for_pdf gate accepts carve-out', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');

  // Function recreated
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_chain_for_pdf\(p_chain_id uuid\)/,
    'Migration must CREATE OR REPLACE get_chain_for_pdf');

  // Extract get_chain_for_pdf body (between its CREATE...AS $function$ ... $function$;)
  const pdfFnMatch = body.match(/CREATE OR REPLACE FUNCTION public\.get_chain_for_pdf[\s\S]*?\$function\$;/);
  assert.ok(pdfFnMatch, 'get_chain_for_pdf body must be parseable');
  const pdfBody = pdfFnMatch[0];

  // Both gates referenced in the OR clause
  assert.match(pdfBody, /can_by_member\(v_caller_id,\s*'manage_member'\)/,
    'get_chain_for_pdf must still call can_by_member(manage_member) — preserves strict path');
  assert.match(pdfBody, /can_by_member\(v_caller_id,\s*'participate_in_governance_review'\)/,
    'get_chain_for_pdf must now ALSO call can_by_member(participate_in_governance_review) — p195 carve-out');

  // OR-combined gate (boolean OR, not separate IF statements)
  assert.match(pdfBody, /IF NOT \(public\.can_by_member\(v_caller_id,\s*'manage_member'\)[\s\S]*?OR public\.can_by_member\(v_caller_id,\s*'participate_in_governance_review'\)\) THEN/,
    'Gate must be combined as boolean OR in a single IF statement, not two separate checks');
});

test('p220 BUG-219.A Phase 2: get_chain_audit_report gate accepts carve-out', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');

  assert.match(body, /CREATE OR REPLACE FUNCTION public\.get_chain_audit_report\(p_chain_id uuid\)/,
    'Migration must CREATE OR REPLACE get_chain_audit_report');

  const auditFnMatch = body.match(/CREATE OR REPLACE FUNCTION public\.get_chain_audit_report[\s\S]*?\$function\$;/);
  assert.ok(auditFnMatch, 'get_chain_audit_report body must be parseable');
  const auditBody = auditFnMatch[0];

  assert.match(auditBody, /can_by_member\(v_caller_id,\s*'manage_member'\)/,
    'get_chain_audit_report must still call can_by_member(manage_member)');
  assert.match(auditBody, /can_by_member\(v_caller_id,\s*'participate_in_governance_review'\)/,
    'get_chain_audit_report must now ALSO call can_by_member(participate_in_governance_review)');
  assert.match(auditBody, /IF NOT \(public\.can_by_member\(v_caller_id,\s*'manage_member'\)[\s\S]*?OR public\.can_by_member\(v_caller_id,\s*'participate_in_governance_review'\)\) THEN/,
    'audit_report gate must be combined as boolean OR');
});

test('p220 BUG-219.A Phase 2: error message references both gate names', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');

  // Symmetry: error message in BOTH RPCs must reference both gate names so
  // ops/support staff can read the message and recognize which capability
  // failed (instead of confusing "requires manage_member" when carve-out
  // could have unlocked them).
  const errorMatches = body.match(/RAISE EXCEPTION 'Access denied: requires manage_member or participate_in_governance_review'/g);
  assert.ok(errorMatches && errorMatches.length === 2,
    `Both RPCs must RAISE the same broadened error message; found ${errorMatches?.length ?? 0} occurrences (expected 2)`);
});

test('p220 BUG-219.A Phase 2: scope guard — write/destructive RPCs NOT touched', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');

  // Migration must NOT recreate any of these (they keep strict manage_member).
  // Forward-defense against scope creep — if a future maintainer adds carve-out
  // to lock_document_version (which would let external reviewers FREEZE a version),
  // this test fails until the migration name + ADR review reflect the broader scope.
  const guarded = [
    'lock_document_version',
    'recirculate_governance_doc',
    'delete_document_version_draft',
    'sign_ratification_gate',
    'sign_ip_ratification',
    'approve_change_request',
  ];
  for (const fn of guarded) {
    assert.doesNotMatch(body, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}\\b`),
      `p220 Phase 2 scope is READ-only. RPC ${fn} must NOT be in this migration (write/sign actions keep strict manage_member). If you legitimately need to expand carve-out scope, file a separate ADR-0016 amendment first.`);
  }
});

test('p220 BUG-219.A Phase 2: migration header documents p195 carve-out reference + LGPD note', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');

  // Header must cite the p195 migration that defined the carve-out — readers
  // need the trail from "why broaden the gate?" to "where is the gate defined?"
  assert.match(body, /20260710000000_p195_can_carve_out_governance_review\.sql/,
    'Header must reference p195 carve-out migration (the parent decision)');

  // Header must reference external_reviewer kind (not just "external counsel")
  // — kind name is the V4 contract surface
  assert.match(body, /external_reviewer/,
    'Header must reference engagement kind external_reviewer explicitly');

  // LGPD considerations called out — audit_report exposes PII
  assert.match(body, /LGPD/i,
    'Header must call out LGPD impact (audit_report exposes signer PII)');
  assert.match(body, /OAB Art\.?\s*7/i,
    'Header must reference Bar duty of confidentiality (OAB Art. 7) as the legal basis enabling carve-out for external attorneys');
});

test('p220 BUG-219.A Phase 2: NOT authenticated path preserved (forward-defense vs gate-merge regression)', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');

  // Forward-defense: a refactor merging the not-authenticated check INTO the
  // capability check (e.g., "if v_caller_id IS NULL OR NOT can_by_member") would
  // change the error semantics (auth check returns "Not authenticated" 401-ish;
  // gate check returns "Access denied" 403-ish). Verify both messages remain distinct.
  const notAuthMatches = body.match(/RAISE EXCEPTION 'Not authenticated'/g);
  assert.ok(notAuthMatches && notAuthMatches.length === 2,
    `Both RPCs must preserve 'Not authenticated' as a distinct error from 'Access denied'; found ${notAuthMatches?.length ?? 0} (expected 2)`);
});
