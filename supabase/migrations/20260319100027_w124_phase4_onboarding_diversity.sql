-- W124 Phase 4: Onboarding + Diversity RPCs
-- ============================================================
-- RPCs: get_onboarding_status, update_onboarding_step,
--        get_onboarding_dashboard, get_diversity_dashboard
-- + SLA overdue detection + notifications
-- ============================================================

-- ============================================================
-- 1. GET_ONBOARDING_STATUS
--    Returns checklist with step status, SLA, completion %.
--    Available to: the member themselves, committee lead, GP.
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_onboarding_status(
  p_application_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller record;
  v_app record;
  v_cycle record;
  v_steps jsonb;
  v_total int;
  v_completed int;
  v_overdue int;
  v_progress_pct numeric;
BEGIN
  -- 1. Auth
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- 2. Get application
  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  -- 3. Authorization: member themselves, committee lead, or superadmin
  IF v_caller.is_superadmin IS NOT TRUE THEN
    -- Check if caller is the approved member
    DECLARE v_is_own boolean := false;
    BEGIN
      SELECT EXISTS(
        SELECT 1 FROM public.onboarding_progress
        WHERE application_id = p_application_id AND member_id = v_caller.id
      ) INTO v_is_own;

      IF NOT v_is_own THEN
        -- Check committee lead
        DECLARE v_is_lead boolean := false;
        BEGIN
          SELECT EXISTS(
            SELECT 1 FROM public.selection_committee
            WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead'
          ) INTO v_is_lead;

          -- Check sponsor/chapter_liaison
          IF NOT v_is_lead THEN
            IF NOT (v_caller.designations && ARRAY['sponsor', 'chapter_liaison']::text[]) THEN
              RAISE EXCEPTION 'Unauthorized: insufficient permissions';
            END IF;
          END IF;
        END;
      END IF;
    END;
  END IF;

  -- 4. Get cycle config for step labels
  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  -- 5. Build steps array with status
  SELECT jsonb_agg(
    jsonb_build_object(
      'step_key', op.step_key,
      'status', op.status,
      'completed_at', op.completed_at,
      'evidence_url', op.evidence_url,
      'sla_deadline', op.sla_deadline,
      'notes', op.notes,
      'is_overdue', CASE
        WHEN op.status NOT IN ('completed', 'skipped') AND op.sla_deadline < now()
        THEN true ELSE false
      END
    ) ORDER BY op.created_at
  ) INTO v_steps
  FROM public.onboarding_progress op
  WHERE op.application_id = p_application_id;

  -- 6. Compute counts
  SELECT COUNT(*) INTO v_total FROM public.onboarding_progress WHERE application_id = p_application_id;
  SELECT COUNT(*) INTO v_completed FROM public.onboarding_progress
    WHERE application_id = p_application_id AND status IN ('completed', 'skipped');
  SELECT COUNT(*) INTO v_overdue FROM public.onboarding_progress
    WHERE application_id = p_application_id AND status NOT IN ('completed', 'skipped')
    AND sla_deadline < now();

  v_progress_pct := CASE WHEN v_total > 0 THEN ROUND((v_completed::numeric / v_total) * 100, 1) ELSE 0 END;

  RETURN jsonb_build_object(
    'application_id', p_application_id,
    'applicant_name', v_app.applicant_name,
    'chapter', v_app.chapter,
    'role_applied', v_app.role_applied,
    'steps', COALESCE(v_steps, '[]'::jsonb),
    'total_steps', v_total,
    'completed_steps', v_completed,
    'overdue_steps', v_overdue,
    'progress_pct', v_progress_pct,
    'is_fully_complete', (v_completed = v_total AND v_total > 0)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_onboarding_status(uuid) TO authenticated;

-- ============================================================
-- 2. UPDATE_ONBOARDING_STEP
--    Marks step completed/skipped with optional evidence.
--    If all required steps done → notify Tribe Leader + Comms.
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_onboarding_step(
  p_application_id uuid,
  p_step_key text,
  p_status text DEFAULT 'completed',
  p_evidence_url text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller record;
  v_app record;
  v_step record;
  v_member_id uuid;
  v_total int;
  v_completed int;
  v_all_done boolean;
  v_tribe_leader record;
BEGIN
  -- 1. Auth
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- 2. Validate status
  IF p_status NOT IN ('completed', 'skipped', 'in_progress') THEN
    RAISE EXCEPTION 'Invalid status: must be completed, skipped, or in_progress';
  END IF;

  -- 3. Get application
  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  -- 4. Get step
  SELECT * INTO v_step FROM public.onboarding_progress
    WHERE application_id = p_application_id AND step_key = p_step_key;
  IF v_step IS NULL THEN
    RAISE EXCEPTION 'Onboarding step not found';
  END IF;

  v_member_id := v_step.member_id;

  -- 5. Authorization: own step, committee lead, or superadmin
  IF v_caller.is_superadmin IS NOT TRUE AND v_caller.id != v_member_id THEN
    DECLARE v_is_lead boolean := false;
    BEGIN
      SELECT EXISTS(
        SELECT 1 FROM public.selection_committee
        WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead'
      ) INTO v_is_lead;
      IF NOT v_is_lead THEN
        RAISE EXCEPTION 'Unauthorized: can only update own steps or be committee lead';
      END IF;
    END;
  END IF;

  -- 6. Update step
  UPDATE public.onboarding_progress
  SET status = p_status,
      completed_at = CASE WHEN p_status IN ('completed', 'skipped') THEN now() ELSE NULL END,
      evidence_url = COALESCE(p_evidence_url, evidence_url)
  WHERE application_id = p_application_id AND step_key = p_step_key;

  -- 7. Check if all steps are done
  SELECT COUNT(*) INTO v_total FROM public.onboarding_progress WHERE application_id = p_application_id;
  SELECT COUNT(*) INTO v_completed FROM public.onboarding_progress
    WHERE application_id = p_application_id AND status IN ('completed', 'skipped');

  v_all_done := (v_completed = v_total AND v_total > 0);

  -- 8. If all steps done → activate member + notify
  IF v_all_done AND v_member_id IS NOT NULL THEN
    UPDATE public.members
    SET is_active = true,
        current_cycle_active = true
    WHERE id = v_member_id;

    -- Update application status
    UPDATE public.selection_applications
    SET status = 'approved', updated_at = now()
    WHERE id = p_application_id;

    -- Notify tribe leader
    IF EXISTS(SELECT 1 FROM public.members WHERE id = v_member_id AND tribe_id IS NOT NULL) THEN
      SELECT m.* INTO v_tribe_leader
      FROM public.members m
      WHERE m.tribe_id = (SELECT tribe_id FROM public.members WHERE id = v_member_id)
        AND m.operational_role = 'tribe_leader'
      LIMIT 1;

      IF v_tribe_leader.id IS NOT NULL THEN
        PERFORM public.create_notification(
          v_tribe_leader.id,
          'selection_onboarding_complete',
          'Onboarding Concluído',
          v_app.applicant_name || ' completou o onboarding e está ativo na tribo.',
          '/workspace',
          'selection_application',
          p_application_id
        );
      END IF;
    END IF;

    -- Notify comms team
    PERFORM public.create_notification(
      v_caller.id,
      'selection_onboarding_complete',
      'Onboarding Concluído',
      v_app.applicant_name || ' completou todas as etapas de onboarding.',
      '/admin/selection',
      'selection_application',
      p_application_id
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'step_key', p_step_key,
    'new_status', p_status,
    'all_done', v_all_done,
    'completed_steps', v_completed,
    'total_steps', v_total
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_onboarding_step(uuid, text, text, text) TO authenticated;

-- ============================================================
-- 3. GET_ONBOARDING_DASHBOARD
--    Aggregate: steps completion, overdue, per-chapter breakdown.
--    Admin/GP only.
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_onboarding_dashboard(
  p_cycle_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller record;
  v_cycle_id uuid;
  v_total_candidates int;
  v_fully_complete int;
  v_in_progress int;
  v_overdue_count int;
  v_by_step jsonb;
  v_by_chapter jsonb;
  v_overdue_list jsonb;
BEGIN
  -- 1. Auth
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- 2. Admin/GP check
  IF v_caller.is_superadmin IS NOT TRUE
    AND v_caller.operational_role NOT IN ('manager', 'deputy_manager')
    AND NOT (v_caller.designations && ARRAY['sponsor', 'chapter_liaison']::text[]) THEN
    RAISE EXCEPTION 'Unauthorized: admin or sponsor required';
  END IF;

  -- 3. Resolve cycle
  IF p_cycle_id IS NOT NULL THEN
    v_cycle_id := p_cycle_id;
  ELSE
    SELECT id INTO v_cycle_id FROM public.selection_cycles
    ORDER BY created_at DESC LIMIT 1;
  END IF;

  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'no_cycle_found');
  END IF;

  -- 4. Count candidates with onboarding
  SELECT COUNT(DISTINCT op.application_id) INTO v_total_candidates
  FROM public.onboarding_progress op
  JOIN public.selection_applications sa ON sa.id = op.application_id
  WHERE sa.cycle_id = v_cycle_id;

  -- 5. Fully complete
  SELECT COUNT(*) INTO v_fully_complete
  FROM (
    SELECT op.application_id
    FROM public.onboarding_progress op
    JOIN public.selection_applications sa ON sa.id = op.application_id
    WHERE sa.cycle_id = v_cycle_id
    GROUP BY op.application_id
    HAVING COUNT(*) = COUNT(*) FILTER (WHERE op.status IN ('completed', 'skipped'))
  ) sub;

  v_in_progress := v_total_candidates - v_fully_complete;

  -- 6. Overdue count
  SELECT COUNT(DISTINCT op.application_id) INTO v_overdue_count
  FROM public.onboarding_progress op
  JOIN public.selection_applications sa ON sa.id = op.application_id
  WHERE sa.cycle_id = v_cycle_id
    AND op.status NOT IN ('completed', 'skipped')
    AND op.sla_deadline < now();

  -- 7. By step aggregation
  SELECT jsonb_agg(
    jsonb_build_object(
      'step_key', step_key,
      'total', total,
      'completed', completed,
      'overdue', overdue
    )
  ) INTO v_by_step
  FROM (
    SELECT
      op.step_key,
      COUNT(*) AS total,
      COUNT(*) FILTER (WHERE op.status IN ('completed', 'skipped')) AS completed,
      COUNT(*) FILTER (WHERE op.status NOT IN ('completed', 'skipped') AND op.sla_deadline < now()) AS overdue
    FROM public.onboarding_progress op
    JOIN public.selection_applications sa ON sa.id = op.application_id
    WHERE sa.cycle_id = v_cycle_id
    GROUP BY op.step_key
    ORDER BY op.step_key
  ) sub;

  -- 8. By chapter aggregation
  SELECT jsonb_agg(
    jsonb_build_object(
      'chapter', chapter,
      'total', total,
      'complete', complete,
      'overdue', overdue
    )
  ) INTO v_by_chapter
  FROM (
    SELECT
      sa.chapter,
      COUNT(DISTINCT op.application_id) AS total,
      COUNT(DISTINCT op.application_id) FILTER (
        WHERE NOT EXISTS(
          SELECT 1 FROM public.onboarding_progress op2
          WHERE op2.application_id = op.application_id
            AND op2.status NOT IN ('completed', 'skipped')
        )
      ) AS complete,
      COUNT(DISTINCT op.application_id) FILTER (
        WHERE op.status NOT IN ('completed', 'skipped') AND op.sla_deadline < now()
      ) AS overdue
    FROM public.onboarding_progress op
    JOIN public.selection_applications sa ON sa.id = op.application_id
    WHERE sa.cycle_id = v_cycle_id
    GROUP BY sa.chapter
    ORDER BY sa.chapter
  ) sub;

  -- 9. Overdue list (candidates with overdue steps)
  SELECT jsonb_agg(
    jsonb_build_object(
      'application_id', sub.application_id,
      'applicant_name', sub.applicant_name,
      'chapter', sub.chapter,
      'overdue_steps', sub.overdue_steps,
      'days_overdue', sub.days_overdue
    )
  ) INTO v_overdue_list
  FROM (
    SELECT
      sa.id AS application_id,
      sa.applicant_name,
      sa.chapter,
      COUNT(*) AS overdue_steps,
      MAX(EXTRACT(DAY FROM now() - op.sla_deadline))::int AS days_overdue
    FROM public.onboarding_progress op
    JOIN public.selection_applications sa ON sa.id = op.application_id
    WHERE sa.cycle_id = v_cycle_id
      AND op.status NOT IN ('completed', 'skipped')
      AND op.sla_deadline < now()
    GROUP BY sa.id, sa.applicant_name, sa.chapter
    ORDER BY days_overdue DESC
  ) sub;

  RETURN jsonb_build_object(
    'cycle_id', v_cycle_id,
    'total_candidates', v_total_candidates,
    'fully_complete', v_fully_complete,
    'in_progress', v_in_progress,
    'overdue_count', v_overdue_count,
    'by_step', COALESCE(v_by_step, '[]'::jsonb),
    'by_chapter', COALESCE(v_by_chapter, '[]'::jsonb),
    'overdue_list', COALESCE(v_overdue_list, '[]'::jsonb)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_onboarding_dashboard(uuid) TO authenticated;

-- ============================================================
-- 4. GET_DIVERSITY_DASHBOARD
--    Returns diversity metrics from selection_applications:
--    gender, chapter, sector, seniority, industry, region.
--    Comparison: applicants vs approved vs historical.
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_diversity_dashboard(
  p_cycle_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller record;
  v_cycle_id uuid;
  v_by_gender jsonb;
  v_by_chapter jsonb;
  v_by_sector jsonb;
  v_by_seniority jsonb;
  v_by_region jsonb;
  v_applicants_total int;
  v_approved_total int;
  v_snapshots jsonb;
BEGIN
  -- 1. Auth
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- 2. Admin/GP check
  IF v_caller.is_superadmin IS NOT TRUE
    AND v_caller.operational_role NOT IN ('manager', 'deputy_manager')
    AND NOT (v_caller.designations && ARRAY['sponsor', 'chapter_liaison']::text[]) THEN
    RAISE EXCEPTION 'Unauthorized: admin or sponsor required';
  END IF;

  -- 3. Resolve cycle
  IF p_cycle_id IS NOT NULL THEN
    v_cycle_id := p_cycle_id;
  ELSE
    SELECT id INTO v_cycle_id FROM public.selection_cycles
    ORDER BY created_at DESC LIMIT 1;
  END IF;

  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'no_cycle_found');
  END IF;

  -- 4. Totals
  SELECT COUNT(*) INTO v_applicants_total FROM public.selection_applications WHERE cycle_id = v_cycle_id;
  SELECT COUNT(*) INTO v_approved_total FROM public.selection_applications
    WHERE cycle_id = v_cycle_id AND status IN ('approved', 'converted');

  -- 5. By gender: applicants vs approved
  SELECT jsonb_agg(
    jsonb_build_object(
      'gender', COALESCE(gender, 'Não informado'),
      'applicants', applicants,
      'approved', approved
    )
  ) INTO v_by_gender
  FROM (
    SELECT
      sa.gender,
      COUNT(*) AS applicants,
      COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa
    WHERE sa.cycle_id = v_cycle_id
    GROUP BY sa.gender
    ORDER BY applicants DESC
  ) sub;

  -- 6. By chapter: applicants vs approved
  SELECT jsonb_agg(
    jsonb_build_object(
      'chapter', COALESCE(chapter, 'Não informado'),
      'applicants', applicants,
      'approved', approved
    )
  ) INTO v_by_chapter
  FROM (
    SELECT
      sa.chapter,
      COUNT(*) AS applicants,
      COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa
    WHERE sa.cycle_id = v_cycle_id
    GROUP BY sa.chapter
    ORDER BY applicants DESC
  ) sub;

  -- 7. By sector
  SELECT jsonb_agg(
    jsonb_build_object(
      'sector', COALESCE(sector, 'Não informado'),
      'applicants', applicants,
      'approved', approved
    )
  ) INTO v_by_sector
  FROM (
    SELECT
      sa.sector,
      COUNT(*) AS applicants,
      COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa
    WHERE sa.cycle_id = v_cycle_id
    GROUP BY sa.sector
    ORDER BY applicants DESC
  ) sub;

  -- 8. By seniority bands
  SELECT jsonb_agg(
    jsonb_build_object(
      'band', band,
      'applicants', applicants,
      'approved', approved
    )
  ) INTO v_by_seniority
  FROM (
    SELECT
      CASE
        WHEN sa.seniority_years IS NULL THEN 'Não informado'
        WHEN sa.seniority_years < 3 THEN '0-2 anos'
        WHEN sa.seniority_years < 6 THEN '3-5 anos'
        WHEN sa.seniority_years < 11 THEN '6-10 anos'
        WHEN sa.seniority_years < 16 THEN '11-15 anos'
        ELSE '16+ anos'
      END AS band,
      COUNT(*) AS applicants,
      COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa
    WHERE sa.cycle_id = v_cycle_id
    GROUP BY band
    ORDER BY band
  ) sub;

  -- 9. By region (state/country)
  SELECT jsonb_agg(
    jsonb_build_object(
      'region', COALESCE(region, 'Não informado'),
      'applicants', applicants,
      'approved', approved
    )
  ) INTO v_by_region
  FROM (
    SELECT
      COALESCE(sa.state, sa.country) AS region,
      COUNT(*) AS applicants,
      COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa
    WHERE sa.cycle_id = v_cycle_id
    GROUP BY region
    ORDER BY applicants DESC
  ) sub;

  -- 10. Historical snapshots
  SELECT jsonb_agg(
    jsonb_build_object(
      'snapshot_type', sds.snapshot_type,
      'metrics', sds.metrics,
      'created_at', sds.created_at
    )
  ) INTO v_snapshots
  FROM public.selection_diversity_snapshots sds
  WHERE sds.cycle_id = v_cycle_id
  ORDER BY sds.created_at DESC;

  RETURN jsonb_build_object(
    'cycle_id', v_cycle_id,
    'applicants_total', v_applicants_total,
    'approved_total', v_approved_total,
    'by_gender', COALESCE(v_by_gender, '[]'::jsonb),
    'by_chapter', COALESCE(v_by_chapter, '[]'::jsonb),
    'by_sector', COALESCE(v_by_sector, '[]'::jsonb),
    'by_seniority', COALESCE(v_by_seniority, '[]'::jsonb),
    'by_region', COALESCE(v_by_region, '[]'::jsonb),
    'snapshots', COALESCE(v_snapshots, '[]'::jsonb)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_diversity_dashboard(uuid) TO authenticated;

-- ============================================================
-- 5. DETECT_ONBOARDING_OVERDUE
--    SLA enforcement: detects overdue steps, sends notifications.
--    Called by cron or manually by admin.
-- ============================================================
CREATE OR REPLACE FUNCTION public.detect_onboarding_overdue()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller record;
  v_overdue record;
  v_notified int := 0;
  v_updated int := 0;
BEGIN
  -- 1. Auth (admin only)
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  IF v_caller.is_superadmin IS NOT TRUE
    AND v_caller.operational_role NOT IN ('manager', 'deputy_manager') THEN
    RAISE EXCEPTION 'Unauthorized: admin only';
  END IF;

  -- 2. Find overdue steps not yet marked as overdue
  FOR v_overdue IN
    SELECT
      op.id AS progress_id,
      op.application_id,
      op.step_key,
      op.member_id,
      op.sla_deadline,
      sa.applicant_name,
      sa.chapter
    FROM public.onboarding_progress op
    JOIN public.selection_applications sa ON sa.id = op.application_id
    WHERE op.status IN ('pending', 'in_progress')
      AND op.sla_deadline < now()
  LOOP
    -- Mark as overdue
    UPDATE public.onboarding_progress
    SET status = 'overdue'
    WHERE id = v_overdue.progress_id AND status != 'overdue';

    IF FOUND THEN
      v_updated := v_updated + 1;
    END IF;

    -- Notify the member
    IF v_overdue.member_id IS NOT NULL THEN
      PERFORM public.create_notification(
        v_overdue.member_id,
        'selection_onboarding_overdue',
        'Etapa de Onboarding Atrasada',
        'A etapa "' || v_overdue.step_key || '" está atrasada. Por favor, complete-a o mais breve possível.',
        '/workspace',
        'onboarding_progress',
        v_overdue.progress_id
      );
      v_notified := v_notified + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'steps_marked_overdue', v_updated,
    'notifications_sent', v_notified
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.detect_onboarding_overdue() TO authenticated;

-- ============================================================
-- 6. GET_SELECTION_PIPELINE_METRICS (for chapter report)
--    Returns pipeline funnel metrics per chapter.
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_selection_pipeline_metrics(
  p_cycle_id uuid DEFAULT NULL,
  p_chapter text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller record;
  v_cycle_id uuid;
  v_funnel jsonb;
  v_by_chapter jsonb;
  v_conversion_rate numeric;
BEGIN
  -- 1. Auth
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- 2. Permission: admin, sponsor, chapter_liaison
  IF v_caller.is_superadmin IS NOT TRUE
    AND v_caller.operational_role NOT IN ('manager', 'deputy_manager')
    AND NOT (v_caller.designations && ARRAY['sponsor', 'chapter_liaison']::text[]) THEN
    RAISE EXCEPTION 'Unauthorized: admin or sponsor required';
  END IF;

  -- 3. Resolve cycle
  IF p_cycle_id IS NOT NULL THEN
    v_cycle_id := p_cycle_id;
  ELSE
    SELECT id INTO v_cycle_id FROM public.selection_cycles
    ORDER BY created_at DESC LIMIT 1;
  END IF;

  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'no_cycle_found');
  END IF;

  -- 4. Funnel metrics (filtered by chapter if provided)
  SELECT jsonb_build_object(
    'total_applications', COUNT(*),
    'screening', COUNT(*) FILTER (WHERE status = 'screening'),
    'objective_eval', COUNT(*) FILTER (WHERE status = 'objective_eval'),
    'passed_cutoff', COUNT(*) FILTER (WHERE status NOT IN ('submitted', 'screening', 'objective_eval', 'objective_cutoff', 'rejected', 'withdrawn', 'cancelled')),
    'interview_pending', COUNT(*) FILTER (WHERE status = 'interview_pending'),
    'interview_scheduled', COUNT(*) FILTER (WHERE status = 'interview_scheduled'),
    'interview_done', COUNT(*) FILTER (WHERE status = 'interview_done'),
    'interview_noshow', COUNT(*) FILTER (WHERE status = 'interview_noshow'),
    'final_eval', COUNT(*) FILTER (WHERE status = 'final_eval'),
    'approved', COUNT(*) FILTER (WHERE status = 'approved'),
    'rejected', COUNT(*) FILTER (WHERE status = 'rejected'),
    'waitlist', COUNT(*) FILTER (WHERE status = 'waitlist'),
    'converted', COUNT(*) FILTER (WHERE status = 'converted'),
    'withdrawn', COUNT(*) FILTER (WHERE status = 'withdrawn')
  ) INTO v_funnel
  FROM public.selection_applications
  WHERE cycle_id = v_cycle_id
    AND (p_chapter IS NULL OR chapter = p_chapter);

  -- 5. By chapter breakdown
  SELECT jsonb_agg(
    jsonb_build_object(
      'chapter', chapter,
      'total', total,
      'approved', approved,
      'rejected', rejected,
      'waitlist', waitlist,
      'converted', converted,
      'avg_score', avg_score
    )
  ) INTO v_by_chapter
  FROM (
    SELECT
      sa.chapter,
      COUNT(*) AS total,
      COUNT(*) FILTER (WHERE sa.status = 'approved') AS approved,
      COUNT(*) FILTER (WHERE sa.status = 'rejected') AS rejected,
      COUNT(*) FILTER (WHERE sa.status = 'waitlist') AS waitlist,
      COUNT(*) FILTER (WHERE sa.status = 'converted') AS converted,
      ROUND(AVG(sa.final_score), 2) AS avg_score
    FROM public.selection_applications sa
    WHERE sa.cycle_id = v_cycle_id
      AND (p_chapter IS NULL OR sa.chapter = p_chapter)
    GROUP BY sa.chapter
    ORDER BY sa.chapter
  ) sub;

  -- 6. Conversion rate
  v_conversion_rate := CASE
    WHEN (v_funnel->>'total_applications')::int > 0
    THEN ROUND(((v_funnel->>'approved')::int + (v_funnel->>'converted')::int)::numeric /
         (v_funnel->>'total_applications')::int * 100, 1)
    ELSE 0
  END;

  RETURN jsonb_build_object(
    'cycle_id', v_cycle_id,
    'chapter_filter', p_chapter,
    'funnel', v_funnel,
    'by_chapter', COALESCE(v_by_chapter, '[]'::jsonb),
    'conversion_rate', v_conversion_rate
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_selection_pipeline_metrics(uuid, text) TO authenticated;
