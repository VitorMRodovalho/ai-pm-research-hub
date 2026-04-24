-- Migration: LGPD — add log_pii_access_batch() helper
-- Issue: #85 Onda C — PII access logging instrumentation
-- Context: log_pii_access(uuid, text[], text, text) single-target helper exists.
--          List-reader RPCs (admin_list_members_with_pii, get_tribe_member_contacts,
--          get_initiative_member_contacts, admin_preview_campaign) access N members per call.
--          Add batch variant to avoid duplicated inline INSERT patterns and keep logging consistent.
-- Invariant preserved: helper skips accessor's own row (no self-access noise), same as single-target version.
-- Rollback: DROP FUNCTION public.log_pii_access_batch(uuid[], text[], text, text);

CREATE OR REPLACE FUNCTION public.log_pii_access_batch(
  p_target_member_ids uuid[],
  p_fields text[],
  p_context text,
  p_reason text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_accessor_id uuid;
  v_count integer;
BEGIN
  SELECT id INTO v_accessor_id FROM public.members WHERE auth_id = auth.uid();
  IF v_accessor_id IS NULL
     OR p_target_member_ids IS NULL
     OR cardinality(p_target_member_ids) = 0 THEN
    RETURN 0;
  END IF;

  INSERT INTO public.pii_access_log (accessor_id, target_member_id, fields_accessed, context, reason)
  SELECT v_accessor_id, tid, p_fields, p_context, p_reason
  FROM unnest(p_target_member_ids) AS tid
  WHERE tid IS NOT NULL
    AND tid <> v_accessor_id;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.log_pii_access_batch(uuid[], text[], text, text) IS
  'LGPD Art. 37 — batch variant of log_pii_access for list readers. Skips self-access. Returns insert count.';

REVOKE ALL ON FUNCTION public.log_pii_access_batch(uuid[], text[], text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.log_pii_access_batch(uuid[], text[], text, text) TO authenticated, service_role;
