-- ADR-0059 W2 — Anti-bias enforcement em selection_evaluations via cycle phase
-- Council Tier 3 (#87): 4 agents convergiram em "ship esta semana"
-- Ciclo cycle3-2026-b2 ATIVO recebendo avaliações; cada hora = bias risk

-- ============================================================================
-- 1. Cycle phase enum (state machine)
-- ============================================================================

ALTER TABLE public.selection_cycles
  ADD COLUMN IF NOT EXISTS phase text NOT NULL DEFAULT 'planning'
  CHECK (phase IN (
    'planning',
    'applications_open',
    'screening',
    'evaluating',
    'evaluations_closed',
    'interviews_scheduling',
    'interviews',
    'interviews_closed',
    'ranking',
    'announcement',
    'onboarding'
  ));

COMMENT ON COLUMN public.selection_cycles.phase IS
  'State machine fina do ciclo seletivo. Substitui status binário open/closed para anti-bias enforcement (ADR-0059). Phases evaluating + interviews ativam blind mode em get_application_score_breakdown e similares.';

UPDATE public.selection_cycles
SET phase = CASE
  WHEN status = 'closed' THEN 'announcement'
  WHEN status = 'open' AND cycle_code = 'cycle3-2026-b2' THEN 'evaluating'
  ELSE 'planning'
END
WHERE phase = 'planning';

-- ============================================================================
-- 2. selection_evaluation_anomalies table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.selection_evaluation_anomalies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES public.selection_applications(id) ON DELETE CASCADE,
  cycle_id uuid REFERENCES public.selection_cycles(id) ON DELETE CASCADE,
  alert_type text NOT NULL CHECK (alert_type IN (
    'high_variance',
    'outlier_score',
    'late_submission',
    'blind_violation_attempt'
  )),
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  detected_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  resolved_by uuid REFERENCES public.members(id)
);

CREATE INDEX IF NOT EXISTS sea_app_idx ON public.selection_evaluation_anomalies(application_id);
CREATE INDEX IF NOT EXISTS sea_cycle_idx ON public.selection_evaluation_anomalies(cycle_id);
CREATE INDEX IF NOT EXISTS sea_unresolved_idx ON public.selection_evaluation_anomalies(detected_at)
  WHERE resolved_at IS NULL;

ALTER TABLE public.selection_evaluation_anomalies ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.selection_evaluation_anomalies IS
  'Audit trail de anomalias em avaliações: high variance entre avaliadores, scores outlier, late submissions, tentativas de blind violation. Service-role-only (RLS + sem policies).';

-- ============================================================================
-- 3. Patch get_application_score_breakdown
-- ============================================================================

DROP FUNCTION IF EXISTS public.get_application_score_breakdown(uuid);

