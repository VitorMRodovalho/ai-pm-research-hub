-- #1175 D2 (PM ratified 2026-07-08): the 15 BR chapters in chapter_registry are ALL part of
-- the Núcleo journey since the CBGPL announcement; 10 have not signed the cooperation
-- agreement yet only because the agreement + IP Policy are under legal review. The binary
-- partner_chapters list of 5 therefore under-reports the journey and over-fires the
-- no_partner_chapter selection tag.
--
-- Model change (explicit status, NOT a silent inflation of the binary list):
--   1. partner_chapters.partnership_status: 'signed' (agreement executed) vs
--      'announced_at_risk' (announced partner, agreement pending — partnership at risk).
--      The 5 existing rows stay 'signed'; the 10 remaining registry chapters enter as
--      'announced_at_risk' (partnership_start NULL until signature).
--   2. parse_vep_chapters() becomes chapter_registry-driven via resolve_br_chapter_code()
--      (#1175 F2, migration 20260805000364) instead of a hardcoded ILIKE chain — IMMUTABLE
--      → STABLE (it now reads the registry). Unresolved names keep the legacy
--      'PMI-<stripped name>' fallback so non-BR chapters remain visible in snapshots.
--      (The old 'PMI-HN' Honduras special-case folds into that generic fallback.)
--   3. Selection-tag semantics centralized in apply_partner_chapter_tags():
--        - no_partner_chapter  = NO partner chapter at all (not even announced);
--        - partner_chapter_at_risk = has partner chapter(s), but none 'signed'.
--      admin_update_application + finalize_decisions now call the helper instead of
--      duplicating the inline block (the only two live functions carrying it).
--   4. Retroactive data corrections (audited in admin_audit_log):
--        - normalize the legacy 'PMI-Santa Catarina' snapshot code → 'PMI-SC'
--          (2 rows, csv_enrichment_20260401231023, pre-ILIKE parser era);
--        - recompute selection_membership_snapshots.is_partner_chapter under the
--          15-partner semantics;
--        - re-tag applications: drop no_partner_chapter where a partner now exists,
--          append partner_chapter_at_risk where that partner is not signed.
--
-- Grounded live 2026-07-08 (pre-apply): partner_chapters = 5 rows; snapshots = 434
-- (329 is_partner_chapter=true); 41 applications tagged no_partner_chapter, of which 1
-- gains a partner under the 15-chapter model (at-risk only); 5 snapshots flip to
-- is_partner_chapter=true before the SC normalization.

-- ── 1. partnership_status ────────────────────────────────────────────────────────────

ALTER TABLE public.partner_chapters
  ADD COLUMN IF NOT EXISTS partnership_status text NOT NULL DEFAULT 'signed'
  CHECK (partnership_status IN ('signed', 'announced_at_risk'));

COMMENT ON COLUMN public.partner_chapters.partnership_status IS
  '#1175 D2: signed = cooperation agreement executed; announced_at_risk = partner announced at CBGPL, agreement pending legal review (Termo/Política de PI). All 15 registry chapters are journey partners; only signed ones anchor the strongest selection guarantee.';

-- The 10 registry chapters not yet in partner_chapters enter as announced_at_risk.
-- chapter_name follows the VEP display name ("<State>, Brazil Chapter"; AM's real VEP
-- name is "Amazônia Chapter"). partnership_start stays NULL until signature.
INSERT INTO public.partner_chapters (chapter_code, chapter_name, is_active, partnership_start, partnership_status)
SELECT
  'PMI-' || cr.chapter_code,
  CASE WHEN cr.chapter_code = 'AM' THEN 'Amazônia Chapter'
       ELSE cr.state || ', Brazil Chapter' END,
  true,
  NULL,
  'announced_at_risk'
FROM public.chapter_registry cr
WHERE cr.country = 'BR' AND cr.is_active = true
  AND NOT EXISTS (
    SELECT 1 FROM public.partner_chapters pc
    WHERE pc.chapter_code = 'PMI-' || cr.chapter_code
  );

-- ── 2. parse_vep_chapters: registry-driven (was a hardcoded ILIKE chain) ─────────────

CREATE OR REPLACE FUNCTION public.parse_vep_chapters(p_membership text)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_chapters text[] := '{}';
  v_match text;
  v_code text;
BEGIN
  IF p_membership IS NULL OR p_membership = '' THEN RETURN v_chapters; END IF;

  -- Extract all "X, Brazil Chapter" or "X Chapter" patterns (unchanged extraction).
  FOR v_match IN
    SELECT m[1] FROM regexp_matches(p_membership, '([^,]+(?:,\s*Brazil)?\s+Chapter)', 'gi') AS m
  LOOP
    v_match := trim(v_match);
    -- #1175 D2: resolution now comes from chapter_registry (state names + vep_name_aliases,
    -- see resolve_br_chapter_code, #1175 F2) instead of a hardcoded state list.
    v_code := public.resolve_br_chapter_code(v_match);
    v_chapters := v_chapters || CASE
      WHEN v_code IS NOT NULL THEN 'PMI-' || v_code
      -- Legacy fallback keeps non-BR / unknown names visible in snapshots
      -- ("Central Italy Chapter" → 'PMI-Central Italy Chapter'); they never match
      -- partner_chapters codes, so they cannot affect partner semantics.
      ELSE 'PMI-' || regexp_replace(split_part(v_match, ',', 1), '[^A-Za-z ]', '', 'g')
    END;
  END LOOP;

  RETURN v_chapters;
END;
$function$;

-- ── 3. Centralized selection-tag semantics ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.apply_partner_chapter_tags(p_application_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- no_partner_chapter: not a single partner chapter in the membership snapshot —
  -- under D2 that means "outside the 15-chapter journey", not "outside the signed 5".
  IF NOT EXISTS (
    SELECT 1 FROM public.selection_membership_snapshots sms
    WHERE sms.application_id = p_application_id AND sms.is_partner_chapter = true
  ) THEN
    UPDATE public.selection_applications
    SET tags = array_append(tags, 'no_partner_chapter')
    WHERE id = p_application_id AND NOT ('no_partner_chapter' = ANY(tags));

  -- partner_chapter_at_risk: has a partner chapter, but none with a SIGNED agreement —
  -- the selection guarantee rests on an announced partnership still under legal review.
  ELSIF NOT EXISTS (
    SELECT 1
    FROM public.selection_membership_snapshots sms
    JOIN public.partner_chapters pc
      ON pc.is_active = true
     AND pc.partnership_status = 'signed'
     AND pc.chapter_code = ANY(sms.chapter_affiliations)
    WHERE sms.application_id = p_application_id
  ) THEN
    UPDATE public.selection_applications
    SET tags = array_append(tags, 'partner_chapter_at_risk')
    WHERE id = p_application_id AND NOT ('partner_chapter_at_risk' = ANY(tags));
  END IF;
END;
$function$;

COMMENT ON FUNCTION public.apply_partner_chapter_tags(uuid) IS
  '#1175 D2: single source of the partner-chapter selection tags (no_partner_chapter / partner_chapter_at_risk), called at approval time by admin_update_application and finalize_decisions.';

REVOKE EXECUTE ON FUNCTION public.apply_partner_chapter_tags(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.apply_partner_chapter_tags(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.apply_partner_chapter_tags(uuid) TO service_role;

-- ── 4. admin_update_application: inline partner block → helper call ──────────────────
-- Body otherwise byte-identical to the live function (captured 2026-07-08).

CREATE OR REPLACE FUNCTION public.admin_update_application(p_application_id uuid, p_data jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id        uuid;
  v_caller_name      text;
  v_app              record;
  v_old_status       text;
  v_new_status       text;
  v_canonical_result jsonb := NULL;
  v_member_id        uuid := NULL;
  v_seeded_count     int := 0;
  v_promoted         boolean := false;
  v_target_role      text;
BEGIN
  SELECT id, name INTO v_caller_id, v_caller_name FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN json_build_object('error', 'Unauthorized'); END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN json_build_object('error', 'Unauthorized');
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF NOT FOUND THEN RETURN json_build_object('error', 'Application not found'); END IF;

  v_old_status := v_app.status;
  v_new_status := coalesce(p_data->>'status', v_old_status);

  UPDATE public.selection_applications SET
    status            = v_new_status,
    feedback          = coalesce(p_data->>'feedback', feedback),
    tags              = CASE WHEN p_data ? 'tags'              THEN ARRAY(SELECT jsonb_array_elements_text(p_data->'tags')) ELSE tags END,
    role_applied      = coalesce(p_data->>'role_applied', role_applied),
    converted_from    = CASE WHEN p_data ? 'converted_from'    THEN p_data->>'converted_from'    ELSE converted_from END,
    converted_to      = CASE WHEN p_data ? 'converted_to'      THEN p_data->>'converted_to'      ELSE converted_to END,
    conversion_reason = CASE WHEN p_data ? 'conversion_reason' THEN p_data->>'conversion_reason' ELSE conversion_reason END,
    updated_at        = now()
  WHERE id = p_application_id;

  IF v_new_status = 'approved' AND v_old_status <> 'approved' THEN
    -- #1175 D2: partner-chapter tag semantics centralized (no_partner_chapter /
    -- partner_chapter_at_risk) — see apply_partner_chapter_tags.
    PERFORM public.apply_partner_chapter_tags(p_application_id);

    v_canonical_result := public.approve_selection_application(p_application_id, p_data);

    -- Council fix: RAISE so the entire transaction rolls back if canonical fails
    -- (otherwise the UPDATE status='approved' above commits without member/person/
    -- engagement, creating an invariant-R violation).
    IF (v_canonical_result->>'success') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Canonical approval failed: %', coalesce(v_canonical_result->>'error', 'unknown')
        USING ERRCODE = 'P0001',
              DETAIL = v_canonical_result::text;
    END IF;

    v_member_id      := (v_canonical_result->>'member_id')::uuid;
    v_seeded_count   := coalesce((v_canonical_result->>'onboarding_seeded')::int, 0);
    v_promoted       := coalesce((v_canonical_result->>'role_promoted')::boolean, false);
    v_target_role    := v_canonical_result->>'promoted_to';
  END IF;

  INSERT INTO public.data_anomaly_log (anomaly_type, severity, description, context)
  VALUES (
    'selection_status_change',
    'info',
    'Application ' || v_app.applicant_name || ': ' || v_old_status || ' → ' || v_new_status,
    jsonb_build_object(
      'application_id',    p_application_id,
      'old_status',        v_old_status,
      'new_status',        v_new_status,
      'actor',             v_caller_name,
      'member_id',         v_member_id,
      'onboarding_seeded', v_seeded_count,
      'role_promoted',     v_promoted,
      'promoted_to',       CASE WHEN v_promoted THEN v_target_role ELSE NULL END,
      'canonical_invoked', v_canonical_result IS NOT NULL
    )
  );

  RETURN json_build_object(
    'success',           true,
    'old_status',        v_old_status,
    'new_status',        v_new_status,
    'onboarding_seeded', v_seeded_count,
    'role_promoted',     v_promoted,
    'promoted_to',       CASE WHEN v_promoted THEN v_target_role ELSE NULL END,
    'canonical',         v_canonical_result
  );
END;
$function$;

-- ── 5. finalize_decisions: inline partner block → helper call ────────────────────────
-- Body otherwise byte-identical to the live function (captured 2026-07-08).

CREATE OR REPLACE FUNCTION public.finalize_decisions(p_cycle_id uuid, p_decisions jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller              record;
  v_committee           record;
  v_has_manage_platform boolean;
  v_decision            jsonb;
  v_app_id              uuid;
  v_app                 record;
  v_status              text;
  v_feedback            text;
  v_convert_to          text;
  v_approved_count      int := 0;
  v_rejected_count      int := 0;
  v_waitlisted_count    int := 0;
  v_converted_count     int := 0;
  v_created_members     int := 0;
  v_promoted_count      int := 0;
  v_canonical_result    jsonb;
  v_member_id           uuid;
  v_promoted_this_app   boolean;
  v_target_role         text;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RETURN json_build_object('error', 'Unauthorized');
  END IF;

  SELECT * INTO v_committee FROM public.selection_committee
  WHERE cycle_id = p_cycle_id AND member_id = v_caller.id AND role = 'lead';

  v_has_manage_platform := public.can_by_member(v_caller.id, 'manage_platform'::text);

  IF v_committee IS NULL AND NOT v_has_manage_platform THEN
    RETURN json_build_object('error', 'Unauthorized: must be committee lead or platform admin');
  END IF;

  -- #906: committee leads may reject / waitlist / convert without manage_platform, but
  -- APPROVING runs the canonical member-creation/promotion path, which requires
  -- manage_platform (ADR-0007). Surface that authority error up front instead of letting
  -- the inner gate roll each approval back silently and returning a success-looking
  -- {approved:0}. A decision with a non-empty convert_to takes the conversion path below
  -- and never calls approve_selection_application, so it is excluded here.
  IF NOT v_has_manage_platform AND EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_decisions) d
    WHERE d->>'decision' = 'approved'
      AND coalesce(d->>'convert_to', '') = ''
  ) THEN
    RETURN json_build_object(
      'error', 'Forbidden: approving an applicant requires platform admin (manage_platform). Committee leads may reject, waitlist, or convert roles.',
      'code', 'approve_requires_manage_platform'
    );
  END IF;

  FOR v_decision IN SELECT * FROM jsonb_array_elements(p_decisions)
  LOOP
    v_app_id            := (v_decision->>'application_id')::uuid;
    v_status            := v_decision->>'decision';
    v_feedback          := v_decision->>'feedback';
    v_convert_to        := v_decision->>'convert_to';
    v_promoted_this_app := false;
    v_target_role       := NULL;
    v_member_id         := NULL;
    v_canonical_result  := NULL;

    SELECT * INTO v_app FROM public.selection_applications WHERE id = v_app_id AND cycle_id = p_cycle_id;
    IF NOT FOUND THEN CONTINUE; END IF;

    IF v_convert_to IS NOT NULL AND v_convert_to != '' THEN
      UPDATE public.selection_applications SET
        status            = 'converted',
        converted_from    = v_app.role_applied,
        converted_to      = v_convert_to,
        conversion_reason = coalesce(v_feedback, 'Promoted by committee'),
        role_applied      = v_convert_to,
        feedback          = coalesce(v_feedback, feedback),
        updated_at        = now()
      WHERE id = v_app_id;
      v_converted_count := v_converted_count + 1;

      PERFORM public.create_notification(
        m.id, 'selection_conversion_offer',
        'Proposta de conversão de papel',
        'O comitê identificou seu perfil para o papel de ' || v_convert_to || '. Acesse a plataforma para mais detalhes.',
        '/admin/selection', 'selection_application', v_app_id
      ) FROM public.members m WHERE lower(m.email) = lower(v_app.email);

      CONTINUE;
    END IF;

    IF v_status = 'approved' THEN
      BEGIN
        UPDATE public.selection_applications SET
          status     = v_status,
          feedback   = coalesce(v_feedback, feedback),
          updated_at = now()
        WHERE id = v_app_id;

        -- #1175 D2: partner-chapter tag semantics centralized (no_partner_chapter /
        -- partner_chapter_at_risk) — see apply_partner_chapter_tags.
        PERFORM public.apply_partner_chapter_tags(v_app_id);

        v_canonical_result := public.approve_selection_application(v_app_id, '{}'::jsonb);

        IF (v_canonical_result->>'success') IS DISTINCT FROM 'true' THEN
          RAISE EXCEPTION 'Canonical approval failed for application %: %',
                          v_app_id,
                          coalesce(v_canonical_result->>'error', 'unknown')
            USING ERRCODE = 'P0001';
        END IF;

        v_approved_count := v_approved_count + 1;
        v_member_id         := (v_canonical_result->>'member_id')::uuid;
        v_promoted_this_app := coalesce((v_canonical_result->>'role_promoted')::boolean, false);
        v_target_role       := v_canonical_result->>'promoted_to';
        IF (v_canonical_result->>'member_created')::boolean THEN
          v_created_members := v_created_members + 1;
        END IF;
        IF v_promoted_this_app THEN
          v_promoted_count := v_promoted_count + 1;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        v_member_id        := NULL;
        v_canonical_result := jsonb_build_object('success', false, 'error', SQLERRM);
      END;

    ELSIF v_status = 'rejected' THEN
      UPDATE public.selection_applications SET
        status     = v_status,
        feedback   = coalesce(v_feedback, feedback),
        updated_at = now()
      WHERE id = v_app_id;
      v_rejected_count := v_rejected_count + 1;
    ELSIF v_status = 'waitlist' THEN
      UPDATE public.selection_applications SET
        status     = v_status,
        feedback   = coalesce(v_feedback, feedback),
        updated_at = now()
      WHERE id = v_app_id;
      v_waitlisted_count := v_waitlisted_count + 1;
    ELSE
      v_canonical_result := jsonb_build_object('success', false, 'error', 'unknown_decision', 'decision', v_status);
    END IF;

    INSERT INTO public.data_anomaly_log (anomaly_type, severity, description, context)
    VALUES (
      'selection_decision',
      'info',
      v_app.applicant_name || ' → ' || v_status,
      jsonb_build_object(
        'application_id',    v_app_id,
        'decision',          v_status,
        'actor',             v_caller.name,
        'member_id',         v_member_id,
        'role_promoted',     v_promoted_this_app,
        'promoted_to',       CASE WHEN v_promoted_this_app THEN v_target_role ELSE NULL END,
        'canonical_invoked', v_canonical_result IS NOT NULL,
        'canonical_success', (v_canonical_result->>'success')::boolean
      )
    );
  END LOOP;

  INSERT INTO public.selection_diversity_snapshots (cycle_id, snapshot_type, metrics)
  VALUES (p_cycle_id, 'approved', (
    SELECT jsonb_build_object(
      'by_chapter', (SELECT jsonb_object_agg(coalesce(chapter,'unknown'), cnt) FROM (SELECT chapter, count(*) as cnt FROM public.selection_applications WHERE cycle_id = p_cycle_id AND status = 'approved' GROUP BY chapter) x),
      'by_gender',  (SELECT jsonb_object_agg(coalesce(gender,'unknown'), cnt) FROM (SELECT gender,  count(*) as cnt FROM public.selection_applications WHERE cycle_id = p_cycle_id AND status = 'approved' GROUP BY gender) x),
      'by_role',    (SELECT jsonb_object_agg(role_applied, cnt) FROM (SELECT role_applied, count(*) as cnt FROM public.selection_applications WHERE cycle_id = p_cycle_id AND status = 'approved' GROUP BY role_applied) x),
      'total_approved',  v_approved_count,
      'total_rejected',  v_rejected_count,
      'total_converted', v_converted_count,
      'finalized_at',    now()
    )
  ));

  RETURN json_build_object(
    'approved',         v_approved_count,
    'rejected',         v_rejected_count,
    'waitlisted',       v_waitlisted_count,
    'converted',        v_converted_count,
    'members_created',  v_created_members,
    'members_promoted', v_promoted_count,
    'cycle_id',         p_cycle_id
  );
END;
$function$;

-- ── 6. Retroactive data corrections (audited) ────────────────────────────────────────

DO $$
DECLARE
  v_sc_fixed     int;
  v_flipped      int;
  v_untagged     int;
  v_at_risk      int;
BEGIN
  -- 6a. Legacy garbage code from the pre-ILIKE csv_enrichment parser era: the raw name
  -- "Santa Catarina, Brazil Chapter" was captured as 'PMI-Santa Catarina' (2 rows,
  -- grounded 2026-07-08). Normalize to the registry code so partner semantics see it.
  UPDATE public.selection_membership_snapshots
     SET chapter_affiliations = array_replace(chapter_affiliations, 'PMI-Santa Catarina', 'PMI-SC')
   WHERE 'PMI-Santa Catarina' = ANY(chapter_affiliations);
  GET DIAGNOSTICS v_sc_fixed = ROW_COUNT;

  -- 6b. Recompute is_partner_chapter under the 15-partner model.
  UPDATE public.selection_membership_snapshots s
     SET is_partner_chapter = (
       s.chapter_affiliations && (SELECT coalesce(array_agg(chapter_code), '{}') FROM public.partner_chapters WHERE is_active = true)
     )
   WHERE s.is_partner_chapter IS DISTINCT FROM (
       s.chapter_affiliations && (SELECT coalesce(array_agg(chapter_code), '{}') FROM public.partner_chapters WHERE is_active = true)
     );
  GET DIAGNOSTICS v_flipped = ROW_COUNT;

  -- 6c. Applications tagged no_partner_chapter that DO have a partner chapter under the
  -- 15-chapter journey lose the tag...
  UPDATE public.selection_applications a
     SET tags = array_remove(tags, 'no_partner_chapter')
   WHERE 'no_partner_chapter' = ANY(a.tags)
     AND EXISTS (
       SELECT 1 FROM public.selection_membership_snapshots s
       WHERE s.application_id = a.id AND s.is_partner_chapter = true
     );
  GET DIAGNOSTICS v_untagged = ROW_COUNT;

  -- ...and gain partner_chapter_at_risk when none of their partner chapters is signed.
  UPDATE public.selection_applications a
     SET tags = array_append(tags, 'partner_chapter_at_risk')
   WHERE NOT ('partner_chapter_at_risk' = ANY(a.tags))
     AND NOT ('no_partner_chapter' = ANY(a.tags))
     AND EXISTS (
       SELECT 1 FROM public.selection_membership_snapshots s
       WHERE s.application_id = a.id AND s.is_partner_chapter = true
     )
     AND NOT EXISTS (
       SELECT 1
       FROM public.selection_membership_snapshots s
       JOIN public.partner_chapters pc
         ON pc.is_active = true
        AND pc.partnership_status = 'signed'
        AND pc.chapter_code = ANY(s.chapter_affiliations)
       WHERE s.application_id = a.id
     )
     -- only applications that went through the tagging surface (approved at some point
     -- or currently tagged) — do not spray the tag over the whole funnel retroactively.
     AND a.status IN ('approved', 'converted');
  GET DIAGNOSTICS v_at_risk = ROW_COUNT;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    (SELECT id FROM public.members WHERE email = 'vitor.rodovalho@outlook.com'),
    'selection.partner_chapters_d2_semantics', 'partner_chapters', NULL,
    jsonb_build_object(
      'issue', '#1175 D2',
      'sc_codes_normalized', v_sc_fixed,
      'snapshots_recomputed', v_flipped,
      'apps_untagged_no_partner', v_untagged,
      'apps_tagged_at_risk', v_at_risk));
END $$;

NOTIFY pgrst, 'reload schema';
