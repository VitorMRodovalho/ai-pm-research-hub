import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// #700 Agenda Viva [Foundation] — SLICE 3: gamification pillar + confirm/XP + revoke.
// The XP-crediting happy paths are gated on auth.uid() (a manage_event member) and verified
// live during the session with an injected JWT (full-bonus credit = 33, first_time-off = 32,
// present=false → no credit, idempotent re-confirm, revoke deletes the ledger row). Here we
// assert the migration shape + the seeded config + the anon/negative DB-gated paths.

const MIGRATION_PATH = 'supabase/migrations/20260805000179_700_agenda_viva_foundation_slice3.sql';
const MIGRATION_SQL = readFileSync(MIGRATION_PATH, 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK ? createClient(SUPABASE_URL, SUPABASE_SRK, { auth: { persistSession: false } }) : null;
const anon = SUPABASE_URL && ANON_KEY ? createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } }) : null;

const RPCS = ['confirm_agenda_block', 'confirm_event_blocks', 'revoke_agenda_block_xp'];

describe('p700 slice 3 — Agenda Viva gamification + confirm/XP', () => {
  describe('migration static assertions', () => {
    it('migration file exists', () => assert.ok(MIGRATION_SQL.length > 0));

    it('enables the protagonismo pillar in the CHECK constraint', () => {
      assert.match(MIGRATION_SQL, /ADD CONSTRAINT gamification_rules_pillar_check[\s\S]*'protagonismo'/);
    });

    it('seeds the credit anchor + 3 tunable bonus rules (config-driven)', () => {
      for (const slug of [
        'agenda_block_protagonismo',
        'agenda_block_bonus_external_guest',
        'agenda_block_bonus_shared_material',
        'agenda_block_bonus_first_time',
      ]) {
        assert.ok(MIGRATION_SQL.includes(`'${slug}'`), `${slug} seeded`);
      }
      // upsert so a re-run is idempotent
      assert.match(MIGRATION_SQL, /ON CONFLICT \(organization_id, slug\) DO UPDATE/);
    });

    it('defines confirm/revoke RPCs + internal helper as SECURITY DEFINER with pinned search_path', () => {
      for (const fn of [...RPCS, '_grant_agenda_block_xp']) {
        assert.match(MIGRATION_SQL, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}\\(`), `${fn} present`);
      }
      const secdef = (MIGRATION_SQL.match(/SECURITY DEFINER/g) || []).length;
      const path = (MIGRATION_SQL.match(/SET search_path TO 'public','pg_temp'/g) || []).length;
      assert.ok(secdef >= 4, `expected ≥4 SECURITY DEFINER; got ${secdef}`);
      assert.ok(path >= 4, `expected ≥4 pinned search_path; got ${path}`);
    });

    it('XP credit = round(format base × duration weight) + Σ bonuses', () => {
      assert.match(MIGRATION_SQL, /round\(v_base \* v_weight\)::int \+ v_bonus/);
      // weight bands: 5–10 ×1.0 · 15–20 ×1.15 · ≥25 ×1.3
      assert.match(MIGRATION_SQL, /WHEN v_block\.duration_min <= 10 THEN 1\.0/);
      assert.match(MIGRATION_SQL, /WHEN v_block\.duration_min <= 20 THEN 1\.15/);
    });

    it('credit is idempotent by (ref_id, category, member) and honors the active kill-switch', () => {
      assert.match(MIGRATION_SQL, /ref_id = p_block_id AND category = 'agenda_block_protagonismo'[\s\S]*member_id = v_block\.owner_member_id/);
      assert.match(MIGRATION_SQL, /slug = 'agenda_block_protagonismo' AND organization_id = v_org[\s\S]*active = true/);
    });

    it('XP is credited ONLY when attendance.present = true; confirm gates on manage_event', () => {
      assert.match(MIGRATION_SQL, /FROM public\.attendance[\s\S]*present = true/);
      assert.match(MIGRATION_SQL, /IF v_present THEN[\s\S]*_grant_agenda_block_xp/);
      const gates = (MIGRATION_SQL.match(/can_by_member\(v_caller, 'manage_event'\)/g) || []).length;
      assert.ok(gates >= 3, `expected manage_event gate on the 3 coordination RPCs; got ${gates}`);
    });

    it('revoke flips status to no_show and deletes the protagonismo ledger row', () => {
      assert.match(MIGRATION_SQL, /DELETE FROM public\.gamification_points[\s\S]*category = 'agenda_block_protagonismo'/);
      assert.match(MIGRATION_SQL, /SET status = 'no_show', confirmed_at = NULL/);
    });

    it('first_time bonus computed at confirmation, never persisted (anti-gaming)', () => {
      assert.match(MIGRATION_SQL, /NOT EXISTS \([\s\S]*status = 'confirmed' AND id <> p_block_id[\s\S]*agenda_block_bonus_first_time/);
    });

    it('grants: helper is internal; confirm/revoke authenticated-only (anon revoked)', () => {
      assert.match(MIGRATION_SQL, /REVOKE ALL ON FUNCTION public\._grant_agenda_block_xp\(uuid\)\s*FROM PUBLIC, anon, authenticated/);
      assert.match(MIGRATION_SQL, /REVOKE ALL ON FUNCTION public\.confirm_agenda_block\(uuid\)\s*FROM PUBLIC, anon/);
      assert.match(MIGRATION_SQL, /GRANT EXECUTE ON FUNCTION public\.confirm_agenda_block\(uuid\)\s*TO authenticated/);
    });

    it('NOTIFY pgrst trailer present', () => assert.match(MIGRATION_SQL, /NOTIFY pgrst, 'reload schema';/));
  });

  if (sb) {
    describe('DB-gated assertions', () => {
      it('protagonismo rules are live with the expected bonus amounts', async () => {
        const { data, error } = await sb
          .from('gamification_rules')
          .select('slug, base_points, pillar')
          .eq('pillar', 'protagonismo');
        if (error) assert.fail(`query error: ${error.message}`);
        const by = Object.fromEntries((data || []).map((r) => [r.slug, r.base_points]));
        assert.equal(by['agenda_block_protagonismo'], 0, 'credit anchor base lives in the format, not the rule');
        assert.equal(by['agenda_block_bonus_external_guest'], 2);
        assert.equal(by['agenda_block_bonus_shared_material'], 1);
        assert.equal(by['agenda_block_bonus_first_time'], 1);
      });

      it('service-role confirm (no auth.uid()) returns not_authenticated, never writes', async () => {
        const { data, error } = await sb.rpc('confirm_agenda_block', {
          p_block_id: '00000000-0000-0000-0000-000000000000',
        });
        assert.ok(!error, `rpc call itself should succeed; got ${error?.message}`);
        assert.equal(data?.error, 'not_authenticated', `expected not_authenticated; got ${JSON.stringify(data)}`);
      });
    });
  } else {
    describe('DB-gated assertions', () => {
      it.skip('SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY not set — DB checks skipped', () => {});
    });
  }

  describe('anon-path assertions', () => {
    for (const fn of RPCS) {
      it(`anon CANNOT execute ${fn} (REVOKE anon)`, { skip: !anon }, async () => {
        const { error } = await anon.rpc(fn, fn === 'confirm_event_blocks'
          ? { p_event_id: '00000000-0000-0000-0000-000000000000' }
          : { p_block_id: '00000000-0000-0000-0000-000000000000' });
        assert.ok(error, `anon must be permission-denied on ${fn}`);
      });
    }
  });
});
