-- ARM Onda 3 (p108 cont.): ai_processing_log table + selection_applications triage columns + admin RPC
--
-- Foundation para Sub-itens 1+2 da Onda 3 ARM:
--   1. ai_processing_log: LGPD Art. 37 + Art. 20 §1 — registra cada call a modelo
--      (model + purpose + prompt_hash + token usage + duration). NUNCA conteúdo.
--      Substrato genérico: triage (Sonnet 4.6), briefing (Haiku 4.5), qualitative (Gemini, futuro).
--   2. selection_applications.ai_triage_*: scoring AI-derived 0-10 + reasoning curto + confidence.
--      LGPD Art. 20 §1: non-binding, human-in-loop final decision (decisão humana é a fonte
--      autoritária; ai_triage_score é signal de pre-screen para reduzir pool de avaliação).
--   3. list_ai_processing_log: admin observability via view_internal_analytics permission.
--
-- ADR ref: ADR-0074 (dual-model AI architecture)
-- ADR-0011 ref: can_by_member para gates
-- ADR-0012 ref: ai_triage_* NÃO são cache columns (calculadas por EF externa, não derivam de outra tabela).
--
-- Não-conflitos:
--   - ai_analysis_runs (existing, ADR-0059): operational tracker para Gemini path, complementar.
--     Triage/briefing escrevem em ai_processing_log (LGPD audit), Gemini qualitative em ambos
--     (ai_analysis_runs operacional + ai_processing_log audit).
--   - Invariants 13/13: nenhum impactado (sem cache cols novas, sem FKs em members).
--
-- Rollback:
--   ALTER TABLE selection_applications DROP COLUMN ai_triage_*;
--   DROP TABLE ai_processing_log;
--   DROP FUNCTION list_ai_processing_log(uuid, text, text, integer);

-- 1. Table ai_processing_log (LGPD audit, generic AI call observability)
CREATE TABLE IF NOT EXISTS public.ai_processing_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES public.selection_applications(id) ON DELETE CASCADE,
  model_provider text NOT NULL,
  model_id text NOT NULL,
  purpose text NOT NULL,
  prompt_hash text,
  response_hash text,
  input_tokens integer,
  output_tokens integer,
  cache_creation_tokens integer DEFAULT 0,
  cache_read_tokens integer DEFAULT 0,
  duration_ms integer,
  status text NOT NULL DEFAULT 'running',
  error_message text,
  triggered_by text NOT NULL,
  caller_member_id uuid REFERENCES public.members(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  organization_id uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906',
  CONSTRAINT ai_processing_log_status_check CHECK (status IN ('running', 'completed', 'failed')),
  CONSTRAINT ai_processing_log_purpose_check CHECK (purpose IN ('triage', 'briefing', 'qualitative', 'enrichment', 'other')),
  CONSTRAINT ai_processing_log_model_provider_check CHECK (model_provider IN ('anthropic', 'gemini', 'openai', 'other'))
);

