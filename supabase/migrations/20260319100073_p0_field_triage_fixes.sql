-- ============================================================
-- GC-091: P0 Field Triage Fixes (19/Mar/2026)
-- ============================================================

-- P0-1: Drop legacy UUID create_event overload (ambiguity error)
-- tribes.id is INTEGER, frontend sends integer. UUID version is orphaned.
DROP FUNCTION IF EXISTS public.create_event(text, text, date, integer, uuid, text);
DROP FUNCTION IF EXISTS public.create_event(text, text, date, integer, uuid);

-- P0-3a: Drop legacy 6-param overload of admin_list_members (ambiguity with 4-param)
DROP FUNCTION IF EXISTS public.admin_list_members(text, text, text, boolean, integer, integer);

-- P0-3b: Fix admin_list_members — m.full_name → m.name
CREATE OR REPLACE FUNCTION public.admin_list_members(
  p_search text DEFAULT NULL,
  p_tier text DEFAULT NULL,
  p_tribe_id integer DEFAULT NULL,
  p_status text DEFAULT 'active'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM members WHERE auth_id = auth.uid()
    AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager'))
  ) THEN RAISE EXCEPTION 'Admin only'; END IF;

  RETURN (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', m.id,
      'full_name', m.name,
      'email', m.email,
      'photo_url', m.photo_url,
      'operational_role', m.operational_role,
      'designations', m.designations,
      'is_superadmin', m.is_superadmin,
      'is_active', m.is_active,
      'tribe_id', m.tribe_id,
      'tribe_name', tc.name,
      'chapter', m.chapter,
      'auth_id', m.auth_id,
      'last_seen_at', m.last_seen_at,
      'total_sessions', COALESCE(m.total_sessions, 0),
      'credly_username', m.credly_username
    ) ORDER BY m.name), '[]'::jsonb)
    FROM members m
    LEFT JOIN tribes tc ON tc.id = m.tribe_id
    WHERE
      (p_status = 'all' OR (p_status = 'active' AND m.is_active = true) OR (p_status = 'inactive' AND m.is_active = false))
      AND (p_tier IS NULL OR m.operational_role = p_tier)
      AND (p_tribe_id IS NULL OR m.tribe_id = p_tribe_id)
      AND (p_search IS NULL OR m.name ILIKE '%' || p_search || '%' OR m.email ILIKE '%' || p_search || '%')
  );
END;
$$;

-- P0-4: Fix get_admin_dashboard — actor.full_name / target.full_name / m.full_name → .name
CREATE OR REPLACE FUNCTION public.get_admin_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM members WHERE auth_id = auth.uid()
    AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager'))
  ) THEN RAISE EXCEPTION 'Admin only'; END IF;

  SELECT jsonb_build_object(
    'generated_at', now(),

    'kpis', jsonb_build_object(
      'active_members', (SELECT count(*) FROM members WHERE is_active = true),
      'adoption_7d', (
        SELECT ROUND(
          count(*) FILTER (WHERE last_seen_at > now() - interval '7 days')::numeric
          / NULLIF(count(*), 0) * 100, 1
        ) FROM members WHERE is_active = true
      ),
      'deliverables_completed', (
        SELECT count(*) FROM board_items WHERE status = 'done'
      ),
      'deliverables_total', (
        SELECT count(*) FROM board_items WHERE status != 'archived'
      ),
      'impact_hours', (
        SELECT COALESCE(sum(duration_actual), 0) FROM events
        WHERE date >= '2026-01-01'
      ),
      'cpmai_current', (
        SELECT count(DISTINCT member_id) FROM gamification_points
        WHERE category IN ('cert_cpmai')
      ),
      'cpmai_target', (
        SELECT target_value FROM annual_kpi_targets
        WHERE kpi_key = 'cpmai_certifications' AND cycle = 3
        LIMIT 1
      ),
      'chapters_current', (
        SELECT count(DISTINCT chapter) FROM members WHERE is_active = true AND chapter IS NOT NULL
      ),
      'chapters_target', (
        SELECT target_value FROM annual_kpi_targets
        WHERE kpi_key = 'chapters_participating' AND cycle = 3
        LIMIT 1
      )
    ),

    'alerts', (
      SELECT COALESCE(jsonb_agg(alert), '[]'::jsonb) FROM (
        SELECT jsonb_build_object(
          'severity', 'high',
          'message', count(*) || ' membros sem tribo',
          'action_label', 'Ir para Tribos',
          'action_href', '/admin/tribes'
        ) as alert
        FROM members WHERE is_active = true AND tribe_id IS NULL
        HAVING count(*) > 0

        UNION ALL

        SELECT jsonb_build_object(
          'severity', 'medium',
          'message', count(*) || ' stakeholders sem conta',
          'action_label', 'Ver Membros',
          'action_href', '/admin/members'
        )
        FROM members WHERE is_active = true AND auth_id IS NULL
        AND operational_role IN ('sponsor', 'chapter_liaison')
        HAVING count(*) > 0

        UNION ALL

        SELECT jsonb_build_object(
          'severity', 'medium',
          'message', count(*) || ' membros em risco de dropout',
          'action_label', 'Ver lista',
          'action_href', '/admin/members'
        )
        FROM members m WHERE m.is_active = true
        AND m.tribe_id IS NOT NULL
        AND m.id NOT IN (
          SELECT a.member_id FROM attendance a
          JOIN events e ON e.id = a.event_id
          WHERE e.date > now() - interval '60 days'
        )
        HAVING count(*) > 0
      ) sub
    ),

    'recent_activity', (
      SELECT COALESCE(jsonb_agg(r.activity ORDER BY r.ts DESC), '[]'::jsonb)
      FROM (
        SELECT * FROM (
          SELECT jsonb_build_object(
            'type', 'audit',
            'message', actor.name || ' ' || al.action || ' em ' || COALESCE(target.name, '?'),
            'details', al.changes,
            'timestamp', al.created_at
          ) as activity, al.created_at as ts
          FROM admin_audit_log al
          LEFT JOIN members actor ON actor.id = al.actor_id
          LEFT JOIN members target ON target.id = al.target_id
          WHERE al.created_at > now() - interval '7 days'
          ORDER BY al.created_at DESC LIMIT 10
        ) a1

        UNION ALL

        SELECT * FROM (
          SELECT jsonb_build_object(
            'type', 'campaign',
            'message', 'Campanha "' || ct.name || '" enviada',
            'timestamp', cs.created_at
          ), cs.created_at
          FROM campaign_sends cs
          JOIN campaign_templates ct ON ct.id = cs.template_id
          WHERE cs.created_at > now() - interval '7 days'
          ORDER BY cs.created_at DESC LIMIT 5
        ) a2

        UNION ALL

        SELECT * FROM (
          SELECT jsonb_build_object(
            'type', 'publication',
            'message', m.name || ' submeteu "' || ps.title || '"',
            'timestamp', ps.submitted_at
          ), ps.submitted_at
          FROM publication_submissions ps
          JOIN publication_submission_authors psa ON psa.submission_id = ps.id
          JOIN members m ON m.id = psa.member_id
          WHERE ps.submitted_at > now() - interval '30 days'
          ORDER BY ps.submitted_at DESC LIMIT 5
        ) a3
      ) r
      LIMIT 15
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;
