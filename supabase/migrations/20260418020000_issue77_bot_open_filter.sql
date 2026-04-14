-- ============================================================================
-- Issue #77: Filter bot/scanner opens from campaign analytics
-- Adds bot detection to email open tracking:
--   1. bot_suspected flag + first_opened_at on campaign_recipients
--   2. Updated process_email_webhook to detect bots via timing + user_agent
--   3. Updated get_campaign_analytics to separate human vs bot opens
-- Rollback: ALTER TABLE campaign_recipients DROP COLUMN IF EXISTS bot_suspected,
--           DROP COLUMN IF EXISTS first_opened_at;
--           Then re-deploy original process_email_webhook + get_campaign_analytics.
-- ============================================================================

-- ══════════════════════════════════════════════
-- 1. Add bot detection columns to campaign_recipients
-- ══════════════════════════════════════════════

ALTER TABLE public.campaign_recipients
  ADD COLUMN IF NOT EXISTS bot_suspected boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS first_opened_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_user_agent text;

COMMENT ON COLUMN public.campaign_recipients.bot_suspected IS 'True if open was likely from email scanner (timing <30s or known bot UA)';
COMMENT ON COLUMN public.campaign_recipients.first_opened_at IS 'Timestamp of first email.opened webhook';
COMMENT ON COLUMN public.campaign_recipients.last_user_agent IS 'User-agent from most recent open event';

