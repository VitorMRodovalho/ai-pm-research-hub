-- =====================================================================
-- Migration: p238_331_voice_biometric_consent_rpcs
-- Issue: #331 (Wave 2 of #221/#218 Whisper Art. 11 voice biometric remediation)
-- Date: 2026-05-23 (slot 20260805000022)
--
-- WHY: The Wave 1 emergency moat (p207, canonical row 20260520231254 +
-- aliases 20260801000001/002) added DB columns + a trigger that blocks
-- pmi_video_screenings.transcription writes whenever
-- selection_applications.consent_voice_biometric_at IS NULL. But Wave 1
-- shipped no UX path to populate those columns, so live state is 0/107
-- applications with voice biometric consent. The candidate-facing portal
-- (PMIOnboardingPortal.tsx at /pmi-onboarding/[token]) exposes only a
-- single ai_analysis consent toggle that hits give_consent_via_token —
-- which is hardcoded to reject any consent_type other than 'ai_analysis'.
--
-- This migration unblocks Wave 2 by:
--   1. DROP+CREATE give_consent_via_token(text, text, jsonb) — accepts
--      p_consent_type='voice_biometric' plus a required jsonb evidence
--      payload (version + lang + label_text_hash). The hash is the
--      SHA-256 of the displayed destacado label text — provable later that
--      the candidate saw the exact Art. 11 §I copy when consenting. For
--      ai_analysis the evidence param is ignored (preserves existing
--      schema; ai_analysis has no _evidence column).
--   2. DROP+CREATE revoke_consent_via_token(text, text) — accepts
--      voice_biometric and clears the revoked_at sibling column.
--   3. CREATE OR REPLACE consume_onboarding_token(text) — payload.
--      application gains has_voice_biometric_consent + has_voice_biometric_revoked
--      so the React island can render the destacado section state and
--      gate the video upload UI without an extra RPC roundtrip.
--
-- DROP+CREATE not CREATE OR REPLACE because the parameter count changes
-- for give_consent_via_token (2 -> 3 args). Per SEDIMENT-232.A, leaving
-- the stale 2-arg overload would let PostgREST dispatch the body without
-- the new evidence enforcement. revoke also uses DROP+CREATE for symmetry
-- (param count unchanged but the dispatch policy expands).
--
-- consume_onboarding_token uses CREATE OR REPLACE because the signature
-- (text -> jsonb) is unchanged; only the payload shape grows. No PostgREST
-- overload risk.
--
-- ROLLBACK: re-apply 20260516210000 (give/revoke ai_analysis-only bodies)
-- and the most recent consume_onboarding_token capture
-- (20260516400000 / 20260516240000 / 20260516200000 chain). Note this
-- removes the only path to populate consent_voice_biometric_at — Wave 1
-- moat will then block all transcription forever (intentional but worth
-- noting before rollback).
--
-- INVARIANTS: 19/19 = 0 violations expected post-apply (no new schema,
-- no FK changes, only function bodies).
-- =====================================================================

DROP FUNCTION IF EXISTS public.give_consent_via_token(text, text);

