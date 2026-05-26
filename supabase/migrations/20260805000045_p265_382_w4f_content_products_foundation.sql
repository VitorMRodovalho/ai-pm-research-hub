-- Migration: 20260805000045_p265_382_w4f_content_products_foundation
-- Date:      2026-05-26 (Session p265)
-- Issue:     #382 (W4f blind-review primitives — Foundation PR-A of 2)
-- ADR:       0099 (content_products canonical surface — §6 steps 1-9 Foundation)
-- Spec ref:  SPEC_GOVERNANCE_DOCUMENTS_END_TO_END §6.1 + §15.7 step 5 + §16.5 row 4
--
-- WHAT
-- ----
-- Foundation migration for ADR-0099 §6 (steps 1-9). Creates the canonical
-- content_products surface + bridges to existing operational tables, backfills
-- 37 stub products from publication_submissions, adds 2 SECDEF RPCs (reader +
-- list mirroring p263 W4d + p256 M3 patterns), and adds invariant W to
-- check_schema_invariants() for source-CHECK ratchet visibility.
--
-- PR-B (next session p266) ships §7 blind-review primitives (3 tables + RLS +
-- visibility RPC + release RPC) and closes #382.
--
-- WHY
-- ---
-- Per ADR-0099 §1.2: derived editorial outputs (LinkedIn post, Newsletter,
-- blog/Hub article, magazine, journal submission, etc.) have no canonical
-- home today. They split across publication_ideas (1 row, polymorphic),
-- publication_submissions (37 rows, submission ≠ product), board_items
-- (operational), and document_comments (governance). ADR-0099 ratifies
-- content_products as the canonical artifact, disjoint from
-- governance_documents.
--
-- Per ADR-0099 §2.7: blind-review (#382) MUST FK to content_products.id
-- via a single deterministic content_product_id column. Foundation must
-- ship first so PR-B blind-review primitives have a stable FK target.
--
-- Sediments respected
-- -------------------
-- - SEDIMENT-186.C: new contract test file `tests/contracts/p265-382-w4f-content-products-foundation.test.mjs`
--   added to BOTH `test` and `test:contracts` whitelists pre-`npm test`.
-- - SEDIMENT-225.B: comments preserved; Phase C body-drift gate must pass
--   after deploy. If drift detected on check_schema_invariants, minimum-diff
--   fix is to strip mismatched comments from this file to match live.
-- - SEDIMENT-238.C: check_schema_invariants() CREATE OR REPLACE preserves all
--   parameter DEFAULTs (there are none — function takes no args) and ALL 21
--   existing RETURN QUERY branches verbatim. W is appended before END;.
-- - SEDIMENT-239b.A: SECDEF RPCs write no rows; reader/list are pure SELECTs.
--   No FK column source issue. Future PR-B (which DOES insert into FK tables)
--   must apply the column-source forward-defense pattern.
-- - SEDIMENT-254.A: NO ad-hoc clean-up of supabase_migrations.schema_migrations.
--
-- Backfill correctness invariants (enforced via sanity DO block):
-- - 37 stub content_products created (one per publication_submissions row)
-- - 37 publication_submissions linked (content_product_id NOT NULL post-backfill)
-- - 8 board_items bridged (those with board_item_id referenced by a publication_submission)
--
-- ROLLBACK
-- --------
-- (Reverse order; preserve atomicity; assumes no consumer has started writing yet)
-- 1.  ALTER TABLE public.publication_submissions ALTER COLUMN content_product_id DROP NOT NULL;
-- 2.  ALTER TABLE public.publication_submissions DROP COLUMN content_product_id;
-- 3.  ALTER TABLE public.board_items DROP COLUMN content_product_id;
-- 4.  Restore check_schema_invariants() to pre-p265 body (without W block).
-- 5.  DROP FUNCTION public.list_content_products(jsonb);
-- 6.  DROP FUNCTION public.get_content_product_reader(uuid);
-- 7.  DROP FUNCTION public.trg_content_products_set_updated_at();
-- 8.  DROP TABLE public.content_products CASCADE;
-- 9.  DROP TYPE public.content_product_status;
-- 10. DROP TYPE public.review_mode;
-- 11. DROP TYPE public.content_product_source_kind;
-- 12. DROP TYPE public.content_product_instrument;
-- 13. NOTIFY pgrst, 'reload schema';
-- (No data loss: backfill is recoverable from publication_submissions which keeps its rows.)

BEGIN;

-- ============================================================================
-- §6 STEP 1a — Enums (new)
-- ============================================================================

CREATE TYPE public.content_product_source_kind AS ENUM (
  'governance_document_version',
  'board_item',
  'publication_idea',
  'external',
  'none'
);

CREATE TYPE public.review_mode AS ENUM (
  'collaborative',
  'sequential',
  'independent_blind',
  'governance_commentary'
);

CREATE TYPE public.content_product_status AS ENUM (
  'idea',
  'drafted',
  'under_review',
  'approved',
  'published',
  'archived'
);

-- content_product_instrument: superset of submission_target_type (8 existing + 6 new per ADR-0099 §2.4).
-- ADR-0099 §2.4 leaves the choice open between "extend existing enum" vs "new enum".
-- Chosen: new enum, because (a) ALTER TYPE ADD VALUE cannot run inside an
-- atomic migration alongside the CREATE TABLE that USES the type, (b) keeps
-- publication_submissions.target_type semantically distinct as "the formal
-- submission instrument", and (c) avoids cross-table semantic coupling.
-- The two enums are value-aligned (text-cast safe in backfill).
CREATE TYPE public.content_product_instrument AS ENUM (
  -- 8 existing values (parity with submission_target_type)
  'pmi_global_conference',
  'pmi_chapter_event',
  'academic_journal',
  'academic_conference',
  'webinar',
  'blog_post',
  'other',
  'linkedin_newsletter',
  -- 6 new values (ADR-0099 §2.4 extension)
  'linkedin_post',
  'medium_article',
  'youtube_video',
  'podcast_episode',
  'hub_article',
  'magazine_article'
);

-- ============================================================================
-- §6 STEP 1b — content_products table
-- ============================================================================

CREATE TABLE public.content_products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid
    REFERENCES public.organizations(id) ON DELETE RESTRICT,

  -- Identity
  title text NOT NULL,
  summary text NULL,

  -- Source (ADR-0099 §2.2 — discriminated tagged FK; NOT polymorphic)
  source_kind public.content_product_source_kind NOT NULL,
  source_document_version_id uuid NULL REFERENCES public.document_versions(id) ON DELETE RESTRICT,
  source_board_item_id uuid NULL REFERENCES public.board_items(id) ON DELETE RESTRICT,
  source_publication_idea_id uuid NULL REFERENCES public.publication_ideas(id) ON DELETE RESTRICT,
  source_external_uri text NULL,
  CONSTRAINT chk_content_products_source_integrity CHECK (
    (source_kind = 'governance_document_version'
       AND source_document_version_id IS NOT NULL
       AND source_board_item_id IS NULL
       AND source_publication_idea_id IS NULL
       AND source_external_uri IS NULL)
    OR (source_kind = 'board_item'
          AND source_board_item_id IS NOT NULL
          AND source_document_version_id IS NULL
          AND source_publication_idea_id IS NULL
          AND source_external_uri IS NULL)
    OR (source_kind = 'publication_idea'
          AND source_publication_idea_id IS NOT NULL
          AND source_document_version_id IS NULL
          AND source_board_item_id IS NULL
          AND source_external_uri IS NULL)
    OR (source_kind = 'external'
          AND source_external_uri IS NOT NULL
          AND source_document_version_id IS NULL
          AND source_board_item_id IS NULL
          AND source_publication_idea_id IS NULL)
    OR (source_kind = 'none'
          AND source_document_version_id IS NULL
          AND source_board_item_id IS NULL
          AND source_publication_idea_id IS NULL
          AND source_external_uri IS NULL)
  ),

  -- Target (ADR-0099 §2.4 + SPEC §6.1 advisory fields)
  target_instrument public.content_product_instrument NOT NULL,
  target_audience text NULL,
  target_language_policy text NULL,
  target_length_policy text NULL,

  -- Review semantics (ADR-0099 §2.5 + SPEC §6.1)
  review_mode public.review_mode NOT NULL,
  review_round smallint NOT NULL DEFAULT 1
    CONSTRAINT chk_content_products_review_round_positive CHECK (review_round >= 1),

  -- Lifecycle (ADR-0099 §2.6)
  status public.content_product_status NOT NULL DEFAULT 'idea',

  -- Sibling grouping (ADR-0099 §2.3)
  derived_group_id uuid NULL REFERENCES public.content_products(id) ON DELETE SET NULL,

  -- Linkage to operational graph
  initiative_id uuid NULL REFERENCES public.initiatives(id) ON DELETE SET NULL,
  proposer_member_id uuid NULL REFERENCES public.members(id) ON DELETE SET NULL,

  -- Publication metadata (flexible jsonb for v1; will normalize in future PR if needed)
  publication_metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  -- Audit
  created_by uuid NULL REFERENCES public.members(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz NULL,
  archived_at timestamptz NULL
);

-- Indexes
CREATE INDEX idx_content_products_organization
  ON public.content_products(organization_id);

CREATE INDEX idx_content_products_source_document_version
  ON public.content_products(source_document_version_id)
  WHERE source_document_version_id IS NOT NULL;

CREATE INDEX idx_content_products_source_board_item
  ON public.content_products(source_board_item_id)
  WHERE source_board_item_id IS NOT NULL;

CREATE INDEX idx_content_products_source_publication_idea
  ON public.content_products(source_publication_idea_id)
  WHERE source_publication_idea_id IS NOT NULL;

CREATE INDEX idx_content_products_derived_group
  ON public.content_products(derived_group_id)
  WHERE derived_group_id IS NOT NULL;

CREATE INDEX idx_content_products_initiative
  ON public.content_products(initiative_id)
  WHERE initiative_id IS NOT NULL;

CREATE INDEX idx_content_products_proposer
  ON public.content_products(proposer_member_id);

CREATE INDEX idx_content_products_status_instrument
  ON public.content_products(status, target_instrument);

-- RLS: enable + permissive SELECT for active members (published/approved or own).
-- Direct INSERT/UPDATE/DELETE not permitted via PostgREST; future PR-B will
-- add curator INSERT via dedicated RPCs honoring V4 capabilities. Service-role
-- continues to bypass RLS for backfill/admin paths.
ALTER TABLE public.content_products ENABLE ROW LEVEL SECURITY;

CREATE POLICY content_products_authenticated_read
  ON public.content_products FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid() AND m.is_active = true
    )
    AND (
      status IN ('published'::public.content_product_status, 'approved'::public.content_product_status)
      OR proposer_member_id = (SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid() LIMIT 1)
    )
  );

