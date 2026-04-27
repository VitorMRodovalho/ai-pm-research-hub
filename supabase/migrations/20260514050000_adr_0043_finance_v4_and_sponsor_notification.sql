-- ============================================================
-- ADR-0043: create_cost_entry + create_revenue_entry V3→V4 + sponsor finance notification safeguard
-- Section A: V3→V4 conversion (manage_finance catalog action)
-- Section B: New notification type sponsor_finance_entry_logged + _delivery_mode_for update
-- Section C: Trigger fn notify_sponsor_finance_entry + 2 triggers (cost + revenue)
-- Section D: Enhanced audit_log entry with engagement context
-- Cross-references: ADR-0007, ADR-0011, ADR-0022 (notification catalog), ADR-0025 (manage_finance)
-- Rollback: DROP triggers + DROP fn + revert create_cost/revenue_entry to prior bodies
-- ============================================================

-- ── Section A: V3→V4 conversion ────────────────────────────
-- create_cost_entry — V3 (manager/deputy_manager/superadmin) → V4 manage_finance
CREATE OR REPLACE FUNCTION public.create_cost_entry(
  p_category_name text,
  p_description text,
  p_amount_brl numeric,
  p_date date,
  p_paid_by text DEFAULT 'zero_cost'::text,
  p_event_id uuid DEFAULT NULL::uuid,
  p_submission_id uuid DEFAULT NULL::uuid,
  p_notes text DEFAULT NULL::text
) RETURNS uuid
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_id uuid;
  v_caller_id uuid;
  v_member_id uuid;
  v_category_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = v_caller_id LIMIT 1;
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  -- ADR-0043: V4 catalog source-of-truth (manage_finance) — sponsor × sponsor + volunteer × {manager, deputy_manager, co_gp}
  IF NOT public.can_by_member(v_member_id, 'manage_finance') THEN
    RAISE EXCEPTION 'Requires manage_finance permission';
  END IF;

  SELECT id INTO v_category_id FROM public.cost_categories WHERE name = p_category_name;
  IF v_category_id IS NULL THEN RAISE EXCEPTION 'Invalid cost category: %', p_category_name; END IF;

  INSERT INTO public.cost_entries (category_id, description, amount_brl, date, paid_by, event_id, submission_id, notes, created_by)
  VALUES (v_category_id, p_description, p_amount_brl, p_date, p_paid_by, p_event_id, p_submission_id, p_notes, v_member_id)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

-- create_revenue_entry — same V3→V4
CREATE OR REPLACE FUNCTION public.create_revenue_entry(
  p_category_name text,
  p_description text,
  p_date date,
  p_value_type text DEFAULT 'monetary'::text,
  p_amount_brl numeric DEFAULT NULL::numeric,
  p_notes text DEFAULT NULL::text
) RETURNS uuid
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_id uuid;
  v_caller_id uuid;
  v_member_id uuid;
  v_category_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = v_caller_id LIMIT 1;
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  -- ADR-0043: V4 catalog source-of-truth (manage_finance)
  IF NOT public.can_by_member(v_member_id, 'manage_finance') THEN
    RAISE EXCEPTION 'Requires manage_finance permission';
  END IF;

  SELECT id INTO v_category_id FROM public.revenue_categories WHERE name = p_category_name;
  IF v_category_id IS NULL THEN RAISE EXCEPTION 'Invalid revenue category: %', p_category_name; END IF;

  INSERT INTO public.revenue_entries (category_id, description, value_type, amount_brl, date, notes, created_by)
  VALUES (v_category_id, p_description, p_value_type, p_amount_brl, p_date, p_notes, v_member_id)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

-- ── Section B: notification catalog extension ──────────────
-- Adds sponsor_finance_entry_logged → transactional_immediate (governance visibility critical)
CREATE OR REPLACE FUNCTION public._delivery_mode_for(p_type text)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE PARALLEL SAFE
  SET search_path TO ''
AS $function$
  SELECT CASE p_type
    WHEN 'volunteer_agreement_signed'    THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_pending'  THEN 'transactional_immediate'
    WHEN 'system_alert'                  THEN 'transactional_immediate'
    WHEN 'certificate_ready'             THEN 'transactional_immediate'
    WHEN 'member_offboarded'             THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_advanced'    THEN 'transactional_immediate'
    WHEN 'ip_ratification_chain_approved'   THEN 'transactional_immediate'
    WHEN 'ip_ratification_awaiting_members' THEN 'transactional_immediate'
    WHEN 'webinar_status_confirmed'      THEN 'transactional_immediate'
    WHEN 'webinar_status_completed'      THEN 'transactional_immediate'
    WHEN 'webinar_status_cancelled'      THEN 'transactional_immediate'
    WHEN 'weekly_card_digest_member'     THEN 'transactional_immediate'
    WHEN 'governance_cr_new'             THEN 'transactional_immediate'
    WHEN 'governance_cr_vote'            THEN 'transactional_immediate'
    WHEN 'governance_cr_approved'        THEN 'transactional_immediate'
    WHEN 'sponsor_finance_entry_logged'  THEN 'transactional_immediate'
    WHEN 'attendance_detractor'          THEN 'suppress'
    WHEN 'info'                          THEN 'suppress'
    WHEN 'system'                        THEN 'suppress'
    ELSE 'digest_weekly'
  END;
$function$;

