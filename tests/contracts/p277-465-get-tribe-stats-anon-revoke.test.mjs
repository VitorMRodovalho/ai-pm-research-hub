/**
 * Contract: #465 — close the anon member-name leak on the tribe-stats RPC family.
 *
 * get_tribe_stats(integer) is SECURITY DEFINER (owner postgres/bypassrls), has NO in-body auth gate, and
 * was EXECUTE-able by anon (via BOTH the PUBLIC default grant `=X` AND a direct `anon=X` grant). A direct
 * REST call with the public anon key — bypassing the tribe page's client-side canExploreTribes gate, which
 * already denies anon — returned member NAMES in top_contributors[].name. Migration 20260805000087 revokes
 * EXECUTE from PUBLIC + anon (revoking from anon alone is insufficient — anon also inherits via PUBLIC, the
 * same trap as the pg_default_acl view leak) and re-grants authenticated + service_role.
 *
 * The only legitimate consumer (src/pages/tribe/[id].astro loadTribeStats) runs for an authenticated ACTIVE
 * member (canExploreTribes blocks anon before the RPC) → role=authenticated, which keeps EXECUTE. So the
 * revoke closes the direct-API leak with zero impact on legit callers. exec_tribe_dashboard gets the same
 * revoke as defense-in-depth (it was already body-gated, not leaking, but carried the needless grant).
 *
 * Pre-existing leak (since mig 068), NOT introduced by the #419 metric-4 work; surfaced by the PR4-C-clean
 * adversarial review. Cross-ref: #465; CLAUDE.md key decision #6; METRIC_DISPARITY_AUDIT_2026-05-28 Bucket A.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000087_p277_465_get_tribe_stats_anon_revoke.sql');
const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const svcGated = !!(SUPABASE_URL && SERVICE_KEY);
const anonGated = !!(SUPABASE_URL && ANON_KEY);

// ── STATIC ────────────────────────────────────────────────────────────────────────
test('#465 static: get_tribe_stats EXECUTE revoked from PUBLIC + anon, retained for authenticated/service_role', () => {
  assert.ok(existsSync(MIG), 'migration 087 exists');
  assert.match(body, /REVOKE EXECUTE ON FUNCTION public\.get_tribe_stats\(integer\) FROM PUBLIC;/,
    'must revoke the PUBLIC default grant (anon inherits via PUBLIC)');
  assert.match(body, /REVOKE EXECUTE ON FUNCTION public\.get_tribe_stats\(integer\) FROM anon;/,
    'must revoke the direct anon grant');
  assert.match(body, /GRANT\s+EXECUTE ON FUNCTION public\.get_tribe_stats\(integer\) TO authenticated, service_role;/,
    'authenticated + service_role retain EXECUTE (legit consumers unaffected)');
});

test('#465 static: exec_tribe_dashboard anon/PUBLIC EXECUTE also stripped (defense-in-depth)', () => {
  assert.match(body, /REVOKE EXECUTE ON FUNCTION public\.exec_tribe_dashboard\(integer, text\) FROM PUBLIC;/);
  assert.match(body, /REVOKE EXECUTE ON FUNCTION public\.exec_tribe_dashboard\(integer, text\) FROM anon;/);
  assert.match(body, /GRANT\s+EXECUTE ON FUNCTION public\.exec_tribe_dashboard\(integer, text\) TO authenticated, service_role;/);
});

// ── BEHAVIOURAL (DB-gated) ──────────────────────────────────────────────────────────
test('#465 DB: anon client CANNOT execute get_tribe_stats — leak closed (no data, no member names)', { skip: anonGated ? false : 'anon key required' }, async () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const { data, error } = await anon.rpc('get_tribe_stats', { p_tribe_id: 8 });
  assert.ok(error, 'anon must be rejected (permission denied for function)');
  assert.ok(!data, 'anon must receive NO payload (no top_contributors[].name)');
});

test('#465 DB: anon client CANNOT execute exec_tribe_dashboard (defense-in-depth)', { skip: anonGated ? false : 'anon key required' }, async () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const { data, error } = await anon.rpc('exec_tribe_dashboard', { p_tribe_id: 8 });
  assert.ok(error, 'anon must be rejected');
  assert.ok(!data, 'anon must receive no payload');
});

test('#465 DB: service_role STILL executes get_tribe_stats (legit authenticated consumers unaffected)', { skip: svcGated ? false : 'service key required' }, async () => {
  const svc = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  const { data, error } = await svc.rpc('get_tribe_stats', { p_tribe_id: 8 });
  assert.ifError(error);
  assert.ok(data && typeof data.member_count !== 'undefined', 'service_role gets the stats payload (member_count present)');
});
