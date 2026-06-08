/**
 * Contract: #568 — LGPD Art. 18 consent-record read surface (#564 council follow-up).
 *
 * consent_records was locked (rpc_only_deny_all) with the read RPCs deferred ("futuras") and never
 * created → export_my_data omitted consent history and there was no admin audit path. This migration
 * (20260805000130) adds:
 *   1. list_my_consents() — subject self-read (auth.uid()→member). Friendly fields, OMITS hashes,
 *      adds is_active = (revoked_at IS NULL).
 *   2. admin_list_member_consents(p_member_id) — view_pii-gated audit read WITH capture-evidence
 *      hashes; an explicit multi-tenant org fence (SECDEF bypasses the RESTRICTIVE org RLS, and
 *      can_by_member('view_pii') does not bound the TARGET → a cross-org read was possible); logs
 *      EVERY call (incl self) to pii_access_log (Art. 37 accountability).
 *   3. export_my_data() — adds 'consent_records' (explicit projection, not row_to_json) and FIXES a
 *      pre-existing latent bug: it referenced initiatives.name (V4 renamed to `title`) → the export
 *      RAISED "column i.name does not exist" for ANY member with engagements. Now i.title.
 *
 * Grant posture: new fns REVOKE FROM PUBLIC, anon + GRANT authenticated, service_role. export_my_data
 * is re-asserted to authenticated+service_role (anon dropped — CREATE OR REPLACE would otherwise let
 * the auto PUBLIC grant linger).
 *
 * Cross-ref: #568, #564/PR#565, GC-162, LGPD Art. 18 (II access / V confirmation) + Art. 37.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000130_p568_consent_records_lgpd_read_rpcs.sql');
const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const svcGated = !!(SUPABASE_URL && SERVICE_KEY);
const anonGated = !!(SUPABASE_URL && ANON_KEY);

// ── STATIC: list_my_consents (subject self-read) ────────────────────────────────────────
test('#568 static: list_my_consents is SECDEF + STABLE, anon-revoked, omits hashes, has is_active', () => {
  assert.ok(existsSync(MIG), 'migration 130 exists');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.list_my_consents\(\)/);
  assert.match(body, /list_my_consents\(\)[\s\S]*?STABLE[\s\S]*?SECURITY DEFINER/);
  assert.match(body, /REVOKE EXECUTE ON FUNCTION public\.list_my_consents\(\) FROM PUBLIC, anon;/);
  assert.match(body, /GRANT EXECUTE ON FUNCTION public\.list_my_consents\(\) TO authenticated, service_role;/);
  // subject view must NOT leak the internal capture hashes (slice the fn body by its CREATE..REVOKE bounds)
  const lmcBlock = body.slice(
    body.indexOf('CREATE OR REPLACE FUNCTION public.list_my_consents'),
    body.indexOf('REVOKE EXECUTE ON FUNCTION public.list_my_consents'));
  assert.doesNotMatch(lmcBlock, /email_hash|ip_hash|user_agent_hash/,
    'list_my_consents (subject view) must omit the capture-evidence hashes');
  assert.match(lmcBlock, /'is_active', \(cr\.revoked_at IS NULL\)/, 'subject sees a consolidated active flag');
});

// ── STATIC: admin_list_member_consents (view_pii + org fence + audit log) ────────────────
test('#568 static: admin_list_member_consents is view_pii-gated with an org fence + always logs', () => {
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.admin_list_member_consents\(p_member_id uuid\)/);
  assert.match(body, /IF NOT public\.can_by_member\(v_caller_id, 'view_pii'\) THEN/,
    'admin read gated on view_pii');
  // CRITICAL: multi-tenant fence — target must be in caller org (SECDEF bypasses the RESTRICTIVE RLS)
  assert.match(body, /v_target_org_id IS NULL OR v_caller_org_id IS NULL OR v_target_org_id <> v_caller_org_id/,
    'org fence: target must be a real member in the caller organization');
  assert.match(body, /RAISE EXCEPTION 'Access denied: target member not in caller organization'/);
  assert.match(body, /AND cr\.organization_id = v_caller_org_id/, 'row-level org fence on the consent query too');
  // accountability: log EVERY admin read (no self-read carve-out), with explicit accessed_at.
  // (The INSERT + the self-read carve-out string are both unique to this function — assert on the
  // whole body; an earlier indexOf('export_my_data') matched the header comment, slicing to empty.)
  assert.doesNotMatch(body, /p_member_id <> v_caller_id/, 'self-read must NOT be excluded from the audit log');
  assert.match(body, /INSERT INTO public\.pii_access_log[\s\S]*?'admin_list_member_consents'[\s\S]*?now\(\)/);
  assert.match(body, /REVOKE EXECUTE ON FUNCTION public\.admin_list_member_consents\(uuid\) FROM PUBLIC, anon;/);
  // the admin (view_pii) audit path MUST expose the capture-evidence hashes (inverse of the subject view)
  const admProjBlock = body.slice(
    body.indexOf('CREATE OR REPLACE FUNCTION public.admin_list_member_consents'),
    body.indexOf('REVOKE EXECUTE ON FUNCTION public.admin_list_member_consents'));
  assert.match(admProjBlock, /email_hash[\s\S]*?ip_hash[\s\S]*?user_agent_hash/,
    'admin audit path exposes the capture-evidence hashes');
});

// ── STATIC: export_my_data adds consent + fixes the i.name→i.title regression ────────────
test('#568 static: export_my_data includes consent_records, fixes i.name→i.title, re-asserts grants', () => {
  assert.match(body, /'consent_records', COALESCE\(\(/, 'export gains a consent_records key');
  // explicit projection (NOT row_to_json) so future columns are not auto-exported
  const exBlock = body.slice(body.lastIndexOf("'consent_records'"));
  assert.doesNotMatch(exBlock, /row_to_json\(cr\)/, 'consent_records export uses explicit projection');
  // the pre-existing bug: initiatives.name no longer exists (V4 renamed to title)
  assert.doesNotMatch(body, /'initiative_name', i\.name\b/, 'must NOT reference i.name (column was renamed to title)');
  assert.match(body, /'initiative_name', i\.title\b/, 'engagements use i.title');
  assert.match(body, /REVOKE EXECUTE ON FUNCTION public\.export_my_data\(\) FROM PUBLIC, anon;/,
    'CREATE OR REPLACE must re-assert the ACL explicitly (drop the lingering anon auto-grant)');
});

// ── DB (gated): anon is revoked on all three; service_role fail-closes ───────────────────
test('#568 DB: anon CANNOT execute the consent read RPCs (revoke effective)', { skip: anonGated ? false : 'anon key required' }, async () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const r1 = await anon.rpc('list_my_consents');
  assert.ok(r1.error, 'anon rejected from list_my_consents');
  const r2 = await anon.rpc('admin_list_member_consents', { p_member_id: '00000000-0000-0000-0000-000000000000' });
  assert.ok(r2.error, 'anon rejected from admin_list_member_consents');
});

test('#568 DB: anon CANNOT execute export_my_data (anon grant dropped this migration)', { skip: anonGated ? false : 'anon key required' }, async () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const { error } = await anon.rpc('export_my_data');
  assert.ok(error, 'anon must be rejected from export_my_data (permission denied for function)');
});

test('#568 DB: service_role (no auth.uid) fail-closes on all three', { skip: svcGated ? false : 'service key required' }, async () => {
  const svc = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  // list_my_consents + export_my_data raise 'Not authenticated' (no auth.uid → no member row)
  const r1 = await svc.rpc('list_my_consents');
  assert.ok(r1.error, 'list_my_consents fail-closes for null uid');
  const r2 = await svc.rpc('export_my_data');
  assert.ok(r2.error, 'export_my_data fail-closes for null uid');
  // admin_list_member_consents also fail-closes (Not authenticated before the view_pii gate)
  const r3 = await svc.rpc('admin_list_member_consents', { p_member_id: '00000000-0000-0000-0000-000000000000' });
  assert.ok(r3.error, 'admin_list_member_consents fail-closes for null uid');
});
