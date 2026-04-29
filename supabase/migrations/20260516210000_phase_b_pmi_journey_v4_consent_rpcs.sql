-- =====================================================================
-- Migration: phase_b_pmi_journey_v4_consent_rpcs
-- Date: 2026-04-29 (slot 20260516210000)
-- Author: Claude Code (autonomous p81 follow-up)
--
-- Purpose: Token-authenticated consent flow for PMI candidate portal.
-- Spec gap: token has scope 'consent_giving' (per issueOnboardingToken)
-- but spec did not provide RPCs to actually consume that scope. Without
-- these, the candidate portal cannot grant or revoke consent.
--
-- Adds 2 RPCs:
--   give_consent_via_token(p_token, p_consent_type)
--   revoke_consent_via_token(p_token, p_consent_type)
--
-- Both: token-auth (no auth.uid()), require source_type='pmi_application'
-- and scope 'consent_giving'. Existing trigger
-- trg_supersede_ai_suggestions_on_consent_revoke auto-supersedes
-- non-consumed AI suggestions on revoke (no extra logic needed here).
-- =====================================================================

CREATE OR REPLACE FUNCTION public.give_consent_via_token(
  p_token text,
  p_consent_type text DEFAULT 'ai_analysis'
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_token_row onboarding_tokens%ROWTYPE;
  v_application_id uuid;
  v_app selection_applications%ROWTYPE;
BEGIN
  SELECT * INTO v_token_row
  FROM onboarding_tokens
  WHERE token = p_token
    AND expires_at > now()
    AND 'consent_giving' = ANY(scopes);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid token or missing consent_giving scope'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_token_row.source_type <> 'pmi_application' THEN
    RAISE EXCEPTION 'Token source_type % does not support consent giving', v_token_row.source_type;
  END IF;

  v_application_id := v_token_row.source_id;

  IF p_consent_type <> 'ai_analysis' THEN
    RAISE EXCEPTION 'Unsupported consent type: % (only ai_analysis is supported)', p_consent_type;
  END IF;

  UPDATE selection_applications
     SET consent_ai_analysis_at = COALESCE(consent_ai_analysis_at, now()),
         consent_ai_analysis_revoked_at = NULL,
         updated_at = now()
   WHERE id = v_application_id
  RETURNING * INTO v_app;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Token references missing application';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'application_id', v_application_id,
    'consent_type', p_consent_type,
    'consent_at', v_app.consent_ai_analysis_at,
    'has_consent', true,
    'has_revoked', false
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.give_consent_via_token(text, text) TO anon, authenticated;

COMMENT ON FUNCTION public.give_consent_via_token(text, text) IS
  'Token-authenticated consent grant for PMI candidate. Requires onboarding_tokens row with scope consent_giving and source_type pmi_application. Idempotent: re-granting preserves original consent_at and clears revoked_at.';


CREATE OR REPLACE FUNCTION public.revoke_consent_via_token(
  p_token text,
  p_consent_type text DEFAULT 'ai_analysis'
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_token_row onboarding_tokens%ROWTYPE;
  v_application_id uuid;
  v_app selection_applications%ROWTYPE;
BEGIN
  SELECT * INTO v_token_row
  FROM onboarding_tokens
  WHERE token = p_token
    AND expires_at > now()
    AND 'consent_giving' = ANY(scopes);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid token or missing consent_giving scope'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_token_row.source_type <> 'pmi_application' THEN
    RAISE EXCEPTION 'Token source_type % does not support consent revocation', v_token_row.source_type;
  END IF;

  v_application_id := v_token_row.source_id;

  IF p_consent_type <> 'ai_analysis' THEN
    RAISE EXCEPTION 'Unsupported consent type: % (only ai_analysis is supported)', p_consent_type;
  END IF;

  UPDATE selection_applications
     SET consent_ai_analysis_revoked_at = COALESCE(consent_ai_analysis_revoked_at, now()),
         updated_at = now()
   WHERE id = v_application_id
  RETURNING * INTO v_app;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Token references missing application';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'application_id', v_application_id,
    'consent_type', p_consent_type,
    'revoked_at', v_app.consent_ai_analysis_revoked_at,
    'has_consent', false,
    'has_revoked', true
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.revoke_consent_via_token(text, text) TO anon, authenticated;

COMMENT ON FUNCTION public.revoke_consent_via_token(text, text) IS
  'Token-authenticated consent revocation for PMI candidate. Idempotent (preserves earliest revoked_at). Trigger trg_supersede_ai_suggestions_on_consent_revoke auto-supersedes non-consumed AI suggestions.';

NOTIFY pgrst, 'reload schema';
