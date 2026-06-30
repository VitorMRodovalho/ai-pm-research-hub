/**
 * Contract: #572 Block A — institutional data portability (LGPD doc4 §6.4 / Parecer 01/2026 rec g).
 *
 * Full-DB institutional export for platform MIGRATION/SHUTDOWN — DISTINCT from the per-titular Art.18
 * export (export_my_data / #568). The bulk dump itself is pg_dump over the direct Postgres connection
 * (docs/operations/INSTITUTIONAL_EXPORT_RUNBOOK.md); migration 20260805000299 ships FOUR SECDEF RPCs:
 *
 *   1. generate_institutional_export_manifest(text,uuid,text) — pre-dump per-table SHA-256 integrity
 *      manifest + aggregate hash, mandatory justification (>=10 chars), 5/30d rate-limit, phase-1 audit.
 *   2. export_institutional_data_dictionary() — machine-readable schema dictionary (public + z_archive).
 *   3. export_redacted_settings() — site_config/platform_settings with _secret/_token/_key keys masked.
 *   4. register_institutional_export_completion(uuid,text,bigint,text) — phase-2 audit (dump sha256+bytes).
 *
 * Gate (all four): can_by_member(caller,'manage_platform') AND caller_chapter_scope() IS NULL = GP/sede.
 * NOT view_pii (held by chapter partners → cross-chapter leak; FU-2 closed it). ADR-0112.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000299_572_block_a_institutional_export_rpcs.sql');
const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const svcGated = !!(SUPABASE_URL && SERVICE_KEY);
const anonGated = !!(SUPABASE_URL && ANON_KEY);

const FNS = [
  'generate_institutional_export_manifest\\(text, uuid, text\\)',
  'export_institutional_data_dictionary\\(\\)',
  'export_redacted_settings\\(\\)',
  'register_institutional_export_completion\\(uuid, text, bigint, text\\)',
];

// ── STATIC: all four RPCs exist, are SECDEF, and pin search_path ───────────────────────────
test('#572A static: four SECDEF RPCs with pinned search_path', () => {
  assert.ok(existsSync(MIG), 'migration 299 exists');
  for (const fn of ['generate_institutional_export_manifest', 'export_institutional_data_dictionary',
                    'export_redacted_settings', 'register_institutional_export_completion']) {
    assert.match(body, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}\\(`), `${fn} defined`);
  }
  assert.equal((body.match(/SECURITY DEFINER/g) || []).length, 4, 'all four are SECURITY DEFINER');
  assert.equal((body.match(/SET search_path TO 'public'/g) || []).length, 4, 'all four pin search_path to public-first');
  // the dictionary additionally needs z_archive on the path
  assert.match(body, /SET search_path TO 'public', 'z_archive', 'pg_temp'/, 'dictionary covers z_archive');
});

// ── STATIC: gate = manage_platform AND caller_chapter_scope() IS NULL, on all four; NEVER view_pii ──
test('#572A static: GP/sede gate (manage_platform + chapter_scope NULL), never view_pii', () => {
  const gates = body.match(/can_by_member\(v_caller, 'manage_platform'\) AND public\.caller_chapter_scope\(\) IS NULL/g) || [];
  assert.equal(gates.length, 4, 'the GP/sede gate appears once per RPC');
  assert.doesNotMatch(body, /can_by_member\([^)]*'view_pii'/, 'must NOT gate on view_pii (chapter-partner leak)');
});

// ── STATIC: anti-open-relay grants on every function ────────────────────────────────────────
test('#572A static: REVOKE PUBLIC/anon + GRANT authenticated, service_role on all four', () => {
  for (const fn of FNS) {
    assert.match(body, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn} FROM PUBLIC;`), `${fn} revokes PUBLIC`);
    assert.match(body, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn} FROM anon;`), `${fn} revokes anon`);
    assert.match(body, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn} TO authenticated;`), `${fn} grants authenticated`);
    assert.match(body, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn} TO service_role;`), `${fn} grants service_role`);
  }
});

// ── STATIC: pgcrypto digest is ALWAYS schema-qualified (extensions.digest) ───────────────────
// Guards the bug where SET search_path 'public','pg_temp' cannot resolve a bare digest() (pgcrypto
// lives in the extensions schema). Every digest( call site MUST be extensions.digest(.
test('#572A static: every digest() is schema-qualified extensions.digest()', () => {
  const all = (body.match(/digest\(/g) || []).length;
  const qualified = (body.match(/extensions\.digest\(/g) || []).length;
  assert.ok(all > 0, 'manifest hashes via digest()');
  assert.equal(all, qualified, 'no bare digest() — all are extensions.digest()');
});

// ── STATIC: manifest accountability — mandatory justification + rate limit + phase-1 audit ──
test('#572A static: manifest enforces justification, rate-limit, and writes phase-1 audit', () => {
  assert.match(body, /length\(trim\(p_justification\)\) < 10/, 'justification must be >= 10 chars (RoPA Art.37)');
  assert.match(body, /RAISE EXCEPTION 'justification_required/, 'raises justification_required on a too-short reason');
  assert.match(body, /v_recent >= 5/, '5/30d rate-limit');
  assert.match(body, /interval '30 days'/, 'rate-limit window is 30 days');
  assert.match(body, /INSERT INTO public\.admin_audit_log[\s\S]*?'institutional_export\.manifest_generated'/, 'phase-1 audit row');
});

// ── STATIC: two-phase audit lifecycle; completion validates the manifest exists ──────────────
test('#572A static: completion is keyed to a prior manifest, single-receipt (two-phase audit)', () => {
  assert.match(body, /'institutional_export\.completed'/, 'phase-2 completed action');
  assert.match(body, /no_manifest_for_export_id/, 'completion fails if no manifest exists for the export_id');
  assert.match(body, /metadata->>'export_id' = p_export_id::text/, 'completion is matched by export_id');
  assert.match(body, /already_registered/, 'completion is idempotency-guarded — one receipt per export_id');
});

// ── STATIC: review-hardening fixes (adversarial review of the build) ─────────────────────────
test('#572A static: review fixes — null-safe dictionary, matview reporting, unanalyzed-table guard', () => {
  // constraints/columns are [] (not null) for matviews/constraint-less tables → machine-readable
  assert.match(body, /'constraints', \(\s*\n\s*SELECT coalesce\(jsonb_agg/, 'constraints subquery is COALESCE [] not null');
  assert.match(body, /'columns', \(\s*\n\s*SELECT coalesce\(jsonb_agg/, 'columns subquery is COALESCE [] not null');
  // matviews are reported (they are in the dictionary but not the per-table manifest)
  assert.match(body, /'excluded_matviews'/, 'manifest reports excluded matviews');
  // never-analyzed tables (reltuples=-1) fall back to count-only, not a full scan
  assert.match(body, /v_est < 0 OR v_est > v_threshold/, 'unanalyzed-table (reltuples<0) guard');
  // cron schema named excluded so a successor knows to recreate LGPD retention jobs
  assert.match(body, /'cron'/, "cron schema named in excluded_schemas");
});

// ── STATIC: secret redaction is the only export path for the two settings tables ─────────────
test('#572A static: settings secrets redacted; the two config tables are excluded from the dump', () => {
  assert.match(body, /\(_secret\|_token\|_key\|_password\|_passphrase\|_credential\)\$/, 'extended credential-pattern present');
  assert.match(body, /'"\[REDACTED\]"'::jsonb/, 'secret values masked to [REDACTED]');
  assert.match(body, /FROM public\.site_config/, 'site_config exported via the redacting RPC');
  assert.match(body, /FROM public\.platform_settings/, 'platform_settings exported via the redacting RPC');
});

// ── STATIC: exclusion list (derived/cache/external-sync + the two settings tables) ──────────
test('#572A static: manifest excludes derived/cache/external-sync table data + the settings tables', () => {
  // regular tables (relkind='r') whose DATA is dropped from the dump (matviews like cycle_tribe_dim are
  // excluded by the relkind='r' loop filter instead, reported via excluded_matviews — see review-fixes test)
  for (const t of ['preview_gate_eligibles_cache','wiki_pages','artia_status_reports',
                   'cron_run_log','site_config','platform_settings']) {
    assert.match(body, new RegExp(`'${t}'`), `excluded_table_data includes ${t}`);
  }
  // the absolute schema red lines must be named in the dictionary's excluded_schemas
  for (const s of ['auth','vault']) {
    assert.match(body, new RegExp(`'${s}'`), `excluded_schemas names ${s} (no password hashes / vault secrets in the dump)`);
  }
});

// ── STATIC: distinctness from the Art.18 individual export (#568) ────────────────────────────
test('#572A static: documented as institutional, DISTINCT from per-titular export_my_data (#568)', () => {
  assert.match(body, /distinct from the per-titular/i, 'comment marks the distinction from Art.18/#568');
  assert.match(body, /export_my_data/, 'references the per-titular precedent it is NOT replacing');
});

// ── DB (gated): anon is revoked from all four ────────────────────────────────────────────────
test('#572A DB: anon CANNOT execute any export RPC (revoke effective)', { skip: anonGated ? false : 'anon key required' }, async () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const calls = [
    ['generate_institutional_export_manifest', { p_justification: 'anon attempt — should be rejected by gate' }],
    ['export_institutional_data_dictionary', {}],
    ['export_redacted_settings', {}],
    ['register_institutional_export_completion', { p_export_id: '00000000-0000-0000-0000-000000000000', p_dump_sha256: 'x', p_dump_bytes: 1 }],
  ];
  for (const [fn, args] of calls) {
    const { error } = await anon.rpc(fn, args);
    assert.ok(error, `anon rejected from ${fn}`);
  }
});

// ── DB (gated): service_role has no auth.uid() → gate fail-closes (unauthorized), no dump ─────
test('#572A DB: service_role (no auth.uid) fail-closes on all four export RPCs', { skip: svcGated ? false : 'service key required' }, async () => {
  const svc = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  const calls = [
    ['generate_institutional_export_manifest', { p_justification: 'service-role attempt with no member identity' }],
    ['export_institutional_data_dictionary', {}],
    ['export_redacted_settings', {}],
    ['register_institutional_export_completion', { p_export_id: '00000000-0000-0000-0000-000000000000', p_dump_sha256: 'x', p_dump_bytes: 1 }],
  ];
  for (const [fn, args] of calls) {
    const { error } = await svc.rpc(fn, args);
    assert.ok(error, `${fn} fail-closes for a caller with no resolvable member (auth.uid() NULL)`);
  }
});
