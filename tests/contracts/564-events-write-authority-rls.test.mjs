/**
 * Contract: #564 — close the events write-authority bypass (RLS) + companion timezone coerce.
 *
 * BEFORE: public.events had ONE write-capable policy `events_v4_org_scope` (cmd=ALL, roles={public},
 * USING/CHECK = org-scope only) → any authenticated org member could INSERT/UPDATE/DELETE any event row
 * directly via PostgREST, bypassing can_by_member('manage_event'). The frontend (canEdit) and the
 * create/update RPCs gate properly; the table RLS did not.
 *
 * AFTER (migration 20260805000127): the blanket ALL policy is split into SELECT (identical read
 * predicate, TO public) + INSERT/UPDATE/DELETE (TO authenticated). UPDATE/DELETE gate on the new
 * rls_can_write_event(initiative_id, created_by) SECURITY DEFINER predicate, which returns the SAME
 * boolean as the update_event RPC gate: member AND (event-author OR (manage_event AND NOT
 * tribe_leader-cross-tribe)). Invariant: if update_event would succeed, the matching direct .update()
 * also passes RLS — no legitimate editor regresses, while the "any member" bypass closes.
 *
 * Companion: update_event + update_future_events_in_group gain p_timezone (pg_timezone_names coerce,
 * parity with create_event); the frontend routes future-sibling timezone through the SECDEF RPC instead
 * of a direct multi-row .update() (which would silently drop drifted siblings for tribe_leaders).
 * Hardening: the DROP+CREATE'd RPCs + the new helper are REVOKE'd from anon (ADR-0038/0041 pattern).
 *
 * Cross-ref: #564, #485/PR#563 (where it was found), ADR-0007 (can() authority), GC-162 (RLS/LGPD).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000127_564_events_write_authority_rls.sql');
const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const ATT = resolve(ROOT, 'src/pages/attendance.astro');
const att = existsSync(ATT) ? readFileSync(ATT, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const svcGated = !!(SUPABASE_URL && SERVICE_KEY);
const anonGated = !!(SUPABASE_URL && ANON_KEY);

// ── STATIC: RLS policy split ─────────────────────────────────────────────────────────
test('#564 static: blanket events_v4_org_scope (cmd=ALL) is dropped', () => {
  assert.ok(existsSync(MIG), 'migration 127 exists');
  assert.match(body, /DROP POLICY IF EXISTS events_v4_org_scope ON public\.events;/,
    'the blanket cmd=ALL write policy must be removed');
});

test('#564 static: per-command policies exist, writes gated on rls_can_write_event', () => {
  assert.match(body, /CREATE POLICY events_select_org_scope ON public\.events\s+FOR SELECT TO public/,
    'SELECT keeps the org-scope read predicate (TO public, zero read regression)');
  assert.match(body, /CREATE POLICY events_insert_authority ON public\.events\s+FOR INSERT TO authenticated/,
    'INSERT scoped to authenticated');
  assert.match(body, /CREATE POLICY events_update_authority ON public\.events\s+FOR UPDATE TO authenticated/,
    'UPDATE scoped to authenticated');
  assert.match(body, /CREATE POLICY events_delete_authority ON public\.events\s+FOR DELETE TO authenticated/,
    'DELETE scoped to authenticated');
  // UPDATE + DELETE must call the authority predicate
  assert.ok(
    (body.match(/rls_can_write_event\(initiative_id, created_by\)/g) || []).length >= 3,
    'UPDATE (USING+CHECK) and DELETE (USING) all gate on rls_can_write_event');
});

// ── STATIC: predicate helper ───────────────────────────────────────────────────────────
test('#564 static: rls_can_write_event is SECURITY DEFINER + STABLE, anon-revoked', () => {
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.rls_can_write_event\(p_initiative_id uuid, p_created_by uuid\)/);
  assert.match(body, /RETURNS boolean[\s\S]*?STABLE[\s\S]*?SECURITY DEFINER/,
    'predicate must be STABLE + SECURITY DEFINER');
  assert.match(body, /REVOKE EXECUTE ON FUNCTION public\.rls_can_write_event\(uuid, uuid\) FROM PUBLIC, anon;/,
    'revoke from BOTH public and anon (anon inherits via PUBLIC default grant)');
  assert.match(body, /GRANT EXECUTE ON FUNCTION public\.rls_can_write_event\(uuid, uuid\) TO authenticated, service_role;/);
  // mirrors the RPC gate: member-existence + event-author OR manage_event w/ tribe-scope
  assert.match(body, /FROM public\.members m, t\s+WHERE m\.auth_id = auth\.uid\(\)/,
    'caller must have a members row (parity with update_event Unauthorized; closes ghost-creator)');
  assert.match(body, /m\.operational_role IS NOT DISTINCT FROM 'tribe_leader'/,
    'tribe_leader cross-tribe restriction uses NULL-safe IS NOT DISTINCT FROM');
});

// ── STATIC: companion p_timezone + anon hardening on the edit RPCs ──────────────────────
test('#564 static: update_event gains p_timezone with pg_timezone_names coerce + anon revoke', () => {
  assert.match(body, /DROP FUNCTION IF EXISTS public\.update_event\(uuid, text, date, time without time zone, integer, text, text, boolean, text, text, text, text, text, text\[\]\);/,
    'DROP the prior 14-arg signature (param count change, GC-097)');
  assert.match(body, /p_timezone text DEFAULT NULL::text\s*\)\s*\n\s*RETURNS json/,
    'p_timezone added as the new last param');
  assert.match(body, /WHEN p_timezone IS NULL OR p_timezone = '' THEN NULL[\s\S]*?pg_timezone_names[\s\S]*?'America\/Sao_Paulo'/,
    'coerce: NULL/empty keeps existing, unknown IANA -> BRT (parity with create_event)');
  assert.match(body, /REVOKE EXECUTE ON FUNCTION public\.update_event\([\s\S]*?text\) FROM PUBLIC, anon;/);
  assert.match(body, /GRANT EXECUTE ON FUNCTION public\.update_event\([\s\S]*?text\) TO authenticated, service_role;/);
});

test('#564 static: update_future_events_in_group gains p_timezone + anon revoke', () => {
  assert.match(body, /DROP FUNCTION IF EXISTS public\.update_future_events_in_group\(uuid, time without time zone, integer, text, text, text, text, text\);/);
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.update_future_events_in_group\([\s\S]*?p_timezone text DEFAULT NULL/,
    'p_timezone added as the new last param (9-arg signature)');
  assert.match(body, /timezone = COALESCE\(v_safe_tz, timezone\)/,
    'future-group UPDATE sets timezone (anchor + future siblings)');
  assert.match(body, /REVOKE EXECUTE ON FUNCTION public\.update_future_events_in_group\([\s\S]*?text\) FROM PUBLIC, anon;/);
});

// ── STATIC: frontend routes timezone through the RPCs (no direct multi-row write) ────────
test('#564 static: attendance.astro routes timezone via RPC, drops the direct multi-row propagation', () => {
  assert.ok(existsSync(ATT), 'attendance.astro exists');
  // the removed :2112 direct multi-row sibling write must be gone
  assert.doesNotMatch(att, /\.update\(\{\s*timezone:\s*timezone\s*\|\|\s*DEFAULT_TZ\s*\}\)/,
    'the direct sibling .update({ timezone }) multi-row write must be removed');
  // timezone now flows through both edit RPCs
  assert.match(att, /update_future_events_in_group[\s\S]*?p_timezone:\s*timezone\s*\|\|\s*DEFAULT_TZ/,
    'future-scope edit passes p_timezone to update_future_events_in_group');
  // structural (not prose-anchored): p_timezone routed to BOTH edit RPC calls (future-group + this-only)
  const tzRpcArgs = (att.match(/p_timezone:\s*timezone\s*\|\|\s*DEFAULT_TZ/g) || []).length;
  assert.ok(tzRpcArgs >= 2, 'p_timezone routed to BOTH update_future_events_in_group and the this-only update_event call');
});

// ── DB (gated): anon cannot reach the predicate or write events ─────────────────────────
test('#564 DB: anon CANNOT execute rls_can_write_event (anon revoke effective)', { skip: anonGated ? false : 'anon key required' }, async () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const { error } = await anon.rpc('rls_can_write_event', { p_initiative_id: null, p_created_by: null });
  assert.ok(error, 'anon must be rejected (permission denied for function)');
});

test('#564 DB: anon direct UPDATE on events affects 0 rows (write bypass closed)', { skip: svcGated && anonGated ? false : 'service + anon keys required' }, async () => {
  const svc = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  const { data: ev } = await svc.from('events').select('id').limit(1).maybeSingle();
  assert.ok(ev?.id, 'a sample event exists');
  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const { data, error } = await anon.from('events').update({ notes: '#564-rls-probe' }).eq('id', ev.id).select('id');
  // RLS filters the row out: either an error or an empty result set — never a successful mutation.
  assert.ok(error || !(data && data.length), 'anon must not mutate any event row');
});

test('#564 DB: service_role retains update_event EXECUTE and the body fail-closes for null uid', { skip: svcGated ? false : 'service key required' }, async () => {
  const svc = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  const { data: ev } = await svc.from('events').select('id').limit(1).maybeSingle();
  const { data, error } = await svc.rpc('update_event', { p_event_id: ev.id });
  assert.ifError(error); // EXECUTE is granted (no permission-denied)
  assert.equal(data?.success, false, 'fail-closed: no auth.uid() -> Unauthorized, never a silent write');
});
