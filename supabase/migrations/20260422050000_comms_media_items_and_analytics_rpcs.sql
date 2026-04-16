-- ═══════════════════════════════════════════════════════════════
-- Social Media Analytics: per-post media items + analytics RPCs
-- Supports: Instagram media, YouTube videos, LinkedIn posts
-- Rollback: DROP TABLE comms_media_items CASCADE; DROP FUNCTION comms_top_media, comms_executive_kpis;
-- ═══════════════════════════════════════════════════════════════

-- 1. Per-post media items table
CREATE TABLE IF NOT EXISTS public.comms_media_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  channel text NOT NULL,                    -- 'instagram', 'youtube', 'linkedin'
  external_id text NOT NULL,                -- IG media_id or YT video_id
  media_type text,                          -- 'IMAGE', 'VIDEO', 'CAROUSEL_ALBUM', 'REEL', 'SHORTS'
  caption text,
  permalink text,
  thumbnail_url text,
  published_at timestamptz,
  -- metrics snapshot (updated each sync)
  likes int DEFAULT 0,
  comments int DEFAULT 0,
  shares int DEFAULT 0,
  saves int DEFAULT 0,
  reach int,
  views int,                                -- YouTube views / IG video views
  -- metadata
  payload jsonb DEFAULT '{}',
  synced_at timestamptz DEFAULT now(),
  UNIQUE(channel, external_id)
);

COMMENT ON TABLE public.comms_media_items IS
  'Per-post social media items with engagement metrics, synced from Instagram/YouTube/LinkedIn APIs';

ALTER TABLE public.comms_media_items ENABLE ROW LEVEL SECURITY;

-- Read access for comms team (metrics are not PII)
CREATE POLICY "comms_media_items_read" ON public.comms_media_items
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members
      WHERE auth_id = auth.uid()
        AND (
          is_superadmin
          OR operational_role IN ('manager', 'deputy_manager')
          OR designations && ARRAY['comms_leader', 'comms_member']
        )
    )
  );

-- Write access for admin/comms_leader only (sync writes via service role anyway)
CREATE POLICY "comms_media_items_write" ON public.comms_media_items
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members
      WHERE auth_id = auth.uid()
        AND (
          is_superadmin
          OR operational_role IN ('manager', 'deputy_manager')
          OR designations && ARRAY['comms_leader']
        )
    )
  );

-- 2. Top content RPC
CREATE OR REPLACE FUNCTION public.comms_top_media(
  p_channel text DEFAULT NULL,
  p_days int DEFAULT 30,
  p_limit int DEFAULT 10
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.engagement_score DESC), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      m.channel,
      m.external_id,
      m.media_type,
      LEFT(m.caption, 120) as caption,
      m.permalink,
      m.thumbnail_url,
      m.published_at,
      m.likes,
      m.comments,
      m.shares,
      m.saves,
      m.reach,
      m.views,
      (COALESCE(m.likes, 0) + COALESCE(m.comments, 0) * 2 + COALESCE(m.shares, 0) * 3 + COALESCE(m.saves, 0) * 2) as engagement_score
    FROM public.comms_media_items m
    WHERE (p_channel IS NULL OR m.channel = p_channel)
      AND m.published_at >= NOW() - (p_days || ' days')::interval
    ORDER BY (COALESCE(m.likes, 0) + COALESCE(m.comments, 0) * 2 + COALESCE(m.shares, 0) * 3 + COALESCE(m.saves, 0) * 2) DESC
    LIMIT p_limit
  ) r;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.comms_top_media(text, int, int) TO authenticated;

-- 3. Executive KPIs RPC
CREATE OR REPLACE FUNCTION public.comms_executive_kpis()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
  v_channels jsonb;
  v_total_audience bigint := 0;
  v_weekly_reach bigint := 0;
  v_avg_engagement numeric := 0;
  v_growth_pct numeric := 0;
  v_this_week_audience bigint := 0;
  v_last_week_audience bigint := 0;
BEGIN
  -- Latest audience per channel
  WITH latest_per_channel AS (
    SELECT DISTINCT ON (channel)
      channel, audience, reach, engagement_rate, metric_date, payload
    FROM public.comms_metrics_daily
    ORDER BY channel, metric_date DESC
  )
  SELECT
    COALESCE(SUM(audience), 0),
    COALESCE(jsonb_agg(jsonb_build_object(
      'channel', channel,
      'audience', audience,
      'reach', reach,
      'engagement_rate', engagement_rate,
      'date', metric_date
    )), '[]'::jsonb)
  INTO v_total_audience, v_channels
  FROM latest_per_channel;

  -- Weekly reach (sum of reach in last 7 days)
  SELECT COALESCE(SUM(reach), 0) INTO v_weekly_reach
  FROM public.comms_metrics_daily
  WHERE metric_date >= CURRENT_DATE - 7;

  -- Average engagement (weighted by audience)
  WITH eng AS (
    SELECT DISTINCT ON (channel)
      channel, engagement_rate, audience
    FROM public.comms_metrics_daily
    WHERE engagement_rate IS NOT NULL
    ORDER BY channel, metric_date DESC
  )
  SELECT CASE WHEN SUM(audience) > 0
    THEN SUM(engagement_rate * audience) / SUM(audience)
    ELSE 0
  END INTO v_avg_engagement FROM eng;

  -- Growth: compare latest audience vs 7 days ago
  v_this_week_audience := v_total_audience;
  SELECT COALESCE(SUM(sub.audience), 0) INTO v_last_week_audience
  FROM (
    SELECT DISTINCT ON (channel) channel, audience
    FROM public.comms_metrics_daily
    WHERE metric_date <= CURRENT_DATE - 7
    ORDER BY channel, metric_date DESC
  ) sub;

  IF v_last_week_audience > 0 THEN
    v_growth_pct := ROUND(((v_this_week_audience - v_last_week_audience)::numeric / v_last_week_audience) * 100, 1);
  END IF;

  -- Media counts
  v_result := jsonb_build_object(
    'total_audience', v_total_audience,
    'weekly_reach', v_weekly_reach,
    'avg_engagement', ROUND(v_avg_engagement, 4),
    'audience_growth_pct', v_growth_pct,
    'channel_breakdown', v_channels,
    'media_count', (SELECT COUNT(*) FROM public.comms_media_items)::int,
    'top_media_count', (SELECT COUNT(*) FROM public.comms_media_items WHERE published_at >= NOW() - interval '30 days')::int
  );

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.comms_executive_kpis() TO authenticated;