-- updated_at trigger
CREATE OR REPLACE FUNCTION public.trg_content_products_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_content_products_updated_at
BEFORE UPDATE ON public.content_products
FOR EACH ROW
EXECUTE FUNCTION public.trg_content_products_set_updated_at();

-- ============================================================================
-- §6 STEP 2 — Bridge: board_items.content_product_id (nullable, ON DELETE SET NULL)
-- ============================================================================

ALTER TABLE public.board_items
  ADD COLUMN content_product_id uuid NULL
    REFERENCES public.content_products(id) ON DELETE SET NULL;

CREATE INDEX idx_board_items_content_product
  ON public.board_items(content_product_id)
  WHERE content_product_id IS NOT NULL;

-- ============================================================================
-- §6 STEP 3 — Bridge: publication_submissions.content_product_id
-- (initially nullable for backfill; ALTER SET NOT NULL after backfill)
-- ============================================================================

ALTER TABLE public.publication_submissions
  ADD COLUMN content_product_id uuid NULL
    REFERENCES public.content_products(id) ON DELETE RESTRICT;

CREATE INDEX idx_publication_submissions_content_product
  ON public.publication_submissions(content_product_id);

-- ============================================================================
-- §6 STEP 4 — Backfill 37 stub products from publication_submissions
-- ============================================================================
-- Strategy:
--   - source_kind = 'external' (per ADR-0099 §6 step 4)
--   - source_external_uri = COALESCE(doi_or_url, target_url, target_name)
--   - status = 'published' if acceptance_date IS NOT NULL else 'under_review'
--   - target_instrument = ps.target_type::text::content_product_instrument
--   - review_mode = default-per-instrument matrix (ADR-0099 §2.5)
--   - Title + summary + initiative_id + proposer_member_id + audit fields copied
--   - publication_metadata captures full lineage
--
-- Mechanism: pre-assign UUIDs via CTE → INSERT with explicit IDs → UPDATE
-- publication_submissions.content_product_id + board_items.content_product_id
-- in the same atomic statement. Final SELECT exposes counts to logs (no return
-- value consumed; surfaced via sanity DO block below).

