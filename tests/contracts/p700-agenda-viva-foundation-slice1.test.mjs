import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// #700 Agenda Viva [Foundation] — SLICE 1: schema + catalog + RLS + V4 action seed.
// event_agenda_blocks + agenda_block_formats (8 seeded) + reserve_agenda_block action
// seeded for all active "doer" engagement combos (PM 2026-06-15). RPCs/XP land in slices 2-3.

const MIGRATION_PATH = 'supabase/migrations/20260805000177_700_agenda_viva_foundation_slice1.sql';
const MIGRATION_SQL = readFileSync(MIGRATION_PATH, 'utf8');

const LOCALES = ['pt-BR', 'en-US', 'es-LATAM'];
const EXPECTED_FORMATS = [
  'prompt_semana', 'review_ferramenta', 'insight_rapido', 'pilula_quinzena',
  'case_aplicado', 'demo_pratica', 'convidado', 'espaco_aberto',
];

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK ? createClient(SUPABASE_URL, SUPABASE_SRK, {
  auth: { persistSession: false }
}) : null;
const anon = SUPABASE_URL && ANON_KEY ? createClient(SUPABASE_URL, ANON_KEY, {
  auth: { persistSession: false }
}) : null;

describe('p700 slice 1 — Agenda Viva foundation (schema + catalog + RLS + action)', () => {
  describe('migration static assertions', () => {
    it('migration file exists', () => {
      assert.ok(MIGRATION_SQL.length > 0);
    });

    it('creates both core tables + audit table', () => {
      assert.match(MIGRATION_SQL, /CREATE TABLE IF NOT EXISTS public\.agenda_block_formats/);
      assert.match(MIGRATION_SQL, /CREATE TABLE IF NOT EXISTS public\.event_agenda_blocks/);
      assert.match(MIGRATION_SQL, /CREATE TABLE IF NOT EXISTS public\.event_agenda_block_audit/);
    });

    it('event_agenda_blocks enforces duration multiple-of-5 and one block per person/event', () => {
      assert.match(MIGRATION_SQL, /duration_min\s+integer NOT NULL CHECK \(duration_min > 0 AND duration_min % 5 = 0\)/);
      assert.match(MIGRATION_SQL, /CONSTRAINT eab_one_block_per_person_per_event UNIQUE \(event_id, owner_member_id\)/);
    });

    it('status CHECK lists the 4 lifecycle states', () => {
      assert.match(MIGRATION_SQL, /status IN \('reserved','confirmed','cancelled','no_show'\)/);
    });

    it('seeds the 8 block formats', () => {
      for (const slug of EXPECTED_FORMATS) {
        assert.ok(MIGRATION_SQL.includes(`('${slug}',`), `must seed format ${slug}`);
      }
    });

    it('enables RLS + revokes anon on the blocks table; catalog readable by anon', () => {
      assert.match(MIGRATION_SQL, /ALTER TABLE public\.event_agenda_blocks\s+ENABLE ROW LEVEL SECURITY/);
      assert.match(MIGRATION_SQL, /REVOKE ALL ON public\.event_agenda_blocks\s+FROM anon, PUBLIC/);
      assert.match(MIGRATION_SQL, /GRANT SELECT ON public\.agenda_block_formats\s+TO anon, authenticated/);
    });

    it('blocks table grants SELECT to authenticated only (no anon table read)', () => {
      assert.match(MIGRATION_SQL, /GRANT SELECT ON public\.event_agenda_blocks\s+TO authenticated;/);
      assert.doesNotMatch(MIGRATION_SQL, /GRANT SELECT ON public\.event_agenda_blocks\s+TO anon/);
    });

    it('seeds the new V4 action reserve_agenda_block at organization scope', () => {
      assert.match(MIGRATION_SQL, /'reserve_agenda_block', 'organization'/);
      // rank-and-file volunteer/researcher must be in the seed (PM 2026-06-15 decision)
      assert.match(MIGRATION_SQL, /\('volunteer','researcher'\)/);
    });

    it('NOTIFY pgrst trailer present', () => {
      assert.match(MIGRATION_SQL, /NOTIFY pgrst, 'reload schema';/);
    });
  });

  if (sb) {
    describe('DB-gated assertions (with SUPABASE_SERVICE_ROLE_KEY)', () => {
      it('8 formats seeded with full trilingual i18n parity', async () => {
        const { data, error } = await sb.from('agenda_block_formats').select('slug, label_i18n, base_points, default_duration_min');
        if (error) assert.fail(`probe error: ${error.message}`);
        assert.equal(data.length, 8, 'expect exactly 8 seeded formats');
        for (const row of data) {
          for (const loc of LOCALES) {
            assert.ok(row.label_i18n?.[loc], `format ${row.slug} missing ${loc} label`);
          }
          assert.ok(row.default_duration_min % 5 === 0, `${row.slug} duration must be multiple of 5`);
        }
      });

      it('reserve_agenda_block seeded for all 27 doer combos at org scope', async () => {
        const { data, error } = await sb
          .from('engagement_kind_permissions')
          .select('kind, role, scope')
          .eq('action', 'reserve_agenda_block');
        if (error) assert.fail(`probe error: ${error.message}`);
        assert.equal(data.length, 27, `expect 27 doer combos; got ${data.length}`);
        assert.ok(data.every(r => r.scope === 'organization'), 'all combos must be org-scoped');
        assert.ok(
          data.some(r => r.kind === 'volunteer' && r.role === 'researcher'),
          'rank-and-file volunteer/researcher must be granted'
        );
      });

      it('AUTHORITY: pure non-doer members are NOT granted reserve_agenda_block', async () => {
        // can() resolution is verified via a SQL probe RPC if present; otherwise assert the
        // negative via the seed shape: no non-doer kind appears in the action seed.
        const { data, error } = await sb
          .from('engagement_kind_permissions')
          .select('kind')
          .eq('action', 'reserve_agenda_block');
        if (error) assert.fail(`probe error: ${error.message}`);
        const nonDoerKinds = ['observer', 'sponsor', 'speaker', 'ambassador', 'chapter_board', 'external_reviewer'];
        const seededKinds = new Set(data.map(r => r.kind));
        for (const k of nonDoerKinds) {
          assert.ok(!seededKinds.has(k), `non-doer kind ${k} must NOT be in the reserve_agenda_block seed`);
        }
      });

      it('LGPD: anon cannot read event_agenda_blocks but CAN read the format catalog', { skip: !anon }, async () => {
        // anon must be denied at the privilege layer (REVOKE + no anon grant → PostgREST 403).
        // Assert the error specifically so a future inadvertent `GRANT SELECT TO anon` fails the
        // test instead of silently passing on an empty table.
        const blocks = await anon.from('event_agenda_blocks').select('id').limit(1);
        assert.ok(blocks.error, `anon must be permission-denied on event_agenda_blocks; got data ${JSON.stringify(blocks.data)}`);
        // anon may read the catalog (needed to render the public agenda UI)
        const formats = await anon.from('agenda_block_formats').select('slug').limit(1);
        assert.ok(!formats.error, `anon must read agenda_block_formats; got error: ${formats.error?.message}`);
      });
    });
  } else {
    describe('DB-gated assertions', () => {
      it.skip('SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY not set — DB checks skipped', () => {});
    });
  }
});
