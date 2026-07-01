/**
 * Contract test for #999 — verify_member_affiliations_bulk must persist the VEP-enriched
 * membership expiry (selection_applications.service_latest_end_date) into
 * membership_expires_on for the vep_sync branch, so the renewal radar can fire. The pre-fix
 * body hard-coded membership_expires_on = NULL and never selected service_latest_end_date.
 *
 * Static migration-body guard (offline, hard-fails without the fix). Non-no-op: the
 * assertions below fail against the pre-fix body (which had the NULL hard-code and no
 * service_latest_end_date reference). A behavioral DB-aware assertion is intentionally
 * omitted — exercising the write path would mutate live member/verification data.
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

test('#999 the enriched expiry is persisted for vep_sync (no longer a hard-coded NULL)', () => {
  const body = latestFunctionBody('verify_member_affiliations_bulk');
  assert.ok(body);
  // The vep_sync branch must persist the date via a CASE keyed on the method.
  assert.ok(
    /CASE\s+WHEN\s+p_method\s*=\s*'vep_sync'\s+THEN\s+r\.service_end/i.test(body),
    "membership_expires_on must be CASE WHEN p_method='vep_sync' THEN r.service_end (not a hard NULL)",
  );
  // The pre-fix INSERT wrote `..., v_active, NULL, p_method, ...` — that exact NULL-in-the-
  // expiry-slot must be gone.
  assert.ok(
    !/v_active,\s*NULL,\s*p_method/.test(body),
    'the pre-fix hard-coded NULL expiry slot must be replaced',
  );
});

test('#999 active/inactive stays VEP-authoritative (unchanged consistency guard)', () => {
  const body = latestFunctionBody('verify_member_affiliations_bulk');
  assert.ok(body);
  assert.ok(
    /v_active\s*:=\s*\(r\.vep_status\s*=\s*'Active'\)/.test(body),
    'membership_active must still derive from vep_status = Active (the date only feeds the radar)',
  );
});
