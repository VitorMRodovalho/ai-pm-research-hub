-- p117 follow-up: nudge campaign para candidatos que receberam token mas
-- não acessaram portal (ou token expirou sem uso). Triggered by audit p117 das
-- 17 apps em cycle3-2026-b2 que tem token mas consent_ai_analysis_at IS NULL.
--
-- Eligibility:
--   - cycle status='open'
--   - application status='submitted'
--   - consent_ai_analysis_at IS NULL
--   - NEVER accessed any token (last_accessed_at IS NULL across all tokens)
--     => excludes "declined at portal" 7 candidates (intentional opt-out signal)
--   - No nudge audit log entry in last 7 days (idempotência)
--
-- Two paths:
--   (a) Valid token exists, never accessed → reuse URL (token unchanged)
--   (b) Only expired tokens → re-issue token + dispatch with new URL
--
-- Default dry_run=true (safety, mirror dispatch_pending_welcomes).
--
-- Rollback:
--   DELETE FROM campaign_templates WHERE slug = 'pmi_consent_nudge';
--   DROP FUNCTION IF EXISTS public.dispatch_consent_nudge(boolean, int, int);

INSERT INTO public.campaign_templates (
  name, slug, subject, body_html, body_text, target_audience, category, variables
) VALUES (
  'PMI Consent Nudge — Reminder for Pending Onboarding',
  'pmi_consent_nudge',
  jsonb_build_object(
    'pt', 'Lembrete: complete o onboarding da sua candidatura ao Núcleo IA & GP',
    'en', 'Reminder: finish onboarding for your Núcleo IA & GP application',
    'es', 'Recordatorio: complete el onboarding de su candidatura al Núcleo IA & GP'
  ),
  jsonb_build_object(
    'pt', '<p>Olá <b>{{first_name}}</b>,</p>'
       || '<p>Sua candidatura como <b>{{role_label}}</b> em {{chapter}} foi recebida há alguns dias, mas ainda não completou o onboarding.</p>'
       || '<p>O onboarding leva ~2 minutos. Inclui o consentimento opcional para análise por IA, que ajuda o comitê a contextualizar sua candidatura.</p>'
       || '<p><a href="{{onboarding_url}}" style="background:#0066cc;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;">Completar onboarding</a></p>'
       || '<p><small>Link válido por {{expires_in_days}} dias. Se já completou ou prefere não dar consentimento de IA, ignore esta mensagem.</small></p>'
       || '<p>Equipe GP — Núcleo IA & GP</p>',
    'en', '<p>Hi <b>{{first_name}}</b>,</p>'
       || '<p>Your application as <b>{{role_label}}</b> at {{chapter}} was received a few days ago but onboarding is still pending.</p>'
       || '<p>Onboarding takes ~2 minutes. It includes the optional AI analysis consent, which helps the committee contextualize your application.</p>'
       || '<p><a href="{{onboarding_url}}" style="background:#0066cc;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;">Complete onboarding</a></p>'
       || '<p><small>Link valid for {{expires_in_days}} days. If you already completed or prefer not to grant AI consent, ignore this message.</small></p>'
       || '<p>GP Team — Núcleo IA & GP</p>',
    'es', '<p>Hola <b>{{first_name}}</b>,</p>'
       || '<p>Su candidatura como <b>{{role_label}}</b> en {{chapter}} fue recibida hace unos días pero el onboarding está pendiente.</p>'
       || '<p>El onboarding toma ~2 minutos. Incluye el consentimiento opcional para análisis por IA, que ayuda al comité a contextualizar su candidatura.</p>'
       || '<p><a href="{{onboarding_url}}" style="background:#0066cc;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;">Completar onboarding</a></p>'
       || '<p><small>Link válido por {{expires_in_days}} días. Si ya completó o prefiere no dar consentimiento de IA, ignore este mensaje.</small></p>'
       || '<p>Equipo GP — Núcleo IA & GP</p>'
  ),
  jsonb_build_object(
    'pt', 'Olá {{first_name}}!' || E'\n\n'
       || 'Sua candidatura como {{role_label}} em {{chapter}} foi recebida há alguns dias, mas o onboarding ainda está pendente.' || E'\n\n'
       || 'Complete em ~2 minutos: {{onboarding_url}}' || E'\n\n'
       || 'Link expira em {{expires_in_days}} dias. Se já completou ou prefere não dar consentimento de IA, ignore esta mensagem.' || E'\n\n'
       || 'Equipe GP — Núcleo IA & GP',
    'en', 'Hi {{first_name}}!' || E'\n\n'
       || 'Your application as {{role_label}} at {{chapter}} was received a few days ago. Onboarding is still pending.' || E'\n\n'
       || 'Complete in ~2 minutes: {{onboarding_url}}' || E'\n\n'
       || 'Link expires in {{expires_in_days}} days. If you already completed or prefer not to grant AI consent, ignore this.' || E'\n\n'
       || 'GP Team — Núcleo IA & GP',
    'es', 'Hola {{first_name}}!' || E'\n\n'
       || 'Su candidatura como {{role_label}} en {{chapter}} fue recibida hace unos días. El onboarding está pendiente.' || E'\n\n'
       || 'Complete en ~2 minutos: {{onboarding_url}}' || E'\n\n'
       || 'Link expira en {{expires_in_days}} días. Si ya completó o prefiere no dar consentimiento de IA, ignore.' || E'\n\n'
       || 'Equipo GP — Núcleo IA & GP'
  ),
  jsonb_build_object('type', 'external'),
  'onboarding',
  jsonb_build_object(
    'first_name', jsonb_build_object('type', 'text', 'required', true),
    'role_label', jsonb_build_object('type', 'text', 'required', true),
    'chapter', jsonb_build_object('type', 'text', 'required', true),
    'onboarding_url', jsonb_build_object('type', 'text', 'required', true),
    'expires_in_days', jsonb_build_object('type', 'number', 'required', true)
  )
)
ON CONFLICT (slug) DO UPDATE SET
  subject = EXCLUDED.subject,
  body_html = EXCLUDED.body_html,
  body_text = EXCLUDED.body_text,
  variables = EXCLUDED.variables,
  updated_at = now();

