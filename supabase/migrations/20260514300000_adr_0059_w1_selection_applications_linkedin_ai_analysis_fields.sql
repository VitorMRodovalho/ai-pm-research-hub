-- ADR-0059 W1 — Schema hardening aditivo para LinkedIn cross-ref + LLM analyze
-- Council Tier 3: legal-counsel red flags incorporados (consent + retencao)
-- Substrate-only: nenhum consumer ativa ainda. Pre-W4 (LLM analyze deferida Q3 2026).

ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS linkedin_relevant_posts text[] DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS ai_pm_focus_tags text[] DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS cv_extracted_text text DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS ai_analysis jsonb DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS consent_ai_analysis_at timestamptz DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS consent_ai_analysis_revoked_at timestamptz DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS cycle_decision_date timestamptz DEFAULT NULL;

COMMENT ON COLUMN public.selection_applications.linkedin_relevant_posts IS
  'URLs de posts LinkedIn auto-declarados pelo candidato (ADR-0059 W1). Purgar imediatamente apos ciclo encerrado para nao-selecionados (LGPD minimizacao). Self-declared only — scraping LinkedIn viola ToS + Lei 14.155/21.';

COMMENT ON COLUMN public.selection_applications.ai_pm_focus_tags IS
  'Tags inferidas via LLM analise (pm/ai/agile/genai/etc). Requer consent_ai_analysis_at preenchido. Purgar com cv_extracted_text em 90 dias pos-decisao para nao-selecionados.';

COMMENT ON COLUMN public.selection_applications.cv_extracted_text IS
  'Texto extraido do PDF do resume_url para search/analise LLM. Purgar em 90 dias apos cycle_decision_date para nao-selecionados, 180 dias para selecionados (LGPD Art. 16 II).';

COMMENT ON COLUMN public.selection_applications.ai_analysis IS
  'Output LLM (scores, summary, flags). NAO modifica research_score nem leader_score (peer-review humano canonico preservado). Apenas insumo. Cada acesso registrado em pii_access_log (#85 Onda C). Purgar com cv_extracted_text.';

COMMENT ON COLUMN public.selection_applications.consent_ai_analysis_at IS
  'Timestamp consent destacado, especifico para analise LLM (separado do consent geral de candidatura — LGPD Art. 9 par 1). NULL = sem consent. Sem este, RPC analyze_application deve falhar.';

COMMENT ON COLUMN public.selection_applications.consent_ai_analysis_revoked_at IS
  'Revogacao de consent (LGPD Art. 8 par 5). Trigger purga linkedin_relevant_posts + cv_extracted_text + ai_pm_focus_tags + ai_analysis em 72h SLA.';

COMMENT ON COLUMN public.selection_applications.cycle_decision_date IS
  'Data da decisao final do ciclo (aprovacao/rejeicao). Base de calculo para cron de purga LGPD (90/180 dias). NULL ate decision.';

-- Trigger: ao revogar consent, purgar dados de analise IA
CREATE OR REPLACE FUNCTION public._trg_purge_ai_analysis_on_consent_revocation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF NEW.consent_ai_analysis_revoked_at IS NOT NULL
     AND OLD.consent_ai_analysis_revoked_at IS NULL THEN
    NEW.linkedin_relevant_posts := NULL;
    NEW.cv_extracted_text := NULL;
    NEW.ai_pm_focus_tags := NULL;
    NEW.ai_analysis := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_purge_ai_analysis_on_consent_revocation ON public.selection_applications;
CREATE TRIGGER trg_purge_ai_analysis_on_consent_revocation
  BEFORE UPDATE OF consent_ai_analysis_revoked_at ON public.selection_applications
  FOR EACH ROW
  EXECUTE FUNCTION public._trg_purge_ai_analysis_on_consent_revocation();

NOTIFY pgrst, 'reload schema';
