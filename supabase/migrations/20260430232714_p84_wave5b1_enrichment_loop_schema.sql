-- p84 Wave 5b-1 — AI-augmented self-improvement loop schema
--
-- Adds candidate enrichment loop foundation:
--   - selection_applications.enrichment_count (cap counter, default 0, max 2)
--   - selection_applications.last_enrichment_at (cooldown timer, 5min)
--   - selection_applications.last_enrichment_content_hash (MD5 dedup)
--   - selection_topic_views (audit-immutable opt-in interview-topic reveal log)
--
-- Helper:
--   - _should_offer_enrichment(jsonb) -> boolean (pure)
--
-- RPCs (token-auth, anon-callable; internal token validation gates):
--   - request_application_enrichment(token, jsonb_field_updates) -> jsonb
--   - log_topic_view(token, ip, ua) -> jsonb
--   - get_application_enrichment_status(token) -> jsonb
--
-- Council Tier 2 ratifications honored:
--   - ai-engineer: MD5 content_hash dedup (not char count)
--   - legal-counsel: B1 disclosure landed in p84 21d995b (privacy policy)
--   - ux-leader: Card B opt-in reveal logged via log_topic_view
--
-- Rollback:
--   DROP FUNCTION request_application_enrichment(text, jsonb),
--                 log_topic_view(text, inet, text),
--                 get_application_enrichment_status(text),
--                 _should_offer_enrichment(jsonb);
--   DROP TABLE selection_topic_views;
--   ALTER TABLE selection_applications
--     DROP COLUMN enrichment_count,
--     DROP COLUMN last_enrichment_at,
--     DROP COLUMN last_enrichment_content_hash;

-- 1. Schema additions on selection_applications
ALTER TABLE selection_applications
  ADD COLUMN IF NOT EXISTS enrichment_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_enrichment_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_enrichment_content_hash text;

COMMENT ON COLUMN selection_applications.enrichment_count IS
  'Wave 5b-1: count of self-improvement re-analyses. Capped at 2 (PM-approved 2026-04-30).';
COMMENT ON COLUMN selection_applications.last_enrichment_at IS
  'Wave 5b-1: timestamp of last accepted enrichment. Drives 5-minute cooldown.';
COMMENT ON COLUMN selection_applications.last_enrichment_content_hash IS
  'Wave 5b-1: MD5 of last enrichment content. Blocks re-analysis when unchanged (council ai-engineer).';

-- 2. selection_topic_views (audit-immutable opt-in topic-reveal log)
CREATE TABLE IF NOT EXISTS selection_topic_views (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES selection_applications(id) ON DELETE CASCADE,
  viewed_at timestamptz NOT NULL DEFAULT now(),
  ip_address inet,
  user_agent text,
  organization_id uuid NOT NULL DEFAULT auth_org() REFERENCES organizations(id) ON DELETE RESTRICT
);

COMMENT ON TABLE selection_topic_views IS
  'Wave 5b-1: audit-immutable log of candidates revealing Card B (interview topics opt-in). RLS: SECDEF-only insert; committee read; no update/delete.';

CREATE INDEX IF NOT EXISTS idx_selection_topic_views_application
  ON selection_topic_views (application_id, viewed_at DESC);

ALTER TABLE selection_topic_views ENABLE ROW LEVEL SECURITY;

-- Direct INSERT blocked (must go through SECDEF helper log_topic_view)
CREATE POLICY "selection_topic_views_no_direct_insert"
  ON selection_topic_views FOR INSERT TO anon, authenticated
  WITH CHECK (false);

-- Committee read via V4 manage_member or view_internal_analytics
CREATE POLICY "selection_topic_views_committee_read"
  ON selection_topic_views FOR SELECT TO authenticated
  USING (rls_can('manage_member') OR rls_can('view_internal_analytics'));

-- Audit-immutable: no UPDATE / DELETE for anyone (CASCADE handled at FK)
CREATE POLICY "selection_topic_views_no_update"
  ON selection_topic_views FOR UPDATE TO anon, authenticated USING (false);
