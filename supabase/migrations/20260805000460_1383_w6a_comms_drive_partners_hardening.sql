-- #1383 Wave 6a (comms/drive/partners) raw-side hardening.
-- (1) search_partner_cards: add the #785 confidential gate (ADR-0105) on the board_item join and
--     move it off the PUBLIC/anon grant to authenticated-only. It was SECURITY DEFINER with NO
--     EXECUTE grant to authenticated (dead: 0 calls, unreachable) and no confidential filter on the
--     board_items join. The semantic partner_crm search mode needs it reachable AND #785-safe.
CREATE OR REPLACE FUNCTION public.search_partner_cards(p_link_role text DEFAULT NULL::text, p_card_status text DEFAULT NULL::text, p_chapter text DEFAULT NULL::text, p_limit integer DEFAULT 100)
 RETURNS TABLE(link_id uuid, link_role text, link_notes text, linked_at timestamp with time zone, linked_by_name text, partner_entity_id uuid, partner_name text, partner_chapter text, partner_status text, board_item_id uuid, board_item_title text, board_item_status text, board_item_due_date date, board_item_assignee_name text, board_id uuid, board_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_limit int;
BEGIN
  SELECT m.id INTO v_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_member_id IS NULL THEN RETURN; END IF;

  v_limit := GREATEST(1, LEAST(COALESCE(p_limit, 100), 500));

  RETURN QUERY
  SELECT
    pc.id, pc.link_role, pc.notes, pc.created_at, cm.name,
    pe.id, pe.name, pe.chapter, pe.status,
    bi.id, bi.title, bi.status, bi.due_date, am.name,
    bi.board_id, pb.board_name
  FROM public.partner_cards pc
  JOIN public.partner_entities pe ON pe.id = pc.partner_entity_id
  JOIN public.board_items bi ON bi.id = pc.board_item_id
  LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
  LEFT JOIN public.members am ON am.id = bi.assignee_id
  LEFT JOIN public.members cm ON cm.id = pc.created_by
  WHERE (p_link_role IS NULL OR pc.link_role = p_link_role)
    AND (p_card_status IS NULL OR bi.status = p_card_status)
    AND (p_chapter IS NULL OR pe.chapter = p_chapter)
    AND public.rls_can_see_item(bi.id)
  ORDER BY pc.created_at DESC
  LIMIT v_limit;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.search_partner_cards(text, text, text, integer) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.search_partner_cards(text, text, text, integer) TO authenticated;

-- (2) #965 anon-write hygiene: the webinar/idea write RPCs drifted onto a PUBLIC/anon EXECUTE grant.
--     All already reject callers whose auth.uid() has no member row (fail-closed), so this is
--     defense-in-depth. REVOKE FROM anon, PUBLIC then re-GRANT authenticated so the PUBLIC-default
--     trap (#965) does not strip legitimate authenticated access.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure::text AS sig
    FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace
      AND p.proname IN (
        'create_webinar_proposal','update_webinar_proposal','review_webinar_proposal',
        'convert_proposal_to_webinar','update_webinar_comms_assets',
        'advance_idea_stage','fork_idea_to_channel','link_idea_to_series','propose_publication_idea'
      )
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon, PUBLIC', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.sig);
  END LOOP;
END $$;