CREATE OR REPLACE FUNCTION public.give_consent_via_token(
  p_token text,
  p_consent_type text DEFAULT 'ai_analysis',
  p_evidence jsonb DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_token_row onboarding_tokens%ROWTYPE;
  v_application_id uuid;
  v_app selection_applications%ROWTYPE;
  v_consent_at timestamptz;
  v_evidence_text text;
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

  IF p_consent_type NOT IN ('ai_analysis', 'voice_biometric') THEN
    RAISE EXCEPTION 'Unsupported consent type: % (supported: ai_analysis, voice_biometric)', p_consent_type;
  END IF;

  IF p_consent_type = 'voice_biometric' THEN
    -- LGPD Art. 11 §I sensitive: evidence (version+lang+label_text_hash) MUST
    -- be supplied so we can later prove the candidate saw the destacado label.
    IF p_evidence IS NULL
       OR (p_evidence ->> 'version') IS NULL
       OR (p_evidence ->> 'lang') IS NULL
       OR (p_evidence ->> 'label_text_hash') IS NULL THEN
      RAISE EXCEPTION 'voice_biometric consent requires p_evidence jsonb with version + lang + label_text_hash'
        USING HINT = 'Compute SHA-256 of the displayed destacado label and submit it as label_text_hash.';
    END IF;
    v_evidence_text := p_evidence::text;

    UPDATE selection_applications
       SET consent_voice_biometric_at = COALESCE(consent_voice_biometric_at, now()),
           consent_voice_biometric_revoked_at = NULL,
           consent_voice_biometric_evidence = COALESCE(consent_voice_biometric_evidence, v_evidence_text),
           updated_at = now()
     WHERE id = v_application_id
    RETURNING * INTO v_app;

    v_consent_at := v_app.consent_voice_biometric_at;
  ELSE
    UPDATE selection_applications
       SET consent_ai_analysis_at = COALESCE(consent_ai_analysis_at, now()),
           consent_ai_analysis_revoked_at = NULL,
           updated_at = now()
     WHERE id = v_application_id
    RETURNING * INTO v_app;

    v_consent_at := v_app.consent_ai_analysis_at;
  END IF;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Token references missing application';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'application_id', v_application_id,
    'consent_type', p_consent_type,
    'consent_at', v_consent_at,
    'has_consent', true,
    'has_revoked', false
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.give_consent_via_token(text, text, jsonb) TO anon, authenticated;

COMMENT ON FUNCTION public.give_consent_via_token(text, text, jsonb) IS
  'Token-authenticated consent grant for PMI candidate. p_consent_type IN (ai_analysis, voice_biometric). For voice_biometric (LGPD Art. 11 sensitive), p_evidence jsonb REQUIRED with version + lang + label_text_hash (SHA-256 of displayed destacado label). Idempotent: re-granting preserves first consent_at + evidence and clears revoked_at.';


DROP FUNCTION IF EXISTS public.revoke_consent_via_token(text, text);

CREATE OR REPLACE FUNCTION public.revoke_consent_via_token(
  p_token text,
  p_consent_type text DEFAULT 'ai_analysis'
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_token_row onboarding_tokens%ROWTYPE;
  v_application_id uuid;
  v_app selection_applications%ROWTYPE;
  v_revoked_at timestamptz;
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

  IF p_consent_type NOT IN ('ai_analysis', 'voice_biometric') THEN
    RAISE EXCEPTION 'Unsupported consent type: % (supported: ai_analysis, voice_biometric)', p_consent_type;
  END IF;

  IF p_consent_type = 'voice_biometric' THEN
    UPDATE selection_applications
       SET consent_voice_biometric_revoked_at = COALESCE(consent_voice_biometric_revoked_at, now()),
           updated_at = now()
     WHERE id = v_application_id
    RETURNING * INTO v_app;

    v_revoked_at := v_app.consent_voice_biometric_revoked_at;
  ELSE
    UPDATE selection_applications
       SET consent_ai_analysis_revoked_at = COALESCE(consent_ai_analysis_revoked_at, now()),
           updated_at = now()
     WHERE id = v_application_id
    RETURNING * INTO v_app;

    v_revoked_at := v_app.consent_ai_analysis_revoked_at;
  END IF;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Token references missing application';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'application_id', v_application_id,
    'consent_type', p_consent_type,
    'revoked_at', v_revoked_at,
    'has_consent', false,
    'has_revoked', true
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.revoke_consent_via_token(text, text) TO anon, authenticated;

COMMENT ON FUNCTION public.revoke_consent_via_token(text, text) IS
  'Token-authenticated consent revocation for PMI candidate. p_consent_type IN (ai_analysis, voice_biometric). Idempotent (preserves earliest revoked_at). For voice_biometric: post-revoke, transcription is blocked by trg_pmi_video_screening_voice_consent and a 30-day deletion window starts per Art. 18 §IV (executed by sibling Wave 3 issue #332).';


-- Extend payload to surface voice biometric consent state to the React island
-- (avoids a separate RPC roundtrip + keeps the consent UX coherent with the
-- existing ai_analysis flag pair).
CREATE OR REPLACE FUNCTION public.consume_onboarding_token(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_token_row onboarding_tokens%ROWTYPE;
  v_app selection_applications%ROWTYPE;
  v_cycle selection_cycles%ROWTYPE;
  v_progress jsonb;
  v_video_screenings jsonb;
  v_result jsonb;
BEGIN
  UPDATE onboarding_tokens
     SET consumed_at = COALESCE(consumed_at, now()),
         last_accessed_at = now(),
         access_count = access_count + 1
   WHERE token = p_token
     AND expires_at > now()
  RETURNING * INTO v_token_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired token'
      USING ERRCODE = 'invalid_authorization_specification';
  END IF;

  IF v_token_row.source_type = 'pmi_application' THEN
    SELECT * INTO v_app
    FROM selection_applications
    WHERE id = v_token_row.source_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Token references missing application';
    END IF;

    SELECT * INTO v_cycle
    FROM selection_cycles
    WHERE id = v_app.cycle_id;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'step_key', op.step_key,
      'status', op.status,
      'completed_at', op.completed_at,
      'evidence_url', op.evidence_url,
      'notes', op.notes,
      'sla_deadline', op.sla_deadline
    ) ORDER BY op.created_at), '[]'::jsonb)
    INTO v_progress
    FROM onboarding_progress op
    WHERE op.application_id = v_app.id;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'pillar', vs.pillar,
      'question_index', vs.question_index,
      'status', vs.status,
      'uploaded_at', vs.uploaded_at
    ) ORDER BY vs.question_index, vs.created_at), '[]'::jsonb)
    INTO v_video_screenings
    FROM pmi_video_screenings vs
    WHERE vs.application_id = v_app.id;

    v_result := jsonb_build_object(
      'source_type', 'pmi_application',
      'scopes', v_token_row.scopes,
      'application', jsonb_build_object(
        'id', v_app.id,
        'applicant_name', v_app.applicant_name,
        'email', v_app.email,
        'phone', v_app.phone,
        'linkedin_url', v_app.linkedin_url,
        'credly_url', v_app.credly_url,
        'role_applied', v_app.role_applied,
        'cycle_id', v_app.cycle_id,
        'has_consent', v_app.consent_ai_analysis_at IS NOT NULL
                       AND v_app.consent_ai_analysis_revoked_at IS NULL,
        'has_revoked', v_app.consent_ai_analysis_revoked_at IS NOT NULL,
        'has_voice_biometric_consent', v_app.consent_voice_biometric_at IS NOT NULL
                       AND v_app.consent_voice_biometric_revoked_at IS NULL,
        'has_voice_biometric_revoked', v_app.consent_voice_biometric_revoked_at IS NOT NULL,
        'status', v_app.status
      ),
      'cycle', jsonb_build_object(
        'id', v_cycle.id,
        'cycle_code', v_cycle.cycle_code,
        'title', v_cycle.title,
        'phase', v_cycle.phase,
        'onboarding_steps', v_cycle.onboarding_steps
      ),
      'onboarding_progress', v_progress,
      'video_screenings', v_video_screenings,
      'token_metadata', jsonb_build_object(
        'access_count', v_token_row.access_count,
        'expires_at', v_token_row.expires_at,
        'first_access', v_token_row.consumed_at = v_token_row.last_accessed_at
      )
    );

  ELSIF v_token_row.source_type IN ('initiative_invitation', 'direct_assignment') THEN
    v_result := jsonb_build_object(
      'source_type', v_token_row.source_type,
      'scopes', v_token_row.scopes,
      'pending_implementation', true,
      'message', 'Esse fluxo ainda não está ativo. Aguarde comunicação.'
    );

  ELSE
    RAISE EXCEPTION 'Unknown source_type: %', v_token_row.source_type;
  END IF;

  RETURN v_result;
