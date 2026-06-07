-- Migration: #420 follow-up — present-detection filter on attendance hours/impact metrics
-- Date: 2026-06-06 (session 6)
--
-- Context (#420, 2026-05-31 comment): the attendance table carries a `present` boolean
-- (true: 1374 rows, false: 65 rows, no NULLs). Several consumers summed/counted attendance
-- WITHOUT filtering present=true, so registered-but-absent rows inflated the numbers.
-- Live antes (2026-06-06):
--   get_public_impact_data.impact_hours          = 1655.99  -> present-only 1577.49 (-78.5h)
--   get_public_impact_data.total_attendance_hours= 896.16   -> present-only 817.66  (-78.5h)
-- This migration filters `a.present` in the two public/member hours metrics.
--
-- Body-faithful reproduction (Phase-C): the live `get_public_impact_data` body carried inline
-- `-- #481` comments; apply_migration strips inline `--` comments inside $function$ (sediment #156),
-- which would drift the body hash. They are removed here (the #481 rationale: chapters_summary is the
-- 5 SIGNED chapters from partner_entities, member_count/sponsor from members filtered to those names —
-- unchanged by this migration). No behavioural change beyond the present filter.
--
-- DEFERRED (NOT in this migration): get_admin_dashboard also has present-blind attendance logic —
--   (a) the dropout 60-day alert subquery (1-line present filter, but buried in a 7KB body), and
--   (b) the "detractors (3+ faltas consecutivas)" query, which is SEPARATELY BROKEN (its inner
--       LEFT JOIN exposes a.member_id that the NOT EXISTS then negates against itself -> NULL
--       member_ids -> the alert never fires). That needs a rewrite, not a present filter, and is
--       tracked as a #420 follow-up. No regression: the detractor alert is already effectively dead.
--
-- Scope note (data-architect review): the canonical KPI-bar source `impact_hours_total` VIEW
-- (mig 20260674400000) filters `present = true AND excused IS NOT TRUE` — stricter than this RPC's
-- present-only `impact_hours`. The two surfaces are intentionally different scopes (public impact page
-- = present participation hours; KPI bar = present-and-not-excused). Pre-existing divergence; this
-- migration only moves the RPC from all-attendance to present-only, it does not unify the excused scope.
--
-- Rollback: re-apply the prior bodies (without the `AND a.present` / `WHERE a.present` predicates).

CREATE OR REPLACE FUNCTION public.get_member_attendance_hours(p_member_id uuid, p_cycle_code text DEFAULT 'cycle_3'::text)
 RETURNS TABLE(total_hours numeric, total_events integer, avg_hours_per_event numeric, current_streak integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_start date;
  v_streak int := 0;
  v_rec record;
  v_target_tribe int;
BEGIN
  SELECT id INTO v_caller_id
  FROM public.members WHERE auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT (v_caller_id = p_member_id OR public.can_by_member(v_caller_id, 'view_pii')) THEN
    RAISE EXCEPTION 'Unauthorized: can only view own attendance or requires view_pii permission';
  END IF;

  SELECT cycle_start INTO v_cycle_start
  FROM public.cycles WHERE cycle_code = p_cycle_code;

  IF v_cycle_start IS NULL THEN
    RETURN QUERY SELECT 0::numeric, 0::int, 0::numeric, 0::int;
    RETURN;
  END IF;

  SELECT tribe_id INTO v_target_tribe FROM public.members WHERE id = p_member_id;

  FOR v_rec IN
    SELECT e.id,
           EXISTS(SELECT 1 FROM public.attendance a WHERE a.event_id = e.id AND a.member_id = p_member_id AND a.present) AS was_present
    FROM public.events e
    LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.date >= v_cycle_start
      AND e.date <= current_date
      AND (e.initiative_id IS NULL
           OR i.legacy_tribe_id = v_target_tribe)
    ORDER BY e.date DESC
  LOOP
    IF v_rec.was_present THEN
      v_streak := v_streak + 1;
    ELSE
      EXIT;
    END IF;
  END LOOP;

  RETURN QUERY
  SELECT
    COALESCE(SUM(e.duration_minutes / 60.0), 0)::numeric          AS total_hours,
    COUNT(DISTINCT a.event_id)::int                                AS total_events,
    CASE WHEN COUNT(DISTINCT a.event_id) > 0
      THEN (COALESCE(SUM(e.duration_minutes / 60.0), 0) / COUNT(DISTINCT a.event_id))::numeric
      ELSE 0::numeric
    END                                                            AS avg_hours_per_event,
    v_streak                                                       AS current_streak
  FROM public.attendance a
  JOIN public.events e ON e.id = a.event_id
  WHERE a.member_id = p_member_id AND a.present;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_public_impact_data()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result jsonb;
  v_chapters jsonb := public.get_chapter_metrics();
BEGIN
  SELECT jsonb_build_object(
    'chapters', (v_chapters->>'signed')::int,
    'chapters_engaged', (v_chapters->>'engaged')::int,
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
      WHERE e.date >= '2026-03-01' AND a.present
    ),
    'impact_hours', (
      SELECT COALESCE(SUM(e.duration_minutes / 60.0), 0)
      FROM attendance a JOIN events e ON e.id = a.event_id
      WHERE a.present
    ),
    'webinars', public.get_webinars_count(NULL, NULL, 'realized'),
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
      SELECT jsonb_agg(
        jsonb_build_object(
          'chapter', pe.name,
          'member_count', (SELECT COUNT(*) FROM members m WHERE m.chapter = pe.name AND m.is_active),
          'sponsor', (SELECT ms.name FROM members ms WHERE ms.chapter = pe.name AND 'sponsor' = ANY(ms.designations) AND ms.is_active LIMIT 1)
        )
        ORDER BY (SELECT COUNT(*) FROM members m WHERE m.chapter = pe.name AND m.is_active) DESC, pe.name
      )
      FROM partner_entities pe
      WHERE pe.entity_type = 'pmi_chapter' AND pe.status = 'active' AND NOT COALESCE(pe.is_international, false)
    ), '[]'::jsonb),
    'partners', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('name', name, 'type', entity_type, 'status', status))
      FROM partner_entities WHERE status = 'active'
    ), '[]'::jsonb),
    'recognitions', jsonb_build_array(
      jsonb_build_object(
        'title', 'Finalista — Prêmio "Carlos Novello" Voluntário do Ano',
        'organization', 'PMI LATAM Excellence Awards 2025',
        'recipient', 'Vitor Maia Rodovalho (GP)',
        'date', '2026-02-26',
        'category', 'Volunteer of the Year — LATAM Brasil',
        'description', 'Nomeado pelo PMI Goiás pelo trabalho à frente do Núcleo de IA & GP'
      )
    ),
    'timeline', jsonb_build_array(
      jsonb_build_object('year', '2024', 'title', 'Fase Piloto', 'description', 'Concepção pelo PMI-GO. Patrocínio Ivan Lourenço. Experimentação e lições aprendidas.'),
      jsonb_build_object('year', '2025.1', 'title', 'Oficialização', 'description', 'Parceria PMI-GO + PMI-CE. 7 artigos submetidos ao ProjectManagement.com. 1º Webinar.'),
      jsonb_build_object('year', '2025.2', 'title', 'Amadurecimento', 'description', 'Manual de Governança R2. 13 pesquisadores selecionados. Expansão para PMI-DF, PMI-MG, PMI-RS.'),
      jsonb_build_object('year', '2026', 'title', 'Escala', 'description', '44+ colaboradores, 8 tribos, 5 capítulos PMI. Plataforma digital própria. Processo seletivo estruturado.')
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;
