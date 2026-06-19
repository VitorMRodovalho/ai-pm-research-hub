-- Tribe Selection Híbrida — PR3 (FE leader-facing): leader's pending-requests reader.
-- See docs/specs/SPEC_TRIBE_SELECTION_HYBRID.md §5. Council: ux-leader (FE), this RPC is the data layer.
--
-- GROUNDING CORRECTION (live 2026-06-18): the SPEC said PR3 "reusa list_invitations_for_my_initiatives".
-- That RPC scopes to initiatives where the caller is owner/coordinator/lead (role IN
-- ('owner','coordinator','lead')) OR admin — a TRIBE LEADER is engagement volunteer/role='leader'
-- ('leader' != 'lead'), so it returns an EMPTY list for them. This is the SAME authority mismatch
-- PR1 hit on the WRITE path (review_tribe_request needed Caminho-3 inline-scope because role='leader'
-- is not in the shared gate). The leader-facing READ has the identical gap. This RPC fills it with
-- the same Caminho-3 inline authority as review_tribe_request.
--
-- list_tribe_pending_requests(p_tribe_id integer) -> pending self-requests for that tribe, each with
-- the requester's name (PII -> log_pii_access, mirroring list_invitations_for_my_initiatives).
-- Authority: GP (manage_member) OR active volunteer/leader engagement in THIS tribe's initiative.
-- SECURITY DEFINER STABLE, authenticated-only.
--
-- ROLLBACK: DROP FUNCTION IF EXISTS public.list_tribe_pending_requests(integer); NOTIFY pgrst, 'reload schema';

CREATE OR REPLACE FUNCTION public.list_tribe_pending_requests(p_tribe_id integer)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE
  v_caller_member_id uuid;
  v_caller_person_id uuid;
  v_is_admin boolean;
  v_is_leader boolean;
  v_initiative_id uuid;
  v_results jsonb;
  v_count integer;
BEGIN
  SELECT m.id, m.person_id INTO v_caller_member_id, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT i.id INTO v_initiative_id
  FROM public.initiatives i
  WHERE i.legacy_tribe_id = p_tribe_id AND i.kind = 'research_tribe';
  IF v_initiative_id IS NULL THEN
    RAISE EXCEPTION 'Tribo não encontrada' USING ERRCODE = 'no_data_found';
  END IF;

  -- Authority (Caminho-3 inline-scope, identical to review_tribe_request): GP OR leader of THIS tribe.
  v_is_admin := public.can_by_member(v_caller_member_id, 'manage_member');
  IF NOT v_is_admin THEN
    v_is_leader := EXISTS (
      SELECT 1 FROM public.engagements e
      WHERE e.person_id = v_caller_person_id
        AND e.initiative_id = v_initiative_id
        AND e.kind = 'volunteer'
        AND e.role = 'leader'
        AND e.status = 'active'
    );
    IF NOT v_is_leader THEN
      RAISE EXCEPTION 'Não autorizado: apenas o líder desta tribo ou o GP podem ver os pedidos'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  SELECT
    jsonb_agg(jsonb_build_object(
      'invitation_id', ii.id,
      'invitee_member_id', ii.invitee_member_id,
      'invitee_name', m.name,
      'message', ii.message,
      'created_at', ii.created_at,
      'expires_at', ii.expires_at
    ) ORDER BY ii.created_at DESC),
    count(*)
  INTO v_results, v_count
  FROM public.initiative_invitations ii
  JOIN public.members m ON m.id = ii.invitee_member_id
  WHERE ii.initiative_id = v_initiative_id
    AND ii.status = 'pending'
    AND ii.invitee_member_id = ii.inviter_member_id;  -- self-requests only

  IF v_count > 0 THEN
    PERFORM public.log_pii_access(
      v_caller_member_id,
      ARRAY['name']::text[],
      'list_tribe_pending_requests',
      format('Leader/GP viewing %s pending tribe request(s) for tribe_id=%s', v_count, p_tribe_id)
    );
  END IF;

  RETURN COALESCE(v_results, '[]'::jsonb);
END;
$function$;

REVOKE ALL ON FUNCTION public.list_tribe_pending_requests(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_tribe_pending_requests(integer) TO authenticated;

NOTIFY pgrst, 'reload schema';