-- ── Section C: trigger fn notify_sponsor_finance_entry ─────
-- Detects when finance entry created_by has sponsor × sponsor engagement (non-volunteer)
-- and broadcasts notification to all manage_platform holders.
-- Also writes admin_audit_log entry with enhanced context.
CREATE OR REPLACE FUNCTION public.notify_sponsor_finance_entry()
  RETURNS trigger
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_actor_member members%rowtype;
  v_actor_person_id uuid;
  v_is_sponsor boolean;
  v_is_volunteer boolean;
  v_chapter_board_aff text[];
  v_admin_member uuid;
  v_kind text;
  v_amount numeric;
  v_description text;
  v_source_type text;
  v_link text;
  v_audit_changes jsonb;
BEGIN
  IF TG_TABLE_NAME = 'cost_entries' THEN
    v_kind := 'cost';
    v_amount := NEW.amount_brl;
    v_description := NEW.description;
    v_source_type := 'cost_entry';
    v_link := '/admin/sustainability/cost?id=' || NEW.id::text;
  ELSE
    v_kind := 'revenue';
    v_amount := NEW.amount_brl;
    v_description := NEW.description;
    v_source_type := 'revenue_entry';
    v_link := '/admin/sustainability/revenue?id=' || NEW.id::text;
  END IF;

  -- Skip if no created_by (system-generated entry)
  IF NEW.created_by IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_actor_member FROM public.members WHERE id = NEW.created_by;
  IF v_actor_member IS NULL THEN RETURN NEW; END IF;

  SELECT id INTO v_actor_person_id FROM public.persons WHERE legacy_member_id = v_actor_member.id;
  IF v_actor_person_id IS NULL THEN RETURN NEW; END IF;

  -- Path Y check: actor has sponsor × sponsor authoritative engagement
  v_is_sponsor := EXISTS (
    SELECT 1 FROM public.auth_engagements ae
    WHERE ae.person_id = v_actor_person_id
      AND ae.kind = 'sponsor' AND ae.role = 'sponsor'
      AND ae.is_authoritative = true
  );

  -- Path Y check: actor has any volunteer authoritative engagement (then we don't notify; volunteer chain is normal)
  v_is_volunteer := EXISTS (
    SELECT 1 FROM public.auth_engagements ae
    WHERE ae.person_id = v_actor_person_id
      AND ae.kind = 'volunteer'
      AND ae.is_authoritative = true
  );

  -- Trigger fires only when non-volunteer sponsor logged the entry (governance-relevant)
  IF NOT v_is_sponsor OR v_is_volunteer THEN RETURN NEW; END IF;

  -- Capture chapter_board affiliation for audit
  SELECT COALESCE(array_agg(DISTINCT ae.role), '{}')
  INTO v_chapter_board_aff
  FROM public.auth_engagements ae
  WHERE ae.person_id = v_actor_person_id
    AND ae.kind = 'chapter_board'
    AND ae.is_authoritative = true;

  -- Enhanced audit log entry
  v_audit_changes := jsonb_build_object(
    'entry_kind', v_kind,
    'entry_id', NEW.id,
    'amount_brl', v_amount,
    'description', v_description,
    'created_by_member_id', NEW.created_by,
    'created_by_name', v_actor_member.name,
    'created_by_chapter', v_actor_member.chapter,
    'engagement_context', jsonb_build_object(
      'is_sponsor', v_is_sponsor,
      'is_volunteer', v_is_volunteer,
      'chapter_board_roles', v_chapter_board_aff
    ),
    'governance_concern', 'non_volunteer_sponsor_logged_finance_entry'
  );

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (NEW.created_by, 'sponsor_finance_entry_logged', v_source_type, NEW.id, v_audit_changes);

  -- Notify all manage_platform holders (read-only governance visibility)
  FOR v_admin_member IN
    SELECT DISTINCT m.id
    FROM public.members m
    JOIN public.persons p ON p.legacy_member_id = m.id
    JOIN public.auth_engagements ae ON ae.person_id = p.id
    JOIN public.engagement_kind_permissions ekp
      ON ekp.kind = ae.kind AND ekp.role = ae.role AND ekp.action = 'manage_platform'
    WHERE m.is_active = true
      AND ae.is_authoritative = true
      AND m.id <> NEW.created_by  -- don't notify the actor
  LOOP
    PERFORM public.create_notification(
      v_admin_member,
      'sponsor_finance_entry_logged',
      v_source_type,
      NEW.id,
      'Lançamento ' || v_kind || ' por sponsor: ' || v_actor_member.name || ' · R$ ' || COALESCE(v_amount::text, '—'),
      NEW.created_by,
      COALESCE(v_description, '(sem descrição)')
    );
  END LOOP;

  RETURN NEW;
END;
$function$;

-- ── Section D: triggers ────────────────────────────────────
DROP TRIGGER IF EXISTS trg_cost_entry_sponsor_notify ON public.cost_entries;
CREATE TRIGGER trg_cost_entry_sponsor_notify
  AFTER INSERT ON public.cost_entries
  FOR EACH ROW EXECUTE FUNCTION public.notify_sponsor_finance_entry();

DROP TRIGGER IF EXISTS trg_revenue_entry_sponsor_notify ON public.revenue_entries;
CREATE TRIGGER trg_revenue_entry_sponsor_notify
  AFTER INSERT ON public.revenue_entries
  FOR EACH ROW EXECUTE FUNCTION public.notify_sponsor_finance_entry();

-- ── Defense-in-depth REVOKE FROM anon ──────────────────────
REVOKE EXECUTE ON FUNCTION public.create_cost_entry(text, text, numeric, date, text, uuid, uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_revenue_entry(text, text, date, text, numeric, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.notify_sponsor_finance_entry() FROM anon, authenticated;

-- ── Cache reload ───────────────────────────────────────────
NOTIFY pgrst, 'reload schema';
