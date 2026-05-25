import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// p265 #312-W4f (#382 — Foundation PR-A of 2) — Implements ADR-0099 §6 steps 1-9
// Foundation: content_products canonical surface + bridges + 37-row backfill
// + 2 SECDEF RPCs + invariant W. PR-B (next session) ships §7 blind-review
// primitives and closes #382.
//
// Sediments respected:
// - SEDIMENT-186.C: this file added to BOTH "test" + "test:contracts" whitelists.
// - SEDIMENT-235.A: this file's name internally tags #382 — PR title/body must
//   NOT include "Closes #382" (PR-A is Foundation only).
// - SEDIMENT-238.C: check_schema_invariants() CREATE OR REPLACE preserves all
//   21 existing RETURN QUERY blocks verbatim + appends W as the 22nd.
// - SEDIMENT-239b.A: SECDEF RPCs are pure SELECTs; no FK column source issue.

const MIGRATION_PATH = 'supabase/migrations/20260805000045_p265_382_w4f_content_products_foundation.sql';
const MIGRATION_SQL  = readFileSync(MIGRATION_PATH, 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK ? createClient(SUPABASE_URL, SUPABASE_SRK, {
  auth: { persistSession: false }
}) : null;

describe('p265 #382 W4f Foundation — content_products canonical surface (ADR-0099 §6)', () => {
  describe('migration file presence + header cross-refs', () => {
    it('migration file exists at canonical timestamp 20260805000045', () => {
      assert.ok(existsSync(MIGRATION_PATH));
      assert.ok(MIGRATION_SQL.length > 0);
    });

    it('header documents WHAT / WHY / ROLLBACK / Sediments / Backfill invariants', () => {
      assert.match(MIGRATION_SQL, /WHAT/);
      assert.match(MIGRATION_SQL, /WHY/);
      assert.match(MIGRATION_SQL, /ROLLBACK/);
      assert.match(MIGRATION_SQL, /SEDIMENT-186\.C/);
      assert.match(MIGRATION_SQL, /SEDIMENT-238\.C/);
      assert.match(MIGRATION_SQL, /Backfill correctness invariants/);
    });

    it('header cross-refs ADR-0099 + #382 (this PR-A) + spec §6.1 + §15.7 + §16.5', () => {
      assert.match(MIGRATION_SQL, /ADR-0099/);
      assert.match(MIGRATION_SQL, /#382/);
      assert.match(MIGRATION_SQL, /§6\.1/);
      assert.match(MIGRATION_SQL, /§15\.7/);
      assert.match(MIGRATION_SQL, /§16\.5/);
    });

    it('header anchors p265 + PR-B (§7 blind-review primitives) sequencing', () => {
      assert.match(MIGRATION_SQL, /p265/);
      assert.match(MIGRATION_SQL, /PR-B/);
      assert.match(MIGRATION_SQL, /blind-review/);
    });
  });

  describe('§6 step 1a — Three new enums + content_product_instrument superset', () => {
    it('content_product_source_kind enum (5 values: governance_document_version, board_item, publication_idea, external, none)', () => {
      assert.match(MIGRATION_SQL, /CREATE TYPE public\.content_product_source_kind AS ENUM/);
      assert.match(MIGRATION_SQL, /'governance_document_version'/);
      assert.match(MIGRATION_SQL, /'board_item'/);
      assert.match(MIGRATION_SQL, /'publication_idea'/);
      assert.match(MIGRATION_SQL, /'external'/);
      assert.match(MIGRATION_SQL, /'none'/);
    });

    it('review_mode enum (4 values per ADR-0099 §2.5)', () => {
      assert.match(MIGRATION_SQL, /CREATE TYPE public\.review_mode AS ENUM/);
      assert.match(MIGRATION_SQL, /'collaborative'/);
      assert.match(MIGRATION_SQL, /'sequential'/);
      assert.match(MIGRATION_SQL, /'independent_blind'/);
      assert.match(MIGRATION_SQL, /'governance_commentary'/);
    });

    it('content_product_status enum (6 FSM states per ADR-0099 §2.6)', () => {
      assert.match(MIGRATION_SQL, /CREATE TYPE public\.content_product_status AS ENUM/);
      for (const status of ['idea','drafted','under_review','approved','published','archived']) {
        assert.match(MIGRATION_SQL, new RegExp(`'${status}'`));
      }
    });

    it('content_product_instrument enum (14 values = 8 from submission_target_type + 6 new per ADR §2.4)', () => {
      assert.match(MIGRATION_SQL, /CREATE TYPE public\.content_product_instrument AS ENUM/);
      // 8 existing
      for (const v of ['pmi_global_conference','pmi_chapter_event','academic_journal','academic_conference','webinar','blog_post','other','linkedin_newsletter']) {
        assert.match(MIGRATION_SQL, new RegExp(`'${v}'`));
      }
      // 6 new
      for (const v of ['linkedin_post','medium_article','youtube_video','podcast_episode','hub_article','magazine_article']) {
        assert.match(MIGRATION_SQL, new RegExp(`'${v}'`));
      }
    });

    it('FORWARD-DEFENSE: submission_target_type NOT extended in place (avoids ALTER TYPE in-transaction constraint)', () => {
      // The chosen pattern is "new enum content_product_instrument" instead of
      // "ALTER TYPE submission_target_type ADD VALUE ..." (which cannot run
      // alongside CREATE TABLE that references the type in a single migration).
      // Forward-defense: future drift toward "extend in place" would be caught here.
      assert.doesNotMatch(MIGRATION_SQL, /ALTER TYPE public\.submission_target_type ADD VALUE/);
    });
  });

  describe('§6 step 1b — content_products table schema', () => {
    it('CREATE TABLE public.content_products with PK + organization_id NOT NULL FK', () => {
      assert.match(MIGRATION_SQL, /CREATE TABLE public\.content_products/);
      assert.match(MIGRATION_SQL, /id uuid PRIMARY KEY DEFAULT gen_random_uuid\(\)/);
      assert.match(MIGRATION_SQL, /organization_id uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906'/);
      assert.match(MIGRATION_SQL, /REFERENCES public\.organizations\(id\) ON DELETE RESTRICT/);
    });

    it('discriminated tagged FK source columns (4 FK cols + URI per ADR-0099 §2.2)', () => {
      assert.match(MIGRATION_SQL, /source_kind public\.content_product_source_kind NOT NULL/);
      assert.match(MIGRATION_SQL, /source_document_version_id uuid NULL REFERENCES public\.document_versions\(id\) ON DELETE RESTRICT/);
      assert.match(MIGRATION_SQL, /source_board_item_id uuid NULL REFERENCES public\.board_items\(id\) ON DELETE RESTRICT/);
      assert.match(MIGRATION_SQL, /source_publication_idea_id uuid NULL REFERENCES public\.publication_ideas\(id\) ON DELETE RESTRICT/);
      assert.match(MIGRATION_SQL, /source_external_uri text NULL/);
    });

    it('discriminated source CHECK enforces "exactly one populated per source_kind" (5 branches)', () => {
      assert.match(MIGRATION_SQL, /CONSTRAINT chk_content_products_source_integrity CHECK/);
      // 5 source_kind branches
      assert.match(MIGRATION_SQL, /source_kind = 'governance_document_version'/);
      assert.match(MIGRATION_SQL, /source_kind = 'board_item'/);
      assert.match(MIGRATION_SQL, /source_kind = 'publication_idea'/);
      assert.match(MIGRATION_SQL, /source_kind = 'external'/);
      assert.match(MIGRATION_SQL, /source_kind = 'none'/);
    });

    it('target_instrument + review_mode + status NOT NULL + status DEFAULT idea', () => {
      assert.match(MIGRATION_SQL, /target_instrument public\.content_product_instrument NOT NULL/);
      assert.match(MIGRATION_SQL, /review_mode public\.review_mode NOT NULL/);
      assert.match(MIGRATION_SQL, /status public\.content_product_status NOT NULL DEFAULT 'idea'/);
    });

    it('derived_group_id self-FK + initiative_id + proposer_member_id linkage (ADR §2.3)', () => {
      assert.match(MIGRATION_SQL, /derived_group_id uuid NULL REFERENCES public\.content_products\(id\) ON DELETE SET NULL/);
      assert.match(MIGRATION_SQL, /initiative_id uuid NULL REFERENCES public\.initiatives\(id\) ON DELETE SET NULL/);
      assert.match(MIGRATION_SQL, /proposer_member_id uuid NULL REFERENCES public\.members\(id\) ON DELETE SET NULL/);
    });

    it('review_round smallint with CHECK >= 1 (SPEC §6.1 round support)', () => {
      assert.match(MIGRATION_SQL, /review_round smallint NOT NULL DEFAULT 1/);
      assert.match(MIGRATION_SQL, /CONSTRAINT chk_content_products_review_round_positive CHECK \(review_round >= 1\)/);
    });

    it('RLS enabled + permissive SELECT policy for active members (published/approved or own)', () => {
      assert.match(MIGRATION_SQL, /ALTER TABLE public\.content_products ENABLE ROW LEVEL SECURITY/);
      assert.match(MIGRATION_SQL, /CREATE POLICY content_products_authenticated_read[\s\S]*?FOR SELECT[\s\S]*?TO authenticated/);
    });

    it('FORWARD-DEFENSE: NO polymorphic source_type text + source_id uuid columns (ADR-0099 §2.2 retires that pattern)', () => {
      // publication_ideas has the polymorphic shape this ADR retires;
      // content_products MUST NOT replicate it.
      assert.doesNotMatch(MIGRATION_SQL, /CREATE TABLE public\.content_products[\s\S]*?source_type text/);
      assert.doesNotMatch(MIGRATION_SQL, /CREATE TABLE public\.content_products[\s\S]*?source_id uuid[^_]/);
    });

    it('FORWARD-DEFENSE: source_kind enum-typed, NOT text + CHECK pattern', () => {
      // Defensive against future "simplification" that swaps the enum for text.
      // The enum gives Postgres-enforced type safety on top of the CHECK.
      const tableBlockMatch = MIGRATION_SQL.match(/CREATE TABLE public\.content_products[\s\S]*?\);/);
      assert.ok(tableBlockMatch, 'content_products CREATE TABLE block found');
      const tableBlock = tableBlockMatch[0];
      assert.match(tableBlock, /source_kind public\.content_product_source_kind/);
    });
  });

  describe('§6 steps 2-3 — Bridge columns on board_items + publication_submissions', () => {
    it('board_items.content_product_id ADD COLUMN NULL ON DELETE SET NULL (operational ↔ product bridge)', () => {
      assert.match(MIGRATION_SQL, /ALTER TABLE public\.board_items[\s\S]*?ADD COLUMN content_product_id uuid NULL[\s\S]*?REFERENCES public\.content_products\(id\) ON DELETE SET NULL/);
    });

    it('publication_submissions.content_product_id ADD COLUMN ON DELETE RESTRICT (every submission must trace to product)', () => {
      assert.match(MIGRATION_SQL, /ALTER TABLE public\.publication_submissions[\s\S]*?ADD COLUMN content_product_id uuid NULL[\s\S]*?REFERENCES public\.content_products\(id\) ON DELETE RESTRICT/);
    });

    it('publication_submissions.content_product_id ALTER SET NOT NULL after backfill (ADR §6 step 3)', () => {
      assert.match(MIGRATION_SQL, /ALTER TABLE public\.publication_submissions[\s\S]*?ALTER COLUMN content_product_id SET NOT NULL/);
    });

    it('bridge indexes created on both bridge columns', () => {
      assert.match(MIGRATION_SQL, /CREATE INDEX idx_board_items_content_product/);
      assert.match(MIGRATION_SQL, /CREATE INDEX idx_publication_submissions_content_product/);
    });
  });

  describe('§6 step 4 — 37-row backfill from publication_submissions', () => {
    it('backfill uses source_kind=external + COALESCE(doi_or_url, target_url, target_name) URI', () => {
      assert.match(MIGRATION_SQL, /'external'::public\.content_product_source_kind/);
      assert.match(MIGRATION_SQL, /COALESCE\(pws\.doi_or_url, pws\.target_url, pws\.target_name\)/);
    });

    it('status mapping: published if acceptance_date NOT NULL else under_review (ADR §6 step 4)', () => {
      assert.match(MIGRATION_SQL, /WHEN pws\.acceptance_date IS NOT NULL THEN 'published'::public\.content_product_status/);
      assert.match(MIGRATION_SQL, /ELSE 'under_review'::public\.content_product_status/);
    });

    it('default-per-instrument review_mode matrix (ADR §2.5)', () => {
      assert.match(MIGRATION_SQL, /WHEN 'pmi_global_conference' THEN 'independent_blind'::public\.review_mode/);
      assert.match(MIGRATION_SQL, /WHEN 'academic_journal' THEN 'independent_blind'::public\.review_mode/);
      assert.match(MIGRATION_SQL, /WHEN 'blog_post' THEN 'sequential'::public\.review_mode/);
      assert.match(MIGRATION_SQL, /WHEN 'webinar' THEN 'collaborative'::public\.review_mode/);
    });

    it('sanity DO block raises EXCEPTION if not exactly 37 stubs + 37 linked + 0 unlinked + 8 bridged', () => {
      const sanityBlock = MIGRATION_SQL.match(/DO \$sanity\$([\s\S]*?)\$sanity\$;/);
      assert.ok(sanityBlock, 'sanity DO block found');
      const sanity = sanityBlock[1];
      assert.match(sanity, /expected 37 stub products/);
      assert.match(sanity, /expected 37 linked submissions/);
      assert.match(sanity, /submissions still unlinked/);
      assert.match(sanity, /expected 8 bridged board_items/);
    });

    it('publication_metadata captures full lineage (backfill_source + publication_submission_id + dates)', () => {
      assert.match(MIGRATION_SQL, /'backfill_source', 'publication_submissions'/);
      assert.match(MIGRATION_SQL, /'publication_submission_id', pws\.submission_id/);
      assert.match(MIGRATION_SQL, /'doi_or_url', pws\.doi_or_url/);
    });
  });

  describe('§6 steps 6+7 — SECDEF RPCs (reader + list)', () => {
    it('get_content_product_reader(uuid) RETURNS jsonb + STABLE SECDEF + pinned search_path', () => {
      assert.match(MIGRATION_SQL, /CREATE OR REPLACE FUNCTION public\.get_content_product_reader\(p_product_id uuid\)/);
      assert.match(MIGRATION_SQL, /RETURNS jsonb[\s\S]*?STABLE[\s\S]*?SECURITY DEFINER[\s\S]*?SET search_path TO 'public', 'pg_temp'/);
    });

    it('get_content_product_reader gates active member + applies V4 admin/curator/proposer ladder', () => {
      assert.match(MIGRATION_SQL, /Unauthorized: no active member record/);
      assert.match(MIGRATION_SQL, /v_caller_is_admin := public\.can_by_member\(v_caller_member_id, 'manage_member'\)/);
      assert.match(MIGRATION_SQL, /v_caller_is_curator := public\.can_by_member\(v_caller_member_id, 'curate_content'\)/);
    });

    it('get_content_product_reader returns privacy-preserving null-envelope on miss or status block (no 404/403 oracle)', () => {
      assert.match(MIGRATION_SQL, /jsonb_build_object\('ok', true, 'product', NULL, 'source_summary', NULL\)/);
    });

    it('list_content_products(jsonb) RETURNS jsonb + same gate ladder + pagination', () => {
      assert.match(MIGRATION_SQL, /CREATE OR REPLACE FUNCTION public\.list_content_products\(p_filters jsonb DEFAULT '\{\}'::jsonb\)/);
      assert.match(MIGRATION_SQL, /v_limit := GREATEST\(1, LEAST\(200, COALESCE\(\(p_filters->>'limit'\)::int, 50\)\)\)/);
    });

    it('REVOKE EXECUTE FROM PUBLIC + GRANT EXECUTE TO authenticated for both RPCs', () => {
      assert.match(MIGRATION_SQL, /REVOKE EXECUTE ON FUNCTION public\.get_content_product_reader\(uuid\) FROM PUBLIC/);
      assert.match(MIGRATION_SQL, /GRANT EXECUTE ON FUNCTION public\.get_content_product_reader\(uuid\) TO authenticated/);
      assert.match(MIGRATION_SQL, /REVOKE EXECUTE ON FUNCTION public\.list_content_products\(jsonb\) FROM PUBLIC/);
      assert.match(MIGRATION_SQL, /GRANT EXECUTE ON FUNCTION public\.list_content_products\(jsonb\) TO authenticated/);
    });
  });

  describe('§6 step 9 — Invariant W in check_schema_invariants()', () => {
    it('CREATE OR REPLACE FUNCTION check_schema_invariants() preserves return signature + properties', () => {
      assert.match(MIGRATION_SQL, /CREATE OR REPLACE FUNCTION public\.check_schema_invariants\(\)[\s\S]*?RETURNS TABLE\(invariant_name text, description text, severity text, violation_count integer, sample_ids uuid\[\]\)/);
      assert.match(MIGRATION_SQL, /STABLE SECURITY DEFINER[\s\S]*?SET search_path TO 'public', 'pg_temp'/);
    });

    it('W_content_product_source_integrity block appended with high severity', () => {
      assert.match(MIGRATION_SQL, /'W_content_product_source_integrity'::text/);
      assert.match(MIGRATION_SQL, /'high'::text/);
      assert.match(MIGRATION_SQL, /ADR-0099 §2\.2 \+ §6 step 9/);
    });

    it('SEDIMENT-238.C — all 21 prior invariants preserved verbatim (A1, A2, A3, B, C, D, E, F, J, K, L, M, N, O, P, Q, R, S, T, V_prime, V)', () => {
      // Spot-check first/last + tricky ones (P is the only one with NULL::uuid[] sample)
      for (const inv of [
        'A1_alumni_role_consistency',
        'A2_observer_role_consistency',
        'A3_active_role_engagement_derivation',
        'B_is_active_status_mismatch',
        'J_current_version_published',
        'P_tribe_initiative_bridge_complete',
        'T_member_has_exactly_one_primary_email',
        'V_prime_pending_proposer_consent_no_open_chain',
        'V_status_chain_coherence',
        'W_content_product_source_integrity'
      ]) {
        assert.match(MIGRATION_SQL, new RegExp(`'${inv.replace(/_/g, '_')}'::text`));
      }
    });
  });

  describe('Trigger + reload', () => {
    it('updated_at BEFORE UPDATE trigger created (audit hygiene)', () => {
      assert.match(MIGRATION_SQL, /CREATE OR REPLACE FUNCTION public\.trg_content_products_set_updated_at\(\)/);
      assert.match(MIGRATION_SQL, /CREATE TRIGGER trg_content_products_updated_at[\s\S]*?BEFORE UPDATE ON public\.content_products/);
    });

    it('NOTIFY pgrst, reload schema at migration tail', () => {
      assert.match(MIGRATION_SQL, /NOTIFY pgrst, 'reload schema'/);
    });
  });

  describe('DB-gated smoke (requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY)', () => {
    it('content_products has exactly 37 backfilled rows from publication_submissions', { skip: !sb }, async () => {
      const { data, error } = await sb
        .from('content_products')
        .select('id', { count: 'exact', head: true });
      assert.equal(error, null);
      // Live verification — backfill produces 37 rows.
      // Check total separately (head:true only returns count metadata via response).
      const { data: rows, error: e2 } = await sb
        .from('content_products')
        .select('id, source_kind, publication_metadata');
      assert.equal(e2, null);
      assert.equal(rows.length, 37);
      assert.ok(rows.every(r => r.source_kind === 'external'));
      assert.ok(rows.every(r => r.publication_metadata?.backfill_source === 'publication_submissions'));
    });

    it('check_schema_invariants() reports 22 invariants with W violation_count=0', { skip: !sb }, async () => {
      const { data, error } = await sb.rpc('check_schema_invariants');
      assert.equal(error, null);
      assert.equal(data.length, 22);
      const w = data.find(r => r.invariant_name === 'W_content_product_source_integrity');
      assert.ok(w, 'W invariant present');
      assert.equal(w.violation_count, 0);
      assert.equal(w.severity, 'high');
      // No regressions on V/V' from p256/p257
      const vPrime = data.find(r => r.invariant_name === 'V_prime_pending_proposer_consent_no_open_chain');
      const vStatus = data.find(r => r.invariant_name === 'V_status_chain_coherence');
      assert.equal(vPrime.violation_count, 0);
      assert.equal(vStatus.violation_count, 0);
    });

    it('publication_submissions.content_product_id NOT NULL: all 37 rows linked, 0 NULL', { skip: !sb }, async () => {
      const { count, error } = await sb
        .from('publication_submissions')
        .select('id', { count: 'exact', head: true })
        .is('content_product_id', null);
      assert.equal(error, null);
      assert.equal(count, 0);
    });

    it('board_items.content_product_id populated for exactly 8 board_items (bridges from publication_submissions.board_item_id)', { skip: !sb }, async () => {
      const { count, error } = await sb
        .from('board_items')
        .select('id', { count: 'exact', head: true })
        .not('content_product_id', 'is', null);
      assert.equal(error, null);
      assert.equal(count, 8);
    });
  });
});
