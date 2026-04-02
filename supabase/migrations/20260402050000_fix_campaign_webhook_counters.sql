-- Fix P0 #28: Campaign webhook counters not syncing to campaign_sends
-- Bug: process_email_webhook updated campaign_recipients but never synced
-- aggregate counters (delivered_count, failed_count) on campaign_sends.
-- Fix: Added counter sync at end of RPC + backfilled existing data.

CREATE OR REPLACE FUNCTION process_email_webhook(p_resend_id text, p_event_type text, p_update_fields jsonb DEFAULT '{}'::jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_send_id uuid;
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

-- Backfill existing data
UPDATE campaign_sends cs SET
  delivered_count = sub.delivered,
  failed_count = sub.failed
FROM (
  SELECT send_id,
    count(*) FILTER (WHERE delivered = true) as delivered,
    count(*) FILTER (WHERE bounced_at IS NOT NULL) as failed
  FROM campaign_recipients
  GROUP BY send_id
) sub
WHERE cs.id = sub.send_id;

NOTIFY pgrst, 'reload schema';
