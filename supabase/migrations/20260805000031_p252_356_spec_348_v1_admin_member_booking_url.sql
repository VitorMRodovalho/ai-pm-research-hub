-- ============================================================
-- p252 #356 — SPEC #348 Child #3 Admin UI (RPC extensions for booking URL)
-- ------------------------------------------------------------
-- WHAT: Extends admin_update_member_audited allowlist and get_member_detail
--   return shape to surface members.interview_booking_url (column added in
--   #354 Foundation, consumed by #355 routing RPC for researcher-track LRD).
--   1. CREATE OR REPLACE public.admin_update_member_audited (same signature:
--      p_member_id uuid, p_changes jsonb):
--      - v_old_record SELECT adds 'interview_booking_url' so the audit FOR-loop
--        can compute old vs new on this field.
--      - UPDATE SET adds:
--          interview_booking_url = CASE
--            WHEN p_changes ? 'interview_booking_url'
--              THEN NULLIF(p_changes->>'interview_booking_url', '')
--            ELSE interview_booking_url
--          END
--        NULLIF('', '') so a cleared form field stores SQL NULL (not '').
--      - Audit dispatch unchanged: dynamic
--        'member.' || v_field || '_changed' → admin_audit_log row when the
--        old/new values differ.
--   2. CREATE OR REPLACE public.get_member_detail (same signature:
--      p_member_id uuid):
--      - member jsonb adds 'interview_booking_url', m.interview_booking_url
--        so the React island can pre-populate the input on edit.
--      - Everything else preserved verbatim from p118 (the latest canonical
--        body — gamification CTE + cycle_label + is_active mapping).
--
-- WHY: SPEC #348 Child #3 (#356) lands the admin form field that populates
--   members.interview_booking_url. Without these two RPC extensions:
--     - admin_update_member_audited would silently drop the field — the
--       FOR-loop would log a phantom audit row, but the UPDATE statement
--       wouldn't touch the column (only allowlisted columns are written).
--     - get_member_detail wouldn't return the current URL, so the form would
--       always render empty regardless of stored state.
--   Both extensions are same-signature CREATE OR REPLACE per SEDIMENT-238.C
--   (preserves EXECUTE grants; no consumer break).
--   No DB CHECK on URL format (SPEC #348 §3 Q2 — keep flexible for deep
--   links / future booking providers; UI validates pattern=^https?://.*).
--
-- SPEC DRIFT RESOLVED: none. Child #3 lands the admin UI surface promised
--   by SPEC #348 §8.
--
-- ROLLBACK: re-apply the immediately-preceding canonical body of each RPC:
--   - admin_update_member_audited →
--       supabase/migrations/20260425200827_qb_drift_correction_2touch_batch4_completion_a.sql
--   - get_member_detail →
--       supabase/migrations/20260517130000_p118_fix_get_member_detail_cycles_columns.sql
--   Safe additive change: existing consumers keep working. No data movement.
--
-- INVARIANTS: 19/19=0 unchanged. No new tables / policies / columns / FKs.
--   ACL preserved by CREATE OR REPLACE (REVOKE FROM PUBLIC,anon re-issued
--   below for defense-in-depth on get_member_detail).
--
-- CROSS-REF:
--   Parent:        #348 (SPEC roadmap)
--   This:          #356 (Child #3 Admin UI)
--   Predecessors:  #354 (Foundation DDL, p250) · #355 (RPC routing, p251)
--   SPEC doc:      docs/specs/SPEC_348_BOOKING_URL_PER_EVALUATOR.md §8 Child #3
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_update_member_audited(p_member_id uuid, p_changes jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_actor_id uuid; v_old_record jsonb; v_field text; v_old_val text; v_new_val text;
BEGIN
  SELECT id INTO v_actor_id FROM public.members WHERE auth_id = auth.uid();
  IF v_actor_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.can_by_member(v_actor_id, 'manage_member') THEN RAISE EXCEPTION 'Unauthorized: requires manage_member permission'; END IF;
  SELECT jsonb_build_object(
    'operational_role', m.operational_role,
    'designations', m.designations,
    'tribe_id', m.tribe_id,
    'chapter', m.chapter,
    'is_active', m.is_active,
    'is_superadmin', m.is_superadmin,
    'interview_booking_url', m.interview_booking_url
  ) INTO v_old_record FROM public.members m WHERE m.id = p_member_id;
  UPDATE public.members SET
    operational_role = COALESCE((p_changes->>'operational_role'), operational_role),
    designations = CASE WHEN p_changes ? 'designations' THEN ARRAY(SELECT jsonb_array_elements_text(p_changes->'designations')) ELSE designations END,
    tribe_id = CASE WHEN p_changes ? 'tribe_id' THEN (p_changes->>'tribe_id')::integer ELSE tribe_id END,
    chapter = COALESCE((p_changes->>'chapter'), chapter),
    is_active = CASE WHEN p_changes ? 'is_active' THEN (p_changes->>'is_active')::boolean ELSE is_active END,
    is_superadmin = CASE WHEN p_changes ? 'is_superadmin' THEN (p_changes->>'is_superadmin')::boolean ELSE is_superadmin END,
    interview_booking_url = CASE WHEN p_changes ? 'interview_booking_url' THEN NULLIF(p_changes->>'interview_booking_url', '') ELSE interview_booking_url END
  WHERE id = p_member_id;
  FOR v_field IN SELECT jsonb_object_keys(p_changes) LOOP
    v_old_val := v_old_record->>v_field;
    v_new_val := p_changes->>v_field;
    IF v_old_val IS DISTINCT FROM v_new_val THEN
      INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
      VALUES (v_actor_id, 'member.' || v_field || '_changed', 'member', p_member_id, jsonb_build_object('field', v_field, 'old', v_old_val, 'new', v_new_val));
    END IF;
  END LOOP;
  RETURN jsonb_build_object('success', true);
END; $$;

CREATE OR REPLACE FUNCTION public.get_member_detail(p_member_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  SELECT jsonb_build_object(
    'member', (SELECT jsonb_build_object(
      'id', m.id, 'full_name', m.name, 'email', m.email, 'photo_url', m.photo_url,
      'operational_role', m.operational_role, 'designations', m.designations,
      'is_superadmin', m.is_superadmin, 'is_active', m.is_active,
      'tribe_id', m.tribe_id, 'tribe_name', t.name, 'chapter', m.chapter,
      'auth_id', m.auth_id, 'credly_username', m.credly_url,
      'last_seen_at', m.last_seen_at, 'total_sessions', COALESCE(m.total_sessions, 0),
      'credly_badges', COALESCE(m.credly_badges, '[]'::jsonb),
      'interview_booking_url', m.interview_booking_url
    ) FROM public.members m LEFT JOIN public.tribes t ON t.id = m.tribe_id WHERE m.id = p_member_id),
    'cycles', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'cycle', mch.cycle_label,
      'tribe_id', mch.tribe_id,
      'tribe_name', t.name,
      'operational_role', mch.operational_role,
      'designations', mch.designations,
      'status', CASE WHEN mch.is_active THEN 'ativo' ELSE 'inativo' END
    ) ORDER BY mch.cycle_start DESC), '[]'::jsonb)
    FROM public.member_cycle_history mch
    LEFT JOIN public.tribes t ON t.id = mch.tribe_id
    WHERE mch.member_id = p_member_id),
    'gamification', (
      WITH agg AS (
        SELECT member_id, SUM(points)::int AS total_points
        FROM public.gamification_points
        GROUP BY member_id
      ),
      ranked AS (
        SELECT member_id, total_points,
               ROW_NUMBER() OVER (ORDER BY total_points DESC) AS rk
        FROM agg
      )
      SELECT jsonb_build_object(
        'total_xp', COALESCE((SELECT total_points FROM ranked WHERE member_id = p_member_id), 0),
        'rank', (SELECT rk FROM ranked WHERE member_id = p_member_id),
        'categories', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'category', gp.category, 'xp', gp.points, 'description', gp.reason
        )), '[]'::jsonb) FROM public.gamification_points gp WHERE gp.member_id = p_member_id)
      )
    ),
    'attendance', (SELECT jsonb_build_object(
      'total_events', count(DISTINCT e.id),
      'attended', count(a.id),
      'rate', ROUND(count(a.id)::numeric / NULLIF(count(DISTINCT e.id), 0) * 100, 1),
      'recent', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'event_name', ev.title, 'event_date', ev.date, 'present', att.id IS NOT NULL
      ) ORDER BY ev.date DESC), '[]'::jsonb)
      FROM (SELECT * FROM public.events WHERE date >= CURRENT_DATE - INTERVAL '6 months' AND date <= CURRENT_DATE ORDER BY date DESC LIMIT 20) ev
      LEFT JOIN public.attendance att ON att.event_id = ev.id AND att.member_id = p_member_id)
    ) FROM public.events e LEFT JOIN public.attendance a ON a.event_id = e.id AND a.member_id = p_member_id
    WHERE e.date >= CURRENT_DATE - INTERVAL '12 months' AND e.date <= CURRENT_DATE),
    'publications', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', ps.id, 'title', ps.title, 'status', ps.status,
      'submitted_at', ps.submission_date, 'target_type', ps.target_type
    ) ORDER BY ps.submission_date DESC), '[]'::jsonb)
    FROM public.publication_submissions ps
    JOIN public.publication_submission_authors psa ON psa.submission_id = ps.id
    WHERE psa.member_id = p_member_id),
    'audit_log', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'action', al.action, 'changes', al.changes, 'actor_name', actor.name, 'created_at', al.created_at
    ) ORDER BY al.created_at DESC), '[]'::jsonb)
    FROM public.admin_audit_log al
    LEFT JOIN public.members actor ON actor.id = al.actor_id
    WHERE al.target_id = p_member_id AND al.target_type = 'member' LIMIT 20)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_member_detail(uuid) FROM PUBLIC, anon;

NOTIFY pgrst, 'reload schema';
