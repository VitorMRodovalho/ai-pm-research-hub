-- p171 #13 — /admin/gamification recent activity panel (P162 backlog gap)
--
-- Adiciona painel "Atividade Recente por categoria" em /admin/gamification
-- para detectar canários: regras (slugs) ativas que NUNCA receberam award
-- ou idle há > 30d. Sinal precoce de seed config errado pós-deploy.
--
-- Auth: caller deve ter `manage_event` (admin.gamification holders =
-- manager + deputy_manager + comms_leader — todos têm manage_event V4).
--
-- Status taxonomia:
--   never    — rule active=true, points_count=0 (CANARY VERMELHO)
--   idle     — last_30d=0 AND points_count>0 (CANARY ÂMBAR)
--   warm     — last_30d>0 AND last_7d=0 (verde claro)
--   healthy  — last_7d>0 (verde forte)
--   inactive — rule active=false (cinza, filtered out por default)
--
-- Inclui também categorias órfãs (em gamification_points mas SEM rule
-- correspondente) para detectar drift inverso (legacy slug com points
-- chegando mas sem rule wiring → bonus_points bucket).
--
-- Rollback:
--   DROP FUNCTION public.get_gamification_category_activity(int);

CREATE OR REPLACE FUNCTION public.get_gamification_category_activity(
  p_window_days int DEFAULT 30
)
RETURNS TABLE(
  slug text,
  pillar text,
  display_name text,
  base_points int,
  trigger_source text,
  active boolean,
  total_events bigint,
  unique_members bigint,
  last_window_events bigint,
  last_7d_events bigint,
  last_award timestamptz,
  status text,
  is_orphan boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
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
      count(*) FILTER (WHERE gp.created_at >= now() - (p_window_days || ' days')::interval)::bigint AS last_window_events,
      count(*) FILTER (WHERE gp.created_at >= now() - INTERVAL '7 days')::bigint AS last_7d_events,
      max(gp.created_at) AS last_award
    FROM public.gamification_points gp
    GROUP BY gp.category
  )
  -- Rows from rules table (active OR inactive)
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
  -- Orphan rows: categories in points but no matching rule
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

COMMENT ON FUNCTION public.get_gamification_category_activity(int) IS
  'p171 #13 — Atividade recente por categoria de XP. Detecta rules nunca acionadas (never) e idle (>30d). Status: never/idle/warm/healthy/inactive/orphan. Auth: manage_event.';

GRANT EXECUTE ON FUNCTION public.get_gamification_category_activity(int) TO authenticated;

NOTIFY pgrst, 'reload schema';