WITH ps_with_stub AS (
  SELECT
    ps.id AS submission_id,
    gen_random_uuid() AS stub_id,
    ps.organization_id,
    ps.title,
    ps.abstract,
    ps.target_type::text AS target_type_text,
    ps.target_name,
    ps.target_url,
    ps.doi_or_url,
    ps.status::text AS submission_status,
    ps.acceptance_date,
    ps.submission_date,
    ps.presentation_date,
    ps.initiative_id,
    ps.primary_author_id,
    ps.created_by,
    ps.created_at,
    ps.updated_at,
    ps.board_item_id
  FROM public.publication_submissions ps
),
ins AS (
  INSERT INTO public.content_products (
    id,
    organization_id,
    title,
    summary,
    source_kind,
    source_external_uri,
    target_instrument,
    review_mode,
    status,
    initiative_id,
    proposer_member_id,
    publication_metadata,
    created_by,
    created_at,
    updated_at,
    published_at
  )
  SELECT
    pws.stub_id,
    pws.organization_id,
    pws.title,
    pws.abstract,
    'external'::public.content_product_source_kind,
    COALESCE(pws.doi_or_url, pws.target_url, pws.target_name),
    pws.target_type_text::public.content_product_instrument,
    CASE pws.target_type_text
      WHEN 'pmi_global_conference' THEN 'independent_blind'::public.review_mode
      WHEN 'pmi_chapter_event' THEN 'sequential'::public.review_mode
      WHEN 'academic_journal' THEN 'independent_blind'::public.review_mode
      WHEN 'academic_conference' THEN 'independent_blind'::public.review_mode
      WHEN 'webinar' THEN 'collaborative'::public.review_mode
      WHEN 'blog_post' THEN 'sequential'::public.review_mode
      WHEN 'linkedin_newsletter' THEN 'sequential'::public.review_mode
      WHEN 'other' THEN 'collaborative'::public.review_mode
      ELSE 'collaborative'::public.review_mode
    END,
    CASE
      WHEN pws.acceptance_date IS NOT NULL THEN 'published'::public.content_product_status
      ELSE 'under_review'::public.content_product_status
    END,
    pws.initiative_id,
    pws.primary_author_id,
    jsonb_build_object(
      'backfill_source', 'publication_submissions',
      'backfill_migration', '20260805000045_p265_382_w4f_content_products_foundation',
      'publication_submission_id', pws.submission_id,
      'submission_status', pws.submission_status,
      'submission_date', pws.submission_date,
      'acceptance_date', pws.acceptance_date,
      'presentation_date', pws.presentation_date,
      'doi_or_url', pws.doi_or_url,
      'target_url', pws.target_url,
      'target_name', pws.target_name
    ),
    pws.created_by,
    pws.created_at,
    pws.updated_at,
    CASE
      WHEN pws.acceptance_date IS NOT NULL
      THEN pws.acceptance_date::timestamptz
      ELSE NULL
    END
  FROM ps_with_stub pws
  RETURNING id
),
ps_update AS (
  UPDATE public.publication_submissions ps
  SET content_product_id = pws.stub_id
  FROM ps_with_stub pws
  WHERE pws.submission_id = ps.id
  RETURNING ps.id
),
bi_update AS (
  UPDATE public.board_items bi
  SET content_product_id = pws.stub_id
  FROM ps_with_stub pws
  WHERE bi.id = pws.board_item_id
    AND pws.board_item_id IS NOT NULL
  RETURNING bi.id
)
SELECT
  (SELECT count(*) FROM ins) AS inserted_products,
  (SELECT count(*) FROM ps_update) AS updated_submissions,
  (SELECT count(*) FROM bi_update) AS bridged_board_items;

