-- Fix: campaign_sends status CHECK missing 'pending_delivery'
-- The admin_send_campaign RPC inserts status='pending_delivery' for immediate sends,
-- but the CHECK constraint only allowed draft/scheduled/sending/sent/failed.
ALTER TABLE public.campaign_sends DROP CONSTRAINT campaign_sends_status_check;
ALTER TABLE public.campaign_sends ADD CONSTRAINT campaign_sends_status_check
  CHECK (status = ANY (ARRAY['draft', 'pending_delivery', 'scheduled', 'sending', 'sent', 'failed']));
