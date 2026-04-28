-- ADR-0061 W3 — Notion-style request-to-join + list_open_initiatives discovery
-- + cron job para auto-expire invitations stale

CREATE OR REPLACE FUNCTION public.list_open_initiatives()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_member_id uuid;
  v_caller_person_id uuid;
  v_results jsonb;
BEGIN
  SELECT m.id, m.person_id INTO v_caller_member_id, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'initiative_id', i.id,
    'title', i.title,
    'kind', i.kind,
    'join_policy', i.join_policy,
    'status', i.status,
    'description', i.description,
    'has_active_engagement',
      EXISTS (SELECT 1 FROM public.engagements e
              WHERE e.person_id = v_caller_person_id
                AND e.initiative_id = i.id
                AND e.status = 'active'),
    'has_pending_invitation',
      EXISTS (SELECT 1 FROM public.initiative_invitations ii
              WHERE ii.invitee_member_id = v_caller_member_id
                AND ii.initiative_id = i.id
                AND ii.status = 'pending')
  ) ORDER BY i.created_at DESC)
  INTO v_results
  FROM public.initiatives i
  WHERE i.status = 'active'
    AND i.join_policy IN ('request_to_join', 'open');

  RETURN COALESCE(v_results, '[]'::jsonb);
END;
$$;

COMMENT ON FUNCTION public.list_open_initiatives() IS
  'ADR-0061 W3 (#88 ux R3): discovery de iniciativas com join_policy=request_to_join ou open. Inclui has_active_engagement + has_pending_invitation flags para o caller (orienta UX a ocultar duplicate joins).';

CREATE OR REPLACE FUNCTION public.request_to_join_initiative(
  p_initiative_id uuid,
  p_message text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_member_id uuid;
  v_caller_person_id uuid;
  v_initiative record;
  v_default_kind text;
  v_invitation_id uuid;
BEGIN
  SELECT m.id, m.person_id INTO v_caller_member_id, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF length(p_message) < 50 THEN
    RAISE EXCEPTION 'Message must be at least 50 characters describing your motivation (current: %)', length(p_message)
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT i.* INTO v_initiative FROM public.initiatives i WHERE i.id = p_initiative_id;
  IF v_initiative.id IS NULL THEN
    RAISE EXCEPTION 'Initiative not found' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_initiative.status <> 'active' THEN
    RAISE EXCEPTION 'Initiative is not active' USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_initiative.join_policy NOT IN ('request_to_join', 'open') THEN
    RAISE EXCEPTION 'Initiative does not accept self-service requests (join_policy=%)', v_initiative.join_policy
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.engagements e
    WHERE e.person_id = v_caller_person_id
      AND e.initiative_id = p_initiative_id
      AND e.status = 'active'
  ) THEN
    RAISE EXCEPTION 'You already have an active engagement in this initiative'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.initiative_invitations
    WHERE invitee_member_id = v_caller_member_id
      AND initiative_id = p_initiative_id
      AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'You already have a pending invitation/request for this initiative'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  v_default_kind := CASE v_initiative.kind
    WHEN 'study_group' THEN 'study_group_participant'
    WHEN 'workgroup' THEN 'workgroup_member'
    WHEN 'committee' THEN 'committee_member'
    WHEN 'research_tribe' THEN 'volunteer'
    ELSE 'observer'
  END;

  INSERT INTO public.initiative_invitations
    (initiative_id, invitee_member_id, inviter_member_id, kind_scope, message)
  VALUES
    (p_initiative_id, v_caller_member_id, v_caller_member_id, v_default_kind, p_message)
  RETURNING id INTO v_invitation_id;

  RETURN jsonb_build_object(
    'ok', true,
    'invitation_id', v_invitation_id,
    'initiative_id', p_initiative_id,
    'kind_scope', v_default_kind,
    'expires_at', (now() + interval '72 hours'),
    'note', 'Owner of initiative will review your request. Watch for notification or call list_my_initiative_invitations.'
  );
END;
$$;

COMMENT ON FUNCTION public.request_to_join_initiative(uuid, text) IS
  'ADR-0061 W3 (#88 ux R3): Notion-style self-service request. Caller pede para entrar em initiative com join_policy=request_to_join|open. Cria initiative_invitation com invitee=inviter=caller. Owner aprova/rejeita via list_invitations_for_my_initiatives (TBD next slice). Default kind_scope inferido por initiative.kind.';

DO $$
BEGIN
  PERFORM cron.unschedule('expire-stale-invitations-hourly')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'expire-stale-invitations-hourly');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'expire-stale-invitations-hourly',
  '0 * * * *',
  $$SELECT public.expire_stale_initiative_invitations();$$
);

NOTIFY pgrst, 'reload schema';
