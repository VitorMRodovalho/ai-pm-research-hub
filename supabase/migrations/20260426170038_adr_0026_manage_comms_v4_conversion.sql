-- ADR-0026 (Accepted): manage_comms V4 action
-- Phase B'' V3→V4 conversion of admin_manage_comms_channel.
-- See docs/adr/ADR-0026-manage-comms-v4-action.md
--
-- PM ratified Q1-Q4 (2026-04-26 p59):
--   Q1 (sponsors com manage_comms?) — NÃO
--   Q2 (chapter_board × liaison?) — NÃO agora (adiar até comms_channel_config tem chapter_id)
--   Q3 (migrar admin_send_campaign + comms_check_token_expiry?) — NÃO
--   Q4 (timing?) — p59 mesmo
--
-- Privilege expansion safety check (verified pre-apply):
--   V3 grant: 3 members (Vitor, Fabricio, Mayanna)
--   V4 grant proposed: 2 members (Vitor, Fabricio)
--   Would gain: 0
--   Would lose: 1 (Mayanna Duarte) — DRIFT correction
--     Mayanna has V3 designation comms_leader but no V4 engagement
--     volunteer×comms_leader. Per ADR-0026 documented as expected
--     drift correction — V3 designation cache was not migrated to
--     engagement. If Mayanna is a real comms operator, PM creates
--     engagement post-migration. If not, drift was wrong.

-- ============================================================
-- 1. Adicionar action manage_comms ao engagement_kind_permissions
-- ============================================================
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope)
VALUES
  ('volunteer', 'co_gp',          'manage_comms', 'organization'),
  ('volunteer', 'manager',        'manage_comms', 'organization'),
  ('volunteer', 'deputy_manager', 'manage_comms', 'organization'),
  ('volunteer', 'comms_leader',   'manage_comms', 'organization')
ON CONFLICT (kind, role, action) DO NOTHING;

-- ============================================================
-- 2. Convert admin_manage_comms_channel
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_manage_comms_channel(text, text, text, text, text, timestamp with time zone, jsonb);
CREATE OR REPLACE FUNCTION public.admin_manage_comms_channel(
  p_action text,
  p_channel text,
  p_api_key text,
  p_oauth_token text,
  p_oauth_refresh_token text,
  p_token_expires_at timestamp with time zone,
  p_config jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_member_id uuid;
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'authentication_required');
  END IF;

  -- V4 gate (replaces V3 mix of role + designation check)
  IF NOT public.can_by_member(v_caller_member_id, 'manage_comms') THEN
    RETURN jsonb_build_object('success', false, 'error', 'permission_denied');
  END IF;

  IF p_channel IS NULL OR p_channel = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'missing_channel');
  END IF;

  CASE p_action
    WHEN 'upsert' THEN
      INSERT INTO public.comms_channel_config (
        channel, api_key, oauth_token, oauth_refresh_token,
        token_expires_at, config, sync_status
      ) VALUES (
        lower(trim(p_channel)), p_api_key, p_oauth_token, p_oauth_refresh_token,
        p_token_expires_at, p_config,
        CASE
          WHEN p_token_expires_at IS NOT NULL AND p_token_expires_at < now() THEN 'token_expired'
          ELSE 'active'
        END
      )
      ON CONFLICT (channel) DO UPDATE SET
        api_key = COALESCE(EXCLUDED.api_key, public.comms_channel_config.api_key),
        oauth_token = COALESCE(EXCLUDED.oauth_token, public.comms_channel_config.oauth_token),
        oauth_refresh_token = COALESCE(EXCLUDED.oauth_refresh_token, public.comms_channel_config.oauth_refresh_token),
        token_expires_at = COALESCE(EXCLUDED.token_expires_at, public.comms_channel_config.token_expires_at),
        config = COALESCE(EXCLUDED.config, public.comms_channel_config.config),
        sync_status = CASE
          WHEN EXCLUDED.token_expires_at IS NOT NULL AND EXCLUDED.token_expires_at < now() THEN 'token_expired'
          ELSE 'active'
        END;
      RETURN jsonb_build_object('success', true);

    WHEN 'delete' THEN
      DELETE FROM public.comms_channel_config WHERE channel = lower(trim(p_channel));
      RETURN jsonb_build_object('success', true);

    ELSE
      RETURN jsonb_build_object('success', false, 'error', 'invalid_action');
  END CASE;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_manage_comms_channel(text, text, text, text, text, timestamp with time zone, jsonb) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_manage_comms_channel(text, text, text, text, text, timestamp with time zone, jsonb) IS
  'Phase B'' V4 conversion (ADR-0026, p59): manage_comms gate via can_by_member. Was V3 (is_superadmin OR manager/deputy_manager OR designation comms_leader).';

NOTIFY pgrst, 'reload schema';
