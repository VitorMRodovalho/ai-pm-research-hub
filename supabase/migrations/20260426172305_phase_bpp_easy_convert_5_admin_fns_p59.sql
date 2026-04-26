-- Phase B'' easy-convert batch (p59) — 5 admin_* fns V3→V4
-- All use existing V4 actions (no new actions needed):
--   - admin_bulk_allocate_tribe   → manage_member
--   - admin_bulk_set_status        → manage_member
--   - admin_get_tribe_allocations  → manage_platform (admin tier, returns PII;
--                                    TODO: future view_pii + log_pii_access)
--   - admin_set_tribe_active       → manage_platform
--   - admin_deactivate_tribe       → manage_platform
--
-- Privilege expansion safety check (verified pre-apply):
--   V3 grant: 2 members (Vitor, Fabricio — superadmin)
--   V4 manage_platform: 2 (same)
--   V4 manage_member: 2 (same)
--   would_gain: [] / would_lose: []
--   ZERO expansion — clean conversion.
--
-- Pattern uniforme: top gate replaced; body unchanged.

-- ============================================================
-- 1. admin_bulk_allocate_tribe → manage_member
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_bulk_allocate_tribe(uuid[], integer);
CREATE OR REPLACE FUNCTION public.admin_bulk_allocate_tribe(
  p_member_ids uuid[],
  p_tribe_id integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor_id uuid;
  v_member_id uuid;
  v_old_tribe_id integer;
  v_count integer := 0;
BEGIN
  SELECT id INTO v_actor_id FROM public.members WHERE auth_id = auth.uid();
  IF v_actor_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_actor_id, 'manage_member') THEN
    RAISE EXCEPTION 'permission_denied: manage_member required';
  END IF;

  FOREACH v_member_id IN ARRAY p_member_ids LOOP
    SELECT tribe_id INTO v_old_tribe_id FROM public.members WHERE id = v_member_id;

    UPDATE public.members SET tribe_id = p_tribe_id WHERE id = v_member_id;

    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
    VALUES (v_actor_id, 'member.tribe_allocated_bulk', 'member', v_member_id,
      jsonb_build_object('field', 'tribe_id', 'old', v_old_tribe_id, 'new', p_tribe_id));

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'count', v_count);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_bulk_allocate_tribe(uuid[], integer) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_bulk_allocate_tribe(uuid[], integer) IS
  'Phase B'' V4 conversion (p59): manage_member gate via can_by_member. Was V3 (is_superadmin OR operational_role IN manager/deputy_manager).';

-- ============================================================
-- 2. admin_bulk_set_status → manage_member
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_bulk_set_status(uuid[], boolean);
CREATE OR REPLACE FUNCTION public.admin_bulk_set_status(
  p_member_ids uuid[],
  p_is_active boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor_id uuid;
  v_member_id uuid;
  v_old_status boolean;
  v_count integer := 0;
BEGIN
  SELECT id INTO v_actor_id FROM public.members WHERE auth_id = auth.uid();
  IF v_actor_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_actor_id, 'manage_member') THEN
    RAISE EXCEPTION 'permission_denied: manage_member required';
  END IF;

  FOREACH v_member_id IN ARRAY p_member_ids LOOP
    SELECT is_active INTO v_old_status FROM public.members WHERE id = v_member_id;

    IF v_old_status IS DISTINCT FROM p_is_active THEN
      UPDATE public.members SET is_active = p_is_active WHERE id = v_member_id;

      INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
      VALUES (v_actor_id, 'member.status_changed_bulk', 'member', v_member_id,
        jsonb_build_object('field', 'is_active', 'old', v_old_status, 'new', p_is_active));

      v_count := v_count + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'count', v_count);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_bulk_set_status(uuid[], boolean) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_bulk_set_status(uuid[], boolean) IS
  'Phase B'' V4 conversion (p59): manage_member gate via can_by_member. Was V3 (is_superadmin OR operational_role IN manager/deputy_manager).';

