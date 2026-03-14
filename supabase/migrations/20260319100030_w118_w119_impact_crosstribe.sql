-- ============================================================================
-- W118: Impact Narrative Public Page — get_public_impact_data()
-- W119: Cross-Tribe Comparison + Operational Alerts
-- Zero new tables — aggregation only
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- W118: PUBLIC IMPACT DATA (no auth required)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_public_impact_data()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb;
BEGIN
  -- PUBLIC — no auth required, returns aggregated data only (no PII)

  SELECT jsonb_build_object(
    'chapters', (SELECT COUNT(DISTINCT chapter) FROM members WHERE is_active = true AND chapter IS NOT NULL),
    'active_members', (SELECT COUNT(*) FROM members WHERE is_active = true AND current_cycle_active = true),
    'tribes', (SELECT COUNT(*) FROM tribes),
    'articles_published', (SELECT COUNT(*) FROM public_publications WHERE is_published = true),
    'articles_approved', (
      SELECT COUNT(*) FROM board_lifecycle_events WHERE action = 'curation_review' AND new_status = 'approved'
    ),
    'total_events', (SELECT COUNT(*) FROM events WHERE date >= '2026-03-01'),
    'total_attendance_hours', (
      SELECT COALESCE(SUM(e.duration_minutes / 60.0), 0)
      FROM attendance a JOIN events e ON e.id = a.event_id
      WHERE e.date >= '2026-03-01'
    ),
    'impact_hours', (
      SELECT COALESCE(SUM(e.duration_minutes / 60.0), 0)
      FROM attendance a JOIN events e ON e.id = a.event_id
    ),
    'webinars', (SELECT COUNT(*) FROM events WHERE type = 'webinar'),
    'ia_pilots', (SELECT COUNT(*) FROM ia_pilots WHERE status IN ('active','completed')),
    'partner_count', (SELECT COUNT(*) FROM partner_entities WHERE status = 'active'),
    'courses_count', (SELECT COUNT(*) FROM courses),
    'recent_publications', COALESCE((
      SELECT jsonb_agg(sub ORDER BY sub.publication_date DESC NULLS LAST)
      FROM (SELECT title, authors, external_platform AS platform, publication_date, external_url
            FROM public_publications WHERE is_published = true
            ORDER BY publication_date DESC NULLS LAST LIMIT 5) sub
    ), '[]'::jsonb),
    'tribes_summary', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', t.name, 'quadrant_name', t.quadrant_name,
        'member_count', (SELECT COUNT(*) FROM members m WHERE m.tribe_id = t.id AND m.is_active),
        'leader_name', (SELECT name FROM members WHERE id = t.leader_member_id)
      ) ORDER BY t.id)
      FROM tribes t
    ), '[]'::jsonb),
    'chapters_summary', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'chapter', m.chapter,
        'member_count', COUNT(*),
        'sponsor', (SELECT ms.name FROM members ms WHERE ms.chapter = m.chapter AND 'sponsor' = ANY(ms.designations) AND ms.is_active LIMIT 1)
      ))
      FROM members m WHERE m.is_active AND m.chapter IS NOT NULL
      GROUP BY m.chapter
    ), '[]'::jsonb),
    'partners', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('name', name, 'type', entity_type, 'status', status))
      FROM partner_entities WHERE status = 'active'
    ), '[]'::jsonb),
    'timeline', jsonb_build_array(
      jsonb_build_object('year', '2024', 'title', 'Fase Piloto', 'description', 'Concepção pelo PMI-GO. Patrocínio Ivan Lourenço. Experimentação e lições aprendidas.'),
      jsonb_build_object('year', '2025.1', 'title', 'Oficialização', 'description', 'Parceria PMI-GO + PMI-CE. 7 artigos submetidos ao ProjectManagement.com. 1º Webinar.'),
      jsonb_build_object('year', '2025.2', 'title', 'Amadurecimento', 'description', 'Manual de Governança R2. 13 pesquisadores selecionados. Expansão para PMI-DF, PMI-MG, PMI-RS.'),
      jsonb_build_object('year', '2026', 'title', 'Escala', 'description', '44+ colaboradores, 8 tribos, 5 capítulos PMI. Plataforma digital própria. Processo seletivo estruturado.')
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_public_impact_data() TO anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- W119: CROSS-TRIBE COMPARISON (GP/DM/superadmin)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.exec_cross_tribe_comparison(p_cycle text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_cycle_start date := '2026-03-01';
BEGIN
  -- Auth: GP/DM/superadmin only
  SELECT id INTO v_caller_id FROM members
  WHERE auth_id = auth.uid()
  AND (is_superadmin = true OR operational_role IN ('manager','deputy_manager'));
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;

  SELECT jsonb_build_object(
    'tribes', (
      SELECT jsonb_agg(jsonb_build_object(
        'tribe_id', t.id,
        'tribe_name', t.name,
        'quadrant', t.quadrant_name,
        'leader', (SELECT name FROM members WHERE id = t.leader_member_id),
        'member_count', (SELECT COUNT(*) FROM members m WHERE m.tribe_id = t.id AND m.is_active),
        'members_inactive_30d', (
          SELECT COUNT(*) FROM members m
          WHERE m.tribe_id = t.id AND m.is_active
          AND m.id NOT IN (
            SELECT DISTINCT a.member_id FROM attendance a
            JOIN events e ON e.id = a.event_id
            WHERE e.date >= (current_date - 30)
          )
        ),
        'total_cards', (
          SELECT COUNT(*) FROM board_items bi
          JOIN project_boards pb ON pb.id = bi.board_id
          WHERE pb.tribe_id = t.id
        ),
        'cards_completed', (
          SELECT COUNT(*) FROM board_items bi
          JOIN project_boards pb ON pb.id = bi.board_id
          WHERE pb.tribe_id = t.id AND bi.status IN ('done','approved','published')
        ),
        'articles_submitted', (
          SELECT COUNT(*) FROM board_lifecycle_events ble
          JOIN board_items bi ON bi.id = ble.item_id
          JOIN project_boards pb ON pb.id = bi.board_id
          WHERE pb.tribe_id = t.id AND ble.action = 'submission'
        ),
        'attendance_rate', (
          SELECT COALESCE(
            ROUND(
              COUNT(*) FILTER (WHERE EXISTS (SELECT 1 FROM attendance a2 WHERE a2.event_id = e.id AND a2.member_id IN (SELECT id FROM members WHERE tribe_id = t.id AND is_active)))::numeric
              / NULLIF((SELECT COUNT(*) FROM members WHERE tribe_id = t.id AND is_active)::numeric * COUNT(DISTINCT e.id), 0)
            , 2), 0)
          FROM events e
          WHERE (e.tribe_id = t.id OR e.tribe_id IS NULL) AND e.date >= v_cycle_start
        ),
        'total_hours', (
          SELECT COALESCE(SUM(e.duration_minutes / 60.0), 0)
          FROM attendance a JOIN events e ON e.id = a.event_id
          WHERE a.member_id IN (SELECT id FROM members WHERE tribe_id = t.id AND is_active)
          AND e.date >= v_cycle_start
        ),
        'meetings_count', (
          SELECT COUNT(*) FROM events WHERE tribe_id = t.id AND date >= v_cycle_start
        ),
        'total_xp', (
          SELECT COALESCE(SUM(gp.points), 0) FROM gamification_points gp
          WHERE gp.member_id IN (SELECT id FROM members WHERE tribe_id = t.id AND is_active)
        ),
        'avg_xp', (
          SELECT COALESCE(ROUND(AVG(sub.total)::numeric, 1), 0)
          FROM (SELECT SUM(gp.points) AS total FROM gamification_points gp
                WHERE gp.member_id IN (SELECT id FROM members WHERE tribe_id = t.id AND is_active)
                GROUP BY gp.member_id) sub
        ),
        'last_meeting_date', (SELECT MAX(date) FROM events WHERE tribe_id = t.id),
        'days_since_last_meeting', (
          SELECT EXTRACT(DAY FROM now() - MAX(date)::timestamp)::int FROM events WHERE tribe_id = t.id
        )
      ) ORDER BY t.id)
      FROM tribes t
    ),
    'generated_at', now()
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.exec_cross_tribe_comparison(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- W119: OPERATIONAL ALERTS (GP/DM/superadmin)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.detect_operational_alerts()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_id uuid;
  v_alerts jsonb := '[]'::jsonb;
  v_tmp jsonb;
BEGIN
  -- Auth: GP/DM/superadmin only
  SELECT id INTO v_caller_id FROM members
  WHERE auth_id = auth.uid()
  AND (is_superadmin = true OR operational_role IN ('manager','deputy_manager'));
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;

  -- ALERT 1: Tribes with no meeting in 14+ days
  SELECT jsonb_agg(jsonb_build_object(
    'severity', 'high',
    'type', 'tribe_no_meeting',
    'tribe_id', t.id,
    'tribe_name', t.name,
    'days_since', EXTRACT(DAY FROM now() - MAX(e.date)::timestamp)::int,
    'message', t.name || ' sem reunião há ' || EXTRACT(DAY FROM now() - MAX(e.date)::timestamp)::int || ' dias'
  ))
  INTO v_tmp
  FROM tribes t LEFT JOIN events e ON e.tribe_id = t.id
  GROUP BY t.id, t.name
  HAVING MAX(e.date) < current_date - 14 OR MAX(e.date) IS NULL;

  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  -- ALERT 2: Members absent from last 3 tribe meetings
  SELECT jsonb_agg(jsonb_build_object(
    'severity', 'medium',
    'type', 'member_absence_streak',
    'member_name', m.name,
    'tribe_name', t.name,
    'message', m.name || ' ausente em últimas reuniões da ' || t.name
  ))
  INTO v_tmp
  FROM members m JOIN tribes t ON t.id = m.tribe_id
  WHERE m.is_active AND m.tribe_id IS NOT NULL
  AND m.id NOT IN (
    SELECT DISTINCT a.member_id FROM attendance a
    JOIN events e ON e.id = a.event_id
    WHERE e.tribe_id = m.tribe_id
    AND e.date >= current_date - 21
  );

  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  -- ALERT 3: Tribes with zero card movement in 14+ days
  SELECT jsonb_agg(jsonb_build_object(
    'severity', 'medium',
    'type', 'tribe_stagnant_production',
    'tribe_id', t.id,
    'tribe_name', t.name,
    'message', t.name || ' sem movimentação de cards em 14+ dias'
  ))
  INTO v_tmp
  FROM tribes t
  WHERE t.id NOT IN (
    SELECT DISTINCT pb.tribe_id FROM board_lifecycle_events ble
    JOIN board_items bi ON bi.id = ble.item_id
    JOIN project_boards pb ON pb.id = bi.board_id
    WHERE ble.created_at >= now() - interval '14 days'
    AND pb.tribe_id IS NOT NULL
  );

  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  -- ALERT 4: Onboarding overdue
  SELECT jsonb_agg(jsonb_build_object(
    'severity', 'low',
    'type', 'onboarding_overdue',
    'member_name', sa.applicant_name,
    'step', op.step_key,
    'message', sa.applicant_name || ' atrasou ' || op.step_key
  ))
  INTO v_tmp
  FROM onboarding_progress op
  JOIN selection_applications sa ON sa.id = op.application_id
  WHERE op.status = 'overdue';

  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  -- ALERT 5: KPI at risk (below 50% of target)
  SELECT jsonb_agg(jsonb_build_object(
    'severity', 'high',
    'type', 'kpi_at_risk',
    'kpi_name', pkt.metric_key,
    'target_value', pkt.target_value,
    'message', pkt.metric_key || ' abaixo de 50% da meta'
  ))
  INTO v_tmp
  FROM portfolio_kpi_targets pkt
  WHERE pkt.target_value > 0
  AND pkt.critical_threshold > 0
  AND pkt.critical_threshold < (pkt.target_value * 0.5);

  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  RETURN jsonb_build_object(
    'alerts', v_alerts,
    'total', jsonb_array_length(v_alerts),
    'by_severity', jsonb_build_object(
      'high', (SELECT COUNT(*) FROM jsonb_array_elements(v_alerts) x WHERE x->>'severity' = 'high'),
      'medium', (SELECT COUNT(*) FROM jsonb_array_elements(v_alerts) x WHERE x->>'severity' = 'medium'),
      'low', (SELECT COUNT(*) FROM jsonb_array_elements(v_alerts) x WHERE x->>'severity' = 'low')
    ),
    'checked_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.detect_operational_alerts() TO authenticated;
