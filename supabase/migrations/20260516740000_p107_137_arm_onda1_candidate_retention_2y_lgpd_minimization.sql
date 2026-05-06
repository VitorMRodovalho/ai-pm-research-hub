-- ARM Onda 1 #137: candidate retention 1095d → 730d (LGPD minimização)
--
-- Estado pré (verificado p107):
--   engagement_kinds.candidate.retention_days_after_end = 1095 (3 anos)
--   (nota: auditoria inicial reportou 1825, mas valor real era 1095)
--
-- Justificativa:
--   - LGPD Art. 16 II + princípio da minimização: retenção limitada à finalidade
--   - Candidato rejeitado SEM relação contratual com Núcleo
--   - 2 anos cobre 2 ciclos de seleção (yearly) para auditoria de processo + reaplicação
--   - Alinhado com study_group_participant (730) que tem natureza similar
--
-- Outros kinds com 1825d permanecem (out of scope deste issue):
--   alumni, ambassador, chapter_board, committee_*, observer, sponsor,
--   study_group_owner, volunteer, workgroup_*, external_signer (2555)
--   — esses têm relação contratual ativa ou histórico institucional que justifica
--
-- Rollback:
--   UPDATE public.engagement_kinds SET retention_days_after_end = 1095 WHERE slug = 'candidate';

DO $func$
DECLARE
  v_old integer;
  v_count integer;
BEGIN
  SELECT retention_days_after_end INTO v_old
  FROM public.engagement_kinds
  WHERE slug = 'candidate';

  UPDATE public.engagement_kinds
  SET retention_days_after_end = 730,
      updated_at = now()
  WHERE slug = 'candidate';

  GET DIAGNOSTICS v_count = ROW_COUNT;

  IF v_count = 0 THEN
    RAISE EXCEPTION 'engagement_kinds row for slug=candidate not found';
  END IF;

  -- Audit trail
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL,
    'engagement_kind_retention_updated',
    'engagement_kind',
    NULL,
    jsonb_build_object(
      'slug', 'candidate',
      'previous_retention_days', v_old,
      'new_retention_days', 730
    ),
    jsonb_build_object(
      'lgpd_basis', 'Art. 16 II — minimização',
      'arm_pillar', 'ARM-8',
      'issue', '#137',
      'rationale', 'Rejected candidate without contractual relation; 2y covers 2 selection cycles for re-application + audit'
    )
  );

  RAISE NOTICE 'candidate retention: % → 730 days', v_old;
END
$func$;

NOTIFY pgrst, 'reload schema';
