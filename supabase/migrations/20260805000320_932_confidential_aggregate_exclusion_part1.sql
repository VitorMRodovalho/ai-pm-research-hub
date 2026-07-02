-- #932 (follow-up to #785 Tier 2): universal confidential exclusion from shared aggregate readers — PART 1.
--
-- Policy (PM decision 2026-07-02): a confidential initiative's board_items / events / the initiative row
-- NEVER count in shared aggregates, for EVERYONE incl GP (a private governance cadence must not inflate
-- community / portfolio / public KPIs; GP sees confidential via the dedicated gated board, not via polluted
-- KPIs). This is UNIVERSAL exclusion, NOT the session-aware rls_can_see_initiative() gate.
--
-- Part 1 scope = the CONTENT leaks + public + the canonical impact-hours source (highest severity, grounded
-- live 2026-07-02): reachable by anon and by the 12 non-GP view_internal_analytics + 15 non-GP
-- view_chapter_dashboards holders. Count-only aggregates over board tables (exec_portfolio_health,
-- exec_portfolio_board_summary, get_admin_dashboard deliverables, _artia_safe_monthly_metrics,
-- get_cycle_evolution, get_kpi_dashboard, get_annual_kpis, get_tags) are the Part-2 follow-up.
--
-- Council: security-engineer + data-architect both APPROVE_WITH_CONDITIONS. Conditions applied:
--   * session-BLIND helper (is_confidential_*), NOT rls_can_see_initiative (which GP passes) [data-arch F-01]
--   * fix get_impact_hours_canonical FIRST — cascades to homepage/public/admin/portfolio impact_hours [data-arch F-02]
--   * exec_cross_initiative_comparison + get_cycle_report + _artia_safe_event_summary are CONTENT leaks
--     to non-GP (view_chapter_dashboards / view_internal_analytics), not GP-only [security F-01/F-03/F-04]
--   * inline `visibility <> 'confidential'` where initiatives is already joined; helper where not [data-arch #3]

-- ---------------------------------------------------------------------------
-- 1. Session-blind confidential-visibility helpers (for AGGREGATE exclusion).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_confidential_initiative(p_initiative_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- #932: TRUE when the initiative is confidential. Session-BLIND (unlike rls_can_see_initiative, which
  -- returns TRUE for GP). Usage is ALWAYS `AND NOT public.is_confidential_initiative(...)`. NULL id → FALSE
  -- (org-level events/boards without an initiative are never confidential and must remain counted).
  SELECT COALESCE(
    (SELECT i.visibility = 'confidential' FROM public.initiatives i WHERE i.id = p_initiative_id),
    false);
$function$;

CREATE OR REPLACE FUNCTION public.is_confidential_board(p_board_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- #932: TRUE when the board's initiative is confidential. Usage ALWAYS `AND NOT public.is_confidential_board(...)`.
  -- NULL initiative_id (org-level board) → FALSE.
  SELECT COALESCE(
    (SELECT i.visibility = 'confidential'
     FROM public.project_boards pb JOIN public.initiatives i ON i.id = pb.initiative_id
     WHERE pb.id = p_board_id),
    false);
$function$;

COMMENT ON FUNCTION public.is_confidential_initiative(uuid) IS
  '#932 session-blind confidential flag for aggregate exclusion; use AS `AND NOT is_confidential_initiative(id)`. NOT a caller gate (see rls_can_see_initiative).';
COMMENT ON FUNCTION public.is_confidential_board(uuid) IS
  '#932 session-blind confidential flag (via board->initiative) for aggregate exclusion; use AS `AND NOT is_confidential_board(board_id)`.';

-- ---------------------------------------------------------------------------
-- 2. Recurrence-guard audit RPC: recognize the confidential-exclusion predicate
--    (helper name OR inline `visibility <> 'confidential'`) as a gate, so fixed
--    functions leave the #785 ALLOWLIST. The word 'confidential' appears in a
--    reader's body only when it excludes confidential.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._audit_secdef_initiative_reader_gates()
 RETURNS TABLE(proname text, identity_args text, reads_initiative_table boolean, is_writer boolean, exec_authenticated boolean, references_gate boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT
    p.proname::text,
    pg_catalog.pg_get_function_identity_arguments(p.oid)::text,
    (p.prosrc ~ '(board_items|project_boards|board_members|board_lifecycle_events|board_item_|board_drive_links|meeting_action_items)'),
    (upper(p.prosrc) ~ '(INSERT |UPDATE |DELETE )'),
    pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE'),
    (p.prosrc ~ 'rls_can_see_(initiative|board|item)|confidential')
  FROM pg_catalog.pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace
    AND p.prokind = 'f'
    AND p.prosecdef
    AND NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_depend d
      JOIN pg_catalog.pg_extension e ON e.oid = d.refobjid
      WHERE d.objid = p.oid AND d.deptype = 'e'
    )
  ORDER BY p.proname, p.oid;
$function$;

-- ---------------------------------------------------------------------------
-- 3. Canonical impact-hours (ADR-0100): single source for impact_hours across
--    homepage / public / admin / exec_portfolio_health / get_cycle_report.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_impact_hours_canonical(p_start_date date DEFAULT make_date((EXTRACT(year FROM now()))::integer, 1, 1), p_end_date date DEFAULT CURRENT_DATE)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    ROUND(SUM(COALESCE(e.duration_actual, e.duration_minutes)::numeric / 60.0), 1),
    0
  )
  FROM public.events e
  JOIN public.attendance a ON a.event_id = e.id
  WHERE e.date >= p_start_date
    AND e.date <= p_end_date
    AND a.present = true
    AND a.excused IS NOT TRUE
    AND NOT EXISTS (SELECT 1 FROM public.initiatives ci WHERE ci.id = e.initiative_id AND ci.visibility = 'confidential');
$function$;

-- ---------------------------------------------------------------------------
-- 4. Public platform stats (anon-facing): total_events excludes confidential.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_public_platform_stats()
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT json_build_object(
    -- #625 C1 (homepage instance): pre-onboarding cohort excluded -- "Pesquisadores ativos"
    -- counts only members OPERATING in the current cycle.
    'active_members', (
      SELECT COUNT(*) FROM public.members m
      WHERE m.is_active AND m.current_cycle_active
        AND NOT public.member_is_pre_onboarding(m.person_id, m.member_status)
    ),
    'total_tribes', (SELECT COUNT(*) FROM public.tribes WHERE is_active),
    'total_initiatives', (
      SELECT count(*) FROM public.initiatives
      WHERE status = 'active' AND legacy_tribe_id IS NULL
        AND visibility <> 'confidential'  -- #785 PR-3: aggregate excludes confidential
    ),
    -- Cycle 4: community verticals (ADR-0103) surfaced as a live counter.
    'total_verticals', (
      SELECT count(*) FROM public.initiatives
      WHERE kind = 'community_vertical' AND status = 'active'
        AND visibility <> 'confidential'  -- #785 PR-3: aggregate excludes confidential
    ),
    -- #481: canonical signed-chapter count.
    'total_chapters', (public.get_chapter_metrics()->>'signed')::int,
    'total_events', (SELECT COUNT(*) FROM public.events e WHERE e.date >= '2026-01-01' AND NOT EXISTS (SELECT 1 FROM public.initiatives ci WHERE ci.id = e.initiative_id AND ci.visibility = 'confidential')),
    'total_resources', (SELECT COUNT(*) FROM public.hub_resources WHERE is_active),
    -- #692: canonical retention = cohort-survival (members of cycle N present in N+1), last closed transition.
    -- Replaces the old snapshot ratio (current_cycle_active / ever-active) that read 68.1.
    'retention_rate', (public.get_member_retention_canonical() -> 'headline' ->> 'survival_pct')::numeric,
    -- R2 (Ciclo 4): canonical impact-hours, shared with the hero headline (single denominator).
    'impact_hours', round(public.get_impact_hours_canonical())
  );
$function$;

-- ---------------------------------------------------------------------------
-- 5. Public impact data (anon-facing /impact page): total_events + the two
--    attendance-hours sums exclude confidential events.
-- ---------------------------------------------------------------------------
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
    'total_events', (SELECT COUNT(*) FROM events e WHERE e.date >= '2026-03-01' AND NOT EXISTS (SELECT 1 FROM initiatives ci WHERE ci.id = e.initiative_id AND ci.visibility = 'confidential')),
    'total_attendance_hours', (
      SELECT COALESCE(SUM(e.duration_minutes / 60.0), 0)
      FROM attendance a JOIN events e ON e.id = a.event_id
      WHERE e.date >= '2026-03-01' AND a.present AND NOT EXISTS (SELECT 1 FROM initiatives ci WHERE ci.id = e.initiative_id AND ci.visibility = 'confidential')
    ),
    'impact_hours', (
      SELECT COALESCE(SUM(e.duration_minutes / 60.0), 0)
      FROM attendance a JOIN events e ON e.id = a.event_id
      WHERE a.present AND NOT EXISTS (SELECT 1 FROM initiatives ci WHERE ci.id = e.initiative_id AND ci.visibility = 'confidential')
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

-- ---------------------------------------------------------------------------
-- 6. _artia_safe_event_summary (any authenticated member): CONTENT leak — the
--    event_titles_sample + counts exclude confidential events.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._artia_safe_event_summary(p_start_date date, p_end_date date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT jsonb_build_object(
    'period', jsonb_build_object('start', p_start_date, 'end', p_end_date),
    'total_events', COUNT(*),
    'by_type', jsonb_object_agg(COALESCE(type, 'other'), type_count),
    'total_duration_hours', COALESCE(ROUND(SUM(duration_minutes)::numeric / 60, 1), 0),
    'event_titles_sample', (
      SELECT jsonb_agg(title ORDER BY date DESC)
      FROM public.events
      WHERE date BETWEEN p_start_date AND p_end_date
      AND NOT EXISTS (SELECT 1 FROM public.initiatives ci WHERE ci.id = initiative_id AND ci.visibility = 'confidential')
      LIMIT 10
    )
  )
  FROM (
    SELECT type, duration_minutes, COUNT(*) OVER (PARTITION BY type) AS type_count
    FROM public.events
    WHERE date BETWEEN p_start_date AND p_end_date
      AND NOT EXISTS (SELECT 1 FROM public.initiatives ci WHERE ci.id = initiative_id AND ci.visibility = 'confidential')
  ) e;
$function$;

-- ---------------------------------------------------------------------------
-- 7. exec_cross_initiative_comparison (manage_platform OR view_chapter_dashboards
--    = 15 non-GP): CONTENT leak — listed all initiatives incl the confidential
--    committee by title + leader + metrics. Exclude confidential from the list
--    and from kinds_present.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.exec_cross_initiative_comparison(p_kind text DEFAULT 'research_tribe'::text, p_cycle text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_cycle_start date := (SELECT cycle_start FROM public.cycles WHERE is_current = true LIMIT 1);
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT (public.can_by_member(v_caller_id, 'manage_platform')
          OR public.can_by_member(v_caller_id, 'view_chapter_dashboards')) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform or view_chapter_dashboards permission';
  END IF;

  SELECT jsonb_build_object(
    'initiatives', (
      SELECT jsonb_agg(row_obj ORDER BY sort_kind, sort_tribe, sort_title)
      FROM (
        SELECT
          i.kind AS sort_kind,
          COALESCE(t.id, 9999) AS sort_tribe,
          i.title AS sort_title,
          jsonb_build_object(
            'initiative_id', i.id,
            'initiative_kind', i.kind,
            'initiative_title', i.title,
            'tribe_id', t.id,
            'tribe_name', t.name,
            'quadrant', t.quadrant_name,
            'leader', (
              SELECT m.name FROM public.members m
              WHERE m.id = COALESCE(
                t.leader_member_id,
                (SELECT em.id
                 FROM public.engagements en
                 JOIN public.members em ON em.person_id = en.person_id
                 WHERE en.initiative_id = i.id
                   AND en.status = 'active'
                   AND en.kind ~ '(coordinator|owner|leader|manager)'
                 ORDER BY en.created_at ASC
                 LIMIT 1)
              )
            ),
            'member_count', public.get_initiative_roster_count(i.id),
            'members_inactive_30d', (
              SELECT COUNT(*) FROM public.members m
              WHERE m.id IN (
                  SELECT member_id FROM public.v_initiative_roster
                  WHERE initiative_id = i.id AND member_id IS NOT NULL
                )
                AND m.id NOT IN (
                  SELECT DISTINCT a.member_id FROM public.attendance a
                  JOIN public.events ev ON ev.id = a.event_id
                  WHERE ev.date >= (current_date - 30) AND ev.date <= CURRENT_DATE
                    AND ev.initiative_id = i.id  -- p194 GAP-194.A: strict scope (PM Option A)
                )
            ),
            'total_cards', (
              SELECT COUNT(*) FROM public.board_items bi
              JOIN public.project_boards pb ON pb.id = bi.board_id
              WHERE pb.initiative_id = i.id
            ),
            'cards_completed', (
              SELECT COUNT(*) FROM public.board_items bi
              JOIN public.project_boards pb ON pb.id = bi.board_id
              WHERE pb.initiative_id = i.id
                AND bi.status IN ('done','approved','published')
            ),
            'articles_submitted', (
              SELECT COUNT(*) FROM public.board_lifecycle_events ble
              JOIN public.board_items bi ON bi.id = ble.item_id
              JOIN public.project_boards pb ON pb.id = bi.board_id
              WHERE pb.initiative_id = i.id
                AND ble.action = 'submission'
            ),
            'attendance_rate', CASE WHEN t.id IS NOT NULL THEN COALESCE((public.get_attendance_engagement_summary('tribe', t.id) ->> 'avg_rate')::numeric, 0) ELSE NULL END,
            'total_hours', (
              SELECT COALESCE(SUM(ev.duration_minutes / 60.0), 0)
              FROM public.attendance a JOIN public.events ev ON ev.id = a.event_id
              WHERE a.member_id IN (
                SELECT member_id FROM public.v_initiative_roster
                WHERE initiative_id = i.id AND member_id IS NOT NULL
              )
              AND ev.date >= v_cycle_start AND ev.date <= CURRENT_DATE
              AND ev.initiative_id = i.id  -- p194 GAP-192.C: strict scope (PM Option B)
            ),
            'meetings_count', (
              SELECT COUNT(*) FROM public.events ev
              WHERE ev.initiative_id = i.id
                AND ev.date >= v_cycle_start AND ev.date <= CURRENT_DATE
            ),
            'total_xp', (
              SELECT COALESCE(SUM(gp.points), 0) FROM public.gamification_points gp
              WHERE gp.member_id IN (
                SELECT member_id FROM public.v_initiative_roster
                WHERE initiative_id = i.id AND member_id IS NOT NULL
              )
            ),
            'avg_xp', (
              SELECT COALESCE(ROUND(AVG(sub.total)::numeric, 1), 0)
              FROM (
                SELECT SUM(gp.points) AS total
                FROM public.gamification_points gp
                WHERE gp.member_id IN (
                  SELECT member_id FROM public.v_initiative_roster
                  WHERE initiative_id = i.id AND member_id IS NOT NULL
                )
                GROUP BY gp.member_id
              ) sub
            ),
            'last_meeting_date', (
              SELECT MAX(ev.date) FROM public.events ev
              WHERE ev.initiative_id = i.id AND ev.date <= CURRENT_DATE
            ),
            'days_since_last_meeting', (
              SELECT EXTRACT(DAY FROM now() - MAX(ev.date)::timestamp)::int
              FROM public.events ev
              WHERE ev.initiative_id = i.id AND ev.date <= CURRENT_DATE
            )
          ) AS row_obj
        FROM public.initiatives i
        LEFT JOIN public.tribes t ON t.id = i.legacy_tribe_id
        WHERE (p_kind IS NULL OR i.kind = p_kind)
          AND i.visibility <> 'confidential'  -- #932: exclude confidential initiative from cross-initiative list
      ) src
    ),
    'kinds_present', (
      SELECT array_to_json(ARRAY(SELECT DISTINCT i.kind FROM public.initiatives i WHERE i.visibility <> 'confidential' ORDER BY i.kind))::jsonb
    ),
    'generated_at', now()
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 8. get_cycle_report (view_internal_analytics OR view_aggregate_analytics =
--    12 non-GP): CONTENT leak — the boards section listed every active board by
--    name incl the confidential board title. Exclude confidential board from the
--    boards list and confidential events from the event total.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_cycle_report(p_cycle integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT (public.can_by_member(v_caller_id, 'view_internal_analytics') OR public.can_by_member(v_caller_id, 'view_aggregate_analytics')) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  v_result := jsonb_build_object(
    'cycle', p_cycle,
    'generated_at', now(),
    'members', (SELECT jsonb_build_object(
      'total', count(*),
      'active', (SELECT count(*) FROM public.v_active_members),
      'observers', count(*) FILTER (WHERE member_status = 'observer'),
      'alumni', count(*) FILTER (WHERE member_status = 'alumni'),
      'by_role', (SELECT coalesce(jsonb_object_agg(operational_role, cnt), '{}') FROM (SELECT operational_role, count(*) as cnt FROM public.v_active_members GROUP BY operational_role) r)
    ) FROM public.members),
    'tribes', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id, 'name', t.name,
      'member_count', (SELECT count(*) FROM public.members WHERE tribe_id = t.id AND is_active),
      'board_progress', (SELECT CASE WHEN count(*) = 0 THEN 0 ELSE round(100.0 * count(*) FILTER (WHERE bi.status = 'done') / count(*)) END FROM public.project_boards pb JOIN public.initiatives i ON i.id = pb.initiative_id JOIN public.board_items bi ON bi.board_id = pb.id WHERE i.legacy_tribe_id = t.id AND bi.status != 'archived')
    ) ORDER BY t.id), '[]') FROM public.tribes t WHERE t.is_active),
    'events', (SELECT jsonb_build_object(
      'total', count(*),
      'total_impact_hours', (SELECT * FROM public.get_homepage_stats())->'impact_hours'
    ) FROM public.events e WHERE e.date >= '2026-01-01' AND NOT public.is_confidential_initiative(e.initiative_id)),
    'boards', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', pb.id, 'title', pb.board_name,
      'total_items', (SELECT count(*) FROM public.board_items WHERE board_id = pb.id AND status != 'archived'),
      'done_items', (SELECT count(*) FROM public.board_items WHERE board_id = pb.id AND status = 'done'),
      'progress', (SELECT CASE WHEN count(*) = 0 THEN 0 ELSE round(100.0 * count(*) FILTER (WHERE status = 'done') / count(*)) END FROM public.board_items WHERE board_id = pb.id AND status != 'archived')
    )), '[]') FROM public.project_boards pb WHERE pb.is_active AND NOT public.is_confidential_board(pb.id)),
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
$function$;

NOTIFY pgrst, 'reload schema';