CREATE OR REPLACE FUNCTION public.get_application_score_breakdown(p_application_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller record;
  v_app record;
  v_cycle record;
  v_evals jsonb;
  v_blind boolean;
  v_hidden text[];
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND OR NOT (
    v_caller.is_superadmin = true
    OR can_by_member(v_caller.id, 'manage_member')
    OR (v_caller.designations && ARRAY['curator'])
  ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT * INTO v_app FROM selection_applications WHERE id = p_application_id;
  IF v_app.id IS NULL THEN
    RETURN jsonb_build_object('error', 'application_not_found');
  END IF;

  SELECT * INTO v_cycle FROM selection_cycles WHERE id = v_app.cycle_id;

  v_blind := COALESCE(v_cycle.phase, 'planning') IN ('evaluating', 'interviews')
             AND v_caller.is_superadmin IS NOT TRUE;

  IF v_blind THEN
    SELECT jsonb_agg(jsonb_build_object(
      'evaluation_type', e.evaluation_type,
      'evaluator_name', m.name,
      'evaluator_id', m.id,
      'weighted_subtotal', e.weighted_subtotal,
      'submitted_at', e.submitted_at,
      'scores', e.scores,
      'is_own', true
    ) ORDER BY e.evaluation_type)
    INTO v_evals
    FROM selection_evaluations e
    JOIN members m ON m.id = e.evaluator_id
    WHERE e.application_id = p_application_id
      AND e.submitted_at IS NOT NULL
      AND e.evaluator_id = v_caller.id;

    v_hidden := ARRAY['other_evaluators_names', 'other_evaluators_scores', 'other_evaluators_subtotals'];
  ELSE
    SELECT jsonb_agg(jsonb_build_object(
      'evaluation_type', e.evaluation_type,
      'evaluator_name', m.name,
      'evaluator_id', m.id,
      'weighted_subtotal', e.weighted_subtotal,
      'submitted_at', e.submitted_at,
      'scores', e.scores,
      'is_own', e.evaluator_id = v_caller.id
    ) ORDER BY e.evaluation_type, m.name)
    INTO v_evals
    FROM selection_evaluations e
    JOIN members m ON m.id = e.evaluator_id
    WHERE e.application_id = p_application_id AND e.submitted_at IS NOT NULL;

    v_hidden := ARRAY[]::text[];
  END IF;

  RETURN jsonb_build_object(
    'application_id', v_app.id,
    'applicant_name', v_app.applicant_name,
    'email', v_app.email,
    'role_applied', v_app.role_applied,
    'promotion_path', v_app.promotion_path,
    'status', v_app.status,
    'research_score', v_app.research_score,
    'leader_score', v_app.leader_score,
    'rank_researcher', v_app.rank_researcher,
    'rank_leader', v_app.rank_leader,
    'evaluations', COALESCE(v_evals, '[]'::jsonb),
    'linked_application_id', v_app.linked_application_id,
    'blind_review_active', v_blind,
    'cycle_phase', COALESCE(v_cycle.phase, 'unknown'),
    'hidden_fields', v_hidden
  );
END;
$$;

COMMENT ON FUNCTION public.get_application_score_breakdown(uuid) IS
  'Score breakdown with phase-aware blind enforcement (ADR-0059). During phases evaluating/interviews: returns only caller own evaluation + hidden_fields metadata. Superadmin override always reveals (governance). Reveal phases (evaluations_closed+) show all with is_own flag per row.';

-- ============================================================================
-- 4. Trigger: at evaluations_closed compute stddev anomalies
-- ============================================================================

CREATE OR REPLACE FUNCTION public._trg_compute_evaluation_anomalies_on_phase_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_app record;
  v_stddev numeric;
  v_mean numeric;
  v_count int;
BEGIN
  IF NEW.phase IS DISTINCT FROM OLD.phase
     AND NEW.phase = 'evaluations_closed'
     AND OLD.phase = 'evaluating' THEN

    FOR v_app IN
      SELECT id FROM selection_applications WHERE cycle_id = NEW.id
    LOOP
      SELECT stddev(weighted_subtotal), avg(weighted_subtotal), count(*)
      INTO v_stddev, v_mean, v_count
      FROM selection_evaluations
      WHERE application_id = v_app.id AND submitted_at IS NOT NULL;

      IF v_count >= 2 AND v_stddev > 1.5 THEN
        INSERT INTO selection_evaluation_anomalies
          (application_id, cycle_id, alert_type, payload)
        VALUES (
          v_app.id, NEW.id, 'high_variance',
          jsonb_build_object(
            'stddev', v_stddev, 'mean', v_mean,
            'evaluator_count', v_count, 'threshold', 1.5,
            'detected_at_phase_change', now()
          )
        );
      END IF;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_compute_evaluation_anomalies_on_phase_change ON public.selection_cycles;
CREATE TRIGGER trg_compute_evaluation_anomalies_on_phase_change
  AFTER UPDATE OF phase ON public.selection_cycles
  FOR EACH ROW
  EXECUTE FUNCTION public._trg_compute_evaluation_anomalies_on_phase_change();

NOTIFY pgrst, 'reload schema';
