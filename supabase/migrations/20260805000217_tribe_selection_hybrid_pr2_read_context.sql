-- Tribe Selection Híbrida — PR2 (FE researcher-facing): read primitive.
-- See docs/specs/SPEC_TRIBE_SELECTION_HYBRID.md §5. Council: ux-leader (FE), this RPC is the data layer.
--
-- GROUNDING CORRECTION (live 2026-06-18): the SPEC said PR2 "reusa list_my_initiative_invitations".
-- That public RPC DOES NOT EXIST — it is an MCP-only tool name. The only invitations-list RPC is
-- list_invitations_for_my_initiatives (LEADER-facing, for PR3). There was no researcher-facing
-- "my own pending tribe request" read. This RPC fills that gap, following the get_my_buddy /
-- get_my_onboarding convention: ONE read powers the whole island.
--
-- Returns { eligible, pending, tribes } for the caller:
--   eligible : can this member self-request a tribe right now? (active + termed + no tribe yet)
--              — mirrors request_tribe_assignment's gates so the FE never shows a picker that errors.
--   pending  : the caller's pending research_tribe self-request (tribe_id/title/message/dates) or null.
--   tribes   : selectable active research_tribe initiatives [{tribe_id, title}] for the picker.
-- Read-only, no PII beyond the caller's own row. authenticated-only.
--
-- ROLLBACK: DROP FUNCTION IF EXISTS public.get_my_tribe_request_context(); NOTIFY pgrst, 'reload schema';

CREATE OR REPLACE FUNCTION public.get_my_tribe_request_context()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE
  v_member_id uuid;
  v_person_id uuid;
  v_member_status text;
  v_is_active boolean;
  v_tribe_id integer;
  v_has_tribe_engagement boolean;
  v_eligible boolean;
  v_pending jsonb;
  v_tribes jsonb;
BEGIN
  SELECT m.id, m.person_id, m.member_status, m.is_active, m.tribe_id
    INTO v_member_id, v_person_id, v_member_status, v_is_active, v_tribe_id
    FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_member_id IS NULL THEN
    RETURN jsonb_build_object('eligible', false, 'pending', NULL, 'tribes', '[]'::jsonb);
  END IF;

  -- caller's pending research_tribe self-request (invitee == me), if any
  SELECT to_jsonb(p) INTO v_pending FROM (
    SELECT i.legacy_tribe_id AS tribe_id, i.title, ii.message, ii.created_at, ii.expires_at
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

  -- selectable active research_tribe tribes (single source of truth = initiatives, not static data)
  SELECT coalesce(
    jsonb_agg(jsonb_build_object('tribe_id', i.legacy_tribe_id, 'title', i.title) ORDER BY i.legacy_tribe_id),
    '[]'::jsonb
  ) INTO v_tribes
  FROM public.initiatives i
  WHERE i.kind = 'research_tribe' AND i.status = 'active' AND i.legacy_tribe_id IS NOT NULL;

  RETURN jsonb_build_object(
    'eligible', v_eligible,
    'pending', v_pending,
    'tribes', v_tribes
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_my_tribe_request_context() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_tribe_request_context() TO authenticated;

NOTIFY pgrst, 'reload schema';
