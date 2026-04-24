-- =============================================================================
-- partner_cards — link table between partner_entities and board_items
-- =============================================================================
-- Issue: #85 Onda A — partnership CRM precisa dirigir task breakdown
-- Context: hoje partnerships vivem em partner_entities + partner_interactions,
--   mas trabalho real (deliverables, follow-ups, contratos) vive em board_items.
--   Sem tabela de link, admins perdem visibility sobre quais cards pertencem a
--   cada parceiro e vice-versa.
--
-- Schema:
--   - partner_cards (id, partner_entity_id, board_item_id, link_role, notes,
--     created_by, created_at) com UNIQUE (partner_entity_id, board_item_id)
--   - link_role enum: general, pipeline, deliverable, follow_up, contract, onboarding
--   - ON DELETE CASCADE em ambas FKs
--   - RLS: SELECT authenticated; writes via SECURITY DEFINER RPCs
--
-- 3 RPCs:
--   - link_partner_to_card(partner_id, board_item_id, link_role?, notes?)
--     UPSERT semantics (manage_partner)
--   - unlink_partner_from_card(partner_id, board_item_id)
--     DELETE (manage_partner)
--   - list_partner_cards(partner_id)
--     Read with joined board/item context
--
-- Additive. No data migration. Rollback: DROP TABLE + 3 functions.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.partner_cards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_entity_id uuid NOT NULL REFERENCES public.partner_entities(id) ON DELETE CASCADE,
  board_item_id uuid NOT NULL REFERENCES public.board_items(id) ON DELETE CASCADE,
  link_role text NOT NULL DEFAULT 'general',
  notes text,
  created_by uuid REFERENCES public.members(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT partner_cards_unique_link UNIQUE (partner_entity_id, board_item_id),
  CONSTRAINT partner_cards_link_role_check CHECK (link_role IN ('general','pipeline','deliverable','follow_up','contract','onboarding'))
);

CREATE INDEX IF NOT EXISTS idx_partner_cards_partner ON public.partner_cards(partner_entity_id);
CREATE INDEX IF NOT EXISTS idx_partner_cards_card ON public.partner_cards(board_item_id);

ALTER TABLE public.partner_cards ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "partner_cards_read_authenticated" ON public.partner_cards;
CREATE POLICY "partner_cards_read_authenticated" ON public.partner_cards
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "partner_cards_deny_direct_writes" ON public.partner_cards;
CREATE POLICY "partner_cards_deny_direct_writes" ON public.partner_cards
  FOR ALL TO authenticated USING (false) WITH CHECK (false);

COMMENT ON TABLE public.partner_cards IS
  'Link table: partner_entities ↔ board_items. Enables partner CRM to drive task breakdown. '
  'RLS: authenticated read; writes via SECURITY DEFINER RPCs (manage_partner). Issue #85 Onda A.';

-- RPC 1: link_partner_to_card -----------------------------------------------
CREATE OR REPLACE FUNCTION public.link_partner_to_card(
  p_partner_entity_id uuid,
  p_board_item_id uuid,
  p_link_role text DEFAULT 'general',
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_member record;
  v_partner_exists boolean;
  v_card_exists boolean;
  v_link_id uuid;
  v_was_update boolean := false;
BEGIN
  SELECT m.id, m.name INTO v_member
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_member.id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_member.id, 'manage_partner') THEN
    RAISE EXCEPTION 'Access denied: manage_partner required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT EXISTS(SELECT 1 FROM public.partner_entities WHERE id = p_partner_entity_id) INTO v_partner_exists;
  IF NOT v_partner_exists THEN
    RAISE EXCEPTION 'partner_entity not found (id=%)', p_partner_entity_id USING ERRCODE = 'no_data_found';
  END IF;

  SELECT EXISTS(SELECT 1 FROM public.board_items WHERE id = p_board_item_id) INTO v_card_exists;
  IF NOT v_card_exists THEN
    RAISE EXCEPTION 'board_item not found (id=%)', p_board_item_id USING ERRCODE = 'no_data_found';
  END IF;

  IF p_link_role NOT IN ('general','pipeline','deliverable','follow_up','contract','onboarding') THEN
    RAISE EXCEPTION 'invalid link_role: %. Must be: general|pipeline|deliverable|follow_up|contract|onboarding', p_link_role
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  INSERT INTO public.partner_cards (partner_entity_id, board_item_id, link_role, notes, created_by)
  VALUES (p_partner_entity_id, p_board_item_id, p_link_role, p_notes, v_member.id)
  ON CONFLICT (partner_entity_id, board_item_id) DO UPDATE
    SET link_role = EXCLUDED.link_role,
        notes = COALESCE(EXCLUDED.notes, public.partner_cards.notes),
        updated_at = now()
  RETURNING id, (xmax <> 0) INTO v_link_id, v_was_update;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    v_member.id,
    CASE WHEN v_was_update THEN 'partner_card.updated' ELSE 'partner_card.linked' END,
    'partner_card', v_link_id,
    jsonb_build_object(
      'partner_entity_id', p_partner_entity_id,
      'board_item_id', p_board_item_id,
      'link_role', p_link_role
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'link_id', v_link_id,
    'was_update', v_was_update,
    'partner_entity_id', p_partner_entity_id,
    'board_item_id', p_board_item_id,
    'link_role', p_link_role
  );
