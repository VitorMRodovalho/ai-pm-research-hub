-- ═══════════════════════════════════════════════════════════════
-- Migration: R1 + R3 — Admin global access + time-lock bypass
-- R1: PM (manager), Deputy PM (deputy_manager) get write access
--     to tribe_deliverables for any tribe (same as superadmin).
-- R3: select_tribe RPC bypasses deadline for high management.
-- ═══════════════════════════════════════════════════════════════

-- ─── R1: Update tribe_deliverables write policy ───
-- Drop and recreate to include manager/deputy_manager
DROP POLICY IF EXISTS "tribe_deliverables_write" ON public.tribe_deliverables;

CREATE POLICY "tribe_deliverables_write" ON public.tribe_deliverables
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.members
      WHERE auth_id = auth.uid()
        AND (
          is_superadmin = true
          OR operational_role IN ('manager', 'deputy_manager')
          OR (
            operational_role = 'tribe_leader'
            AND tribe_id = tribe_deliverables.tribe_id
          )
        )
    )
  );

-- ─── R1: Update upsert_tribe_deliverable RPC auth check ───
CREATE OR REPLACE FUNCTION public.upsert_tribe_deliverable(
  p_id                UUID     DEFAULT NULL,
  p_tribe_id          INT      DEFAULT NULL,
  p_cycle_code        TEXT     DEFAULT NULL,
  p_title             TEXT     DEFAULT NULL,
  p_description       TEXT     DEFAULT NULL,
  p_status            TEXT     DEFAULT 'planned',
  p_assigned_member_id UUID    DEFAULT NULL,
  p_artifact_id       UUID     DEFAULT NULL,
  p_due_date          DATE     DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member  RECORD;
  v_result  public.tribe_deliverables%ROWTYPE;
BEGIN
  SELECT id, is_superadmin, operational_role, tribe_id
    INTO v_member
    FROM public.members
   WHERE auth_id = auth.uid()
   LIMIT 1;

  IF v_member IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- R1: superadmin, manager, deputy_manager can edit any tribe
  IF NOT (
    v_member.is_superadmin = true
    OR v_member.operational_role IN ('manager', 'deputy_manager')
    OR (v_member.operational_role = 'tribe_leader' AND v_member.tribe_id = p_tribe_id)
  ) THEN
    RAISE EXCEPTION 'Unauthorized: must be admin, manager, or tribe_leader of this tribe';
  END IF;

  IF p_title IS NULL OR p_title = '' THEN
    RAISE EXCEPTION 'Title is required';
  END IF;

  IF p_id IS NOT NULL THEN
    UPDATE public.tribe_deliverables
       SET title              = COALESCE(p_title, title),
           description        = p_description,
           status             = COALESCE(p_status, status),
           assigned_member_id = p_assigned_member_id,
           artifact_id        = p_artifact_id,
           due_date           = p_due_date
     WHERE id = p_id
       AND tribe_id = p_tribe_id
    RETURNING * INTO v_result;

    IF v_result IS NULL THEN
      RAISE EXCEPTION 'Deliverable not found or tribe mismatch';
    END IF;
  ELSE
    INSERT INTO public.tribe_deliverables
      (tribe_id, cycle_code, title, description, status, assigned_member_id, artifact_id, due_date)
    VALUES
      (p_tribe_id, p_cycle_code, p_title, p_description, p_status, p_assigned_member_id, p_artifact_id, p_due_date)
    RETURNING * INTO v_result;
  END IF;

  RETURN to_jsonb(v_result);
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_tribe_deliverable(UUID, INT, TEXT, TEXT, TEXT, TEXT, UUID, UUID, DATE)
  TO authenticated;

-- ─── R3: Update select_tribe RPC with deadline bypass for high management ───
DROP FUNCTION IF EXISTS public.select_tribe(integer);

CREATE OR REPLACE FUNCTION public.select_tribe(p_tribe_id integer)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid        uuid;
  v_member_id  uuid;
  v_is_active  boolean;
  v_op_role    text;
  v_is_sa      boolean;
  v_deadline   timestamptz;
  v_slot_count integer;
  v_max_slots  integer := 6;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Não autenticado');
  END IF;

  SELECT id, is_active, operational_role, is_superadmin
    INTO v_member_id, v_is_active, v_op_role, v_is_sa
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

  SELECT selection_deadline_at::timestamptz
    INTO v_deadline
    FROM home_schedule
   LIMIT 1;

  -- R3: bypass deadline for superadmin, manager, deputy_manager
  IF v_deadline IS NOT NULL AND now() > v_deadline THEN
    IF NOT (v_is_sa = true OR v_op_role IN ('manager', 'deputy_manager')) THEN
      RETURN jsonb_build_object('success', false, 'error', 'Seleção encerrada');
    END IF;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM tribes WHERE id = p_tribe_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Tribo não encontrada');
  END IF;

  SELECT count(*)
    INTO v_slot_count
    FROM tribe_selections
   WHERE tribe_id = p_tribe_id
     AND member_id IS DISTINCT FROM v_member_id;

  IF v_slot_count >= v_max_slots THEN
    RETURN jsonb_build_object('success', false, 'error', 'Tribo lotada');
  END IF;

  INSERT INTO tribe_selections (member_id, tribe_id, selected_at)
  VALUES (v_member_id, p_tribe_id, now())
  ON CONFLICT (member_id)
  DO UPDATE SET tribe_id    = EXCLUDED.tribe_id,
                selected_at = EXCLUDED.selected_at;

  RETURN jsonb_build_object('success', true, 'tribe_id', p_tribe_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.select_tribe(integer) TO authenticated;
