-- Fix admin dashboard "?" on CPMAI and Chapters KPIs
-- Root cause: KPI targets had cycle=3 but Ciclo 3 has sort_order=4 (pilot=1)
-- Also: RPC used wrong key name 'cpmai_certifications' instead of 'cpmai_certified'
-- Also: member count aligned to current_cycle_active

BEGIN;

-- 1. Fix cycle mismatch (all targets were cycle=3, current cycle sort_order=4)
UPDATE annual_kpi_targets SET cycle = 4 WHERE cycle = 3;

-- 2. Recreate RPC with correct kpi_key + current_cycle_active
CREATE OR REPLACE FUNCTION get_admin_dashboard()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp' AS $$
DECLARE v_result jsonb; v_cycle_start date; v_current_cycle int;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM members WHERE auth_id = auth.uid() AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager', 'sponsor', 'chapter_liaison'))) THEN RAISE EXCEPTION 'Admin only'; END IF;
  SELECT cycle_start, sort_order INTO v_cycle_start, v_current_cycle FROM cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := '2026-01-01'; END IF;
  IF v_current_cycle IS NULL THEN v_current_cycle := 4; END IF;
  SELECT jsonb_build_object(
    'generated_at', now(),
    'kpis', jsonb_build_object(
      'active_members', (SELECT count(*) FROM members WHERE is_active AND current_cycle_active),
      'adoption_7d', (SELECT ROUND(count(*) FILTER (WHERE last_seen_at > now() - interval '7 days')::numeric / NULLIF(count(*), 0) * 100, 1) FROM members WHERE is_active AND current_cycle_active),
      'deliverables_completed', (SELECT count(*) FROM board_items WHERE status = 'done'),
      'deliverables_total', (SELECT count(*) FROM board_items WHERE status != 'archived'),
      'impact_hours', (SELECT COALESCE(sum(duration_actual), 0) FROM events WHERE date >= v_cycle_start),
      'cpmai_current', (SELECT count(DISTINCT member_id) FROM gamification_points WHERE category = 'cert_cpmai' AND created_at >= v_cycle_start),
      'cpmai_target', (SELECT target_value FROM annual_kpi_targets WHERE kpi_key = 'cpmai_certified' AND cycle = v_current_cycle LIMIT 1),
      'chapters_current', (SELECT count(DISTINCT chapter) FROM members WHERE is_active = true AND chapter IS NOT NULL),
      'chapters_target', (SELECT target_value FROM annual_kpi_targets WHERE kpi_key = 'chapters_participating' AND cycle = v_current_cycle LIMIT 1)
    ),
    'alerts', (SELECT COALESCE(jsonb_agg(alert), '[]'::jsonb) FROM (
      SELECT jsonb_build_object('severity', 'high', 'message', count(*) || ' pesquisadores sem tribo', 'action_label', 'Ir para Tribos', 'action_href', '/admin/tribes') as alert FROM members WHERE is_active = true AND tribe_id IS NULL AND operational_role NOT IN ('sponsor', 'chapter_liaison', 'manager', 'deputy_manager', 'observer') HAVING count(*) > 0
      UNION ALL SELECT jsonb_build_object('severity', 'medium', 'message', count(*) || ' stakeholders sem conta', 'action_label', 'Ver Membros', 'action_href', '/admin/members') FROM members WHERE is_active = true AND auth_id IS NULL AND operational_role IN ('sponsor', 'chapter_liaison') HAVING count(*) > 0
      UNION ALL SELECT jsonb_build_object('severity', 'medium', 'message', count(*) || ' membros em risco de dropout', 'action_label', 'Ver lista', 'action_href', '/admin/members') FROM members m WHERE m.is_active = true AND m.current_cycle_active AND m.tribe_id IS NOT NULL AND m.id NOT IN (SELECT a.member_id FROM attendance a JOIN events e ON e.id = a.event_id WHERE e.date > now() - interval '60 days') HAVING count(*) > 0
    ) sub),
    'recent_activity', (SELECT COALESCE(jsonb_agg(r.activity ORDER BY r.ts DESC), '[]'::jsonb) FROM (
      SELECT * FROM (SELECT jsonb_build_object('type', 'audit', 'message', actor.name || ' ' || al.action || ' em ' || COALESCE(target.name, '?'), 'details', al.changes, 'timestamp', al.created_at) as activity, al.created_at as ts FROM admin_audit_log al LEFT JOIN members actor ON actor.id = al.actor_id LEFT JOIN members target ON target.id = al.target_id WHERE al.created_at > now() - interval '7 days' ORDER BY al.created_at DESC LIMIT 10) a1
      UNION ALL SELECT * FROM (SELECT jsonb_build_object('type', 'campaign', 'message', 'Campanha "' || ct.name || '" enviada', 'timestamp', cs.created_at), cs.created_at FROM campaign_sends cs JOIN campaign_templates ct ON ct.id = cs.template_id WHERE cs.created_at > now() - interval '7 days' ORDER BY cs.created_at DESC LIMIT 5) a2
      UNION ALL SELECT * FROM (SELECT jsonb_build_object('type', 'publication', 'message', m.name || ' submeteu "' || ps.title || '"', 'timestamp', ps.submission_date), ps.submission_date FROM publication_submissions ps JOIN publication_submission_authors psa ON psa.submission_id = ps.id JOIN members m ON m.id = psa.member_id WHERE ps.submission_date > now() - interval '30 days' ORDER BY ps.submission_date DESC LIMIT 5) a3
    ) r LIMIT 15)
  ) INTO v_result;
  RETURN v_result;
END;
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;
