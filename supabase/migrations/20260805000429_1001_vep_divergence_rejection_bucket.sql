-- #1001: adiciona o bucket D (rejection_divergent) ao get_vep_divergence_report.
-- Sentido faltante: plataforma REJEITADA + oferta VEP ainda ABERTA (Submitted/Active/
-- OfferExtended = não negada nem expirada). Hoje invisível na /admin/vep-reconciliation
-- e no widget. Mesma taxonomia dos chips do #1000 (as duas telas não podem divergir).
-- Assinatura inalterada (RETURNS jsonb) => CREATE OR REPLACE + NOTIFY pgrst (GC-097).
-- Base: corpo VIVO (pg_get_functiondef) + o novo bucket (reference-create-or-replace-base-on-live-body).
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
  v_rejection jsonb;
  v_onboarding_by_cohort jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.selection_cycles sc
    WHERE sc.status = 'open' AND public.selection_coi_recused(v_caller_id, sc.id)
  ) THEN
    RETURN jsonb_build_object('error', 'recused_conflict_of_interest',
      'detail', 'Você é candidato(a) em um ciclo aberto — as visões de seleção estão impedidas por conflito de interesse (ADR-0109).');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'application_id', a.id, 'applicant_name', a.applicant_name, 'email', a.email, 'pmi_id', a.pmi_id,
    'cycle_code', c.cycle_code, 'nucleo_status', a.status, 'vep_status_raw', a.vep_status_raw,
    'vep_last_seen_at', a.vep_last_seen_at, 'vep_reconciled_at', a.vep_reconciled_at,
    'suggested_action', 'Comitê: marcar withdrawn/rejected no Núcleo'
  ) ORDER BY a.applicant_name), '[]'::jsonb) INTO v_selection
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE a.vep_status_raw IN ('Withdrawn', 'Declined', 'OfferNotExtended')
    AND a.status IN ('submitted', 'screening', 'objective_eval', 'interview_pending', 'interview_scheduled', 'interview_done', 'final_eval')
    AND c.status = 'open'
    AND (a.vep_reconciled_at IS NULL OR a.vep_reconciled_at < a.vep_last_seen_at);

  -- #1130 fix: pré-onboarding = aprovado/convertido MAS ainda pré-aceite no VEP
  -- ('Submitted' sem oferta OU 'OfferExtended' oferta emitida aguardando aceite). 'Active' = já aceitou.
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'application_id', a.id, 'applicant_name', a.applicant_name, 'email', a.email, 'pmi_id', a.pmi_id,
    'cycle_code', c.cycle_code, 'nucleo_status', a.status, 'vep_status_raw', a.vep_status_raw,
    'vep_last_seen_at', a.vep_last_seen_at, 'vep_reconciled_at', a.vep_reconciled_at,
    'suggested_action', CASE
      WHEN a.vep_status_raw = 'OfferExtended' THEN 'Pré-onboarding: oferta emitida no VEP aguardando aceite do voluntário — acompanhar/nudge para aceitar'
      ELSE 'Recruiter PMI: sem oferta no VEP — estender oferta ao aprovado'
    END
  ) ORDER BY a.applicant_name), '[]'::jsonb) INTO v_onboarding
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE a.status IN ('approved', 'converted')
    AND a.vep_status_raw IN ('Submitted', 'OfferExtended')
    AND (a.vep_reconciled_at IS NULL OR a.vep_reconciled_at < a.vep_last_seen_at);

  SELECT COALESCE(jsonb_object_agg(cohort, n), '{}'::jsonb) INTO v_onboarding_by_cohort
  FROM (
    SELECT COALESCE(c.cycle_code, 'no_cycle') AS cohort, count(*) AS n
    FROM public.selection_applications a
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE a.status IN ('approved', 'converted')
      AND a.vep_status_raw IN ('Submitted', 'OfferExtended')
      AND (a.vep_reconciled_at IS NULL OR a.vep_reconciled_at < a.vep_last_seen_at)
    GROUP BY 1
  ) q;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'member_id', m.id, 'member_name', m.name, 'email', m.email, 'pmi_id', a.pmi_id,
    'is_active', m.is_active, 'last_engagement_end_date', latest_eng.end_date,
    'latest_application_id', a.id, 'cycle_code', c.cycle_code, 'vep_status_raw', a.vep_status_raw,
    'vep_last_seen_at', a.vep_last_seen_at, 'vep_reconciled_at', a.vep_reconciled_at,
    'suggested_action', 'Recruiter PMI: encerrar no VEP (membro offboarded na plataforma)'
  ) ORDER BY m.name), '[]'::jsonb) INTO v_active
  FROM public.members m
  JOIN LATERAL (
    SELECT sa.* FROM public.selection_applications sa
    WHERE lower(sa.email) = lower(m.email) AND sa.vep_status_raw IS NOT NULL
    ORDER BY sa.imported_at DESC NULLS LAST LIMIT 1
  ) a ON true
  LEFT JOIN public.selection_cycles c ON c.id = a.cycle_id
  LEFT JOIN LATERAL (
    SELECT end_date FROM public.engagements e
    WHERE e.person_id = m.person_id AND e.end_date IS NOT NULL
    ORDER BY e.end_date DESC LIMIT 1
  ) latest_eng ON true
  WHERE m.is_active = false
    AND a.vep_status_raw IN ('Submitted', 'Active')
    AND (a.vep_reconciled_at IS NULL OR a.vep_reconciled_at < a.vep_last_seen_at);

  -- #1001: bucket D (rejection_divergent) = REJEITADO no Núcleo MAS oferta ainda ABERTA no VEP
  -- ('Submitted'/'Active'/'OfferExtended' = não negada nem expirada). "Rejeitei no Núcleo, falta negar no VEP."
  -- Ciclo aberto + mesma cláusula de não-reconciliado dos demais buckets.
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'application_id', a.id, 'applicant_name', a.applicant_name, 'email', a.email, 'pmi_id', a.pmi_id,
    'cycle_code', c.cycle_code, 'nucleo_status', a.status, 'vep_status_raw', a.vep_status_raw,
    'vep_last_seen_at', a.vep_last_seen_at, 'vep_reconciled_at', a.vep_reconciled_at,
    'suggested_action', 'Recruiter PMI: negar/retirar a oferta no VEP (OfferNotExtended)'
  ) ORDER BY a.applicant_name), '[]'::jsonb) INTO v_rejection
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE a.status = 'rejected'
    AND a.vep_status_raw IN ('Submitted', 'Active', 'OfferExtended')
    AND c.status = 'open'
    AND (a.vep_reconciled_at IS NULL OR a.vep_reconciled_at < a.vep_last_seen_at);

  v_result := jsonb_build_object(
    'selection_divergent', v_selection,
    'onboarding_divergent', v_onboarding,
    'active_members_divergent', v_active,
    'rejection_divergent', v_rejection,
    'summary', jsonb_build_object(
      'total_divergent', (jsonb_array_length(v_selection) + jsonb_array_length(v_onboarding) + jsonb_array_length(v_active) + jsonb_array_length(v_rejection)),
      'selection_count', jsonb_array_length(v_selection),
      'onboarding_count', jsonb_array_length(v_onboarding),
      'onboarding_by_cohort', v_onboarding_by_cohort,
      'active_members_count', jsonb_array_length(v_active),
      'rejection_count', jsonb_array_length(v_rejection),
      'generated_at', now()
    )
  );
  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
