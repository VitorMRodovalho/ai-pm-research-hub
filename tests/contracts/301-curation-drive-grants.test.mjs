// #301 / ADR-0108 — Temporary governed Drive access for curation (GRANT mirror of #209).
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

const tableMig = read(join(MIG_DIR, '20260805000265_301_curation_drive_grants_table.sql'));
const wireMig  = read(join(MIG_DIR, '20260805000266_301_curation_drive_grants_enqueue_triggers.sql'));
const rpcMig   = read(join(MIG_DIR, '20260805000267_301_curation_drive_grants_rpcs.sql'));
const invMig   = read(join(MIG_DIR, '20260805000268_301_invariant_AM_curation_drive_grants.sql'));
const cronMig  = read(join(MIG_DIR, '20260805000269_301_curation_drive_grants_crons.sql'));
const grantEf  = read(join(FN_DIR, 'manage-curation-drive-grant/index.ts'));
const driveSa  = read(join(FN_DIR, '_shared/drive-sa.ts'));
const mcpIndex = read(join(FN_DIR, 'nucleo-mcp/index.ts'));

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const client = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

// ───────────────────────── Static: table ─────────────────────────
test('#301: drive_curation_grants table declares core + acceptance columns', () => {
  assert.match(tableMig, /CREATE TABLE IF NOT EXISTS public\.drive_curation_grants/);
  for (const col of ['board_item_id', 'drive_file_id', 'drive_file_url', 'revision_id', 'grantee_member_id',
                     'permission_email', 'permission_id', 'role', 'grant_reason', 'status', 'api_error',
                     'granted_at', 'revoked_at']) {
    assert.match(tableMig, new RegExp(`\\b${col}\\b`), `missing column ${col}`);
  }
  assert.match(tableMig, /permission_email\s+citext NOT NULL/, 'permission_email must be citext NOT NULL (PII)');
  assert.match(tableMig, /board_item_id\s+uuid NOT NULL REFERENCES public\.board_items\(id\)/);
  assert.match(tableMig, /grantee_member_id\s+uuid NOT NULL REFERENCES public\.members\(id\)/);
});

test('#301: status CHECK domain is the 7 lifecycle states', () => {
  assert.match(tableMig, /status\s+text NOT NULL DEFAULT 'pending_grant'/);
  for (const s of ['pending_grant', 'granted', 'failed', 'pending_revoke', 'revoked', 'revoke_failed', 'cancelled']) {
    assert.match(tableMig, new RegExp(`'${s}'`), `CHECK missing status ${s}`);
  }
  assert.match(tableMig, /role\s+text NOT NULL DEFAULT 'commenter'/, 'least-privilege default role = commenter');
});

test('#301: idempotency partial-unique on (drive_file_id, permission_email) WHERE active', () => {
  assert.match(
    tableMig,
    /CREATE UNIQUE INDEX[\s\S]*?drive_curation_grants\s*\(drive_file_id,\s*permission_email\)\s*WHERE status IN \('pending_grant','granted','pending_revoke'\)/,
    'partial unique index (dup-prevention contract) missing or wrong predicate',
  );
});

test('#301: LGPD fail-closed — RLS on + deny-all + REVOKE anon/authenticated', () => {
  assert.match(tableMig, /ALTER TABLE public\.drive_curation_grants ENABLE ROW LEVEL SECURITY/);
  assert.match(tableMig, /CREATE POLICY drive_curation_grants_deny_all[\s\S]*USING \(false\) WITH CHECK \(false\)/);
  assert.match(tableMig, /REVOKE ALL ON public\.drive_curation_grants FROM anon, authenticated/);
});

// ───────────────────────── Static: enqueue + triggers ─────────────────────────
test('#301: FSM trigger on board_items.curation_status enqueues grant on entry, revoke on exit', () => {
  assert.match(wireMig, /AFTER UPDATE OF curation_status ON public\.board_items/);
  assert.match(wireMig, /enqueue_curation_drive_grants/);
  assert.match(wireMig, /enqueue_curation_drive_revokes/);
  // entry → curation_pending grants the committee; exit cancels never-executed + queues revoke
  assert.match(wireMig, /NEW\.curation_status = 'curation_pending'/);
  assert.match(wireMig, /'cancelled'/);
});

test('#301: enqueue grants the curate_content committee (V4 Path 1, no seed expansion)', () => {
  assert.match(wireMig, /can_by_member\(m\.id, 'curate_content'\)/);
  assert.match(wireMig, /'committee_handoff'/);
  assert.match(wireMig, /'reviewer_assignment'/);
});

