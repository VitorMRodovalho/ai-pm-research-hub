-- Onda 2 — FU-2 Slice B: redact the campaign-analytics per-recipient PII for chapter-restricted callers.
--
-- PM decision (2026-06-28): Slice B's org-wide aggregate dashboards (admin/all-tribes/cycle-report/
-- adoption/cross-initiative/event-attendance/tribe-dashboard/portfolio) are AGGREGATES (counts/rates),
-- not individual PII — LEAVE them visible to partner-chapter leaders (view_chapter_dashboards). The only
-- Slice B function that carries individual CONTACT PII is get_campaign_analytics: its per-send `recipients`
-- list exposes member_name + EMAIL (COALESCE(m.email, cr.external_email)) of every recipient, cross-chapter,
-- to any view_chapter_dashboards holder (the same org-scoped partner-chapter leaders as Slices A/C). That
-- is the same A1 contact-PII leak class. Redact the recipient list for chapter-restricted callers
-- (caller_chapter_scope() IS NOT NULL); GP/sede keep it. The funnel/rates/by_role aggregates stay for all.
--
-- exec_tribe_dashboard's member `list` was reviewed and intentionally LEFT: it exposes name + role + XP +
-- attendance_rate (roster + performance), NO contact PII — the same class Slice C deliberately left
-- (list_initiative_engagements). No seed/scope/ACL change. Cross-ref: #952 FU-2, handoff pt8, Slice C #954.

