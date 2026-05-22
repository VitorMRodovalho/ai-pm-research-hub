/**
 * Forward-defense: WATCH-257.B — normalize legacy `contract_volunteer` rows
 * and update producer RPCs to use LGPD-canonical `contract`.
 *
 * Origin: p219, post-p218 PR #263 (WATCH-257.A). PR #263 made the engagements
 * `legal_basis` CHECK constraint additive — both `contract` (LGPD-canonical,
 * Art. 7 V) and `contract_volunteer` (legacy from migration 20260413320000)
 * are accepted. But 46 existing rows and 2 producer RPCs still output
 * `contract_volunteer`, perpetuating the catalog↔runtime asymmetry on every
 * new engagement created via:
 *   - approve_selection_application (canonical selection→engagement RPC)
 *   - seed_member_engagement_by_role (template-based onboarding seed RPC)
 *
 * Fix (p219 Path B, per PM): migration 20260803000004 does:
 *   (1) UPDATE engagements: 46 rows `contract_volunteer` → `contract` (audited)
 *   (2) CREATE OR REPLACE approve_selection_application: default → `contract`
 *   (3) CREATE OR REPLACE seed_member_engagement_by_role: literal → `contract`
 *   (4) Sanity DO block fails loud if any row OR any canonical RPC body still
 *       contains the legacy literal.
 *
 * Scope: rows + 2 producer RPCs. Constraint stays additive (Path C — DROP
 * value from constraint — deferred for safety against other consumers).
 *
 * Cross-ref:
 *   - supabase/migrations/20260803000004_p219_watch_257_b_normalize_legacy_contract_volunteer.sql
 *   - supabase/migrations/20260803000002_p218_watch_257_a_engagements_legal_basis_lgpd_canonical.sql (additive constraint)
 *   - supabase/migrations/20260413320000_v4_phase3_engagements_table.sql (original `contract_volunteer` constraint)
 *   - supabase/migrations/20260415100000_v4_fix_legal_basis_lgpd_compliance.sql (catalog half of harmonization)
 *   - ADR-0006 (engagements + persons V4 model)
 *   - LGPD Art. 7 V (contract as legal basis)
 *   - P162 WATCH-257.B
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MIGRATION_FILE = resolve(
  ROOT,
  'supabase/migrations/20260803000004_p219_watch_257_b_normalize_legacy_contract_volunteer.sql'
);

test('p219 WATCH-257.B migration UPDATEs all contract_volunteer rows to contract', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');

  // Backfill UPDATE clause must target ALL legacy rows
  assert.match(body, /UPDATE public\.engagements\s+SET legal_basis\s*=\s*'contract'\s+WHERE legal_basis\s*=\s*'contract_volunteer'/i,
    'Migration must UPDATE engagements SET legal_basis=contract WHERE legal_basis=contract_volunteer');

  // Backfill must write audit_log entries with before/after values
  assert.match(body, /INSERT INTO public\.admin_audit_log/i,
    'Migration must write to admin_audit_log for backfill traceability');
  assert.match(body, /'watch_257_b_normalize_engagement_legal_basis'/i,
    'Audit action key must identify the migration');
  assert.match(body, /'legal_basis_before',\s*'contract_volunteer'/i,
    'Audit must capture before value contract_volunteer');
  assert.match(body, /'legal_basis_after',\s*'contract'/i,
    'Audit must capture after value contract');
});

test('p219 WATCH-257.B migration updates approve_selection_application RPC body', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');

  // RPC must be CREATE OR REPLACE
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.approve_selection_application/i,
    'Migration must CREATE OR REPLACE approve_selection_application');

  // Body must have v_legal_basis declared as 'contract' (NOT 'contract_volunteer')
  assert.match(body, /v_legal_basis\s+text\s*:=\s*'contract'\s*;/i,
    'approve_selection_application body must declare v_legal_basis := contract (not contract_volunteer)');

  // Must preserve SECDEF + search_path
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.approve_selection_application[\s\S]*?SECURITY DEFINER[\s\S]*?SET search_path TO 'public', 'pg_temp'/i,
    'approve_selection_application must preserve SECURITY DEFINER + search_path pin');
});

test('p219 WATCH-257.B migration updates seed_member_engagement_by_role RPC body', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');

  // RPC must be CREATE OR REPLACE
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.seed_member_engagement_by_role/i,
    'Migration must CREATE OR REPLACE seed_member_engagement_by_role');

  // Body must have 'contract' literal in INSERT (NOT 'contract_volunteer')
  // The INSERT INTO engagements line: CURRENT_DATE, 'contract', v_caller_person_id
  assert.match(body, /CURRENT_DATE,\s*'contract',\s*v_caller_person_id/i,
    'seed_member_engagement_by_role INSERT must use contract literal (not contract_volunteer)');

  // Must preserve SECDEF + search_path
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.seed_member_engagement_by_role[\s\S]*?SECURITY DEFINER[\s\S]*?SET search_path TO 'public', 'pg_temp'/i,
    'seed_member_engagement_by_role must preserve SECURITY DEFINER + search_path pin');
});

test('p219 WATCH-257.B migration sanity DO block fails loud if literal remains', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');

  // Sanity check (a): no engagements rows with contract_volunteer
  assert.match(body, /RAISE EXCEPTION 'WATCH-257\.B sanity FAIL:[^']*engagements rows still have legal_basis=contract_volunteer/i,
    'Migration must RAISE EXCEPTION if any engagement row still has legal_basis=contract_volunteer');

  // Sanity check (b): no RPC body with literal
  assert.match(body, /RAISE EXCEPTION 'WATCH-257\.B sanity FAIL:[^']*canonical RPC bodies still contain contract_volunteer literal/i,
    'Migration must RAISE EXCEPTION if any canonical RPC body still contains contract_volunteer literal');

  // Must query pg_proc.prosrc for the literal
  assert.match(body, /prosrc\s*~\s*'contract_volunteer'/i,
    'Sanity block must regex-check pg_proc.prosrc for the legacy literal');
});

test('p219 WATCH-257.B migration scope guard: only the 2 documented canonical RPCs', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');

  // Sanity check scopes to the 2 documented RPCs (not all functions)
  assert.match(body, /proname IN \('approve_selection_application', 'seed_member_engagement_by_role'\)/i,
    'Sanity block must scope to the 2 documented canonical RPCs');
});

test('p219 WATCH-257.B migration file is registered per timestamp pattern', () => {
  const dir = resolve(ROOT, 'supabase/migrations');
  const files = readdirSync(dir).filter(f => f.startsWith('20260803000004_'));
  assert.equal(files.length, 1,
    'Exactly one migration file must exist for version 20260803000004 (p219 WATCH-257.B)');
  assert.match(files[0], /^20260803000004_p219_watch_257_b_normalize_legacy_contract_volunteer\.sql$/,
    'Migration filename must follow `<timestamp>_<descriptive_name>.sql` per CLAUDE.md GC-097');
});

test('p219 WATCH-257.B migration reloads PostgREST schema cache', () => {
  const body = readFileSync(MIGRATION_FILE, 'utf8');
  assert.match(body, /NOTIFY pgrst,\s*'reload schema'/i,
    'Migration must NOTIFY pgrst reload schema (CLAUDE.md GC-097)');
});
