-- =====================================================================================
-- #1326 fix(attendance): get_my_meetings escopa por AUDIÊNCIA real, não pelo proxy initiative_id IS NULL
--
-- Sintoma (reportado pela membra Ligia Ribeiro, print): a widget "Minhas reuniões" mostrava
--   entrevistas de candidatos e reuniões de liderança; ao clicar "Marcar presença" ela recebia
--   "Você não está na audiência prevista para este evento".
--
-- Causa-raiz (aterrada 2026-07-11): o escopo usava `e.initiative_id IS NULL` como proxy de "evento
--   geral". Mas entrevista/lideranca/1on1 também têm initiative_id NULL, então TODOS vazavam para a
--   lista de TODO membro. Duas consequências:
--     - lideranca (rule role=leader): register_own_presence corretamente barra com not_in_audience —
--       mas o evento nem deveria estar visível.
--     - entrevista sem audience rule: o gate de audiência de register_own_presence é PULADO
--       (v_has_rules=false) → a membra poderia marcar presença errada na entrevista de um candidato
--       (ruído + integridade + privacidade dos candidatos).
--
-- Fix: escopar pela audiência real do membro, ESPELHANDO event_audience_rules como register_own_presence
--   (role/tribe/all_active_operational/specific_members). Alinha "o que vejo" com "onde posso marcar".
--   Mantém o branch explícito de tribo (sem regressão para membros de tribo) e o histórico próprio
--   (nunca esconder uma reunião em que o membro já tem registro de presença). #785 confidential gate mantido.
--
-- Aterrado (sessão 2026-07-11): para a Ligia (researcher, tribe 14, active) entrevista 24→0,
--   lideranca 7→0, geral 3→4, tribo 0→1. Para um tribe_leader as 7 reuniões de liderança seguem
--   visíveis (7→7). Eventos sem audience rule deixam de broadcastar para toda a base.
--
-- GRANTS: authenticated only (member-facing); REVOKE public/anon.
-- =====================================================================================
CREATE OR REPLACE FUNCTION public.get_my_meetings(
  p_days_back integer DEFAULT 30,
  p_days_forward integer DEFAULT 60
)
RETURNS TABLE(
  event_id uuid,
  event_title text,
  event_date date,
  event_type text,
  duration_minutes integer,
  initiative_id uuid,
  initiative_title text,
  attendance_present boolean,
  excused boolean
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_member_id uuid;
  v_tribe_id integer;
  v_member_role text;
  v_member_designations text[];
  v_member_active boolean;
BEGIN
  SELECT m.id, m.tribe_id, m.operational_role, m.designations, m.current_cycle_active
    INTO v_member_id, v_tribe_id, v_member_role, v_member_designations, v_member_active
  FROM public.members m
  WHERE m.auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  RETURN QUERY
  SELECT
    e.id,
    e.title,
    e.date,
    e.type,
    e.duration_minutes,
    e.initiative_id,
    i.title,
    a.present,
    a.excused
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  LEFT JOIN public.attendance a ON a.event_id = e.id AND a.member_id = v_member_id
  WHERE e.status <> 'cancelled'
    AND e.date BETWEEN (CURRENT_DATE - p_days_back) AND (CURRENT_DATE + p_days_forward)
    AND (
      -- tribe events for the caller's tribe (kept explicit: no regression, and covers tribe events
      -- whose audience rule may be absent/atypical).
      (e.initiative_id IS NOT NULL AND i.legacy_tribe_id = v_tribe_id)
      -- OR the caller is in the event's mandatory audience — mirrors register_own_presence exactly.
      OR EXISTS (
        SELECT 1 FROM public.event_audience_rules ar
        WHERE ar.event_id = e.id
          AND ar.attendance_type = 'mandatory'
          AND (
            (ar.target_type = 'role' AND (
              v_member_role = ar.target_value
              OR ar.target_value = ANY(COALESCE(v_member_designations, '{}'))
            ))
            OR (ar.target_type = 'tribe' AND v_tribe_id IS NOT NULL AND v_tribe_id::text = ar.target_value)
            OR (ar.target_type = 'all_active_operational'
                AND COALESCE(v_member_active, false) = true
                AND v_member_role <> 'guest')
            OR (ar.target_type = 'specific_members' AND EXISTS (
              SELECT 1 FROM public.event_invited_members im
              WHERE im.event_id = e.id AND im.member_id = v_member_id
            ))
          )
      )
      -- OR the caller already has an attendance record for this event (their own history —
      -- never hide a meeting they actually attended, e.g. bulk-marked at an ad-hoc event).
      OR a.member_id IS NOT NULL
    )
    AND public.rls_can_see_initiative(e.initiative_id)  -- #785 confidential gate
  ORDER BY e.date DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_my_meetings(integer, integer) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_my_meetings(integer, integer) TO authenticated;
