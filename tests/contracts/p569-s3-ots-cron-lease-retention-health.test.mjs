/**
 * Contract: #569 Slice 3 — OTS pipeline cron + claim lease + retention + health.
 *
 * Locks the four deliverables of migration 20260805000136 (ADR-0101 Slice 3) plus the
 * EF-gate widening and the MCP tool:
 *   1. CLAIM LEASE — `_ots_claim_unstamped_assets` is an UPDATE-based lease (claimed_at,
 *      10-min window, FOR UPDATE SKIP LOCKED). Forward-defense: a bare SELECT-only claim
 *      must never return (PostgREST RPC = one transaction; a row lock alone releases
 *      before the EF processes anything — the lease is what survives across transactions).
 *   2. RETENTION — `_ots_retention_pass` purges ONLY revoked-declaration rows past the
 *      window (default 5y; 1-year safety floor). Forward-defense: must never delete
 *      'error' assets of draft/active declarations (declarant-entered Anexo I rows).
 *   3. HEALTH — `get_ots_pipeline_health` (view_internal_analytics gate; surfaces the
 *      retry-exhausted class that silently falls out of the claim filter).
 *   4. CRON — 3 jobs, stamp/upgrade non-overlapping, authenticating with the DEDICATED
 *      vault secret `ots_cron_secret` — forward-defense: the cron blocks must NOT use
 *      the vault `service_role_key` (proven stale vs the EF-injected key: 403 live,
 *      2026-06-10, #618).
 *
 * Cross-ref: #569, #618, ADR-0101 (Slice 3 + open items L63-64), migration
 * 20260805000135 (Slice 1 foundation), get_lgpd_cron_health (mould).
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const MIG_PATH = 'supabase/migrations/20260805000136_p569_s3_ots_cron_lease_retention_health.sql';
const MIG = readFileSync(MIG_PATH, 'utf8');
const MIG137_PATH = 'supabase/migrations/20260805000137_p569_s3b_claim_index_acl_retention_audit.sql';
const MIG137 = readFileSync(MIG137_PATH, 'utf8');
const EF_STAMP = readFileSync('supabase/functions/ots-stamp/index.ts', 'utf8');
const EF_UPGRADE = readFileSync('supabase/functions/ots-upgrade/index.ts', 'utf8');
const MCP_INDEX = readFileSync('supabase/functions/nucleo-mcp/index.ts', 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK
  ? createClient(SUPABASE_URL, SUPABASE_SRK, { auth: { persistSession: false } })
  : null;

// Scope helpers: slice each $function$ body out of the migration.
function fnBody(src, name) {
  const m = src.match(new RegExp(
    `CREATE OR REPLACE FUNCTION public\\.${name}\\([^)]*\\)[\\s\\S]*?AS \\$function\\$([\\s\\S]*?)\\$function\\$;`
  ));
  return m ? m[1] : '';
}
const CLAIM_BODY = fnBody(MIG, '_ots_claim_unstamped_assets');
// Retention was re-captured in 137 (council folds: audit trail + forward-guard) — latest capture wins.
const RETENTION_BODY = fnBody(MIG137, '_ots_retention_pass');
const HEALTH_BODY = fnBody(MIG, 'get_ots_pipeline_health');

describe('p569-s3 — migration presence + header', () => {
  it('migration file exists at canonical timestamp and is non-empty', () => {
    assert.ok(existsSync(MIG_PATH));
    assert.ok(MIG.length > 1000);
  });

  it('header carries WHAT/ROLLBACK + #569/#618/ADR-0101/#572 cross-refs', () => {
    assert.match(MIG, /-- WHAT/);
    assert.match(MIG, /-- ROLLBACK/);
    assert.match(MIG, /#569/);
    assert.match(MIG, /#618/);
    assert.match(MIG, /ADR-0101/);
    assert.match(MIG, /#572/, 'the FULL doc1 2.5.6 program is #572 scope — must be cross-referenced');
    assert.match(MIG, /NOTIFY pgrst, 'reload schema';/);
  });
});

describe('p569-s3 — 1. claim lease', () => {
  it('adds the claimed_at lease column (idempotent) + comment', () => {
    assert.match(MIG, /ALTER TABLE public\.pi_exclusion_assets\s+ADD COLUMN IF NOT EXISTS claimed_at timestamptz;/);
    assert.match(MIG, /COMMENT ON COLUMN public\.pi_exclusion_assets\.claimed_at/);
  });

  it('claim keeps the Slice-1 signature (p_limit integer DEFAULT 50 → jsonb, SECDEF)', () => {
    assert.match(MIG, /CREATE OR REPLACE FUNCTION public\._ots_claim_unstamped_assets\(p_limit integer DEFAULT 50\)\s+RETURNS jsonb/);
  });

  it('claim is an UPDATE-based lease with FOR UPDATE SKIP LOCKED + 10-minute window', () => {
    assert.ok(CLAIM_BODY.length > 0, 'claim body captured');
    assert.match(CLAIM_BODY, /FOR UPDATE SKIP LOCKED/);
    assert.match(CLAIM_BODY, /UPDATE public\.pi_exclusion_assets a\s+SET claimed_at = now\(\)/);
    assert.match(CLAIM_BODY, /claimed_at IS NULL OR claimed_at < now\(\) - interval '10 minutes'/);
  });

  it('claim preserves the Slice-1 eligibility filter (unstamped + attempts < 5, ordered by created_at)', () => {
    assert.match(CLAIM_BODY, /ots_status = 'unstamped'/);
    assert.match(CLAIM_BODY, /stamp_attempts < 5/);
    assert.match(CLAIM_BODY, /ORDER BY created_at/);
  });

  it('forward-defense: the claim is NOT a bare SELECT (the lease must mutate state)', () => {
    // A SELECT-only claim regresses to the double-claim race (#569 S3 rationale).
    assert.match(CLAIM_BODY, /UPDATE public\.pi_exclusion_assets/,
      'claim must persist the lease via UPDATE — a row lock alone dies with the RPC transaction');
  });
});

describe('p569-s3 — 2. retention pass', () => {
  it('defaults to the 5-year window and enforces the 1-year safety floor', () => {
    assert.match(MIG, /_ots_retention_pass\(p_retention interval DEFAULT interval '5 years'\)/);
    assert.match(RETENTION_BODY, /p_retention < interval '1 year'/);
    assert.match(RETENTION_BODY, /safety floor/);
  });

  it("purges ONLY revoked declarations past the window (both DELETE legs gate on status = 'revoked')", () => {
    const revokedGates = RETENTION_BODY.match(/d\.status = 'revoked'/g) || [];
    assert.ok(revokedGates.length >= 2, `both DELETE legs gate on revoked (found ${revokedGates.length})`);
    const windowGates = RETENTION_BODY.match(/d\.updated_at < now\(\) - p_retention/g) || [];
    assert.ok(windowGates.length >= 2, `both DELETE legs apply the window (found ${windowGates.length})`);
  });

  it("forward-defense: never deletes by ots_status — 'error' assets of active declarations are declarant data", () => {
    assert.ok(!/ots_status\s*=\s*'error'/.test(RETENTION_BODY.replace(/--[^\n]*/g, '')),
      "no DELETE leg may target ots_status='error' (export_anexo_i surfaces them; deletion = silent data loss)");
  });

  it('is service_role-only (REVOKE PUBLIC/anon/authenticated)', () => {
    assert.match(MIG, /REVOKE EXECUTE ON FUNCTION public\._ots_retention_pass\(interval\) FROM PUBLIC, anon, authenticated;/);
    assert.match(MIG, /GRANT {2}EXECUTE ON FUNCTION public\._ots_retention_pass\(interval\) TO service_role;/);
  });
});