-- ══════════════════════════════════════════════
-- 2. Updated process_email_webhook with bot detection
-- ══════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.process_email_webhook(
  p_resend_id text,
  p_event_type text,
  p_update_fields jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_send_id uuid;
  v_delivered_at timestamptz;
  v_user_agent text;
  v_is_bot boolean := false;
  v_known_bot_patterns text[] := ARRAY[
    'GoogleImageProxy', 'YahooMailProxy', 'Outlook-iOS',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',  -- Generic scanner UA
    'python-requests', 'Go-http-client', 'curl',
    'Barracuda', 'ZScaler', 'Mimecast', 'Proofpoint',
    'MessageLabs', 'Symantec', 'FireEye', 'Trend Micro'
  ];
  v_pattern text;
BEGIN
  CASE p_event_type
    WHEN 'email.delivered' THEN
      UPDATE campaign_recipients SET
        delivered = true,
        delivered_at = COALESCE(delivered_at, now())
      WHERE resend_id = p_resend_id;

    WHEN 'email.opened' THEN
      -- Extract user_agent from update fields
      v_user_agent := p_update_fields->>'user_agent';

      -- Get delivery time for timing-based detection
      SELECT delivered_at INTO v_delivered_at
      FROM campaign_recipients WHERE resend_id = p_resend_id;

      -- Bot detection: timing (<30s after delivery)
      IF v_delivered_at IS NOT NULL
         AND (now() - v_delivered_at) < interval '30 seconds' THEN
        v_is_bot := true;
      END IF;

      -- Bot detection: known bot user-agent patterns
      IF v_user_agent IS NOT NULL THEN
        FOREACH v_pattern IN ARRAY v_known_bot_patterns LOOP
          IF v_user_agent ILIKE '%' || v_pattern || '%' THEN
            v_is_bot := true;
            EXIT;
          END IF;
        END LOOP;
      END IF;

      UPDATE campaign_recipients SET
        opened = true,
        opened_at = COALESCE(opened_at, now()),
        first_opened_at = COALESCE(first_opened_at, now()),
        open_count = open_count + 1,
        last_user_agent = COALESCE(v_user_agent, last_user_agent),
        bot_suspected = bot_suspected OR v_is_bot
      WHERE resend_id = p_resend_id;

    WHEN 'email.clicked' THEN
      -- A click is strong signal of human interaction — clear bot flag
      UPDATE campaign_recipients SET
        clicked_at = COALESCE(clicked_at, now()),
        click_count = click_count + 1,
        bot_suspected = false
      WHERE resend_id = p_resend_id;

    WHEN 'email.bounced' THEN
      UPDATE campaign_recipients SET
        bounced_at = COALESCE(bounced_at, now()),
        bounce_type = COALESCE(p_update_fields->>'bounce_type', 'unknown')
      WHERE resend_id = p_resend_id;

    WHEN 'email.complained' THEN
      UPDATE campaign_recipients SET
        complained_at = COALESCE(complained_at, now()),
        unsubscribed = true
      WHERE resend_id = p_resend_id;
  END CASE;

  -- Mark webhook event as processed
  UPDATE email_webhook_events SET processed = true
  WHERE resend_id = p_resend_id AND event_type = p_event_type
  AND processed = false;

  -- Sync aggregate counters on campaign_sends
  SELECT send_id INTO v_send_id FROM campaign_recipients WHERE resend_id = p_resend_id;
  IF v_send_id IS NOT NULL THEN
    UPDATE campaign_sends SET
      delivered_count = (SELECT count(*) FROM campaign_recipients WHERE send_id = v_send_id AND delivered = true),
      failed_count = (SELECT count(*) FROM campaign_recipients WHERE send_id = v_send_id AND bounced_at IS NOT NULL)
    WHERE id = v_send_id;
  END IF;
END;
$$;

-- ══════════════════════════════════════════════
-- 3. Updated get_campaign_analytics with human vs bot separation
-- ══════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_campaign_analytics(
  p_send_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  v_caller_id := auth.uid();
  IF NOT EXISTS (
    SELECT 1 FROM members WHERE auth_id = v_caller_id
    AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager'))
  ) THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  IF p_send_id IS NOT NULL THEN
    SELECT jsonb_build_object(
      'send', (
        SELECT jsonb_build_object(
          'id', cs.id,
          'template_name', ct.name,
          'subject', ct.subject,
          'sent_at', cs.sent_at,
          'created_at', cs.created_at,
          'status', cs.status
        )
        FROM campaign_sends cs
        JOIN campaign_templates ct ON ct.id = cs.template_id
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
          SELECT ROUND(
            count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true)::numeric
            / NULLIF(count(*), 0) * 100, 1
          ) FROM campaign_recipients WHERE send_id = p_send_id
        ),
        'open_rate', (
          SELECT ROUND(
            count(*) FILTER (WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false)::numeric
            / NULLIF(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true), 0) * 100, 1
          ) FROM campaign_recipients WHERE send_id = p_send_id
        ),
        'open_rate_total', (
          SELECT ROUND(
            count(*) FILTER (WHERE opened_at IS NOT NULL OR opened = true)::numeric
            / NULLIF(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true), 0) * 100, 1
          ) FROM campaign_recipients WHERE send_id = p_send_id
        ),
        'click_rate', (
          SELECT ROUND(
            count(*) FILTER (WHERE clicked_at IS NOT NULL)::numeric
            / NULLIF(count(*) FILTER (WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false), 0) * 100, 1
          ) FROM campaign_recipients WHERE send_id = p_send_id
        )
      ),
      'recipients', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'member_name', COALESCE(m.name, cr.external_name, ''),
          'email', COALESCE(m.email, cr.external_email, ''),
          'role', m.operational_role,
          'tribe_name', t.name,
          'delivered', (cr.delivered_at IS NOT NULL OR cr.delivered = true),
          'opened', (cr.opened_at IS NOT NULL OR cr.opened = true),
          'open_count', cr.open_count,
          'bot_suspected', cr.bot_suspected,
          'clicked', cr.clicked_at IS NOT NULL,
          'click_count', cr.click_count,
          'bounced', cr.bounced_at IS NOT NULL,
          'bounce_type', cr.bounce_type,
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
        LEFT JOIN tribes t ON t.id = m.tribe_id
        WHERE cr.send_id = p_send_id
      ),
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
          FROM campaign_recipients cr
          LEFT JOIN members m ON m.id = cr.member_id
          WHERE cr.send_id = p_send_id
          GROUP BY COALESCE(m.operational_role, 'external')
        ) agg
      )
    ) INTO v_result;
  ELSE
    -- AGGREGATE analytics (all sends)
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
        'delivery_rate', (
          SELECT ROUND(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true)::numeric / NULLIF(count(*), 0) * 100, 1)
          FROM campaign_recipients
        ),
        'open_rate', (
          SELECT ROUND(count(*) FILTER (WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false)::numeric
            / NULLIF(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true), 0) * 100, 1)
          FROM campaign_recipients
        ),
        'open_rate_total', (
          SELECT ROUND(count(*) FILTER (WHERE opened_at IS NOT NULL OR opened = true)::numeric
            / NULLIF(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true), 0) * 100, 1)
          FROM campaign_recipients
        ),
        'click_rate', (
          SELECT ROUND(count(*) FILTER (WHERE clicked_at IS NOT NULL)::numeric
            / NULLIF(count(*) FILTER (WHERE (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false), 0) * 100, 1)
          FROM campaign_recipients
        )
      ),
      'recent_sends', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'id', cs.id,
          'template_name', ct.name,
          'sent_at', cs.sent_at,
          'created_at', cs.created_at,
          'total', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id),
          'delivered', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND (delivered_at IS NOT NULL OR delivered = true)),
          'opened', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND (opened_at IS NOT NULL OR opened = true) AND bot_suspected = false),
          'bot_opened', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND (opened_at IS NOT NULL OR opened = true) AND bot_suspected = true),
          'clicked', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND clicked_at IS NOT NULL),
          'bounced', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND bounced_at IS NOT NULL)
        ) ORDER BY cs.created_at DESC), '[]'::jsonb)
        FROM campaign_sends cs
        JOIN campaign_templates ct ON ct.id = cs.template_id
        WHERE cs.status = 'sent'
        LIMIT 20
      )
    ) INTO v_result;
  END IF;

  RETURN v_result;
END;
$$;

-- ══════════════════════════════════════════════
-- 4. Backfill: flag existing opens that look like bots
-- ══════════════════════════════════════════════

-- Flag opens that happened within 30s of delivery
UPDATE campaign_recipients SET
  bot_suspected = true,
  first_opened_at = opened_at
WHERE opened_at IS NOT NULL
  AND delivered_at IS NOT NULL
  AND (opened_at - delivered_at) < interval '30 seconds';

-- Set first_opened_at for non-bot opens that don't have it yet
UPDATE campaign_recipients SET
  first_opened_at = opened_at
WHERE opened_at IS NOT NULL
  AND first_opened_at IS NULL;

NOTIFY pgrst, 'reload schema';
