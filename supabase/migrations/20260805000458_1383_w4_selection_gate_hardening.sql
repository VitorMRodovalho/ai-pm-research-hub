-- #1383 Wave 4 (selection/evaluation) raw-side gate hardening.
-- (1) Widen get_application_interviews from GP-only to committee (taxonomy §2.4, owner-approved
--     at Wave 0), keeping platform-admin global access and adding ADR-0109 COI recusal so a
--     candidate seated on the committee stays recused. Based on the LIVE body (byte-exact SELECT).
-- (2) REVOKE anon EXECUTE on recalculate_cycle_rankings (ACL drift; body already fail-closed,
--     defense-in-depth per Wave 0 hotfix class #2 / #965 trap).

CREATE OR REPLACE FUNCTION public.get_application_interviews(p_application_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_id uuid;
  v_is_committee boolean;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  SELECT cycle_id INTO v_cycle_id FROM public.selection_applications WHERE id = p_application_id;
  IF v_cycle_id IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  -- #1383 W4 (taxonomy §2.4): widen from GP-only to committee, per this tool's own
  -- docstring ("Used by committee to coordinate"). A committee member of THIS
  -- application's cycle may read its interviews; platform admins keep global access.
  SELECT EXISTS (
    SELECT 1 FROM public.selection_committee
    WHERE cycle_id = v_cycle_id AND member_id = v_caller_id
  ) INTO v_is_committee;

  IF NOT v_is_committee AND NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: requires committee membership or manage_platform permission';
  END IF;

  -- ADR-0109 PR-2 COI recusal: an active candidate in this application's cycle is recused
  -- from selection surfaces even if seated on the committee.
  IF public.selection_coi_recused(v_caller_id, v_cycle_id) THEN
    RAISE EXCEPTION 'recused_conflict_of_interest';
  END IF;

  RETURN (
    SELECT coalesce(json_agg(json_build_object(
      'id', si.id, 'scheduled_at', si.scheduled_at, 'duration_minutes', si.duration_minutes,
      'status', si.status, 'conducted_at', si.conducted_at, 'theme_of_interest', si.theme_of_interest,
      'notes', si.notes, 'interviewer_ids', si.interviewer_ids
    ) ORDER BY si.created_at DESC), '[]'::json)
    FROM selection_interviews si
    WHERE si.application_id = p_application_id
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.recalculate_cycle_rankings(uuid, text) FROM anon;
