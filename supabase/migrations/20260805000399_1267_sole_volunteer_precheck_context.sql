-- #1267 (Tribe UX) — surface the sole-volunteer/leader safeguard BEFORE the leave form.
--
-- Today the researcher who is the only active volunteer of their tribe (or its leader) only learns
-- they cannot self-leave AFTER writing a reason (>= 10 chars) and confirming — the block comes from
-- withdraw_from_initiative's `remaining_of_kind` return. Avoidable friction ("wrote the reason for
-- nothing"). This extends get_my_tribe_request_context (ADDITIVE) to expose `can_self_leave` on the
-- has_tribe case so the FE renders the GP-routing message in place of the button.
--
-- can_self_leave mirrors withdraw_from_initiative's guard exactly: if 'volunteer' is a required
-- engagement kind of research_tribe AND the caller is the only active/onboarding volunteer of the
-- tribe, withdraw would block -> can_self_leave = false. Only computed when there is an active
-- engagement to leave (current_tribe_initiative_id present); NULL otherwise (legacy/no-tribe cases,
-- where the FE already hides the leave action). The server RPC stays the source of truth; this is a
-- pre-check for UX, not a new authority path.
CREATE OR REPLACE FUNCTION public.get_my_tribe_request_context()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_person_id uuid;
  v_member_status text;
  v_is_active boolean;
  v_tribe_id integer;
  v_has_tribe_engagement boolean;
  v_eligible boolean;
  v_reason text;
  v_current_tribe_title text;
  v_current_tribe_id integer;
  v_current_tribe_initiative_id uuid;
  v_pending jsonb;
  v_tribes jsonb;
  v_deadline timestamptz;
  v_window_closed boolean;
  v_can_self_leave boolean;
  v_kind_required text[];
  v_active_vol_count integer;