-- Sanity DO block: assert backfill correctness before SET NOT NULL.
DO $sanity$
DECLARE
  v_products_created int;
  v_submissions_linked int;
  v_submissions_unlinked int;
  v_bridged_board_items int;
BEGIN
  SELECT count(*) INTO v_products_created
  FROM public.content_products
  WHERE publication_metadata->>'backfill_migration' = '20260805000045_p265_382_w4f_content_products_foundation';

  SELECT count(*) INTO v_submissions_linked
  FROM public.publication_submissions
  WHERE content_product_id IS NOT NULL;

  SELECT count(*) INTO v_submissions_unlinked
  FROM public.publication_submissions
  WHERE content_product_id IS NULL;

  SELECT count(*) INTO v_bridged_board_items
  FROM public.board_items bi
  WHERE bi.content_product_id IS NOT NULL;

  IF v_products_created <> 37 THEN
    RAISE EXCEPTION 'p265 backfill assertion failed: expected 37 stub products, found %', v_products_created;
  END IF;
  IF v_submissions_linked <> 37 THEN
    RAISE EXCEPTION 'p265 backfill assertion failed: expected 37 linked submissions, found %', v_submissions_linked;
  END IF;
  IF v_submissions_unlinked <> 0 THEN
    RAISE EXCEPTION 'p265 backfill assertion failed: % submissions still unlinked', v_submissions_unlinked;
  END IF;
  IF v_bridged_board_items <> 8 THEN
    RAISE EXCEPTION 'p265 backfill assertion failed: expected 8 bridged board_items (publication_submissions with board_item_id), found %', v_bridged_board_items;
  END IF;

  RAISE NOTICE 'p265 backfill OK: % stub products, % linked submissions, % bridged board_items',
    v_products_created, v_submissions_linked, v_bridged_board_items;
END;
$sanity$;

-- After backfill: enforce NOT NULL on publication_submissions.content_product_id.
-- Every submission MUST trace to a product per ADR-0099 §6 step 3.
ALTER TABLE public.publication_submissions
  ALTER COLUMN content_product_id SET NOT NULL;

