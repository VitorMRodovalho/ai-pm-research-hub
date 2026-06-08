/**
 * Contract: #566 — close the event-author cross-tribe initiative_id reassign (#564 follow-up).
 *
 * BEFORE: the attendance.astro edit/post-create paths wrote events.initiative_id via a direct
 * sb.from('events').update(...). Under #564 RLS, UPDATE re-checks rls_can_write_event(initiative_id,
 * created_by); the AUTHOR carve-out passes for ANY new initiative → an author could move their own
 * event to any tribe's initiative via PostgREST, which update_event's tribe-scope gate disallows.
 *
 * AFTER (migration 20260805000131): a SECDEF link_event_to_initiative(p_event_id, p_initiative_id)
 * reassigns initiative_id behind a two-part gate — (1) rls_can_write_event(current_initiative, created_by)
 * (caller can write the event now) AND (2) rls_can_write_event(p_initiative_id, NULL) (manage_event +
 * tribe-scope on the TARGET, author carve-out DISABLED via created_by=NULL). A non-existent target is
 * rejected explicitly (would otherwise slip past the tribe-scope guard / trip the FK). The 4 frontend
 * sites stop writing initiative_id directly and call the RPC.
 *
 * Verified live this session (JWT impersonation): a tribe_leader moving a tribe-4 event to another
 * tribe's initiative → {success:false,'Cross-tribe initiative move requires manage_event on the target
 * tribe'}; bogus target → 'Initiative not found'; bogus event → 'Event not found'.
 *
 * Cross-ref: #566, #564/PR#565, ADR-0007 (can() authority), GC-162.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000131_p566_link_event_to_initiative.sql');
const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
const ATT = resolve(ROOT, 'src/pages/attendance.astro');
const att = existsSync(ATT) ? readFileSync(ATT, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const svcGated = !!(SUPABASE_URL && SERVICE_KEY);
const anonGated = !!(SUPABASE_URL && ANON_KEY);

// ── STATIC: the RPC + its gate ───────────────────────────────────────────────────────────
test('#566 static: link_event_to_initiative is SECDEF + anon-revoked', () => {
  assert.ok(existsSync(MIG), 'migration 131 exists');
  assert.match(body, /CREATE OR REPLACE FUNCTION public\.link_event_to_initiative\(p_event_id uuid, p_initiative_id uuid\)/);
  assert.match(body, /SECURITY DEFINER/);
  assert.match(body, /REVOKE EXECUTE ON FUNCTION public\.link_event_to_initiative\(uuid, uuid\) FROM PUBLIC, anon;/);
  assert.match(body, /GRANT EXECUTE ON FUNCTION public\.link_event_to_initiative\(uuid, uuid\) TO authenticated, service_role;/);
  assert.match(body, /NOTIFY pgrst, 'reload schema';/);
});

test('#566 static: two-part gate — caller can write current event AND target gate has NO author bypass', () => {
  // (1) caller can write the event in its current state
  assert.match(body, /rls_can_write_event\(v_current_initiative_id, v_created_by\)/,
    'check (1): rls_can_write_event(current_initiative, created_by)');
  // (2) target gate passes created_by = NULL so the author carve-out cannot move cross-tribe
  assert.match(body, /rls_can_write_event\(p_initiative_id, NULL\)/,
    'check (2): rls_can_write_event(target, NULL) — author carve-out disabled');
  // existence check closes the bogus-uuid bypass (resolve_tribe_id(bogus)=NULL slips past tribe scope)
  assert.match(body, /NOT EXISTS \(SELECT 1 FROM public\.initiatives WHERE id = p_initiative_id\)/,
    'non-existent target initiative is rejected before the gate/UPDATE');
  assert.match(body, /'Cross-tribe initiative move requires manage_event on the target tribe'/);
});

// ── STATIC: frontend regression form (no direct initiative_id write to events) ───────────
test('#566 static: attendance.astro no longer writes events.initiative_id directly', () => {
  assert.ok(existsSync(ATT), 'attendance.astro exists');
  assert.doesNotMatch(att, /updateFields\.initiative_id\s*=/, 'no direct updateFields.initiative_id assignment');
  assert.doesNotMatch(att, /\.update\(\{[^}]*initiative_id/, 'no direct events.update({ initiative_id ... })');
  // all four sites route through the RPC (post-create single, post-create recurring, future edit, this-only edit)
  const calls = (att.match(/sb\.rpc\('link_event_to_initiative'/g) || []).length;
  assert.ok(calls >= 4, `expected >= 4 link_event_to_initiative RPC calls, found ${calls}`);
});

// ── DB (gated): anon revoked; service_role (no uid) fail-closes ──────────────────────────
test('#566 DB: anon CANNOT execute link_event_to_initiative (revoke effective)', { skip: anonGated ? false : 'anon key required' }, async () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const { error } = await anon.rpc('link_event_to_initiative', {
    p_event_id: '00000000-0000-0000-0000-000000000000', p_initiative_id: null });
  assert.ok(error, 'anon must be rejected (permission denied for function)');
});

test('#566 DB: service_role (no auth.uid) fail-closes to Unauthorized, never a write', { skip: svcGated ? false : 'service key required' }, async () => {
  const svc = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  const { data, error } = await svc.rpc('link_event_to_initiative', {
    p_event_id: '00000000-0000-0000-0000-000000000000', p_initiative_id: null });
  assert.ifError(error); // EXECUTE granted to service_role (no permission-denied)
  assert.equal(data?.success, false, 'no auth.uid() -> Unauthorized, never a silent write');
});