describe('p569-s3 — 3. pipeline health', () => {
  it('gates on view_internal_analytics via can_by_member (lgpd-cron-health mould)', () => {
    assert.match(HEALTH_BODY, /can_by_member\(v_caller_member_id, 'view_internal_analytics'\)/);
    assert.match(HEALTH_BODY, /Not authenticated/);
    assert.match(HEALTH_BODY, /Not authorized: requires view_internal_analytics/);
  });

  it('surfaces the retry-exhausted class (stamp_attempts >= 5 falls out of the claim silently)', () => {
    assert.match(HEALTH_BODY, /ots_status = 'unstamped' AND stamp_attempts >= 5/);
    assert.match(HEALTH_BODY, /'exhausted_unstamped_attempts_ge_5'/);
  });

  it('snapshots exactly the 3 Slice-3 cron jobs', () => {
    assert.match(HEALTH_BODY, /'ots-stamp-daily', 'ots-upgrade-daily', 'ots-retention-monthly'/);
  });

  it('health signal: exhausted/failed/stale-with-backlog are red; pre-first-fire idle is yellow', () => {
    assert.match(HEALTH_BODY, /WHEN v_exhausted > 0 THEN 'red'/);
    assert.match(HEALTH_BODY, /WHEN v_failed_runs > 0 THEN 'red'/);
    assert.match(HEALTH_BODY, /WHEN v_backlog > 0 AND v_stale_days > 2 THEN 'red'/);
    assert.match(HEALTH_BODY, /WHEN v_backlog = 0 AND v_stale_days = 999 THEN 'yellow'/);
  });

  it('ACL: anon revoked, authenticated granted (gate lives inside the body)', () => {
    assert.match(MIG, /REVOKE ALL ON FUNCTION public\.get_ots_pipeline_health\(\) FROM PUBLIC, anon;/);
    assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\.get_ots_pipeline_health\(\) TO authenticated;/);
  });
});

