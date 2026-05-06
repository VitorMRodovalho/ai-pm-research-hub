-- ARM Onda 4 Fase 2 (p109): AI score validations (PM thumbs/override feedback)
--
-- Atende PM pain #1 (acertividade AI) — long-arc via human signal capture.
-- PM marca 👍/👎/override próximo aos scores AI inline. Cron weekly
-- `compute_ai_calibration_weekly` lerá esta tabela em Onda 5 para enriched signal
-- (não só final_score humano vs AI, mas também desacordo explícito por avaliador).
--
-- Schema:
--   - ai_purpose: 'sonnet_triage' | 'gemini_qualitative' (text + check)
--   - validation_action: 'agree' | 'disagree' | 'override' (text + check)
--   - ai_score / ai_verdict: snapshot do AI no momento da validação
--   - override_score: opcional, só quando action='override' em sonnet_triage
--   - Unique (app, validator, ai_purpose) — uma validação por pilar/validador (UPSERT permitido)
--
-- ADR ref: ADR-0074 (dual-model architecture); LGPD Art. 20 §1 (decisão humana é fonte autoritária)
-- ADR-0011: SECURITY DEFINER + can_by_member auth; ADR-0012: invariants 13/13 preserved
--
-- Rollback:
--   DROP FUNCTION list_my_ai_validations(uuid);
--   DROP FUNCTION record_ai_validation(uuid, text, text, numeric, text, numeric, text);
--   DROP TABLE ai_score_validations;

-- 1. Table
CREATE TABLE IF NOT EXISTS public.ai_score_validations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES public.selection_applications(id) ON DELETE CASCADE,
  validator_id uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  ai_purpose text NOT NULL,
  ai_model text,
  ai_score numeric,
  ai_verdict text,
  validation_action text NOT NULL,
  override_score numeric,
  comment text,
  validated_at timestamptz NOT NULL DEFAULT now(),
  organization_id uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906',
  CONSTRAINT ai_score_validations_purpose_check
    CHECK (ai_purpose IN ('sonnet_triage', 'gemini_qualitative')),
  CONSTRAINT ai_score_validations_action_check
    CHECK (validation_action IN ('agree', 'disagree', 'override')),
  CONSTRAINT ai_score_validations_override_score_range
    CHECK (override_score IS NULL OR (override_score >= 0 AND override_score <= 10)),
  CONSTRAINT ai_score_validations_override_implies_action
    CHECK ((override_score IS NULL) OR (validation_action = 'override')),
  CONSTRAINT ai_score_validations_override_only_for_triage
    CHECK ((validation_action <> 'override') OR (ai_purpose = 'sonnet_triage'))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_ai_score_validations_unique
  ON public.ai_score_validations (application_id, validator_id, ai_purpose);

CREATE INDEX IF NOT EXISTS ix_ai_score_validations_app
  ON public.ai_score_validations (application_id);

CREATE INDEX IF NOT EXISTS ix_ai_score_validations_validator
  ON public.ai_score_validations (validator_id);

CREATE INDEX IF NOT EXISTS ix_ai_score_validations_calibration
  ON public.ai_score_validations (ai_purpose, validated_at DESC, validation_action);

COMMENT ON TABLE public.ai_score_validations IS
  'p109 ARM Onda 4 Fase 2: validações humanas dos scores AI (Sonnet 4.6 triage + Gemini qualitative). Sinal explícito agree/disagree/override para enriquecer compute_ai_calibration_weekly em Onda 5. Uma validação por (app, validador, purpose) — UPSERT permitido.';
COMMENT ON COLUMN public.ai_score_validations.ai_score IS
  'Snapshot do score AI no momento da validação. Para sonnet_triage: 0-10. Para gemini_qualitative: deixar NULL (usar ai_verdict).';
COMMENT ON COLUMN public.ai_score_validations.ai_verdict IS
  'Snapshot do verdict AI no momento (yes|no|uncertain). Para gemini_qualitative apenas.';
COMMENT ON COLUMN public.ai_score_validations.validation_action IS
  'agree = thumbs up (PM concorda com AI). disagree = thumbs down (discorda mas não dá score próprio). override = PM dá score próprio em override_score (apenas sonnet_triage).';
COMMENT ON COLUMN public.ai_score_validations.override_score IS
  'Score humano 0-10 quando action=override (apenas sonnet_triage). NULL caso contrário.';

-- RLS rpc-only — bloqueia acesso direto
ALTER TABLE public.ai_score_validations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ai_score_validations_no_anon ON public.ai_score_validations;
CREATE POLICY ai_score_validations_no_anon
  ON public.ai_score_validations FOR ALL TO anon USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS ai_score_validations_rpc_only_authenticated ON public.ai_score_validations;
