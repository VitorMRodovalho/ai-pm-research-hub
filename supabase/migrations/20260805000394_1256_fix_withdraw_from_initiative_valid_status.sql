-- #1256 Wave 2 (latent-bug fix): withdraw_from_initiative set status='revoked', which is NOT in
-- engagements_status_check (pending/active/suspended/expired/offboarded/anonymized). The UPDATE
-- always threw the CHECK violation, so the RPC never succeeded for any initiative (zero 'revoked'
-- rows exist). Wave 2's self-service "leave tribe" reuses this RPC (SPEC D1). Fix: use 'offboarded'
-- (a valid terminal status) so the engagement ends and the bridge demotion trigger
-- _sync_tribe_id_from_engagement (fires on any status <> 'active') clears members.tribe_id when no
-- other active tribe engagement remains. Body is the live body verbatim except the status literal.
CREATE OR REPLACE FUNCTION public.withdraw_from_initiative(p_initiative_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_person_id uuid;
  v_engagement record;
  v_initiative record;
  v_kind_required text[];
  v_active_count_same_kind integer;
  v_is_required_kind boolean;
BEGIN
  IF coalesce(length(trim(p_reason)), 0) < 10 THEN
    RETURN jsonb_build_object('error', 'Reason required and must be at least 10 characters', 'min_length', 10);
  END IF;

  SELECT p.id INTO v_caller_person_id
  FROM public.persons p
  WHERE p.auth_id = auth.uid();

  IF v_caller_person_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT e.* INTO v_engagement
  FROM public.engagements e
  WHERE e.person_id = v_caller_person_id
    AND e.initiative_id = p_initiative_id
    AND e.status IN ('active', 'onboarding')
  ORDER BY e.start_date DESC, e.created_at DESC
  LIMIT 1;

  IF v_engagement.id IS NULL THEN
    RETURN jsonb_build_object(
      'error', 'You have no active engagement in this initiative',
      'hint', 'Use get_active_engagements to find your engagements'
    );
  END IF;

  SELECT i.id, i.title, i.kind, i.status INTO v_initiative
  FROM public.initiatives i
  WHERE i.id = p_initiative_id;

  SELECT ik.required_engagement_kinds INTO v_kind_required
  FROM public.initiative_kinds ik
  WHERE ik.slug = v_initiative.kind;

  v_is_required_kind := v_engagement.kind = ANY(coalesce(v_kind_required, ARRAY[]::text[]));

  IF v_is_required_kind THEN
    SELECT count(*) INTO v_active_count_same_kind
    FROM public.engagements e
    WHERE e.initiative_id = p_initiative_id
      AND e.kind = v_engagement.kind
      AND e.status IN ('active', 'onboarding');

    IF v_active_count_same_kind <= 1 THEN
      RETURN jsonb_build_object(
        'error', format('Cannot withdraw: you are the only active "%s" of this initiative. Transfer the role to another member before leaving.', v_engagement.kind),
        'hint', 'An admin or coordinator must add a replacement engagement first via manage_initiative_engagement, then retry withdraw.',
        'engagement_id', v_engagement.id,
        'kind', v_engagement.kind,
        'remaining_of_kind', v_active_count_same_kind
      );
    END IF;
  END IF;

  UPDATE public.engagements
  SET status = 'offboarded',
      revoked_at = now(),
      revoked_by = v_caller_person_id,
      revoke_reason = format('self_withdraw: %s', p_reason),
      end_date = CURRENT_DATE,
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'withdrawn_at', now(),
        'withdraw_source', 'self_service',
        'withdraw_reason', p_reason
      ),
      updated_at = now()
  WHERE id = v_engagement.id;

  RETURN jsonb_build_object(
    'ok', true,
    'engagement_id', v_engagement.id,
    'initiative_id', p_initiative_id,
    'initiative_title', v_initiative.title,
    'kind', v_engagement.kind,
    'role', v_engagement.role,
    'withdrew_at', now()
  );
END;
$function$;