-- ============================================================================
-- §6 STEP 6 — get_content_product_reader(uuid) RETURNS jsonb
-- Mirror p263 W4d get_governance_document_reader pattern:
--   gate 1: active membership (RAISE 42501 on miss)
--   gate 2: privacy-preserving null-envelope on product-not-found
--   gate 3: status visibility (admin/curator/proposer bypass; others see published/approved only)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_content_product_reader(p_product_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_caller_is_admin boolean := false;
  v_caller_is_curator boolean := false;
  v_is_proposer boolean := false;
  v_product public.content_products%ROWTYPE;
  v_source_summary jsonb;
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;

  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no active member record' USING ERRCODE = '42501';
  END IF;

  v_caller_is_admin := public.can_by_member(v_caller_member_id, 'manage_member');
  v_caller_is_curator := public.can_by_member(v_caller_member_id, 'curate_content');

  SELECT * INTO v_product
  FROM public.content_products
  WHERE id = p_product_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'product', NULL, 'source_summary', NULL);
  END IF;

  v_is_proposer := (v_product.proposer_member_id IS NOT NULL
                    AND v_product.proposer_member_id = v_caller_member_id);

  IF NOT (v_caller_is_admin OR v_caller_is_curator OR v_is_proposer) THEN
    IF v_product.status NOT IN (
      'published'::public.content_product_status,
      'approved'::public.content_product_status
    ) THEN
      RETURN jsonb_build_object('ok', true, 'product', NULL, 'source_summary', NULL);
    END IF;
  END IF;

  v_source_summary := CASE v_product.source_kind
    WHEN 'governance_document_version' THEN (
      SELECT jsonb_build_object(
        'kind', 'governance_document_version',
        'document_id', gd.id,
        'document_title', gd.title,
        'version_id', dv.id,
        'version_number', dv.version_number
      )
      FROM public.document_versions dv
      LEFT JOIN public.governance_documents gd ON gd.id = dv.document_id
      WHERE dv.id = v_product.source_document_version_id
    )
    WHEN 'board_item' THEN (
      SELECT jsonb_build_object(
        'kind', 'board_item',
        'board_item_id', bi.id,
        'board_item_title', bi.title
      )
      FROM public.board_items bi
      WHERE bi.id = v_product.source_board_item_id
    )
    WHEN 'publication_idea' THEN (
      SELECT jsonb_build_object(
        'kind', 'publication_idea',
        'publication_idea_id', pi.id,
        'publication_idea_title', pi.title
      )
      FROM public.publication_ideas pi
      WHERE pi.id = v_product.source_publication_idea_id
    )
    WHEN 'external' THEN jsonb_build_object(
      'kind', 'external',
      'external_uri', v_product.source_external_uri
    )
    WHEN 'none' THEN jsonb_build_object('kind', 'none')
    ELSE NULL
  END;

  RETURN jsonb_build_object(
    'ok', true,
    'product', jsonb_build_object(
      'id', v_product.id,
      'organization_id', v_product.organization_id,
      'title', v_product.title,
      'summary', v_product.summary,
      'source_kind', v_product.source_kind,
      'source_document_version_id', v_product.source_document_version_id,
      'source_board_item_id', v_product.source_board_item_id,
      'source_publication_idea_id', v_product.source_publication_idea_id,
      'source_external_uri', v_product.source_external_uri,
      'target_instrument', v_product.target_instrument,
      'target_audience', v_product.target_audience,
      'target_language_policy', v_product.target_language_policy,
      'target_length_policy', v_product.target_length_policy,
      'review_mode', v_product.review_mode,
      'review_round', v_product.review_round,
      'status', v_product.status,
      'derived_group_id', v_product.derived_group_id,
      'initiative_id', v_product.initiative_id,
      'proposer_member_id', v_product.proposer_member_id,
      'publication_metadata', v_product.publication_metadata,
      'created_at', v_product.created_at,
      'updated_at', v_product.updated_at,
      'published_at', v_product.published_at,
      'archived_at', v_product.archived_at
    ),
    'source_summary', v_source_summary
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_content_product_reader(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_content_product_reader(uuid) TO authenticated;

-- ============================================================================
-- §6 STEP 7 — list_content_products(jsonb) RETURNS jsonb
-- Mirror p256 M3 list_governance_library shape.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.list_content_products(p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_caller_is_admin boolean := false;
  v_caller_is_curator boolean := false;
  v_status_filter text[];
  v_instrument_filter text[];
  v_review_mode_filter text[];
  v_source_kind_filter text[];
  v_initiative_id uuid;
  v_limit int;
  v_offset int;
  v_result jsonb;
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;

  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no active member record' USING ERRCODE = '42501';
  END IF;

  v_caller_is_admin := public.can_by_member(v_caller_member_id, 'manage_member');
  v_caller_is_curator := public.can_by_member(v_caller_member_id, 'curate_content');

  v_status_filter := (
    SELECT array_agg(value::text)
    FROM jsonb_array_elements_text(COALESCE(p_filters->'status', '[]'::jsonb))
  );
  v_instrument_filter := (
    SELECT array_agg(value::text)
    FROM jsonb_array_elements_text(COALESCE(p_filters->'target_instrument', '[]'::jsonb))
  );
  v_review_mode_filter := (
    SELECT array_agg(value::text)
    FROM jsonb_array_elements_text(COALESCE(p_filters->'review_mode', '[]'::jsonb))
  );
  v_source_kind_filter := (
    SELECT array_agg(value::text)
    FROM jsonb_array_elements_text(COALESCE(p_filters->'source_kind', '[]'::jsonb))
  );
  v_initiative_id := NULLIF(p_filters->>'initiative_id', '')::uuid;
  v_limit := GREATEST(1, LEAST(200, COALESCE((p_filters->>'limit')::int, 50)));
  v_offset := GREATEST(0, COALESCE((p_filters->>'offset')::int, 0));

  WITH filtered AS (
    SELECT cp.*
    FROM public.content_products cp
    WHERE
      (v_caller_is_admin
       OR v_caller_is_curator
       OR (cp.proposer_member_id IS NOT NULL AND cp.proposer_member_id = v_caller_member_id)
       OR cp.status IN (
            'published'::public.content_product_status,
            'approved'::public.content_product_status
          ))
      AND (v_status_filter IS NULL OR array_length(v_status_filter, 1) IS NULL OR cp.status::text = ANY(v_status_filter))
      AND (v_instrument_filter IS NULL OR array_length(v_instrument_filter, 1) IS NULL OR cp.target_instrument::text = ANY(v_instrument_filter))
      AND (v_review_mode_filter IS NULL OR array_length(v_review_mode_filter, 1) IS NULL OR cp.review_mode::text = ANY(v_review_mode_filter))
      AND (v_source_kind_filter IS NULL OR array_length(v_source_kind_filter, 1) IS NULL OR cp.source_kind::text = ANY(v_source_kind_filter))
      AND (v_initiative_id IS NULL OR cp.initiative_id = v_initiative_id)
  ),
  paged AS (
    SELECT cp.*
    FROM filtered cp
    ORDER BY cp.created_at DESC, cp.id DESC
    LIMIT v_limit OFFSET v_offset
  )
  SELECT jsonb_build_object(
    'ok', true,
    'products', COALESCE(jsonb_agg(jsonb_build_object(
      'id', p.id,
      'title', p.title,
      'source_kind', p.source_kind,
      'target_instrument', p.target_instrument,
      'review_mode', p.review_mode,
      'status', p.status,
      'derived_group_id', p.derived_group_id,
      'initiative_id', p.initiative_id,
      'proposer_member_id', p.proposer_member_id,
      'created_at', p.created_at,
      'updated_at', p.updated_at,
      'published_at', p.published_at
    ) ORDER BY p.created_at DESC, p.id DESC), '[]'::jsonb),
    'total_count', (SELECT count(*)::int FROM filtered),
    'limit', v_limit,
    'offset', v_offset
  )
  INTO v_result
  FROM paged p;

  RETURN COALESCE(v_result, jsonb_build_object(
    'ok', true,
    'products', '[]'::jsonb,
    'total_count', 0,
    'limit', v_limit,
    'offset', v_offset
  ));
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.list_content_products(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_content_products(jsonb) TO authenticated;

-- ============================================================================
-- §6 STEP 9 — Invariant W in check_schema_invariants()
-- W_content_product_source_integrity: redundant with chk_content_products_source_integrity
-- CHECK constraint but mirrors V/V'/T pattern for ratchet visibility.
--
-- This CREATE OR REPLACE preserves ALL 21 existing invariants verbatim
-- (per SEDIMENT-238.C) and appends W as the 22nd block before END;.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_schema_invariants()
 RETURNS TABLE(invariant_name text, description text, severity text, violation_count integer, sample_ids uuid[])
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NULL
     AND current_setting('role', true) NOT IN ('service_role', 'postgres')
     AND current_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Unauthorized: check_schema_invariants requires authentication';
  END IF;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status = 'alumni' AND operational_role IS DISTINCT FROM 'alumni'
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'A1_alumni_role_consistency'::text,
         'member_status=alumni must coerce operational_role=alumni (B7 trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status = 'observer' AND operational_role NOT IN ('observer','guest','none')
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'A2_observer_role_consistency'::text,
         'member_status=observer must coerce operational_role IN (observer,guest,none) (B7 trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH computed AS (
    SELECT m.id AS member_id,
      CASE
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'manager')        THEN 'manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'co_gp')          THEN 'manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'deputy_manager') THEN 'deputy_manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role IN ('leader','comms_leader')) THEN 'tribe_leader'
        WHEN bool_or(
          (ae.kind = 'volunteer' AND ae.role IN ('researcher','facilitator','communicator','curator'))
          OR (ae.kind IN ('committee_member','workgroup_member','study_group_owner')
              AND ae.role IN ('leader','co_leader','owner','coordinator','researcher','contributor','member','participant'))
          OR (ae.kind IN ('committee_coordinator','workgroup_coordinator')
              AND ae.role IN ('leader','co_leader','owner','coordinator'))
        ) THEN 'researcher'
        WHEN bool_or(ae.kind = 'external_signer') THEN 'external_signer'
        WHEN bool_or(ae.kind = 'observer') THEN 'observer'
        WHEN bool_or(ae.kind = 'alumni') THEN 'alumni'
        WHEN bool_or(ae.kind = 'sponsor') THEN 'sponsor'
        WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
        WHEN bool_or(ae.kind = 'candidate') THEN 'candidate'
        ELSE 'guest'
      END AS expected_role
    FROM public.members m
    LEFT JOIN public.auth_engagements ae ON ae.person_id = m.person_id AND ae.is_authoritative = true
    WHERE m.member_status='active' AND m.name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND m.name NOT LIKE '%_synthetic%'
    GROUP BY m.id
  ),
  drift AS (
    SELECT c.member_id FROM computed c
    JOIN public.members m ON m.id = c.member_id
    WHERE m.operational_role IS DISTINCT FROM c.expected_role
  )
  SELECT 'A3_active_role_engagement_derivation'::text,
         'active member operational_role must equal priority-ladder derivation from active engagements (cache trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE ((member_status='active' AND is_active=false) OR (member_status IN ('observer','alumni','inactive') AND is_active=true))
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'B_is_active_status_mismatch'::text,
         'members.is_active must match member_status mapping (active=true, terminal=false)'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive') AND designations IS NOT NULL AND array_length(designations,1)>0
  )
  SELECT 'C_designations_in_terminal_status'::text,
         'members.designations must be empty when member_status is observer/alumni/inactive'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    JOIN public.persons p ON p.id = m.person_id
    WHERE m.auth_id IS NOT NULL AND p.auth_id IS NOT NULL AND m.auth_id IS DISTINCT FROM p.auth_id
  )
  SELECT 'D_auth_id_mismatch_person_member'::text,
         'persons.auth_id and members.auth_id must agree when both are set (ghost resolution sync)'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT ae.engagement_id AS e_id FROM public.auth_engagements ae
    JOIN public.members m ON m.person_id = ae.person_id
    WHERE ae.status='active' AND m.member_status IN ('observer','alumni','inactive')
      AND ae.kind NOT IN ('observer','alumni','external_signer','sponsor','chapter_board','partner_contact')
  )
  SELECT 'E_engagement_active_with_terminal_member'::text,
         'engagement.status=active is inconsistent with member.member_status in (observer/alumni/inactive) unless kind matches'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(e_id ORDER BY e_id) FROM (SELECT e_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT i.id AS initiative_id FROM public.initiatives i
    WHERE i.legacy_tribe_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.tribes t WHERE t.id = i.legacy_tribe_id)
  )
  SELECT 'F_initiative_legacy_tribe_orphan'::text,
         'initiatives.legacy_tribe_id must point to an existing tribe (bridge integrity)'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(initiative_id ORDER BY initiative_id) FROM (SELECT initiative_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    LEFT JOIN public.document_versions dv ON dv.id = gd.current_version_id
    WHERE gd.current_version_id IS NOT NULL
      AND (dv.id IS NULL OR dv.locked_at IS NULL)
      AND NOT EXISTS (
        SELECT 1 FROM public.approval_chains ac
        WHERE ac.document_id = gd.id
          AND ac.status IN ('review','approved','activated')
          AND ac.closed_at IS NULL
      )
  )
  SELECT 'J_current_version_published'::text,
         'governance_documents.current_version_id must point to a document_versions row with locked_at IS NOT NULL — unless an open approval_chain (review/approved/activated, closed_at NULL) is in flight that will lock the version on close (Phase IP-1, chain-aware).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    WHERE m.operational_role='external_signer'
      AND NOT EXISTS (
        SELECT 1 FROM public.auth_engagements ae
        WHERE ae.person_id=m.person_id AND ae.kind='external_signer' AND ae.status='active' AND ae.is_authoritative=true
      )
  )
  SELECT 'K_external_signer_integrity'::text,
         'members.operational_role=external_signer must have an active auth_engagements row with kind=external_signer (Phase IP-1).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    WHERE m.member_status IN ('alumni','observer','inactive') AND m.anonymized_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM public.member_offboarding_records r WHERE r.member_id=m.id)
  )
  SELECT 'L_offboarding_record_present'::text,
         'members in alumni/observer/inactive (not anonymized) must have a member_offboarding_records row (#91 G3 trigger).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH expected AS (
    SELECT a.id AS application_id, a.research_score AS cached,
      CASE
        WHEN e.obj_avg IS NOT NULL AND e.int_avg IS NOT NULL THEN round(e.obj_avg + e.int_avg, 2)
        WHEN e.obj_avg IS NOT NULL THEN round(e.obj_avg, 2)
        ELSE NULL
      END AS expected
    FROM public.selection_applications a
    CROSS JOIN LATERAL (
      SELECT AVG(weighted_subtotal) FILTER (WHERE evaluation_type='objective' AND submitted_at IS NOT NULL) AS obj_avg,
        AVG(weighted_subtotal) FILTER (WHERE evaluation_type='interview' AND submitted_at IS NOT NULL) AS int_avg
      FROM public.selection_evaluations WHERE application_id=a.id
    ) e
  ),
  drift AS (
    SELECT application_id FROM expected
    WHERE (cached IS NULL) IS DISTINCT FROM (expected IS NULL)
       OR (cached IS NOT NULL AND expected IS NOT NULL AND ABS(cached - expected) > 0.01)
  )
  SELECT 'M_application_score_consistency'::text,
         'selection_applications.research_score must equal compute_application_scores(application_id) derivation (sync trigger trg_recompute_application_scores).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(application_id ORDER BY application_id) FROM (SELECT application_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive')
      AND offboarded_at IS NULL AND anonymized_at IS NULL
      AND name <> 'VP Desenvolvimento Profissional (PMI-GO)'
  )
  SELECT 'N_terminal_status_offboarded_at_present'::text,
         'members in alumni/observer/inactive (not anonymized) must have offboarded_at NOT NULL (ARM-9 G6 defense-in-depth complement to L).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT ma.id AS artifact_id FROM public.meeting_artifacts ma
    WHERE ma.event_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.events e WHERE e.id = ma.event_id)
  )
  SELECT 'O_meeting_artifact_event_orphan'::text,
         'meeting_artifacts.event_id must point to an existing event when not NULL (FK defense).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(artifact_id ORDER BY artifact_id) FROM (SELECT artifact_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  SELECT 'P_tribe_initiative_bridge_complete'::text,
         'tribes.is_active=true must have at least one initiative.legacy_tribe_id pointing to it (V3-V4 bridge; cron leader digest depends).'::text,
         'medium'::text,
         (SELECT COUNT(*)::integer FROM public.tribes t
          WHERE t.is_active = true
            AND NOT EXISTS (SELECT 1 FROM public.initiatives i WHERE i.legacy_tribe_id = t.id)),
         NULL::uuid[];

  RETURN QUERY
  WITH drift AS (
    SELECT id AS engagement_id FROM public.engagements
    WHERE status = 'expired' AND end_date > CURRENT_DATE
  )
  SELECT 'Q_expired_engagement_end_date'::text,
         'engagements.status=expired requires end_date <= CURRENT_DATE (impossible to be expired in the future; VEP service_latest_end_date is source of truth).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(engagement_id ORDER BY engagement_id) FROM (SELECT engagement_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT a.id AS application_id
    FROM public.selection_applications a
    WHERE a.status = 'approved'
      AND a.email IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.members m WHERE lower(m.email) = lower(a.email)
      )
  )
  SELECT 'R_approved_application_has_member'::text,
         'selection_applications.status=approved must have a matching members row by lower(email). Bypass of approve_selection_application() canonical RPC creates this drift (Issue #180).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(application_id ORDER BY application_id) FROM (SELECT application_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT DISTINCT m.id AS member_id
    FROM public.selection_applications a
    JOIN public.members m ON lower(m.email) = lower(a.email)
    WHERE a.status = 'approved' AND m.person_id IS NULL
  )
  SELECT 'S_approved_member_has_person_id'::text,
         'members tied to an approved selection_applications row must have person_id NOT NULL (V4 graph anchor for engagements). Issue #180.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH primary_email_counts AS (
    SELECT m.id AS member_id,
           COUNT(me.id) FILTER (WHERE me.is_primary = true) AS primary_count
    FROM public.members m
    LEFT JOIN public.member_emails me ON me.member_id = m.id
    WHERE m.name NOT LIKE '%_synthetic%'
    GROUP BY m.id
  ),
  drift AS (
    SELECT member_id FROM primary_email_counts
    WHERE primary_count <> 1
  )
  SELECT 'T_member_has_exactly_one_primary_email'::text,
         'Every member must have exactly one primary email in member_emails (Issue #205).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    WHERE gd.status = 'pending_proposer_consent'
      AND EXISTS (
        SELECT 1 FROM public.approval_chains ac
        WHERE ac.document_id = gd.id
          AND ac.status NOT IN ('withdrawn','superseded')
      )
  )
  SELECT 'V_prime_pending_proposer_consent_no_open_chain'::text,
         'status=pending_proposer_consent must not have non-cancelled approval_chains rows (#315 P0-Q7 + Amendment A2 — pending_proposer_consent precedes any chain).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    WHERE gd.status IN ('approved','active')
      AND gd.current_ratified_chain_id IS NULL
  )
  SELECT 'V_status_chain_coherence'::text,
         'governance_documents with status approved/active must have current_ratified_chain_id NOT NULL (#315 P0-Q6 + #367 Wave 1b first leaf). NO carve-out: 7 legacy pre-chain docs backfilled with PM-designated synthetic chains via migration 20260805000038 (acknowledge signoffs, metadata.legacy_migration=true, role=migration_attestation).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT cp.id AS product_id
    FROM public.content_products cp
    WHERE
      CASE cp.source_kind
        WHEN 'governance_document_version' THEN
          NOT (cp.source_document_version_id IS NOT NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_publication_idea_id IS NULL
               AND cp.source_external_uri IS NULL)
        WHEN 'board_item' THEN
          NOT (cp.source_board_item_id IS NOT NULL
               AND cp.source_document_version_id IS NULL
               AND cp.source_publication_idea_id IS NULL
               AND cp.source_external_uri IS NULL)
        WHEN 'publication_idea' THEN
          NOT (cp.source_publication_idea_id IS NOT NULL
               AND cp.source_document_version_id IS NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_external_uri IS NULL)
        WHEN 'external' THEN
          NOT (cp.source_external_uri IS NOT NULL
               AND cp.source_document_version_id IS NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_publication_idea_id IS NULL)
        WHEN 'none' THEN
          NOT (cp.source_document_version_id IS NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_publication_idea_id IS NULL
               AND cp.source_external_uri IS NULL)
        ELSE TRUE
      END
  )
  SELECT 'W_content_product_source_integrity'::text,
         'content_products row must satisfy chk_content_products_source_integrity CHECK semantics (exactly one source FK populated per source_kind; ADR-0099 §2.2 + §6 step 9). Defense-in-depth complement to the CHECK constraint; mirrors V/V''/T pattern.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(product_id ORDER BY product_id) FROM (SELECT product_id FROM drift LIMIT 10) s)
  FROM drift;

END;
$function$;

-- ============================================================================
-- Reload PostgREST schema cache
-- ============================================================================
NOTIFY pgrst, 'reload schema';

COMMIT;
