/**
 * Issue #179 / p204 — Canonical approval orchestration (static contract)
 *
 * Verifies that:
 *   - `approve_selection_application(uuid, jsonb)` exists with the expected
 *     orchestration side-effects (auth gate → member upsert → person upsert →
 *     engagement insert → onboarding seed → notification → audit).
 *   - `admin_update_application` + `finalize_decisions` delegate to the
 *     canonical RPC on approve transition (no inline approval logic).
 *   - The Herlon-class invariant is preserved: engagement is inserted with
 *     `agreement_certificate_id` LEFT NULL when kind requires_agreement, so
 *     `auth_engagements.is_authoritative` stays FALSE until counter-signature.
 *
 * Reads static migration SQL only — does not require DB env. Companion to the
 * `tests/contracts/selection-onboarding-diversity.test.mjs` and #181/#177
 * static contract suites (p203 sediment).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

function loadAllMigrations() {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql')).sort();
  return files.map(f => ({ name: f, content: readFileSync(join(MIGRATIONS_DIR, f), 'utf8') }));
}

const migrations = loadAllMigrations();
const allSQL = migrations.map(m => m.content).join('\n');

function findFunctionBody(funcName) {
  const escaped = funcName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${escaped}\\s*\\([^)]*\\)[\\s\\S]*?AS\\s+\\$(\\w*)\\$([\\s\\S]*?)\\$\\1\\$`,
    'gi'
  );
  const matches = [...allSQL.matchAll(regex)];
  return matches.length > 0 ? matches[matches.length - 1][2] : null;
}

// ─── 1. Canonical RPC exists with expected signature ───
test('approve_selection_application RPC defined in migrations', () => {
  const body = findFunctionBody('approve_selection_application');
  assert.ok(body, 'approve_selection_application not found in migrations');
});

test('approve_selection_application is SECURITY DEFINER + search_path locked', () => {
  const pattern = /approve_selection_application[\s\S]*?SECURITY\s+DEFINER[\s\S]*?SET\s+search_path\s+TO\s+'public',\s*'pg_temp'/i;
  assert.ok(pattern.test(allSQL), 'must be SECURITY DEFINER with locked search_path');
});

test('approve_selection_application granted EXECUTE to authenticated only', () => {
  const grant = /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.approve_selection_application\(uuid,\s*jsonb\)\s+TO\s+authenticated/i;
  const revoke = /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.approve_selection_application\(uuid,\s*jsonb\)\s+FROM\s+PUBLIC/i;
  assert.ok(grant.test(allSQL), 'must GRANT EXECUTE TO authenticated');
  assert.ok(revoke.test(allSQL), 'must REVOKE ALL FROM PUBLIC');
});

// ─── 2. Auth gate ───
test('approve_selection_application gates on can_by_member(manage_platform)', () => {
  const body = findFunctionBody('approve_selection_application');
  assert.ok(/can_by_member\([^,]+,\s*'manage_platform'\)/.test(body),
    'must gate on V4 can_by_member(\'manage_platform\')');
});

// ─── 3. Status guard ───
test('approve_selection_application rejects non-approved/converted status', () => {
  const body = findFunctionBody('approve_selection_application');
  assert.ok(/status NOT IN \('approved', 'converted'\)/.test(body),
    'must reject statuses other than approved|converted');
});

// ─── 4. Member upsert ───
test('approve_selection_application upserts member via lower(email) lookup', () => {
  const body = findFunctionBody('approve_selection_application');
  assert.ok(/lower\(email\)\s*=\s*lower\(v_app\.email\)/.test(body),
    'must lookup member by case-insensitive email');
  assert.ok(/INSERT INTO public\.members[\s\S]+?VALUES\s*\([\s\S]+?v_app\.organization_id/.test(body),
    'must INSERT new member with organization_id from application');
});

// ─── 5. Person upsert + members.person_id link ───
test('approve_selection_application upserts persons with consent_status=pending + links members.person_id', () => {
  const body = findFunctionBody('approve_selection_application');
  assert.ok(/INSERT INTO public\.persons[\s\S]+?'pending'/.test(body),
    'must INSERT person with consent_status=\'pending\'');
  assert.ok(/UPDATE public\.members SET person_id = v_person_id/.test(body),
    'must link members.person_id after person upsert');
});

// ─── 6. Engagement insert with V4 schema ───
test('approve_selection_application creates engagement with selection_application_id + contract_volunteer legal basis', () => {
  const body = findFunctionBody('approve_selection_application');
  assert.ok(/INSERT INTO public\.engagements[\s\S]+?selection_application_id/.test(body),
    'must INSERT engagement with selection_application_id');
  assert.ok(/'contract_volunteer'/.test(body),
    'must use contract_volunteer legal_basis (matches engagements_legal_basis_check)');
  assert.ok(/kind = v_engagement_kind/.test(body) || /kind\s*=\s*'volunteer'/.test(body) || /v_engagement_kind\s+text\s+:=\s+'volunteer'/.test(body),
    'must use kind=volunteer for selection-derived engagements');
});

// ─── 7. Herlon-class invariant: engagement created with no certificate when requires_agreement ───
test('approve_selection_application does NOT set agreement_certificate_id (kept NULL until counter-sign)', () => {
  const body = findFunctionBody('approve_selection_application');
  // INSERT clause must NOT name agreement_certificate_id in its column list
  const insertEngagement = body.match(/INSERT INTO public\.engagements\s*\(([^)]+)\)/);
  assert.ok(insertEngagement, 'engagement INSERT not found');
  assert.ok(!/agreement_certificate_id/.test(insertEngagement[1]),
    'INSERT must NOT set agreement_certificate_id — leave NULL so is_authoritative=false in auth_engagements view');
});

// ─── 8. Idempotency: existing active engagement is reused, selection_application_id backfilled ───
test('approve_selection_application is idempotent on existing active engagement', () => {
  const body = findFunctionBody('approve_selection_application');
  assert.ok(/v_existing_engagement_id[\s\S]+?FROM public\.engagements[\s\S]+?status\s*=\s*'active'/.test(body),
    'must look up existing active engagement before INSERT');
  assert.ok(/UPDATE public\.engagements\s*SET selection_application_id = p_application_id[\s\S]+?WHERE id = v_existing_engagement_id\s+AND selection_application_id IS NULL/.test(body),
    'must backfill selection_application_id on existing engagement when missing');
});

// ─── 9. Onboarding + notification + audit ───
test('approve_selection_application seeds onboarding, sends notification, writes audit row', () => {
  const body = findFunctionBody('approve_selection_application');
  assert.ok(/INSERT INTO public\.onboarding_progress[\s\S]+?onboarding_steps[\s\S]+?is_required = true/.test(body),
    'must seed canonical onboarding (is_required=true) from onboarding_steps');
  assert.ok(/PERFORM public\.check_pre_onboarding_auto_steps/.test(body),
    'must call check_pre_onboarding_auto_steps');
  assert.ok(/PERFORM public\.create_notification\([\s\S]+?'selection_approved'/.test(body),
    'must send selection_approved notification');
  assert.ok(/INSERT INTO public\.data_anomaly_log[\s\S]+?'selection_approval_canonical'/.test(body),
    'must write data_anomaly_log row with anomaly_type=\'selection_approval_canonical\'');
});

// ─── 10. admin_update_application delegates to canonical ───
test('admin_update_application delegates to canonical RPC on approve transition', () => {
  const body = findFunctionBody('admin_update_application');
  assert.ok(body, 'admin_update_application must still exist');
  assert.ok(/v_canonical_result\s*:=\s*public\.approve_selection_application\(p_application_id/.test(body),
    'must delegate to approve_selection_application on approve transition');
  // Audit signals canonical_invoked
  assert.ok(/'canonical_invoked',\s*v_canonical_result IS NOT NULL/.test(body),
    'audit log must signal canonical_invoked');
  // Approve-transition guard
  assert.ok(/v_new_status\s*=\s*'approved'\s+AND\s+v_old_status\s*<>\s*'approved'/.test(body),
    'delegation must be gated by approve transition (new=approved AND old≠approved)');
});

// ─── 11. finalize_decisions delegates per-decision when status=approved ───
test('finalize_decisions delegates per-decision when status=approved', () => {
  const body = findFunctionBody('finalize_decisions');
  assert.ok(body, 'finalize_decisions must still exist');
  assert.ok(/v_canonical_result\s*:=\s*public\.approve_selection_application\(v_app_id,/.test(body),
    'must delegate to approve_selection_application per decision');
  // Conversion path stays separate (does NOT delegate)
  assert.ok(/v_convert_to IS NOT NULL[\s\S]+?CONTINUE/.test(body),
    'conversion path (researcher → leader) must still short-circuit without calling canonical');
  // Diversity snapshot preserved
  assert.ok(/INSERT INTO public\.selection_diversity_snapshots/.test(body),
    'diversity snapshot at loop end must be preserved');
});

// ─── 12. Return contract on admin_update_application is backward-compat ───
test('admin_update_application return shape preserved for frontend callers', () => {
  const body = findFunctionBody('admin_update_application');
  assert.ok(/'success',\s+true/.test(body), 'must return success:true on happy path');
  assert.ok(/'old_status',\s+v_old_status/.test(body), 'must return old_status');
  assert.ok(/'new_status',\s+v_new_status/.test(body), 'must return new_status');
  assert.ok(/'onboarding_seeded',\s+v_seeded_count/.test(body), 'must return onboarding_seeded');
  assert.ok(/'role_promoted',\s+v_promoted/.test(body), 'must return role_promoted');
});
