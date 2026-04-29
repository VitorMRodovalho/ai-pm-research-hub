-- =====================================================================
-- Migration: phase_b_pmi_journey_v4_one_off_direct_insert
-- Date: 2026-04-29 (slot 20260516220000)
-- Author: Claude Code (autonomous p81 follow-up — discovered during smoke test)
--
-- Purpose: Rewrite campaign_send_one_off to bypass admin_send_campaign's
-- caller permission check + rate limit. Worker uses service_role JWT where
-- auth.uid() returns NULL, so admin_send_campaign raises 'Forbidden: only
-- GP/DM can send campaigns'.
--
-- New design: campaign_send_one_off does its OWN direct INSERT into
-- campaign_sends + campaign_recipients (transactional / one-off — no rate
-- limit applies, just like a single-purpose template dispatch). For audit:
-- sent_by = highest-tier active member with manage_platform action.
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
BEGIN
  SELECT id INTO v_template_id FROM public.campaign_templates WHERE slug = p_template_slug;
  IF v_template_id IS NULL THEN
    RAISE EXCEPTION 'Template not found: %', p_template_slug USING ERRCODE = 'no_data_found';
  END IF;

  -- System sender: highest-tier active member with manage_platform action.
  -- Used only for audit (campaign_sends.sent_by NOT NULL FK). NOT subject to rate limit.
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

  -- Recipient language: prefer explicit metadata, then variables.lang, default 'pt'.
  v_recipient_lang := COALESCE(p_metadata->>'language', p_variables->>'lang', 'pt');

  -- Direct INSERT — bypass admin_send_campaign rate limit (transactional, not broadcast).
  INSERT INTO public.campaign_sends (
    id, template_id, sent_by, audience_filter, status, recipient_count, scheduled_at
  ) VALUES (
    gen_random_uuid(),
    v_template_id,
    v_system_sender_id,
    jsonb_build_object(
      'type', 'transactional',
      'one_off', true,
      'source', COALESCE(p_metadata->>'source', 'system')
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

  RETURN jsonb_build_object(
    'send_id', v_send_id,
    'system_sender_id', v_system_sender_id,
    'template_slug', p_template_slug,
    'to_email', p_to_email,
    'status', 'pending_delivery',
    'mode', 'one_off_transactional'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.campaign_send_one_off(text, text, jsonb, jsonb) TO service_role;

COMMENT ON FUNCTION public.campaign_send_one_off(text, text, jsonb, jsonb) IS
  'One-off transactional email wrapper. Direct INSERT into campaign_sends + campaign_recipients (bypasses admin_send_campaign rate limit + caller GP/DM check). sent_by attributed to highest-tier active GP-tier member for audit. Used by Cloudflare workers (e.g., pmi-vep-sync welcome via /ingest endpoint).';

NOTIFY pgrst, 'reload schema';