CREATE OR REPLACE FUNCTION public.get_campaign_analytics(p_send_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  -- ADR-0042: V4 catalog (manage_platform writes; view_chapter_dashboards reads)
  IF NOT (public.can_by_member(v_caller_id, 'manage_platform')
          OR public.can_by_member(v_caller_id, 'view_chapter_dashboards')) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform or view_chapter_dashboards permission';
  END IF;

  IF p_send_id IS NOT NULL THEN
    SELECT jsonb_build_object(
      'send', (
        SELECT jsonb_build_object(
          'id', cs.id, 'template_name', ct.name, 'subject', ct.subject,
          'sent_at', cs.sent_at, 'created_at', cs.created_at, 'status', cs.status
        )
        FROM campaign_sends cs JOIN campaign_templates ct ON ct.id = cs.template_id
        WHERE cs.id = p_send_id
      ),
      'funnel', jsonb_build_object(
        'total', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id),
        'delivered', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND (delivered_at IS NOT NULL OR delivered = true)),
        'opened', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND (opened_at IS NOT NULL OR opened = true)),
        'human_opened', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false),
        'bot_opened', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND (opened_at IS NOT NULL OR opened = true) AND bot_suspected = true),
        'clicked', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND clicked_at IS NOT NULL),
        'bounced', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND bounced_at IS NOT NULL),
        'complained', (SELECT count(*) FROM campaign_recipients WHERE send_id = p_send_id AND complained_at IS NOT NULL)
      ),
      'rates', jsonb_build_object(
        'delivery_rate', (
          SELECT ROUND(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true)::numeric / NULLIF(count(*), 0) * 100, 1)
          FROM campaign_recipients WHERE send_id = p_send_id
        ),
        'open_rate', (
          SELECT ROUND(count(*) FILTER (WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false)::numeric
            / NULLIF(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true), 0) * 100, 1)
          FROM campaign_recipients WHERE send_id = p_send_id
        ),
        'open_rate_total', (
          SELECT ROUND(count(*) FILTER (WHERE opened_at IS NOT NULL OR opened = true)::numeric
            / NULLIF(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true), 0) * 100, 1)
          FROM campaign_recipients WHERE send_id = p_send_id
        ),
        'click_rate', (
          SELECT ROUND(count(*) FILTER (WHERE clicked_at IS NOT NULL)::numeric
            / NULLIF(count(*) FILTER (WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false), 0) * 100, 1)
          FROM campaign_recipients WHERE send_id = p_send_id
        )
      ),
      -- FU-2 Slice B: the per-recipient list carries contact PII (member_name + email) of every recipient
      -- cross-chapter; redact it for chapter-restricted callers (partner-chapter leaders). GP/sede
      -- (caller_chapter_scope() IS NULL) keep it. The funnel/rates/by_role aggregates stay for everyone.
      'recipients', CASE WHEN public.caller_chapter_scope() IS NULL THEN (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'member_name', COALESCE(m.name, cr.external_name, ''),
          'email', COALESCE(m.email, cr.external_email, ''),
          'role', m.operational_role, 'tribe_name', t.name,
          'delivered', (cr.delivered_at IS NOT NULL OR cr.delivered = true),
          'opened', (cr.opened_at IS NOT NULL OR cr.opened = true),
          'open_count', cr.open_count, 'bot_suspected', cr.bot_suspected,
          'clicked', cr.clicked_at IS NOT NULL, 'click_count', cr.click_count,
          'bounced', cr.bounced_at IS NOT NULL, 'bounce_type', cr.bounce_type,
          'complained', cr.complained_at IS NOT NULL,
          'status', CASE
            WHEN cr.complained_at IS NOT NULL THEN 'complained'
            WHEN cr.bounced_at IS NOT NULL THEN 'bounced'
            WHEN cr.clicked_at IS NOT NULL THEN 'clicked'
            WHEN (cr.opened_at IS NOT NULL OR cr.opened = true) AND cr.bot_suspected = false THEN 'opened'
            WHEN (cr.opened_at IS NOT NULL OR cr.opened = true) AND cr.bot_suspected = true THEN 'bot_opened'
            WHEN cr.delivered_at IS NOT NULL OR cr.delivered = true THEN 'delivered'
            ELSE 'sent'
          END
        ) ORDER BY cr.delivered_at DESC NULLS LAST), '[]'::jsonb)
        FROM campaign_recipients cr
        LEFT JOIN members m ON m.id = cr.member_id
        LEFT JOIN tribes t ON t.id = public.get_member_tribe(m.id)
        WHERE cr.send_id = p_send_id
      ) ELSE '[]'::jsonb END,
      'by_role', (
        SELECT COALESCE(jsonb_agg(sub), '[]'::jsonb) FROM (
          SELECT jsonb_build_object(
            'role', COALESCE(m.operational_role, 'external'),
            'total', count(*),
            'delivered', count(*) FILTER (WHERE cr.delivered_at IS NOT NULL OR cr.delivered = true),
            'opened', count(*) FILTER (WHERE (cr.opened_at IS NOT NULL OR cr.opened = true) AND cr.bot_suspected = false),
            'bot_opened', count(*) FILTER (WHERE (cr.opened_at IS NOT NULL OR cr.opened = true) AND cr.bot_suspected = true),
            'clicked', count(*) FILTER (WHERE cr.clicked_at IS NOT NULL)
          ) AS sub
          FROM campaign_recipients cr LEFT JOIN members m ON m.id = cr.member_id
          WHERE cr.send_id = p_send_id
          GROUP BY COALESCE(m.operational_role, 'external')
        ) agg
      )
    ) INTO v_result;
  ELSE
    SELECT jsonb_build_object(
      'total_sends', (SELECT count(*) FROM campaign_sends WHERE status = 'sent'),
      'total_recipients', (SELECT count(*) FROM campaign_recipients),
      'total_delivered', (SELECT count(*) FROM campaign_recipients WHERE delivered_at IS NOT NULL OR delivered = true),
      'total_opened', (SELECT count(*) FROM campaign_recipients WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false),
      'total_opened_incl_bots', (SELECT count(*) FROM campaign_recipients WHERE opened_at IS NOT NULL OR opened = true),
      'total_bot_opens', (SELECT count(*) FROM campaign_recipients WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = true),
      'total_clicked', (SELECT count(*) FROM campaign_recipients WHERE clicked_at IS NOT NULL),
      'total_bounced', (SELECT count(*) FROM campaign_recipients WHERE bounced_at IS NOT NULL),
      'overall_rates', jsonb_build_object(
        'delivery_rate', (SELECT ROUND(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true)::numeric / NULLIF(count(*), 0) * 100, 1) FROM campaign_recipients),
        'open_rate', (SELECT ROUND(count(*) FILTER (WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false)::numeric / NULLIF(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true), 0) * 100, 1) FROM campaign_recipients),
        'open_rate_total', (SELECT ROUND(count(*) FILTER (WHERE opened_at IS NOT NULL OR opened = true)::numeric / NULLIF(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true), 0) * 100, 1) FROM campaign_recipients),
        'click_rate', (SELECT ROUND(count(*) FILTER (WHERE clicked_at IS NOT NULL)::numeric / NULLIF(count(*) FILTER (WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false), 0) * 100, 1) FROM campaign_recipients)
      ),
      'recent_sends', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'id', cs.id, 'template_name', ct.name, 'sent_at', cs.sent_at, 'created_at', cs.created_at,
          'total', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id),
          'delivered', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND (delivered_at IS NOT NULL OR delivered = true)),
          'opened', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false),
          'bot_opened', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND (opened_at IS NOT NULL OR opened = true) AND bot_suspected = true),
          'clicked', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND clicked_at IS NOT NULL),
          'bounced', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND bounced_at IS NOT NULL)
        ) ORDER BY cs.created_at DESC), '[]'::jsonb)
        FROM campaign_sends cs JOIN campaign_templates ct ON ct.id = cs.template_id
        WHERE cs.status = 'sent' LIMIT 20
      )
    ) INTO v_result;
  END IF;

  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
