-- #3037: a revogação do consentimento de IA falhava sempre com 27000 ("tuple to be updated was already
-- modified by an operation triggered by the current command").
--
-- O gatilho é BEFORE UPDATE OF consent_ai_analysis_revoked_at, e o corpo vindo de 20260516970000 (mantido
-- por 20260517150000) fazia UPDATE public.selection_applications ... WHERE id = NEW.id: atualizava a linha que
-- o próprio comando já estava atualizando. O Postgres recusa e desfaz a transação inteira, então nem a data
-- da revogação, nem o fechamento da linha em consent_records, nem a limpeza chegavam a valer.
--
-- Volta à forma de 20260514300000 e 20260516940000: num BEFORE, limpar é atribuir em NEW. As 12 colunas são
-- as mesmas do corpo vivo. Assinatura, search_path e o gatilho não mudam.
CREATE OR REPLACE FUNCTION public._trg_purge_ai_analysis_on_consent_revocation()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.consent_ai_analysis_revoked_at IS NOT NULL
     AND OLD.consent_ai_analysis_revoked_at IS NULL THEN
    NEW.linkedin_relevant_posts := NULL;
    NEW.cv_extracted_text := NULL;
    NEW.ai_pm_focus_tags := NULL;
    NEW.ai_analysis := NULL;
    NEW.ai_triage_score := NULL;
    NEW.ai_triage_reasoning := NULL;
    NEW.ai_triage_confidence := NULL;
    NEW.ai_triage_at := NULL;
    NEW.ai_triage_model := NULL;
    NEW.last_briefing_jsonb := NULL;
    NEW.last_briefing_at := NULL;
    NEW.last_briefing_model := NULL;
  END IF;
  RETURN NEW;
END;
$function$;
