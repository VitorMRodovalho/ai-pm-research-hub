-- ARM Onda 3 (p108 cont. ADR-0074 follow-up #3): extend consent revoke purge trigger
-- to cover ai_triage_* columns shipped em 20260516930000.
--
-- Pré-fix: trigger _trg_purge_ai_analysis_on_consent_revocation purgava
-- {linkedin_relevant_posts, cv_extracted_text, ai_pm_focus_tags, ai_analysis} mas
-- não cobre ai_triage_score/reasoning/confidence/at/model — quando candidato revoga
-- consent, dados Sonnet 4.6 triage permaneciam. Bug latente.
--
-- LGPD note: ai_processing_log NÃO é purgada (Art. 16 permite retenção para Art. 37
-- record-keeping). Só hashes ficam — sem PII. Aplicação retroativa: 0 rows hoje
-- (consent_revoked AND ai_triage_score NOT NULL), pois triage foi shipped hoje
-- (2026-05-06) sem revokes intermediários. Aplicação só impacta revokes futuros.
--
-- Rollback: re-aplicar versão anterior do trigger function (sem as 5 NEW.ai_triage_* := NULL).

CREATE OR REPLACE FUNCTION public._trg_purge_ai_analysis_on_consent_revocation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $func$
BEGIN
  IF NEW.consent_ai_analysis_revoked_at IS NOT NULL
     AND OLD.consent_ai_analysis_revoked_at IS NULL THEN
    -- Original purge (Gemini qualitative path)
    NEW.linkedin_relevant_posts := NULL;
    NEW.cv_extracted_text := NULL;
    NEW.ai_pm_focus_tags := NULL;
    NEW.ai_analysis := NULL;
    -- p108 Onda 3 (ADR-0074): purge Sonnet 4.6 triage scoring data
    NEW.ai_triage_score := NULL;
    NEW.ai_triage_reasoning := NULL;
    NEW.ai_triage_confidence := NULL;
    NEW.ai_triage_at := NULL;
    NEW.ai_triage_model := NULL;
  END IF;
  RETURN NEW;
END;
$func$;

COMMENT ON FUNCTION public._trg_purge_ai_analysis_on_consent_revocation() IS
  'p108 Onda 3 extended: purges Gemini qualitative + Sonnet 4.6 triage data on consent revoke. ai_processing_log retained per LGPD Art. 16 (Art. 37 audit obligation).';

NOTIFY pgrst, 'reload schema';
