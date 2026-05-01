-- p86 Wave 5b-1b: AI analysis observability via separate ai_analysis_runs table.
-- Substrate for Wave 5b-3 admin diff UI (committee panel showing version evolution).
-- Spec ref: docs/specs/p84-wave5-ai-augmented-self-improvement.md (Estágio 4 Comissão visibility).
--
-- Why separate table: spec ai_analysis_history jsonb[] discarded — separate table is queryable
-- (analytics, retention, RLS), supports per-run audit fields (model_version/tokens/duration/error),
-- and enables clean diff visualization without parsing array.
--
-- Migration phases:
--   1. CREATE TABLE ai_analysis_runs + RLS + indexes
--   2. Backfill existing analyzed apps as run_index=1 from selection_applications.ai_analysis
--
-- EF refactor (separate commit, no migration): pmi-ai-analyze inserts + updates row per call.
-- Backward compat: selection_applications.ai_analysis column STILL maintained (additive).
--
-- Rollback:
--   DROP TABLE public.ai_analysis_runs;

CREATE TABLE IF NOT EXISTS public.ai_analysis_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES public.selection_applications(id) ON DELETE CASCADE,
  run_index integer NOT NULL,
  triggered_by text NOT NULL,
  status text NOT NULL DEFAULT 'running',
  ai_analysis_snapshot jsonb,
  fields_changed text[],
  model_version text NOT NULL DEFAULT 'gemini-2.5-flash',
  input_token_estimate integer,
  output_token_estimate integer,
  duration_ms integer,
  error_message text,
  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  organization_id uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906',
  CONSTRAINT ai_analysis_runs_app_run_unique UNIQUE (application_id, run_index),
  CONSTRAINT ai_analysis_runs_triggered_by_check CHECK (triggered_by IN ('consent', 'enrichment_request', 'admin_retry', 'cron_retry')),
  CONSTRAINT ai_analysis_runs_status_check CHECK (status IN ('running', 'completed', 'failed'))
);

CREATE INDEX IF NOT EXISTS ix_ai_analysis_runs_app_run_desc
  ON public.ai_analysis_runs (application_id, run_index DESC);

CREATE INDEX IF NOT EXISTS ix_ai_analysis_runs_status_started
  ON public.ai_analysis_runs (status, started_at DESC)
  WHERE status <> 'completed';

ALTER TABLE public.ai_analysis_runs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ai_analysis_runs_no_anon ON public.ai_analysis_runs;
CREATE POLICY ai_analysis_runs_no_anon
  ON public.ai_analysis_runs
  FOR ALL TO anon
  USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS ai_analysis_runs_committee_read ON public.ai_analysis_runs;
CREATE POLICY ai_analysis_runs_committee_read
  ON public.ai_analysis_runs
  FOR SELECT TO authenticated
  USING (
    public.rls_can('manage_member')
    OR public.rls_can('view_internal_analytics')
    OR EXISTS (
      SELECT 1
      FROM public.selection_committee sc
      JOIN public.selection_applications sa ON sa.cycle_id = sc.cycle_id
      JOIN public.members m ON m.auth_id = auth.uid()
      WHERE sa.id = ai_analysis_runs.application_id
        AND sc.member_id = m.id
        AND sc.role IN ('lead', 'member')
    )
  );

GRANT SELECT ON public.ai_analysis_runs TO authenticated;

COMMENT ON TABLE public.ai_analysis_runs IS
  'p86 Wave 5b-1b: per-run audit of pmi-ai-analyze EF invocations. Substrate for 5b-3 admin diff UI. Backward-compatible w/ selection_applications.ai_analysis (additive).';

-- Backfill: existing analyzed applications become run_index=1 with triggered_by='consent'
INSERT INTO public.ai_analysis_runs (
  application_id, run_index, triggered_by, status,
  ai_analysis_snapshot, model_version, started_at, completed_at
)
SELECT
  id,
  1,
  'consent',
  'completed',
  ai_analysis,
  COALESCE(ai_analysis ->> 'model', 'gemini-2.5-flash'),
  COALESCE(
    NULLIF(ai_analysis ->> 'analyzed_at', '')::timestamptz,
    consent_ai_analysis_at,
    created_at
  ),
  COALESCE(
    NULLIF(ai_analysis ->> 'analyzed_at', '')::timestamptz,
    consent_ai_analysis_at,
    created_at
  )
FROM public.selection_applications
WHERE ai_analysis IS NOT NULL
ON CONFLICT (application_id, run_index) DO NOTHING;

NOTIFY pgrst, 'reload schema';
