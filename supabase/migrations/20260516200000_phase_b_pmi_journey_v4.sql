-- =====================================================================
-- Migration: phase_b_pmi_journey_v4
-- Date: 2026-04-29 (slot 20260516200000 in series convention)
-- Author: Vitor M. Rodovalho (GP) + Claude Code (autonomous review p81)
-- Spec: docs/specs/PMI_JOURNEY_V4_REVIEW.md (PM-approved 2026-04-28)
--
-- Source: specs/p81-pmi-vep-journey/migration_20260429_pmi_journey_v4.sql
-- Modifications baked in:
--   B1: extend selection_applications.role_applied CHECK to include 'manager'
--   B2 (corrected): PARTIAL COMPOUND UNIQUE on (vep_application_id, vep_opportunity_id)
--                    Preserves dual-track triaged_to_leader rows (5 confirmed pairs).
--                    NO DELETEs — original review's DELETE plan was wrong; rows are legitimate.
--   B3: campaign_send_one_off wrapper for slug-based template lookup
--   R2: consume_onboarding_token excludes interview_questions from payload
--   R5: consume_onboarding_token includes onboarding_progress
--   R6: trigger renamed trg_supersede_ai_suggestions_on_consent_revoke
--   R7: submit_evaluation extended with p_ai_suggestion_id param (lineage atomic)
--   R8: update_pmi_onboarding_step token-auth wrapper (PMI candidate pre-member)
-- =====================================================================

-- ---------------------------------------------------------------------
-- B1: extend role_applied to include 'manager' (vep_opportunities.role_default supports it)
-- ---------------------------------------------------------------------
ALTER TABLE public.selection_applications
  DROP CONSTRAINT IF EXISTS selection_applications_role_applied_check;
ALTER TABLE public.selection_applications
  ADD CONSTRAINT selection_applications_role_applied_check
  CHECK (role_applied = ANY (ARRAY['researcher','leader','both','manager']));

-- ---------------------------------------------------------------------
-- B2: partial compound UNIQUE — preserves dual-track triaged_to_leader (5 pairs)
-- ---------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uq_selection_applications_vep_app_opp
  ON public.selection_applications(vep_application_id, vep_opportunity_id)
  WHERE vep_application_id IS NOT NULL AND vep_opportunity_id IS NOT NULL;

