/**
 * Contract: #766 H5 — buddy/padrinho bilateral pairing loop (DB layer, PR1 of 2).
 *
 * Model (PM decision 2026-06-17): bilateral, VOLUNTEER-DRIVEN. A senior (non-guest, same tribe)
 * VOLUNTEERS as padrinho (offer_buddy = inviter) and the afilhado accepts/declines
 * (respond_to_buddy_offer = invitee). MVP is a light social pointer; no check-ins/duration/metrics.
 *
 * Own minimal table buddy_pairings (NOT initiative_invitations — that primitive is coupled to
 * initiative_id/kind_scope and mints an engagement on accept; none fits buddy). ADR-0013 Cat B.
 * LGPD: contact (phone/WhatsApp) lives in members; exposed ONLY via get_my_buddy() under a DOUBLE
 * gate (members.share_whatsapp AND pairing.status='accepted'). The accept IS the bilateral consent.
 * NO invariant in check_schema_invariants(): status is mutable/bidirectional; CHECK + partial unique
 * index cover the only static invariant (1 active pairing per afilhado).
 *
 * Migration: 20260805000207_766_h5_buddy_pairings.sql. SPEC: docs/specs/SPEC_766_H5_BUDDY.md.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const read = (p) => (existsSync(resolve(ROOT, p)) ? readFileSync(resolve(ROOT, p), 'utf8') : '');
const MIG = read('supabase/migrations/20260805000207_766_h5_buddy_pairings.sql');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── Offline: table shape ─────────────────────────────────────────────────────────
test('migration: buddy_pairings table with padrino/afilhado member FKs (ON DELETE CASCADE)', () => {
  assert.ok(MIG, 'PR1 migration exists');
  assert.match(MIG, /CREATE TABLE public\.buddy_pairings/);
  assert.match(MIG, /padrino_member_id\s+uuid NOT NULL REFERENCES public\.members\(id\) ON DELETE CASCADE/);
  assert.match(MIG, /afilhado_member_id\s+uuid NOT NULL REFERENCES public\.members\(id\) ON DELETE CASCADE/);
});

test('migration: status CHECK has exactly offered/accepted/declined/revoked (NO expired — no cron)', () => {
  assert.match(MIG, /CHECK \(status IN \('offered','accepted','declined','revoked'\)\)/);
  assert.ok(!/'expired'/.test(MIG), "no 'expired' status (unreachable without a cron)");
});

test('migration: self-pairing forbidden by CHECK', () => {
  assert.match(MIG, /CHECK \(padrino_member_id <> afilhado_member_id\)/);
});

test('migration: NO tribe_id column on the table (derived from members, not a cache column)', () => {
  const ddl = MIG.slice(MIG.indexOf('CREATE TABLE public.buddy_pairings'), MIG.indexOf(');', MIG.indexOf('CREATE TABLE public.buddy_pairings')));
  assert.ok(!/tribe_id/.test(ddl), 'buddy_pairings must not carry a denormalized tribe_id');
});

test('migration: partial unique index enforces 1 active pairing per afilhado (frees on decline/revoke)', () => {
  assert.match(MIG, /CREATE UNIQUE INDEX buddy_pairings_one_active_afilhado\s+ON public\.buddy_pairings \(afilhado_member_id\)\s+WHERE status IN \('offered','accepted'\)/);
});

test('migration: padrino lookup index present', () => {
  assert.match(MIG, /CREATE INDEX buddy_pairings_padrino_idx ON public\.buddy_pairings \(padrino_member_id\)/);
});

test('migration: dedicated updated_at trigger fn + BEFORE UPDATE trigger', () => {
  assert.match(MIG, /CREATE FUNCTION public\.buddy_pairings_set_updated_at\(\)/);
  assert.match(MIG, /CREATE TRIGGER _trg_buddy_pairings_updated_at\s+BEFORE UPDATE ON public\.buddy_pairings/);
});

// ── Offline: RLS ─────────────────────────────────────────────────────────────────
test('migration: RLS enabled; SELECT policy for the two parties + tribe_leader of the padrino tribe', () => {
  assert.match(MIG, /ALTER TABLE public\.buddy_pairings ENABLE ROW LEVEL SECURITY/);
  assert.match(MIG, /CREATE POLICY buddy_pairings_select ON public\.buddy_pairings\s+FOR SELECT TO authenticated/);
  assert.match(MIG, /me\.id IN \(buddy_pairings\.padrino_member_id, buddy_pairings\.afilhado_member_id\)/);
  assert.match(MIG, /tl\.operational_role = 'tribe_leader'/);
  // no write policy -> mutations only via SECDEF RPCs (default deny)
  assert.ok(!/FOR (INSERT|UPDATE|DELETE|ALL)/.test(MIG), 'no write policy: mutations only via SECDEF RPCs');
});

// ── Offline: RPCs are SECDEF with locked search_path ─────────────────────────────
for (const fn of ['offer_buddy', 'respond_to_buddy_offer', 'revoke_buddy_offer', 'get_my_buddy']) {
  test(`migration: ${fn} is SECURITY DEFINER with search_path 'public','pg_temp' + COMMENT (Phase-C rationale outside body)`, () => {
    const re = new RegExp(`CREATE FUNCTION public\\.${fn}\\([^)]*\\)[\\s\\S]*?SECURITY DEFINER\\s+SET search_path TO 'public', 'pg_temp'`);
    assert.match(MIG, re, `${fn} SECDEF + search_path`);
    assert.match(MIG, new RegExp(`COMMENT ON FUNCTION public\\.${fn}\\(`), `${fn} has a COMMENT (rationale lives here, not inline in $fn$ body)`);
  });
}

// ── Offline: behavioral guards in RPC bodies ─────────────────────────────────────
test('offer_buddy: guards same tribe, not self, no active pairing; notifies afilhado', () => {
  assert.match(MIG, /v_afilhado\.tribe_id IS DISTINCT FROM v_caller\.tribe_id/);
  assert.match(MIG, /Cannot be your own buddy/);
  assert.match(MIG, /already has an active buddy offer or pairing/);
  assert.match(MIG, /INSERT INTO public\.notifications[\s\S]*?'buddy_offer'/);
  // ADR-0011: no operational_role authority branch in the body (consensual peer action).
  assert.ok(!/operational_role/.test(MIG.slice(MIG.indexOf('CREATE FUNCTION public.offer_buddy'), MIG.indexOf('COMMENT ON FUNCTION public.offer_buddy'))), 'offer_buddy body carries no operational_role gate');
});

test('respond_to_buddy_offer: only the afilhado, only pending; on accept notifies padrinho', () => {
  assert.match(MIG, /Only the afilhado can respond to this offer/);
  assert.match(MIG, /Offer is not pending/);
  assert.match(MIG, /p_response NOT IN \('accept','decline'\)/);
  assert.match(MIG, /INSERT INTO public\.notifications[\s\S]*?'buddy_accepted'/);
  // p_note removed from MVP (no responded_note column)
  assert.ok(!/responded_note/.test(MIG), 'responded_note dropped from MVP');
});

test('revoke_buddy_offer: ownership-only (either party); sets status=revoked', () => {
  assert.match(MIG, /v_caller_id NOT IN \(v_pairing\.padrino_member_id, v_pairing\.afilhado_member_id\)/);
  assert.match(MIG, /Not authorized to revoke this pairing/);
  assert.match(MIG, /SET status = 'revoked', revoked_at = now\(\), revoked_by = v_caller_id/);
  // ADR-0011: tribe_leader force-revoke deferred (would be role authority); no role gate in body.
  assert.ok(!/'tribe_leader'/.test(MIG.slice(MIG.indexOf('CREATE FUNCTION public.revoke_buddy_offer'), MIG.indexOf('COMMENT ON FUNCTION public.revoke_buddy_offer'))), 'revoke body carries no tribe_leader role gate');
});

test('get_my_buddy: WhatsApp under DOUBLE gate (share_whatsapp AND accepted); manager/GP tribe_id NULL guard', () => {
  assert.match(MIG, /CASE WHEN bp\.status = 'accepted' AND p\.share_whatsapp THEN p\.phone ELSE NULL END AS padrino_whatsapp/);
  assert.match(MIG, /CASE WHEN bp\.status = 'accepted' AND a\.share_whatsapp THEN a\.phone ELSE NULL END AS afilhado_whatsapp/);
  assert.match(MIG, /IF v_tribe_id IS NULL THEN\s+v_can_volunteer := '\[\]'::jsonb;/);
  assert.match(MIG, /'can_volunteer_for'/);
  // pool excludes guests and self
  assert.match(MIG, /m\.operational_role <> 'guest'/);
  assert.match(MIG, /m\.id <> v_member_id/);
});

// ── Offline: design invariants ───────────────────────────────────────────────────
test('migration: does NOT touch check_schema_invariants (no invariant — mutable bidirectional state)', () => {
  // the real signal of "added an invariant" (cf. PR5) is REDEFINING the function; header may name it.
  assert.ok(!/(CREATE OR REPLACE|CREATE) FUNCTION public\.check_schema_invariants/.test(MIG), 'PR1 adds no schema invariant');
});

test('migration: does NOT reuse/alter initiative_invitations (own minimal table)', () => {
  // narrow to actual SQL use (schema-qualified); the header comment may name the table to explain the choice.
  assert.ok(!/public\.initiative_invitations/.test(MIG), 'buddy is its own primitive, not a graft on initiative_invitations');
});

// ── DB-gated: live wiring ────────────────────────────────────────────────────────
test('DB: buddy_pairings table exists and is empty (rollback probe left no rows)', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { count, error } = await sb.from('buddy_pairings').select('*', { count: 'exact', head: true });
  assert.ok(!error, error?.message);
  assert.equal(count, 0, 'buddy_pairings should start empty in production');
});

test('DB: all 4 RPCs reject an unauthenticated (service-role, auth.uid()=NULL) caller', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const calls = [
    ['get_my_buddy', {}],
    ['offer_buddy', { p_afilhado_member_id: '00000000-0000-0000-0000-000000000000' }],
    ['respond_to_buddy_offer', { p_pairing_id: '00000000-0000-0000-0000-000000000000', p_response: 'accept' }],
    ['revoke_buddy_offer', { p_pairing_id: '00000000-0000-0000-0000-000000000000' }],
  ];
  for (const [fn, args] of calls) {
    const { error } = await sb.rpc(fn, args);
    assert.ok(error, `${fn} must error for an unauthenticated caller`);
    assert.match(error.message, /Not authenticated/i, `${fn} guard fires (auth.uid() NULL)`);
  }
});