CREATE INDEX IF NOT EXISTS ix_ai_processing_log_app_created
  ON public.ai_processing_log (application_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_ai_processing_log_purpose_created
  ON public.ai_processing_log (purpose, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_ai_processing_log_status_pending
  ON public.ai_processing_log (status, created_at DESC) WHERE status <> 'completed';

-- RLS rpc-only: bloqueia acesso direto. EFs (service_role) bypass RLS.
ALTER TABLE public.ai_processing_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ai_processing_log_no_anon ON public.ai_processing_log;
CREATE POLICY ai_processing_log_no_anon
  ON public.ai_processing_log FOR ALL TO anon USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS ai_processing_log_rpc_only_authenticated ON public.ai_processing_log;
CREATE POLICY ai_processing_log_rpc_only_authenticated
  ON public.ai_processing_log FOR ALL TO authenticated USING (false) WITH CHECK (false);

REVOKE INSERT, UPDATE, DELETE ON public.ai_processing_log FROM authenticated, anon;

COMMENT ON TABLE public.ai_processing_log IS
  'p108 ARM Onda 3 (LGPD Art. 37 + Art. 20 §1): audit log genérico de AI calls. NUNCA conteúdo; só hashes + metadata + tokens. RLS rpc-only — admin via list_ai_processing_log RPC.';
COMMENT ON COLUMN public.ai_processing_log.prompt_hash IS
  'SHA-256 do payload enviado ao modelo (sem conteúdo). Permite verificar reproducibilidade sem armazenar PII.';
COMMENT ON COLUMN public.ai_processing_log.response_hash IS
  'SHA-256 da resposta do modelo (sem conteúdo). Permite verificar consistência sem armazenar conclusões automatizadas.';
COMMENT ON COLUMN public.ai_processing_log.purpose IS
  'triage = analyze_application Sonnet 4.6 (ARM-3); briefing = generate_interview_briefing Haiku 4.5 (ARM-5); qualitative = pmi-ai-analyze Gemini (legacy); enrichment = futuro; other = catch-all.';

-- 2. ALTER selection_applications: triage scoring columns
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS ai_triage_score numeric,
  ADD COLUMN IF NOT EXISTS ai_triage_reasoning text,
  ADD COLUMN IF NOT EXISTS ai_triage_confidence text,
  ADD COLUMN IF NOT EXISTS ai_triage_at timestamptz,
  ADD COLUMN IF NOT EXISTS ai_triage_model text;

ALTER TABLE public.selection_applications
  DROP CONSTRAINT IF EXISTS selection_applications_ai_triage_score_range;
ALTER TABLE public.selection_applications
  DROP CONSTRAINT IF EXISTS selection_applications_ai_triage_confidence_check;

ALTER TABLE public.selection_applications
  ADD CONSTRAINT selection_applications_ai_triage_score_range
    CHECK (ai_triage_score IS NULL OR (ai_triage_score >= 0 AND ai_triage_score <= 10));
ALTER TABLE public.selection_applications
  ADD CONSTRAINT selection_applications_ai_triage_confidence_check
    CHECK (ai_triage_confidence IS NULL OR ai_triage_confidence IN ('high', 'medium', 'low'));

COMMENT ON COLUMN public.selection_applications.ai_triage_score IS
  'p108 ARM-3 Onda 3: AI-derived triage score 0-10 (Sonnet 4.6 + cached rubric). LGPD Art. 20 §1: non-binding, decisão humana é autoritária. Pre-screen signal para priorizar pool de avaliação.';
COMMENT ON COLUMN public.selection_applications.ai_triage_reasoning IS
  'p108 ARM-3 Onda 3: short rationale (ideal <= 500 chars). Gerado por pmi-ai-triage EF. PII status: contém análise sobre o candidato — purga LGPD respeita cycle_decision_date + retention.';
COMMENT ON COLUMN public.selection_applications.ai_triage_confidence IS
  'p108 ARM-3 Onda 3: high|medium|low — alinhado com a aplicação da rubrica pelo modelo.';
COMMENT ON COLUMN public.selection_applications.ai_triage_at IS
  'p108 ARM-3 Onda 3: timestamp do último triage run completado.';
COMMENT ON COLUMN public.selection_applications.ai_triage_model IS
  'p108 ARM-3 Onda 3: model_id usado no último triage (e.g. claude-sonnet-4-6). Mantido para audit + observability vs ai_processing_log cross-ref.';

-- 3. Admin observability RPC: list_ai_processing_log
CREATE OR REPLACE FUNCTION public.list_ai_processing_log(
  p_application_id uuid DEFAULT NULL,
  p_purpose text DEFAULT NULL,
  p_status text DEFAULT NULL,
  p_limit integer DEFAULT 50
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $func$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_safe_limit integer;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Not authorized: requires view_internal_analytics');
  END IF;

  v_safe_limit := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);

  SELECT jsonb_agg(jsonb_build_object(
    'id', l.id,
    'application_id', l.application_id,
    'applicant_name', sa.applicant_name,
    'model_provider', l.model_provider,
    'model_id', l.model_id,
    'purpose', l.purpose,
    'triggered_by', l.triggered_by,
    'caller_name', m.name,
    'input_tokens', l.input_tokens,
    'output_tokens', l.output_tokens,
    'cache_creation_tokens', l.cache_creation_tokens,
    'cache_read_tokens', l.cache_read_tokens,
    'duration_ms', l.duration_ms,
    'status', l.status,
    'error_message', l.error_message,
    'created_at', l.created_at,
    'completed_at', l.completed_at,
    'prompt_hash_short', LEFT(COALESCE(l.prompt_hash, ''), 12),
    'response_hash_short', LEFT(COALESCE(l.response_hash, ''), 12)
  ) ORDER BY l.created_at DESC)
  INTO v_result
  FROM (
    SELECT * FROM public.ai_processing_log
    WHERE (p_application_id IS NULL OR application_id = p_application_id)
      AND (p_purpose IS NULL OR purpose = p_purpose)
      AND (p_status IS NULL OR status = p_status)
    ORDER BY created_at DESC
    LIMIT v_safe_limit
  ) l
  LEFT JOIN public.selection_applications sa ON sa.id = l.application_id
  LEFT JOIN public.members m ON m.id = l.caller_member_id;

  RETURN jsonb_build_object(
    'rows', COALESCE(v_result, '[]'::jsonb),
    'count', COALESCE(jsonb_array_length(v_result), 0),
    'fetched_at', now()
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.list_ai_processing_log(uuid, text, text, integer) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_ai_processing_log(uuid, text, text, integer) TO authenticated;

COMMENT ON FUNCTION public.list_ai_processing_log(uuid, text, text, integer) IS
  'p108 ARM Onda 3: admin observability sobre ai_processing_log (LGPD Art. 37). Auth: view_internal_analytics. Retorna rows + hashes truncados (12 chars) — full hash via direct SQL para audit profundo.';

NOTIFY pgrst, 'reload schema';
