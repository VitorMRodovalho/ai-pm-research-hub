-- p197d D1 (2026-05-19): video AI analysis schema + trigger
-- Decisions ratified by PM:
-- - Reuse selection_evaluation_ai_suggestions with evaluation_type='video' (5 pillars
--   mapped: background + communication + culture_alignment + proactivity + teamwork).
-- - IA-as-suggestion pattern: humano evaluator aceita/ajusta via ai_suggestion_id.
-- - Trigger DB AFTER UPDATE OF status='uploaded' on pmi_video_screenings.
-- - LGPD boundary: same consent_ai_analysis_at as CV.
--
-- This migration:
-- (1) extends CHECK constraint evaluation_type ALLOW 'video'
-- (2) adds helper RPC analyze_application_video_async (called by trigger + by MCP tool)
-- (3) trigger trg_video_ai_analysis_on_upload on pmi_video_screenings
-- (4) idempotency guard: skip if existing pending suggestion for (app, pillar, video)
--
-- RECOVERY NOTE (BUG-199.B p199-b, 2026-05-19): applied to DB live as foundation
-- for the analyze-application-video EF (committed in 27e08ad4 fix(p199-a)) and
-- the MCP analyze_application_video tool (v2.76.0, committed in 51582b04). FS
-- file was lost when Supabase fork-bomb killed the session (CR-051). Body
-- recovered byte-equivalent from supabase_migrations.schema_migrations.statements
-- on 2026-05-19. Without this migration in the FS, a fresh `supabase db reset`
-- would have left the video AI pipeline broken (no trigger, no RPCs).

-- 1) Extend CHECK constraint on selection_evaluation_ai_suggestions
ALTER TABLE public.selection_evaluation_ai_suggestions
  DROP CONSTRAINT IF EXISTS selection_evaluation_ai_suggestions_evaluation_type_check;
ALTER TABLE public.selection_evaluation_ai_suggestions
  ADD CONSTRAINT selection_evaluation_ai_suggestions_evaluation_type_check
  CHECK (evaluation_type IN ('objective', 'interview', 'leader_extra', 'video'));

-- 2) Helper RPC: dispatch to EF analyze-application-video
CREATE OR REPLACE FUNCTION public.analyze_application_video_async(
  p_application_id uuid,
  p_pillar text DEFAULT NULL,
  p_force boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_app record;
  v_url text := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/analyze-application-video';
  v_key text;
  v_dispatch_id bigint;
  v_existing_pending int;
BEGIN
  SELECT id, cycle_id, consent_ai_analysis_at, consent_ai_analysis_revoked_at
  INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app.id IS NULL THEN
    RETURN jsonb_build_object('error', 'application_not_found');
  END IF;

  -- LGPD gate (same as CV)
  IF v_app.consent_ai_analysis_at IS NULL OR v_app.consent_ai_analysis_revoked_at IS NOT NULL THEN
    RETURN jsonb_build_object('skipped', true, 'reason', 'consent_pending_or_revoked');
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
$$;

-- 3) Trigger function: fires when video status transitions to 'uploaded'
CREATE OR REPLACE FUNCTION public._trg_video_ai_analysis_on_upload()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF NEW.status = 'uploaded' AND (OLD.status IS DISTINCT FROM NEW.status) THEN
    PERFORM public.analyze_application_video_async(NEW.application_id, NEW.pillar, false);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_video_ai_analysis_on_upload ON public.pmi_video_screenings;
CREATE TRIGGER trg_video_ai_analysis_on_upload
  AFTER UPDATE OF status ON public.pmi_video_screenings
  FOR EACH ROW
  EXECUTE FUNCTION public._trg_video_ai_analysis_on_upload();

-- 4) Public entrypoint for MCP tool / admin override
CREATE OR REPLACE FUNCTION public.analyze_application_video(
  p_application_id uuid,
  p_pillar text DEFAULT NULL,
  p_force boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- Auth: committee membership OR manage_member
  IF NOT (
    EXISTS (SELECT 1 FROM public.selection_committee sc
            JOIN public.selection_applications sa ON sa.cycle_id = sc.cycle_id
            WHERE sa.id = p_application_id AND sc.member_id = v_caller_id)
    OR public.can_by_member(v_caller_id, 'manage_member')
  ) THEN
    RETURN jsonb_build_object('error', 'access_denied', 'required', 'committee or manage_member');
  END IF;

  RETURN public.analyze_application_video_async(p_application_id, p_pillar, p_force);
END;
$$;

GRANT EXECUTE ON FUNCTION public.analyze_application_video(uuid, text, boolean) TO authenticated;

COMMENT ON FUNCTION public.analyze_application_video_async(uuid, text, boolean) IS
  'p197d D1 (2026-05-19): internal dispatch RPC for video AI analysis. Called by (a) trigger trg_video_ai_analysis_on_upload when pmi_video_screenings.status transitions to uploaded, (b) public entrypoint analyze_application_video. Idempotent (skips if pending suggestion exists unless force=true). LGPD-gated via consent_ai_analysis_at. Async via pg_net.';

COMMENT ON FUNCTION public.analyze_application_video(uuid, text, boolean) IS
  'p197d D1 (2026-05-19): public entrypoint for video AI analysis. Auth: committee membership of cycle OR manage_member. Delegates to analyze_application_video_async after auth check.';
