/**
 * Track R contract — `auth_org()` ACL hard tripwire.
 *
 * Security-engineer council review (p59) flagged that Track R Phase R2
 * D-category (21 tables with `(organization_id = auth_org() OR organization_id IS NULL)`
 * RLS policies) depends on `auth_org()` remaining REVOKE'd from anon/authenticated.
 * If a future migration runs `CREATE OR REPLACE FUNCTION public.auth_org()`
 * without a follow-up REVOKE, Postgres re-grants EXECUTE to PUBLIC by default,
 * silently undoing 21 table-level REVOKEs on PII tables.
 *
 * This contract test fails the build if `auth_org()` ACL contains any of:
 *   - PUBLIC (`=X/postgres`)
 *   - anon (`anon=X/...`)
 *   - authenticated (`authenticated=X/...`)
 *
 * Expected ACL post-Track R Phase R3 (p59):
 *   `postgres=X/postgres | service_role=X/postgres`
 *
 * If this test fails, either (a) the tripwire caught a regression — fix
 * by adding `REVOKE EXECUTE ON FUNCTION public.auth_org() FROM PUBLIC, anon,
 * authenticated;` to the offending migration, OR (b) the platform's V4 model
 * legitimately needs anon/authenticated callable — in which case re-evaluate
 * the 21 D-category Track R REVOKEs which depend on this constraint.
 *
 * Requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY for the DB-aware
 * assertion. Skips gracefully when env vars missing.
 *
 * Run locally:
 *   SUPABASE_URL=https://…supabase.co SUPABASE_SERVICE_ROLE_KEY=eyJ… \
 *   node --test tests/contracts/track-r-auth-org-acl.test.mjs
 */
import test from 'node:test';
import assert from 'node:assert/strict';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

const FORBIDDEN_PATTERNS = [
  // PUBLIC default grant — ACL element starts with `=` (no grantee)
  { regex: /(^|\| )=[^|]*r/, label: 'PUBLIC' },
  // anon role grant with `r` (SELECT/EXECUTE) privilege
  { regex: /\banon=[^|]*X/, label: 'anon (EXECUTE)' },
  // authenticated role grant with `X` (EXECUTE) privilege
  { regex: /\bauthenticated=[^|]*X/, label: 'authenticated (EXECUTE)' },
];

async function probeAclFor(functionName) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/_audit_function_acl`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify({ p_function_name: functionName }),
  });
  if (!res.ok) {
    throw new Error(`ACL probe RPC failed: ${res.status} ${await res.text()}`);
  }
  return res.json();
}

test(
  'Track R: auth_org() must not grant EXECUTE to PUBLIC, anon, or authenticated',
  { skip: !canRun && skipMsg },
  async () => {
    const result = await probeAclFor('auth_org');
    const acl = String(result?.acl ?? '');

    if (!acl || acl === 'NULL') {
      assert.fail(
        `auth_org() ACL probe returned empty/NULL result. Either the function ` +
          `was dropped, the helper RPC \`_audit_function_acl\` is missing, or ` +
          `the function ACL is unset (Postgres default = PUBLIC EXECUTE which ` +
          `would be a regression).`
      );
    }

    const violations = FORBIDDEN_PATTERNS.filter(({ regex }) => regex.test(acl));
    if (violations.length > 0) {
      const labels = violations.map(v => v.label).join(', ');
      assert.fail(
        `auth_org() ACL contains forbidden grant(s): ${labels}.\n\n` +
          `Current ACL: ${acl}\n\n` +
          `Track R Phase R2 D-category (21 tables with org_scope policy) ` +
          `depends on auth_org() being REVOKE'd from PUBLIC/anon/authenticated. ` +
          `If a migration recreated auth_org() without a follow-up REVOKE, ` +
          `add this to the offending migration:\n\n` +
          `  REVOKE EXECUTE ON FUNCTION public.auth_org() FROM PUBLIC, anon, authenticated;`
      );
    }
  }
);

test(
  'Track R: can() and can_by_member() V4 authority core must not grant EXECUTE to PUBLIC, anon, or authenticated',
  { skip: !canRun && skipMsg },
  async () => {
    // Defense-in-depth assertion: V4 authority core functions REVOKE'd
    // in Q-D batch 3b (p59) must remain locked down.
    for (const fnName of ['can', 'can_by_member']) {
      const result = await probeAclFor(fnName);
      const acl = String(result?.acl ?? '');

      if (!acl || acl === 'NULL') {
        assert.fail(
          `${fnName}() ACL probe returned empty/NULL — function may have been ` +
            `dropped or recreated with default PUBLIC EXECUTE.`
        );
      }

      const violations = FORBIDDEN_PATTERNS.filter(({ regex }) => regex.test(acl));
      if (violations.length > 0) {
        const labels = violations.map(v => v.label).join(', ');
        assert.fail(
          `${fnName}() ACL contains forbidden grant(s): ${labels}.\n\n` +
            `Current ACL: ${acl}\n\n` +
            `V4 authority core must remain REVOKE'd from PUBLIC/anon/authenticated ` +
            `(Q-D batch 3b, p59). Frontend uses cached operational_role; EF uses ` +
            `service_role via canV4 wrapper. Direct authenticated PostgREST call ` +
            `is not a legitimate use case.\n\n` +
            `Add to the offending migration:\n` +
            `  REVOKE EXECUTE ON FUNCTION public.${fnName}(uuid, text, text, uuid) FROM PUBLIC, anon, authenticated;`
        );
      }
    }
  }
);