-- ---------------------------------------------------------------------
-- B3: campaign_send_one_off wrapper (slug-based template lookup)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.campaign_send_one_off(
  p_template_slug text,
  p_to_email text,
  p_variables jsonb DEFAULT '{}'::jsonb,
  p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_template_id uuid;
BEGIN
  SELECT id INTO v_template_id
  FROM public.campaign_templates
  WHERE slug = p_template_slug;

  IF v_template_id IS NULL THEN
    RAISE EXCEPTION 'Template not found: %', p_template_slug
      USING ERRCODE = 'no_data_found';
  END IF;

  RETURN public.admin_send_campaign(
    p_template_id := v_template_id,
    p_audience_filter := '{}'::jsonb,
    p_scheduled_at := NULL,
    p_external_contacts := jsonb_build_array(jsonb_build_object(
      'email', p_to_email,
      'variables', p_variables,
      'metadata', p_metadata
    ))
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.campaign_send_one_off(text, text, jsonb, jsonb) TO service_role;

COMMENT ON FUNCTION public.campaign_send_one_off(text, text, jsonb, jsonb) IS
  'One-off transactional email wrapper. Looks up campaign_templates by slug, builds external_contacts payload, delegates to admin_send_campaign. Used by Cloudflare workers (e.g., pmi-vep-sync welcome).';

-- ---------------------------------------------------------------------
-- 1. HELPER FUNCTION: set_updated_at_v4
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at_v4()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------
-- 2. TABLE: selection_evaluation_ai_suggestions
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.selection_evaluation_ai_suggestions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES public.selection_applications(id) ON DELETE CASCADE,
  evaluation_type text NOT NULL CHECK (evaluation_type IN ('objective', 'interview', 'leader_extra')),

  suggested_scores jsonb NOT NULL,
  suggested_criterion_notes jsonb NOT NULL DEFAULT '{}'::jsonb,
  suggested_overall_summary text,
  suggested_weighted_subtotal numeric,

  model_provider text NOT NULL,
  model_name text NOT NULL,
  prompt_version text NOT NULL,
  generation_inputs jsonb,
  generation_cost_usd numeric,
  generation_latency_ms integer,

  used_in_evaluation_id uuid REFERENCES public.selection_evaluations(id) ON DELETE SET NULL,
  superseded_by uuid REFERENCES public.selection_evaluation_ai_suggestions(id) ON DELETE SET NULL,

  generated_at timestamptz NOT NULL DEFAULT now(),
  consumed_at timestamptz,

  organization_id uuid NOT NULL DEFAULT auth_org(),

  consent_snapshot_at timestamptz NOT NULL
);

COMMENT ON TABLE public.selection_evaluation_ai_suggestions IS
  'AI-proposed evaluation scores. Linked to humanly-confirmed selection_evaluations row via used_in_evaluation_id. Versioned by (model_name, prompt_version). Insertion gated by active consent trigger.';

CREATE INDEX IF NOT EXISTS idx_ai_suggestions_app_type_active
  ON public.selection_evaluation_ai_suggestions(application_id, evaluation_type)
  WHERE superseded_by IS NULL;

CREATE INDEX IF NOT EXISTS idx_ai_suggestions_consumed
  ON public.selection_evaluation_ai_suggestions(used_in_evaluation_id)
  WHERE used_in_evaluation_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_ai_suggestions_generated_at
  ON public.selection_evaluation_ai_suggestions(generated_at DESC);

ALTER TABLE public.selection_evaluation_ai_suggestions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rpc_only_deny_all ON public.selection_evaluation_ai_suggestions;
CREATE POLICY rpc_only_deny_all
  ON public.selection_evaluation_ai_suggestions
  FOR ALL
  USING (false);

DROP POLICY IF EXISTS ai_suggestions_v4_org_scope ON public.selection_evaluation_ai_suggestions;
CREATE POLICY ai_suggestions_v4_org_scope
  ON public.selection_evaluation_ai_suggestions
  AS RESTRICTIVE
  FOR ALL
  USING ((organization_id = auth_org()) OR (organization_id IS NULL))
  WITH CHECK ((organization_id = auth_org()) OR (organization_id IS NULL));

-- ---------------------------------------------------------------------
-- 3. TABLE: pmi_video_screenings
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.pmi_video_screenings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES public.selection_applications(id) ON DELETE CASCADE,

  pillar text NOT NULL CHECK (pillar IN (
    'background', 'communication', 'proactivity', 'teamwork', 'culture_alignment'
  )),
  question_index integer NOT NULL,
  question_text text NOT NULL,

  storage_provider text NOT NULL CHECK (storage_provider IN (
    'google_drive', 'youtube_unlisted', 'opted_out'
  )),
  drive_folder_id text,
  drive_file_id text,
  drive_file_name text,
  youtube_url text,

  duration_seconds integer,
  file_size_bytes bigint,
  mime_type text,

  transcription text,
  transcription_provider text,
  transcription_model_version text,
  transcription_at timestamptz,
  transcription_confidence numeric,

  status text NOT NULL DEFAULT 'pending_upload' CHECK (status IN (
    'pending_upload', 'uploaded', 'transcribing', 'transcribed', 'failed', 'opted_out'
  )),
  failure_reason text,
  retry_count integer NOT NULL DEFAULT 0,

  uploaded_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  organization_id uuid NOT NULL DEFAULT auth_org(),

  CONSTRAINT pmi_video_screenings_uniq_per_question
    UNIQUE (application_id, pillar, question_index),

  CONSTRAINT pmi_video_screenings_storage_consistency CHECK (
    (storage_provider = 'opted_out' AND drive_file_id IS NULL AND youtube_url IS NULL) OR
    (storage_provider = 'google_drive' AND drive_file_id IS NOT NULL) OR
    (storage_provider = 'youtube_unlisted' AND youtube_url IS NOT NULL)
  )
);

COMMENT ON TABLE public.pmi_video_screenings IS
  'Video screenings (assíncronos) por candidato e pillar. Drive default, YouTube unlisted fallback, opted_out se candidato preferir entrevista ao vivo. Transcrição alimenta ai-interview-drafter.';

