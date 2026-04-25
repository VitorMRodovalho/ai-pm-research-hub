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
  // Split on CREATE [OR REPLACE] FUNCTION boundaries. Captures any tagged
  // dollar-quote delimiter via back-reference: $$, $function$, $fn$, $body$, etc.
  // The header group (m[3]) covers RETURNS / LANGUAGE / SECURITY DEFINER / SET
  // search_path so callers can inspect SECURITY DEFINER inline without a
  // secondary scan that may match the wrong slice.
  const regex = /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+([a-z_.]+)\s*\(([\s\S]*?)\)\s*RETURNS\s+([\s\S]*?)\s+AS\s+\$(\w*)\$([\s\S]*?)\$\4\$/gi;
  const out = [];
  let m;
  while ((m = regex.exec(sql)) !== null) {
    out.push({ name: m[1], args: m[2].trim(), header: m[3], body: m[5] });
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
  return /\bpublic\.can\s*\(/i.test(body)
      || /\bpublic\.can_by_member\s*\(/i.test(body)
      || /\bcan_by_member\s*\(/i.test(body)
      || /\brls_can\s*\(/i.test(body)
      || /[^\w]can\s*\(\s*auth\.uid/i.test(body)
      || /[^\w]can\s*\(\s*\w+\s*,\s*['"]/i.test(body)  // can(person_id_var, 'action', ...)
      || /\bpublic\._can_\w+\s*\(/i.test(body)  // V4 helpers (e.g., _can_sign_gate)
      || /[^\w]_can_\w+\s*\(/i.test(body);
}

// V3 hardcoded role-based authority — what ADR-0011 forbids in new RPCs.
// A function violates ADR-0011 when it gates auth using role-list logic
// (operational_role / is_superadmin / designations) in an IF/THEN authority
// branch or in a caller-lookup WHERE clause, regardless of whether the role
// reference goes through a local var alias (v_role, v_is_admin) or directly.
// Pure data filters (`m.operational_role NOT IN (...)` inside a SELECT used
// for aggregation) are not flagged.
const HARDCODED_ROLE_NAMES_RE =
  /['"](?:manager|deputy_manager|tribe_leader|sponsor|chapter_liaison|co_gp|chapter_board|curator|external_signer|alumni|observer|chapter_president|chapter_vice_president|chapter_secretary|chapter_treasurer)['"]/i;
function usesV3RoleAuthority(body) {
  // Collect local var aliases assigned from role expressions:
  //   v_is_gp := v_caller.is_superadmin OR v_caller.operational_role IN ('manager', ...)
  //   v_role := operational_role
  // Any IF block referencing such an alias is treated as a role-authority gate.
  const roleAliases = new Set();
  const assignmentRegex = /\b(v_[a-z_]+)\s*(?::=)\s*([^;]{1,800})/gi;
  let am;
  while ((am = assignmentRegex.exec(body)) !== null) {
    const expr = am[2];
    if (/\boperational_role\b/i.test(expr)
        || /\bdesignations\s*&&/i.test(expr)
        || /\bis_superadmin\b/i.test(expr)
        || HARDCODED_ROLE_NAMES_RE.test(expr)) {
      roleAliases.add(am[1]);
    }
  }
  // SELECT INTO local var bindings of role columns:
  //   SELECT id, operational_role, is_superadmin INTO v_id, v_role, v_admin
  const intoRegex = /SELECT[\s\S]{0,400}?\bINTO\b\s+([^;]+?)(?:\s+FROM\b|;)/gi;
  let im;
  while ((im = intoRegex.exec(body)) !== null) {
    const before = body.slice(Math.max(0, im.index), im.index + im[0].length);
    if (/\boperational_role\b/i.test(before) || /\bis_superadmin\b/i.test(before)) {
      const targets = im[1].split(/\s*,\s*/).map(s => s.trim()).filter(s => /^v_[a-z_]+$/i.test(s));
      for (const t of targets) roleAliases.add(t);
    }
  }

  // (1) IF ... THEN authority blocks — anchored to statement boundary so the
  // closing `IF` of `END IF;` does not match as a new block opening.
  const ifThenBlocks = body.match(/(?:^|[;\n])\s*IF\b[\s\S]{0,1500}?\bTHEN\b/gi) || [];
  for (const block of ifThenBlocks) {
    if (/\boperational_role\s+(?:NOT\s+)?(?:IN|=)\s*[\(\x27]/i.test(block)) return true;
    if (/\bdesignations\s*&&\s*ARRAY/i.test(block)) return true;
    if (/\bis_superadmin\b/i.test(block)) return true;
    if (HARDCODED_ROLE_NAMES_RE.test(block) && /\b(?:IN|=|<>|!=)\s*[\(\x27]/i.test(block)) return true;
    for (const alias of roleAliases) {
      if (new RegExp(`\\b${alias}\\b`).test(block)) return true;
    }
  }
  // (2) caller-lookup WHERE clauses with embedded role check (single statement
  // — must not cross `;`, otherwise unrelated SELECT counts get false-flagged)
  if (/WHERE[^;]{0,200}auth_id\s*=\s*auth\.uid\(\)[^;]{0,400}(is_superadmin|operational_role\s+(?:NOT\s+)?IN|designations\s*&&)/i.test(body)) {
    return true;
  }
  return false;
}

function isSecurityDefiner(header) {
  return /SECURITY\s+DEFINER/i.test(header);
}

// Track Q-A orphan-recovery + Q-B drift-correction migrations (p52, 2026-04-25)
// — these capture the LIVE body of functions that previously had no migration
// (Q-A orphans) or whose live body diverged from the latest migration capture
// (Q-B drift). By design both preserve the existing legacy V3 authority gates
// verbatim (rule: capture-only, no behavior change). The drift-to-V4 work
// for these functions is Phase B' of the audit. Skip them here so they don't
// get double-flagged — the violations are already documented in their
// migration headers and in docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md.
const Q_AUDIT_CAPTURE_FILE_RE = /qa_orphan_recovery_|qb_drift_correction_/;

test('ADR-0011: new migrations (20260424+) — every SECURITY DEFINER RPC with auth gate calls can*', () => {
  const files = readdirSync(MIGRATIONS_DIR)
    .filter(f => f.endsWith('.sql') && f >= CUTOVER_FILENAME)
    .filter(f => !Q_AUDIT_CAPTURE_FILE_RE.test(f))
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
      if (!isSecurityDefiner(fn.header)) continue;
      rpcLatest.set(fn.name, { file: f, args: fn.args, body: fn.body });
    }
  }

  const violations = [];
  for (const [name, { file, args, body }] of rpcLatest.entries()) {
    if (!hasAuthGate(body)) continue;
    if (V4_AUTH_INFRASTRUCTURE_ALLOWLIST.has(name)) continue;
    if (!usesV3RoleAuthority(body)) continue;  // baseline-auth-only RPCs are not violations
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
