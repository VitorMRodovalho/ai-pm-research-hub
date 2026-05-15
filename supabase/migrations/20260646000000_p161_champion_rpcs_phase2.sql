-- p161 Fase 2 — 4 Champion RPCs
-- Refs: docs/reference/SEMANTIC_TAXONOMY.md Q5 + Fase 1 (20260645000000)
-- PM ratification: 2026-05-15 (sessão p161, batch 4)

-- ════════════════════════════════════════════════════════════
-- 1. award_champion
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.award_champion(
  p_recipient_id uuid,
  p_surface text,
  p_context_kind text,
  p_context_id uuid,
  p_criteria_met text[],
  p_justification text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
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

REVOKE EXECUTE ON FUNCTION public.award_champion(uuid, text, text, uuid, text[], text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.award_champion(uuid, text, text, uuid, text[], text) FROM anon;
GRANT EXECUTE ON FUNCTION public.award_champion(uuid, text, text, uuid, text[], text) TO authenticated;

COMMENT ON FUNCTION public.award_champion(uuid, text, text, uuid, text[], text) IS
'Award a Champion to a member. V4 gated by award_champion action (org or initiative scope per surface). '
'Enforces per-event cap (3/2/1), per-grantor-per-event cap (3), per-cycle soft warning. '
'Auto-computes points via gamification_rules. Validates recipient eligibility (presence in event for general/tribe; assigned/creator for deliverable). '
'Ver docs/reference/SEMANTIC_TAXONOMY.md Q5.';

-- ════════════════════════════════════════════════════════════
-- 2. revoke_champion
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.revoke_champion(
  p_champion_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_caller members%ROWTYPE;
  v_champ champions_awarded%ROWTYPE;
  v_is_within_window boolean;
  v_is_platform_admin boolean;
  v_points_removed int;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;

  IF length(trim(coalesce(p_reason,''))) < 10 THEN
    RETURN jsonb_build_object('error','reason_required','detail','provide >=10 char reason');
  END IF;

  SELECT * INTO v_champ FROM champions_awarded WHERE id = p_champion_id;
  IF v_champ.id IS NULL THEN
    RETURN jsonb_build_object('error','champion_not_found');
  END IF;
  IF v_champ.status = 'revoked' THEN
    RETURN jsonb_build_object('error','already_revoked');
  END IF;

  v_is_platform_admin := public.can_by_member(v_caller.id, 'manage_platform'::text);
  v_is_within_window := v_champ.created_at >= now() - interval '7 days';

  IF NOT (v_is_platform_admin OR (v_champ.awarded_by = v_caller.id AND v_is_within_window)) THEN
    RETURN jsonb_build_object('error','not_authorized','detail',
      CASE
        WHEN v_champ.awarded_by = v_caller.id THEN '7-day window expired; only manage_platform can revoke'
        ELSE 'only original awarder (within 7 days) or platform admin can revoke'
      END);
  END IF;

  UPDATE champions_awarded SET
    status = 'revoked',
    revoked_at = now(),
    revoked_by = v_caller.id,
    revoked_reason = p_reason,
    updated_at = now()
  WHERE id = p_champion_id;

  WITH deleted AS (
    DELETE FROM gamification_points
    WHERE ref_id = p_champion_id
      AND category LIKE 'champion_%'
    RETURNING 1
  )
  SELECT count(*) INTO v_points_removed FROM deleted;

  RETURN jsonb_build_object(
    'success', true,
    'champion_id', p_champion_id,
    'points_removed', v_points_removed,
    'revoked_by', v_caller.id,
    'revoked_within_window', v_is_within_window,
    'by_platform_admin', v_is_platform_admin AND v_champ.awarded_by != v_caller.id
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.revoke_champion(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.revoke_champion(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.revoke_champion(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.revoke_champion(uuid, text) IS
'Revoke a Champion. Soft-revokes row (status=revoked + audit fields) AND deletes corresponding gamification_points (no compounding from revoked Champions). '
'Authority: original awarder within 7-day window OR manage_platform anytime. '
'Reason required (>=10 chars). Ver docs/reference/SEMANTIC_TAXONOMY.md Q5.7.';

-- ════════════════════════════════════════════════════════════
-- 3. get_champions_ranking
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.get_champions_ranking(
  p_scope_kind text DEFAULT 'global',
  p_scope_id uuid DEFAULT NULL,
  p_cycle_code text DEFAULT NULL,
  p_limit int DEFAULT 20
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_caller members%ROWTYPE;
  v_cycle_start timestamptz;
  v_cycle_end timestamptz;
  v_cycle_code text;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;

  IF p_scope_kind NOT IN ('global','initiative') THEN
    RETURN jsonb_build_object('error','invalid_scope_kind');
  END IF;
  IF p_scope_kind = 'initiative' AND p_scope_id IS NULL THEN
    RETURN jsonb_build_object('error','scope_id_required_for_initiative');
  END IF;

  IF p_cycle_code IS NULL THEN
    SELECT cycle_code, cycle_start::timestamptz, cycle_end::timestamptz
    INTO v_cycle_code, v_cycle_start, v_cycle_end
    FROM cycles WHERE is_current = true LIMIT 1;
  ELSE
    SELECT cycle_code, cycle_start::timestamptz, cycle_end::timestamptz
    INTO v_cycle_code, v_cycle_start, v_cycle_end
    FROM cycles WHERE cycle_code = p_cycle_code LIMIT 1;
    IF v_cycle_start IS NULL THEN
      RETURN jsonb_build_object('error','cycle_not_found');
    END IF;
  END IF;

  WITH ranking AS (
    SELECT
      ca.recipient_id AS member_id,
      m.name AS member_name,
      sum(ca.points_awarded)::int AS total_points,
      count(*) FILTER (WHERE ca.surface = 'general')::int AS champions_general,
      count(*) FILTER (WHERE ca.surface = 'tribe')::int AS champions_tribe,
      count(*) FILTER (WHERE ca.surface = 'deliverable')::int AS champions_deliverable,
      count(*)::int AS champions_total
    FROM champions_awarded ca
    JOIN members m ON m.id = ca.recipient_id
    WHERE ca.status = 'active'
      AND ca.organization_id = v_caller.organization_id
      AND ca.created_at >= v_cycle_start
      AND (v_cycle_end IS NULL OR ca.created_at < (v_cycle_end + interval '1 day'))
      AND (p_scope_kind = 'global'
        OR (p_scope_kind = 'initiative' AND ca.initiative_id = p_scope_id))
      AND coalesce(m.gamification_opt_out, false) = false
    GROUP BY ca.recipient_id, m.name
    ORDER BY total_points DESC, champions_total DESC, member_name ASC
    LIMIT greatest(1, least(p_limit, 100))
  )
  SELECT jsonb_build_object(
    'scope_kind', p_scope_kind,
    'scope_id', p_scope_id,
    'cycle_code', v_cycle_code,
    'cycle_start', v_cycle_start,
    'cycle_end', v_cycle_end,
    'ranking', coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
  ) INTO v_result
  FROM ranking r;

  RETURN v_result;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_champions_ranking(text, uuid, text, int) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_champions_ranking(text, uuid, text, int) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_champions_ranking(text, uuid, text, int) TO authenticated;

COMMENT ON FUNCTION public.get_champions_ranking(text, uuid, text, int) IS
'Ranking of Champion recipients within scope (global or initiative) + cycle. Respects LGPD opt-out (gamification_opt_out). NULL-safe cycle_end handling per ADR-0062 pattern. Limit clamp [1,100].';

-- ════════════════════════════════════════════════════════════
-- 4. get_member_champions_history
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.get_member_champions_history(
  p_member_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_caller members%ROWTYPE;
  v_target_id uuid;
  v_is_self boolean;
  v_can_view_pii boolean;
  v_target_opted_out boolean;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;

  v_target_id := coalesce(p_member_id, v_caller.id);
  v_is_self := (v_target_id = v_caller.id);

  IF NOT v_is_self THEN
    v_can_view_pii := public.can_by_member(v_caller.id, 'view_pii'::text);
    SELECT coalesce(gamification_opt_out, false) INTO v_target_opted_out
    FROM members WHERE id = v_target_id;
    IF NOT v_can_view_pii AND v_target_opted_out THEN
      RETURN jsonb_build_object('error','member_opted_out_from_public');
    END IF;
  END IF;

  WITH history AS (
    SELECT
      ca.id AS champion_id,
      ca.surface,
      ca.context_kind,
      ca.context_id,
      ca.criteria_met,
      ca.justification,
      ca.points_awarded,
      ca.status,
      ca.revoked_at,
      ca.revoked_reason,
      ca.created_at AS awarded_at,
      jsonb_build_object('id', awarder.id, 'name', awarder.name) AS awarded_by,
      CASE WHEN ca.initiative_id IS NOT NULL THEN
        jsonb_build_object('id', ca.initiative_id,
          'name', (SELECT name FROM initiatives WHERE id = ca.initiative_id))
      ELSE NULL END AS initiative
    FROM champions_awarded ca
    LEFT JOIN members awarder ON awarder.id = ca.awarded_by
    WHERE ca.recipient_id = v_target_id
      AND ca.organization_id = v_caller.organization_id
    ORDER BY ca.created_at DESC
  ),
  totals AS (
    SELECT
      count(*) FILTER (WHERE status='active')::int AS active_count,
      count(*) FILTER (WHERE status='revoked')::int AS revoked_count,
      coalesce(sum(points_awarded) FILTER (WHERE status='active'), 0)::int AS active_points,
      count(*) FILTER (WHERE status='active' AND surface='general')::int AS general_count,
      count(*) FILTER (WHERE status='active' AND surface='tribe')::int AS tribe_count,
      count(*) FILTER (WHERE status='active' AND surface='deliverable')::int AS deliverable_count
    FROM history
  )
  SELECT jsonb_build_object(
    'member_id', v_target_id,
    'is_self', v_is_self,
    'totals', (SELECT to_jsonb(totals.*) FROM totals),
    'history', coalesce((SELECT jsonb_agg(to_jsonb(history.*)) FROM history), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_member_champions_history(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_member_champions_history(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_member_champions_history(uuid) TO authenticated;

COMMENT ON FUNCTION public.get_member_champions_history(uuid) IS
'Chronological history of Champions received by a member. Self-view always allowed; cross-member view requires view_pii OR target not opted out. Returns history[] + totals (counts by surface + active points). Audit-load-bearing.';

NOTIFY pgrst, 'reload schema';

-- ════════════════════════════════════════════════════════════
-- Rollback
-- ════════════════════════════════════════════════════════════
-- DROP FUNCTION IF EXISTS public.get_member_champions_history(uuid);
-- DROP FUNCTION IF EXISTS public.get_champions_ranking(text, uuid, text, int);
-- DROP FUNCTION IF EXISTS public.revoke_champion(uuid, text);
-- DROP FUNCTION IF EXISTS public.award_champion(uuid, text, text, uuid, text[], text);