CREATE INDEX IF NOT EXISTS idx_video_screenings_app
  ON public.pmi_video_screenings(application_id);

CREATE INDEX IF NOT EXISTS idx_video_screenings_status_pending
  ON public.pmi_video_screenings(status)
  WHERE status IN ('uploaded', 'transcribing', 'failed');

DROP TRIGGER IF EXISTS trg_video_screenings_updated_at ON public.pmi_video_screenings;
CREATE TRIGGER trg_video_screenings_updated_at
  BEFORE UPDATE ON public.pmi_video_screenings
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at_v4();

ALTER TABLE public.pmi_video_screenings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rpc_only_deny_all ON public.pmi_video_screenings;
CREATE POLICY rpc_only_deny_all
  ON public.pmi_video_screenings
  FOR ALL
  USING (false);

DROP POLICY IF EXISTS video_screenings_v4_org_scope ON public.pmi_video_screenings;
CREATE POLICY video_screenings_v4_org_scope
  ON public.pmi_video_screenings
  AS RESTRICTIVE
  FOR ALL
  USING ((organization_id = auth_org()) OR (organization_id IS NULL))
  WITH CHECK ((organization_id = auth_org()) OR (organization_id IS NULL));

-- ---------------------------------------------------------------------
-- 4. TABLE: onboarding_tokens
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.onboarding_tokens (
  token text PRIMARY KEY,

  source_type text NOT NULL CHECK (source_type IN (
    'pmi_application',
    'initiative_invitation',
    'direct_assignment'
  )),
  source_id uuid NOT NULL,

  scopes text[] NOT NULL DEFAULT ARRAY['profile_completion'],

  issued_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  last_accessed_at timestamptz,
  access_count integer NOT NULL DEFAULT 0,

  issued_by uuid,
  issued_by_worker text,

  organization_id uuid NOT NULL DEFAULT auth_org()
);

COMMENT ON TABLE public.onboarding_tokens IS
  'Token de uso (potencialmente multi-acesso com TTL) para portal de onboarding sem Supabase Auth. Track-agnostic via source_type.';

CREATE INDEX IF NOT EXISTS idx_onboarding_tokens_source
  ON public.onboarding_tokens(source_type, source_id);

CREATE INDEX IF NOT EXISTS idx_onboarding_tokens_expiry_unconsumed
  ON public.onboarding_tokens(expires_at)
  WHERE consumed_at IS NULL;

ALTER TABLE public.onboarding_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rpc_only_deny_all ON public.onboarding_tokens;
CREATE POLICY rpc_only_deny_all
  ON public.onboarding_tokens
  FOR ALL
  USING (false);

DROP POLICY IF EXISTS onboarding_tokens_v4_org_scope ON public.onboarding_tokens;
CREATE POLICY onboarding_tokens_v4_org_scope
  ON public.onboarding_tokens
  AS RESTRICTIVE
  FOR ALL
  USING ((organization_id = auth_org()) OR (organization_id IS NULL))
  WITH CHECK ((organization_id = auth_org()) OR (organization_id IS NULL));

-- ---------------------------------------------------------------------
-- 5. TABLE: cron_run_log
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cron_run_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  worker_name text NOT NULL,
  scheduled_for timestamptz NOT NULL,
  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  status text NOT NULL DEFAULT 'running' CHECK (status IN (
    'running', 'success', 'failed', 'skipped', 'zombie'
  )),
  metrics jsonb NOT NULL DEFAULT '{}'::jsonb,
  errors jsonb NOT NULL DEFAULT '[]'::jsonb,
  retry_of uuid REFERENCES public.cron_run_log(id) ON DELETE SET NULL,

  organization_id uuid NOT NULL DEFAULT auth_org()
);

COMMENT ON TABLE public.cron_run_log IS
  'Log de execução de workers cron. Suporta self-healing: workers consultam último success para decidir se rodam.';

