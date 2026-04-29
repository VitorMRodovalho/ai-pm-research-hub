-- p82 CBGPL launch: candidate self-service profile completion
-- Adds credly_url column + token-auth RPC for portal to update LinkedIn / Credly / phone(WhatsApp).
-- Pre-fills are visible in payload from consume_onboarding_token (existing fields surfaced).

ALTER TABLE selection_applications
  ADD COLUMN IF NOT EXISTS credly_url text;

COMMENT ON COLUMN selection_applications.credly_url IS
  'Candidate self-provided Credly badge profile URL. Filled via portal /pmi-onboarding/[token].';

CREATE OR REPLACE FUNCTION public.update_application_profile_via_token(
  p_token text,
  p_linkedin_url text DEFAULT NULL,
  p_credly_url text DEFAULT NULL,
  p_phone text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_token_row onboarding_tokens%ROWTYPE;
  v_application_id uuid;
  v_normalized_linkedin text;
  v_normalized_credly text;
  v_normalized_phone text;
BEGIN
  SELECT * INTO v_token_row
  FROM onboarding_tokens
  WHERE token = p_token
    AND expires_at > now();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired token'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_token_row.source_type <> 'pmi_application' THEN
    RAISE EXCEPTION 'Token source_type does not support profile update (got %)', v_token_row.source_type;
  END IF;

  v_application_id := v_token_row.source_id;

  v_normalized_linkedin := NULLIF(btrim(p_linkedin_url), '');
  v_normalized_credly := NULLIF(btrim(p_credly_url), '');
  v_normalized_phone := NULLIF(btrim(p_phone), '');

  IF v_normalized_linkedin IS NOT NULL AND v_normalized_linkedin !~* '^https?://([a-z0-9-]+\.)?linkedin\.com/' THEN
    RAISE EXCEPTION 'LinkedIn URL must start with https://www.linkedin.com/ or https://linkedin.com/';
  END IF;

  IF v_normalized_credly IS NOT NULL AND v_normalized_credly !~* '^https?://([a-z0-9-]+\.)?credly\.com/' THEN
    RAISE EXCEPTION 'Credly URL must start with https://www.credly.com/';
  END IF;

  UPDATE selection_applications
  SET
    linkedin_url = COALESCE(v_normalized_linkedin, linkedin_url),
    credly_url = COALESCE(v_normalized_credly, credly_url),
    phone = COALESCE(v_normalized_phone, phone),
    updated_at = now()
  WHERE id = v_application_id;

  RETURN jsonb_build_object(
    'success', true,
    'application_id', v_application_id,
    'linkedin_url_set', v_normalized_linkedin IS NOT NULL,
    'credly_url_set', v_normalized_credly IS NOT NULL,
    'phone_set', v_normalized_phone IS NOT NULL
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_application_profile_via_token(text, text, text, text)
  TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
