-- ═══════════════════════════════════════════════════════════════
-- W109: Align KPIs with GP-Sponsor formal agreement (12/Oct/2025)
-- Expand from 6 to 9 KPIs, add partner_entities table,
-- add cpmai_certified_at column, update exec_portfolio_health RPC
-- ═══════════════════════════════════════════════════════════════

-- 1. Add cpmai_certified_at to members
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS cpmai_certified_at date;

-- Backfill for already-certified members (GP will provide real dates later)
UPDATE public.members
SET cpmai_certified_at = '2026-01-15'
WHERE cpmai_certified = true AND cpmai_certified_at IS NULL;

-- 2. Partner entities table
CREATE TABLE IF NOT EXISTS public.partner_entities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  entity_type text NOT NULL,  -- 'academia', 'governo', 'empresa', 'pmi_chapter', 'outro'
  description text,
  partnership_date date NOT NULL,
  cycle_code text DEFAULT 'cycle3-2026',
  contact_name text,
  contact_email text,
  status text DEFAULT 'active',  -- 'active', 'prospect', 'inactive'
  created_at timestamptz DEFAULT now()
);
COMMENT ON TABLE public.partner_entities IS 'KPI #2: Entidades parceiras (governo, academia, empresas)';

-- RLS
ALTER TABLE public.partner_entities ENABLE ROW LEVEL SECURITY;
CREATE POLICY "partner_entities_read" ON public.partner_entities
  FOR SELECT USING (true);
CREATE POLICY "partner_entities_admin_write" ON public.partner_entities
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND m.operational_role IN ('manager', 'deputy_manager')
    )
  );

-- Seed known PMI chapter partners
INSERT INTO public.partner_entities (name, entity_type, partnership_date, cycle_code) VALUES
  ('PMI-GO', 'pmi_chapter', '2024-06-01', 'pilot-2024'),
  ('PMI-CE', 'pmi_chapter', '2025-01-01', 'cycle1-2025'),
  ('PMI-DF', 'pmi_chapter', '2026-03-01', 'cycle3-2026'),
  ('PMI-MG', 'pmi_chapter', '2026-03-01', 'cycle3-2026'),
  ('PMI-RS', 'pmi_chapter', '2026-03-01', 'cycle3-2026')
ON CONFLICT DO NOTHING;

-- 3. Update portfolio_kpi_targets — expand to 9 KPIs
DELETE FROM public.portfolio_kpi_targets WHERE cycle_code = 'cycle3-2026';
INSERT INTO public.portfolio_kpi_targets
  (cycle_code, metric_key, metric_label, target_value, warning_threshold, critical_threshold, unit, display_order)
VALUES
  ('cycle3-2026', 'chapters_participating',
   '{"pt":"Capítulos PMI","en":"PMI Chapters","es":"Capítulos PMI"}',
   8, 6, 5, 'count', 1),
  ('cycle3-2026', 'partner_entities',
   '{"pt":"Entidades Parceiras","en":"Partner Entities","es":"Entidades Asociadas"}',
   3, 2, 1, 'count', 2),
  ('cycle3-2026', 'certification_trail',
   '{"pt":"Trilha Mini Cert. IA","en":"AI Mini Cert. Trail","es":"Sendero Mini Cert. IA"}',
   70, 50, 30, 'percent', 3),
  ('cycle3-2026', 'cpmai_certified',
   '{"pt":"Certificados CPMAI","en":"CPMAI Certified","es":"Certificados CPMAI"}',
   2, 1, 0, 'count', 4),
  ('cycle3-2026', 'articles_published',
   '{"pt":"Artigos Publicados","en":"Articles Published","es":"Artículos Publicados"}',
   10, 6, 3, 'count', 5),
  ('cycle3-2026', 'webinars_completed',
   '{"pt":"Webinares/Talks","en":"Webinars/Talks","es":"Webinarios/Charlas"}',
   6, 4, 2, 'count', 6),
  ('cycle3-2026', 'ia_pilots',
   '{"pt":"Pilotos IA","en":"AI Pilots","es":"Pilotos IA"}',
   3, 2, 1, 'count', 7),
  ('cycle3-2026', 'meeting_hours',
   '{"pt":"Horas de Encontros","en":"Meeting Hours","es":"Horas de Encuentros"}',
   90, 60, 30, 'hours', 8),
  ('cycle3-2026', 'impact_hours',
   '{"pt":"Horas de Impacto","en":"Impact Hours","es":"Horas de Impacto"}',
   1800, 1200, 600, 'hours', 9);

-- 4. Update exec_portfolio_health — handle all 9 KPIs
CREATE OR REPLACE FUNCTION public.exec_portfolio_health(p_cycle_code text DEFAULT 'cycle3-2026')
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb := '[]'::jsonb;
  v_target record;
  v_current numeric;
  v_progress numeric;
  v_status text;
  v_cycle_start date;
  v_cycle_end date;
