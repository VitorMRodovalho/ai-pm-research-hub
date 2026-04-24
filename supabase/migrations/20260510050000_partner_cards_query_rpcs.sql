-- =============================================================================
-- partner_cards query surface — 2 new read RPCs
-- =============================================================================
-- Issue: #85 Onda A — complete partner↔card surface (p42 Track C1 follow-up)
-- Context: Track C1 shipped link/unlink/list_partner_cards (per-partner view).
--   Missing: inverse card→partners query + cross-partner admin search.
--
-- Adds:
--   1. list_card_partners(board_item_id) — "which partners are stakeholders
--      on this card?" (inverse of list_partner_cards)
--   2. search_partner_cards(link_role?, card_status?, chapter?, limit?) —
--      cross-partner admin view. "All deliverable cards across partners",
--      "all contract cards for PMI-CE chapter", etc.
--
-- Auth: both require authenticated active member. No PII exposed (partner
-- entity data is non-sensitive per partner_entities RLS).
--
-- Additive RPC-only. Rollback: DROP FUNCTION on both.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.list_card_partners(p_board_item_id uuid)
RETURNS TABLE(
  link_id uuid,
  link_role text,
  link_notes text,
  linked_at timestamptz,
  linked_by_name text,
  partner_entity_id uuid,
  partner_name text,
  partner_entity_type text,
  partner_chapter text,
  partner_status text,
  partner_contact_name text
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT m.id INTO v_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_member_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    pc.id,
    pc.link_role,
    pc.notes,
    pc.created_at,
    cm.name,
    pe.id,
    pe.name,
    pe.entity_type,
    pe.chapter,
    pe.status,
    pe.contact_name
  FROM public.partner_cards pc
  JOIN public.partner_entities pe ON pe.id = pc.partner_entity_id
  LEFT JOIN public.members cm ON cm.id = pc.created_by
  WHERE pc.board_item_id = p_board_item_id
  ORDER BY pc.created_at DESC;
END;
$fn$;

COMMENT ON FUNCTION public.list_card_partners(uuid) IS
  'Inverse of list_partner_cards — returns all partner entities linked to a given board card. '
  'Authenticated member required. Issue #85 Onda A.';

GRANT EXECUTE ON FUNCTION public.list_card_partners(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.search_partner_cards(
  p_link_role text DEFAULT NULL,
  p_card_status text DEFAULT NULL,
  p_chapter text DEFAULT NULL,
  p_limit int DEFAULT 100
)
RETURNS TABLE(
  link_id uuid,
  link_role text,
  link_notes text,
  linked_at timestamptz,
  linked_by_name text,
  partner_entity_id uuid,
  partner_name text,
  partner_chapter text,
  partner_status text,
  board_item_id uuid,
  board_item_title text,
  board_item_status text,
  board_item_due_date date,
  board_item_assignee_name text,
  board_id uuid,
  board_name text
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
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
    pc.id,
    pc.link_role,
    pc.notes,
    pc.created_at,
    cm.name,
    pe.id,
    pe.name,
    pe.chapter,
    pe.status,
    bi.id,
    bi.title,
    bi.status,
    bi.due_date,
    am.name,
    bi.board_id,
    pb.board_name
  FROM public.partner_cards pc
  JOIN public.partner_entities pe ON pe.id = pc.partner_entity_id
  JOIN public.board_items bi ON bi.id = pc.board_item_id
  LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
  LEFT JOIN public.members am ON am.id = bi.assignee_id
  LEFT JOIN public.members cm ON cm.id = pc.created_by
  WHERE (p_link_role IS NULL OR pc.link_role = p_link_role)
    AND (p_card_status IS NULL OR bi.status = p_card_status)
    AND (p_chapter IS NULL OR pe.chapter = p_chapter)
  ORDER BY pc.created_at DESC
  LIMIT v_limit;
END;
$fn$;

COMMENT ON FUNCTION public.search_partner_cards(text, text, text, int) IS
  'Cross-partner admin view of partner↔card links with optional filters (link_role, '
  'card_status, chapter). Authenticated member required. Default 100 rows, cap 500. Issue #85 Onda A.';

GRANT EXECUTE ON FUNCTION public.search_partner_cards(text, text, text, int) TO authenticated;

NOTIFY pgrst, 'reload schema';
