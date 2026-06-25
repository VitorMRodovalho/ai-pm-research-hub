-- #883 PR-2: gate the ungated comms read RPCs + split comms_channel_status (config jsonb → managers only).
-- Read tier = view_internal_analytics (governance audience) OR manage_comms (write tier) OR comms designation (comms team).
-- Mirrors get_comms_to_adoption_funnel's existing view_internal_analytics gate (ADR-0007 / ADR-0011 / V4_AUTHORITY_MODEL Path 1+2).
-- Public repo: shipped quietly (no public issue) per #869 no-pre-fix-disclosure precedent.

-- 1) Read-tier helper. Path 1 (reuse view_internal_analytics/manage_comms) + Path 2 (comms designation for the
--    comms team, who are workgroup_member-scoped and do not fit a (kind,role) seed). NO engagement_kind_permissions change.
CREATE OR REPLACE FUNCTION public.can_view_comms_analytics()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id    uuid;
  v_desig text[];
BEGIN
  SELECT id, designations INTO v_id, v_desig
  FROM public.members WHERE auth_id = auth.uid();
  IF v_id IS NULL THEN
    RETURN false;
  END IF;
  RETURN public.can_by_member(v_id, 'view_internal_analytics')
      OR public.can_by_member(v_id, 'manage_comms')
      OR (v_desig && ARRAY['comms_leader','comms_member']);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.can_view_comms_analytics() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_view_comms_analytics() TO authenticated;

-- 2) comms_metrics_latest_by_channel — add read-tier gate (SQL fn: WHERE-guard → 0 rows if unauthorized).
--    Also fixes ACL creep: a prior DROP+CREATE (p158 payload hotfix) reset EXECUTE to PUBLIC/anon.
CREATE OR REPLACE FUNCTION public.comms_metrics_latest_by_channel(p_days integer DEFAULT 14)
RETURNS TABLE(metric_date date, channel text, audience bigint, reach bigint, engagement numeric, leads bigint, source text, updated_at timestamptz, payload jsonb)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
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
  where public.can_view_comms_analytics()
    and c.metric_date >= coalesce((select d from latest) - greatest(p_days, 1) + 1, current_date)
  order by c.metric_date desc, c.reach desc nulls last, c.channel asc;
$$;
REVOKE EXECUTE ON FUNCTION public.comms_metrics_latest_by_channel(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.comms_metrics_latest_by_channel(integer) TO authenticated;

-- 3) comms_top_media — add read-tier gate (plpgsql: early return []).
CREATE OR REPLACE FUNCTION public.comms_top_media(p_channel text DEFAULT NULL::text, p_days integer DEFAULT 30, p_limit integer DEFAULT 10)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_result jsonb;
BEGIN
  IF NOT public.can_view_comms_analytics() THEN
    RETURN '[]'::jsonb;
  END IF;
  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.engagement_score DESC), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT m.channel, m.external_id, m.media_type,
      LEFT(m.caption, 120) as caption, m.permalink, m.thumbnail_url,
      m.published_at, m.likes, m.comments, m.shares, m.saves, m.reach, m.views,
      (COALESCE(m.likes,0) + COALESCE(m.comments,0)*2 + COALESCE(m.shares,0)*3 + COALESCE(m.saves,0)*2) as engagement_score
    FROM public.comms_media_items m
    WHERE (p_channel IS NULL OR m.channel = p_channel)
      AND m.published_at >= NOW() - (p_days || ' days')::interval
    ORDER BY (COALESCE(m.likes,0) + COALESCE(m.comments,0)*2 + COALESCE(m.shares,0)*3 + COALESCE(m.saves,0)*2) DESC
    LIMIT p_limit
  ) r;
  RETURN v_result;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.comms_top_media(text, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.comms_top_media(text, integer, integer) TO authenticated;

-- 4) comms_channel_status — read-tier gate + SPLIT: token-health to read tier; config jsonb (infra IDs/URNs)
--    only to manage_comms holders. Closes the config-jsonb leak to all authenticated (incl. pre-onboarding guests).
CREATE OR REPLACE FUNCTION public.comms_channel_status()
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result     jsonb;
  v_id         uuid;
  v_is_manager boolean;
BEGIN
  SELECT id INTO v_id FROM public.members WHERE auth_id = auth.uid();
  IF v_id IS NULL OR NOT public.can_view_comms_analytics() THEN
    RETURN '[]'::jsonb;
  END IF;
  v_is_manager := public.can_by_member(v_id, 'manage_comms');

  SELECT jsonb_agg(jsonb_build_object(
    'channel', c.channel,
    'sync_status', c.sync_status,
    'last_sync_at', c.last_sync_at,
    'token_expires_at', c.token_expires_at,
    'has_api_key', c.api_key IS NOT NULL,
    'has_oauth_token', c.oauth_token IS NOT NULL,
    'days_until_expiry', CASE
      WHEN c.token_expires_at IS NULL THEN NULL
      ELSE EXTRACT(day FROM c.token_expires_at - now())::int
    END,
    -- infra config (org URN, page/app/user IDs) only to manage_comms holders; NULL for the read tier
    'config', CASE WHEN v_is_manager THEN c.config ELSE NULL END
  ) ORDER BY c.channel)
  INTO v_result
  FROM public.comms_channel_config c;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.comms_channel_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.comms_channel_status() TO authenticated;

-- 5) comms_acknowledge_alert — was UNGATED (any authenticated could dismiss token alerts). Gate on manage_comms (D2-07).
CREATE OR REPLACE FUNCTION public.comms_acknowledge_alert(p_alert_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid;
  v_id  uuid;
BEGIN
  SELECT auth.uid() INTO v_uid;
  SELECT id INTO v_id FROM public.members WHERE auth_id = v_uid;
  IF v_id IS NULL OR NOT public.can_by_member(v_id, 'manage_comms') THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthorized');
  END IF;

  UPDATE public.comms_token_alerts
  SET acknowledged = true, acknowledged_by = v_uid
  WHERE id = p_alert_id AND acknowledged = false;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'alert_not_found');
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.comms_acknowledge_alert(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.comms_acknowledge_alert(uuid) TO authenticated;

-- 6) D2-05 belt-and-suspenders: keep comms_executive_kpis locked away from broad roles (idempotent).
REVOKE EXECUTE ON FUNCTION public.comms_executive_kpis() FROM PUBLIC, anon, authenticated;