BEGIN
  -- Resolve cycle date range
  SELECT cycle_start, COALESCE(cycle_end, current_date)
  INTO v_cycle_start, v_cycle_end
  FROM public.cycles
  WHERE cycle_code = (
    CASE p_cycle_code
      WHEN 'cycle3-2026' THEN 'cycle_3'
      ELSE p_cycle_code
    END
  );

  IF v_cycle_start IS NULL THEN
    v_cycle_start := '2026-03-01';
    v_cycle_end := current_date;
  END IF;

  FOR v_target IN
    SELECT * FROM public.portfolio_kpi_targets
    WHERE cycle_code = p_cycle_code
    ORDER BY display_order
  LOOP
    CASE v_target.metric_key

      -- 1) CHAPTERS: distinct active chapters
      WHEN 'chapters_participating' THEN
        SELECT COUNT(DISTINCT chapter)::numeric INTO v_current
        FROM public.members
        WHERE current_cycle_active = true
          AND chapter IS NOT NULL;

      -- 2) PARTNER ENTITIES: governo/academia/empresa (not pmi_chapter)
      WHEN 'partner_entities' THEN
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.partner_entities
        WHERE entity_type IN ('academia', 'governo', 'empresa')
          AND status = 'active'
          AND partnership_date <= current_date;

      -- 3) CERTIFICATION TRAIL: aggregated course progress
      WHEN 'certification_trail' THEN
        SELECT ROUND(COALESCE(AVG(member_pct) * 100, 0))
        INTO v_current
        FROM (
          SELECT
            COALESCE(
              COUNT(cp.id) FILTER (WHERE cp.status = 'completed'),
              0
            )::numeric / NULLIF(tc.cnt, 0) AS member_pct
          FROM public.members m
          CROSS JOIN (SELECT count(*)::numeric AS cnt FROM public.courses) tc
          LEFT JOIN public.course_progress cp ON cp.member_id = m.id
          WHERE m.current_cycle_active = true
            AND m.is_active = true
            AND (
              m.operational_role IN ('researcher', 'tribe_leader', 'manager', 'deputy_manager', 'communicator', 'facilitator')
              OR m.designations && ARRAY['ambassador', 'curator', 'co_gp']
            )
          GROUP BY m.id, tc.cnt
        ) sub;

      -- 4) CPMAI CERTIFIED: binary count of certified members
      WHEN 'cpmai_certified' THEN
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.members
        WHERE cpmai_certified = true
          AND current_cycle_active = true
          AND is_active = true
          AND (cpmai_certified_at IS NULL OR cpmai_certified_at >= '2024-01-01');

      -- 5) ARTICLES: only curated/approved items
      WHEN 'articles_published' THEN
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.board_items bi
        JOIN public.project_boards pb ON pb.id = bi.board_id
        WHERE (pb.domain_key ILIKE '%publication%' OR pb.domain_key ILIKE '%artigo%')
          AND bi.curation_status = 'approved'
          AND bi.created_at >= v_cycle_start::timestamptz;

      -- 6) WEBINARS/TALKS
      WHEN 'webinars_completed' THEN
        SELECT COUNT(*)::numeric INTO v_current
        FROM public.events e
        WHERE e.type = 'webinar'
          AND e.date >= v_cycle_start
          AND e.date <= current_date;

      -- 7) IA PILOTS
      WHEN 'ia_pilots' THEN
        v_current := COALESCE(
          (SELECT (value->>'count')::numeric FROM public.site_config WHERE key = 'ia_pilots_count'),
          1
        );

      -- 8) MEETING HOURS: raw sum of event durations (not multiplied by attendees)
      WHEN 'meeting_hours' THEN
        SELECT COALESCE(SUM(COALESCE(e.duration_actual, e.duration_minutes)::numeric / 60.0), 0)
        INTO v_current
        FROM public.events e
        WHERE e.date >= v_cycle_start
          AND e.date <= current_date;

      -- 9) IMPACT HOURS: duration × attendees present
      WHEN 'impact_hours' THEN
        SELECT COALESCE(SUM(e.duration_minutes::numeric / 60.0), 0)
        INTO v_current
        FROM public.attendance a
        JOIN public.events e ON e.id = a.event_id
        WHERE e.date >= v_cycle_start
          AND e.date <= current_date
          AND a.present = true;

      ELSE
        v_current := 0;
    END CASE;

    v_progress := CASE
      WHEN v_target.target_value > 0 THEN ROUND((v_current / v_target.target_value) * 100)
      ELSE 0
    END;

    v_status := CASE
      WHEN v_current >= v_target.target_value THEN 'green'
      WHEN v_current >= v_target.warning_threshold THEN 'yellow'
      ELSE 'red'
    END;

    v_result := v_result || jsonb_build_object(
      'metric_key', v_target.metric_key,
      'label', v_target.metric_label,
      'target', v_target.target_value,
      'current', v_current,
      'progress_pct', v_progress,
      'status', v_status,
      'unit', v_target.unit,
      'display_order', v_target.display_order
    );
  END LOOP;

  RETURN v_result;
END;
$$;

-- Grant access
GRANT EXECUTE ON FUNCTION public.exec_portfolio_health(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.exec_portfolio_health(text) TO anon;
