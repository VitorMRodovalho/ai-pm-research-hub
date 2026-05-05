-- p92 Phase F — Bulk dispatch pending welcomes
-- Audit context: docs/specs/p91-selection-journey-audit.md Bug #3
-- Purpose: identify selection_applications inserted via bulk SQL (bypassing
-- worker `was_new=true` welcome trigger) and dispatch onboarding token + welcome
-- email. PM 2026-05-05 explicitly: BLOQUEADO até Phase A/B/C done.
--   - Phase A done (worker filter)
--   - Phase B partial (webhook code shipped; Apps Script setup PM action)
--   - Phase C done (peer review round-robin)
-- Decision: ship RPC + dry_run safety, but DO NOT execute live dispatch in this
-- session. PM invokes manually when ready.

CREATE OR REPLACE FUNCTION public.dispatch_pending_welcomes(
  p_dry_run boolean DEFAULT true,
  p_max_count int DEFAULT NULL,
  p_ttl_days int DEFAULT 14
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $func$
DECLARE
  v_caller record;
  v_app record;
  v_token text;
  v_token_hash text;
  v_onboarding_url text;
  v_first_name text;
  v_role_label text;
  v_dispatched int := 0;
  v_skipped int := 0;
  v_processed jsonb := '[]'::jsonb;
  v_errors jsonb := '[]'::jsonb;
  v_count int := 0;
  v_role_labels jsonb := jsonb_build_object(
    'leader', 'Líder de Tribo',
    'researcher', 'Pesquisador',
    'manager', 'Gerente de Projeto',
    'both', 'Pesquisador / Líder'
  );
BEGIN
  -- Authority gate
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member'::text) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member';
  END IF;

  FOR v_app IN
    SELECT a.id, a.applicant_name, a.email, a.role_applied, a.chapter,
           a.organization_id, a.cycle_id
    FROM public.selection_applications a
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE a.status = 'submitted'
      AND c.status = 'open'
      AND a.ai_analysis IS NULL  -- skip candidates already in active pipeline
      AND a.consent_ai_analysis_at IS NULL  -- and those who gave consent (token consumed)
      AND NOT EXISTS (
        SELECT 1 FROM public.onboarding_tokens t
        WHERE t.source_id = a.id
          AND t.source_type = 'pmi_application'
          AND t.expires_at > now()
          AND t.consumed_at IS NULL
      )
    ORDER BY a.created_at ASC
  LOOP
    v_count := v_count + 1;
    IF p_max_count IS NOT NULL AND v_count > p_max_count THEN
      EXIT;
    END IF;

    v_first_name := split_part(v_app.applicant_name, ' ', 1);
    v_role_label := COALESCE(v_role_labels->>v_app.role_applied, v_app.role_applied, 'Voluntário');

    IF p_dry_run THEN
      v_processed := v_processed || jsonb_build_object(
        'application_id', v_app.id,
        'applicant_name', v_app.applicant_name,
        'email', v_app.email,
        'chapter', v_app.chapter,
        'role_applied', v_app.role_applied,
        'role_label', v_role_label,
        'first_name', v_first_name,
        'would_dispatch', true
      );
      v_dispatched := v_dispatched + 1;
      CONTINUE;
    END IF;

    BEGIN
      v_token := translate(
        regexp_replace(encode(extensions.gen_random_bytes(32), 'base64'), '=+$', '', 'g'),
        '+/',
        '-_'
      );
      v_token_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');

      INSERT INTO public.onboarding_tokens (
        token, source_type, source_id, scopes,
        issued_at, expires_at, issued_by, organization_id
      ) VALUES (
        v_token,
        'pmi_application',
        v_app.id,
        ARRAY['profile_completion', 'video_screening', 'consent_giving'],
        now(),
        now() + (p_ttl_days || ' days')::interval,
        v_caller.id,
        v_app.organization_id
      );

      v_onboarding_url := 'https://nucleoia.vitormr.dev/pmi-onboarding/' || v_token;

      PERFORM public.campaign_send_one_off(
        p_template_slug := 'pmi_welcome_with_token',
        p_to_email := v_app.email,
        p_variables := jsonb_build_object(
          'first_name', v_first_name,
          'role_label', v_role_label,
          'chapter', COALESCE(v_app.chapter, 'Núcleo IA & GP'),
          'onboarding_url', v_onboarding_url,
          'expires_in_days', p_ttl_days
        ),
        p_metadata := jsonb_build_object(
          'source', 'dispatch_pending_welcomes',
          'application_id', v_app.id,
          'onboarding_token_hash', v_token_hash,
          'rpc_version', 'p92_phase_f_v1'
        )
      );

      v_dispatched := v_dispatched + 1;
      v_processed := v_processed || jsonb_build_object(
        'application_id', v_app.id,
        'applicant_name', v_app.applicant_name,
        'email', v_app.email,
        'token_hash', v_token_hash,
        'expires_at', (now() + (p_ttl_days || ' days')::interval)::text,
        'dispatched', true
      );

      INSERT INTO public.admin_audit_log (
        actor_id, action, target_type, target_id, changes, metadata
      ) VALUES (
        v_caller.id,
        'selection.bulk_welcome_dispatched',
        'selection_application',
        v_app.id,
        jsonb_build_object(
          'token_hash', v_token_hash,
          'expires_in_days', p_ttl_days,
          'email', v_app.email
        ),
        jsonb_build_object(
          'source', 'dispatch_pending_welcomes',
          'rpc_version', 'p92_phase_f_v1',
          'cycle_id', v_app.cycle_id,
          'incident', 'p91-bulk-import-skip-welcome'
        )
      );

    EXCEPTION WHEN OTHERS THEN
      v_skipped := v_skipped + 1;
      v_errors := v_errors || jsonb_build_object(
        'application_id', v_app.id,
        'applicant_name', v_app.applicant_name,
        'error', SQLERRM
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'dispatched', v_dispatched,
    'skipped', v_skipped,
    'processed', v_processed,
    'errors', v_errors,
    'run_at', now()
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.dispatch_pending_welcomes(boolean, int, int) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dispatch_pending_welcomes(boolean, int, int) TO authenticated;

COMMENT ON FUNCTION public.dispatch_pending_welcomes(boolean, int, int) IS
'Bulk dispatch onboarding tokens + welcome emails para selection_applications '
'status=submitted no current open cycle sem token ativo. Default dry_run=true. '
'Usage: SELECT dispatch_pending_welcomes(false) para executar live. '
'p_max_count limita batch size. p_ttl_days controla token TTL (default 14d). '
'Authority: manage_member. Audit: admin_audit_log entry per dispatch.';

NOTIFY pgrst, 'reload schema';