CREATE POLICY ai_score_validations_rpc_only_authenticated
  ON public.ai_score_validations FOR ALL TO authenticated USING (false) WITH CHECK (false);

REVOKE INSERT, UPDATE, DELETE ON public.ai_score_validations FROM authenticated, anon;

-- 2. RPC: record_ai_validation (UPSERT — substitui se existe)
CREATE OR REPLACE FUNCTION public.record_ai_validation(
  p_application_id uuid,
  p_ai_purpose text,
  p_validation_action text,
  p_ai_score numeric DEFAULT NULL,
  p_ai_verdict text DEFAULT NULL,
  p_ai_model text DEFAULT NULL,
  p_override_score numeric DEFAULT NULL,
  p_comment text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $func$
DECLARE
  v_caller record;
  v_app record;
  v_committee record;
  v_id uuid;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RETURN jsonb_build_object('error', 'Application not found');
  END IF;

  -- Auth: committee member of this cycle OR view_pii (admin)
  SELECT * INTO v_committee FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;
  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'view_pii'::text) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: not a committee member or admin');
  END IF;

  -- Validate inputs
  IF p_ai_purpose NOT IN ('sonnet_triage', 'gemini_qualitative') THEN
    RETURN jsonb_build_object('error', 'invalid ai_purpose');
  END IF;
  IF p_validation_action NOT IN ('agree', 'disagree', 'override') THEN
    RETURN jsonb_build_object('error', 'invalid validation_action');
  END IF;
  IF p_validation_action = 'override' AND p_ai_purpose <> 'sonnet_triage' THEN
    RETURN jsonb_build_object('error', 'override only valid for sonnet_triage');
  END IF;
  IF p_validation_action = 'override' AND (p_override_score IS NULL OR p_override_score < 0 OR p_override_score > 10) THEN
    RETURN jsonb_build_object('error', 'override_score (0-10) required when action=override');
  END IF;
  IF p_validation_action <> 'override' AND p_override_score IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'override_score only allowed when action=override');
  END IF;

  INSERT INTO public.ai_score_validations (
    application_id, validator_id, ai_purpose, ai_model, ai_score, ai_verdict,
    validation_action, override_score, comment, validated_at
  ) VALUES (
    p_application_id, v_caller.id, p_ai_purpose, p_ai_model, p_ai_score, p_ai_verdict,
    p_validation_action, p_override_score, NULLIF(trim(COALESCE(p_comment, '')), ''), now()
  )
  ON CONFLICT (application_id, validator_id, ai_purpose)
  DO UPDATE SET
    ai_model = EXCLUDED.ai_model,
    ai_score = EXCLUDED.ai_score,
    ai_verdict = EXCLUDED.ai_verdict,
    validation_action = EXCLUDED.validation_action,
    override_score = EXCLUDED.override_score,
    comment = EXCLUDED.comment,
    validated_at = now()
  RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'success', true,
    'id', v_id,
    'application_id', p_application_id,
    'ai_purpose', p_ai_purpose,
    'validation_action', p_validation_action,
    'override_score', p_override_score,
    'validated_at', now()
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.record_ai_validation(uuid, text, text, numeric, text, text, numeric, text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_ai_validation(uuid, text, text, numeric, text, text, numeric, text) TO authenticated;

COMMENT ON FUNCTION public.record_ai_validation(uuid, text, text, numeric, text, text, numeric, text) IS
  'p109 ARM Onda 4 Fase 2: registra (upsert) validação humana de score AI. Auth: committee member do ciclo OU view_pii. Calibration cron Onda 5 lê esta tabela.';

-- 3. RPC: list_my_ai_validations (reads only my validations for this app)
CREATE OR REPLACE FUNCTION public.list_my_ai_validations(p_application_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $func$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'id', v.id,
    'ai_purpose', v.ai_purpose,
    'ai_model', v.ai_model,
    'ai_score', v.ai_score,
    'ai_verdict', v.ai_verdict,
    'validation_action', v.validation_action,
    'override_score', v.override_score,
    'comment', v.comment,
    'validated_at', v.validated_at
  ))
  INTO v_result
  FROM public.ai_score_validations v
  WHERE v.application_id = p_application_id
    AND v.validator_id = v_caller_id;

  RETURN jsonb_build_object(
    'application_id', p_application_id,
    'validations', COALESCE(v_result, '[]'::jsonb)
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.list_my_ai_validations(uuid) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_my_ai_validations(uuid) TO authenticated;

COMMENT ON FUNCTION public.list_my_ai_validations(uuid) IS
  'p109 ARM Onda 4 Fase 2: retorna validações AI do próprio chamador para uma application. Frontend usa para preencher estado dos thumbs no inline AI panel.';

NOTIFY pgrst, 'reload schema';
