-- =====================================================================================
-- #906 — finalize_decisions: surface the approve-authority error UP FRONT instead of
-- the silent success:true / approved:0 no-op.
--
-- Defect (surfaced by the #902 sub-gap-2 grounding, PR #904): the OUTER gate admits a
-- committee lead OR manage_platform. When a committee-lead-WITHOUT-manage_platform submits
-- 'approved' decisions, the inner approve_selection_application re-resolves auth.uid() and
-- fails ITS OWN can_by_member(...,'manage_platform') gate; the per-decision BEGIN/EXCEPTION
-- sub-block swallows the rollback and the loop never increments v_approved_count. The RPC
-- then returns {approved:0} with a success-looking envelope — the lead believes a candidate
-- was approved when nothing happened (deceptive UX, NOT a privilege escalation: the inner
-- gate still holds).
--
-- Fix (ADR-0007 authority): compute manage_platform once at the outer gate. Committee leads
-- keep their reject / waitlist / convert authority WITHOUT manage_platform, but if the batch
-- contains any real 'approved' decision (i.e. not a conversion — a row with a non-empty
-- convert_to takes the conversion path and never calls approve_selection_application), and
-- the caller lacks manage_platform, return a clear authority error UP FRONT. Atomic: nothing
-- in the batch is applied, so there is no silent partial no-op.
--
-- Signature unchanged (uuid, jsonb) → CREATE OR REPLACE. SECURITY DEFINER preserved.
-- The only behavioural change is for committee-lead-without-manage_platform batches that
-- contain approvals; manage_platform callers and reject/waitlist/convert-only batches are
-- unaffected.
-- =====================================================================================

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
      -- Council fix: BEGIN/EXCEPTION sub-block — canonical failure rolls back
      -- this decision (status UPDATE + canonical side-effects) WITHOUT aborting
      -- the rest of the batch (preserves best-effort semantics).
      BEGIN
        UPDATE public.selection_applications SET
          status     = v_status,
          feedback   = coalesce(v_feedback, feedback),
          updated_at = now()
        WHERE id = v_app_id;

        IF NOT EXISTS (
          SELECT 1 FROM public.selection_membership_snapshots
          WHERE application_id = v_app_id AND is_partner_chapter = true
        ) THEN
          UPDATE public.selection_applications SET tags = array_append(tags, 'no_partner_chapter')
          WHERE id = v_app_id AND NOT ('no_partner_chapter' = ANY(tags));
        END IF;

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

NOTIFY pgrst, 'reload schema';
