-- #3069: a triagem por IA volta a deixar registro em ai_processing_log.
--
-- A EF pmi-ai-triage grava prompt_version em cada chamada, mas a coluna nunca existiu no banco: a migration
-- 20260518090000_p126_e3_ai_processing_log_prompt_version.sql ficou no repo sem ser aplicada. O INSERT do log
-- falhava, a EF só avisava, e a triagem seguia sem registro. Último registro de triagem: 22/06/2026.
--
-- Sem default, ao contrário do arquivo de maio: as linhas antigas não dizem qual versão do prompt as gerou, e um
-- 'v1-cycle3' preenchido agora seria um dado inventado.

ALTER TABLE public.ai_processing_log ADD COLUMN IF NOT EXISTS prompt_version text;

COMMENT ON COLUMN public.ai_processing_log.prompt_version IS
  '#3069 (ADR-0076): a versão do prompt que gerou esta chamada (ex.: v1-apoio-2026-11 nas vagas de apoio, #3063). Nula nas linhas anteriores a 14/11/2026, quando a coluna não existia e não se sabe a versão.';
