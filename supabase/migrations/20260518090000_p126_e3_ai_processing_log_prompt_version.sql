-- p126 E3 Migration 9/9 (reduced scope) — ai_processing_log prompt_version column
-- Decision 4 acceptance criteria: "Logs em ai_processing_log registram qual prompt_version foi usado"
-- Wave 1 PM draft (ai-engineer Wave 2 E2 flagged como B1 BLOCKER pré-Cycle 4)
--
-- Adds prompt_version text column to ai_processing_log. Worker E2 stores
-- consent_version on selection_applications; EF agora também loga prompt_version
-- por chamada → cycle freeze audit trail per Decision 4.
--
-- Default 'v1-cycle3' for backwards compat (existing rows + Cycle 3 active).
-- Cycle 4+ V2 enriched prompt deploy will populate 'v2-cycle4' or similar.
--
-- Rollback: ALTER TABLE ai_processing_log DROP COLUMN prompt_version;

BEGIN;

ALTER TABLE public.ai_processing_log
  ADD COLUMN IF NOT EXISTS prompt_version text NOT NULL DEFAULT 'v1-cycle3';

COMMENT ON COLUMN public.ai_processing_log.prompt_version IS
  'Audit trail: which prompt template version was used for this AI processing event. Cycle 3 freeze = v1-cycle3 (Decision 4). Cycle 4+ enriched = v2-cycle4 (target deploy 2026-09-01 OR 30d post-Cycle 3 closure per ADR-0076 Princípio 4). pmi-ai-triage EF must populate this column on every call.';

-- Drop default after backfilling existing rows (so future inserts must specify)
-- DEFER drop default to follow-up migration if explicit version-on-insert preferred.
-- For now keep default to avoid blocking EF deploys; EF should override for Cycle 4+.

COMMIT;

-- Post-apply checklist:
--   1. supabase migration repair --status applied 20260518090000
--   2. NOTIFY pgrst, 'reload schema' (column exposed via PostgREST)
--   3. EF pmi-ai-triage must populate prompt_version on next deploy
--   4. Smoke: SELECT prompt_version, COUNT(*) FROM ai_processing_log GROUP BY 1
--      Expected (post-deploy): mix of 'v1-cycle3' (Cycle 3) + 'v2-cycle4' (post-Cycle 4 launch)