describe('p569-s3 — 4. cron jobs', () => {
  it('schedules the 3 jobs with idempotent unschedule guards', () => {
    for (const job of ['ots-stamp-daily', 'ots-upgrade-daily', 'ots-retention-monthly']) {
      assert.match(MIG, new RegExp(`SELECT cron\\.unschedule\\('${job}'\\)\\s+WHERE EXISTS \\(SELECT 1 FROM cron\\.job WHERE jobname = '${job}'\\);`));
      assert.match(MIG, new RegExp(`cron\\.schedule\\(\\s+'${job}',`));
    }
  });

  it('stamp and upgrade are NON-OVERLAPPING (02:10 vs 02:40 UTC) — single-consumer discipline', () => {
    assert.match(MIG, /'ots-stamp-daily',\s+'10 2 \* \* \*'/);
    assert.match(MIG, /'ots-upgrade-daily',\s+'40 2 \* \* \*'/);
    assert.match(MIG, /'ots-retention-monthly',\s+'30 5 1 \* \*'/);
  });

  it('EF jobs authenticate with the DEDICATED vault secret ots_cron_secret', () => {
    const hits = MIG.match(/vault\.decrypted_secrets WHERE name = 'ots_cron_secret'/g) || [];
    assert.equal(hits.length, 2, 'both net.http_post jobs read ots_cron_secret from vault');
  });

  it("forward-defense (#618): cron blocks must NOT use the vault 'service_role_key' (stale vs EF-injected)", () => {
    assert.ok(!/name = 'service_role_key'/.test(MIG),
      'the vault service_role_key copy 403s against the OTS EF exact-match gate — proven live 2026-06-10');
  });

  it('retention job calls the SQL function directly (no EF hop)', () => {
    assert.match(MIG, /'SELECT public\._ots_retention_pass\(\);'/);
  });
});

