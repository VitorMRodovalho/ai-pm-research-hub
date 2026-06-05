/**
 * GAP-205.A contract test — member_emails RLS multi-tenant isolation
 *
 * Static analysis tripwire over migration files. Validates the policy
 * surface that protects `public.member_emails` from cross-tenant reads.
 * Issue: #205 (P162 #116 GAP-205.A) — council Tier 1 PR #240 finding that
 * the original behavioural test (member_emails.test.mjs Step 7) only
 * exercised the no-Authorization-header path. The RESTRICTIVE policy
 * `member_emails_v4_org_scope` was never asserted.
 *
 * Why static analysis (not behavioural):
 *   - The two-policy combination on `member_emails` is PERMISSIVE(false)
 *     + RESTRICTIVE(auth_org()). PostgreSQL evaluates RLS as
 *     `(any PERMISSIVE = true) AND (all RESTRICTIVE = true)`. Because
 *     PERMISSIVE always returns false, no direct client path (anon,
 *     authenticated same-org, authenticated different-org) can ever
 *     return rows. The RESTRICTIVE policy is dead-code at the SQL layer
 *     but encoded as belt-and-suspenders documentation of intent.
 *   - A behavioural test would need to mint JWTs for two different orgs,
 *     observe the deny path, and assert empty results. The deny path is
 *     already covered by PERMISSIVE(false); the RESTRICTIVE policy adds
 *     no observable behaviour beyond PERMISSIVE(false).
 *   - Codebase convention (multi-org-isolation.test.mjs +
 *     rls-auth-org-caller-derived.test.mjs) is to assert policy text
 *     against migration files. This test follows that pattern.
 *
 * What this guards against:
 *   - Future migration drops the PERMISSIVE(false) policy → table becomes
 *     readable by authenticated clients.
 *   - Future migration relaxes the RESTRICTIVE org_scope to remove
 *     auth_org() — cross-tenant reads become possible if PERMISSIVE is
 *     also relaxed.
 *   - GRANT SELECT is re-granted to anon or authenticated → direct
 *     client SELECT becomes possible.
 *
 * Cross-ref:
 *   - ADR-0095 §3 (Security and RLS)
 *   - Migration 20260802000008 (initial policies + grants)
 *   - Migration 20260802000009 (REVOKE SELECT FROM authenticated)
 *   - P162 #116 GAP-205.A (docs/audit/P162_GAP_OPPORTUNITY_LOG.md)
 *
 * Scope: static analysis on migration text. Fast, no DB env required.
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
const allSQL = migrations.map(m => m.content).join('\n');

// ─── 1. PERMISSIVE deny-all policy must exist on member_emails ───
test('GAP-205.A: rpc_only_deny_all PERMISSIVE policy on member_emails uses USING (false)', () => {
  // Match: CREATE POLICY rpc_only_deny_all ON public.member_emails ... AS PERMISSIVE ... USING (false)
  const re = /CREATE\s+POLICY\s+rpc_only_deny_all\s+ON\s+public\.member_emails[\s\S]{0,300}USING\s*\(\s*false\s*\)/i;
  assert.match(allSQL, re,
    'rpc_only_deny_all must be created ON public.member_emails with USING (false). ' +
    'This is the canonical deny-all policy for tables that should only be reachable via SECDEF RPCs.');

  // Additionally verify the AS PERMISSIVE clause appears before USING (within the same CREATE POLICY block)
  const blockRe = /CREATE\s+POLICY\s+rpc_only_deny_all\s+ON\s+public\.member_emails[\s\S]{0,300}/i;
  const blockMatch = allSQL.match(blockRe);
  assert.ok(blockMatch, 'rpc_only_deny_all CREATE POLICY block must match');
  assert.match(blockMatch[0], /AS\s+PERMISSIVE/i,
    'rpc_only_deny_all must be declared AS PERMISSIVE (not RESTRICTIVE). ' +
    'A PERMISSIVE policy with USING (false) combined with the RESTRICTIVE org_scope creates ' +
    'an AND-false gate that blocks all direct client access regardless of org context.');
});

// ─── 2. RESTRICTIVE org-scope policy must exist with auth_org() check ───
test('GAP-205.A: member_emails_v4_org_scope RESTRICTIVE policy uses auth_org() in USING + WITH CHECK', () => {
  const blockRe = /CREATE\s+POLICY\s+member_emails_v4_org_scope\s+ON\s+public\.member_emails[\s\S]{0,500}/i;
  const blockMatch = allSQL.match(blockRe);
  assert.ok(blockMatch, 'member_emails_v4_org_scope CREATE POLICY block must exist');

  const block = blockMatch[0];

  assert.match(block, /AS\s+RESTRICTIVE/i,
    'member_emails_v4_org_scope must be RESTRICTIVE (not PERMISSIVE). RESTRICTIVE policies ' +
    'are AND-combined with PERMISSIVE; this adds tenant isolation as belt-and-suspenders.');

  assert.match(block, /USING\s*\(\s*\([^)]*organization_id\s*=\s*auth_org\(\)/i,
    'member_emails_v4_org_scope USING clause must filter by organization_id = auth_org(). ' +
    'Without this, RLS would only consult PERMISSIVE — losing the documented multi-tenant intent.');

  assert.match(block, /WITH\s+CHECK\s*\(\s*\([^)]*organization_id\s*=\s*auth_org\(\)/i,
    'member_emails_v4_org_scope WITH CHECK clause must also filter by organization_id = auth_org(). ' +
    'WITH CHECK runs on INSERT/UPDATE; omitting it would allow cross-tenant writes if ' +
    'PERMISSIVE were ever relaxed.');

  // The current policy also admits organization_id IS NULL (pre-V4-cutover support).
  // Track this explicitly so a future cleanup doesn't silently regress.
  assert.match(block, /organization_id\s+IS\s+NULL/i,
    'member_emails_v4_org_scope includes `organization_id IS NULL` admit clause ' +
    '(pre-V4 cutover support). If this is intentionally removed, update this test.');
});

// ─── 3. Direct DML grants must be revoked from anon + authenticated ───
test('GAP-205.A: direct DML grants revoked from anon + authenticated on member_emails', () => {
  // Migration 20260802000008 should contain both REVOKE statements
  const revokeFromAnon = /REVOKE\s+INSERT\s*,\s*UPDATE\s*,\s*DELETE\s*,\s*REFERENCES\s*,\s*TRIGGER\s*,\s*TRUNCATE\s+ON\s+public\.member_emails\s+FROM\s+anon/i;
  const revokeFromAuthd = /REVOKE\s+INSERT\s*,\s*UPDATE\s*,\s*DELETE\s*,\s*REFERENCES\s*,\s*TRIGGER\s*,\s*TRUNCATE\s+ON\s+public\.member_emails\s+FROM\s+authenticated/i;

  assert.match(allSQL, revokeFromAnon,
    'REVOKE INSERT,UPDATE,DELETE,REFERENCES,TRIGGER,TRUNCATE ON member_emails FROM anon must exist. ' +
    'Without this, anon could attempt direct table mutations (blocked by RLS, but the grant ' +
    'is the first line of defense and removes the attack surface entirely).');

  assert.match(allSQL, revokeFromAuthd,
    'REVOKE INSERT,UPDATE,DELETE,REFERENCES,TRIGGER,TRUNCATE ON member_emails FROM authenticated must exist. ' +
    'Without this, any authenticated user could attempt direct DML (blocked by RLS, but ' +
    'defense in depth requires removing the grant too).');
});

// ─── 4. SELECT must be revoked from anon (migration 20260802000008) ───
test('GAP-205.A: SELECT revoked from anon on member_emails (20260802000008)', () => {
  const revokeSelectAnon = /REVOKE\s+SELECT\s+ON\s+public\.member_emails\s+FROM\s+anon/i;
  assert.match(allSQL, revokeSelectAnon,
    'REVOKE SELECT ON member_emails FROM anon must exist (migration 20260802000008). ' +
    'Anon is blocked by RLS PERMISSIVE(false) regardless, but removing the grant removes ' +
    'the attack surface entirely (defense in depth).');
});

// ─── 5. SELECT must be revoked from authenticated (migration 20260802000009 amendment) ───
test('GAP-205.A: SELECT revoked from authenticated on member_emails (20260802000009 amendment)', () => {
  const revokeSelectAuth = /REVOKE\s+SELECT\s+ON\s+public\.member_emails\s+FROM\s+authenticated/i;
  assert.match(allSQL, revokeSelectAuth,
    'REVOKE SELECT ON member_emails FROM authenticated must exist ' +
    '(migration 20260802000009 council Tier 1 LOW-1 amendment). ' +
    'Authenticated clients are blocked by RLS PERMISSIVE(false) regardless, but removing ' +
    'the grant prevents accidental future drift if the PERMISSIVE policy is ever relaxed.');
});

// ─── 6. SECDEF RPC member_resolve_email must require authentication (no anon enumeration) ───
test('GAP-205.A: member_resolve_email SECDEF requires authentication (auth.uid() IS NULL guard)', () => {
  // Find the latest CREATE [OR REPLACE] FUNCTION member_resolve_email block.
  // Pattern-agnostic regex accepts both `CREATE FUNCTION` (after explicit DROP,
  // per GC-097 for signature changes) and `CREATE OR REPLACE FUNCTION`
  // (in-place body updates). Mirrors the shared parser at
  // tests/helpers/rpc-body-drift-parser.mjs:43. WATCH-215.A sediment.
  let latestBlock = null;
  for (let i = migrations.length - 1; i >= 0; i--) {
    const m = migrations[i];
    const match = m.content.match(
      /CREATE(?:\s+OR\s+REPLACE)?\s+FUNCTION\s+(?:public\.)?member_resolve_email\s*\([^)]*\)[\s\S]*?\$\$([\s\S]*?)\$\$/i
    );
    if (match) {
      latestBlock = { migration: m.name, body: match[1] };
      break;
    }
  }
  assert.ok(latestBlock,
    'No CREATE [OR REPLACE] FUNCTION member_resolve_email found in migrations.');

  // The function must raise on unauthenticated callers (excluding service_role/postgres).
  // ADR-0095 §4 documents this as intentional: any authenticated user can resolve any email.
  // The membership-enumeration concern is acknowledged; what we MUST guard against is anon.
  assert.match(latestBlock.body, /auth\.uid\(\)\s+IS\s+NULL/i,
    `member_resolve_email (in ${latestBlock.migration}) must check auth.uid() IS NULL. ` +
    `Without this, anon clients could resolve emails to member_ids — a clear ` +
    `membership-existence leak. ADR-0095 §4 explicitly limits resolve to authenticated users.`);

  assert.match(latestBlock.body, /RAISE\s+EXCEPTION\s+'Not authenticated'/i,
    `member_resolve_email (in ${latestBlock.migration}) must RAISE EXCEPTION 'Not authenticated' ` +
    `when auth.uid() IS NULL (and caller is not service_role/postgres).`);
});

// ─── 7. SECDEF RPC member_list_emails must require self / manage_member / view_pii ───
test('GAP-205.A: member_list_emails SECDEF gates on self / manage_member / view_pii', () => {
  let latestBlock = null;
  for (let i = migrations.length - 1; i >= 0; i--) {
    const m = migrations[i];
    const match = m.content.match(
      /CREATE(?:\s+OR\s+REPLACE)?\s+FUNCTION\s+(?:public\.)?member_list_emails\s*\([^)]*\)[\s\S]*?\$\$([\s\S]*?)\$\$/i
    );
    if (match) {
      latestBlock = { migration: m.name, body: match[1] };
      break;
    }
  }
  assert.ok(latestBlock,
    'No CREATE [OR REPLACE] FUNCTION member_list_emails found in migrations.');

  // The function must check self / manage_member / view_pii via can_by_member()
  assert.match(latestBlock.body, /can_by_member\([^)]*,\s*'manage_member'\)/i,
    `member_list_emails (in ${latestBlock.migration}) must call can_by_member(..., 'manage_member'). ` +
    `Without this, authenticated users could list ANY member's emails — including across orgs ` +
    `(since the function is SECDEF and bypasses RLS).`);

  assert.match(latestBlock.body, /can_by_member\([^)]*,\s*'view_pii'\)/i,
    `member_list_emails (in ${latestBlock.migration}) must call can_by_member(..., 'view_pii') ` +
    `as an alternative authorization path. ADR-0095 §4 grants list access to admin roles ` +
    `with view_pii permission.`);

  // Self path: v_caller.id = p_member_id
  assert.match(latestBlock.body, /v_caller\.id\s*=\s*p_member_id/i,
    `member_list_emails (in ${latestBlock.migration}) must allow self-read ` +
    `via v_caller.id = p_member_id (members can list their own emails).`);
});

// ─── 8. SECDEF RPC member_add_alternate_email must require self / manage_member ───
test('GAP-205.A: member_add_alternate_email SECDEF gates on self / manage_member', () => {
  let latestBlock = null;
  for (let i = migrations.length - 1; i >= 0; i--) {
    const m = migrations[i];
    const match = m.content.match(
      /CREATE(?:\s+OR\s+REPLACE)?\s+FUNCTION\s+(?:public\.)?member_add_alternate_email\s*\([^)]*\)[\s\S]*?\$\$([\s\S]*?)\$\$/i
    );
    if (match) {
      latestBlock = { migration: m.name, body: match[1] };
      break;
    }
  }
  assert.ok(latestBlock,
    'No CREATE [OR REPLACE] FUNCTION member_add_alternate_email found in migrations.');

  assert.match(latestBlock.body, /can_by_member\([^)]*,\s*'manage_member'\)/i,
    `member_add_alternate_email (in ${latestBlock.migration}) must call can_by_member(..., 'manage_member'). ` +
    `Note: view_pii is NOT sufficient for write — only manage_member or self.`);

  assert.match(latestBlock.body, /v_caller\.id\s*=\s*p_member_id/i,
    `member_add_alternate_email (in ${latestBlock.migration}) must allow self-write ` +
    `via v_caller.id = p_member_id (members can add their own alternate emails).`);

  // The function must NOT delegate to view_pii (read permission ≠ write permission)
  // We verify this by checking that view_pii is not in the OR chain for write.
  // A simple regex: between v_caller.id check and the second can_by_member, view_pii should not appear.
  const authBlock = latestBlock.body.match(/IF\s+v_caller\.id\s*=\s*p_member_id[\s\S]{0,200}THEN/i);
  if (authBlock) {
    assert.doesNotMatch(authBlock[0], /view_pii/i,
      `member_add_alternate_email auth gate must NOT include view_pii (read permission ` +
      `should not grant write). Current latest migration: ${latestBlock.migration}.`);
  }
});

// ─── 9. Trigger sync_member_email_trigger_fn must have cross-member collision guard ───
test('GAP-205.A: sync_member_email_trigger_fn raises on cross-member email collision', () => {
  let latestBlock = null;
  for (let i = migrations.length - 1; i >= 0; i--) {
    const m = migrations[i];
    const match = m.content.match(
      /CREATE(?:\s+OR\s+REPLACE)?\s+FUNCTION\s+(?:public\.)?sync_member_email_trigger_fn\s*\(\s*\)[\s\S]*?\$\$([\s\S]*?)\$\$/i
    );
    if (match) {
      latestBlock = { migration: m.name, body: match[1] };
      break;
    }
  }
  assert.ok(latestBlock,
    'No CREATE [OR REPLACE] FUNCTION sync_member_email_trigger_fn found in migrations.');

  // Cross-member guard (migration 20260802000009 council Tier 1 HIGH-1)
  assert.match(latestBlock.body, /cross-member\s+collision\s+guard/i,
    `sync_member_email_trigger_fn (in ${latestBlock.migration}) must have the ` +
    `"Cross-member collision guard" comment. The original af378809 trigger used ` +
    `ON CONFLICT DO UPDATE SET member_id = NEW.id which silently transferred email ` +
    `ownership between members (email theft vector). Migration 20260802000009 amended.`);

  assert.match(latestBlock.body, /v_existing_member_id\s+IS\s+NOT\s+NULL\s+AND\s+v_existing_member_id\s*<>\s*NEW\.id/i,
    `sync_member_email_trigger_fn (in ${latestBlock.migration}) must check ` +
    `v_existing_member_id <> NEW.id before allowing the email to bind. ` +
    `Council Tier 1 PR #240 HIGH-1 finding.`);

  assert.match(latestBlock.body, /RAISE\s+EXCEPTION/i,
    `sync_member_email_trigger_fn (in ${latestBlock.migration}) must RAISE EXCEPTION on ` +
    `cross-member collision (not silently transfer ownership).`);

  // ERRCODE 23505 (unique_violation)
  assert.match(latestBlock.body, /ERRCODE\s*=\s*'23505'/i,
    `sync_member_email_trigger_fn (in ${latestBlock.migration}) must use ERRCODE = '23505' ` +
    `(unique_violation) so callers can distinguish this from other errors.`);
});

// ─── 10. Sanity: tests cite the canonical migrations ───
test('GAP-205.A: canonical migrations exist (20260802000008 + 20260802000009)', () => {
  const m008 = migrations.find(m => m.name === '20260802000008_member_alternate_emails.sql');
  assert.ok(m008, 'Migration 20260802000008_member_alternate_emails.sql must exist');

  const m009 = migrations.find(m =>
    m.name === '20260802000009_p213_205_email_theft_guard_and_revoke_authenticated_select.sql'
  );
  assert.ok(m009,
    'Migration 20260802000009_p213_205_email_theft_guard_and_revoke_authenticated_select.sql must exist');
});

// ─── 11. GAP-205.B: FK constraint member_emails.organization_id → organizations(id) ON DELETE RESTRICT ───
test('GAP-205.B: member_emails.organization_id has FK to organizations(id) ON DELETE RESTRICT', () => {
  // The FK constraint must be added by migration 20260802000011 (council Tier 1
  // LOW / platform-guardian LOW-3 finding — schema integrity gap)
  const fkRe = /ALTER\s+TABLE\s+(?:ONLY\s+)?public\.member_emails\s+ADD\s+CONSTRAINT\s+member_emails_organization_id_fkey\s+FOREIGN\s+KEY\s*\(\s*organization_id\s*\)\s+REFERENCES\s+(?:public\.)?organizations\s*\(\s*id\s*\)\s+ON\s+DELETE\s+RESTRICT/i;
  assert.match(allSQL, fkRe,
    'ALTER TABLE public.member_emails ADD CONSTRAINT member_emails_organization_id_fkey ' +
    'FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT ' +
    'must exist in migrations (added by 20260802000011). ' +
    'Canonical pattern across multi-tenant tables (members/tribes/engagements all use RESTRICT). ' +
    'Without this FK, dangling org refs could silently accumulate.');

  // Verify the canonical migration exists
  const m011 = migrations.find(m =>
    m.name === '20260802000011_p214_205b_member_emails_organization_id_fk.sql'
  );
  assert.ok(m011,
    'Migration 20260802000011_p214_205b_member_emails_organization_id_fk.sql must exist');

  // Verify the safety pre-flight (no dangling refs) is part of the migration
  assert.match(m011.content, /dangling\s+org_id\s+refs/i,
    'Migration 20260802000011 must include a pre-flight check that asserts ' +
    'no dangling org refs exist before applying the FK constraint.');
});

// ─── 12. GAP-205.C: verified_at column dropped from member_emails ───
test('GAP-205.C: migration 20260802000012 drops verified_at column from member_emails', () => {
  const m012 = migrations.find(m =>
    m.name === '20260802000012_p215_205c_drop_member_emails_verified_at.sql'
  );
  assert.ok(m012,
    'Migration 20260802000012_p215_205c_drop_member_emails_verified_at.sql must exist');

  assert.match(m012.content, /ALTER\s+TABLE\s+public\.member_emails\s+DROP\s+COLUMN\s+verified_at/i,
    'Migration 20260802000012 must contain ALTER TABLE public.member_emails DROP COLUMN verified_at. ' +
    'GAP-205.C closure: column was dead schema (0 writes, 0 of 73 rows non-NULL) at p214 close.');
});

// ─── 13. GAP-205.C: latest member_list_emails CREATE FUNCTION omits verified_at from RETURNS TABLE ───
test('GAP-205.C: latest member_list_emails RETURNS TABLE does not include verified_at', () => {
  // Find the LATEST CREATE [OR REPLACE] FUNCTION member_list_emails block in migration sort order.
  // Same pattern-agnostic regex used in test #7. The latest definition must be
  // free of verified_at — both as a return column AND in the SELECT projection.
  let latestBlock = null;
  for (let i = migrations.length - 1; i >= 0; i--) {
    const m = migrations[i];
    const match = m.content.match(
      /CREATE(?:\s+OR\s+REPLACE)?\s+FUNCTION\s+(?:public\.)?member_list_emails\s*\([^)]*\)[\s\S]*?\$\$([\s\S]*?)\$\$/i
    );
    if (match) {
      // Capture both the header (RETURNS TABLE block) and body for inspection.
      const fullBlock = m.content.match(
        /CREATE(?:\s+OR\s+REPLACE)?\s+FUNCTION\s+(?:public\.)?member_list_emails\s*\([^)]*\)[\s\S]*?\$\$[\s\S]*?\$\$/i
      );
      latestBlock = { migration: m.name, header: fullBlock[0], body: match[1] };
      break;
    }
  }
  assert.ok(latestBlock,
    'No CREATE [OR REPLACE] FUNCTION member_list_emails found in migrations.');

  // The latest definition must NOT mention verified_at anywhere in its header
  // (RETURNS TABLE column list) or body (SELECT projection). Without this assertion,
  // a future re-add of the column could silently restore the dead-schema pattern.
  assert.doesNotMatch(latestBlock.header, /\bverified_at\b/i,
    `member_list_emails (latest in ${latestBlock.migration}) must NOT reference verified_at ` +
    `anywhere in the function header (RETURNS TABLE) or body (SELECT projection). ` +
    `Column was dropped via GAP-205.C; re-adding requires explicit ADR amendment.`);
});
