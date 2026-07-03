import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// #1071: a General Meeting that ended with blocks still 'reserved' (protagonists never
// confirmed live) became invisible + unconfirmable forever — the admin panel only asked
// for the 'upcoming' window, and get_geral_agenda_viva's past window hid 'reserved'
// blocks. Fix: the past window now surfaces 'reserved' blocks to ADMINS (manage_event)
// only, so a coordinator can confirm/no-show them after the meeting. This SUPERSEDES the
// p812 "past never reserved" invariant, which now holds for NON-admins only (LGPD).
const MIGRATION_PATH = 'supabase/migrations/20260805000323_agenda_viva_past_window_admin_reserved.sql';
const MIGRATION_SQL = readFileSync(MIGRATION_PATH, 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_ROLE = process.env.SUPABASE_SERVICE_ROLE_KEY;

describe('#1071 — Agenda Viva past window: admin-only reserved visibility', () => {
  describe('migration static assertions', () => {
    it('migration file exists and re-creates get_geral_agenda_viva', () => {
      assert.ok(MIGRATION_SQL.length > 0);
      assert.match(MIGRATION_SQL, /CREATE OR REPLACE FUNCTION public\.get_geral_agenda_viva\(/);
    });

    it('past window surfaces reserved blocks ONLY when v_is_admin', () => {
      // the new third branch of the blocks CTE — gated on v_is_admin.
      assert.match(MIGRATION_SQL, /s\.is_past AND v_is_admin AND b\.status = 'reserved'/);
    });

    it('non-admin past view is unchanged (confirmed + no_show only — LGPD invariant)', () => {
      // base past filter (applies to everyone, admin included) still excludes reserved.
      assert.match(MIGRATION_SQL, /s\.is_past\s+AND b\.status IN \('confirmed','no_show'\)/);
      // upcoming branch untouched.
      assert.match(MIGRATION_SQL, /NOT s\.is_past AND b\.status IN \('reserved','confirmed'\)/);
    });

    it('keeps SECURITY DEFINER + pinned search_path + STABLE (unchanged surface)', () => {
      assert.match(MIGRATION_SQL, /STABLE SECURITY DEFINER/);
      assert.match(MIGRATION_SQL, /SET search_path TO 'public', 'pg_temp'/);
    });
  });

  describe('DB-gated: non-admin caller never sees reserved-past (LGPD guard)', () => {
    const gated = SUPABASE_URL && SERVICE_ROLE ? it : it.skip;
    // A service-role client resolves v_caller = NULL → v_is_admin = false, i.e. the
    // "non-admin" path. It must NEVER receive a past block with status 'reserved'.
    gated('service-role (non-admin) past/both windows expose no reserved block', async () => {
      const sb = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } });
      for (const p_window of ['past_recent', 'both']) {
        const { data, error } = await sb.rpc('get_geral_agenda_viva', { p_limit_events: 2, p_window });
        assert.ifError(error);
        for (const ev of data.events || []) {
          if (!ev.is_past) continue;
          for (const b of ev.blocks || []) {
            assert.notEqual(b.status, 'reserved', `non-admin past window leaked a reserved block (window=${p_window})`);
          }
        }
      }
    });
  });
});