test('#301: assign_curation_reviewer re-create carries the full body + reviewer enqueue', () => {
  // full-body re-create (body-hash drift gate) keeps the prior guards
  assert.match(wireMig, /CREATE OR REPLACE FUNCTION public\.assign_curation_reviewer/);
  assert.match(wireMig, /participate_in_governance_review/);
  assert.match(wireMig, /rls_can_see_board/);
  // the #301 addition
  assert.match(wireMig, /enqueue_curation_drive_grant_for_member\(p_item_id, p_reviewer_id, 'reviewer_assignment'\)/);
});

// ───────────────────────── Static: RPCs ─────────────────────────
test('#301: status RPC gates curate_content OR manage_platform + #785 confidential carve-out', () => {
  const body = rpcMig.slice(rpcMig.indexOf('FUNCTION public.get_board_item_drive_access'));
  assert.match(body.slice(0, 1500), /can_by_member\(v_caller\.id, 'curate_content'\)/);
  assert.match(body.slice(0, 1500), /can_by_member\(v_caller\.id, 'manage_platform'\)/);
  assert.match(body.slice(0, 2500), /rls_can_see_board\(v_item\.board_id\)/);
  // surfaces the #201/#190 envelope
  assert.match(body.slice(0, 4000), /drive_permission_status/);
  assert.match(body.slice(0, 4000), /missing_drive_access/);
});

test('#301: GP RPCs gate manage_platform', () => {
  for (const fn of ['admin_list_curation_drive_grants', 'force_grant_curation_drive_access', 'force_revoke_curation_drive_access']) {
    const body = rpcMig.slice(rpcMig.indexOf(`FUNCTION public.${fn}`));
    assert.match(body.slice(0, 900), /can_by_member\(v_caller_id, 'manage_platform'\)/, `${fn} missing manage_platform gate`);
  }
});

test('#301: EF-facing RPCs gate to service_role (NULL-safe IS DISTINCT FROM)', () => {
  for (const fn of ['get_curation_grant_row', 'mark_curation_grant_done', 'mark_curation_grant_revoked']) {
    const body = rpcMig.slice(rpcMig.indexOf(`FUNCTION public.${fn}`));
    assert.match(body.slice(0, 600), /current_caller_role\(\) IS DISTINCT FROM 'service_role'/, `${fn} missing NULL-safe service-role gate`);
  }
  assert.match(rpcMig, /GRANT\s+EXECUTE ON FUNCTION public\.mark_curation_grant_done\(uuid,text,text,jsonb\) TO service_role/);
  assert.match(rpcMig, /REVOKE ALL ON FUNCTION public\.get_curation_grant_row\(uuid\) FROM PUBLIC, anon, authenticated/);
});

test('#301: grant success logs admin_audit_log; PII read logs pii_access', () => {
  assert.match(rpcMig, /'drive_curation_grant_created'/);
  assert.match(rpcMig, /'drive_curation_grant_revoked'/);
  assert.match(rpcMig, /log_pii_access_batch/);
});

// ───────────────────────── Static: invariant ─────────────────────────
test('#301: invariant AM present in the check_schema_invariants rebuild (carries AL + AK)', () => {
  assert.match(invMig, /'AM_drive_curation_grant_terminal_consistency'/);
  assert.match(invMig, /CREATE OR REPLACE FUNCTION public\.check_schema_invariants\(\)/);
  // rebuild must still carry the prior latest (AL + AK) — guards against a truncated body
  assert.match(invMig, /'AL_drive_revocation_terminal_consistency'/);
  assert.match(invMig, /'AK_voice_biometric_consent_enforcement'/);
});

// ───────────────────────── Static: Edge Function + shared module ─────────────────────────
test('#301: grant EF fail-safe on missing SA creds (503) + verify service-role caller', () => {
  assert.match(grantEf, /drive_integration_not_configured/);
  assert.match(grantEf, /status:\s*503/);
  assert.match(grantEf, /isServiceRoleToken/);
  assert.match(grantEf, /status:\s*401/);
});

test('#301: grant EF creates (POST) and revokes (DELETE), handles out-of-domain notify', () => {
  assert.match(grantEf, /method:\s*"POST"/);
  assert.match(grantEf, /\/permissions/);
  assert.match(grantEf, /method:\s*"DELETE"/);
  assert.match(grantEf, /sendNotificationEmail/);
  assert.match(grantEf, /role:\s*row\.role/);
  assert.match(grantEf, /action === "grant"/);
  // grant classifies success vs 403/400 fail-safe; revoke treats 404 as already-gone
  assert.match(grantEf, /"granted"/);
  assert.match(grantEf, /"revoke_failed"/);
});

