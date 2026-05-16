-- p171 #8 — Update award_champion to validate criteria_met[] against catalog
--
-- Companion migration to 20260675500000_p171_8_champion_criteria_catalog.sql.
-- Adds validation loop after cardinality check: each slug in p_criteria_met
-- must exist in champion_criteria_catalog (per-org + per-surface + active=true).
-- Unknown slugs return jsonb_build_object('error','invalid_criteria','detail',...).
--
-- Migration body matches what was applied via MCP apply_migration 2026-05-16
-- (only signature unchanged; body adds 14 lines after existing cardinality check).
--
-- Rollback: restore previous award_champion body from 20260645000000.

CREATE OR REPLACE FUNCTION public.award_champion(p_recipient_id uuid, p_surface text, p_context_kind text, p_context_id uuid, p_criteria_met text[], p_justification text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller members%ROWTYPE;
  v_org_id uuid;
  v_target_init_id uuid;
  v_event events%ROWTYPE;
  v_deliv tribe_deliverables%ROWTYPE;
  v_artifact meeting_artifacts%ROWTYPE;
  v_attendance_present boolean;
  v_per_event_count int;
  v_per_grantor_count int;
  v_per_cycle_count int;
  v_per_event_cap int;
  v_per_cycle_cap int;
  v_rule gamification_rules%ROWTYPE;
  v_points int;
  v_champion_id uuid;
  v_org_authority boolean;
  v_soft_cap_warning boolean := false;
  v_recipient_org uuid;
  v_invalid_criteria text[];
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;
  v_org_id := v_caller.organization_id;

  IF p_surface NOT IN ('general','tribe','deliverable') THEN
    RETURN jsonb_build_object('error','invalid_surface');
  END IF;
  IF p_context_kind NOT IN ('event','deliverable','artifact') THEN
    RETURN jsonb_build_object('error','invalid_context_kind');
  END IF;
  IF p_recipient_id = v_caller.id THEN
    RETURN jsonb_build_object('error','self_award_not_allowed');
  END IF;
  IF p_criteria_met IS NULL OR cardinality(p_criteria_met) < 1 OR cardinality(p_criteria_met) > 4 THEN
    RETURN jsonb_build_object('error','invalid_criteria_count','detail','must have 1-4 criteria');
  END IF;
  IF length(trim(p_justification)) < 50 THEN
    RETURN jsonb_build_object('error','justification_too_short','detail','must be >= 50 chars');
  END IF;

  -- p171 #8: Validate each criterion slug ∈ champion_criteria_catalog
  SELECT array_agg(c) INTO v_invalid_criteria
  FROM unnest(p_criteria_met) AS c
  WHERE NOT EXISTS (
    SELECT 1 FROM public.champion_criteria_catalog cat
    WHERE cat.surface = p_surface
      AND cat.slug = c
      AND cat.active = true
      AND cat.organization_id = v_org_id
  );
  IF v_invalid_criteria IS NOT NULL AND cardinality(v_invalid_criteria) > 0 THEN
    RETURN jsonb_build_object(
      'error','invalid_criteria',
      'detail','unknown criterion slug(s) for surface ' || p_surface || ': ' || array_to_string(v_invalid_criteria, ', ')
    );
  END IF;

  IF p_surface = 'general' THEN
    IF p_context_kind != 'event' THEN
      RETURN jsonb_build_object('error','surface_context_kind_mismatch','detail','general requires event');
    END IF;
    SELECT * INTO v_event FROM events WHERE id = p_context_id;
    IF v_event.id IS NULL THEN
      RETURN jsonb_build_object('error','event_not_found');
    END IF;
    IF v_event.type NOT IN ('geral','lideranca') THEN
      RETURN jsonb_build_object('error','event_type_invalid_for_general','detail','expected type IN (geral, lideranca)');
    END IF;
    SELECT present INTO v_attendance_present FROM attendance
    WHERE event_id = p_context_id AND member_id = p_recipient_id;
    IF v_attendance_present IS NULL OR v_attendance_present = false THEN
      RETURN jsonb_build_object('error','recipient_not_present_at_event');
    END IF;
    v_target_init_id := NULL;

  ELSIF p_surface = 'tribe' THEN
    IF p_context_kind != 'event' THEN
      RETURN jsonb_build_object('error','surface_context_kind_mismatch','detail','tribe requires event');
    END IF;
    SELECT * INTO v_event FROM events WHERE id = p_context_id;
    IF v_event.id IS NULL THEN
      RETURN jsonb_build_object('error','event_not_found');
    END IF;
    IF v_event.type NOT IN ('tribo','1on1') THEN
      RETURN jsonb_build_object('error','event_type_invalid_for_tribe','detail','expected type IN (tribo, 1on1)');
    END IF;
    IF v_event.initiative_id IS NULL THEN
      RETURN jsonb_build_object('error','event_missing_initiative');
    END IF;
    SELECT present INTO v_attendance_present FROM attendance
    WHERE event_id = p_context_id AND member_id = p_recipient_id;
    IF v_attendance_present IS NULL OR v_attendance_present = false THEN
      RETURN jsonb_build_object('error','recipient_not_present_at_event');
    END IF;
    v_target_init_id := v_event.initiative_id;

  ELSIF p_surface = 'deliverable' THEN
    IF p_context_kind = 'deliverable' THEN
      SELECT * INTO v_deliv FROM tribe_deliverables WHERE id = p_context_id;
      IF v_deliv.id IS NULL THEN
        RETURN jsonb_build_object('error','deliverable_not_found');
      END IF;
      IF v_deliv.assigned_member_id IS NULL THEN
        RETURN jsonb_build_object('error','deliverable_no_assignee');
      END IF;
      IF v_deliv.assigned_member_id != p_recipient_id THEN
        RETURN jsonb_build_object('error','recipient_not_deliverable_assignee');
      END IF;
      v_target_init_id := v_deliv.initiative_id;
    ELSIF p_context_kind = 'artifact' THEN
      SELECT * INTO v_artifact FROM meeting_artifacts WHERE id = p_context_id;
      IF v_artifact.id IS NULL THEN
        RETURN jsonb_build_object('error','artifact_not_found');
      END IF;
      IF NOT v_artifact.is_published THEN
        RETURN jsonb_build_object('error','artifact_not_published');
      END IF;
      IF v_artifact.created_by IS NULL OR v_artifact.created_by != p_recipient_id THEN
        RETURN jsonb_build_object('error','recipient_not_artifact_creator');
      END IF;
      v_target_init_id := v_artifact.initiative_id;
    ELSE
      RETURN jsonb_build_object('error','surface_context_kind_mismatch','detail','deliverable surface requires context_kind IN (deliverable, artifact)');
    END IF;
  END IF;

  IF p_surface = 'general' THEN
    SELECT EXISTS (
      SELECT 1 FROM auth_engagements ae
      JOIN engagement_kind_permissions ekp
        ON ekp.kind = ae.kind AND ekp.role = ae.role AND ekp.action = 'award_champion'
      WHERE ae.legacy_member_id = v_caller.id
        AND ae.status = 'active'
        AND ekp.scope = 'organization'
    ) INTO v_org_authority;
    IF NOT v_org_authority THEN
      RETURN jsonb_build_object('error','not_authorized','detail','general surface requires org-scope grantor');
    END IF;
  ELSE
    IF NOT public.can_by_member(v_caller.id, 'award_champion'::text, 'initiative'::text, v_target_init_id) THEN
      RETURN jsonb_build_object('error','not_authorized','detail','no award_champion grant for this initiative');
    END IF;
  END IF;

  v_per_event_cap := CASE p_surface
    WHEN 'general' THEN 3
    WHEN 'tribe' THEN 2
    WHEN 'deliverable' THEN 1
  END;
  SELECT count(*) INTO v_per_event_count
  FROM champions_awarded
  WHERE context_id = p_context_id
    AND surface = p_surface
    AND status = 'active';
  IF v_per_event_count >= v_per_event_cap THEN
    RETURN jsonb_build_object('error','per_event_cap_reached','detail',
      format('max %s champion(s) per %s context', v_per_event_cap, p_surface));
  END IF;

  SELECT count(*) INTO v_per_grantor_count
  FROM champions_awarded
  WHERE context_id = p_context_id
    AND awarded_by = v_caller.id
    AND status = 'active';
  IF v_per_grantor_count >= 3 THEN
    RETURN jsonb_build_object('error','per_grantor_cap_reached','detail','grantor max 3 champions per context');
  END IF;

  v_per_cycle_cap := CASE p_surface
    WHEN 'general' THEN 5
    WHEN 'tribe' THEN 8
    WHEN 'deliverable' THEN 3
  END;
  SELECT count(*) INTO v_per_cycle_count
  FROM champions_awarded ca
  JOIN cycles c ON c.is_current = true
  WHERE ca.recipient_id = p_recipient_id
    AND ca.surface = p_surface
    AND ca.status = 'active'
    AND ca.created_at >= c.cycle_start::timestamptz
    AND (c.cycle_end IS NULL OR ca.created_at < (c.cycle_end + interval '1 day')::timestamptz);
  IF v_per_cycle_count >= v_per_cycle_cap THEN
    v_soft_cap_warning := true;
  END IF;

  SELECT * INTO v_rule
  FROM gamification_rules
  WHERE slug = 'champion_' || p_surface
    AND organization_id = v_org_id
    AND active = true
    AND effective_from <= now()
  ORDER BY effective_from DESC
  LIMIT 1;
  IF v_rule.slug IS NULL THEN
    RETURN jsonb_build_object('error','rule_not_found','detail','no active rule for champion_' || p_surface);
  END IF;
  v_points := v_rule.base_points + (v_rule.bonus_per_criterion * cardinality(p_criteria_met));
  IF v_rule.cap_points IS NOT NULL AND v_points > v_rule.cap_points THEN
    v_points := v_rule.cap_points;
  END IF;

  INSERT INTO champions_awarded (
    recipient_id, awarded_by, surface, context_kind, context_id,
    criteria_met, justification, points_awarded, organization_id, initiative_id
  ) VALUES (
    p_recipient_id, v_caller.id, p_surface, p_context_kind, p_context_id,
    p_criteria_met, p_justification, v_points, v_org_id, v_target_init_id
  ) RETURNING id INTO v_champion_id;

  SELECT organization_id INTO v_recipient_org FROM members WHERE id = p_recipient_id;

  INSERT INTO gamification_points (member_id, points, reason, category, ref_id, organization_id)
  VALUES (
    p_recipient_id,
    v_points,
    'Champion ' || p_surface || ': ' || substring(p_justification FROM 1 FOR 80),
    'champion_' || p_surface,
    v_champion_id,
    coalesce(v_recipient_org, v_org_id)
  );

  RETURN jsonb_build_object(
    'success', true,
    'champion_id', v_champion_id,
    'points_awarded', v_points,
    'soft_cap_warning', v_soft_cap_warning,
    'recipient_id', p_recipient_id,
    'surface', p_surface,
    'criteria_count', cardinality(p_criteria_met),
    'rule_slug', v_rule.slug
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