BEGIN
  SELECT m.id, m.person_id, m.member_status, m.is_active, m.tribe_id
    INTO v_member_id, v_person_id, v_member_status, v_is_active, v_tribe_id
    FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_member_id IS NULL THEN
    RETURN jsonb_build_object('eligible', false, 'ineligible_reason', 'no_member', 'current_tribe_title', NULL, 'current_tribe_id', NULL, 'current_tribe_initiative_id', NULL, 'can_self_leave', NULL, 'pending', NULL, 'tribes', '[]'::jsonb, 'deadline', NULL);
  END IF;

  -- Deadline SSOT (absent/null = open window). Surfaced in the payload + drives the window_closed reason.
  v_deadline := (SELECT (value #>> '{}')::timestamptz FROM public.platform_settings WHERE key = 'tribe_request_deadline');
  v_window_closed := v_deadline IS NOT NULL AND now() > v_deadline;

  -- caller's pending research_tribe self-request (invitee == me), if any.
  -- #1255: invitation_id added so the FE can cancel this exact pending request.
  SELECT to_jsonb(p) INTO v_pending FROM (
    SELECT ii.id AS invitation_id, i.legacy_tribe_id AS tribe_id, i.title, ii.message, ii.created_at, ii.expires_at
    FROM public.initiative_invitations ii
    JOIN public.initiatives i ON i.id = ii.initiative_id AND i.kind = 'research_tribe'
    WHERE ii.invitee_member_id = v_member_id AND ii.status = 'pending'
    ORDER BY ii.created_at DESC
    LIMIT 1
  ) p;

  -- already in a tribe via an active engagement?
  v_has_tribe_engagement := EXISTS (
    SELECT 1 FROM public.engagements e
    JOIN public.initiatives i ON i.id = e.initiative_id AND i.kind = 'research_tribe'
    WHERE e.person_id = v_person_id AND e.kind = 'volunteer' AND e.status = 'active'
  );

  -- eligible to self-request: active, termed (not pre-onboarding), no tribe yet (mirrors request_tribe_assignment)
  v_eligible := v_is_active IS TRUE
    AND v_tribe_id IS NULL
    AND NOT v_has_tribe_engagement
    AND v_person_id IS NOT NULL
    AND NOT public.member_is_pre_onboarding(v_person_id, v_member_status);

  -- #1139 Item 1: surface WHY when ineligible so the FE renders an explicit empty-state instead of a
  -- blank block. Priority mirrors request_tribe_assignment's guard sequence: inactive → has-tribe → term.
  -- Deadline enforcement: if the window is closed and the caller has no tribe (so they would want to
  -- request), window_closed outranks the term/eligible states — after the deadline there is nothing to
  -- request. has_tribe callers keep their own state (the deadline is about joining, not their membership).
  IF v_window_closed AND v_tribe_id IS NULL AND NOT v_has_tribe_engagement THEN
    v_eligible := false;
    v_reason := 'window_closed';
  ELSIF v_eligible THEN
    v_reason := NULL;
  ELSIF v_person_id IS NULL THEN
    v_reason := 'no_member';
  ELSIF v_is_active IS DISTINCT FROM true THEN
    v_reason := 'inactive';
  ELSIF v_tribe_id IS NOT NULL OR v_has_tribe_engagement THEN
    v_reason := 'has_tribe';
  ELSIF public.member_is_pre_onboarding(v_person_id, v_member_status) THEN
    v_reason := 'pending_term';
  ELSE
    v_reason := 'ineligible';
  END IF;

  -- #1256: for the has_tribe empty-state, prefer the initiative where the caller holds the ACTIVE
  -- volunteer engagement — withdraw_from_initiative requires an active engagement on that initiative,
  -- so the FE's "leave tribe" action targets it. Returns tribe_id + initiative_id + title together.
  IF v_reason = 'has_tribe' THEN
    SELECT i.id, i.legacy_tribe_id, i.title
      INTO v_current_tribe_initiative_id, v_current_tribe_id, v_current_tribe_title
    FROM public.initiatives i
    JOIN public.engagements e ON e.initiative_id = i.id
      AND e.person_id = v_person_id AND e.kind = 'volunteer' AND e.status = 'active'
    WHERE i.kind = 'research_tribe'
    ORDER BY (i.legacy_tribe_id = v_tribe_id) DESC NULLS LAST, e.start_date DESC, e.created_at DESC
    LIMIT 1;

    -- legacy-only fallback: tribe_id set but no active engagement (liaison / stale bridge). Keep the
    -- title for the empty-state; leave initiative_id NULL so the FE hides the self-service leave action.
    IF v_current_tribe_title IS NULL THEN
      SELECT i.title, i.legacy_tribe_id INTO v_current_tribe_title, v_current_tribe_id
      FROM public.initiatives i
      WHERE i.kind = 'research_tribe' AND i.legacy_tribe_id = v_tribe_id
      ORDER BY i.legacy_tribe_id
      LIMIT 1;
    END IF;

    -- #1267: pre-check the sole-volunteer/leader safeguard so the FE routes to the GP BEFORE the reason
    -- form. Mirrors withdraw_from_initiative: if 'volunteer' is a required kind of research_tribe and the
    -- caller is the only active/onboarding volunteer of the tribe, withdraw would block. Only meaningful
    -- when there is an active engagement to leave (initiative_id present); NULL otherwise.
    IF v_current_tribe_initiative_id IS NOT NULL THEN
      SELECT ik.required_engagement_kinds INTO v_kind_required
      FROM public.initiative_kinds ik
      WHERE ik.slug = 'research_tribe';

      IF 'volunteer' = ANY(coalesce(v_kind_required, ARRAY[]::text[])) THEN
        SELECT count(*) INTO v_active_vol_count
        FROM public.engagements e
        WHERE e.initiative_id = v_current_tribe_initiative_id
          AND e.kind = 'volunteer'
          AND e.status IN ('active', 'onboarding');
        v_can_self_leave := v_active_vol_count > 1;
      ELSE
        v_can_self_leave := true;
      END IF;
    END IF;
  END IF;

  -- selectable active research_tribe tribes (single source of truth = initiatives, not static data)
  SELECT coalesce(
    jsonb_agg(jsonb_build_object('tribe_id', i.legacy_tribe_id, 'title', i.title) ORDER BY i.legacy_tribe_id),
    '[]'::jsonb
  ) INTO v_tribes
  FROM public.initiatives i
  WHERE i.kind = 'research_tribe' AND i.status = 'active' AND i.legacy_tribe_id IS NOT NULL;

  RETURN jsonb_build_object(
    'eligible', v_eligible,
    'ineligible_reason', v_reason,
    'current_tribe_title', v_current_tribe_title,
    'current_tribe_id', v_current_tribe_id,
    'current_tribe_initiative_id', v_current_tribe_initiative_id,
    'can_self_leave', v_can_self_leave,
    'pending', v_pending,
    'tribes', v_tribes,
    'deadline', v_deadline
  );
END;
$function$;
