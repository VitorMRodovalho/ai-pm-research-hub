-- W-CAMP-ANALYTICS: Resend Webhook Analytics
-- Adds email delivery tracking columns + webhook events table + RPCs
-- Webhook URL for Resend dashboard: https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/resend-webhook

-- ══════════════════════════════════════════════
-- 1. Tracking columns on campaign_recipients
-- ══════════════════════════════════════════════

ALTER TABLE public.campaign_recipients
  ADD COLUMN IF NOT EXISTS resend_id text,
  ADD COLUMN IF NOT EXISTS delivered_at timestamptz,
  ADD COLUMN IF NOT EXISTS opened_at timestamptz,
  ADD COLUMN IF NOT EXISTS open_count integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS clicked_at timestamptz,
  ADD COLUMN IF NOT EXISTS click_count integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS bounced_at timestamptz,
  ADD COLUMN IF NOT EXISTS bounce_type text,
  ADD COLUMN IF NOT EXISTS complained_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_campaign_recipients_resend_id
  ON public.campaign_recipients(resend_id);

COMMENT ON COLUMN public.campaign_recipients.resend_id IS 'Resend email ID for webhook correlation';

-- ══════════════════════════════════════════════
-- 2. Webhook events log table (audit/debug)
-- ══════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.email_webhook_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  resend_id text NOT NULL,
  event_type text NOT NULL,
  recipient_email text,
  payload jsonb DEFAULT '{}',
  processed boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.email_webhook_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Superadmin can view webhook events"
  ON public.email_webhook_events
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.members WHERE auth_id = auth.uid() AND is_superadmin = true
  ));

CREATE INDEX IF NOT EXISTS idx_webhook_events_resend_id
  ON public.email_webhook_events(resend_id);
CREATE INDEX IF NOT EXISTS idx_webhook_events_type
  ON public.email_webhook_events(event_type, created_at DESC);

-- ══════════════════════════════════════════════
-- 3. RPC: process_email_webhook (idempotent)
-- ══════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.process_email_webhook(
  p_resend_id text,
  p_event_type text,
  p_update_fields jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  CASE p_event_type
    WHEN 'email.delivered' THEN
      UPDATE campaign_recipients SET
        delivered = true,
        delivered_at = COALESCE(delivered_at, now())
      WHERE resend_id = p_resend_id;

    WHEN 'email.opened' THEN
      UPDATE campaign_recipients SET
        opened = true,
        opened_at = COALESCE(opened_at, now()),
        open_count = open_count + 1
      WHERE resend_id = p_resend_id;

    WHEN 'email.clicked' THEN
      UPDATE campaign_recipients SET
        clicked_at = COALESCE(clicked_at, now()),
        click_count = click_count + 1
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
END;
$$;

COMMENT ON FUNCTION public.process_email_webhook IS 'Processes Resend webhook events, updating campaign_recipients tracking columns idempotently.';

-- ══════════════════════════════════════════════
-- 4. RPC: get_campaign_analytics (admin only)
-- ══════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_campaign_analytics(
  p_send_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
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
    -- SPECIFIC SEND analytics
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
            count(*) FILTER (WHERE opened_at IS NOT NULL OR opened = true)::numeric
            / NULLIF(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true), 0) * 100, 1
          ) FROM campaign_recipients WHERE send_id = p_send_id
        ),
        'click_rate', (
          SELECT ROUND(
            count(*) FILTER (WHERE clicked_at IS NOT NULL)::numeric
            / NULLIF(count(*) FILTER (WHERE opened_at IS NOT NULL OR opened = true), 0) * 100, 1
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
          'clicked', cr.clicked_at IS NOT NULL,
          'click_count', cr.click_count,
          'bounced', cr.bounced_at IS NOT NULL,
          'bounce_type', cr.bounce_type,
          'complained', cr.complained_at IS NOT NULL,
          'status', CASE
            WHEN cr.complained_at IS NOT NULL THEN 'complained'
            WHEN cr.bounced_at IS NOT NULL THEN 'bounced'
            WHEN cr.clicked_at IS NOT NULL THEN 'clicked'
            WHEN cr.opened_at IS NOT NULL OR cr.opened = true THEN 'opened'
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
            'opened', count(*) FILTER (WHERE cr.opened_at IS NOT NULL OR cr.opened = true),
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
      'total_opened', (SELECT count(*) FROM campaign_recipients WHERE opened_at IS NOT NULL OR opened = true),
      'total_clicked', (SELECT count(*) FROM campaign_recipients WHERE clicked_at IS NOT NULL),
      'total_bounced', (SELECT count(*) FROM campaign_recipients WHERE bounced_at IS NOT NULL),
      'overall_rates', jsonb_build_object(
        'delivery_rate', (
          SELECT ROUND(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true)::numeric / NULLIF(count(*), 0) * 100, 1)
          FROM campaign_recipients
        ),
        'open_rate', (
          SELECT ROUND(count(*) FILTER (WHERE opened_at IS NOT NULL OR opened = true)::numeric / NULLIF(count(*) FILTER (WHERE delivered_at IS NOT NULL OR delivered = true), 0) * 100, 1)
          FROM campaign_recipients
        ),
        'click_rate', (
          SELECT ROUND(count(*) FILTER (WHERE clicked_at IS NOT NULL)::numeric / NULLIF(count(*) FILTER (WHERE opened_at IS NOT NULL OR opened = true), 0) * 100, 1)
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
          'opened', (SELECT count(*) FROM campaign_recipients WHERE send_id = cs.id AND (opened_at IS NOT NULL OR opened = true)),
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

COMMENT ON FUNCTION public.get_campaign_analytics IS 'Campaign email analytics: delivery funnel, open/click rates, by role. Uses Resend webhook data.';