CREATE POLICY "selection_topic_views_no_delete"
  ON selection_topic_views FOR DELETE TO anon, authenticated USING (false);

-- 3. _should_offer_enrichment helper (pure)
CREATE OR REPLACE FUNCTION _should_offer_enrichment(p_ai_analysis jsonb)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_score integer;
  v_red_count integer;
BEGIN
  IF p_ai_analysis IS NULL THEN RETURN false; END IF;
  v_score := COALESCE(NULLIF(p_ai_analysis #>> '{fit_for_role,score}', '')::integer, 5);
  v_red_count := COALESCE(jsonb_array_length(p_ai_analysis -> 'red_flags'), 0);
  RETURN v_score < 3 OR v_red_count >= 2;
END;
$fn$;
COMMENT ON FUNCTION _should_offer_enrichment(jsonb) IS
  'Wave 5b-1: pure check whether AI analysis indicates the candidate should see enrichment cards. true when fit_for_role.score < 3 OR red_flags >= 2.';

-- 4. request_application_enrichment (token-auth, cooldown + cap + content_hash dedup + fire EF)
CREATE OR REPLACE FUNCTION request_application_enrichment(
  p_token text,
  p_field_updates jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_token onboarding_tokens%ROWTYPE;
  v_app selection_applications%ROWTYPE;
  v_application_id uuid;
  v_max_attempts CONSTANT integer := 2;
  v_cooldown CONSTANT interval := interval '5 minutes';
  v_cooldown_until timestamptz;
  v_normalized_content text := '';
  v_content_hash text;
  v_field_key text;
  v_field_value text;
  v_allowed_fields CONSTANT text[] := ARRAY[
    'academic_background','motivation_letter','non_pmi_experience',
    'leadership_experience','proposed_theme','reason_for_applying',
    'areas_of_interest','availability_declared','certifications',
    'linkedin_url','credly_url','resume_url'
  ];
  v_service_role_key text;
  v_dispatch_request_id bigint;
BEGIN
  IF p_field_updates IS NULL OR jsonb_typeof(p_field_updates) <> 'object' THEN
    RAISE EXCEPTION 'p_field_updates must be a jsonb object';
  END IF;

  -- Validate token + scope (profile_completion)
  SELECT * INTO v_token
  FROM onboarding_tokens
  WHERE token = p_token
    AND expires_at > now()
    AND 'profile_completion' = ANY(scopes);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid token or missing profile_completion scope'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_token.source_type <> 'pmi_application' THEN
    RAISE EXCEPTION 'Token source_type % does not support enrichment', v_token.source_type;
  END IF;

  v_application_id := v_token.source_id;

  SELECT * INTO v_app FROM selection_applications WHERE id = v_application_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Token references missing application';
  END IF;

  -- Enrichment requires prior AI consent (cannot enrich without consent path)
  IF v_app.consent_ai_analysis_at IS NULL OR v_app.consent_ai_analysis_revoked_at IS NOT NULL THEN
    RAISE EXCEPTION 'Consent for AI analysis missing or revoked'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Cap (PM-approved: 2 re-analyses)
  IF v_app.enrichment_count >= v_max_attempts THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'cap_reached',
      'enrichment_count', v_app.enrichment_count,
      'remaining_attempts', 0,
      'message', 'Você usou suas 2 reanálises. O comitê verá sua versão atual.'
    );
  END IF;

  -- Cooldown (PM-approved: 5 minutes between re-analyses)
  IF v_app.last_enrichment_at IS NOT NULL
     AND v_app.last_enrichment_at + v_cooldown > now() THEN
    v_cooldown_until := v_app.last_enrichment_at + v_cooldown;
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'cooldown',
      'enrichment_count', v_app.enrichment_count,
      'remaining_attempts', v_max_attempts - v_app.enrichment_count,
      'next_allowed_at', v_cooldown_until,
      'message', 'Aguarde alguns minutos antes da próxima reanálise.'
    );
  END IF;

  -- Build normalized content for hash dedup (council ai-engineer rec:
  -- MD5 of concat of submitted-field values, lowercased + trimmed,
  -- to detect material changes vs. character noise)
  FOR v_field_key, v_field_value IN
    SELECT key, value FROM jsonb_each_text(p_field_updates)
  LOOP
    IF v_field_key = ANY(v_allowed_fields) THEN
      v_normalized_content := v_normalized_content
        || v_field_key || ':'
        || lower(trim(coalesce(v_field_value, '')))
        || E'\n';
    END IF;
  END LOOP;

  v_content_hash := md5(v_normalized_content);

  IF v_app.last_enrichment_content_hash IS NOT NULL
     AND v_app.last_enrichment_content_hash = v_content_hash THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'no_change_detected',
      'enrichment_count', v_app.enrichment_count,
      'remaining_attempts', v_max_attempts - v_app.enrichment_count,
      'content_hash', v_content_hash,
      'message', 'Nenhuma mudança material detectada — reanálise não disparada.'
    );
  END IF;

  -- Apply field updates (whitelist enforced via explicit per-column COALESCE).
  -- Empty strings are treated as no-change (preserve existing value).
  UPDATE selection_applications
     SET academic_background  = COALESCE(NULLIF(p_field_updates->>'academic_background',''),  academic_background),
         motivation_letter    = COALESCE(NULLIF(p_field_updates->>'motivation_letter',''),    motivation_letter),
         non_pmi_experience   = COALESCE(NULLIF(p_field_updates->>'non_pmi_experience',''),   non_pmi_experience),
         leadership_experience = COALESCE(NULLIF(p_field_updates->>'leadership_experience',''), leadership_experience),
         proposed_theme       = COALESCE(NULLIF(p_field_updates->>'proposed_theme',''),       proposed_theme),
         reason_for_applying  = COALESCE(NULLIF(p_field_updates->>'reason_for_applying',''),  reason_for_applying),
         areas_of_interest    = COALESCE(NULLIF(p_field_updates->>'areas_of_interest',''),    areas_of_interest),
         availability_declared = COALESCE(NULLIF(p_field_updates->>'availability_declared',''), availability_declared),
         certifications       = COALESCE(NULLIF(p_field_updates->>'certifications',''),       certifications),
         linkedin_url         = COALESCE(NULLIF(p_field_updates->>'linkedin_url',''),         linkedin_url),
         credly_url           = COALESCE(NULLIF(p_field_updates->>'credly_url',''),           credly_url),
         resume_url           = COALESCE(NULLIF(p_field_updates->>'resume_url',''),           resume_url),
         enrichment_count     = enrichment_count + 1,
         last_enrichment_at   = now(),
         last_enrichment_content_hash = v_content_hash,
         updated_at           = now()
   WHERE id = v_application_id
   RETURNING * INTO v_app;

  -- Update token access counters
  UPDATE onboarding_tokens
     SET last_accessed_at = now(),
         access_count = access_count + 1
   WHERE token = p_token;

  -- Fire-and-forget Gemini re-analysis dispatch (same pattern as give_consent_via_token)
  BEGIN
    SELECT decrypted_secret INTO v_service_role_key
    FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

    IF v_service_role_key IS NOT NULL THEN
      SELECT net.http_post(
        url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/pmi-ai-analyze',
        body := jsonb_build_object('application_id', v_application_id),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_service_role_key
        )
      ) INTO v_dispatch_request_id;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pmi-ai-analyze dispatch failed: % (application_id=%)', SQLERRM, v_application_id;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'enrichment_count', v_app.enrichment_count,
    'remaining_attempts', v_max_attempts - v_app.enrichment_count,
    'next_allowed_at', v_app.last_enrichment_at + v_cooldown,
    'content_hash', v_content_hash,
    'dispatch_request_id', v_dispatch_request_id,
    'message', 'Reanálise disparada. Aguarde ~10 segundos para ver atualização.'
  );
