/**
 * ADR-0077 contract test — auth_org() caller-derived + Group A/B postura.
 *
 * Static analysis tripwire over migration files. Validates:
 *   1. The latest auth_org() definition is caller-derived (members.auth_id
 *      lookup + is_active=true), NOT the pre-p136 hardcoded constant.
 *   2. Financial tables (Group A strict — cost_entries, revenue_entries,
 *      sustainability_kpi_targets) do NOT have `organization_id IS NULL`
 *      relaxation in their SELECT policies.
 *   3. mcp_usage_log Group B permissive policy includes `organization_id
 *      IS NULL` admit clause for admins (per Ω-E.1.c).
 *
 * Why this matters:
 *   - Pre-p136 auth_org() was hardcoded `SELECT '2b4f58ab-...'::uuid`.
 *     Every authenticated caller (incl ghosts with no member row) saw
 *     single-org data. RF-1 financial exposure depended on the placeholder.
 *   - Commit 30af579 (p136 Ω-E.1.b) rewrote it caller-derived. This test
 *     fails the build if a future migration regresses.
 *   - Commit 5bba12b (p138 Ω-E.2-b.c) + commits 09362e3, f41b452, e9135d1
 *     consolidated the pattern. Tripwire keeps the contract honest.
 *
 * Scope: static analysis on migration text. Fast, no DB env required.
 * Live caller-class behavior was verified empirically in p136-p138 sessions
 * (memory/project_omega_e1_rf1_closed_p136.md +
 *  memory/project_omega_e2b_adr0077_shipped_p138.md).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

function loadMigrations() {
  const files = readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql')).sort();
  return files.map(f => ({
    name: f,
    content: readFileSync(join(MIGRATIONS_DIR, f), 'utf8'),
  }));
}

const migrations = loadMigrations();

// ─── Find the latest CREATE OR REPLACE FUNCTION public.auth_org() block ───
function findLatestAuthOrgDefinition() {
  // Iterate in reverse to find the most recent definition
  for (let i = migrations.length - 1; i >= 0; i--) {
    const m = migrations[i];
    // Match the CREATE OR REPLACE FUNCTION ... auth_org ... AS $...$ BODY $...$ block
    const match = m.content.match(
      /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+(?:public\.)?auth_org\s*\([^)]*\)[\s\S]*?\$function\$([\s\S]*?)\$function\$/i
    );
    if (match) {
      return { migration: m.name, body: match[1] };
    }
  }
  return null;
}

test('ADR-0077: latest auth_org() definition is caller-derived (members.auth_id + is_active)', () => {
  const found = findLatestAuthOrgDefinition();
  assert.ok(found, 'No CREATE OR REPLACE FUNCTION auth_org() found in any migration');

  const { migration, body } = found;

  assert.match(
    body,
    /FROM\s+public\.members\s+m/i,
    `Latest auth_org() (in ${migration}) must SELECT FROM public.members. Got body: ${body.trim()}`
  );
  assert.match(
    body,
    /m\.auth_id\s*=\s*auth\.uid\(\)/i,
    `Latest auth_org() (in ${migration}) must filter by m.auth_id = auth.uid(). Got body: ${body.trim()}`
  );
  assert.match(
    body,
    /m\.is_active\s*=\s*true/i,
    `Latest auth_org() (in ${migration}) must filter by m.is_active = true (fail-closed for offboarded). Got body: ${body.trim()}`
  );

  // Tripwire: must not be the pre-p136 hardcoded constant placeholder
  // (the body should NOT be just a SELECT of the hardcoded UUID literal)
  const isHardcodedOnly = /^\s*SELECT\s+'2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid\s*;?\s*$/i.test(body.trim());
  assert.equal(
    isHardcodedOnly,
    false,
    `Latest auth_org() (in ${migration}) is the pre-p136 hardcoded constant. ` +
    `This regresses RF-1 ghost exposure across 30+ V4 tables. See ADR-0077 + commit 30af579.`
  );
});

// ─── Group A (strict) financial tables: SELECT policies must NOT have IS NULL clause ───
test('ADR-0077: Group A financial tables policies must NOT relax NULL admit clause', () => {
  // The Ω-E.1 hardening migration (20260520000000) is the canonical source.
  const omegaE1 = migrations.find(m =>
    m.name.includes('p136_omega_e1_rls_rf1_org_scope_financial_tables')
  );
  assert.ok(omegaE1, 'Ω-E.1 financial RLS hardening migration must exist (20260520000000)');

  // Extract CREATE POLICY blocks for the 3 financial tables.
  const FINANCIAL_TABLES = ['cost_entries', 'revenue_entries', 'sustainability_kpi_targets'];

  for (const table of FINANCIAL_TABLES) {
    // Find the SELECT policy CREATE block for this table
    const selectPolicyRegex = new RegExp(
      `CREATE\\s+POLICY\\s+\\S+\\s+ON\\s+(?:public\\.)?${table}[\\s\\S]*?FOR\\s+SELECT[\\s\\S]*?(?=\\n\\s*(?:CREATE|DROP|ALTER|COMMENT|;?\\s*--|GRANT|REVOKE|$))`,
      'i'
    );
    const policyBlock = omegaE1.content.match(selectPolicyRegex);

    if (policyBlock) {
      const block = policyBlock[0];
      assert.doesNotMatch(
        block,
        /\borganization_id\s+IS\s+NULL\b/i,
        `Group A financial table ${table} SELECT policy must NOT include "organization_id IS NULL" clause. ` +
        `That relaxes to Group B (permissive). Financial tables keep NULL rows superadmin-only per ADR-0077. ` +
        `Found in: ${omegaE1.name}`
      );
    }
  }
});

// ─── Group B (permissive) mcp_usage_log: SELECT policy MUST have IS NULL admit clause ───
test('ADR-0077: mcp_usage_log Group B admin SELECT policy includes IS NULL admit clause', () => {
  // Ω-E.1.c migration is the canonical place
  const omegaE1c = migrations.find(m =>
    m.name.includes('p136_omega_e1c_mcp_usage_log_null_org_admin_visible')
  );
  assert.ok(omegaE1c, 'Ω-E.1.c mcp_usage_log NULL admit migration must exist (20260520020000)');

  // The whole migration body should contain the IS NULL clause for the admin policy
  assert.match(
    omegaE1c.content,
    /CREATE\s+POLICY\s+mcp_usage_log_select_admin_org\s+ON[\s\S]*?organization_id\s+IS\s+NULL/i,
    `mcp_usage_log_select_admin_org policy must include "organization_id IS NULL" admit clause ` +
    `(Group B permissive — system/platform logs visible to manage_member admins). ` +
    `Migration: ${omegaE1c.name}`
  );
});
