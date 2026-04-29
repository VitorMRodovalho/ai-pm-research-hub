-- =====================================================================
-- Migration: phase_b_pmi_journey_v4_token_payload_video
-- Date: 2026-04-29 (slot 20260516240000)
-- Author: Claude Code (autonomous p81 backlog item 2)
--
-- Purpose: Extend consume_onboarding_token to include video_screenings
-- list. Portal needs visibility into which pillars already have a status
-- (uploaded / opted_out) to render correct state.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.consume_onboarding_token(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
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
        'role_applied', v_app.role_applied,
        'cycle_id', v_app.cycle_id,
        'has_consent', v_app.consent_ai_analysis_at IS NOT NULL
                       AND v_app.consent_ai_analysis_revoked_at IS NULL,
        'has_revoked', v_app.consent_ai_analysis_revoked_at IS NOT NULL,
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

GRANT EXECUTE ON FUNCTION public.consume_onboarding_token(text) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
