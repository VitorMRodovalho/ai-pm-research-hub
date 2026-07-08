/**
 * Contract test for #999 + #1175 F1 — verify_member_affiliations_bulk (vep_sync branch).
 *
 * #999 established that the bulk verify must persist a real expiry into
 * membership_expires_on (the pre-#999 body hard-coded NULL). #1175 F1 then fixed WHICH
 * expiry: the #999 body persisted service_latest_end_date (end of the VOLUNTEER SERVICE)
 * and derived membership_active from vep_status_raw = 'Active' — the status of the VEP
 * CANDIDATURA, not of the PMI membership (same conflation class as #1130). Measured
 * impact 2026-07-08: 10/68 falsely marked "filiação inativa", 7 with provably current
 * membership. F1 derives both membership_active and membership_expires_on from the
 * pmi_memberships snapshot ([{chapterName, expiryDate}]) on the SAME matched row, and
 * routes no-evidence members to the no_vep bucket instead of fabricating "inactive".
 *
 * Static migration-body guard (offline, hard-fails without the fix). A behavioral
 * DB-aware assertion is intentionally omitted — exercising the write path would mutate
 * live member/verification data.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const MIGRATIONS_DIR = resolve(process.cwd(), 'supabase/migrations');
const allSQL = readdirSync(MIGRATIONS_DIR)
  .filter((f) => f.endsWith('.sql')).sort()
  .map((f) => readFileSync(join(MIGRATIONS_DIR, f), 'utf8')).join('\n');

function latestFunctionBody(funcName) {
  const escaped = funcName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:public\\.)?${escaped}\\s*\\([^)]*\\)[\\s\\S]*?AS\\s+\\$(\\w*)\\$([\\s\\S]*?)\\$\\1\\$`,
    'gi',
  );
  const m = [...allSQL.matchAll(regex)];
  return m.length ? m[m.length - 1][2] : null;
}

test('#999 bulk vep_sync branch selects service_latest_end_date from the matched application', () => {
  const body = latestFunctionBody('verify_member_affiliations_bulk');
  assert.ok(body, 'verify_member_affiliations_bulk must be defined in a migration');
  assert.ok(
    body.includes('service_latest_end_date'),
    'the LATERAL/subquery must fetch service_latest_end_date (was only vep_status_raw)',
  );
});

test('#999/#1175 a real expiry is persisted for vep_sync (no longer a hard-coded NULL)', () => {
  const body = latestFunctionBody('verify_member_affiliations_bulk');
  assert.ok(body);
  // #1175 F1: the persisted expiry is the MEMBERSHIP expiry (max pmi_memberships
  // expiryDate), not service_latest_end_date (end of the volunteer service, the #999 slip).
  assert.ok(
    /CASE\s+WHEN\s+p_method\s*=\s*'vep_sync'\s+THEN\s+v_max_expiry/i.test(body),
    "membership_expires_on must be CASE WHEN p_method='vep_sync' THEN v_max_expiry (the membership expiry from pmi_memberships)",
  );
  // The pre-#999 INSERT wrote `..., v_active, NULL, p_method, ...` — that exact NULL-in-the-
  // expiry-slot must stay gone.
  assert.ok(
    !/v_active,\s*NULL,\s*p_method/.test(body),
    'the pre-#999 hard-coded NULL expiry slot must not return',
  );
});

test('#1175 F1: vep_sync derives membership_active from membership EVIDENCE, never from the application status', () => {
  const body = latestFunctionBody('verify_member_affiliations_bulk');
  assert.ok(body);
  // max parseable expiryDate from the pmi_memberships snapshot...
  assert.ok(
    /max\(to_date\(x\.elem->>'expiryDate',\s*'DD Mon YYYY'\)\)/.test(body),
    'v_max_expiry must aggregate pmi_memberships expiryDate',
  );
  // ...compared to today decides active/inactive
  assert.ok(
    /v_active\s*:=\s*\(v_max_expiry\s*>=\s*CURRENT_DATE\)/.test(body),
    'membership_active must derive from the membership expiry, not vep_status_raw (#1130 conflation class)',
  );
  // no evidence -> no_vep bucket (manual verification), never fabricated inactive
  assert.ok(
    /IF\s+v_max_expiry\s+IS\s+NULL\s+THEN[\s\S]*?v_no_vep\s*:=\s*array_append\(v_no_vep,\s*r\.id\)/.test(body),
    'members without membership evidence must go to no_vep, not be marked inactive',
  );
});

test('#1175 F1: sede_manual/self_attested branch keeps the previous derivation (separate follow-up)', () => {
  const body = latestFunctionBody('verify_member_affiliations_bulk');
  assert.ok(body);
  assert.ok(
    /v_active\s*:=\s*\(r\.vep_status\s*=\s*'Active'\)/.test(body),
    'the non-vep_sync ELSE branch is intentionally unchanged by #1175 F1',
  );
});
