-- #1470 (follow-up da Onda 3 / #1464): rejanelar os DOIS leitores de janela MOVEL de
-- gamification_points por COALESCE(occurred_at, created_at) (data do fato), nao created_at.
--
-- A #1464 (mig 480) rejanelou toda a atribuicao de CICLO por occurred_at, mas deixou de fora
-- (por escopo) dois leitores de janela movel:
--   get_weekly_member_digest.xp_delta  -> "XP dos ultimos 7 dias"
--   get_gamification_category_activity -> "eventos na janela now()-p_window_days / 7d"
-- ambos janelavam por created_at. O mesmo flush historico que motivou a #1464 (a EF
-- sync-attendance-points inserindo presenca antiga com created_at = now() do run) inflava
-- essas janelas: uma presenca de 2025 marcada hoje contava como "XP ganho esta semana".
-- Sonda ao vivo (2026-07-24): 790/1020 pts (77%) do xp_delta semanal eram backfill historico.
--
-- Decisao de produto ratificada: a semantica pretendida e "atividades que ACONTECERAM na
-- janela" -> janelar por COALESCE(occurred_at, created_at), igual a mig 480/#1464.
-- last_award (get_gamification_category_activity) permanece max(created_at): e o carimbo de
-- CONCESSAO (auditoria "quando foi lancado"), fora do escopo das janelas de atividade.

