-- Enforce selection_deadline_at server-side in select_tribe RPC.
-- Previously the deadline was only checked client-side in TribesSection.astro,
-- allowing direct API callers to bypass it.

DROP FUNCTION IF EXISTS public.select_tribe(integer);

CREATE OR REPLACE FUNCTION public.select_tribe(p_tribe_id integer)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid       uuid;
  v_member_id uuid;
  v_is_active boolean;
  v_op_role   text;
  v_deadline  timestamptz;
  v_slot_count integer;
  v_max_slots  integer := 6;
BEGIN
  -- Auth
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Não autenticado');
  END IF;

  -- Member lookup
  SELECT id, is_active, operational_role
    INTO v_member_id, v_is_active, v_op_role
    FROM members
   WHERE auth_id = v_uid;

  IF v_member_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Membro não encontrado');
  END IF;

  IF v_is_active IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('success', false, 'error', 'Membro inativo');
  END IF;

  IF v_op_role = 'tribe_leader' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Líderes de tribo são alocados diretamente');
  END IF;

  -- Deadline check: only block when a home_schedule row exists AND deadline has passed
  SELECT selection_deadline_at::timestamptz
    INTO v_deadline
    FROM home_schedule
   LIMIT 1;

  IF v_deadline IS NOT NULL AND now() > v_deadline THEN
    RETURN jsonb_build_object('success', false, 'error', 'Seleção encerrada');
  END IF;

  -- Tribe exists
  IF NOT EXISTS (SELECT 1 FROM tribes WHERE id = p_tribe_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Tribo não encontrada');
  END IF;

  -- Capacity: exclude caller's own row so switching tribes doesn't self-block
  SELECT count(*)
    INTO v_slot_count
    FROM tribe_selections
   WHERE tribe_id = p_tribe_id
     AND member_id IS DISTINCT FROM v_member_id;

  IF v_slot_count >= v_max_slots THEN
    RETURN jsonb_build_object('success', false, 'error', 'Tribo lotada');
  END IF;

  -- Upsert (one selection per member; unique on member_id)
  INSERT INTO tribe_selections (member_id, tribe_id, selected_at)
  VALUES (v_member_id, p_tribe_id, now())
  ON CONFLICT (member_id)
  DO UPDATE SET tribe_id    = EXCLUDED.tribe_id,
                selected_at = EXCLUDED.selected_at;

  RETURN jsonb_build_object('success', true, 'tribe_id', p_tribe_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.select_tribe(integer) TO authenticated;

-- ---------------------------------------------------------------------------
-- Extend tribe selection deadline from 2026-03-09T15:00 to 2026-03-14T23:59
-- Gives researchers until Friday to choose tribes.
-- ---------------------------------------------------------------------------
UPDATE home_schedule
   SET selection_deadline_at = '2026-03-14T23:59:59+00:00',
       updated_at            = now();
