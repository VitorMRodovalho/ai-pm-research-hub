-- Phase B'' batch 15.2: select_tribe V3 hardcoded deadline bypass → V4 can_by_member('manage_platform')
-- V3 bypass: v_is_sa OR v_op_role IN ('manager', 'deputy_manager')
-- V4 mapping: manage_platform covers manager/deputy_manager/co_gp + is_superadmin (via can() short-circuit)
-- Impact: V3=2 active members, V4=2 active members (clean match; +co_gp is admin-tier consistent)
CREATE OR REPLACE FUNCTION public.select_tribe(p_tribe_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid        uuid;
  v_member_id  uuid;
  v_is_active  boolean;
  v_op_role    text;
  v_deadline   timestamptz;
  v_slot_count integer;
  v_max_slots  integer := 6;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Não autenticado');
  END IF;

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

  SELECT selection_deadline_at::timestamptz
    INTO v_deadline
    FROM home_schedule
   LIMIT 1;

  -- R3 V4: bypass deadline for manage_platform holders (was: superadmin/manager/deputy_manager)
  IF v_deadline IS NOT NULL AND now() > v_deadline THEN
    IF NOT public.can_by_member(v_member_id, 'manage_platform'::text) THEN
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
$function$;