END;
$fn$;
COMMENT ON FUNCTION request_application_enrichment(text, jsonb) IS
  'Wave 5b-1: candidate-driven re-analysis. Validates token (profile_completion scope) + cap (2) + cooldown (5min) + MD5 content-hash dedup. Updates whitelisted fields and fires gemini-2.5-flash via pmi-ai-analyze EF.';

-- 5. log_topic_view (token-auth INSERT into audit-immutable table)
CREATE OR REPLACE FUNCTION log_topic_view(
  p_token text,
  p_ip inet DEFAULT NULL,
  p_ua text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_token onboarding_tokens%ROWTYPE;
  v_view_id uuid;
BEGIN
  SELECT * INTO v_token
  FROM onboarding_tokens
  WHERE token = p_token
    AND expires_at > now()
    AND 'profile_completion' = ANY(scopes);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid token' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_token.source_type <> 'pmi_application' THEN
    RAISE EXCEPTION 'Token source_type % does not support enrichment', v_token.source_type;
  END IF;

  INSERT INTO selection_topic_views (application_id, ip_address, user_agent, organization_id)
  VALUES (v_token.source_id, p_ip, p_ua, v_token.organization_id)
  RETURNING id INTO v_view_id;

  RETURN jsonb_build_object('success', true, 'view_id', v_view_id);
END;
$fn$;
COMMENT ON FUNCTION log_topic_view(text, inet, text) IS
  'Wave 5b-1: candidate opted to reveal interview topics (Card B). Audit-immutable INSERT into selection_topic_views.';

-- 6. get_application_enrichment_status (portal status check)
CREATE OR REPLACE FUNCTION get_application_enrichment_status(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_token onboarding_tokens%ROWTYPE;
  v_app selection_applications%ROWTYPE;
  v_max CONSTANT integer := 2;
  v_cool CONSTANT interval := interval '5 minutes';
BEGIN
  SELECT * INTO v_token
  FROM onboarding_tokens
  WHERE token = p_token
    AND expires_at > now()
    AND 'profile_completion' = ANY(scopes);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid token' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_token.source_type <> 'pmi_application' THEN
    RAISE EXCEPTION 'Token source_type % does not support enrichment', v_token.source_type;
  END IF;

  SELECT * INTO v_app FROM selection_applications WHERE id = v_token.source_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  RETURN jsonb_build_object(
    'application_id', v_app.id,
    'has_consent', v_app.consent_ai_analysis_at IS NOT NULL AND v_app.consent_ai_analysis_revoked_at IS NULL,
    'has_analysis', v_app.ai_analysis IS NOT NULL,
    'should_offer_enrichment', _should_offer_enrichment(v_app.ai_analysis),
    'enrichment_count', v_app.enrichment_count,
    'remaining_attempts', GREATEST(v_max - v_app.enrichment_count, 0),
    'cap_reached', v_app.enrichment_count >= v_max,
    'last_enrichment_at', v_app.last_enrichment_at,
    'cooldown_until', CASE WHEN v_app.last_enrichment_at IS NULL THEN NULL ELSE v_app.last_enrichment_at + v_cool END,
    'is_in_cooldown', v_app.last_enrichment_at IS NOT NULL AND v_app.last_enrichment_at + v_cool > now(),
    'red_flags', COALESCE(v_app.ai_analysis -> 'red_flags', '[]'::jsonb),
    'areas_to_probe', COALESCE(v_app.ai_analysis -> 'areas_to_probe', '[]'::jsonb),
    'fit_score', NULLIF(v_app.ai_analysis #>> '{fit_for_role,score}', '')::integer,
    'analyzed_at', v_app.ai_analysis ->> 'analyzed_at'
  );
END;
$fn$;
COMMENT ON FUNCTION get_application_enrichment_status(text) IS
  'Wave 5b-1: portal status read for /pmi-onboarding/[token]. Returns enrichment eligibility, attempts remaining, cooldown timer, and AI analysis snapshot.';

-- 7. GRANTs (token-auth pattern: anon-callable; internal token validation gates)
GRANT EXECUTE ON FUNCTION _should_offer_enrichment(jsonb) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION request_application_enrichment(text, jsonb) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION log_topic_view(text, inet, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_application_enrichment_status(text) TO anon, authenticated, service_role;
