// #209 / ADR-0107 — Drive permission revocation cascade on member offboarding.
// Static source assertions run offline; DB-gated behavioral assertions skip without
// SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (set in CI).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const MIG_DIR = resolve(process.cwd(), 'supabase/migrations');
const FN_DIR = resolve(process.cwd(), 'supabase/functions');
const read = (p) => readFileSync(p, 'utf8');

const tableMig = read(join(MIG_DIR, '20260805000261_209_drive_offboarding_audit_table.sql'));
const rpcMig = read(join(MIG_DIR, '20260805000262_209_drive_offboarding_rpcs.sql'));
const invMig = read(join(MIG_DIR, '20260805000263_209_invariant_AL_drive_revocation.sql'));
const cronMig = read(join(MIG_DIR, '20260805000264_209_drive_offboarding_crons.sql'));
const detEf = read(join(FN_DIR, 'audit-drive-offboarding-access/index.ts'));
const revEf = read(join(FN_DIR, 'revoke-drive-permission/index.ts'));
const mcpIndex = read(join(FN_DIR, 'nucleo-mcp/index.ts'));

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const client = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

// ───────────────────────── Static: table ─────────────────────────
test('#209: drive_offboarding_audit table declares core columns', () => {
  assert.match(tableMig, /CREATE TABLE IF NOT EXISTS public\.drive_offboarding_audit/);
  for (const col of ['organization_id', 'member_id', 'permission_id', 'permission_email', 'status', 'google_error', 'approved_by', 'revoked_at']) {
    assert.match(tableMig, new RegExp(`\\b${col}\\b`), `missing column ${col}`);
  }
  assert.match(tableMig, /permission_email\s+citext/, 'permission_email must be citext');
  assert.match(tableMig, /member_id\s+uuid NOT NULL REFERENCES public\.members\(id\)/);
});

test('#209: status CHECK domain is exactly the 6 lifecycle states', () => {
  assert.match(tableMig, /status\s+text NOT NULL DEFAULT 'pending_revoke'/);
  for (const s of ['pending_revoke', 'approved', 'revoked', 'failed', 'already_absent', 'skipped']) {
    assert.match(tableMig, new RegExp(`'${s}'`), `CHECK missing status ${s}`);
  }
});

test('#209: idempotency partial-unique index on (drive_file_id, permission_id) WHERE open', () => {
  assert.match(
    tableMig,
    /CREATE UNIQUE INDEX[\s\S]*?drive_offboarding_audit\s*\(drive_file_id,\s*permission_id\)\s*WHERE status IN \('pending_revoke','approved'\)/,
    'partial unique index (the dup-prevention contract) missing or wrong predicate',
  );
});

test('#209: LGPD fail-closed — RLS on + deny-all policy + REVOKE anon/authenticated', () => {
  assert.match(tableMig, /ALTER TABLE public\.drive_offboarding_audit ENABLE ROW LEVEL SECURITY/);
  assert.match(tableMig, /CREATE POLICY drive_offb_audit_deny_all[\s\S]*USING \(false\) WITH CHECK \(false\)/);
  assert.match(tableMig, /REVOKE ALL ON public\.drive_offboarding_audit FROM anon, authenticated/);
});

// ───────────────────────── Static: RPCs ─────────────────────────
test('#209: GP RPCs gate on can_by_member(manage_member)', () => {
  for (const fn of ['admin_list_drive_revocation_audit', 'approve_drive_revocation', 'bulk_approve_drive_revocations']) {
    const body = rpcMig.slice(rpcMig.indexOf(`FUNCTION public.${fn}`));
    assert.match(body.slice(0, 1200), /can_by_member\(v_caller_id, 'manage_member'\)/, `${fn} missing manage_member gate`);
  }
});

test('#209: EF-facing RPCs gate to service_role (NULL-safe IS DISTINCT FROM)', () => {
  for (const fn of ['get_offboarded_member_emails', 'upsert_drive_revocation_candidates', 'get_drive_revocation_row', 'mark_drive_revocation_done']) {
    const body = rpcMig.slice(rpcMig.indexOf(`FUNCTION public.${fn}`));
    assert.match(body.slice(0, 600), /current_caller_role\(\) IS DISTINCT FROM 'service_role'/, `${fn} missing NULL-safe service-role gate`);
  }
  // service-role RPCs must not be executable by authenticated/anon
  assert.match(rpcMig, /REVOKE ALL ON FUNCTION public\.get_offboarded_member_emails\(\) FROM PUBLIC, anon, authenticated/);
  assert.match(rpcMig, /GRANT\s+EXECUTE ON FUNCTION public\.upsert_drive_revocation_candidates\(jsonb\) TO service_role/);
});

test('#209: detection email read logs pii_access; success path logs admin_audit_log kind drive_permission_revoked', () => {
  assert.match(rpcMig, /INSERT INTO public\.pii_access_log[\s\S]*audit_drive_offboarding_access/);
  assert.match(rpcMig, /'drive_permission_revoked'/);
  assert.match(rpcMig, /'drive_permission_revocation_queued'/);
});

// ───────────────────────── Static: invariant ─────────────────────────
test('#209: invariant AL present in the check_schema_invariants rebuild', () => {
  assert.match(invMig, /'AL_drive_revocation_terminal_consistency'/);
  assert.match(invMig, /CREATE OR REPLACE FUNCTION public\.check_schema_invariants\(\)/);
  // the rebuild must still carry the prior latest (AK) — guards against a truncated body
  assert.match(invMig, /'AK_voice_biometric_consent_enforcement'/);
});

