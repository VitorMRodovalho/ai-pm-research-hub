-- #1290 / #1291 / #1286 — GP/co-GP visibility: camada de dado (read-only, GP-gated).
-- Superficies read que o GP/co-GP nao tinha em UX. Combina:
--   get_gp_cohort_health()               -> #1290 (pendentes de aprovacao do lider) + #1291 (coorte em risco)
--   get_cycle_attendance_overview(text)  -> #1286 (presencas/faltas por ciclo, cross-membro)
-- Gate: manage_member OR view_internal_analytics (GP + co-GP). Endurecido com coalesce(...,false)
-- para que o postgres-direto (execute_sql, jwt NULL) tambem seja barrado
-- (ver reference-large-migration-waf-chunk-and-impersonated-qa).

-- ═══════════════════════════════════════════════════════════════════════════
-- #1290 + #1291 — get_gp_cohort_health()
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.get_gp_cohort_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller uuid;
  v_is_service boolean;
  v_cycle record;
  v_kickoff uuid;
  v_result jsonb;
BEGIN
  v_is_service := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  ) = 'service_role';
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT coalesce(v_is_service, false)
     AND (v_caller IS NULL
          OR NOT (public.can_by_member(v_caller, 'manage_member')
                  OR public.can_by_member(v_caller, 'view_internal_analytics'))) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_member or view_internal_analytics');
  END IF;

  SELECT cycle_code, cycle_label, cycle_start INTO v_cycle
  FROM public.cycles WHERE is_current = true ORDER BY cycle_start DESC LIMIT 1;

  -- kickoff da coorte corrente: derivado (NAO hardcoded) — type='kickoff' OU titulo ILIKE '%kick%',
  -- primeiro evento nao-cancelado dentro da janela do ciclo. Em C4 o kickoff foi registrado como
  -- type='geral' com "Kick-off" no titulo, dai o OR por titulo.
  SELECT id INTO v_kickoff
  FROM public.events
  WHERE (type = 'kickoff' OR title ILIKE '%kick%')
    AND date >= v_cycle.cycle_start
    AND status IS DISTINCT FROM 'cancelled'
  ORDER BY date ASC LIMIT 1;

  WITH cohort AS (
    SELECT m.id, m.name, m.chapter,
      EXISTS (SELECT 1 FROM public.v_initiative_roster r
              JOIN public.initiatives i2 ON i2.id = r.initiative_id
              WHERE r.member_id = m.id AND i2.kind = 'research_tribe') AS has_tribe,
      EXISTS (SELECT 1 FROM public.attendance a
              WHERE a.member_id = m.id AND a.event_id = v_kickoff AND a.present = true) AS at_kickoff,
      EXISTS (SELECT 1 FROM public.gamification_points gp
              WHERE gp.member_id = m.id AND gp.created_at >= v_cycle.cycle_start) AS has_activity
    FROM public.members m
    WHERE m.member_status = 'active'
      AND m.operational_role IN ('researcher', 'tribe_leader')
  )
  SELECT jsonb_build_object(
    'cycle', jsonb_build_object('code', v_cycle.cycle_code, 'label', v_cycle.cycle_label),
    'kickoff_event_id', v_kickoff,
    'cohort_summary', jsonb_build_object(
      'total',         (SELECT count(*) FROM cohort),
      'with_tribe',    (SELECT count(*) FROM cohort WHERE has_tribe),
      'without_tribe', (SELECT count(*) FROM cohort WHERE NOT has_tribe),
      'at_kickoff',    (SELECT count(*) FROM cohort WHERE at_kickoff),
      'no_kickoff',    (SELECT count(*) FROM cohort WHERE NOT at_kickoff),
      'no_activity',   (SELECT count(*) FROM cohort WHERE NOT has_activity)
    ),
    'at_risk_members', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'member_id', c.id, 'name', c.name, 'chapter', c.chapter,
        'no_tribe', NOT c.has_tribe,
        'no_kickoff', NOT c.at_kickoff,
        'no_activity', NOT c.has_activity,
        'risk_count', (CASE WHEN NOT c.has_tribe THEN 1 ELSE 0 END
                     + CASE WHEN NOT c.at_kickoff THEN 1 ELSE 0 END
                     + CASE WHEN NOT c.has_activity THEN 1 ELSE 0 END)
      ) ORDER BY (CASE WHEN NOT c.has_tribe THEN 1 ELSE 0 END
                + CASE WHEN NOT c.at_kickoff THEN 1 ELSE 0 END
                + CASE WHEN NOT c.has_activity THEN 1 ELSE 0 END) DESC, c.name), '[]'::jsonb)
      FROM cohort c
      WHERE NOT c.has_tribe OR NOT c.at_kickoff OR NOT c.has_activity
    ),
    'pending_leader_approvals', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'invitation_id', ii.id,
        'requester_member_id', ii.invitee_member_id,
        'requester_name', rm.name,
        'tribe', init.title,
        'legacy_tribe_id', init.legacy_tribe_id,
        'requested_at', ii.created_at,
        'expires_at', ii.expires_at,
        'days_waiting', EXTRACT(day FROM now() - ii.created_at)::int
      ) ORDER BY ii.created_at), '[]'::jsonb)
      FROM public.initiative_invitations ii
      JOIN public.initiatives init ON init.id = ii.initiative_id
      JOIN public.members rm ON rm.id = ii.invitee_member_id
      WHERE ii.status = 'pending' AND init.kind = 'research_tribe'
        AND ii.invitee_member_id = ii.inviter_member_id
        AND ii.expires_at > now()
    ),
    'generated_at', now()
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_gp_cohort_health() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_gp_cohort_health() TO authenticated, service_role;
COMMENT ON FUNCTION public.get_gp_cohort_health() IS
  '#1290/#1291: GP/co-GP cohort health. Pendentes de aprovacao do lider (self-service tribe requests) + coorte em risco (sem tribo / sem presenca no kickoff / sem atividade voluntaria no ciclo). Gate manage_member OR view_internal_analytics.';

