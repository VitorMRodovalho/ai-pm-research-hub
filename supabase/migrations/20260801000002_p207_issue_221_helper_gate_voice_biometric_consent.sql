-- P207 issue #221 — Whisper Art. 11 RETROATIVO Phase 3 of 3
-- Update `analyze_application_video_async` to gate on consent_voice_biometric_at
--
-- BODY pulled from pg_get_functiondef pre-update (sediment
-- [[feedback-create-or-replace-full-body-fetch]]). Single new gate added
-- after existing consent_ai_analysis_at check. Returns same skipped envelope
-- shape so MCP tool callers see graceful skip, not exception.
--
-- This migration keeps the public entrypoint `analyze_application_video(uuid,text,bool)`
-- unchanged — it still delegates to async helper. New gate fires for BOTH the
-- (now-dropped) trigger path AND the MCP tool path. Trigger remains DROPPED
-- from Phase 1 until Angeline's Art. 48 determination clears consent flow.
--
-- After this migration:
--   - Phase 1 trigger DROP keeps automatic dispatch dead
--   - Phase 3 helper gate keeps manual MCP tool call dead
--   - Re-enabling requires per-candidate consent_voice_biometric_at NOT NULL
--   - Future re-attachment of trg_video_ai_analysis_on_upload (Phase 4, separate
--     migration after Angeline cycle complete) restores automatic path with gate
--
-- LGPD legal basis for the gate:
--   - Art. 11 §I (biometria de voz = dado sensível)
--   - Art. 11 §II (hipóteses taxativas — só consentimento explícito Art. 8 cabe)
--   - Art. 8 §6 (especificidade da finalidade — consentimento AI genérico ≠ Art. 11)
--   - Art. 9 §V (revogabilidade — revoked_at column gate also applies)
--
-- Rollback: re-CREATE OR REPLACE FUNCTION with the pre-Phase-3 body (preserved
-- in p197d migration file 20260519041719). NOT RECOMMENDED — restores violation.
--
-- Refs: issue #221 · ADR-0094 (Draft, gated on this Phase 3 being live)

CREATE OR REPLACE FUNCTION public.analyze_application_video_async(
  p_application_id uuid,
  p_pillar text DEFAULT NULL::text,
  p_force boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_app record;
  v_url text := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/analyze-application-video';
  v_key text;
  v_dispatch_id bigint;
  v_existing_pending int;
BEGIN
  SELECT id, cycle_id,
         consent_ai_analysis_at, consent_ai_analysis_revoked_at,
         consent_voice_biometric_at, consent_voice_biometric_revoked_at
    INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app.id IS NULL THEN
    RETURN jsonb_build_object('error', 'application_not_found');
  END IF;

  -- LGPD generic AI consent gate (predates this migration; preserved)
  IF v_app.consent_ai_analysis_at IS NULL OR v_app.consent_ai_analysis_revoked_at IS NOT NULL THEN
    RETURN jsonb_build_object('skipped', true, 'reason', 'consent_pending_or_revoked');
  END IF;

  -- p207 #221: LGPD Art. 11 §I biometric voice consent gate (NEW)
  -- Trigger trg_video_ai_analysis_on_upload was DROPPED at Phase 1 of this
  -- remediation. This gate ALSO refuses manual MCP tool calls until candidate
  -- has explicit Art. 11 consent + non-revoked status. Returns graceful skip
  -- envelope so MCP/UI callers see structured response, not exception.
  IF v_app.consent_voice_biometric_at IS NULL OR v_app.consent_voice_biometric_revoked_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'skipped', true,
      'reason', 'voice_biometric_consent_required',
      'detail', 'LGPD Art. 11 §I — voice biometric is sensitive data requiring explicit consent destacado per Art. 8. Pipeline blocked until consent_voice_biometric_at is captured per Termo de Speaker.',
      'issue', 221
    );
  END IF;

  -- Idempotency: skip if pending suggestion already exists (unless force)
  IF NOT p_force THEN
    SELECT COUNT(*) INTO v_existing_pending FROM public.selection_evaluation_ai_suggestions
    WHERE application_id = p_application_id
      AND evaluation_type = 'video'
      AND used_in_evaluation_id IS NULL
      AND superseded_by IS NULL
      AND (p_pillar IS NULL OR suggested_scores ? p_pillar);
    IF v_existing_pending > 0 THEN
      RETURN jsonb_build_object('skipped', true, 'reason', 'pending_suggestion_exists',
        'existing_count', v_existing_pending,
        'hint', 'pass force=true to regenerate');
    END IF;
  END IF;

  -- Read service_role_key from vault
  SELECT decrypted_secret INTO v_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
  IF v_key IS NULL THEN
    RAISE EXCEPTION 'service_role_key not in vault (analyze_application_video_async)';
  END IF;

  -- Async dispatch via pg_net (EF returns 200 quickly; analysis is async inside)
  SELECT net.http_post(
    url := v_url,
    body := jsonb_build_object(
      'application_id', p_application_id,
      'pillar', p_pillar,
      'force', p_force,
      'triggered_by', 'rpc'
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key
    )
  ) INTO v_dispatch_id;

  RETURN jsonb_build_object(
    'dispatched', true,
    'application_id', p_application_id,
    'pillar', COALESCE(p_pillar, 'all'),
    'force', p_force,
    'dispatch_id', v_dispatch_id
  );
END;
$function$;

COMMENT ON FUNCTION public.analyze_application_video_async(uuid, text, boolean) IS
  'p207 #221 (2026-05-20): internal dispatch RPC for video AI analysis. Called by MCP tool analyze_application_video (trigger trg_video_ai_analysis_on_upload DROPPED at Phase 1 of this remediation). Idempotent (skips if pending suggestion exists unless force=true). Two LGPD gates: (1) consent_ai_analysis_at (predates p207); (2) consent_voice_biometric_at (NEW — Art. 11 §I). Async via pg_net.';

NOTIFY pgrst, 'reload schema';
