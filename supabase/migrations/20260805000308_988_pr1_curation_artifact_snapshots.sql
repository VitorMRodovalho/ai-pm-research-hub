-- =====================================================================
-- #308-PR1 (#988) — curation_artifact_snapshots + review-log FK +
--                   criteria/version anchors
--
-- Parent: #308 (planning) · Spec: docs/specs/SPEC_308_CURATOR_EVIDENCE_BUNDLES.md
--   §3.1 · ADR-0119. Follows #308-PR0 (#987). BEHAVIOR-NEUTRAL foundation:
--   captures the version anchor of the artifact under review (Gap 1). No write
--   path is modified; nothing auto-fires. Value accrues on the next real curation
--   cycle (curation_review_log = 0 rows today).
--
-- GROUNDING (this turn, live, prod ldrfrvwhxsmgaabwmaik, 2026-06-30):
--   * curation_artifact_snapshots + register_curation_artifact_snapshot DO NOT
--     exist yet (to_regclass / to_regprocedure = NULL). Head migration = ...307.
--   * FK targets are all uuid PKs: organizations, initiatives, board_items,
--     board_item_files, document_versions, content_products, members.
--   * board_item_files columns: id, board_item_id, drive_file_id, drive_file_url,
--     filename, mime_type, size_bytes, uploaded_by, uploaded_via, created_at,
--     deleted_at (NO revision_id, NO hash — the Gap-1 weakness this PR anchors).
--   * board_items has board_id + organization_id + curation_status.
--   * project_boards has initiative_id (NULLABLE) + organization_id.
--   * submit_curation_review gates on can_by_member(id,'participate_in_governance_review')
--     and validates criteria_scores ONLY when non-empty (accepts '{}'); its INSERT
--     lists a fixed column set that does NOT include any of the new columns ⇒ adding
--     nullable columns + a criteria CHECK that also accepts '{}' is behavior-neutral.
--   * criteria_scores keys confirmed live in the writer:
--     ARRAY['clarity','originality','adherence','relevance','ethics'], scores 1-5.
--   * curate_content, manage_platform, participate_in_governance_review all exist in
--     engagement_kind_permissions.
--   * rls_can_see_initiative(uuid) exists; rls_can_see_initiative(NULL) = TRUE
--     (NULL initiative = org-level = visible).
--   * Supabase default privileges auto-grant arwdDxtm to anon AND authenticated on
--     new public tables (verified on work_governing_version.relacl) ⇒ a deny-all
--     table needs ENABLE RLS (no policy) + explicit REVOKE from anon, authenticated.
--
-- GROUNDING CORRECTION vs SPEC §3.1 (same class as PR-0's "board_items has no
--   initiative_id"): the SPEC declares `initiative_id uuid NOT NULL`, but the real
--   derivation board_item.board_id -> project_boards.initiative_id is NULLABLE —
--   2 of 25 boards live are org-level (initiative_id IS NULL). NOT NULL would make
--   the RPC's INSERT fail for any board_item on an org-level board. This column is
--   therefore NULLABLE, mirroring curation_review_log.initiative_id (#987): NULL =
--   org-level board = visible (rls_can_see_initiative(NULL)=TRUE).
--
-- SCOPE (behavior-neutral, matches #988 acceptance):
--   1. curation_artifact_snapshots (deny-all RLS + REVOKE; digest_status; 2 partial
--      UNIQUE indexes for real idempotency; denormalized nullable initiative_id for
--      the ADR-0105 gate JOIN-free).
--   2. register_curation_artifact_snapshot(...) SECDEF, curate_content OR
--      manage_platform, ON CONFLICT DO NOTHING, REVOKE PUBLIC/anon (keep
--      authenticated + service_role). No trigger (auto-capture w/ async Drive
--      revisionId via EF is a deferred go-live enhancement — SPEC §3.1).
--   3. curation_review_log additive nullable columns (0 rows = free backward compat):
--      artifact_snapshot_id (FK ON DELETE SET NULL) + reviewer_governing_politica/
--      termo_version_id (per-reviewer governing version, tie-break Termo 15.4.6;
--      NOT populated here — writer untouched, F-B2). criteria_scores CHECK for the
--      five keys, written to also accept '{}' so the untouched writer stays neutral.
--   4. _audit_curation_artifact_snapshot_security() service_role-only ratchet oracle
--      so CI can assert the deny-all posture + REVOKE without raw SQL (padrão #987).
--
-- GC-097: new table + new SECDEF RPC + one read-only audit fn + 3 additive nullable
--   columns on curation_review_log + 1 CHECK. No RPC signature change to an existing
--   function; submit_curation_review is NOT redefined (F-B2). apply_migration MCP →
--   reconcile schema_migrations version → NOTIFY pgrst.
--
-- LGPD (deferred, go-live blocker for #308-B): the 5y anonymization cron MUST be
--   extended to cover curation_artifact_snapshots.captured_by (SPEC §5 F-M-lgpd,
--   same class as export_my_data). captured_by is ON DELETE RESTRICT (hash-in-place
--   model: institutional review provenance is never hard-deleted). Blocks any go-live
--   of evidence-bundle issuance; tracked as a #308-B acceptance item.
--
-- Adversarial pre-apply review (4 lenses, wf_778e9d29-a76 — data-architect · security ·
--   senior-eng · code-reviewer): APPLY_AFTER_FIXES, 0 blockers. Fixes folded in BEFORE
--   apply:
--     * H1 (3 lenses): idempotent re-select was IF/ELSIF → returned {id:null} when both
--       file + docver anchors supplied and the conflict fired only on the docver index
--       (Case C3). Now two sequential IF blocks (file, then docver-if-still-null).
--     * H2 (security): existence oracle — a not-found board item raised BEFORE the
--       confidential gate, letting a non-engaged curator distinguish "confidential item
--       exists" from "doesn't exist" (ADR-0105 "omit silently" violation). Board-item
--       lookup + confidential gate + org-scope now collapse into ONE generic error.
--     * M (security): cross-org write guard — a curate_content curator is pinned to their
--       own org (manage_platform/GP is cross-org by design); docver + content_product must
--       be same-org as the board item (data-integrity invariant, not authz).
--     * M (dba): review_round is integer (matches curation_review_log/board_lifecycle_events
--       — smallint would force implicit join casts).
--     * M (dba/spec): criteria CHECK is exception-free (jsonb_typeof number guard before
--       cast; no ::int throw on a non-numeric string).
--     * M (neutrality): ADD CONSTRAINT wrapped in DO/EXCEPTION duplicate_object (re-apply
--       safe; matches migration 192 idiom).
--     * L (spec): REVOKE aligned to the SPEC §5 canonical (FROM PUBLIC, anon, authenticated;
--       GRANT authenticated, service_role).
-- =====================================================================

-- =====================================================================
-- 1. TABLE — curation_artifact_snapshots (Gap 1). Digest-only (ADR-0101):
--    the work never leaves the Núcleo; only a SHA-256 + a version anchor + a
--    denormalized metadata snapshot are captured. Not an extension of
--    board_item_files (an item has N files; "no artifact" is a valid state;
--    Drive revisions do not apply to the 22 existing file rows).
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.curation_artifact_snapshots (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  -- Denormalized from board_item.board_id -> project_boards.initiative_id at capture,
  -- so any SECDEF read applies the ADR-0105 confidential gate JOIN-free. NULLABLE:
  -- NULL = org-level board = visible (grounding correction vs SPEC §3.1 NOT NULL).
  initiative_id       uuid REFERENCES public.initiatives(id) ON DELETE SET NULL,
  board_item_id       uuid NOT NULL REFERENCES public.board_items(id) ON DELETE RESTRICT,
  board_item_file_id  uuid REFERENCES public.board_item_files(id)  ON DELETE RESTRICT,   -- nullable
  document_version_id uuid REFERENCES public.document_versions(id) ON DELETE RESTRICT,   -- nullable; the FK IS the version (immutable, ADR-0113)
  content_product_id  uuid REFERENCES public.content_products(id)  ON DELETE RESTRICT,   -- nullable; ADR-0099 work seam
  file_digest         text,                                    -- SHA-256 hex; meaning gated by digest_status
  digest_status       text NOT NULL DEFAULT 'pending'
                        CHECK (digest_status IN ('pending','verified','unresolvable')),  -- SPEC §11 F-B3/F-B5
  drive_revision_id   text,                                    -- INTERNAL — never surfaced by any RPC, never frozen in a snapshot (F-H6)
  version_label       text NOT NULL,
  metadata_snapshot   jsonb,                                   -- allowlisted filename/mime/size (survives rename/move)
  review_round        integer NOT NULL DEFAULT 1 CHECK (review_round >= 1),  -- int (matches curation_review_log/board_lifecycle_events)
  capture_trigger     text NOT NULL DEFAULT 'manual_gp'
                        CHECK (capture_trigger IN ('curation_pending','manual_gp','retroactive')),
  captured_by         uuid REFERENCES public.members(id) ON DELETE RESTRICT,
  snapshot_at         timestamptz NOT NULL DEFAULT now(),
  created_at          timestamptz NOT NULL DEFAULT now(),
  -- At least one version/work anchor (CUR_002; #988 AC "at least one of ...").
  CONSTRAINT cas_has_anchor CHECK (
    board_item_file_id IS NOT NULL
    OR document_version_id IS NOT NULL
    OR content_product_id IS NOT NULL
  )
);

COMMENT ON TABLE public.curation_artifact_snapshots IS
  '#308-PR1 (#988): immutable per-version capture of a curated artifact (Gap 1). '
  'Digest-only (ADR-0101). deny-all RLS (reads/writes only via SECURITY DEFINER RPCs). '
  'initiative_id denormalized (nullable; NULL=org-level=visible) for the ADR-0105 gate JOIN-free. '
  'drive_revision_id is INTERNAL: never surfaced by an RPC, never frozen in a content_snapshot. '
  'No trigger: capture is the manual register_curation_artifact_snapshot RPC (auto-capture deferred).';
COMMENT ON COLUMN public.curation_artifact_snapshots.initiative_id IS
  'Denormalized board_item.board_id -> project_boards.initiative_id at capture (ADR-0105 gate). '
  'NULLABLE by grounding: 2/25 boards are org-level (initiative_id NULL); NULL = visible.';
COMMENT ON COLUMN public.curation_artifact_snapshots.drive_revision_id IS
  'INTERNAL provenance only. MUST NOT be returned by any RPC nor copied into a content_snapshot (F-H6).';
COMMENT ON COLUMN public.curation_artifact_snapshots.digest_status IS
  'pending (awaiting compute) | verified (digest matches the curator-opened revision) | '
  'unresolvable (Drive inaccessible). A DACO must not embed an artifact whose status <> verified (F-B3/F-B5).';

-- Real idempotency (SPEC §11 F-M-unique): one snapshot per (item, file, round) and
-- per (item, docver, round). Content-product-only snapshots are intentionally NOT
-- deduped (no partial index) — they carry no per-version anchor.
CREATE UNIQUE INDEX IF NOT EXISTS cas_item_file_round
  ON public.curation_artifact_snapshots(board_item_id, board_item_file_id, review_round)
  WHERE board_item_file_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS cas_item_docver_round
  ON public.curation_artifact_snapshots(board_item_id, document_version_id, review_round)
  WHERE document_version_id IS NOT NULL;
-- Gate-support index (confidential-scope reads filter by initiative_id).
CREATE INDEX IF NOT EXISTS cas_initiative
  ON public.curation_artifact_snapshots(initiative_id) WHERE initiative_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS cas_board_item
  ON public.curation_artifact_snapshots(board_item_id);

-- =====================================================================
-- 2. RLS — deny-all. No permissive policy: reads/writes only via SECURITY
--    DEFINER RPCs that apply per-field filtering + the ADR-0105 gate. Belt-and-
--    suspenders REVOKE because Supabase default privileges auto-grant arwdDxtm to
--    anon + authenticated on new public tables (SPEC §5). service_role kept.
-- =====================================================================
ALTER TABLE public.curation_artifact_snapshots ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.curation_artifact_snapshots FROM anon, authenticated;

-- =====================================================================
-- 3. register_curation_artifact_snapshot — SECDEF, curate_content OR
--    manage_platform. Manual capture (no trigger). ON CONFLICT DO NOTHING =
--    idempotent per the two partial unique indexes; returns the existing id on
--    conflict (two sequential re-selects — H1). initiative_id + org derived
--    server-side (never from the caller — gate-bearing denorm).
--    ADR-0105 + existence-oracle (H2): the board-item lookup, the confidential
--    gate, and the cross-org guard collapse into ONE generic error, so a
--    non-engaged curate_content curator cannot distinguish "confidential item
--    exists" from "doesn't exist" or "another org's item". manage_platform (GP)
--    is cross-org + confidential-visible by construction. docver + content_product
--    must be same-org as the board item (data-integrity invariant). drive_revision_id
--    is stored but NEVER returned (F-H6).
-- =====================================================================
CREATE OR REPLACE FUNCTION public.register_curation_artifact_snapshot(
  p_board_item_id       uuid,
  p_board_item_file_id  uuid    DEFAULT NULL,
  p_document_version_id uuid    DEFAULT NULL,
  p_content_product_id  uuid    DEFAULT NULL,
  p_file_digest         text    DEFAULT NULL,
  p_digest_status       text    DEFAULT 'pending',
  p_version_label       text    DEFAULT NULL,
  p_review_round        integer DEFAULT 1,
  p_capture_trigger     text    DEFAULT 'manual_gp',
  p_drive_revision_id   text    DEFAULT NULL
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller     members%rowtype;
  v_file       board_item_files%rowtype;
  v_item_id    uuid;
  v_initiative uuid;
  v_org        uuid;
  v_is_gp      boolean;
  v_cp_org     uuid;
  v_dv_org     uuid;
  v_round      integer := COALESCE(p_review_round, 1);
  v_status     text    := COALESCE(p_digest_status, 'pending');
  v_trigger    text    := COALESCE(p_capture_trigger, 'manual_gp');
  v_label      text;
  v_meta       jsonb;
  v_id         uuid;
BEGIN
  -- Auth: curate_content OR manage_platform (GP).
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_is_gp := public.can_by_member(v_caller.id, 'manage_platform');
  IF NOT (v_is_gp OR public.can_by_member(v_caller.id, 'curate_content')) THEN
    RAISE EXCEPTION 'Access denied: curate_content or manage_platform required'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Param validation (defensive; the table CHECKs also enforce).
  IF v_status NOT IN ('pending','verified','unresolvable') THEN
    RAISE EXCEPTION 'invalid digest_status: %', v_status USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_trigger NOT IN ('curation_pending','manual_gp','retroactive') THEN
    RAISE EXCEPTION 'invalid capture_trigger: %', v_trigger USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_round < 1 THEN
    RAISE EXCEPTION 'review_round must be >= 1' USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF p_board_item_file_id IS NULL AND p_document_version_id IS NULL AND p_content_product_id IS NULL THEN
    RAISE EXCEPTION 'At least one of board_item_file_id, document_version_id, content_product_id is required'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Resolve board item + org + initiative anchor in one shot (initiative NULL = org-level board).
  SELECT bi.id, bi.organization_id, pb.initiative_id
    INTO v_item_id, v_org, v_initiative
    FROM public.board_items bi
    LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
   WHERE bi.id = p_board_item_id;

  -- Single generic gate (H2 no-existence-oracle + ADR-0105 + cross-org). All three
  -- failure modes — not found, confidential-and-not-visible, other-org (non-GP) —
  -- raise the SAME error so nothing is leaked about a board item the caller may not see.
  IF v_item_id IS NULL
     OR NOT public.rls_can_see_initiative(v_initiative)
     OR (NOT v_is_gp AND v_caller.organization_id IS DISTINCT FROM v_org) THEN
    RAISE EXCEPTION 'Board item not found or not accessible: %', p_board_item_id
      USING ERRCODE = 'no_data_found';
  END IF;

  -- Integrity: a supplied file must belong to this board item (caller already authorized for it).
  IF p_board_item_file_id IS NOT NULL THEN
    SELECT * INTO v_file FROM public.board_item_files
      WHERE id = p_board_item_file_id AND board_item_id = p_board_item_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'board_item_file % does not belong to board_item %',
        p_board_item_file_id, p_board_item_id USING ERRCODE = 'invalid_parameter_value';
    END IF;
  END IF;

  -- Integrity: docver + content_product must be same-org as the board item (or org-agnostic).
  -- Prevents a cross-org artifact link corrupting the evidentiary chain (data invariant, not authz).
  IF p_document_version_id IS NOT NULL THEN
    SELECT organization_id INTO v_dv_org FROM public.document_versions WHERE id = p_document_version_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'document_version not found: %', p_document_version_id USING ERRCODE = 'no_data_found';
    END IF;
    IF v_dv_org IS NOT NULL AND v_dv_org IS DISTINCT FROM v_org THEN
      RAISE EXCEPTION 'document_version % does not belong to the board item''s organization', p_document_version_id
        USING ERRCODE = 'invalid_parameter_value';
    END IF;
  END IF;
  IF p_content_product_id IS NOT NULL THEN
    SELECT organization_id INTO v_cp_org FROM public.content_products WHERE id = p_content_product_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'content_product not found: %', p_content_product_id USING ERRCODE = 'no_data_found';
    END IF;
    IF v_cp_org IS NOT NULL AND v_cp_org IS DISTINCT FROM v_org THEN
      RAISE EXCEPTION 'content_product % does not belong to the board item''s organization', p_content_product_id
        USING ERRCODE = 'invalid_parameter_value';
    END IF;
  END IF;

  -- version_label (NOT NULL): caller value, else the docver label, else the filename, else fallback.
  v_label := COALESCE(
    NULLIF(btrim(p_version_label), ''),
    (SELECT version_label FROM public.document_versions WHERE id = p_document_version_id),
    v_file.filename,
    'unversioned');

  -- metadata_snapshot: allowlisted file facts only (denormalized; survives rename/move).
  IF v_file.id IS NOT NULL THEN
    v_meta := jsonb_build_object(
      'filename',   v_file.filename,
      'mime_type',  v_file.mime_type,
      'size_bytes', v_file.size_bytes);
  END IF;

  INSERT INTO public.curation_artifact_snapshots (
    organization_id, initiative_id, board_item_id, board_item_file_id, document_version_id,
    content_product_id, file_digest, digest_status, drive_revision_id, version_label,
    metadata_snapshot, review_round, capture_trigger, captured_by
  ) VALUES (
    v_org, v_initiative, p_board_item_id, p_board_item_file_id, p_document_version_id,
    p_content_product_id, p_file_digest, v_status, p_drive_revision_id, v_label,
    v_meta, v_round, v_trigger, v_caller.id
  )
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    -- Conflict on a partial unique index: return the existing snapshot (idempotent).
    -- H1: two SEQUENTIAL re-selects (not IF/ELSIF) so a dual-anchor row whose conflict
    -- fired only on the docver index still resolves to the existing id.
    IF p_board_item_file_id IS NOT NULL THEN
      SELECT id INTO v_id FROM public.curation_artifact_snapshots
        WHERE board_item_id = p_board_item_id
          AND board_item_file_id = p_board_item_file_id
          AND review_round = v_round;
    END IF;
    IF v_id IS NULL AND p_document_version_id IS NOT NULL THEN
      SELECT id INTO v_id FROM public.curation_artifact_snapshots
        WHERE board_item_id = p_board_item_id
          AND document_version_id = p_document_version_id
          AND review_round = v_round;
    END IF;
    RETURN jsonb_build_object('id', v_id, 'created', false, 'idempotent', true);
  END IF;

  -- drive_revision_id is deliberately absent from the return envelope (F-H6).
  RETURN jsonb_build_object('id', v_id, 'created', true, 'idempotent', false);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.register_curation_artifact_snapshot(uuid,uuid,uuid,uuid,text,text,text,integer,text,text) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.register_curation_artifact_snapshot(uuid,uuid,uuid,uuid,text,text,text,integer,text,text) TO authenticated, service_role;

-- =====================================================================
-- 4. Ratchet oracle — service_role-only. Catalog reads only (no bodies, no PII).
--    Lets CI assert the deny-all posture + REVOKE without raw SQL (padrão #987
--    _audit_get_all_certificates_anon_execute).
-- =====================================================================
CREATE OR REPLACE FUNCTION public._audit_curation_artifact_snapshot_security()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
    'rpc_anon_execute', has_function_privilege('anon',
      'public.register_curation_artifact_snapshot(uuid,uuid,uuid,uuid,text,text,text,integer,text,text)'::regprocedure, 'EXECUTE'),
    'rpc_authenticated_execute', has_function_privilege('authenticated',
      'public.register_curation_artifact_snapshot(uuid,uuid,uuid,uuid,text,text,text,integer,text,text)'::regprocedure, 'EXECUTE'),
    'table_anon_select', has_table_privilege('anon', 'public.curation_artifact_snapshots', 'SELECT'),
    'table_anon_insert', has_table_privilege('anon', 'public.curation_artifact_snapshots', 'INSERT'),
    'table_authenticated_select', has_table_privilege('authenticated', 'public.curation_artifact_snapshots', 'SELECT'),
    'table_authenticated_insert', has_table_privilege('authenticated', 'public.curation_artifact_snapshots', 'INSERT'),
    'rls_enabled', (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.curation_artifact_snapshots'::regclass),
    'permissive_policy_count', (SELECT count(*)::int FROM pg_policies
       WHERE schemaname = 'public' AND tablename = 'curation_artifact_snapshots')
  );
$function$;
REVOKE EXECUTE ON FUNCTION public._audit_curation_artifact_snapshot_security() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._audit_curation_artifact_snapshot_security() TO service_role;

-- =====================================================================
-- 5. curation_review_log — additive nullable columns (0 rows = free compat) +
--    criteria CHECK. The writer submit_curation_review is NOT modified (F-B2);
--    the new columns are placeholders populated later (#308-B go-live).
-- =====================================================================
ALTER TABLE public.curation_review_log
  ADD COLUMN IF NOT EXISTS artifact_snapshot_id uuid
    REFERENCES public.curation_artifact_snapshots(id) ON DELETE SET NULL;

-- Per-reviewer governing version, frozen at review INSERT (tie-break Termo 15.4.6).
-- NO ON DELETE clause (NO ACTION) mirrors #977 governing_*_version_id: an immutable
-- legal anchor (ADR-0113) must not be silently dropped. NOT populated in PR-1.
ALTER TABLE public.curation_review_log
  ADD COLUMN IF NOT EXISTS reviewer_governing_politica_version_id uuid
    REFERENCES public.document_versions(id);
ALTER TABLE public.curation_review_log
  ADD COLUMN IF NOT EXISTS reviewer_governing_termo_version_id uuid
    REFERENCES public.document_versions(id);

COMMENT ON COLUMN public.curation_review_log.artifact_snapshot_id IS
  '#308-PR1 (#988): FK to the frozen artifact version this review examined (Gap 1/2). '
  'Nullable; populated by the write path in #308-B (not PR-1, F-B2). ON DELETE SET NULL.';
COMMENT ON COLUMN public.curation_review_log.reviewer_governing_politica_version_id IS
  '#308-PR1 (#988): per-reviewer governing Política version, frozen at review INSERT '
  '(tie-break Termo 15.4.6). Nullable placeholder; populated in #308-B (writer untouched here).';
COMMENT ON COLUMN public.curation_review_log.reviewer_governing_termo_version_id IS
  '#308-PR1 (#988): per-reviewer governing Termo version, frozen at review INSERT '
  '(tie-break Termo 15.4.6). Nullable placeholder; populated in #308-B (writer untouched here).';

CREATE INDEX IF NOT EXISTS crl_artifact_snapshot
  ON public.curation_review_log(artifact_snapshot_id) WHERE artifact_snapshot_id IS NOT NULL;

-- criteria_scores CHECK (SPEC §11 F-M-criteria): the five keys 1-5 OR the empty
-- object. Empty is allowed to mirror the live writer, which validates the five
-- keys ONLY when criteria_scores is non-empty and accepts '{}' — so this CHECK
-- never rejects a row the untouched writer produces (behavior-neutral). 0 rows
-- today ⇒ ADD CONSTRAINT cannot fail on existing data.
-- Exception-free: `? key` guards presence and `jsonb_typeof = 'number'` guards the
-- type BEFORE the numeric cast, so a non-numeric JSON value yields a clean CHECK
-- violation (not an `invalid input syntax` runtime error). DO/EXCEPTION makes the
-- ADD re-apply safe (matches migration 192 idiom).
DO $$ BEGIN
  ALTER TABLE public.curation_review_log
    ADD CONSTRAINT curation_review_log_criteria_scores_check CHECK (
      criteria_scores = '{}'::jsonb
      OR (
        (criteria_scores ? 'clarity')     AND jsonb_typeof(criteria_scores->'clarity')     = 'number' AND (criteria_scores->>'clarity')::numeric     BETWEEN 1 AND 5
        AND (criteria_scores ? 'originality') AND jsonb_typeof(criteria_scores->'originality') = 'number' AND (criteria_scores->>'originality')::numeric BETWEEN 1 AND 5
        AND (criteria_scores ? 'adherence')   AND jsonb_typeof(criteria_scores->'adherence')   = 'number' AND (criteria_scores->>'adherence')::numeric   BETWEEN 1 AND 5
        AND (criteria_scores ? 'relevance')   AND jsonb_typeof(criteria_scores->'relevance')   = 'number' AND (criteria_scores->>'relevance')::numeric   BETWEEN 1 AND 5
        AND (criteria_scores ? 'ethics')      AND jsonb_typeof(criteria_scores->'ethics')      = 'number' AND (criteria_scores->>'ethics')::numeric      BETWEEN 1 AND 5
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON CONSTRAINT curation_review_log_criteria_scores_check ON public.curation_review_log IS
  '#308-PR1 (#988): criteria envelope guard. Accepts ''{}'' (writer submits empty when a '
  'reviewer records no scores) OR all five keys clarity/originality/adherence/relevance/ethics in 1-5.';

-- =====================================================================
-- 6. PostgREST reload
-- =====================================================================
NOTIFY pgrst, 'reload schema';
