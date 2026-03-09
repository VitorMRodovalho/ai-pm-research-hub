-- ═══════════════════════════════════════════════════════════════
-- Migration: deliverable CRUD RPCs — upsert with auth check
-- ═══════════════════════════════════════════════════════════════

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
  -- Auth: caller must be superadmin or tribe_leader of that tribe
  SELECT id, is_superadmin, operational_role, tribe_id
    INTO v_member
    FROM public.members
   WHERE auth_id = auth.uid()
   LIMIT 1;

  IF v_member IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  IF NOT (
    v_member.is_superadmin = true
    OR (v_member.operational_role = 'tribe_leader' AND v_member.tribe_id = p_tribe_id)
  ) THEN
    RAISE EXCEPTION 'Unauthorized: must be superadmin or tribe_leader of this tribe';
  END IF;

  IF p_title IS NULL OR p_title = '' THEN
    RAISE EXCEPTION 'Title is required';
  END IF;

  IF p_id IS NOT NULL THEN
    -- UPDATE existing deliverable
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
    -- INSERT new deliverable
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