-- ============================================================
-- 3. admin_get_tribe_allocations → manage_platform (TODO future view_pii)
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_get_tribe_allocations();
CREATE OR REPLACE FUNCTION public.admin_get_tribe_allocations()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor_id uuid;
BEGIN
  SELECT id INTO v_actor_id FROM public.members WHERE auth_id = auth.uid();
  IF v_actor_id IS NULL THEN RETURN json_build_object('error', 'authentication_required'); END IF;
  IF NOT public.can_by_member(v_actor_id, 'manage_platform') THEN
    RETURN json_build_object('error', 'Acesso negado');
  END IF;

  -- TODO future: migrate to view_pii action + add log_pii_access call
  -- (returns email, phone — PII fields per LGPD Art. 5, I).

  RETURN (
    SELECT json_agg(row_to_json(t))
    FROM (
      SELECT
        m.id AS member_id, m.name, m.email, m.phone, m.photo_url,
        m.operational_role, m.designations,
        public.compute_legacy_role(m.operational_role, m.designations) AS role,
        public.compute_legacy_roles(m.operational_role, m.designations) AS roles,
        m.chapter, m.tribe_id AS fixed_tribe_id, m.current_cycle_active,
        ts.tribe_id AS selected_tribe_id, ts.selected_at
      FROM public.members m
      LEFT JOIN public.tribe_selections ts ON m.id = ts.member_id
      WHERE m.current_cycle_active = true
      ORDER BY ts.tribe_id ASC NULLS FIRST, m.name ASC
    ) t
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_get_tribe_allocations() FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_get_tribe_allocations() IS
  'Phase B'' V4 conversion (p59): manage_platform gate via can_by_member. Was V3 (is_superadmin OR manager/deputy_manager OR designation co_gp). TODO future: migrate to view_pii action + log_pii_access (returns email/phone PII).';

-- ============================================================
-- 4. admin_set_tribe_active → manage_platform
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_set_tribe_active(integer, boolean, text);
CREATE OR REPLACE FUNCTION public.admin_set_tribe_active(
  p_tribe_id integer,
  p_is_active boolean,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_tribe record;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'permission_denied: manage_platform required';
  END IF;

  SELECT * INTO v_tribe FROM public.tribes WHERE id = p_tribe_id;
  IF v_tribe IS NULL THEN
    RAISE EXCEPTION 'Tribe not found: %', p_tribe_id;
  END IF;

  UPDATE public.tribes
  SET is_active = p_is_active,
      updated_at = now(),
      updated_by = v_caller_id
  WHERE id = p_tribe_id;

  RETURN jsonb_build_object(
    'success', true,
    'tribe_id', p_tribe_id,
    'name', v_tribe.name,
    'is_active', p_is_active,
    'reason', p_reason
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_set_tribe_active(integer, boolean, text) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_set_tribe_active(integer, boolean, text) IS
  'Phase B'' V4 conversion (p59): manage_platform gate via can_by_member. Was V3 (is_superadmin OR manager/deputy_manager OR designation co_gp).';

-- ============================================================
-- 5. admin_deactivate_tribe → manage_platform
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_deactivate_tribe(integer, text);
CREATE OR REPLACE FUNCTION public.admin_deactivate_tribe(
  p_tribe_id integer,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_name text;
  v_tribe record;
  v_member record;
  v_cycle record;
  v_count integer := 0;
BEGIN
  SELECT id, name INTO v_caller_id, v_caller_name FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'permission_denied: manage_platform required';
  END IF;

  SELECT * INTO v_tribe FROM public.tribes WHERE id = p_tribe_id;
  IF v_tribe IS NULL THEN
    RAISE EXCEPTION 'Tribe not found: %', p_tribe_id;
  END IF;

  SELECT * INTO v_cycle FROM public.cycles WHERE is_current = true LIMIT 1;

  FOR v_member IN
    SELECT * FROM public.members
    WHERE tribe_id = p_tribe_id AND current_cycle_active = true
  LOOP
    INSERT INTO public.member_cycle_history (
      member_id, cycle_code, cycle_label, cycle_start, cycle_end,
      operational_role, designations, tribe_id, tribe_name,
      chapter, is_active, member_name_snapshot, notes
    ) VALUES (
      v_member.id,
      COALESCE(v_cycle.cycle_code, 'cycle_3'),
      COALESCE(v_cycle.cycle_label, 'Ciclo 3'),
      COALESCE(v_cycle.cycle_start, now()::text),
      now()::text,
      v_member.operational_role,
      v_member.designations,
      v_member.tribe_id,
      v_tribe.name,
      v_member.chapter,
      false,
      v_member.name,
      'TRIBE_DEACTIVATED: ' || v_tribe.name || ' closed. Reason: ' || p_reason || '. By: ' || v_caller_name
    );

    UPDATE public.members
    SET current_cycle_active = false,
        inactivated_at = now()
    WHERE id = v_member.id;

    v_count := v_count + 1;
  END LOOP;

  UPDATE public.tribes
  SET is_active = false,
      updated_at = now(),
      updated_by = v_caller_id
  WHERE id = p_tribe_id;

  RETURN jsonb_build_object(
    'success', true,
    'tribe', v_tribe.name,
    'members_affected', v_count,
    'reason', p_reason,
    'draft_email_subject', 'Comunicado: Encerramento da Tribo ' || v_tribe.name,
    'draft_email_body', 'Prezados membros da Tribo ' || v_tribe.name || E',\n\nInformamos que a tribo foi encerrada.\nMotivo: ' || p_reason || E'\n\nOs membros afetados serao realocados. Qualquer duvida, entrem em contato com a gerencia do projeto.\n\nAtenciosamente,\nGerencia do Projeto'
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_deactivate_tribe(integer, text) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_deactivate_tribe(integer, text) IS
  'Phase B'' V4 conversion (p59): manage_platform gate via can_by_member. Was V3 (is_superadmin OR manager/deputy_manager OR designation co_gp).';

NOTIFY pgrst, 'reload schema';
