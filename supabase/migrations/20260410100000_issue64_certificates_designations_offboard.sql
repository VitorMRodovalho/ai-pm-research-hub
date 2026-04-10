-- ============================================================
-- Issue #64: Certificates — designation auto-remove, filter volunteer_agreement,
-- atomic offboard_member RPC, audit trail via member_role_changes
-- ============================================================

-- ============================================================
-- 1. Filter volunteer_agreement from certificates RPCs
-- ============================================================

-- 1a. get_my_certificates: exclude volunteer_agreement (has its own page)
DROP FUNCTION IF EXISTS get_my_certificates();
CREATE OR REPLACE FUNCTION get_my_certificates()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
DECLARE v_member_id uuid; result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', c.id, 'type', c.type, 'title', c.title, 'cycle', c.cycle, 'status', c.status,
    'verification_code', c.verification_code, 'issued_at', c.issued_at,
    'issued_by_name', ib.name, 'counter_signed_by_name', cs.name,
    'counter_signed_at', c.counter_signed_at, 'period_start', c.period_start,
    'period_end', c.period_end, 'language', c.language,
    'has_counter_signature', c.counter_signed_by IS NOT NULL, 'signature_hash', c.signature_hash,
    'function_role', c.function_role
  ) ORDER BY c.issued_at DESC), '[]'::jsonb) INTO result
  FROM certificates c
  LEFT JOIN members ib ON ib.id = c.issued_by
  LEFT JOIN members cs ON cs.id = c.counter_signed_by
  WHERE c.member_id = v_member_id
    AND COALESCE(c.status, 'issued') != 'revoked'
    AND c.type != 'volunteer_agreement';  -- FIX: volunteer agreements have their own page
  RETURN result;
END;
$$;
GRANT EXECUTE ON FUNCTION get_my_certificates() TO authenticated;

-- 1b. get_pending_countersign: keep chapter_board scope but exclude volunteer_agreement
DROP FUNCTION IF EXISTS get_pending_countersign();
CREATE OR REPLACE FUNCTION get_pending_countersign()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_member_id uuid;
  v_member_chapter text;
  v_is_manager boolean;
  v_is_chapter_board boolean;
  result jsonb;
BEGIN
  SELECT m.id, m.chapter,
    (m.operational_role IN ('manager') OR m.is_superadmin = true),
    ('chapter_board' = ANY(m.designations))
  INTO v_member_id, v_member_chapter, v_is_manager, v_is_chapter_board
  FROM members m WHERE m.auth_id = auth.uid();

  IF NOT COALESCE(v_is_manager, false) AND NOT COALESCE(v_is_chapter_board, false) THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', c.id, 'type', c.type, 'title', c.title, 'member_name', m.name, 'member_email', m.email,
    'member_role', m.operational_role, 'member_chapter', m.chapter, 'tribe_name', t.name, 'cycle', c.cycle,
    'verification_code', c.verification_code, 'issued_at', c.issued_at,
    'signature_hash', c.signature_hash
  ) ORDER BY c.issued_at DESC), '[]'::jsonb) INTO result
  FROM certificates c
  JOIN members m ON m.id = c.member_id
  LEFT JOIN tribes t ON t.id = m.tribe_id
  WHERE c.counter_signed_by IS NULL
    AND COALESCE(c.status, 'issued') = 'issued'
    AND c.type != 'volunteer_agreement'  -- FIX: volunteer agreements have their own page/workflow
    AND (COALESCE(v_is_manager, false) OR m.chapter = v_member_chapter);

  RETURN result;
END;
$$;
GRANT EXECUTE ON FUNCTION get_pending_countersign() TO authenticated;

-- ============================================================
-- 2. Trigger: auto-remove designation when contribution cert is issued
-- ============================================================

CREATE OR REPLACE FUNCTION _auto_remove_designation_on_cert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_desig_to_remove text;
  v_old_designations text[];
  v_new_designations text[];
