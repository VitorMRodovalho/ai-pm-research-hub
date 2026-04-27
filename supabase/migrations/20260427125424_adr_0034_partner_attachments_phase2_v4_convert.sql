-- ADR-0034 (Accepted, p66): partner attachments V4 conversion (Phase 2 — 4 fns)
-- See docs/adr/ADR-0034-partner-attachments-v4-conversion.md
--
-- PM ratified Q1-Q4 (2026-04-26 p66): SIM / Path D / SIM / p66
--
-- Privilege expansion (verified pre-apply):
--   Group W2 (writers): legacy=4 → v4=10
--     would_gain = 7 admin/governance (Ana, Felipe, Francisca, Ivan, Márcio, Matheus, Rogério)
--     would_lose = [Sarah] (curator drift, same precedent as ADR-0030/0031/0033)
--   Group R2 (readers, Path D drop chapter scope): legacy_org=10 → v4=10
--     would_gain = 7 admin/governance
--     would_lose = [Sarah curator + 6 tribe_leaders] (drift correction)
--
-- Drift signals #5 #6 closed: V3 chapter_match using operational_role IN
-- ('sponsor', 'chapter_liaison') (column-based check) is removed entirely.
-- V4 manage_partner ladder is the single source of truth — sponsor/chapter_board
-- liaisons access via engagement, not designation.

-- ============================================================
-- 1. add_partner_attachment → reuse manage_partner
-- ============================================================
CREATE OR REPLACE FUNCTION public.add_partner_attachment(
  p_entity_id uuid DEFAULT NULL::uuid,
  p_interaction_id uuid DEFAULT NULL::uuid,
  p_file_name text DEFAULT NULL::text,
  p_file_url text DEFAULT NULL::text,
  p_file_size integer DEFAULT NULL::integer,
  p_file_type text DEFAULT NULL::text,
  p_description text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- V4 gate (Path A reuse manage_partner — Opção B precedent)
  IF NOT public.can_by_member(v_caller_id, 'manage_partner') THEN
    RETURN jsonb_build_object('error', 'Only governance roles can upload partnership attachments');
  END IF;

  IF p_entity_id IS NULL AND p_interaction_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Must link to entity or interaction');
  END IF;

  INSERT INTO public.partner_attachments (
    partner_entity_id, partner_interaction_id, file_name, file_url,
    file_size, file_type, description, uploaded_by
  ) VALUES (
    p_entity_id, p_interaction_id, p_file_name, p_file_url,
    p_file_size, p_file_type, p_description, v_caller_id
  ) RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'id', v_id);
END;
$$;
COMMENT ON FUNCTION public.add_partner_attachment(uuid, uuid, text, text, integer, text, text) IS
  'Phase B'' V4 conversion (ADR-0034 Phase 2, p66): Opção B reuse manage_partner via can_by_member. Was V3 (SA OR manager/deputy OR curator designation).';

-- ============================================================
-- 2. delete_partner_attachment → reuse manage_partner
-- ============================================================
CREATE OR REPLACE FUNCTION public.delete_partner_attachment(p_attachment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_attachment record;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- V4 gate (Path A reuse manage_partner)
  IF NOT public.can_by_member(v_caller_id, 'manage_partner') THEN
    RETURN jsonb_build_object('error', 'Only governance roles can delete attachments');
  END IF;

  SELECT * INTO v_attachment FROM public.partner_attachments WHERE id = p_attachment_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Attachment not found');
  END IF;

  DELETE FROM public.partner_attachments WHERE id = p_attachment_id;

  RETURN jsonb_build_object('ok', true, 'deleted_file', v_attachment.file_name);
END;
$$;
COMMENT ON FUNCTION public.delete_partner_attachment(uuid) IS
  'Phase B'' V4 conversion (ADR-0034 Phase 2, p66): Opção B reuse manage_partner via can_by_member. Was V3 (SA OR manager/deputy OR curator designation).';

-- ============================================================
-- 3. get_partner_entity_attachments → reuse manage_partner (Path D drop chapter scope)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_partner_entity_attachments(p_entity_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  -- V4 gate (Path D — drop V3 chapter_match, drift signals #5 #6 closed)
  IF NOT public.can_by_member(v_caller_id, 'manage_partner') THEN
    RETURN '[]'::jsonb;
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', pa.id,
      'file_name', pa.file_name,
      'file_url', pa.file_url,
      'file_size', pa.file_size,
      'file_type', pa.file_type,
      'description', pa.description,
      'uploaded_by_name', m.name,
      'created_at', pa.created_at
    ) ORDER BY pa.created_at DESC)
    FROM public.partner_attachments pa
    JOIN public.members m ON m.id = pa.uploaded_by
    WHERE pa.partner_entity_id = p_entity_id
  ), '[]'::jsonb);
END;
$$;
COMMENT ON FUNCTION public.get_partner_entity_attachments(uuid) IS
  'Phase B'' V4 conversion (ADR-0034 Phase 2, p66): Path D reuse manage_partner via can_by_member. Was V3 (4-tier visibility GP/Curator + Leader + own-chapter sponsor/chapter_liaison). Drift signals #5 #6 closed (V3 operational_role-based chapter_match removed).';

-- ============================================================
-- 4. get_partner_interaction_attachments → reuse manage_partner (Path D)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_partner_interaction_attachments(p_interaction_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  -- V4 gate (Path D — drop V3 chapter_match, drift signals #5 #6 closed)
  IF NOT public.can_by_member(v_caller_id, 'manage_partner') THEN
    RETURN '[]'::jsonb;
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', pa.id,
      'file_name', pa.file_name,
      'file_url', pa.file_url,
      'file_size', pa.file_size,
      'file_type', pa.file_type,
      'description', pa.description,
      'uploaded_by_name', m.name,
      'created_at', pa.created_at
    ) ORDER BY pa.created_at DESC)
    FROM public.partner_attachments pa
    JOIN public.members m ON m.id = pa.uploaded_by
    WHERE pa.partner_interaction_id = p_interaction_id
  ), '[]'::jsonb);
END;
$$;
COMMENT ON FUNCTION public.get_partner_interaction_attachments(uuid) IS
  'Phase B'' V4 conversion (ADR-0034 Phase 2, p66): Path D reuse manage_partner via can_by_member. Was V3 (4-tier visibility GP/Curator + Leader + own-chapter sponsor/chapter_liaison). Drift signals #5 #6 closed (V3 operational_role-based chapter_match removed).';

NOTIFY pgrst, 'reload schema';
