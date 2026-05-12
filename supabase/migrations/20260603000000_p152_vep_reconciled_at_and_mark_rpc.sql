-- p152 Wave 1.1 (2026-05-12) — vep_reconciled_at column + mark_vep_reconciled RPC
-- + filter divergence report by reconciled state.
--
-- Strategic context: handoff_p152 backlog item 1 (frontend VEP reconciliation
-- route). After surfacing the divergence list, admin needs to "mark reconciled"
-- so the row is excluded from the report until the next worker /ingest brings
-- fresh vep_status_raw data (which may surface new divergence).
--
-- Design:
--   - selection_applications.vep_reconciled_at — timestamp when admin acked.
--   - Report RPC excludes rows where vep_reconciled_at > vep_last_seen_at
--     (i.e., admin handled it after the last observation). When the worker
--     re-syncs and updates vep_last_seen_at, the row re-surfaces if still
--     divergent — admin sees the fresh divergence.
--   - mark_vep_reconciled(p_application_id, p_note) — atomic update + audit
--     log entry; SECURITY DEFINER + can_by_member('view_internal_analytics').

-- ─── 1) Schema ──────────────────────────────────────────────────────────
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS vep_reconciled_at timestamptz,
  ADD COLUMN IF NOT EXISTS vep_reconciled_by uuid REFERENCES public.members(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS vep_reconciled_note text;

COMMENT ON COLUMN public.selection_applications.vep_reconciled_at IS
  'Timestamp when admin acknowledged VEP↔Núcleo divergence. Reset by worker on next /ingest if divergence persists (vep_last_seen_at > vep_reconciled_at).';

CREATE INDEX IF NOT EXISTS idx_selection_applications_vep_reconciled_at
  ON public.selection_applications(vep_reconciled_at) WHERE vep_reconciled_at IS NOT NULL;

-- ─── 2) mark_vep_reconciled RPC ────────────────────────────────────────
DROP FUNCTION IF EXISTS public.mark_vep_reconciled(uuid, text);
CREATE OR REPLACE FUNCTION public.mark_vep_reconciled(
  p_application_id uuid,
  p_note text DEFAULT NULL
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_app public.selection_applications%ROWTYPE;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app.id IS NULL THEN
    RETURN jsonb_build_object('error', 'Application not found');
  END IF;

  UPDATE public.selection_applications
  SET vep_reconciled_at = now(),
      vep_reconciled_by = v_caller_id,
      vep_reconciled_note = p_note
  WHERE id = p_application_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller_id,
    'vep_reconciliation_marked',
    'selection_application',
    p_application_id,
    jsonb_build_object(
      'vep_reconciled_at', now(),
      'vep_status_raw', v_app.vep_status_raw,
      'nucleo_status', v_app.status,
      'note', p_note
    ),
    jsonb_build_object(
      'applicant_name', v_app.applicant_name,
      'email', v_app.email,
      'cycle_id', v_app.cycle_id
    )
  );

  RETURN jsonb_build_object(
    'ok', true,
    'application_id', p_application_id,
    'reconciled_at', now()
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.mark_vep_reconciled(uuid, text) TO authenticated;

-- ─── 3) Update get_vep_divergence_report to filter reconciled ─────────
DROP FUNCTION IF EXISTS public.get_vep_divergence_report();
CREATE OR REPLACE FUNCTION public.get_vep_divergence_report()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_selection jsonb;
  v_onboarding jsonb;
  v_active jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- ─── Bucket A: Candidato em seleção (NOT terminal in Núcleo) ────────
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'application_id', a.id,
    'applicant_name', a.applicant_name,
    'email', a.email,
    'pmi_id', a.pmi_id,
    'cycle_code', c.cycle_code,
    'nucleo_status', a.status,
    'vep_status_raw', a.vep_status_raw,
    'vep_last_seen_at', a.vep_last_seen_at,
    'vep_reconciled_at', a.vep_reconciled_at,
    'suggested_action', 'Comitê: marcar withdrawn/rejected no Núcleo'
  ) ORDER BY a.applicant_name), '[]'::jsonb) INTO v_selection
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE a.vep_status_raw IN ('Withdrawn', 'Declined', 'OfferNotExtended')
    AND a.status IN ('submitted', 'screening', 'objective_eval', 'interview_pending', 'interview_scheduled', 'interview_done', 'final_eval')
    AND c.status = 'open'
    AND (a.vep_reconciled_at IS NULL OR a.vep_reconciled_at < a.vep_last_seen_at);

  -- ─── Bucket B: Pós-aprovação · onboarding ──────────────────────────
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'application_id', a.id,
    'applicant_name', a.applicant_name,
    'email', a.email,
    'pmi_id', a.pmi_id,
    'cycle_code', c.cycle_code,
    'nucleo_status', a.status,
    'vep_status_raw', a.vep_status_raw,
    'vep_last_seen_at', a.vep_last_seen_at,
    'vep_reconciled_at', a.vep_reconciled_at,
    'suggested_action', 'Recruiter PMI: marcar Complete/OfferExtended no VEP'
  ) ORDER BY a.applicant_name), '[]'::jsonb) INTO v_onboarding
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE a.status IN ('approved', 'converted')
    AND a.vep_status_raw IN ('Submitted', 'Active')
    AND (a.vep_reconciled_at IS NULL OR a.vep_reconciled_at < a.vep_last_seen_at);

  -- ─── Bucket C: Membro ativo/Offboarded ─────────────────────────────
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'member_id', m.id,
    'member_name', m.name,
    'email', m.email,
    'pmi_id', a.pmi_id,
    'is_active', m.is_active,
    'last_engagement_end_date', latest_eng.end_date,
    'latest_application_id', a.id,
    'cycle_code', c.cycle_code,
    'vep_status_raw', a.vep_status_raw,
    'vep_last_seen_at', a.vep_last_seen_at,
    'vep_reconciled_at', a.vep_reconciled_at,
    'suggested_action', 'Recruiter PMI: marcar Complete no VEP (membro offboarded)'
  ) ORDER BY m.name), '[]'::jsonb) INTO v_active
  FROM public.members m
  JOIN LATERAL (
    SELECT sa.* FROM public.selection_applications sa
    WHERE lower(sa.email) = lower(m.email)
      AND sa.vep_status_raw IS NOT NULL
    ORDER BY sa.imported_at DESC NULLS LAST
    LIMIT 1
  ) a ON true
  LEFT JOIN public.selection_cycles c ON c.id = a.cycle_id
  LEFT JOIN LATERAL (
    SELECT end_date FROM public.engagements e
    WHERE e.person_id = m.person_id
      AND e.end_date IS NOT NULL
    ORDER BY e.end_date DESC
    LIMIT 1
  ) latest_eng ON true
  WHERE m.is_active = false
    AND a.vep_status_raw IN ('Submitted', 'Active')
    AND (a.vep_reconciled_at IS NULL OR a.vep_reconciled_at < a.vep_last_seen_at);

  v_result := jsonb_build_object(
    'selection_divergent', v_selection,
    'onboarding_divergent', v_onboarding,
    'active_members_divergent', v_active,
    'summary', jsonb_build_object(
      'total_divergent', (
        jsonb_array_length(v_selection) +
        jsonb_array_length(v_onboarding) +
        jsonb_array_length(v_active)
      ),
      'selection_count', jsonb_array_length(v_selection),
      'onboarding_count', jsonb_array_length(v_onboarding),
      'active_members_count', jsonb_array_length(v_active),
      'generated_at', now()
    )
  );

  RETURN v_result;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_vep_divergence_report() TO authenticated;

NOTIFY pgrst, 'reload schema';
