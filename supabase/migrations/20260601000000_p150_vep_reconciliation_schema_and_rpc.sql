-- p150 P0 (2026-05-12) — VEP ↔ Núcleo reconciliation schema + report RPC.
--
-- Strategic context: PM ask p151 (memory project_vep_nucleo_reconciliation_backlog.md):
-- without API write-back to PMI VEP, the only path to keep statuses aligned is
-- (a) capture VEP raw status on every /ingest, (b) compute divergence per
-- lifecycle, (c) surface a reconciliation queue so PM/recruiter can manually
-- update VEP. 3 lifecycles to cover:
--   A — Candidato em seleção (selection_applications NOT terminal)
--   B — Pós-aprovação · onboarding (Núcleo approved/converted, member not active yet)
--   C — Membro ativo/Offboarded (members + engagements, selection_apps fica histórico)
--
-- This migration:
-- 1) Adds 2 columns to selection_applications: vep_status_raw + vep_last_seen_at.
-- 2) Creates get_vep_divergence_report() RPC returning 3 buckets + summary.
-- Worker patch (separate commit) populates the columns; frontend (p152 dedicated
-- session) adds /admin/vep-reconciliation route + inline badges.

-- ─── 1) Schema additions ────────────────────────────────────────────────
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS vep_status_raw text,
  ADD COLUMN IF NOT EXISTS vep_last_seen_at timestamptz;

COMMENT ON COLUMN public.selection_applications.vep_status_raw IS
  'Raw status from PMI VEP API (Submitted | Active | Withdrawn | Declined | Complete | OfferNotExtended). Populated by worker pmi-vep-sync /ingest on every UPSERT. Source of truth for VEP-side status. Compared against Núcleo status (this.status) and engagements.end_date by get_vep_divergence_report to surface reconciliation queue.';

COMMENT ON COLUMN public.selection_applications.vep_last_seen_at IS
  'Timestamp of the last worker /ingest that observed this application in the VEP. Stale (e.g. > 14 days) may indicate VEP removed the application; combined with vep_status_raw=NULL helps detect VEP-side deletes.';

CREATE INDEX IF NOT EXISTS idx_selection_applications_vep_status_raw
  ON public.selection_applications(vep_status_raw) WHERE vep_status_raw IS NOT NULL;

-- ─── 2) get_vep_divergence_report RPC ─────────────────────────────────
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
  -- Divergent IF VEP says terminal (Withdrawn/Declined/OfferNotExtended)
  -- but Núcleo still has them in active funnel (submitted/screening/etc).
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'application_id', a.id,
    'applicant_name', a.applicant_name,
    'email', a.email,
    'pmi_id', a.pmi_id,
    'cycle_code', c.cycle_code,
    'nucleo_status', a.status,
    'vep_status_raw', a.vep_status_raw,
    'vep_last_seen_at', a.vep_last_seen_at,
    'suggested_action', 'Comitê: marcar withdrawn/rejected no Núcleo'
  ) ORDER BY a.applicant_name), '[]'::jsonb) INTO v_selection
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE a.vep_status_raw IN ('Withdrawn', 'Declined', 'OfferNotExtended')
    AND a.status IN ('submitted', 'screening', 'objective_eval', 'interview_pending', 'interview_scheduled', 'interview_done', 'final_eval')
    AND c.status = 'open';

  -- ─── Bucket B: Pós-aprovação · onboarding ──────────────────────────
  -- Divergent IF Núcleo says approved/converted but VEP still Active/Submitted.
  -- This means PMI recruiter doesn't know that we accepted them.
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'application_id', a.id,
    'applicant_name', a.applicant_name,
    'email', a.email,
    'pmi_id', a.pmi_id,
    'cycle_code', c.cycle_code,
    'nucleo_status', a.status,
    'vep_status_raw', a.vep_status_raw,
    'vep_last_seen_at', a.vep_last_seen_at,
    'suggested_action', 'Recruiter PMI: marcar Complete/OfferExtended no VEP'
  ) ORDER BY a.applicant_name), '[]'::jsonb) INTO v_onboarding
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE a.status IN ('approved', 'converted')
    AND a.vep_status_raw IN ('Submitted', 'Active');

  -- ─── Bucket C: Membro ativo/Offboarded ─────────────────────────────
  -- Divergent IF the person's latest engagement ended (offboarded) but
  -- VEP still shows them as Active. Lookup via email (more stable than
  -- application_id for cross-cycle continuity).
  -- Match by lowered email between members + latest selection_application.
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
    AND a.vep_status_raw IN ('Submitted', 'Active');

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
