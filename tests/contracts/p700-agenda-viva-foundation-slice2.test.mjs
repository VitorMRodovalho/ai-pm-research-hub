import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// #700 Agenda Viva [Foundation] — SLICE 2: reserve/read/update/cancel/reorder RPCs.
// Happy-path writes are gated on auth.uid() (a signed-in member), so they are verified live
// during the session with an injected JWT; here we assert the migration shape + the anon /
// negative DB-gated paths (anon read works without PII; anon/unauth writes are denied).

const MIGRATION_PATH = 'supabase/migrations/20260805000178_700_agenda_viva_foundation_slice2.sql';
const MIGRATION_SQL = readFileSync(MIGRATION_PATH, 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK ? createClient(SUPABASE_URL, SUPABASE_SRK, { auth: { persistSession: false } }) : null;
const anon = SUPABASE_URL && ANON_KEY ? createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } }) : null;

const RPCS = ['reserve_agenda_block', 'get_geral_agenda_viva', 'update_agenda_block', 'cancel_agenda_block', 'reorder_event_blocks'];

describe('p700 slice 2 — Agenda Viva RPCs', () => {
  describe('migration static assertions', () => {
    it('migration file exists', () => assert.ok(MIGRATION_SQL.length > 0));

    it('defines all 5 RPCs as SECURITY DEFINER with pinned search_path', () => {
      for (const fn of RPCS) {
        assert.match(MIGRATION_SQL, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}\\(`), `${fn} present`);
      }
      // every function body pins SECDEF + search_path
      const secdefCount = (MIGRATION_SQL.match(/SECURITY DEFINER/g) || []).length;
      const pathCount = (MIGRATION_SQL.match(/SET search_path TO 'public','pg_temp'/g) || []).length;
      assert.ok(secdefCount >= 5, `expected ≥5 SECURITY DEFINER; got ${secdefCount}`);
      assert.ok(pathCount >= 5, `expected ≥5 pinned search_path; got ${pathCount}`);
    });

    it('reserve enforces capacity ≤90 under a row lock and the next-2 window', () => {
      assert.match(MIGRATION_SQL, /FROM public\.events e\s*WHERE e\.id = p_event_id\s*FOR UPDATE/);
      assert.match(MIGRATION_SQL, /v_used \+ p_duration_min > 90/);
      assert.match(MIGRATION_SQL, /reservation_window_closed/);
      assert.match(MIGRATION_SQL, /v_rn IS NULL OR v_rn > 2/);
    });

    it('reserve is self-scoped (caller from auth.uid(), no p_member_id param)', () => {
      const sig = MIGRATION_SQL.split('FUNCTION public.reserve_agenda_block(')[1].split(')')[0];
      assert.ok(!/p_member_id/.test(sig), 'reserve_agenda_block must not accept p_member_id');
      assert.match(MIGRATION_SQL, /SELECT id INTO v_caller FROM public\.members WHERE auth_id = auth\.uid\(\)/);
      assert.match(MIGRATION_SQL, /can_by_member\(v_caller, 'reserve_agenda_block'\)/);
    });

    it('LGPD: guest_name is only surfaced under the manage_event (is_admin) branch', () => {
      // guest_name must appear inside the v_is_admin CASE, never in the anon base object
      assert.match(MIGRATION_SQL, /CASE WHEN v_is_admin\s*THEN jsonb_build_object\([^)]*'guest_name', bk\.guest_name\)/s);
      // the anon base block object exposes owner_first_name, not owner full name / member_id
      assert.match(MIGRATION_SQL, /'owner_first_name', bk\.owner_first_name/);
    });

    it('grants: public agenda anon-OK; write RPCs revoke anon', () => {
      assert.match(MIGRATION_SQL, /GRANT EXECUTE ON FUNCTION public\.get_geral_agenda_viva\(integer, uuid\) TO anon, authenticated/);
      assert.match(MIGRATION_SQL, /REVOKE ALL ON FUNCTION public\.reserve_agenda_block\([^)]*\) FROM PUBLIC, anon/);
      assert.match(MIGRATION_SQL, /REVOKE ALL ON FUNCTION public\.reorder_event_blocks\(uuid, uuid\[\]\)\s*FROM PUBLIC, anon/);
    });

    it('NOTIFY pgrst trailer present', () => assert.match(MIGRATION_SQL, /NOTIFY pgrst, 'reload schema';/));
  });

  if (sb) {
    describe('DB-gated assertions', () => {
      it('service-role reserve (no auth.uid()) returns not_authenticated, never writes', async () => {
        const { data, error } = await sb.rpc('reserve_agenda_block', {
          p_event_id: '00000000-0000-0000-0000-000000000000',
          p_format_slug: 'insight_rapido', p_title: 'should-not-write', p_duration_min: 5,
        });
        assert.ok(!error, `rpc call itself should succeed; got ${error?.message}`);
        assert.equal(data?.error, 'not_authenticated', `expected not_authenticated; got ${JSON.stringify(data)}`);
      });

      it('get_geral_agenda_viva (service role) returns viewer + events shape', async () => {
        const { data, error } = await sb.rpc('get_geral_agenda_viva', { p_limit_events: 2 });
        if (error) assert.fail(`rpc error: ${error.message}`);
        assert.ok(data?.viewer, 'must return a viewer object');
        assert.ok(Array.isArray(data?.events), 'must return an events array');
      });
    });
  } else {
    describe('DB-gated assertions', () => {
      it.skip('SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY not set — DB checks skipped', () => {});
    });
  }

  describe('anon-path assertions', () => {
    it('anon CAN read the public agenda but it carries no PII', { skip: !anon }, async () => {
      const { data, error } = await anon.rpc('get_geral_agenda_viva', { p_limit_events: 2 });
      if (error) assert.fail(`anon must be able to call get_geral_agenda_viva; got ${error.message}`);
      assert.equal(data?.viewer?.is_authenticated, false, 'anon viewer must be unauthenticated');
      assert.equal(data?.viewer?.is_admin, false, 'anon viewer must not be admin');
      assert.ok(Array.isArray(data?.events), 'events must be an array');
      // No third-party / owner PII may appear in the anon payload.
      const raw = JSON.stringify(data);
      for (const leak of ['guest_name', 'owner_member_id', 'owner_full_name', '"email"']) {
        assert.ok(!raw.includes(leak), `anon payload must not contain ${leak}`);
      }
    });

    it('anon CANNOT execute a write RPC (reserve)', { skip: !anon }, async () => {
      const { error } = await anon.rpc('reserve_agenda_block', {
        p_event_id: '00000000-0000-0000-0000-000000000000',
        p_format_slug: 'insight_rapido', p_title: 'x', p_duration_min: 5,
      });
      assert.ok(error, 'anon must be permission-denied on reserve_agenda_block (REVOKE anon)');
    });
  });
});