END;
$$;


-- Sanity: ensure post-apply state matches Wave 2 intent.
-- (Goal metric still 0/107 voice consent — populated only by candidates
-- via UI, not by migration. We assert the columns exist + the function
-- bodies advertise the new consent type.)
DO $sanity$
DECLARE
  v_give_body text;
  v_revoke_body text;
  v_consume_body text;
BEGIN
  SELECT prosrc INTO v_give_body
    FROM pg_proc
   WHERE proname = 'give_consent_via_token'
     AND pronamespace = 'public'::regnamespace;
  IF v_give_body IS NULL OR position('voice_biometric' in v_give_body) = 0 THEN
    RAISE EXCEPTION 'sanity: give_consent_via_token did not pick up voice_biometric dispatch';
  END IF;
  IF position('label_text_hash' in v_give_body) = 0 THEN
    RAISE EXCEPTION 'sanity: give_consent_via_token missing label_text_hash evidence guard';
  END IF;

  SELECT prosrc INTO v_revoke_body
    FROM pg_proc
   WHERE proname = 'revoke_consent_via_token'
     AND pronamespace = 'public'::regnamespace;
  IF v_revoke_body IS NULL OR position('voice_biometric' in v_revoke_body) = 0 THEN
    RAISE EXCEPTION 'sanity: revoke_consent_via_token did not pick up voice_biometric dispatch';
  END IF;

  SELECT prosrc INTO v_consume_body
    FROM pg_proc
   WHERE proname = 'consume_onboarding_token'
     AND pronamespace = 'public'::regnamespace;
  IF v_consume_body IS NULL
     OR position('has_voice_biometric_consent' in v_consume_body) = 0
     OR position('has_voice_biometric_revoked' in v_consume_body) = 0 THEN
    RAISE EXCEPTION 'sanity: consume_onboarding_token did not pick up has_voice_biometric_* payload';
  END IF;

  -- Confirm we did not regress the give_consent_via_token signature into
  -- two competing overloads (SEDIMENT-232.A defense).
  IF (SELECT count(*) FROM pg_proc
       WHERE proname = 'give_consent_via_token'
         AND pronamespace = 'public'::regnamespace) <> 1 THEN
    RAISE EXCEPTION 'sanity: give_consent_via_token has more than one overload — drop the stale one';
  END IF;
  IF (SELECT count(*) FROM pg_proc
       WHERE proname = 'revoke_consent_via_token'
         AND pronamespace = 'public'::regnamespace) <> 1 THEN
    RAISE EXCEPTION 'sanity: revoke_consent_via_token has more than one overload — drop the stale one';
  END IF;
END;
$sanity$;

NOTIFY pgrst, 'reload schema';
