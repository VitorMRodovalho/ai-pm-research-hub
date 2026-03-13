-- ═══════════════════════════════════════════════════════════════
-- W94 Sprint 1: comms_channel_config table for API token storage
-- Stores OAuth/API credentials per social channel with expiry tracking
-- ═══════════════════════════════════════════════════════════════

-- 1. Channel config table
CREATE TABLE IF NOT EXISTS public.comms_channel_config (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  channel text UNIQUE NOT NULL,           -- 'youtube', 'linkedin', 'instagram'
  api_key text,                           -- YouTube API key (non-expiring)
  oauth_token text,                       -- LinkedIn/Instagram OAuth token
  oauth_refresh_token text,               -- For automatic refresh if available
  token_expires_at timestamptz,           -- Token expiration date
  last_sync_at timestamptz,               -- Last successful sync
  sync_status text DEFAULT 'active'       -- 'active', 'token_expired', 'error'
    CHECK (sync_status IN ('active', 'token_expired', 'error')),
  config jsonb DEFAULT '{}',              -- channel_id, page_id, etc.
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

COMMENT ON TABLE public.comms_channel_config IS
  'W94: API credentials and sync config per social media channel (YouTube, LinkedIn, Instagram)';

-- 2. RLS — admin only (tokens are sensitive)
ALTER TABLE public.comms_channel_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "comms_channel_config_admin" ON public.comms_channel_config
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members
      WHERE auth_id = auth.uid()
        AND (
          is_superadmin
          OR operational_role IN ('manager', 'deputy_manager')
          OR designations && ARRAY['comms_leader']
        )
    )
  );

-- 3. Updated_at trigger
CREATE OR REPLACE FUNCTION public.set_comms_channel_config_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_comms_channel_config_updated_at
  BEFORE UPDATE ON public.comms_channel_config
  FOR EACH ROW EXECUTE FUNCTION set_comms_channel_config_updated_at();

-- 4. Admin RPC: manage channel config (upsert / delete)
CREATE OR REPLACE FUNCTION public.admin_manage_comms_channel(
  p_action text,                -- 'upsert', 'delete'
  p_channel text,
  p_api_key text DEFAULT NULL,
  p_oauth_token text DEFAULT NULL,
  p_oauth_refresh_token text DEFAULT NULL,
  p_token_expires_at timestamptz DEFAULT NULL,
  p_config jsonb DEFAULT '{}'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
  v_is_admin boolean;
  v_designations text[];
BEGIN
  SELECT operational_role, is_superadmin, designations
  INTO v_role, v_is_admin, v_designations
  FROM public.members WHERE auth_id = auth.uid();

  IF NOT (
    v_is_admin
    OR v_role IN ('manager', 'deputy_manager')
    OR v_designations && ARRAY['comms_leader']
  ) THEN
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
        api_key = COALESCE(EXCLUDED.api_key, comms_channel_config.api_key),
        oauth_token = COALESCE(EXCLUDED.oauth_token, comms_channel_config.oauth_token),
        oauth_refresh_token = COALESCE(EXCLUDED.oauth_refresh_token, comms_channel_config.oauth_refresh_token),
        token_expires_at = COALESCE(EXCLUDED.token_expires_at, comms_channel_config.token_expires_at),
        config = COALESCE(EXCLUDED.config, comms_channel_config.config),
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

GRANT EXECUTE ON FUNCTION public.admin_manage_comms_channel(text, text, text, text, text, timestamptz, jsonb) TO authenticated;

-- 5. RPC to check token expiry status (used by alert system + UI)
CREATE OR REPLACE FUNCTION public.comms_channel_status()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
BEGIN
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
    'config', c.config
  ) ORDER BY c.channel)
  INTO v_result
  FROM public.comms_channel_config c;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION public.comms_channel_status() TO authenticated;

-- 6. Seed default channel entries (no tokens yet — admin will configure)
INSERT INTO public.comms_channel_config (channel, config) VALUES
  ('youtube', '{"channel_handle": "@nucleo_ia", "channel_url": "https://www.youtube.com/@nucleo_ia"}'::jsonb),
  ('instagram', '{"profile": "nucleo.ia.gp", "profile_url": "https://www.instagram.com/nucleo.ia.gp"}'::jsonb),
  ('linkedin', '{"company_slug": "nucleo-ia", "company_url": "https://www.linkedin.com/company/nucleo-ia/"}'::jsonb)
ON CONFLICT (channel) DO NOTHING;