-- ═══════════════════════════════════════════════════════════════════════════
-- #1286 — get_cycle_attendance_overview(p_cycle_code)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.get_cycle_attendance_overview(p_cycle_code text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller uuid;
  v_is_service boolean;
  v_cycle record;
  v_result jsonb;
BEGIN
  v_is_service := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  ) = 'service_role';
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT coalesce(v_is_service, false)
     AND (v_caller IS NULL
          OR NOT (public.can_by_member(v_caller, 'manage_member')
                  OR public.can_by_member(v_caller, 'view_internal_analytics'))) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_member or view_internal_analytics');
  END IF;

  SELECT cycle_code, cycle_label, cycle_start,
         COALESCE(cycle_end, CURRENT_DATE) AS cycle_end_eff, is_current
  INTO v_cycle
  FROM public.cycles
  WHERE cycle_code = COALESCE(p_cycle_code,
    (SELECT cycle_code FROM public.cycles WHERE is_current = true ORDER BY cycle_start DESC LIMIT 1));

  IF v_cycle.cycle_code IS NULL THEN
    RETURN jsonb_build_object('error', 'Cycle not found: ' || COALESCE(p_cycle_code, '(current)'));
  END IF;

  -- coorte: ciclo corrente -> membros ativos; ciclo passado -> snapshot em member_cycle_history
  -- (#1104 governa o roll-forward). attendance espelha a janela/tipos do get_tribe_gamification:
  -- eventos nao-cancelados em ('geral','kickoff','tribo','lideranca'); denominador exclui excused.
  WITH cohort AS (
    SELECT m.id AS member_id, m.name, m.chapter, m.tribe_id
    FROM public.members m
    WHERE v_cycle.is_current AND m.member_status = 'active'
      AND m.operational_role IN ('researcher', 'tribe_leader')
    UNION
    SELECT mch.member_id, mch.member_name_snapshot, mch.chapter, mch.tribe_id
    FROM public.member_cycle_history mch
    WHERE NOT v_cycle.is_current AND mch.cycle_code = v_cycle.cycle_code AND mch.is_active
  ),
  att AS (
    SELECT a.member_id,
      count(*) FILTER (WHERE a.present = true) AS present_count,
      count(*) FILTER (WHERE a.present IS NOT TRUE AND a.excused IS NOT TRUE) AS absent_count,
      count(*) FILTER (WHERE a.excused = true) AS excused_count,
      count(*) FILTER (WHERE a.excused IS NOT TRUE) AS eligible_count
    FROM public.attendance a
    JOIN public.events e ON e.id = a.event_id
    WHERE e.date >= v_cycle.cycle_start AND e.date <= v_cycle.cycle_end_eff
      AND e.status IS DISTINCT FROM 'cancelled'
      AND e.type IN ('geral', 'kickoff', 'tribo', 'lideranca')
    GROUP BY a.member_id
  )
  SELECT jsonb_build_object(
    'cycle', jsonb_build_object('code', v_cycle.cycle_code, 'label', v_cycle.cycle_label,
       'start', v_cycle.cycle_start, 'end', v_cycle.cycle_end_eff, 'is_current', v_cycle.is_current),
    'total_members', (SELECT count(*) FROM cohort),
    'members', coalesce(jsonb_agg(jsonb_build_object(
       'member_id', c.member_id, 'name', c.name, 'chapter', c.chapter, 'tribe_id', c.tribe_id,
       'present', coalesce(att.present_count, 0),
       'absent', coalesce(att.absent_count, 0),
       'excused', coalesce(att.excused_count, 0),
       'eligible', coalesce(att.eligible_count, 0),
       'attendance_rate', CASE WHEN coalesce(att.eligible_count, 0) > 0
          THEN round(att.present_count::numeric / att.eligible_count, 2) ELSE NULL END
     ) ORDER BY coalesce(att.present_count, 0) ASC, c.name), '[]'::jsonb),
    'generated_at', now()
  ) INTO v_result
  FROM cohort c
  LEFT JOIN att ON att.member_id = c.member_id;

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_cycle_attendance_overview(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_cycle_attendance_overview(text) TO authenticated, service_role;
COMMENT ON FUNCTION public.get_cycle_attendance_overview(text) IS
  '#1286: GP/co-GP presencas/faltas cross-membro filtravel por ciclo. Ciclo corrente = membros ativos; ciclo passado = member_cycle_history. Gate manage_member OR view_internal_analytics.';
