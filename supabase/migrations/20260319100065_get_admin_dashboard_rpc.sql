-- ============================================================
-- W-ADMIN Phase 4: get_admin_dashboard RPC
-- Dashboard KPIs, alerts, and recent activity.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_admin_dashboard()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
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
        WHERE category IN ('cert_cpmai') AND cycle = 3
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
      SELECT COALESCE(jsonb_agg(activity ORDER BY ts DESC), '[]'::jsonb) FROM (
        SELECT jsonb_build_object(
          'type', 'audit',
          'message', actor.full_name || ' ' || al.action || ' em ' || COALESCE(target.full_name, '?'),
          'details', al.changes,
          'timestamp', al.created_at
        ) as activity, al.created_at as ts
        FROM admin_audit_log al
        LEFT JOIN members actor ON actor.id = al.actor_id
        LEFT JOIN members target ON target.id = al.target_id
        WHERE al.created_at > now() - interval '7 days'
        ORDER BY al.created_at DESC LIMIT 10

        UNION ALL

        SELECT jsonb_build_object(
          'type', 'campaign',
          'message', 'Campanha "' || ct.name || '" enviada',
          'timestamp', cs.created_at
        ), cs.created_at
        FROM campaign_sends cs
        JOIN campaign_templates ct ON ct.id = cs.template_id
        WHERE cs.created_at > now() - interval '7 days'
        ORDER BY cs.created_at DESC LIMIT 5

        UNION ALL

        SELECT jsonb_build_object(
          'type', 'publication',
          'message', m.full_name || ' submeteu "' || ps.title || '"',
          'timestamp', ps.submitted_at
        ), ps.submitted_at
        FROM publication_submissions ps
        JOIN publication_submission_authors psa ON psa.submission_id = ps.id
        JOIN members m ON m.id = psa.member_id
        WHERE ps.submitted_at > now() - interval '30 days'
        ORDER BY ps.submitted_at DESC LIMIT 5
      ) sub
      LIMIT 15
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;
