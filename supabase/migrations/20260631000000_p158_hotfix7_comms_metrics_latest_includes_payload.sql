-- p158 hotfix #7: comms_metrics_latest_by_channel — return payload jsonb
--
-- PM live test 2026-05-14: /admin/comms YouTube card shows "Vídeos: --" despite DB having
-- 29 video items in comms_media_items + payload.videoCount=37 in comms_metrics_daily.
-- Frontend (comms.astro line 570) reads yt.payload?.videoCount — but the RPC's RETURNS TABLE
-- doesn't include payload, so yt.payload is undefined → falls through to '--' fallback.
--
-- Same gap affects Instagram media_count (line 399) and any other payload-derived KPIs that
-- the RPC currently strips.
--
-- Fix: add payload jsonb as last returned column. STABLE + SECURITY DEFINER preserved.
-- Sort order unchanged.

DROP FUNCTION IF EXISTS public.comms_metrics_latest_by_channel(integer);

CREATE OR REPLACE FUNCTION public.comms_metrics_latest_by_channel(p_days integer DEFAULT 14)
RETURNS TABLE(
  metric_date  date,
  channel      text,
  audience     bigint,
  reach        bigint,
  engagement   numeric,
  leads        bigint,
  source       text,
  updated_at   timestamptz,
  payload      jsonb
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  with latest as (
    select max(metric_date) as d
    from public.comms_metrics_daily
  )
  select
    c.metric_date,
    c.channel,
    c.audience,
    c.reach,
    c.engagement_rate as engagement,
    c.leads,
    c.source,
    c.updated_at,
    c.payload
  from public.comms_metrics_daily c
  where c.metric_date >= coalesce((select d from latest) - greatest(p_days, 1) + 1, current_date)
  order by c.metric_date desc, c.reach desc nulls last, c.channel asc;
$function$;

GRANT EXECUTE ON FUNCTION public.comms_metrics_latest_by_channel(integer) TO authenticated;

NOTIFY pgrst, 'reload schema';
