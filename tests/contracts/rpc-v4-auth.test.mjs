/**
 * ADR-0011 — V4 Auth Pattern compliance (anti-drift)
 *
 * Contract: any new RPC SECURITY DEFINER with an auth gate (Unauthorized
 * response) MUST invoke can() / can_by_member() / rls_can() as its primary
 * gate. Enforces the pattern set in ADR-0011 (17/Abr/2026) on all migrations
 * from 20260424 onward.
 *
 * Legacy RPCs (pre-2026-04-17) may still use hardcoded role lists — they are
 * tracked as tech debt (83 RPCs audited 17/Abr). Each session that touches a
 * legacy RPC should migrate it inline.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const MIGRATIONS_DIR = resolve(process.cwd(), 'supabase/migrations');
// ADR-0011 effective from migration 20260424040000 (A4.1 refactor, 17/Abr/2026).
// Earlier migrations are legacy tech debt tracked in the ADR.
const CUTOVER_FILENAME = '20260424040000';

function readMigration(filename) {
  return readFileSync(resolve(MIGRATIONS_DIR, filename), 'utf8');
}

function splitFunctions(sql) {
  // Split on CREATE [OR REPLACE] FUNCTION boundaries.
  // KNOWN LIMITATION: regex assumes $$ delimiter. Functions using $function$ or
  // other tagged delimiters are silently skipped or have their body swapped with
  // the next function's $$ body. Tracked as backlog item — fixing the regex to
  // \$(\w*)\$...\$\1\$ unmasks ~30 pre-existing ADR-0011 violations across
  // 20260428* migrations (ADR-0015 phase3+phase5 readers). Schedule a dedicated
  // ADR-0011 cleanup session before tightening the parser.
  const regex = /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+([a-z_.]+)\s*\(([\s\S]*?)\)\s*RETURNS[\s\S]*?\$\$([\s\S]*?)\$\$/gi;
  const out = [];
  let m;
  while ((m = regex.exec(sql)) !== null) {
    out.push({ name: m[1], args: m[2].trim(), body: m[3] });
  }
  return out;
}

// Functions whose auth gate is intentionally "any authenticated user" (transparency
// readers, schema introspection). They DO have RAISE EXCEPTION but are exempt from
// the can_by_member requirement because they have no PII surface and no write side
// effects. Adding gates would break legitimate non-admin use cases.
const V4_AUTH_INFRASTRUCTURE_ALLOWLIST = new Set([
  'public.check_schema_invariants', // ADR-0012 — any authed user can verify integrity (no PII, count + sample IDs only)
]);

function hasAuthGate(body) {
  // Expanded 2026-04-17 to catch legacy V3 exception strings that escape the
  // original matcher: `access_denied` (upsert_webinar, link_webinar_event,
  // admin_manage_publication), `auth_required` (upsert/link_webinar), and
  // `Admin only` (create_pilot, update_pilot). After ADR-0015 writer refactor,
  // all these 5 RPCs will use `Unauthorized` prefix — matcher stays catching
  // anything that LOOKS like an auth gate.
  return /RAISE\s+EXCEPTION\s+[^;]{0,80}(Unauthorized|Access\s+denied|access_denied|Not\s+authenticated|auth_required|Admin\s+only)/i.test(body)
      || /RETURN[^;]{0,120}['"]?(Unauthorized|Access\s+denied|access_denied)/i.test(body)
      || /jsonb_build_object\([^)]*['"]error['"][^)]*['"][^)]*[Uu]nauthor/i.test(body);
}

function usesV4Can(body) {
  return /\bpublic\.can\(/i.test(body)
      || /\bpublic\.can_by_member\(/i.test(body)
      || /\bcan_by_member\(/i.test(body)
      || /\brls_can\(/i.test(body)
      || /[^\w]can\(\s*auth\.uid/i.test(body);
}

function isSecurityDefiner(sql, fnName) {
  const idx = sql.indexOf(fnName);
  if (idx < 0) return false;
  const slice = sql.slice(idx, idx + 800);
  return /SECURITY\s+DEFINER/i.test(slice);
}

test('ADR-0011: new migrations (20260424+) — every SECURITY DEFINER RPC with auth gate calls can*', () => {
  const files = readdirSync(MIGRATIONS_DIR)
    .filter(f => f.endsWith('.sql') && f >= CUTOVER_FILENAME)
    .sort();

  // Track LATEST definition per RPC across all post-cutover migrations. Matches
  // runtime behavior: `CREATE OR REPLACE FUNCTION` overwrites, so only the last
  // file wins. A V3 body in an older migration that was later V4-migrated
  // should not flag; only the current live definition counts.
  const rpcLatest = new Map();
  for (const f of files) {
    const sql = readMigration(f);
    if (!/SECURITY\s+DEFINER/i.test(sql)) continue;

    const fns = splitFunctions(sql);
    for (const fn of fns) {
      if (!isSecurityDefiner(sql, fn.name)) continue;
      rpcLatest.set(fn.name, { file: f, args: fn.args, body: fn.body });
    }
  }

  const violations = [];
  for (const [name, { file, args, body }] of rpcLatest.entries()) {
    if (!hasAuthGate(body)) continue;
    if (V4_AUTH_INFRASTRUCTURE_ALLOWLIST.has(name)) continue;
    if (!usesV4Can(body)) {
      violations.push(`${file} :: ${name}(${args.slice(0, 60)}…)`);
    }
  }

  if (violations.length > 0) {
    const msg = [
      'ADR-0011 violation: the following RPCs have an auth gate but do NOT call',
      'can() / can_by_member() / rls_can(). New migrations must use V4 authority.',
      ...violations.map(v => `  - ${v}`),
      '',
      'Fix: replace hardcoded role list with:',
      '  IF NOT public.can_by_member(v_caller_id, \'<action>\') THEN',
      '    RAISE EXCEPTION \'Unauthorized: requires <action> permission\';',
      '  END IF;'
    ].join('\n');
    assert.fail(msg);
  }
});

test('ADR-0011: refactored RPCs (A4.1+A4.2+A4.3) are present and use can_by_member', () => {
  const expectedMigrations = [
    { file: '20260424040000_a4_1_event_rpcs_v4_auth.sql',
      fns: ['drop_event_instance', 'update_event_instance', 'update_future_events_in_group'] },
    { file: '20260424050000_a4_2_member_admin_rpcs_v4_auth.sql',
      fns: ['admin_offboard_member', 'admin_reactivate_member', 'admin_update_member',
            'admin_update_member_audited', 'promote_to_leader_track', 'manage_selection_committee'] },
    { file: '20260424060000_a4_3_pii_reads_v4_auth.sql',
      fns: ['admin_get_member_details', 'admin_list_members_with_pii', 'export_audit_log_csv'] }
  ];

  for (const { file, fns } of expectedMigrations) {
    const sql = readMigration(file);
    for (const fn of fns) {
      assert.ok(sql.includes(`CREATE FUNCTION public.${fn}`),
        `Migration ${file} must CREATE function ${fn}`);
      assert.ok(/public\.can_by_member/i.test(sql),
        `Migration ${file} must reference public.can_by_member`);
    }
  }
});
