-- ADR-0061 W5: Self-service withdraw + owner-detail engagement listing
-- Closes #88 lifecycle gap: members can now exit initiatives without admin intervention,
-- and owners can audit engagements with granted_by/source/motivation context.
-- Rollback: DROP FUNCTION public.withdraw_from_initiative(uuid, text);
--           DROP FUNCTION public.list_initiative_engagements(uuid, text);

-- =============================================================================
-- RPC 1: withdraw_from_initiative
-- Self-service exit from an initiative. Safeguard: blocks withdrawal if caller
-- holds a kind that is in initiative_kinds.required_engagement_kinds AND no
-- other active person carries that same kind (would orphan the initiative).
-- Reason >=10 chars enforced at DB level (audit trail completeness — ADR-0061
-- foundation pattern: message constraints survive UI refactors).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.withdraw_from_initiative(
  p_initiative_id uuid,
  p_reason text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
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
  SET status = 'revoked',
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
$$;

REVOKE ALL ON FUNCTION public.withdraw_from_initiative(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.withdraw_from_initiative(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.withdraw_from_initiative(uuid, text) IS
'ADR-0061 W5: Self-service exit from an initiative. Blocks if caller is the sole holder of a required engagement kind (study_group_owner sole, committee/workgroup/congress/research_tribe last required member). Reason >=10 chars (audit trail). Sets engagement.status=revoked + metadata.withdraw_source=self_service.';

-- =============================================================================
-- RPC 2: list_initiative_engagements
-- Owner-detail listing complementing get_initiative_members (which is
-- public-shape). Includes granted_by, source, motivation, and lifecycle
-- timestamps. Authority: admin (manage_member/view_pii on initiative) OR
-- active member of the initiative (own enrollment grants visibility).
-- Status filter: active|all|revoked|onboarding.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.list_initiative_engagements(
  p_initiative_id uuid,
  p_status_filter text DEFAULT 'active'
) RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_person_id uuid;
  v_can_see_detail boolean;
  v_is_member boolean;
  v_authority text;
  v_result jsonb;
BEGIN
  SELECT p.id INTO v_caller_person_id
  FROM public.persons p
  WHERE p.auth_id = auth.uid();

  IF v_caller_person_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF p_status_filter NOT IN ('active', 'all', 'revoked', 'onboarding') THEN
    RETURN jsonb_build_object('error', format('Invalid p_status_filter: %s. Use active|all|revoked|onboarding', p_status_filter));
  END IF;

  v_can_see_detail := public.can(v_caller_person_id, 'manage_member', 'initiative', p_initiative_id)
                    OR public.can(v_caller_person_id, 'view_pii', 'initiative', p_initiative_id);

  v_is_member := EXISTS (
    SELECT 1 FROM public.engagements e
    WHERE e.person_id = v_caller_person_id
      AND e.initiative_id = p_initiative_id
      AND e.status = 'active'
  );

  IF NOT (v_can_see_detail OR v_is_member) THEN
    RETURN jsonb_build_object('error', 'Not authorized to list engagements for this initiative');
  END IF;

  v_authority := CASE WHEN v_can_see_detail THEN 'admin' WHEN v_is_member THEN 'member' ELSE 'none' END;

  SELECT coalesce(jsonb_agg(row_to_json(eng) ORDER BY eng.role_order, eng.start_date DESC), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      e.id AS engagement_id,
      e.kind,
      e.role,
      e.status,
      e.start_date,
      e.end_date,
      e.granted_at,
      e.revoked_at,
      e.revoke_reason,
      e.legal_basis,
      p.id AS person_id,
      COALESCE(p.name, mb.name) AS person_name,
      COALESCE(p.photo_url, mb.photo_url) AS photo_url,
      mb.id AS member_id,
      gp.name AS granted_by_name,
      e.granted_by AS granted_by_person_id,
      e.metadata->>'source' AS source,
      CASE WHEN v_can_see_detail THEN e.metadata->>'motivation' ELSE NULL END AS motivation,
      ek.display_name AS kind_display,
      CASE e.role
        WHEN 'leader' THEN 0
        WHEN 'coordinator' THEN 1
        WHEN 'owner' THEN 1
        WHEN 'participant' THEN 2
        WHEN 'observer' THEN 3
        ELSE 4
      END AS role_order
    FROM public.engagements e
    JOIN public.persons p ON p.id = e.person_id
    LEFT JOIN public.members mb ON mb.id = p.legacy_member_id
    LEFT JOIN public.persons gp ON gp.id = e.granted_by
    LEFT JOIN public.engagement_kinds ek ON ek.slug = e.kind
    WHERE e.initiative_id = p_initiative_id
      AND (
        (p_status_filter = 'active' AND e.status = 'active')
        OR (p_status_filter = 'all')
        OR (p_status_filter = 'revoked' AND e.status = 'revoked')
        OR (p_status_filter = 'onboarding' AND e.status = 'onboarding')
      )
  ) eng;

  RETURN jsonb_build_object(
    'initiative_id', p_initiative_id,
    'status_filter', p_status_filter,
    'authority', v_authority,
    'engagements', v_result
  );
END;
$$;

REVOKE ALL ON FUNCTION public.list_initiative_engagements(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_initiative_engagements(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.list_initiative_engagements(uuid, text) IS
'ADR-0061 W5: Owner/admin-detail engagement listing for an initiative. Adds granted_by/source/motivation/lifecycle timestamps over get_initiative_members. Authority: manage_member or view_pii on initiative (admin) OR active membership (member-self-view). Motivation gated to admin only. status_filter: active|all|revoked|onboarding.';