describe('p569-s3 — EF gate widening (fail-closed)', () => {
  for (const [name, src] of [['ots-stamp', EF_STAMP], ['ots-upgrade', EF_UPGRADE]]) {
    it(`${name}: accepts service-role OR the dedicated cron secret, FAIL-CLOSED on unset secret`, () => {
      assert.match(src, /const cronSecret = Deno\.env\.get\("OTS_CRON_SECRET"\) \?\? "";/);
      assert.match(src, /const authorized = tokenMatches\(token, serviceRoleKey\) \|\| tokenMatches\(token, cronSecret\);/,
        'both legs go through the constant-time comparator');
      assert.match(src, /if \(secret\.length === 0 \|\| token\.length !== secret\.length\) return false;/,
        'fail-closed: an unset secret never matches (contrast: backup-to-r2 broken-open gate, #618)');
      assert.match(src, /timingSafeEqual\(Buffer\.from\(token\), Buffer\.from\(secret\)\)/,
        'constant-time equality (council security MEDIUM): plain === short-circuits = timing oracle');
      assert.match(src, /if \(!authorized\) return jsonResponse\(\{ success: false, error: "Forbidden: service-role or cron-secret only" \}, 403\);/);
      assert.match(src, /if \(!token\) return jsonResponse\(\{ success: false, error: "Unauthorized" \}, 401\);/);
    });
  }
});

describe('p569-s3 — MCP tool', () => {
  it('get_ots_pipeline_health registered with the standard logUsage pattern', () => {
    assert.match(MCP_INDEX, /mcp\.tool\("get_ots_pipeline_health",/);
    assert.match(MCP_INDEX, /sb\.rpc\("get_ots_pipeline_health"\)/);
    const block = MCP_INDEX.split('mcp.tool("get_ots_pipeline_health"')[1]?.split('mcp.tool(')[0] ?? '';
    assert.match(block, /logUsage\(sb, null, "get_ots_pipeline_health", false, "Not authenticated", start\)/);
    assert.match(block, /logUsage\(sb, member\.id, "get_ots_pipeline_health", true, undefined, start\)/);
  });

  it('tool description teaches the #618 lesson (cron succeeded != EF 200)', () => {
    assert.match(MCP_INDEX, /pg_cron 'succeeded' does not imply the EF call returned 200 \(#618\)/);
  });
});

describe('p569-s3 — DB-gated (skip without env)', () => {
  it('live bodies match the migration file byte-for-byte (Phase-C normalized md5, all 3 fns)', { skip: !sb }, async () => {
    // Same normalizer as the SQL side: md5(regexp_replace(prosrc, '\s+', ' ', 'g')) — NO trim.
    const { createHash } = await import('node:crypto');
    const localMd5 = (body) => createHash('md5').update(body.replace(/\s+/g, ' ')).digest('hex');
    const expected = {
      _ots_claim_unstamped_assets: localMd5(CLAIM_BODY),
      _ots_retention_pass: localMd5(RETENTION_BODY),
      get_ots_pipeline_health: localMd5(HEALTH_BODY),
    };
    const { data, error } = await sb.rpc('_audit_list_public_function_bodies');
    if (error) { console.warn(`[p569-s3] helper unavailable: ${error.message}`); return; }
    const rows = Array.isArray(data) ? data : [];
    for (const [name, md5] of Object.entries(expected)) {
      const fn = rows.find((f) => f.proname === name);
      assert.ok(fn, `${name} exists live`);
      assert.equal(fn.is_secdef, true, `${name} is SECURITY DEFINER`);
      assert.equal(fn.body_md5, md5,
        `${name} live body drifted from the migration file (apply_migration comment-strip? see SEDIMENT-246.B)`);
    }
  });

  it('migration 20260805000136 registered in schema_migrations (no wall-clock shadow)', { skip: !sb }, async () => {
    const { data, error } = await sb.rpc('_audit_list_schema_migrations');
    if (error) { console.warn(`[p569-s3] helper unavailable: ${error.message}`); return; }
    const rows = data.filter((r) => r.name === 'p569_s3_ots_cron_lease_retention_health');
    assert.equal(rows.length, 1, 'exactly one registration (shadow row deleted per GC-097 ritual)');
    assert.equal(rows[0].version, '20260805000136');
  });

  it('pi_exclusion_assets.claimed_at column reachable (service-role PostgREST probe)', { skip: !sb }, async () => {
    const { error } = await sb.from('pi_exclusion_assets').select('id, claimed_at').limit(0);
    assert.equal(error, null, `claimed_at column probe failed: ${error?.message}`);
  });
});
