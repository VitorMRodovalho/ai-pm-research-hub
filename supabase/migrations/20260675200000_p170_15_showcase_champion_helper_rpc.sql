-- p170 #15 — Showcase → Champion eligibility helper RPC (ADR-0084)
--
-- PM ratified Option C 2026-05-16: Showcase é INPUT (nudge/eligibility),
-- não constraint. UI grant Champion mostra showcases recentes do member
-- target como suggestion. Sem DB constraint, sem trigger automático.
--
-- Helper RPC: get_recent_showcases_by_member(member_id, days) →
-- returns showcases registrados nos últimos N dias. UI consome para
-- renderizar nudge no modal "Conferir Champion".
--
-- Auth: caller deve ser admin (manage_event OR manage_member) OR self.
-- (Showcase data não é PII; gate aberto seria OK mas mantendo prudência.)
--
-- Rollback:
--   DROP FUNCTION get_recent_showcases_by_member(uuid, int);

CREATE OR REPLACE FUNCTION public.get_recent_showcases_by_member(
  p_member_id uuid,
  p_days int DEFAULT 30
)
RETURNS TABLE(
  showcase_id uuid,
  showcase_type text,
  showcase_title text,
  event_id uuid,
  event_title text,
  event_date date,
  registered_at timestamptz,
  xp_awarded int
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- Auth: admin OR self
  IF v_caller_id <> p_member_id
     AND NOT public.can_by_member(v_caller_id, 'manage_event')
     AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event/manage_member or self';
  END IF;

  RETURN QUERY
  SELECT
    es.id AS showcase_id,
    es.showcase_type,
    es.title AS showcase_title,
    es.event_id,
    e.title AS event_title,
    e.date AS event_date,
    es.created_at AS registered_at,
    COALESCE(es.xp_awarded, 0) AS xp_awarded
  FROM public.event_showcases es
  LEFT JOIN public.events e ON e.id = es.event_id
  WHERE es.member_id = p_member_id
    AND es.created_at >= now() - (p_days || ' days')::interval
  ORDER BY es.created_at DESC;
END;
$function$;

COMMENT ON FUNCTION public.get_recent_showcases_by_member(uuid, int) IS
  'p170 #15 (ADR-0084) — returns showcases registrados pelo member nos últimos N days. UI nudge no modal Champion grant. Admin (manage_event/manage_member) OR self.';

GRANT EXECUTE ON FUNCTION public.get_recent_showcases_by_member(uuid, int) TO authenticated;

NOTIFY pgrst, 'reload schema';