// ───────────────────────── Static: Edge Functions ─────────────────────────
test('#209: both EFs fail-safe on missing SA creds (503 not_configured) + verify service-role caller', () => {
  for (const ef of [detEf, revEf]) {
    assert.match(ef, /drive_integration_not_configured/);
    assert.match(ef, /status:\s*503/);
    assert.match(ef, /isServiceRoleToken/);
    assert.match(ef, /status:\s*401/);
  }
});

test('#209: detection EF uses full Shared-Drive read params + pagination (no truncation regression)', () => {
  assert.match(detEf, /includeItemsFromAllDrives/);
  assert.match(detEf, /supportsAllDrives/);
  assert.match(detEf, /corpora/);
  assert.match(detEf, /pageToken/);
  assert.match(detEf, /drive\.readonly/);
  // owner permissions are skipped (undeletable by the SA)
  assert.match(detEf, /role === "owner"/);
  // dry_run gate exists and writes nothing
  assert.match(detEf, /dry_run/);
});

test('#209: detection scales via folders-only query + parent dedup (no inherited-cascade explosion)', () => {
  // folders-only query bounds the fetch (a member shared on a top folder otherwise matches every
  // descendant FILE via inheritance — the 10k-row explosion).
  assert.match(detEf, /mimeType = 'application\/vnd\.google-apps\.folder'/);
  // parent dedup keeps only top-level DIRECT grants (drop a folder whose parent is also matched).
  assert.match(detEf, /matchedIds/);
  assert.match(detEf, /\.parents/);
});

test('#209: revoke EF uses write scope, acts only on approved, classifies 403/404 fail-safe', () => {
  assert.match(revEf, /auth\/drive"/); // full drive (write) scope
  assert.match(revEf, /row\.status !== "approved"/);
  assert.match(revEf, /httpStatus === 404/);
  assert.match(revEf, /"already_absent"/);
  assert.match(revEf, /"failed"/);
  assert.match(revEf, /method:\s*"DELETE"/);
});

// ───────────────────────── Static: MCP + crons ─────────────────────────
test('#209: 3 MCP tools registered + /health tools count bumped to 311 (now 323 via #1138)', () => {
  for (const t of ['list_drive_revocation_pending', 'approve_drive_revocation', 'bulk_approve_drive_revocations']) {
    assert.match(mcpIndex, new RegExp(`mcp\\.tool\\("${t}"`), `tool ${t} not registered`);
  }
  assert.match(mcpIndex, /"\/mcp":\s*\{[^}]*tools:\s*323/);
  // approve tools invoke the revoke EF synchronously
  assert.match(mcpIndex, /functions\/v1\/revoke-drive-permission/);
});

test('#209: crons scheduled (weekly detection + drain), idempotent by name', () => {
  assert.match(cronMig, /cron\.schedule\(\s*\n?\s*'audit-drive-offboarding-weekly',\s*\n?\s*'0 5 \* \* 1'/);
  assert.match(cronMig, /cron\.schedule\(\s*\n?\s*'revoke-drive-drain-hourly'/);
  assert.match(cronMig, /functions\/v1\/audit-drive-offboarding-access/);
  assert.match(cronMig, /functions\/v1\/revoke-drive-permission/);
});

// ───────────────────────── DB-gated: behavior ─────────────────────────
test('#209 DB: admin_list_drive_revocation_audit fail-closes without an authenticated member',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    const { error } = await sb.rpc('admin_list_drive_revocation_audit', { p_status: 'pending_revoke', p_member_id: null, p_limit: 10, p_offset: 0 });
    assert.ok(error, 'expected a fail-closed error (service-role has no auth.uid())');
    assert.match(error.message, /Not authenticated|Unauthorized/);
  });

test('#209 DB: get_drive_revocation_row accepts the legitimate service-role caller (returns null for unknown id)',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    const { data, error } = await sb.rpc('get_drive_revocation_row', { p_audit_id: '00000000-0000-0000-0000-000000000000' });
    assert.ifError(error); // service-role passes the gate (both-sides discipline: legitimate caller accepted)
    assert.equal(data, null);
  });

test('#209 DB: invariant AL is present and reports 0 violations',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    const { data, error } = await sb.rpc('check_schema_invariants');
    assert.ifError(error);
    const al = (data ?? []).find((r) => r.invariant_name === 'AL_drive_revocation_terminal_consistency');
    assert.ok(al, 'AL invariant missing from check_schema_invariants output');
    assert.equal(al.violation_count, 0, 'AL must baseline at 0 violations');
  });

test('#209 DB: partial-unique index rejects a duplicate open (pending_revoke) grant',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    const { data: member } = await sb.from('members').select('id').not('offboarded_at', 'is', null).limit(1).maybeSingle();
    const { data: org } = await sb.from('organizations').select('id').limit(1).maybeSingle();
    assert.ok(member?.id && org?.id, 'need an offboarded member + an organization to exercise the index');
    const fileId = 'test_209_file_' + Date.now();
    const permId = 'test_209_perm_' + Date.now();
    const row = {
      organization_id: org.id, member_id: member.id, drive_file_id: fileId, permission_id: permId,
      permission_email: 'idempotency-probe-209@example.com', status: 'pending_revoke',
    };
    try {
      const first = await sb.from('drive_offboarding_audit').insert(row);
      assert.ifError(first.error);
      const dup = await sb.from('drive_offboarding_audit').insert(row);
      assert.ok(dup.error, 'duplicate open grant must be rejected by the partial unique index');
      assert.equal(dup.error.code, '23505', `expected unique_violation 23505, got ${dup.error?.code}`);
    } finally {
      await sb.from('drive_offboarding_audit').delete().eq('drive_file_id', fileId);
    }
  });
