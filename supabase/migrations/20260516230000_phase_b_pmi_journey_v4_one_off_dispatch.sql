-- =====================================================================
-- Migration: phase_b_pmi_journey_v4_one_off_dispatch
-- Date: 2026-04-29 (slot 20260516230000)
-- Author: Claude Code (autonomous p81 follow-up)
--
-- Purpose: Auto-dispatch one-off transactional emails by:
--   1. Storing variables in audience_filter.variables (send-campaign EF
--      now reads this for {{key}} replacement — patched 2026-04-29)
--   2. Invoking send-campaign EF via net.http_post after INSERT
--
-- Without this, campaign_sends rows from campaign_send_one_off would sit
-- forever in 'pending_delivery' (no cron picks them up; send-campaign EF
-- requires explicit POST).
-- =====================================================================

CREATE OR REPLACE FUNCTION public.campaign_send_one_off(
  p_template_slug text,
  p_to_email text,
  p_variables jsonb DEFAULT '{}'::jsonb,
  p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_template_id uuid;
  v_send_id uuid;
  v_system_sender_id uuid;
  v_recipient_lang text;
  v_service_role_key text;
  v_dispatch_request_id bigint;
BEGIN
  SELECT id INTO v_template_id FROM public.campaign_templates WHERE slug = p_template_slug;
  IF v_template_id IS NULL THEN
    RAISE EXCEPTION 'Template not found: %', p_template_slug USING ERRCODE = 'no_data_found';
  END IF;

  SELECT m.id INTO v_system_sender_id
  FROM public.members m
  WHERE public.can_by_member(m.id, 'manage_platform') = true
    AND m.is_active = true
  ORDER BY
    CASE m.operational_role
      WHEN 'manager' THEN 1
      WHEN 'gp_lead' THEN 2
      WHEN 'deputy_manager' THEN 3
      WHEN 'co_gp' THEN 4
      ELSE 99
    END,
    m.created_at
  LIMIT 1;

  IF v_system_sender_id IS NULL THEN
    RAISE EXCEPTION 'No GP-tier active member found to attribute system one-off send';
  END IF;

  v_recipient_lang := COALESCE(p_metadata->>'language', p_variables->>'lang', 'pt');

  INSERT INTO public.campaign_sends (
    id, template_id, sent_by, audience_filter, status, recipient_count, scheduled_at
  ) VALUES (
    gen_random_uuid(),
    v_template_id,
    v_system_sender_id,
    jsonb_build_object(
      'type', 'transactional',
      'one_off', true,
      'source', COALESCE(p_metadata->>'source', 'system'),
      'variables', p_variables
    ),
    'pending_delivery',
    1,
    NULL
  )
  RETURNING id INTO v_send_id;

  INSERT INTO public.campaign_recipients (
    send_id, external_email, external_name, language
  ) VALUES (
    v_send_id,
    p_to_email,
    p_metadata->>'recipient_name',
    v_recipient_lang
  );

  -- Async dispatch: invoke send-campaign EF (handles Resend delivery + {{var}} render)
  BEGIN
    SELECT decrypted_secret INTO v_service_role_key
    FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

    IF v_service_role_key IS NOT NULL THEN
      SELECT net.http_post(
        url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/send-campaign',
        body := jsonb_build_object('send_id', v_send_id),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_service_role_key
        )
      ) INTO v_dispatch_request_id;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'send-campaign EF dispatch failed: % (send_id=%)', SQLERRM, v_send_id;
  END;

  RETURN jsonb_build_object(
    'send_id', v_send_id,
    'system_sender_id', v_system_sender_id,
    'template_slug', p_template_slug,
    'to_email', p_to_email,
    'status', 'pending_delivery',
    'mode', 'one_off_transactional',
    'dispatch_request_id', v_dispatch_request_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.campaign_send_one_off(text, text, jsonb, jsonb) TO service_role;

NOTIFY pgrst, 'reload schema';
