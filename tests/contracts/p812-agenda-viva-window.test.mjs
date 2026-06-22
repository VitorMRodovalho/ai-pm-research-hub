import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// #812 Agenda Viva na home com estado temporal — camada .sql (PD-1).
// get_geral_agenda_viva ganha p_window (upcoming/past_recent/both). Static assertions sobre
// a migration + DB-gated sobre as 3 janelas, ordenação passado→futuro e zero-PII no anon
// (incl. supressão LGPD do nome em blocos no_show — PD-5, parecer legal-counsel 2026-06-22).

const MIGRATION_PATH = 'supabase/migrations/20260805000230_812_agenda_viva_p_window.sql';
const MIGRATION_SQL = readFileSync(MIGRATION_PATH, 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK ? createClient(SUPABASE_URL, SUPABASE_SRK, { auth: { persistSession: false } }) : null;
const anon = SUPABASE_URL && ANON_KEY ? createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } }) : null;

describe('p812 — Agenda Viva p_window', () => {
  describe('migration static assertions', () => {
    it('migration file exists', () => assert.ok(MIGRATION_SQL.length > 0));

    it('signature change is DROP+CREATE with the 3-param window signature', () => {
      // old 2-param signature must be dropped (no overload), new 3-param created
      assert.match(MIGRATION_SQL, /DROP FUNCTION IF EXISTS public\.get_geral_agenda_viva\(integer, uuid\)/);
      assert.match(MIGRATION_SQL, /CREATE FUNCTION public\.get_geral_agenda_viva\([^)]*p_window\s+text DEFAULT 'upcoming'/s);
    });

    it('stays SECURITY DEFINER with pinned search_path and STABLE', () => {
      assert.match(MIGRATION_SQL, /SECURITY DEFINER/);
      assert.match(MIGRATION_SQL, /SET search_path TO 'public','pg_temp'/);
      assert.match(MIGRATION_SQL, /\bSTABLE\b/);
    });

    it('window values are validated (fail-closed to upcoming)', () => {
      assert.match(MIGRATION_SQL, /v_window NOT IN \('upcoming','past_recent','both'\)/);
      assert.match(MIGRATION_SQL, /v_window := 'upcoming'/);
    });

    it('past branch is read state only (confirmed + no_show, never reserved)', () => {
      assert.match(MIGRATION_SQL, /s\.is_past\s+AND b\.status IN \('confirmed','no_show'\)/);
      assert.match(MIGRATION_SQL, /NOT s\.is_past AND b\.status IN \('reserved','confirmed'\)/);
    });

    it('LGPD PD-5: no_show suppresses owner name for public + ordinary member', () => {
      // owner_first_name → NULL when no_show AND not admin AND not the block owner
      assert.match(
        MIGRATION_SQL,
        /'owner_first_name', CASE\s*WHEN bk\.status = 'no_show'\s*AND NOT v_is_admin\s*AND NOT \(v_caller IS NOT NULL AND bk\.owner_member_id = v_caller\)\s*THEN NULL/s,
        'no_show name suppression CASE must be present',
      );
      // full-name / guest PII still only under manage_event
      assert.match(MIGRATION_SQL, /CASE WHEN v_is_admin\s*THEN jsonb_build_object\([^)]*'guest_name', bk\.guest_name\)/s);
    });

    it('grants: public agenda anon-OK on the new signature', () => {
      assert.match(MIGRATION_SQL, /GRANT EXECUTE ON FUNCTION public\.get_geral_agenda_viva\(integer, uuid, text\) TO anon, authenticated/);
    });

    it('NOTIFY pgrst trailer present', () => assert.match(MIGRATION_SQL, /NOTIFY pgrst, 'reload schema';/));
  });

  if (sb) {
    describe('DB-gated assertions', () => {
      it('default (no p_window) preserves legacy upcoming shape', async () => {
        const { data, error } = await sb.rpc('get_geral_agenda_viva', { p_limit_events: 2 });
        if (error) assert.fail(`rpc error: ${error.message}`);
        assert.ok(data?.viewer, 'must return a viewer object');
        assert.ok(Array.isArray(data?.events), 'must return an events array');
        assert.ok(data.events.every((e) => e.is_past === false), 'default window must be all-upcoming');
      });

      it('past_recent returns at most the single last concluded meeting', async () => {
        const { data, error } = await sb.rpc('get_geral_agenda_viva', { p_limit_events: 2, p_window: 'past_recent' });
        if (error) assert.fail(`rpc error: ${error.message}`);
        assert.equal(data?.window, 'past_recent');
        assert.ok(data.events.length <= 1, 'past_recent caps at the last concluded meeting');
        assert.ok(data.events.every((e) => e.is_past === true), 'past_recent events must be flagged is_past');
      });

      it('both is ordered past → upcoming', async () => {
        const { data, error } = await sb.rpc('get_geral_agenda_viva', { p_limit_events: 2, p_window: 'both' });
        if (error) assert.fail(`rpc error: ${error.message}`);
        assert.equal(data?.window, 'both');
        const starts = data.events.map((e) => e.start_at);
        const sorted = [...starts].sort();
        assert.deepEqual(starts, sorted, 'events must be ordered chronologically (past first)');
      });
    });
  } else {
    describe('DB-gated assertions', () => {
      it.skip('SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY not set — DB checks skipped', () => {});
    });
  }

  describe('anon-path assertions', () => {
    it('anon can read every window with no owner/guest PII', { skip: !anon }, async () => {
      for (const p_window of ['upcoming', 'past_recent', 'both']) {
        const { data, error } = await anon.rpc('get_geral_agenda_viva', { p_limit_events: 2, p_window });
        if (error) assert.fail(`anon must read window=${p_window}; got ${error.message}`);
        assert.equal(data?.viewer?.is_authenticated, false, `anon viewer unauthenticated (${p_window})`);
        const raw = JSON.stringify(data);
        for (const leak of ['guest_name', 'owner_member_id', 'owner_full_name', '"email"']) {
          assert.ok(!raw.includes(leak), `anon payload (${p_window}) must not contain ${leak}`);
        }
      }
    });
  });
});
