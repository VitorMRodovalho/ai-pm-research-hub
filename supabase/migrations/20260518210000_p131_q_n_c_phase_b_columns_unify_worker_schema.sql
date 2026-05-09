-- p131 Q-N-c: unificar schema worker pmi-vep-sync ↔ DB
-- ============================================================================
-- 22 colunas Phase B que worker manda no INSERT/UPDATE de selection_applications
-- mas não existem no DB — daí erro "Could not find applicant_city column" e
-- ingest result `applications_updated: 0`. Adição aditiva (NULL-permissive),
-- sem regressão.
--
-- Driver: user confirmou Q-N-c (consolidar pmi-vep-sync). Ao auditar JSON
-- enriched recém extraído (2026-05-09), achei 22 mismatches entre payload
-- worker e DB schema. Esta migration alinha os dois — próximo POST do JSON
-- vai ter applications_updated > 0 em vez de 0 (com erros de schema).
-- ============================================================================

ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS applicant_city text,
  ADD COLUMN IF NOT EXISTS profile_location text,
  ADD COLUMN IF NOT EXISTS profile_state text,
  ADD COLUMN IF NOT EXISTS profile_city text,
  ADD COLUMN IF NOT EXISTS profile_country text,
  ADD COLUMN IF NOT EXISTS pmi_memberships jsonb,
  ADD COLUMN IF NOT EXISTS profile_industry text,
  ADD COLUMN IF NOT EXISTS profile_company text,
  ADD COLUMN IF NOT EXISTS profile_designation text,
  ADD COLUMN IF NOT EXISTS profile_certifications text[],
  ADD COLUMN IF NOT EXISTS profile_volunteer_interest text,
  ADD COLUMN IF NOT EXISTS profile_specialties text,
  ADD COLUMN IF NOT EXISTS profile_linkedin_url text,
  ADD COLUMN IF NOT EXISTS profile_about_me text,
  ADD COLUMN IF NOT EXISTS service_history_count int,
  ADD COLUMN IF NOT EXISTS service_history_chapters text,
  ADD COLUMN IF NOT EXISTS service_first_start_date date,
  ADD COLUMN IF NOT EXISTS service_latest_end_date date,
  ADD COLUMN IF NOT EXISTS is_open_to_volunteer boolean,
  ADD COLUMN IF NOT EXISTS community_profile_private boolean,
  ADD COLUMN IF NOT EXISTS pmi_data_fetched_at timestamptz,
  ADD COLUMN IF NOT EXISTS consent_version text;

COMMENT ON COLUMN public.selection_applications.applicant_city IS 'p131 Q-N-c: phase A applicantCity ou phase B resolved (community.pmi.org).';
COMMENT ON COLUMN public.selection_applications.pmi_memberships IS 'p131 Q-N-c: phase B JSONB array de chapter memberships do PMI Community.';
COMMENT ON COLUMN public.selection_applications.service_first_start_date IS 'p131 Q-N-c: data do PRIMEIRO start_date no histórico institucional PMI.';
COMMENT ON COLUMN public.selection_applications.service_latest_end_date IS 'p131 Q-N-c: data do ÚLTIMO end_date no histórico institucional PMI.';
COMMENT ON COLUMN public.selection_applications.pmi_data_fetched_at IS 'p131 Q-N-c: timestamp da extração PMI Community pelo extract_pmi_volunteer.js script.';
COMMENT ON COLUMN public.selection_applications.consent_version IS 'p131 Q-N-c: versão do termo de consentimento aceita pelo candidato (ex: termo-v3-cycle4-2026).';

CREATE INDEX IF NOT EXISTS idx_sa_pmi_data_fetched_at ON public.selection_applications(pmi_data_fetched_at) WHERE pmi_data_fetched_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sa_service_latest_end_date ON public.selection_applications(service_latest_end_date) WHERE service_latest_end_date IS NOT NULL;

NOTIFY pgrst, 'reload schema';
