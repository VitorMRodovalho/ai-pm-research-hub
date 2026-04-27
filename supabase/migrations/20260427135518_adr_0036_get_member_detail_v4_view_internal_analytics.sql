-- ADR-0036 (Accepted, p66 final round): get_member_detail V4 conversion
-- Same ladder pattern as ADR-0031 admin_list_members → reuse view_internal_analytics
-- Privilege expansion: legacy=9 → v4=10 (+Roberto chapter_board × liaison, same as ADR-0031)
-- pg_policy precondition: zero RLS refs verified.

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

  -- V4 gate (Opção B reuse view_internal_analytics — ADR-0031 precedent)
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
      'credly_badges', COALESCE(m.credly_badges, '[]'::jsonb)
    ) FROM public.members m LEFT JOIN public.tribes t ON t.id = m.tribe_id WHERE m.id = p_member_id),
    'cycles', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'cycle', mch.cycle, 'tribe_id', mch.tribe_id, 'tribe_name', t.name,
      'operational_role', mch.operational_role, 'designations', mch.designations, 'status', mch.status
    ) ORDER BY mch.cycle DESC), '[]'::jsonb)
    FROM public.member_cycle_history mch
    LEFT JOIN public.tribes t ON t.id = mch.tribe_id
    WHERE mch.member_id = p_member_id),
    'gamification', (SELECT jsonb_build_object(
      'total_xp', COALESCE(gl.total_points, 0),
      'rank', (SELECT rk FROM (SELECT member_id, ROW_NUMBER() OVER (ORDER BY total_points DESC) AS rk FROM public.gamification_leaderboard) ranked WHERE ranked.member_id = p_member_id),
      'categories', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'category', gp.category, 'xp', gp.points, 'description', gp.reason
      )), '[]'::jsonb) FROM public.gamification_points gp WHERE gp.member_id = p_member_id)
    ) FROM public.gamification_leaderboard gl WHERE gl.member_id = p_member_id),
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
COMMENT ON FUNCTION public.get_member_detail(uuid) IS
  'Phase B'' V4 conversion (ADR-0036, p66): Opção B reuse view_internal_analytics. Was V3 (SA OR manager/deputy/sponsor/chapter_liaison). Same ladder + precedent as ADR-0031 admin_list_members.';

REVOKE EXECUTE ON FUNCTION public.get_member_detail(uuid) FROM PUBLIC, anon;
NOTIFY pgrst, 'reload schema';
