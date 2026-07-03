-- =====================================================================================
-- #883 Onda A — get_comms_to_adoption_funnel security hygiene (audit docs/strategy/883_...).
--
-- A1. REVOKE anon: the function already fail-closes for anon (auth.uid() NULL → Unauthorized),
--     but the leftover anon EXECUTE grant is noise (and would surface in the #965 anon-SECDEF
--     ratchet). Revoked for hygiene.
-- A2. Gate coherence: the funnel is a card of the /admin/comms dashboard, but it gated on
--     view_internal_analytics/manage_platform/view_aggregate_analytics only — EXCLUDING the
--     comms team, who see every OTHER reader on that page (all gated by can_view_comms_analytics).
--     Add `OR public.can_view_comms_analytics()` so the comms team sees its own comms→adoption
--     funnel. Body otherwise byte-identical (Phase C).
-- =====================================================================================
CREATE OR REPLACE FUNCTION public.get_comms_to_adoption_funnel(p_period_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id   uuid;
  v_period      interval := (greatest(p_period_days, 1) || ' days')::interval;
  v_since_ts    timestamptz := now() - v_period;
  v_since_date  date        := current_date - greatest(p_period_days, 1);
  v_social      jsonb;
  v_engagement  jsonb;
  v_apps        jsonb;
  v_approved    jsonb;
  v_top_content jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF NOT (public.can_by_member(v_caller_id, 'view_internal_analytics')
       OR public.can_by_member(v_caller_id, 'manage_platform')
       OR public.can_by_member(v_caller_id, 'view_aggregate_analytics')
       OR public.can_view_comms_analytics()) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- ── Stage 1: Social reach (latest snapshot per channel within period) ──
  WITH latest_per_channel AS (
    SELECT DISTINCT ON (channel)
      channel, audience, reach, engagement_rate, metric_date
    FROM public.comms_metrics_daily
    WHERE metric_date >= v_since_date
    ORDER BY channel, metric_date DESC
  ),
  period_reach AS (
    SELECT channel, sum(reach) AS reach_sum
    FROM public.comms_metrics_daily
    WHERE metric_date >= v_since_date
    GROUP BY channel
  )
  SELECT jsonb_build_object(
    'total_audience_latest', coalesce((SELECT sum(audience) FROM latest_per_channel), 0),
    'total_reach_period',    coalesce((SELECT sum(reach_sum) FROM period_reach), 0),
    'by_channel', coalesce(jsonb_agg(jsonb_build_object(
      'channel',           l.channel,
      'audience_latest',   l.audience,
      'reach_period',      coalesce(p.reach_sum, 0),
      'engagement_rate',   l.engagement_rate
    ) ORDER BY l.audience DESC NULLS LAST), '[]'::jsonb)
  ) INTO v_social
  FROM latest_per_channel l
  LEFT JOIN period_reach p ON p.channel = l.channel;

  -- ── Stage 2: Site engagement on content pages (logged-in proxy) ──
  WITH grouped AS (
    SELECT
      CASE
        WHEN first_page LIKE '/blog/%' THEN 'blog'
        WHEN first_page LIKE '/cpmai%' THEN 'cpmai'
        WHEN first_page LIKE '/trail%' THEN 'trail'
        WHEN first_page LIKE '/presentations%' THEN 'presentations'
        WHEN first_page LIKE '/gamification%' THEN 'gamification'
        WHEN first_page = '/' OR first_page LIKE '/en/%' OR first_page LIKE '/es/%' THEN 'home'
        ELSE 'other'
      END AS landing_group,
      member_id
    FROM public.member_activity_sessions
    WHERE session_date >= v_since_date
  ),
  agg AS (
    SELECT landing_group, count(*) AS sessions, count(DISTINCT member_id) AS members
    FROM grouped
    GROUP BY landing_group
  )
  SELECT jsonb_build_object(
    'content_sessions',      coalesce((SELECT sum(sessions) FROM agg WHERE landing_group IN ('blog','cpmai','trail','presentations','gamification')), 0),
    'content_unique_members', coalesce((SELECT sum(members)  FROM agg WHERE landing_group IN ('blog','cpmai','trail','presentations','gamification')), 0),
    'home_sessions',         coalesce((SELECT sessions FROM agg WHERE landing_group='home'), 0),
    'home_unique_members',   coalesce((SELECT members  FROM agg WHERE landing_group='home'), 0),
    'by_landing_group', coalesce(jsonb_agg(jsonb_build_object(
      'group',           a.landing_group,
      'sessions',        a.sessions,
      'unique_members',  a.members
    ) ORDER BY a.sessions DESC), '[]'::jsonb)
  ) INTO v_engagement
  FROM agg a;

  -- ── Stage 3: Applications submitted in period ──
  SELECT jsonb_build_object(
    'total',     count(*),
    'via_vep',   count(*) FILTER (WHERE referral_source = 'vep'),
    'other',     count(*) FILTER (WHERE referral_source IS DISTINCT FROM 'vep'),
    'by_role',   coalesce(jsonb_object_agg(role_applied, role_count), '{}'::jsonb)
  ) INTO v_apps
  FROM (
    SELECT
      role_applied,
      count(*) AS role_count,
      referral_source
    FROM public.selection_applications
    WHERE created_at >= v_since_ts
    GROUP BY role_applied, referral_source
  ) a
  GROUP BY ();

  IF v_apps IS NULL THEN
    v_apps := jsonb_build_object('total', 0, 'via_vep', 0, 'other', 0, 'by_role', '{}'::jsonb);
  END IF;

  -- ── Stage 4: Approved + converted in period ──
  SELECT jsonb_build_object(
    'total',         count(*),
    'approved',      count(*) FILTER (WHERE status = 'approved'),
    'converted',     count(*) FILTER (WHERE status = 'converted'),
    'approval_rate', CASE
      WHEN (SELECT count(*) FROM public.selection_applications WHERE created_at >= v_since_ts) > 0
      THEN round(count(*)::numeric * 100.0 / (SELECT count(*) FROM public.selection_applications WHERE created_at >= v_since_ts), 1)
      ELSE NULL
    END
  ) INTO v_approved
  FROM public.selection_applications
  WHERE status IN ('approved', 'converted')
    AND updated_at >= v_since_ts;

  -- ── Top content (engagement signal, NOT attribution) ──
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'channel',      m.channel,
    'media_type',   m.media_type,
    'permalink',    m.permalink,
    'caption_excerpt', left(coalesce(m.caption, ''), 80),
    'views',        m.views,
    'likes',        m.likes,
    'comments',     m.comments,
    'published_at', m.published_at
  ) ORDER BY (coalesce(m.likes,0) + coalesce(m.comments,0) + coalesce(m.views,0)) DESC), '[]'::jsonb)
  INTO v_top_content
  FROM (
    SELECT *
    FROM public.comms_media_items
    WHERE published_at >= v_since_ts
    ORDER BY (coalesce(likes,0) + coalesce(comments,0) + coalesce(views,0)) DESC
    LIMIT 6
  ) m;

  RETURN jsonb_build_object(
    'period_days',  p_period_days,
    'period_since', v_since_ts,
    'generated_at', now(),
    'caveat',       'Correlation, not attribution. Pre-login pageviews + UTM tracking infrastructure pending (Phase B backlog). PMI VEP external form does not pass UTM. Funnel reflects what is measurable today: post-login engagement + total application counts in period.',
    'stages', jsonb_build_object(
      'social_reach',    v_social,
      'site_engagement', v_engagement,
      'applications',    v_apps,
      'approved',        v_approved
    ),
    'top_content', v_top_content
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_comms_to_adoption_funnel(integer) FROM anon;