test('#301: shared drive-sa.ts exports the SA auth helpers reused from #209', () => {
  assert.match(driveSa, /export const DRIVE_WRITE_SCOPE/);
  assert.match(driveSa, /export async function getServiceAccountKey/);
  assert.match(driveSa, /export async function getAccessToken/);
  assert.match(driveSa, /export function bearerFrom/);
  assert.match(grantEf, /from "\.\.\/_shared\/drive-sa\.ts"/);
});

// ───────────────────────── Static: MCP + crons ─────────────────────────
test('#301: 3 MCP tools registered + /health tools count bumped to 314 (now 317 via #1099)', () => {
  for (const t of ['list_curation_drive_grants', 'force_grant_curation_drive_access', 'force_revoke_curation_drive_access']) {
    assert.match(mcpIndex, new RegExp(`mcp\\.tool\\("${t}"`), `tool ${t} not registered`);
  }
  assert.match(mcpIndex, /"\/mcp":\s*\{[^}]*tools:\s*317/);
  // force tools invoke the grant/revoke EF synchronously
  assert.match(mcpIndex, /functions\/v1\/manage-curation-drive-grant/);
});

test('#301: crons scheduled (grant-drain, revoke-drain, ttl), idempotent by name', () => {
  assert.match(cronMig, /cron\.schedule\(\s*\n?\s*'curation-grant-drain'/);
  assert.match(cronMig, /cron\.schedule\(\s*\n?\s*'curation-revoke-drain'/);
  assert.match(cronMig, /cron\.schedule\(\s*\n?\s*'curation-grant-ttl-expiry'/);
  assert.match(cronMig, /functions\/v1\/manage-curation-drive-grant/);
});

// ───────────────────────── DB-gated: behavior ─────────────────────────
test('#301 DB: get_board_item_drive_access fail-closes without an authenticated member',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    const { error } = await sb.rpc('get_board_item_drive_access', { p_board_item_id: '00000000-0000-0000-0000-000000000000' });
    assert.ok(error, 'expected a fail-closed error (service-role has no auth.uid())');
    assert.match(error.message, /Not authenticated|Unauthorized/);
  });

test('#301 DB: get_curation_grant_row accepts the legitimate service-role caller (null for unknown id)',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    const { data, error } = await sb.rpc('get_curation_grant_row', { p_grant_id: '00000000-0000-0000-0000-000000000000' });
    assert.ifError(error); // both-sides discipline: legitimate caller accepted
    assert.equal(data, null);
  });

test('#301 DB: invariant AM is present and reports 0 violations',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    const { data, error } = await sb.rpc('check_schema_invariants');
    assert.ifError(error);
    const am = (data ?? []).find((r) => r.invariant_name === 'AM_drive_curation_grant_terminal_consistency');
    assert.ok(am, 'AM invariant missing from check_schema_invariants output');
    assert.equal(am.violation_count, 0, 'AM must baseline at 0 violations');
  });

test('#301 DB: partial-unique index rejects a duplicate active (pending_grant) grant',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = client();
    const { data: item } = await sb.from('board_items').select('id').limit(1).maybeSingle();
    const { data: member } = await sb.from('members').select('id').limit(1).maybeSingle();
    const { data: org } = await sb.from('organizations').select('id').limit(1).maybeSingle();
    assert.ok(item?.id && member?.id && org?.id, 'need a board_item + member + organization to exercise the index');
    const fileId = 'test_301_file_' + Date.now();
    const row = {
      organization_id: org.id, board_item_id: item.id, grantee_member_id: member.id,
      drive_file_id: fileId, permission_email: 'idempotency-probe-301@example.com', status: 'pending_grant',
    };
    try {
      const first = await sb.from('drive_curation_grants').insert(row);
      assert.ifError(first.error);
      const dup = await sb.from('drive_curation_grants').insert(row);
      assert.ok(dup.error, 'duplicate active grant must be rejected by the partial unique index');
      assert.equal(dup.error.code, '23505', `expected unique_violation 23505, got ${dup.error?.code}`);
    } finally {
      await sb.from('drive_curation_grants').delete().eq('drive_file_id', fileId);
    }
  });
