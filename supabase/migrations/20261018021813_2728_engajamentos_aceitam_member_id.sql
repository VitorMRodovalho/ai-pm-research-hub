-- #2728: get_active_engagements aceita persons.id OU members.id, como get_person.
--
-- member_get (MCP) passa o members.id como p_person_id. get_person resolve os dois desde o #1383 W2;
-- get_active_engagements usava o valor literalmente e devolvia count 0, sem erro. A migration do
-- #1383 W2 (20260805000454) recapturou esta função sem acrescentar a resolução.
--
-- Muda só o ramo ELSE: resolve o id como get_person e checa a autoridade ANTES do "não encontrado",
-- para quem não tem manage_member não distinguir id inexistente de id de outra pessoa. Um id que
-- não resolve, para quem tem manage_member, passa a devolver 'Person not found' em vez de count 0.
--
-- Corpo de partida: a captura 20260805000454, idêntica ao vivo (md5 normalizado 103350cf) no dia.
-- ROLLBACK: reaplicar o CREATE OR REPLACE de get_active_engagements em 20260805000454.

CREATE OR REPLACE FUNCTION public.get_active_engagements(p_person_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_caller_person_id uuid;
  v_target_person_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT id INTO v_caller_person_id FROM public.persons WHERE legacy_member_id = v_caller_member_id;

  IF p_person_id IS NULL THEN
    v_target_person_id := v_caller_person_id;
  ELSE
    -- #2728: accept either a persons.id OR a members.id (persons.legacy_member_id), exactly as
    -- get_person does since #1383 W2. A members.id used to be taken literally as a person id and
    -- returned count 0 with no error (member_get by member_id).
    SELECT id INTO v_target_person_id FROM public.persons WHERE id = p_person_id;
    IF v_target_person_id IS NULL THEN
      SELECT id INTO v_target_person_id FROM public.persons WHERE legacy_member_id = p_person_id;
    END IF;
    -- Authority BEFORE "not found": an id that does not resolve is also not the caller, so a
    -- non-manager gets the same 'Unauthorized' for someone else's id and for a nonexistent one
    -- (no existence oracle).
    IF v_target_person_id IS DISTINCT FROM v_caller_person_id THEN
      IF NOT public.can(v_caller_person_id, 'manage_member', NULL, NULL) THEN
        RETURN jsonb_build_object('error', 'Unauthorized: manage_member required');
      END IF;
    END IF;
  END IF;

  IF v_target_person_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Person not found');
  END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', e.id, 'kind', e.kind, 'kind_display', ek.display_name, 'role', e.role,
      'status', e.status, 'initiative_id', e.initiative_id, 'initiative_name', i.title,
      'initiative_kind', i.kind, 'start_date', e.start_date, 'end_date', e.end_date,
      'legal_basis', e.legal_basis, 'has_agreement', (e.agreement_certificate_id IS NOT NULL),
      'is_authoritative', (e.status = 'active' AND e.start_date <= CURRENT_DATE
        AND (e.end_date IS NULL OR e.end_date >= CURRENT_DATE)
        AND (e.agreement_certificate_id IS NOT NULL OR NOT COALESCE(ek.requires_agreement, false))),
      'granted_at', e.granted_at
    ) ORDER BY e.start_date DESC
  ), '[]'::jsonb) INTO v_result
  FROM public.engagements e
  JOIN public.engagement_kinds ek ON ek.slug = e.kind
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.person_id = v_target_person_id AND e.status = 'active';

  RETURN jsonb_build_object('person_id', v_target_person_id, 'engagements', v_result, 'count', jsonb_array_length(v_result));
END;
$function$;