BEGIN
  -- Only process contribution certificates with function_role set
  IF NEW.type != 'contribution' OR NEW.function_role IS NULL THEN
    RETURN NEW;
  END IF;

  -- Map function_role → designation to remove
  v_desig_to_remove := CASE
    WHEN NEW.function_role ILIKE '%comunica%'    THEN 'comms_member'
    WHEN NEW.function_role ILIKE '%curador%'      THEN 'curator'
    WHEN NEW.function_role ILIKE '%embaixador%'   THEN 'ambassador'
    WHEN NEW.function_role ILIKE '%chapter%board%' THEN 'chapter_board'
    ELSE NULL
  END;

  IF v_desig_to_remove IS NULL THEN
    RETURN NEW;
  END IF;

  -- Fetch current designations
  SELECT designations INTO v_old_designations
  FROM members WHERE id = NEW.member_id;

  IF v_old_designations IS NULL OR NOT (v_desig_to_remove = ANY(v_old_designations)) THEN
    RETURN NEW;  -- Nothing to remove
  END IF;

  v_new_designations := array_remove(v_old_designations, v_desig_to_remove);

  -- Apply removal
  UPDATE members
  SET designations = v_new_designations, updated_at = now()
  WHERE id = NEW.member_id;

  -- Audit trail
  INSERT INTO member_role_changes (
    member_id, change_type, field_name,
    old_value, new_value,
    effective_date, reason,
    reference_doc_id, authorized_by, executed_by
  ) VALUES (
    NEW.member_id,
    'designation_removed',
    'designations',
    to_jsonb(v_old_designations),
    to_jsonb(v_new_designations),
    NEW.issued_at::date,
    'Certificado de contribuição emitido: ' || NEW.function_role,
    NEW.verification_code,
    NEW.issued_by,
    NEW.issued_by
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_remove_designation_on_cert ON certificates;
CREATE TRIGGER trg_auto_remove_designation_on_cert
AFTER INSERT ON certificates
FOR EACH ROW
EXECUTE FUNCTION _auto_remove_designation_on_cert();

-- ============================================================
-- 3. Atomic offboard_member RPC — updates all 5 fields + logs
-- ============================================================
CREATE OR REPLACE FUNCTION offboard_member(
  p_member_id uuid,
  p_new_status text,     -- 'observer' | 'alumni'
  p_reason text,
  p_effective_date date DEFAULT NULL  -- defaults to today
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_is_admin boolean;
  v_caller_role text;
  v_old_status text;
  v_old_role text;
  v_new_role text;
  v_effective timestamptz;
BEGIN
  -- Auth
  SELECT id, is_superadmin, operational_role INTO v_caller_id, v_is_admin, v_caller_role
  FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (v_is_admin = true OR v_caller_role IN ('manager', 'deputy_manager')) THEN
    RAISE EXCEPTION 'Unauthorized: only manager, deputy_manager or superadmin can offboard members';
  END IF;

  -- Validate target status
  IF p_new_status NOT IN ('observer', 'alumni') THEN
    RAISE EXCEPTION 'Invalid status. Must be observer or alumni.';
  END IF;

  -- Capture current state
  SELECT member_status, operational_role INTO v_old_status, v_old_role
  FROM members WHERE id = p_member_id;
  IF v_old_status IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;

  -- Derive new operational_role
  v_new_role := CASE WHEN p_new_status = 'alumni' THEN 'alumni' ELSE 'observer' END;
  v_effective := COALESCE(p_effective_date::timestamptz, now());

  -- Atomic update of all 5 fields
  UPDATE members SET
    member_status = p_new_status,
    operational_role = v_new_role,
    is_active = false,
    offboarded_at = v_effective,
    status_change_reason = p_reason,
    updated_at = now()
  WHERE id = p_member_id;

  -- Audit trail: 2 entries (status + role)
  INSERT INTO member_role_changes (
    member_id, change_type, field_name,
    old_value, new_value,
    effective_date, reason,
    authorized_by, executed_by
  ) VALUES
    (p_member_id, 'status_changed', 'member_status',
     to_jsonb(v_old_status), to_jsonb(p_new_status),
     v_effective::date, p_reason, v_caller_id, v_caller_id),
    (p_member_id, 'role_changed', 'operational_role',
     to_jsonb(v_old_role), to_jsonb(v_new_role),
     v_effective::date, p_reason, v_caller_id, v_caller_id);

  RETURN jsonb_build_object(
    'success', true,
    'member_id', p_member_id,
    'new_status', p_new_status,
    'new_role', v_new_role,
    'effective_date', v_effective::date
  );
END;
$$;

GRANT EXECUTE ON FUNCTION offboard_member(uuid, text, text, date) TO authenticated;

NOTIFY pgrst, 'reload schema';
