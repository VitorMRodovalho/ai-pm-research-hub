/**
 * #1200 — the offboard reason category must reach member_offboarding_records.
 *
 * Root cause (2ª reincidência: T7 03/07, Débora 08/07): the MCP wrapper and the deployed EF both
 * propagate p_reason_category to admin_offboard_member correctly, but the record used to be written
 * only by trg_offboarding_stub (AFTER UPDATE OF member_status), which infers the category from
 * members.status_change_reason ('^[a-z_]+:\s' prefix) and lands on 'other' whenever a free-text
 * detail is passed — for EVERY caller, direct RPC included.
 *
 * Fix (mig 20260805000375): admin_offboard_member is the authoritative writer — it inserts the
 * record with the FK-validated caller category BEFORE the members UPDATE, so the trigger's EXISTS
 * guard skips its inference stub. Trigger stays as fallback for status changes that bypass the RPC.
 *
 * Static guards (offline) over the migration + EF wrapper source. Non-no-op: against the pre-#1200
 * bodies these fail — no INSERT INTO member_offboarding_records existed in admin_offboard_member.
 * The behavioral proof was run live via RAISE-rollback smoke (documented in the PR):
 *   BEFORE mig 375: offboard with 'end_of_cycle' + free detail → record 'other'
 *   AFTER  mig 375: same call → record 'end_of_cycle'; invalid category → 'other' (#449a, no crash)
 * Live==file is enforced by the Phase C body-drift gate.
 *
 * Cross-ref: #1200, #449a (never-crash stub), #1022 (offboard targets), mig 20260805000078 (trigger).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const R = (p) => { const f = join(__dirname, p); return existsSync(f) ? readFileSync(f, 'utf8') : ''; };

const MIG = R('../../supabase/migrations/20260805000375_1200_offboard_reason_category_authoritative_write.sql');
const EF = R('../../supabase/functions/nucleo-mcp/index.ts');
// executable SQL only (strip `-- ...` comment lines; the header narrates the old 'other' behavior).
const code = MIG.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');

test('#1200 migration exists and redefines admin_offboard_member in place (no signature change)', () => {
  assert.ok(MIG, 'migration file missing at expected path');
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.admin_offboard_member\(p_member_id uuid, p_new_status text, p_reason_category text, p_reason_detail text DEFAULT NULL::text, p_reassign_to uuid DEFAULT NULL::uuid\)/);
  assert.doesNotMatch(code, /DROP FUNCTION/i, 'signature is unchanged — must be CREATE OR REPLACE, not DROP+CREATE');
});

test('#1200 RPC writes the record itself with the FK-validated caller category (fallback other)', () => {
  assert.match(code, /SELECT code INTO v_reason_code FROM public\.offboard_reason_categories WHERE code = p_reason_category/,
    'category must be validated against offboard_reason_categories');
  assert.match(code, /v_reason_code := COALESCE\(v_reason_code, 'other'\)/,
    "#449a never-crash: invalid/unknown category falls back to 'other'");
  assert.match(code, /INSERT INTO public\.member_offboarding_records/,
    'the RPC must insert the offboarding record directly');
  assert.match(code, /ON CONFLICT \(member_id\) DO NOTHING/,
    'one-record-per-member, first-offboard-wins semantics (UNIQUE member_id) must be preserved');
});

test('#1200 record insert runs BEFORE the members UPDATE (trigger EXISTS guard must skip the stub)', () => {
  const insertAt = code.indexOf('INSERT INTO public.member_offboarding_records');
  const updateAt = code.indexOf('UPDATE public.members SET');
  assert.ok(insertAt > -1 && updateAt > -1, 'both statements must exist in the body');
  assert.ok(insertAt < updateAt,
    'the record insert must precede the members UPDATE, otherwise trg_offboarding_stub writes the inferred stub first');
});

test('#1200 trigger fallback stays intact — migration must not touch the stub path', () => {
  assert.doesNotMatch(code, /_offboarding_create_stub/,
    'the #449a inference stub must NOT be redefined here (it remains the fallback for non-RPC status changes)');
  assert.doesNotMatch(code, /DROP TRIGGER/i, 'trg_offboarding_stub must not be dropped');
});

test('#1200 MCP wrapper propagates reason_category to the RPC (no hardcode regression)', () => {
  assert.ok(EF, 'nucleo-mcp/index.ts missing at expected path');
  const call = EF.match(/sb\.rpc\("admin_offboard_member",\s*\{[\s\S]*?\}\)/);
  assert.ok(call, 'wrapper must dispatch via sb.rpc("admin_offboard_member", {...})');
  assert.match(call[0], /p_reason_category:\s*params\.reason_category/,
    'wrapper must pass the caller-supplied reason_category through');
  assert.doesNotMatch(call[0], /p_reason_category:\s*['"]/,
    'wrapper must not hardcode a reason_category literal');
});