CREATE OR REPLACE FUNCTION public.get_weekly_member_digest(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_is_self boolean;
  v_member_tribe_id integer;
  v_window_start timestamptz := date_trunc('day', now()) - interval '7 days';
  v_extended_window timestamptz := date_trunc('day', now()) - interval '14 days';
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  v_is_self := (v_caller_id = p_member_id);

  IF NOT v_is_self AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: can only read own digest or requires manage_member permission';
  END IF;

  SELECT tribe_id INTO v_member_tribe_id FROM public.members WHERE id = p_member_id;

  SELECT jsonb_build_object(
    'member_id', p_member_id,
    'generated_at', now(),
    'window_start', v_window_start,
    'sections', jsonb_build_object(
      'cards', jsonb_build_object(
        'this_week_pending', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', bi.id, 'title', bi.title, 'status', bi.status,
            'due_date', bi.due_date, 'board_name', pb.board_name,
            'initiative_title', i.title,
            'days_overdue', GREATEST(0, CURRENT_DATE - bi.due_date)
          ) ORDER BY bi.due_date ASC)
          FROM public.board_items bi
          LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
          LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
          WHERE bi.assignee_id = p_member_id
            AND bi.status NOT IN ('done', 'archived')
            AND bi.due_date BETWEEN CURRENT_DATE - INTERVAL '7 days' AND CURRENT_DATE
        ), '[]'::jsonb),
        'next_week_due', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', bi.id, 'title', bi.title, 'status', bi.status,
            'due_date', bi.due_date, 'board_name', pb.board_name,
            'initiative_title', i.title
          ) ORDER BY bi.due_date ASC)
          FROM public.board_items bi
          LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
          LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
          WHERE bi.assignee_id = p_member_id
            AND bi.status NOT IN ('done', 'archived')
            AND bi.due_date > CURRENT_DATE
            AND bi.due_date <= CURRENT_DATE + INTERVAL '7 days'
        ), '[]'::jsonb),
        'overdue_7plus', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', bi.id, 'title', bi.title, 'status', bi.status,
            'due_date', bi.due_date, 'board_name', pb.board_name,
            'initiative_title', i.title,
            'days_overdue', CURRENT_DATE - bi.due_date
          ) ORDER BY bi.due_date ASC)
          FROM public.board_items bi
          LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
          LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
          WHERE bi.assignee_id = p_member_id
            AND bi.status NOT IN ('done', 'archived')
            AND bi.due_date < CURRENT_DATE - INTERVAL '7 days'
        ), '[]'::jsonb),
        -- NEW p95 #99 1B: assignment_new notifications shown in cards section
        'new_assignments', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', n.id, 'title', n.title, 'body', n.body,
            'created_at', n.created_at, 'link', n.link
          ) ORDER BY n.created_at DESC)
          FROM public.notifications n
          WHERE n.recipient_id = p_member_id
            AND n.delivery_mode = 'digest_weekly'
            AND n.digest_delivered_at IS NULL
            AND n.type = 'assignment_new'
            AND n.created_at >= v_extended_window
        ), '[]'::jsonb)
      ),

      'engagements_new', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', n.id, 'type', n.type, 'title', n.title,
          'created_at', n.created_at,
          'source_type', n.source_type, 'source_id', n.source_id,
          'link', n.link
        ) ORDER BY n.created_at DESC)
        FROM public.notifications n
        WHERE n.recipient_id = p_member_id
          AND n.delivery_mode = 'digest_weekly'
          AND n.digest_delivered_at IS NULL
          AND n.type IN ('engagement_welcome', 'engagement_added', 'volunteer_agreement_signed')
          AND n.created_at >= v_window_start
      ), '[]'::jsonb),

      'events_upcoming', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', e.id, 'title', e.title, 'date', e.date,
          'type', e.type, 'initiative_id', e.initiative_id,
          'initiative_title', i.title
        ) ORDER BY e.date ASC)
        FROM public.events e
        LEFT JOIN public.initiatives i ON i.id = e.initiative_id
        WHERE e.date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '7 days'
          AND (
            i.legacy_tribe_id = v_member_tribe_id
            OR e.type IN ('plenaria', 'webinar', 'workshop_geral')
          )
      ), '[]'::jsonb),

      -- NEW p95 #99 1A: attendance_reminder pending notifications visible in dedicated section
      'attendance_reminders_pending', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', n.id, 'title', n.title, 'body', n.body,
          'created_at', n.created_at, 'link', n.link
        ) ORDER BY n.created_at DESC)
        FROM public.notifications n
        WHERE n.recipient_id = p_member_id
          AND n.delivery_mode = 'digest_weekly'
          AND n.digest_delivered_at IS NULL
          AND n.type = 'attendance_reminder'
          AND n.created_at >= v_extended_window
      ), '[]'::jsonb),

      'publications_new', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', ps.id, 'title', ps.title,
          'submission_date', ps.submission_date,
          'primary_author_id', ps.primary_author_id
        ) ORDER BY ps.submission_date DESC)
        FROM public.publication_submissions ps
        WHERE ps.status = 'published'::public.submission_status
          AND ps.submission_date >= v_window_start::date
      ), '[]'::jsonb),

      'broadcasts', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', n.id, 'title', n.title, 'body', n.body,
          'created_at', n.created_at, 'link', n.link
        ) ORDER BY n.created_at DESC)
        FROM public.notifications n
        WHERE n.recipient_id = p_member_id
          AND n.delivery_mode = 'digest_weekly'
          AND n.digest_delivered_at IS NULL
          AND n.type = 'tribe_broadcast'
          AND n.created_at >= v_window_start
      ), '[]'::jsonb),

      'governance_pending', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', n.id, 'type', n.type, 'title', n.title,
          'created_at', n.created_at, 'link', n.link
        ) ORDER BY n.created_at DESC)
        FROM public.notifications n
        WHERE n.recipient_id = p_member_id
          AND n.delivery_mode = 'digest_weekly'
          AND n.digest_delivered_at IS NULL
          AND n.type IN ('governance_vote_reminder', 'ip_ratification_gate_pending', 'change_request_pending')
          AND n.created_at >= v_window_start
      ), '[]'::jsonb),

      'achievements', jsonb_build_object(
        'certificates_issued', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', c.id, 'title', c.title, 'type', c.type,
            'issued_at', c.issued_at
          ) ORDER BY c.issued_at DESC)
          FROM public.certificates c
          WHERE c.member_id = p_member_id
            AND c.issued_at >= v_window_start
        ), '[]'::jsonb),
        -- #1470: XP da janela movel por data do FATO (occurred_at), nao data de lancamento
        -- (created_at) — o backfill historico nao infla mais o "XP desta semana".
        'xp_delta', COALESCE((
          SELECT sum(gp.points)::int
          FROM public.gamification_points gp
          WHERE gp.member_id = p_member_id
            AND COALESCE(gp.occurred_at, gp.created_at) >= v_window_start
        ), 0)
      )
    ),
    -- p95 #99 1A+1B: include attendance_reminder + assignment_new in consumed set (extended window)
    'consumed_notification_ids', COALESCE((
      SELECT jsonb_agg(n.id)
      FROM public.notifications n
      WHERE n.recipient_id = p_member_id
        AND n.delivery_mode = 'digest_weekly'
        AND n.digest_delivered_at IS NULL
        AND (
          n.created_at >= v_window_start
          OR (n.type IN ('attendance_reminder', 'assignment_new') AND n.created_at >= v_extended_window)
        )
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_gamification_category_activity(p_window_days integer DEFAULT 30)
 RETURNS TABLE(slug text, pillar text, display_name text, base_points integer, trigger_source text, active boolean, total_events bigint, unique_members bigint, last_window_events bigint, last_7d_events bigint, last_award timestamp with time zone, status text, is_orphan boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event';
  END IF;

  RETURN QUERY
  WITH agg AS (
    SELECT
      gp.category,
      count(*)::bigint AS total_events,
      count(DISTINCT gp.member_id)::bigint AS unique_members,
      -- #1470: janela movel de atividade por data do FATO (occurred_at), nao created_at.
      count(*) FILTER (WHERE COALESCE(gp.occurred_at, gp.created_at) >= now() - (p_window_days || ' days')::interval)::bigint AS last_window_events,
      count(*) FILTER (WHERE COALESCE(gp.occurred_at, gp.created_at) >= now() - INTERVAL '7 days')::bigint AS last_7d_events,
      -- last_award permanece o carimbo de concessao (auditoria "quando foi lancado").
      max(gp.created_at) AS last_award
    FROM public.gamification_points gp
    GROUP BY gp.category
  )
  SELECT
    r.slug,
    r.pillar,
    COALESCE(r.display_name_i18n->>'pt-BR', r.slug) AS display_name,
    r.base_points,
    r.trigger_source,
    r.active,
    COALESCE(a.total_events, 0) AS total_events,
    COALESCE(a.unique_members, 0) AS unique_members,
    COALESCE(a.last_window_events, 0) AS last_window_events,
    COALESCE(a.last_7d_events, 0) AS last_7d_events,
    a.last_award,
    CASE
      WHEN NOT r.active THEN 'inactive'
      WHEN COALESCE(a.total_events, 0) = 0 THEN 'never'
      WHEN COALESCE(a.last_window_events, 0) = 0 THEN 'idle'
      WHEN COALESCE(a.last_7d_events, 0) = 0 THEN 'warm'
      ELSE 'healthy'
    END AS status,
    false AS is_orphan
  FROM public.gamification_rules r
  LEFT JOIN agg a ON a.category = r.slug
  UNION ALL
  SELECT
    a.category AS slug,
    'orphan'::text AS pillar,
    a.category AS display_name,
    NULL::int AS base_points,
    NULL::text AS trigger_source,
    NULL::boolean AS active,
    a.total_events,
    a.unique_members,
    a.last_window_events,
    a.last_7d_events,
    a.last_award,
    'orphan'::text AS status,
    true AS is_orphan
  FROM agg a
  WHERE NOT EXISTS (SELECT 1 FROM public.gamification_rules r WHERE r.slug = a.category)
  ORDER BY status, pillar NULLS LAST, slug;
END;
$function$;

-- PostgREST schema reload (RPC surface changed)
NOTIFY pgrst, 'reload schema';
