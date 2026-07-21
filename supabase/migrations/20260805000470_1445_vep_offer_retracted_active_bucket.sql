-- #1445 — get_vep_divergence_report was blind to the "approved + VEP offer retracted + member
-- still active" class. The Hector case (approved on Núcleo, VEP offer withdrawn, member left
-- active) had to be reconciled by hand because no bucket surfaced it:
--   - selection_divergent   requires the app to be in the ACTIVE funnel (submitted..final_eval),
--                           so an approved/converted row is excluded.
--   - active_members_divergent requires member.is_active = FALSE, so an active member is excluded.
--   - onboarding_divergent  only covers vep_status_raw IN (Submitted, OfferExtended) — an offer
--                           that was RETRACTED (OfferNotExtended / Withdrawn / Declined) is out.
--
-- Fix: add bucket E `offer_retracted_active_divergent` = status approved/converted + vep_status_raw
-- IN (OfferNotExtended, Withdrawn, Declined) + a linked member that is still is_active = true.
-- Suggested action = offboard on the platform (admin_offboard_member inactive), reachable from the
-- reconciliation card. Same non-reconciled clause as the other buckets so mark_vep_reconciled can
-- also dismiss a row the GP decides to keep. No cycle-status filter (mirrors active_members bucket)
-- so the class is caught in closed cycles too. Count folded into summary.total_divergent.
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
  v_offer_retracted_active jsonb;
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

  -- #1445: bucket E (offer_retracted_active) = APROVADO/convertido no Núcleo MAS a oferta VEP foi
  -- RETIRADA (OfferNotExtended/Withdrawn/Declined) E o membro segue ATIVO na plataforma. Invisível
  -- nos demais buckets (selection exige funil ativo; active_members exige is_active=false; onboarding
  -- só cobre Submitted/OfferExtended). Ação: offboard na plataforma (admin_offboard_member inactive).
  -- Sem filtro de ciclo (espelha o bucket active_members) para pegar a classe também em ciclo fechado.
  -- Mesma cláusula de não-reconciliado dos demais buckets (mark_vep_reconciled também dispensa).
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'application_id', a.id, 'member_id', m.id, 'applicant_name', a.applicant_name, 'email', a.email, 'pmi_id', a.pmi_id,
    'cycle_code', c.cycle_code, 'nucleo_status', a.status, 'vep_status_raw', a.vep_status_raw,
    'member_is_active', m.is_active,
    'vep_last_seen_at', a.vep_last_seen_at, 'vep_reconciled_at', a.vep_reconciled_at,
    'suggested_action', 'GP: oferta VEP retirada mas membro ativo — offboard na plataforma (inativar)'
  ) ORDER BY a.applicant_name), '[]'::jsonb) INTO v_offer_retracted_active
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  JOIN public.members m ON lower(m.email) = lower(a.email)
  WHERE a.status IN ('approved', 'converted')
    AND a.vep_status_raw IN ('OfferNotExtended', 'Withdrawn', 'Declined')
    AND m.is_active = true
    AND (a.vep_reconciled_at IS NULL OR a.vep_reconciled_at < a.vep_last_seen_at);

  v_result := jsonb_build_object(
    'selection_divergent', v_selection,
    'onboarding_divergent', v_onboarding,
    'active_members_divergent', v_active,
    'rejection_divergent', v_rejection,
    'offer_retracted_active_divergent', v_offer_retracted_active,
    'summary', jsonb_build_object(
      'total_divergent', (jsonb_array_length(v_selection) + jsonb_array_length(v_onboarding) + jsonb_array_length(v_active) + jsonb_array_length(v_rejection) + jsonb_array_length(v_offer_retracted_active)),
      'selection_count', jsonb_array_length(v_selection),
      'onboarding_count', jsonb_array_length(v_onboarding),
      'onboarding_by_cohort', v_onboarding_by_cohort,
      'active_members_count', jsonb_array_length(v_active),
      'rejection_count', jsonb_array_length(v_rejection),
      'offer_retracted_active_count', jsonb_array_length(v_offer_retracted_active),
      'generated_at', now()
    )
  );
  RETURN v_result;
END;
$function$;
