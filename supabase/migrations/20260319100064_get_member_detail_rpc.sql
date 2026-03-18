-- ============================================================
-- W-ADMIN Phase 4: get_member_detail + admin_update_member_audited RPCs
-- ============================================================

-- Get full member detail for admin view
CREATE OR REPLACE FUNCTION public.get_member_detail(p_member_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result jsonb;
BEGIN
  -- Admin check
  IF NOT EXISTS (
    SELECT 1 FROM members WHERE auth_id = auth.uid()
    AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager'))
  ) THEN RAISE EXCEPTION 'Admin only'; END IF;

  SELECT jsonb_build_object(
    'member', (
      SELECT jsonb_build_object(
        'id', m.id, 'full_name', m.full_name, 'email', m.email,
        'photo_url', m.photo_url, 'operational_role', m.operational_role,
        'designations', m.designations, 'is_superadmin', m.is_superadmin,
        'is_active', m.is_active, 'tribe_id', m.tribe_id,
        'tribe_name', t.name, 'chapter', m.chapter,
        'auth_id', m.auth_id, 'credly_username', m.credly_username,
        'last_seen_at', m.last_seen_at, 'total_sessions', COALESCE(m.total_sessions, 0),
        'credly_badges', COALESCE(m.credly_badges, '[]'::jsonb)
      )
      FROM members m LEFT JOIN tribes t ON t.id = m.tribe_id
      WHERE m.id = p_member_id
    ),
    'cycles', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'cycle', mch.cycle,
        'tribe_id', mch.tribe_id,
        'tribe_name', t.name,
        'operational_role', mch.operational_role,
        'designations', mch.designations,
        'status', mch.status
      ) ORDER BY mch.cycle DESC), '[]'::jsonb)
      FROM member_cycle_history mch
      LEFT JOIN tribes t ON t.id = mch.tribe_id
      WHERE mch.member_id = p_member_id
    ),
    'gamification', (
      SELECT jsonb_build_object(
        'total_xp', COALESCE(gl.total_xp, 0),
        'rank', gl.rank,
        'categories', (
          SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'category', gp.category,
            'xp', gp.xp_value,
            'description', gp.description
          )), '[]'::jsonb)
          FROM gamification_points gp
          WHERE gp.member_id = p_member_id
        )
      )
      FROM gamification_leaderboard gl
      WHERE gl.member_id = p_member_id
    ),
    'attendance', (
      SELECT jsonb_build_object(
        'total_events', count(DISTINCT e.id),
        'attended', count(a.id),
        'rate', ROUND(count(a.id)::numeric / NULLIF(count(DISTINCT e.id), 0) * 100, 1),
        'recent', (
          SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'event_name', ev.title,
            'event_date', ev.date,
            'present', att.id IS NOT NULL
          ) ORDER BY ev.date DESC), '[]'::jsonb)
          FROM (SELECT * FROM events WHERE date >= CURRENT_DATE - INTERVAL '6 months' ORDER BY date DESC LIMIT 20) ev
          LEFT JOIN attendance att ON att.event_id = ev.id AND att.member_id = p_member_id
        )
      )
      FROM events e
      LEFT JOIN attendance a ON a.event_id = e.id AND a.member_id = p_member_id
      WHERE e.date >= CURRENT_DATE - INTERVAL '12 months'
    ),
    'publications', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', ps.id,
        'title', ps.title,
        'status', ps.status,
        'submitted_at', ps.submitted_at,
        'target_type', ps.target_type
      ) ORDER BY ps.submitted_at DESC), '[]'::jsonb)
      FROM publication_submissions ps
      JOIN publication_submission_authors psa ON psa.submission_id = ps.id
      WHERE psa.member_id = p_member_id
    ),
    'audit_log', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'action', al.action,
        'changes', al.changes,
        'actor_name', actor.full_name,
        'created_at', al.created_at
      ) ORDER BY al.created_at DESC), '[]'::jsonb)
      FROM admin_audit_log al
      LEFT JOIN members actor ON actor.id = al.actor_id
      WHERE al.target_id = p_member_id AND al.target_type = 'member'
      LIMIT 20
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- Update member with audit logging
CREATE OR REPLACE FUNCTION public.admin_update_member_audited(
  p_member_id uuid,
  p_changes jsonb
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_actor_id uuid;
  v_old_record jsonb;
  v_field text;
  v_old_val text;
  v_new_val text;
BEGIN
  SELECT id INTO v_actor_id FROM members WHERE auth_id = auth.uid()
    AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager'));
  IF v_actor_id IS NULL THEN RAISE EXCEPTION 'Admin only'; END IF;

  SELECT jsonb_build_object(
    'operational_role', m.operational_role,
    'designations', m.designations,
    'tribe_id', m.tribe_id,
    'chapter', m.chapter,
    'is_active', m.is_active,
    'is_superadmin', m.is_superadmin
  ) INTO v_old_record FROM members m WHERE m.id = p_member_id;

  UPDATE members SET
    operational_role = COALESCE((p_changes->>'operational_role'), operational_role),
    designations = CASE WHEN p_changes ? 'designations'
      THEN ARRAY(SELECT jsonb_array_elements_text(p_changes->'designations'))
      ELSE designations END,
    tribe_id = CASE WHEN p_changes ? 'tribe_id'
      THEN (p_changes->>'tribe_id')::integer
      ELSE tribe_id END,
    chapter = COALESCE((p_changes->>'chapter'), chapter),
    is_active = CASE WHEN p_changes ? 'is_active'
      THEN (p_changes->>'is_active')::boolean
      ELSE is_active END,
    is_superadmin = CASE WHEN p_changes ? 'is_superadmin'
      THEN (p_changes->>'is_superadmin')::boolean
      ELSE is_superadmin END
  WHERE id = p_member_id;

  FOR v_field IN SELECT jsonb_object_keys(p_changes) LOOP
    v_old_val := v_old_record->>v_field;
    v_new_val := p_changes->>v_field;

    IF v_old_val IS DISTINCT FROM v_new_val THEN
      INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
      VALUES (
        v_actor_id,
        'member.' || v_field || '_changed',
        'member',
        p_member_id,
        jsonb_build_object('field', v_field, 'old', v_old_val, 'new', v_new_val)
      );
    END IF;
  END LOOP;

  RETURN jsonb_build_object('success', true);
END;
$$;
