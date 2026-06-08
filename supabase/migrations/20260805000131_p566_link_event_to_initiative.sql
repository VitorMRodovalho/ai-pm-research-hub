-- Migration: 20260805000131_p566_link_event_to_initiative
-- Issue: #566 — Security follow-up (#564): event-author can reassign own event's initiative_id
--                cross-tribe via direct .update()
-- Refs: #564, PR #565, ADR-0007 (can() authority), GC-162
--
-- Finding (MEDIUM): the events edit path writes initiative_id via a direct
-- sb.from('events').update(...). Under #564 RLS, UPDATE re-evaluates
-- rls_can_write_event(new initiative_id, created_by); for the AUTHOR the author carve-out passes
-- regardless of the new initiative's tribe → an author can move their own event to any tribe's
-- initiative via PostgREST, which update_event's tribe-scope gate disallows.
--
-- Remediation: a SECDEF RPC that reassigns initiative_id behind a tribe-scope gate, so the frontend
-- can stop writing initiative_id directly. Gate (two checks):
--   (1) caller can write the event in its CURRENT state — rls_can_write_event(current_initiative, created_by)
--       (author OR manage_event-with-tribe-scope on the current initiative). Same predicate as update_event.
--   (2) caller can PLACE the event into the TARGET initiative — rls_can_write_event(p_initiative_id, NULL).
--       Passing created_by = NULL deliberately DISABLES the author carve-out, so a mere author (or a
--       tribe_leader) cannot move an event into a tribe they do not manage. Org-level managers (no tribe
--       restriction) still pass for any tribe — unchanged authority. Unlink (p_initiative_id IS NULL)
--       needs only (1).
-- This preserves the #564 invariant "if the legitimate edit would succeed, the link still passes" while
-- closing the cross-tribe author move. audience_level is set to 'initiative' when linking (parity with the
-- prior post-create direct write); the edit paths re-assert the final audience via assignEventTagsAndAudience.
--
-- Scope notes (council):
--   * Linking requires manage_event on the TARGET (check 2). This does NOT regress legitimate authors:
--     events_insert_authority requires rls_can('manage_event') to CREATE an event, so every author holds
--     manage_event by construction and can link/move within their own tribe. Only the cross-tribe author
--     move (and any author who has since lost manage_event) is blocked — which is exactly the #566 fix.
--   * Single-event (anchor) by design — parity with the current frontend, which links the anchor only
--     (update_future_events_in_group does not carry initiative_id). Re-linking a recurring anchor leaves
--     siblings on their prior initiative; batch sibling re-link is out of scope here.
--   * A non-existent target initiative is rejected explicitly (resolve_tribe_id(bogus) returns NULL, which
--     would otherwise slip past the tribe-scope guard; the events.initiative_id FK would then 23503).
--
-- Rollback: DROP FUNCTION public.link_event_to_initiative(uuid, uuid); (frontend reverts to direct update).
-- After apply: NOTIFY pgrst, 'reload schema' (new RPC on the PostgREST surface; also issued at file end).

CREATE OR REPLACE FUNCTION public.link_event_to_initiative(p_event_id uuid, p_initiative_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_created_by uuid;
  v_current_initiative_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  SELECT created_by, initiative_id INTO v_created_by, v_current_initiative_id
  FROM public.events WHERE id = p_event_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Event not found');
  END IF;

  -- (1) caller must be able to write the event in its current state (author or current manager).
  IF NOT public.rls_can_write_event(v_current_initiative_id, v_created_by) THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  -- target must exist — a non-existent uuid would make resolve_tribe_id() NULL (slipping past the
  -- tribe-scope guard in check 2) and then trip the events.initiative_id FK (23503) as a raw 500.
  IF p_initiative_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.initiatives WHERE id = p_initiative_id) THEN
    RETURN json_build_object('success', false, 'error', 'Initiative not found');
  END IF;

  -- (2) caller must have manage_event authority for the TARGET initiative's tribe — author carve-out
  --     disabled (created_by => NULL) so an author/tribe_leader cannot move cross-tribe.
  IF p_initiative_id IS NOT NULL AND NOT public.rls_can_write_event(p_initiative_id, NULL) THEN
    RETURN json_build_object('success', false, 'error', 'Cross-tribe initiative move requires manage_event on the target tribe');
  END IF;

  UPDATE public.events
  SET initiative_id = p_initiative_id,
      audience_level = CASE WHEN p_initiative_id IS NOT NULL THEN 'initiative' ELSE audience_level END
  WHERE id = p_event_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Event not found or already deleted');
  END IF;

  RETURN json_build_object('success', true, 'event_id', p_event_id, 'initiative_id', p_initiative_id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.link_event_to_initiative(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.link_event_to_initiative(uuid, uuid) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