CREATE INDEX IF NOT EXISTS idx_cron_run_log_worker_status
  ON public.cron_run_log(worker_name, status, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_cron_run_log_recent
  ON public.cron_run_log(worker_name, started_at DESC);

ALTER TABLE public.cron_run_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rpc_only_deny_all ON public.cron_run_log;
CREATE POLICY rpc_only_deny_all
  ON public.cron_run_log
  FOR ALL
  USING (false);

DROP POLICY IF EXISTS cron_run_log_v4_org_scope ON public.cron_run_log;
CREATE POLICY cron_run_log_v4_org_scope
  ON public.cron_run_log
  AS RESTRICTIVE
  FOR ALL
  USING ((organization_id = auth_org()) OR (organization_id IS NULL))
  WITH CHECK ((organization_id = auth_org()) OR (organization_id IS NULL));

-- ---------------------------------------------------------------------
-- 6. TRIGGER FUNCTIONS (LGPD)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_ai_consent_at_suggestion_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_consent_at timestamptz;
  v_revoked_at timestamptz;
BEGIN
  SELECT consent_ai_analysis_at, consent_ai_analysis_revoked_at
    INTO v_consent_at, v_revoked_at
  FROM selection_applications
  WHERE id = NEW.application_id;

  IF v_consent_at IS NULL OR v_revoked_at IS NOT NULL THEN
    RAISE EXCEPTION 'Cannot generate AI suggestion for application % without active consent (consent_at=%, revoked_at=%)',
      NEW.application_id, v_consent_at, v_revoked_at
      USING ERRCODE = 'check_violation';
  END IF;

  NEW.consent_snapshot_at := v_consent_at;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_consent_revocation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.consent_ai_analysis_revoked_at IS NOT NULL
     AND (OLD.consent_ai_analysis_revoked_at IS NULL OR OLD.consent_ai_analysis_revoked_at != NEW.consent_ai_analysis_revoked_at) THEN

    UPDATE selection_evaluation_ai_suggestions
       SET superseded_by = id
     WHERE application_id = NEW.id
       AND superseded_by IS NULL
       AND used_in_evaluation_id IS NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_ai_consent ON public.selection_evaluation_ai_suggestions;
CREATE TRIGGER enforce_ai_consent
  BEFORE INSERT ON public.selection_evaluation_ai_suggestions
  FOR EACH ROW
  EXECUTE FUNCTION public.check_ai_consent_at_suggestion_insert();

-- R6: rename trigger
DROP TRIGGER IF EXISTS on_consent_revoke ON public.selection_applications;
DROP TRIGGER IF EXISTS trg_supersede_ai_suggestions_on_consent_revoke ON public.selection_applications;
CREATE TRIGGER trg_supersede_ai_suggestions_on_consent_revoke
  AFTER UPDATE ON public.selection_applications
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_consent_revocation();

-- ---------------------------------------------------------------------
-- 7. VIEWS
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_cron_last_success AS
SELECT DISTINCT ON (worker_name)
  worker_name,
  scheduled_for,
  completed_at,
  metrics,
  organization_id
FROM public.cron_run_log
WHERE status = 'success'
ORDER BY worker_name, completed_at DESC;

COMMENT ON VIEW public.v_cron_last_success IS
  'Helper para self-healing: workers consultam essa view para decidir se rodam (gap > cadência → executa).';

CREATE OR REPLACE VIEW public.v_ai_human_concordance AS
WITH paired AS (
  SELECT
    s.evaluation_type,
    s.model_name,
    s.prompt_version,
    s.id AS suggestion_id,
    e.id AS evaluation_id,
    s.suggested_scores,
    e.scores AS human_scores,
    s.organization_id
  FROM public.selection_evaluation_ai_suggestions s
  JOIN public.selection_evaluations e ON e.id = s.used_in_evaluation_id
)
SELECT
  p.evaluation_type,
  p.model_name,
  p.prompt_version,
  k.criterion_key,
  COUNT(*) AS n_pairs,
  AVG(ABS(s_score - h_score)) AS mae,
  AVG((s_score - h_score) * (s_score - h_score)) AS mse,
  STDDEV(s_score - h_score) AS stddev_diff,
  AVG(s_score) AS mean_ai_score,
  AVG(h_score) AS mean_human_score
FROM paired p
CROSS JOIN LATERAL (
  SELECT
    key AS criterion_key,
    (p.suggested_scores ->> key)::numeric AS s_score,
    (p.human_scores ->> key)::numeric AS h_score
  FROM jsonb_object_keys(p.suggested_scores) AS key
  WHERE p.human_scores ? key
) k
WHERE k.s_score IS NOT NULL AND k.h_score IS NOT NULL
GROUP BY p.evaluation_type, p.model_name, p.prompt_version, k.criterion_key;

COMMENT ON VIEW public.v_ai_human_concordance IS
  'Métricas de concordância AI-humano por (evaluation_type, model, prompt_version, criterion). MAE > 2 indica drift do prompt; investigar.';

-- ---------------------------------------------------------------------
-- 8. RPCs
-- ---------------------------------------------------------------------

-- 8.1 get_ai_suggestion
CREATE OR REPLACE FUNCTION public.get_ai_suggestion(
  p_application_id uuid,
  p_evaluation_type text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result jsonb;
  v_authorized boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM selection_applications a
    JOIN selection_committee sc ON sc.cycle_id = a.cycle_id
    JOIN members m ON m.id = sc.member_id
    WHERE a.id = p_application_id
      AND m.auth_id = auth.uid()
  ) INTO v_authorized;

  IF NOT v_authorized THEN
    RAISE EXCEPTION 'Not authorized to read AI suggestions for this application'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT jsonb_build_object(
    'exists', true,
    'id', s.id,
    'suggested_scores', s.suggested_scores,
    'suggested_criterion_notes', s.suggested_criterion_notes,
    'suggested_overall_summary', s.suggested_overall_summary,
    'suggested_weighted_subtotal', s.suggested_weighted_subtotal,
    'model_provider', s.model_provider,
    'model_name', s.model_name,
    'prompt_version', s.prompt_version,
    'generated_at', s.generated_at,
    'is_consumed', s.consumed_at IS NOT NULL,
    'used_in_evaluation_id', s.used_in_evaluation_id
  )
    INTO v_result
  FROM selection_evaluation_ai_suggestions s
  WHERE s.application_id = p_application_id
    AND s.evaluation_type = p_evaluation_type
    AND s.superseded_by IS NULL
  ORDER BY s.generated_at DESC
  LIMIT 1;

  RETURN COALESCE(v_result, jsonb_build_object('exists', false));
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_ai_suggestion(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.get_ai_suggestion(uuid, text) IS
  'Retorna a AI suggestion mais recente (não superseded) para um par (application_id, evaluation_type). UI do form de evaluation chama para pre-fill HITL.';

-- 8.2 consume_onboarding_token (R5 + R2 modifications)
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

    -- R5: include onboarding_progress for the candidate
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
        -- R2: REMOVED interview_questions (PII / scope leak — candidate sees them DURING interview)
      ),
      'onboarding_progress', v_progress,
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

COMMENT ON FUNCTION public.consume_onboarding_token(text) IS
  'Valida token de onboarding e retorna payload contextualizado por source_type. R2: interview_questions excluded (scope leak). R5: includes onboarding_progress. Atomic increment + first-consumption mark.';

-- 8.3 register_video_screening
CREATE OR REPLACE FUNCTION public.register_video_screening(
  p_token text,
  p_pillar text,
  p_question_index integer,
  p_question_text text,
  p_storage_provider text,
  p_drive_file_id text DEFAULT NULL,
  p_drive_folder_id text DEFAULT NULL,
  p_drive_file_name text DEFAULT NULL,
  p_youtube_url text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_token_row onboarding_tokens%ROWTYPE;
  v_application_id uuid;
  v_screening_id uuid;
  v_status text;
BEGIN
  SELECT * INTO v_token_row
  FROM onboarding_tokens
  WHERE token = p_token
    AND expires_at > now()
    AND 'video_screening' = ANY(scopes);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid token or missing video_screening scope'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_token_row.source_type <> 'pmi_application' THEN
    RAISE EXCEPTION 'Token source_type does not support video screening (got %)', v_token_row.source_type;
  END IF;

  v_application_id := v_token_row.source_id;

  v_status := CASE
    WHEN p_storage_provider = 'opted_out' THEN 'opted_out'
    ELSE 'uploaded'
  END;

  IF p_storage_provider = 'google_drive' AND p_drive_file_id IS NULL THEN
    RAISE EXCEPTION 'drive_file_id required when storage_provider=google_drive';
  END IF;
  IF p_storage_provider = 'youtube_unlisted' AND p_youtube_url IS NULL THEN
    RAISE EXCEPTION 'youtube_url required when storage_provider=youtube_unlisted';
  END IF;

  INSERT INTO pmi_video_screenings (
    application_id, pillar, question_index, question_text,
    storage_provider, drive_file_id, drive_folder_id, drive_file_name, youtube_url,
    status, uploaded_at
  ) VALUES (
    v_application_id, p_pillar, p_question_index, p_question_text,
    p_storage_provider, p_drive_file_id, p_drive_folder_id, p_drive_file_name, p_youtube_url,
    v_status,
    CASE WHEN v_status = 'uploaded' THEN now() ELSE NULL END
  )
  ON CONFLICT (application_id, pillar, question_index) DO UPDATE SET
    storage_provider = EXCLUDED.storage_provider,
    drive_file_id = EXCLUDED.drive_file_id,
    drive_folder_id = EXCLUDED.drive_folder_id,
    drive_file_name = EXCLUDED.drive_file_name,
    youtube_url = EXCLUDED.youtube_url,
    status = EXCLUDED.status,
    uploaded_at = EXCLUDED.uploaded_at,
    failure_reason = NULL,
    retry_count = 0,
    updated_at = now()
  RETURNING id INTO v_screening_id;

  RETURN jsonb_build_object(
    'screening_id', v_screening_id,
    'status', v_status,
    'success', true
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_video_screening(
  text, text, integer, text, text, text, text, text, text
) TO anon, authenticated;

COMMENT ON FUNCTION public.register_video_screening(text, text, integer, text, text, text, text, text, text) IS
  'Registra upload de vídeo de screening. Token-authenticated (token deve ter scope video_screening). Idempotente via UNIQUE.';

-- 8.4 log_cron_run_start
CREATE OR REPLACE FUNCTION public.log_cron_run_start(
  p_worker_name text,
  p_scheduled_for timestamptz,
  p_metrics jsonb DEFAULT '{}'::jsonb
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid;
BEGIN
  UPDATE cron_run_log
     SET status = 'zombie', completed_at = now()
   WHERE worker_name = p_worker_name
     AND status = 'running'
     AND started_at < now() - interval '30 minutes';

  INSERT INTO cron_run_log (worker_name, scheduled_for, metrics)
  VALUES (p_worker_name, p_scheduled_for, p_metrics)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.log_cron_run_complete(
  p_run_id uuid,
  p_status text,
  p_metrics jsonb DEFAULT '{}'::jsonb,
  p_errors jsonb DEFAULT '[]'::jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_status NOT IN ('success', 'failed', 'skipped') THEN
    RAISE EXCEPTION 'Invalid terminal status: %', p_status;
  END IF;

  UPDATE cron_run_log
     SET status = p_status,
         completed_at = now(),
         metrics = metrics || p_metrics,
         errors = p_errors
   WHERE id = p_run_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.log_cron_run_start(text, timestamptz, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.log_cron_run_complete(uuid, text, jsonb, jsonb) TO service_role;

-- 8.5 R7: extend submit_evaluation with p_ai_suggestion_id
DROP FUNCTION IF EXISTS public.submit_evaluation(uuid, text, jsonb, text);
CREATE OR REPLACE FUNCTION public.submit_evaluation(
  p_application_id uuid,
  p_evaluation_type text,
  p_scores jsonb,
  p_notes text DEFAULT NULL,
  p_ai_suggestion_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller record;
  v_app record;
  v_cycle record;
  v_committee record;
  v_criteria jsonb;
  v_criterion jsonb;
  v_key text;
  v_score numeric;
  v_weight numeric;
  v_weighted_sum numeric := 0;
  v_eval_id uuid;
  v_total_evaluators int;
  v_submitted_count int;
  v_all_subtotals numeric[];
  v_pert_score numeric;
  v_min_sub numeric;
  v_max_sub numeric;
  v_avg_sub numeric;
  v_cutoff numeric;
  v_median numeric;
  v_new_status text;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: not a committee member';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.selection_evaluations
    WHERE application_id = p_application_id
      AND evaluator_id = v_caller.id
      AND evaluation_type = p_evaluation_type
      AND submitted_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Evaluation already submitted and locked';
  END IF;

  v_criteria := CASE p_evaluation_type
    WHEN 'objective' THEN v_cycle.objective_criteria
    WHEN 'interview' THEN v_cycle.interview_criteria
    WHEN 'leader_extra' THEN v_cycle.leader_extra_criteria
    ELSE '[]'::jsonb
  END;

  FOR v_criterion IN SELECT * FROM jsonb_array_elements(v_criteria)
  LOOP
    v_key := v_criterion ->> 'key';
    v_weight := COALESCE((v_criterion ->> 'weight')::numeric, 1);

    IF NOT (p_scores ? v_key) THEN
      RAISE EXCEPTION 'Missing score for criterion: %', v_key;
    END IF;

    v_score := (p_scores ->> v_key)::numeric;

    IF v_score IS NULL THEN
      RAISE EXCEPTION 'Score for % must be numeric', v_key;
    END IF;

    v_weighted_sum := v_weighted_sum + (v_weight * v_score);
  END LOOP;

  INSERT INTO public.selection_evaluations (
    application_id, evaluator_id, evaluation_type,
    scores, weighted_subtotal, notes, submitted_at
  ) VALUES (
    p_application_id, v_caller.id, p_evaluation_type,
    p_scores, ROUND(v_weighted_sum, 2), p_notes, now()
  )
  ON CONFLICT (application_id, evaluator_id, evaluation_type)
  DO UPDATE SET
    scores = EXCLUDED.scores,
    weighted_subtotal = EXCLUDED.weighted_subtotal,
    notes = EXCLUDED.notes,
    submitted_at = now()
  RETURNING id INTO v_eval_id;

  -- R7: link AI suggestion lineage if provided
  IF p_ai_suggestion_id IS NOT NULL THEN
    UPDATE public.selection_evaluation_ai_suggestions
       SET used_in_evaluation_id = v_eval_id,
           consumed_at = COALESCE(consumed_at, now())
     WHERE id = p_ai_suggestion_id
       AND application_id = p_application_id
       AND evaluation_type = p_evaluation_type
       AND superseded_by IS NULL;
  END IF;

  SELECT COUNT(*) INTO v_total_evaluators
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND role IN ('evaluator', 'lead');

  SELECT COUNT(*) INTO v_submitted_count
  FROM public.selection_evaluations
  WHERE application_id = p_application_id
    AND evaluation_type = p_evaluation_type
    AND submitted_at IS NOT NULL;

  IF v_submitted_count >= v_cycle.min_evaluators THEN
    SELECT ARRAY_AGG(weighted_subtotal ORDER BY weighted_subtotal)
    INTO v_all_subtotals
    FROM public.selection_evaluations
    WHERE application_id = p_application_id
      AND evaluation_type = p_evaluation_type
      AND submitted_at IS NOT NULL;

    v_min_sub := v_all_subtotals[1];
    v_max_sub := v_all_subtotals[array_upper(v_all_subtotals, 1)];
    SELECT AVG(unnest) INTO v_avg_sub FROM unnest(v_all_subtotals);

    v_pert_score := ROUND((2 * v_min_sub + 4 * v_avg_sub + 2 * v_max_sub) / 8, 2);

    IF p_evaluation_type = 'objective' THEN
      UPDATE public.selection_applications
      SET objective_score_avg = v_pert_score,
          updated_at = now()
      WHERE id = p_application_id;

      SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY objective_score_avg)
      INTO v_median
      FROM public.selection_applications
      WHERE cycle_id = v_app.cycle_id
        AND objective_score_avg IS NOT NULL;

      v_cutoff := ROUND(COALESCE(v_median, 0) * 0.75, 2);

      IF v_pert_score < v_cutoff AND v_cutoff > 0 THEN
        v_new_status := 'objective_cutoff';
      ELSE
        v_new_status := 'interview_pending';
      END IF;

      UPDATE public.selection_applications
      SET status = v_new_status, updated_at = now()
      WHERE id = p_application_id
        AND status IN ('submitted', 'screening', 'objective_eval');

    ELSIF p_evaluation_type = 'interview' THEN
      UPDATE public.selection_applications
      SET interview_score = v_pert_score,
          final_score = COALESCE(objective_score_avg, 0) + v_pert_score,
          status = 'final_eval',
          updated_at = now()
      WHERE id = p_application_id;

    ELSIF p_evaluation_type = 'leader_extra' THEN
      UPDATE public.selection_applications
      SET objective_score_avg = COALESCE(objective_score_avg, 0) + v_pert_score,
          final_score = COALESCE(objective_score_avg, 0) + v_pert_score + COALESCE(interview_score, 0),
          updated_at = now()
      WHERE id = p_application_id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'evaluation_id', v_eval_id,
    'weighted_subtotal', ROUND(v_weighted_sum, 2),
    'all_submitted', v_submitted_count >= v_cycle.min_evaluators,
    'pert_score', v_pert_score,
    'new_status', v_new_status,
    'ai_suggestion_linked', p_ai_suggestion_id IS NOT NULL
  );
END;
$$;

COMMENT ON FUNCTION public.submit_evaluation(uuid, text, jsonb, text, uuid) IS
  'Submit human evaluation. R7: optional p_ai_suggestion_id atomically links lineage to AI suggestion (sets used_in_evaluation_id + consumed_at). V4: committee member or manage_platform.';

-- 8.6 R8: token-authenticated update_pmi_onboarding_step
CREATE OR REPLACE FUNCTION public.update_pmi_onboarding_step(
  p_token text,
  p_step_key text,
  p_status text DEFAULT 'completed',
  p_evidence_url text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_token_row onboarding_tokens%ROWTYPE;
  v_application_id uuid;
  v_step record;
  v_total int;
  v_completed int;
  v_all_done boolean;
BEGIN
  SELECT * INTO v_token_row
  FROM onboarding_tokens
  WHERE token = p_token
    AND expires_at > now()
    AND 'profile_completion' = ANY(scopes);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid token or missing profile_completion scope'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_token_row.source_type <> 'pmi_application' THEN
    RAISE EXCEPTION 'Token source_type % does not support PMI onboarding step update', v_token_row.source_type;
  END IF;

  v_application_id := v_token_row.source_id;

  IF p_status NOT IN ('completed', 'skipped', 'in_progress') THEN
    RAISE EXCEPTION 'Invalid status: must be completed, skipped, or in_progress';
  END IF;

  SELECT * INTO v_step
  FROM public.onboarding_progress
  WHERE application_id = v_application_id AND step_key = p_step_key;
  IF v_step IS NULL THEN
    RAISE EXCEPTION 'Onboarding step not found for application';
  END IF;

  UPDATE public.onboarding_progress
  SET status = p_status,
      completed_at = CASE WHEN p_status IN ('completed', 'skipped') THEN now() ELSE NULL END,
      evidence_url = COALESCE(p_evidence_url, evidence_url)
  WHERE application_id = v_application_id AND step_key = p_step_key;

  SELECT COUNT(*) INTO v_total FROM public.onboarding_progress WHERE application_id = v_application_id;
  SELECT COUNT(*) INTO v_completed FROM public.onboarding_progress
    WHERE application_id = v_application_id AND status IN ('completed', 'skipped');

  v_all_done := (v_completed = v_total AND v_total > 0);

  RETURN jsonb_build_object(
    'success', true,
    'step_key', p_step_key,
    'new_status', p_status,
    'all_done', v_all_done,
    'completed_steps', v_completed,
    'total_steps', v_total
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_pmi_onboarding_step(text, text, text, text) TO anon, authenticated;

COMMENT ON FUNCTION public.update_pmi_onboarding_step(text, text, text, text) IS
  'R8: PMI candidate (pre-member) updates own onboarding step via token. Auth via token + profile_completion scope. Does NOT trigger member activation — staff confirms via authenticated update_onboarding_step.';

-- ---------------------------------------------------------------------
-- 9. Reload PostgREST schema cache
-- ---------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';