CREATE OR REPLACE FUNCTION public.dispatch_consent_nudge(
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
  v_existing_token record;
  v_path text;
  v_role_labels jsonb := jsonb_build_object(
    'leader', 'Líder de Tribo',
    'researcher', 'Pesquisador',
    'manager', 'Gerente de Projeto',
    'both', 'Pesquisador / Líder'
  );
BEGIN
  -- Authority gate (mirrors dispatch_pending_welcomes)
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
      AND a.consent_ai_analysis_at IS NULL
      AND a.consent_ai_analysis_revoked_at IS NULL
      -- At least one token was issued (ensures phase F dispatcher already covered this app)
      AND EXISTS (
        SELECT 1 FROM public.onboarding_tokens t
        WHERE t.source_id = a.id AND t.source_type = 'pmi_application'
      )
      -- NEVER accessed any token (excludes "declined at portal" intentional opt-out signal)
      AND NOT EXISTS (
        SELECT 1 FROM public.onboarding_tokens t
        WHERE t.source_id = a.id AND t.source_type = 'pmi_application'
          AND t.last_accessed_at IS NOT NULL
      )
      -- No nudge in last 7 days (idempotency)
      AND NOT EXISTS (
        SELECT 1 FROM public.admin_audit_log al
        WHERE al.target_type = 'selection_application'
          AND al.target_id = a.id
          AND al.action = 'selection.consent_nudge_dispatched'
          AND al.created_at > now() - interval '7 days'
      )
    ORDER BY a.created_at ASC
  LOOP
    v_count := v_count + 1;
    IF p_max_count IS NOT NULL AND v_count > p_max_count THEN
      EXIT;
    END IF;

    v_first_name := split_part(v_app.applicant_name, ' ', 1);
    v_role_label := COALESCE(v_role_labels->>v_app.role_applied, v_app.role_applied, 'Voluntário');

    -- Prefer reusing a still-valid token; else re-issue
    SELECT t.token, t.expires_at INTO v_existing_token
    FROM public.onboarding_tokens t
    WHERE t.source_id = v_app.id AND t.source_type = 'pmi_application'
      AND t.expires_at > now()
      AND t.consumed_at IS NULL
    ORDER BY t.expires_at DESC
    LIMIT 1;

    IF v_existing_token.token IS NOT NULL THEN
      v_path := 'reuse_valid_token';
      v_token := v_existing_token.token;
      v_onboarding_url := 'https://nucleoia.vitormr.dev/pmi-onboarding/' || v_token;
      v_token_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');
    ELSE
      v_path := 'reissue_expired_token';
      v_token := translate(
        regexp_replace(encode(extensions.gen_random_bytes(32), 'base64'), '=+$', '', 'g'),
        '+/',
        '-_'
      );
      v_token_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');
      v_onboarding_url := 'https://nucleoia.vitormr.dev/pmi-onboarding/' || v_token;
    END IF;

    IF p_dry_run THEN
      v_processed := v_processed || jsonb_build_object(
        'application_id', v_app.id,
        'applicant_name', v_app.applicant_name,
        'email', v_app.email,
        'chapter', v_app.chapter,
        'path', v_path,
        'would_dispatch', true
      );
      v_dispatched := v_dispatched + 1;
      CONTINUE;
    END IF;

    BEGIN
      -- Re-issue token if needed
      IF v_path = 'reissue_expired_token' THEN
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
      END IF;

      PERFORM public.campaign_send_one_off(
        p_template_slug := 'pmi_consent_nudge',
        p_to_email := v_app.email,
        p_variables := jsonb_build_object(
          'first_name', v_first_name,
          'role_label', v_role_label,
          'chapter', COALESCE(v_app.chapter, 'Núcleo IA & GP'),
          'onboarding_url', v_onboarding_url,
          'expires_in_days', p_ttl_days
        ),
        p_metadata := jsonb_build_object(
          'source', 'dispatch_consent_nudge',
          'application_id', v_app.id,
          'onboarding_token_hash', v_token_hash,
          'path', v_path,
          'rpc_version', 'p117_consent_nudge_v1'
        )
      );

      v_dispatched := v_dispatched + 1;
      v_processed := v_processed || jsonb_build_object(
        'application_id', v_app.id,
        'applicant_name', v_app.applicant_name,
        'email', v_app.email,
        'token_hash', v_token_hash,
        'path', v_path,
        'dispatched', true
      );

      INSERT INTO public.admin_audit_log (
        actor_id, action, target_type, target_id, changes, metadata
      ) VALUES (
        v_caller.id,
        'selection.consent_nudge_dispatched',
        'selection_application',
        v_app.id,
        jsonb_build_object(
          'token_hash', v_token_hash,
          'path', v_path,
          'expires_in_days', p_ttl_days,
          'email', v_app.email
        ),
        jsonb_build_object(
          'source', 'dispatch_consent_nudge',
          'rpc_version', 'p117_consent_nudge_v1',
          'cycle_id', v_app.cycle_id
        )
      );

      -- Resend rate-limit guard (5 req/sec hard cap; 0.3s = 3.3 req/sec safe)
      PERFORM pg_sleep(0.3);

    EXCEPTION WHEN OTHERS THEN
      v_skipped := v_skipped + 1;
      v_errors := v_errors || jsonb_build_object(
        'application_id', v_app.id,
        'applicant_name', v_app.applicant_name,
        'path', v_path,
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

REVOKE ALL ON FUNCTION public.dispatch_consent_nudge(boolean, int, int) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dispatch_consent_nudge(boolean, int, int) TO authenticated;

COMMENT ON FUNCTION public.dispatch_consent_nudge(boolean, int, int) IS
'p117 nudge campaign: reminder email para candidatos que receberam token mas nunca acessaram portal (ou cujo token expirou sem uso). Reusa token válido OR reissue se expirou. Idempotente: skip se nudge enviado nos últimos 7 dias. Default dry_run=true. Authority: manage_member. Audit: admin_audit_log action=selection.consent_nudge_dispatched.';

NOTIFY pgrst, 'reload schema';