END;
$fn$;

COMMENT ON FUNCTION public.link_partner_to_card(uuid, uuid, text, text) IS
  'Link a partner to a board card. UPSERT semantics — if link exists, updates link_role + notes. '
  'Requires manage_partner authority. Emits admin_audit_log. Issue #85 Onda A.';

GRANT EXECUTE ON FUNCTION public.link_partner_to_card(uuid, uuid, text, text) TO authenticated;

-- RPC 2: unlink_partner_from_card -------------------------------------------
CREATE OR REPLACE FUNCTION public.unlink_partner_from_card(
  p_partner_entity_id uuid,
  p_board_item_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_member record;
  v_deleted_id uuid;
BEGIN
  SELECT m.id, m.name INTO v_member
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_member.id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_member.id, 'manage_partner') THEN
    RAISE EXCEPTION 'Access denied: manage_partner required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  DELETE FROM public.partner_cards
  WHERE partner_entity_id = p_partner_entity_id AND board_item_id = p_board_item_id
  RETURNING id INTO v_deleted_id;

  IF v_deleted_id IS NOT NULL THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
    VALUES (
      v_member.id, 'partner_card.unlinked', 'partner_card', v_deleted_id,
      jsonb_build_object('partner_entity_id', p_partner_entity_id, 'board_item_id', p_board_item_id)
    );
  END IF;

  RETURN jsonb_build_object(
    'success', (v_deleted_id IS NOT NULL),
    'deleted_id', v_deleted_id
  );
END;
$fn$;

COMMENT ON FUNCTION public.unlink_partner_from_card(uuid, uuid) IS
  'Remove a partner↔card link. Requires manage_partner authority. Emits admin_audit_log. Issue #85 Onda A.';

GRANT EXECUTE ON FUNCTION public.unlink_partner_from_card(uuid, uuid) TO authenticated;

-- RPC 3: list_partner_cards -------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_partner_cards(p_partner_entity_id uuid)
RETURNS TABLE(
  link_id uuid,
  link_role text,
  link_notes text,
  linked_at timestamptz,
  linked_by_name text,
  board_item_id uuid,
  board_item_title text,
  board_item_status text,
  board_item_due_date date,
  board_item_assignee_name text,
  board_id uuid,
  board_name text,
  partner_entity_id uuid,
  partner_name text
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
    bi.id,
    bi.title,
    bi.status,
    bi.due_date,
    am.name,
    bi.board_id,
    pb.board_name,
    pe.id,
    pe.name
  FROM public.partner_cards pc
  JOIN public.partner_entities pe ON pe.id = pc.partner_entity_id
  JOIN public.board_items bi ON bi.id = pc.board_item_id
  LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
  LEFT JOIN public.members am ON am.id = bi.assignee_id
  LEFT JOIN public.members cm ON cm.id = pc.created_by
  WHERE pc.partner_entity_id = p_partner_entity_id
  ORDER BY pc.created_at DESC;
END;
$fn$;

COMMENT ON FUNCTION public.list_partner_cards(uuid) IS
  'List all board cards linked to a partner entity. Joins board_items + project_boards + '
  'members (assignee + linker). Requires authenticated member. Issue #85 Onda A.';

GRANT EXECUTE ON FUNCTION public.list_partner_cards(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
