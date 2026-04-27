-- ADR-0035 (Accepted, p66): analytics dashboards V4 + no-gate hardening
-- See docs/adr/ADR-0035-analytics-dashboards-and-no-gate-hardening.md
--
-- PM ratified Q1-Q4 (2026-04-26 p66): SIM / SIM / SIM / p66
--
-- Group V3 (V3-gated → V4 reuse view_internal_analytics):
--   legacy=11 → v4=10
--   would_lose = [João Uzejka] (chapter_liaison designation drift, ADR-0030 precedent)
-- Group NoGate (security hardening — add gate where there was none):
--   Privilege REDUCTION (any authenticated → 10 V4 ladder)

-- ============================================================
-- 1. get_chapter_dashboard — Path Y view_internal_analytics + own-chapter
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_chapter_dashboard(p_chapter text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_chapter text;
  v_chapter text;
  v_result jsonb;
  v_hub_members int;
  v_hub_avg_xp numeric;
  v_hub_certs int;
  v_ch_members int;
BEGIN
  SELECT m.id, m.chapter INTO v_caller_id, v_caller_chapter
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- V4 gate (Path Y per ADR-0030 precedent):
  -- Cross-chapter institutional access OR own-chapter member access
  IF public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    v_chapter := COALESCE(p_chapter, v_caller_chapter);
  ELSIF p_chapter IS NULL OR p_chapter = v_caller_chapter THEN
    v_chapter := v_caller_chapter;
  ELSE
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  IF v_chapter IS NULL THEN
    RETURN jsonb_build_object('error', 'No chapter specified');
  END IF;

  SELECT count(*) INTO v_hub_members FROM public.members WHERE is_active AND current_cycle_active;
  SELECT count(*) INTO v_ch_members FROM public.members WHERE chapter = v_chapter AND is_active;
  SELECT COALESCE(avg(t.xp), 0) INTO v_hub_avg_xp FROM (SELECT sum(points) AS xp FROM public.gamification_points GROUP BY member_id) t;
  SELECT count(*) INTO v_hub_certs FROM public.gamification_points WHERE category IN ('cert_pmi_senior','cert_cpmai','cert_pmi_mid','cert_pmi_practitioner','cert_pmi_entry');

  SELECT jsonb_build_object(
    'chapter', v_chapter,
    'cycle', 3,
    'people', (SELECT jsonb_build_object(
      'active', count(*) FILTER (WHERE member_status = 'active'),
      'observers', count(*) FILTER (WHERE member_status = 'observer'),
      'alumni', count(*) FILTER (WHERE member_status = 'alumni'),
      'hub_total', v_hub_members,
      'by_role', (SELECT jsonb_object_agg(role, cnt) FROM (SELECT operational_role AS role, count(*) AS cnt FROM public.members WHERE chapter = v_chapter AND member_status = 'active' GROUP BY operational_role) r)
    ) FROM public.members WHERE chapter = v_chapter),
    'output', jsonb_build_object(
      'board_cards_completed', (SELECT count(*) FROM public.board_items bi JOIN public.board_item_assignments bia ON bia.item_id = bi.id JOIN public.members m ON m.id = bia.member_id WHERE m.chapter = v_chapter AND bi.status = 'done'),
      'publications_submitted', (SELECT count(*) FROM public.publication_submissions ps JOIN public.members m ON m.id = ps.primary_author_id WHERE m.chapter = v_chapter)
    ),
    'attendance', jsonb_build_object(
      'rate_pct', (SELECT ROUND(COUNT(DISTINCT a.member_id)::numeric / NULLIF(v_ch_members, 0) * 100, 1) FROM public.attendance a JOIN public.members m ON a.member_id = m.id JOIN public.events e ON a.event_id = e.id WHERE m.chapter = v_chapter AND m.is_active AND a.present AND e.date >= now() - interval '90 days'),
      'avg_events_per_member', (SELECT ROUND(COUNT(a.id)::numeric / NULLIF(v_ch_members, 0), 1) FROM public.attendance a JOIN public.members m ON a.member_id = m.id JOIN public.events e ON a.event_id = e.id WHERE m.chapter = v_chapter AND m.is_active AND a.present AND e.date >= now() - interval '90 days'),
      'total_events_attended', (SELECT COUNT(a.id) FROM public.attendance a JOIN public.members m ON a.member_id = m.id JOIN public.events e ON a.event_id = e.id WHERE m.chapter = v_chapter AND m.is_active AND a.present AND e.date >= now() - interval '90 days'),
      'hub_participation_pct', (SELECT ROUND(COUNT(DISTINCT a.member_id)::numeric / NULLIF(v_hub_members, 0) * 100, 1) FROM public.attendance a JOIN public.members m ON a.member_id = m.id JOIN public.events e ON a.event_id = e.id WHERE m.is_active AND a.present AND e.date >= now() - interval '90 days')
    ),
    'hours', (SELECT jsonb_build_object(
      'total_hours', COALESCE(round(sum(CASE WHEN a.present THEN COALESCE(e.duration_minutes, 60) / 60.0 ELSE 0 END)::numeric, 1), 0),
      'pdu_equivalent', LEAST(COALESCE(round(sum(CASE WHEN a.present THEN COALESCE(e.duration_minutes, 60) / 60.0 ELSE 0 END)::numeric, 1), 0), 25)
    ) FROM public.attendance a JOIN public.events e ON e.id = a.event_id JOIN public.members m ON m.id = a.member_id WHERE m.chapter = v_chapter AND m.member_status = 'active'),
    'certifications', (SELECT jsonb_build_object(
      'pmp', count(*) FILTER (WHERE gp.category = 'cert_pmi_senior'),
      'cpmai', count(*) FILTER (WHERE gp.category = 'cert_cpmai'),
      'total_certs', count(*) FILTER (WHERE gp.category IN ('cert_pmi_senior','cert_cpmai','cert_pmi_mid','cert_pmi_practitioner','cert_pmi_entry')),
      'hub_total_certs', v_hub_certs
    ) FROM public.gamification_points gp JOIN public.members m ON m.id = gp.member_id WHERE m.chapter = v_chapter AND m.member_status = 'active'),
    'partnerships', (SELECT jsonb_build_object(
      'active', count(*) FILTER (WHERE pe.status = 'active'),
      'negotiation', count(*) FILTER (WHERE pe.status = 'negotiation'),
      'total', count(*)
    ) FROM public.partner_entities pe WHERE pe.chapter = v_chapter),
    'gamification', (SELECT jsonb_build_object(
      'avg_xp', COALESCE(round(avg(total_xp)), 0),
      'hub_avg_xp', round(v_hub_avg_xp),
      'top_contributors', (SELECT jsonb_agg(row_to_json(tc) ORDER BY tc.total_xp DESC) FROM (
        SELECT m.name, m.photo_url, sum(gp.points) AS total_xp
        FROM public.gamification_points gp JOIN public.members m ON m.id = gp.member_id
        WHERE m.chapter = v_chapter AND m.member_status = 'active'
        GROUP BY m.id, m.name, m.photo_url
        ORDER BY total_xp DESC LIMIT 3
      ) tc)
    ) FROM (SELECT sum(gp.points) AS total_xp FROM public.gamification_points gp JOIN public.members m ON m.id = gp.member_id WHERE m.chapter = v_chapter AND m.member_status = 'active' GROUP BY gp.member_id) t),
    'members', (SELECT jsonb_agg(row_to_json(ml) ORDER BY ml.total_xp DESC) FROM (
      SELECT m.id, m.name, m.photo_url, m.operational_role, m.designations,
        COALESCE((SELECT sum(points) FROM public.gamification_points WHERE member_id = m.id), 0) AS total_xp,
        COALESCE((SELECT round(100.0 * count(*) FILTER (WHERE present) / NULLIF(count(*), 0)) FROM public.attendance WHERE member_id = m.id), 0) AS attendance_pct,
        (SELECT count(*) FROM public.gamification_points WHERE member_id = m.id AND category = 'trail') AS trail_count
      FROM public.members m WHERE m.chapter = v_chapter AND m.member_status = 'active'
    ) ml),
    'available_chapters', (SELECT jsonb_agg(DISTINCT m.chapter ORDER BY m.chapter) FROM public.members m WHERE m.chapter IS NOT NULL AND m.member_status = 'active')
  ) INTO v_result;

  RETURN v_result;
END;
$$;
COMMENT ON FUNCTION public.get_chapter_dashboard(text) IS
  'Phase B'' V4 conversion (ADR-0035, p66): view_internal_analytics + own-chapter Path Y. Was V3 (SA OR manager/deputy OR designations sponsor/chapter_liaison + own-chapter member).';

-- ============================================================
-- 2. get_diversity_dashboard — pure V4 reuse view_internal_analytics
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_diversity_dashboard(p_cycle_id uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_cycle_id uuid;
  v_by_gender jsonb;
  v_by_chapter jsonb;
  v_by_sector jsonb;
  v_by_seniority jsonb;
  v_by_region jsonb;
  v_applicants_total int;
  v_approved_total int;
  v_snapshots jsonb;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RAISE EXCEPTION 'Unauthorized: admin or sponsor required';
  END IF;

  v_cycle_id := COALESCE(p_cycle_id, (SELECT id FROM public.selection_cycles ORDER BY created_at DESC LIMIT 1));
  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'no_cycle_found');
  END IF;

  SELECT COUNT(*) INTO v_applicants_total FROM public.selection_applications WHERE cycle_id = v_cycle_id;
  SELECT COUNT(*) INTO v_approved_total FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status IN ('approved', 'converted');

  SELECT jsonb_agg(jsonb_build_object('gender', gender_label, 'applicants', applicants, 'approved', approved))
  INTO v_by_gender
  FROM (
    SELECT CASE sa.gender
      WHEN 'M' THEN 'Masculino'
      WHEN 'F' THEN 'Feminino'
      ELSE COALESCE(sa.gender, 'Não informado')
    END as gender_label,
    COUNT(*) AS applicants,
    COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa WHERE sa.cycle_id = v_cycle_id GROUP BY gender_label ORDER BY applicants DESC
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('chapter', COALESCE(chapter, 'Não informado'), 'applicants', applicants, 'approved', approved))
  INTO v_by_chapter
  FROM (
    SELECT sa.chapter, COUNT(*) AS applicants, COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa WHERE sa.cycle_id = v_cycle_id GROUP BY sa.chapter ORDER BY applicants DESC
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('sector', COALESCE(sector, 'Não informado'), 'applicants', applicants, 'approved', approved))
  INTO v_by_sector
  FROM (
    SELECT sa.sector, COUNT(*) AS applicants, COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa WHERE sa.cycle_id = v_cycle_id GROUP BY sa.sector ORDER BY applicants DESC
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('band', band, 'applicants', applicants, 'approved', approved))
  INTO v_by_seniority
  FROM (
    SELECT CASE
      WHEN sa.seniority_years IS NULL THEN 'Não informado'
      WHEN sa.seniority_years < 3 THEN '0-2 anos'
      WHEN sa.seniority_years < 6 THEN '3-5 anos'
      WHEN sa.seniority_years < 11 THEN '6-10 anos'
      WHEN sa.seniority_years < 16 THEN '11-15 anos'
      ELSE '16+ anos'
    END AS band,
    COUNT(*) AS applicants, COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa WHERE sa.cycle_id = v_cycle_id GROUP BY band ORDER BY band
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('region', COALESCE(region, 'Não informado'), 'applicants', applicants, 'approved', approved))
  INTO v_by_region
  FROM (
    SELECT CASE
      WHEN sa.country IS NULL OR sa.country = '' THEN COALESCE(sa.state, 'Não informado')
      WHEN sa.country IN ('Brazil', 'BR', 'Brasil') THEN COALESCE(sa.state, 'Brasil')
      WHEN sa.state IS NOT NULL AND sa.state != '' THEN sa.state || ' (' || sa.country || ')'
      ELSE sa.country
    END AS region,
    COUNT(*) AS applicants, COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa WHERE sa.cycle_id = v_cycle_id GROUP BY region ORDER BY applicants DESC
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('snapshot_type', sds.snapshot_type, 'metrics', sds.metrics, 'created_at', sds.created_at) ORDER BY sds.created_at DESC)
  INTO v_snapshots
  FROM public.selection_diversity_snapshots sds WHERE sds.cycle_id = v_cycle_id;

  RETURN jsonb_build_object(
    'cycle_id', v_cycle_id,
    'applicants_total', v_applicants_total,
    'approved_total', v_approved_total,
    'by_gender', COALESCE(v_by_gender, '[]'::jsonb),
    'by_chapter', COALESCE(v_by_chapter, '[]'::jsonb),
    'by_sector', COALESCE(v_by_sector, '[]'::jsonb),
    'by_seniority', COALESCE(v_by_seniority, '[]'::jsonb),
    'by_region', COALESCE(v_by_region, '[]'::jsonb),
    'snapshots', COALESCE(v_snapshots, '[]'::jsonb)
  );
END;
$$;
COMMENT ON FUNCTION public.get_diversity_dashboard(uuid) IS
  'Phase B'' V4 conversion (ADR-0035, p66): Opção B reuse view_internal_analytics. Was V3 (SA OR manager/deputy OR designations sponsor/chapter_liaison).';

-- ============================================================
-- 3. get_annual_kpis — add V4 gate (no-gate hardening)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_annual_kpis(p_cycle integer DEFAULT 4, p_year integer DEFAULT 2026)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_auto_values jsonb;
  v_kpis jsonb;
  v_cycle_start date := '2025-12-01';
  v_cycle_end date := '2026-06-30';
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  v_auto_values := jsonb_build_object(
    'pilots_active_or_completed', (SELECT count(*) FROM public.pilots WHERE status IN ('active', 'completed')),
    'publications_submitted_count', (SELECT count(*) FROM public.board_items bi JOIN public.board_item_tag_assignments bita ON bita.board_item_id = bi.id JOIN public.tags t ON t.id = bita.tag_id WHERE t.name = 'publicacao' AND bi.status IN ('done', 'review')),
    'articles_academic_count', (SELECT count(*) FROM public.board_items bi JOIN public.board_item_tag_assignments bita ON bita.board_item_id = bi.id JOIN public.tags t ON t.id = bita.tag_id WHERE t.name = 'artigo_academico' AND bi.status IN ('done', 'review')),
    'frameworks_delivered_count', (SELECT count(*) FROM public.board_items bi JOIN public.board_item_tag_assignments bita ON bita.board_item_id = bi.id JOIN public.tags t ON t.id = bita.tag_id WHERE t.name IN ('framework', 'ferramenta') AND bi.status IN ('done', 'review')),
    'webinars_realized_count', (SELECT count(DISTINCT e.id) FROM public.events e JOIN public.event_tag_assignments eta ON eta.event_id = e.id JOIN public.tags t ON t.id = eta.tag_id WHERE t.name = 'webinar' AND e.date BETWEEN v_cycle_start AND LEAST(v_cycle_end, CURRENT_DATE)),
    'attendance_general_avg_pct', public.calc_attendance_pct(),
    'retention_pct', (SELECT ROUND(count(*) FILTER (WHERE is_active = true AND current_cycle_active = true)::numeric / NULLIF(count(*), 0) * 100, 1) FROM public.members WHERE operational_role NOT IN ('visitor', 'candidate') AND is_active = true),
    'events_total_count', (SELECT count(*) FROM public.events e WHERE e.date BETWEEN v_cycle_start AND LEAST(v_cycle_end, CURRENT_DATE) AND NOT EXISTS (SELECT 1 FROM public.event_tag_assignments eta JOIN public.tags t ON t.id = eta.tag_id WHERE eta.event_id = e.id AND t.name = 'interview')),
    'trail_completion_pct', public.calc_trail_completion_pct(),
    'cpmai_certified_count', (SELECT count(*) FROM public.members WHERE cpmai_certified = true),
    'active_members_count', (SELECT count(*) FROM public.members WHERE is_active = true AND current_cycle_active = true),
    'infra_cost_current', (SELECT COALESCE(SUM(ce.amount_brl), 0) FROM public.cost_entries ce JOIN public.cost_categories cc ON cc.id = ce.category_id WHERE cc.name = 'infrastructure' AND ce.date >= date_trunc('month', now())::date AND ce.date < (date_trunc('month', now()) + interval '1 month')::date)
  );

  SELECT jsonb_agg(
    jsonb_build_object(
      'id', k.id, 'kpi_key', k.kpi_key, 'label_pt', k.kpi_label_pt, 'label_en', k.kpi_label_en,
      'category', k.category, 'target', k.target_value, 'baseline', k.baseline_value,
      'current', CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END,
      'unit', k.target_unit, 'icon', k.icon,
      'progress_pct', CASE
        WHEN k.target_value > 0 THEN ROUND(COALESCE(CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END, 0) / k.target_value * 100, 1)
        WHEN k.target_value = 0 THEN 100
        ELSE 0
      END,
      'health', CASE
        WHEN k.target_value = 0 AND COALESCE(CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END, 0) = 0 THEN 'achieved'
        WHEN k.target_value = 0 THEN 'at_risk'
        WHEN COALESCE(CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END, 0) >= k.target_value THEN 'achieved'
        WHEN COALESCE(CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END, 0) >= k.target_value * 0.7 THEN 'on_track'
        WHEN COALESCE(CASE WHEN k.auto_query IS NOT NULL AND v_auto_values ? k.auto_query THEN (v_auto_values->>k.auto_query)::numeric ELSE k.current_value END, 0) >= k.target_value * 0.4 THEN 'at_risk'
        ELSE 'behind'
      END,
      'notes', k.notes,
      'auto_query', k.auto_query
    ) ORDER BY k.display_order
  ) INTO v_kpis
  FROM public.annual_kpi_targets k
  WHERE k.cycle = p_cycle AND k.year = p_year;

  v_result := jsonb_build_object(
    'cycle', p_cycle, 'year', p_year, 'generated_at', now(),
    'kpis', COALESCE(v_kpis, '[]'::jsonb),
    'summary', jsonb_build_object(
      'total', jsonb_array_length(COALESCE(v_kpis, '[]'::jsonb)),
      'achieved', (SELECT count(*) FROM jsonb_array_elements(v_kpis) e WHERE e->>'health' = 'achieved'),
      'on_track', (SELECT count(*) FROM jsonb_array_elements(v_kpis) e WHERE e->>'health' = 'on_track'),
      'at_risk', (SELECT count(*) FROM jsonb_array_elements(v_kpis) e WHERE e->>'health' = 'at_risk'),
      'behind', (SELECT count(*) FROM jsonb_array_elements(v_kpis) e WHERE e->>'health' = 'behind')
    )
  );
  RETURN v_result;
END;
$$;
COMMENT ON FUNCTION public.get_annual_kpis(integer, integer) IS
  'Phase B'' no-gate hardening (ADR-0035, p66): added view_internal_analytics gate. Was zero-auth SECDEF (any authenticated user could call).';

-- ============================================================
-- 4. get_cycle_report — add V4 gate (no-gate hardening)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_cycle_report(p_cycle integer DEFAULT 3)
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
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  v_result := jsonb_build_object(
    'cycle', p_cycle,
    'generated_at', now(),
    'members', (SELECT jsonb_build_object(
      'total', count(*),
      'active', count(*) FILTER (WHERE is_active),
      'observers', count(*) FILTER (WHERE member_status = 'observer'),
      'alumni', count(*) FILTER (WHERE member_status = 'alumni'),
      'by_role', (SELECT coalesce(jsonb_object_agg(operational_role, cnt), '{}') FROM (SELECT operational_role, count(*) as cnt FROM public.members WHERE is_active GROUP BY operational_role) r)
    ) FROM public.members),
    'tribes', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id, 'name', t.name,
      'member_count', (SELECT count(*) FROM public.members WHERE tribe_id = t.id AND is_active),
      'board_progress', (SELECT CASE WHEN count(*) = 0 THEN 0 ELSE round(100.0 * count(*) FILTER (WHERE bi.status = 'done') / count(*)) END FROM public.project_boards pb JOIN public.initiatives i ON i.id = pb.initiative_id JOIN public.board_items bi ON bi.board_id = pb.id WHERE i.legacy_tribe_id = t.id AND bi.status != 'archived')
    ) ORDER BY t.id), '[]') FROM public.tribes t WHERE t.is_active),
    'events', (SELECT jsonb_build_object(
      'total', count(*),
      'total_impact_hours', (SELECT * FROM public.get_homepage_stats())->'impact_hours'
    ) FROM public.events WHERE date >= '2026-01-01'),
    'boards', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', pb.id, 'title', pb.board_name,
      'total_items', (SELECT count(*) FROM public.board_items WHERE board_id = pb.id AND status != 'archived'),
      'done_items', (SELECT count(*) FROM public.board_items WHERE board_id = pb.id AND status = 'done'),
      'progress', (SELECT CASE WHEN count(*) = 0 THEN 0 ELSE round(100.0 * count(*) FILTER (WHERE status = 'done') / count(*)) END FROM public.board_items WHERE board_id = pb.id AND status != 'archived')
    )), '[]') FROM public.project_boards pb WHERE pb.is_active),
    'kpis', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'name', k.kpi_label_pt, 'name_en', k.kpi_label_en,
      'target', k.target_value, 'current', k.current_value,
      'pct', CASE WHEN k.target_value > 0 THEN round(100.0 * k.current_value / k.target_value) ELSE 0 END
    )), '[]') FROM public.annual_kpi_targets k WHERE k.year = 2026),
    'platform', jsonb_build_object(
      'releases_count', (SELECT count(*) FROM public.releases),
      'governance_entries', 125,
      'zero_cost', true,
      'stack', 'Astro 5 + React 19 + Tailwind 4 + Supabase + Cloudflare Pages'
    )
  );
  RETURN v_result;
END;
$$;
COMMENT ON FUNCTION public.get_cycle_report(integer) IS
  'Phase B'' no-gate hardening (ADR-0035, p66): added view_internal_analytics gate. Was zero-auth SECDEF (any authenticated user could call).';

NOTIFY pgrst, 'reload schema';
