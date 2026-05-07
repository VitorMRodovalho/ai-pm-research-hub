-- p118 audit follow-up: 4 trigger functions com search_path mutable (advisor WARN)
-- Adiciona SET search_path TO 'public', 'pg_temp' para defense-in-depth contra
-- search_path injection. Funções são todas BEFORE UPDATE triggers que setam updated_at
-- ou similar — risco real é baixo, mas alinhamento com pattern do projeto.
-- Rollback: re-create cada função sem SET search_path (não recomendado).

CREATE OR REPLACE FUNCTION public._re_engagement_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

CREATE OR REPLACE FUNCTION public.webinar_proposals_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

CREATE OR REPLACE FUNCTION public.publication_ideas_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

CREATE OR REPLACE FUNCTION public._trg_purge_ai_analysis_on_consent_revocation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF NEW.consent_ai_analysis_revoked_at IS NOT NULL
     AND OLD.consent_ai_analysis_revoked_at IS NULL THEN
    UPDATE public.selection_applications
       SET linkedin_relevant_posts = NULL,
           cv_extracted_text = NULL,
           ai_pm_focus_tags = NULL,
           ai_analysis = NULL,
           ai_triage_score = NULL,
           ai_triage_reasoning = NULL,
           ai_triage_confidence = NULL,
           ai_triage_at = NULL,
           ai_triage_model = NULL,
           last_briefing_jsonb = NULL,
           last_briefing_at = NULL,
           last_briefing_model = NULL
     WHERE id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

NOTIFY pgrst, 'reload schema';
