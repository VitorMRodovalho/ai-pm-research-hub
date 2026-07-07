-- #1130 — Reconciliação VEP↔plataforma por papel×coorte + correção de causa-raiz do bucket B
--
-- Parte A: get_vep_divergence_report — corrige a semântica do bucket B (onboarding_divergent).
--   VEP 'Active' = voluntário que JÁ ACEITOU a oferta e está na jornada (estado saudável; só vira
--   'Complete' quando o termo encerra). O bucket antigo marcava ('Submitted','Active') como
--   divergência → contava o roster ativo inteiro como "divergente" (62 crescendo sem parar).
--   Correção: divergência de pré-onboarding = aprovado/convertido no Núcleo MAS ainda em estado
--   pré-aceite no VEP: 'Submitted' (sem oferta) OU 'OfferExtended' (oferta emitida, aguardando
--   aceite). Aceitar a oferta é parte do pré-onboarding — sem esta lista o owner perde a
--   visibilidade de quem falta aceitar e já deveria estar na jornada (feedback do owner 2026-07-07).
--   NÃO inclui 'Active' (já aceitou). Adiciona breakdown por coorte no summary.
--
-- Parte B: get_vep_role_cohort_reconciliation() — matriz plataforma×VEP por papel×coorte, com
--   listas nominais dos divergentes nos dois sentidos. Join estável por PMI id (fallback e-mail),
--   resolvendo o falso-gap do caso Paulo (e-mails divergentes, mesmo pmi_id).
--
-- Bodies capturados verbatim do vivo (pg_get_functiondef) — GC-097 body-drift parity.

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

  v_result := jsonb_build_object(
    'selection_divergent', v_selection,
    'onboarding_divergent', v_onboarding,
    'active_members_divergent', v_active,
    'summary', jsonb_build_object(
      'total_divergent', (jsonb_array_length(v_selection) + jsonb_array_length(v_onboarding) + jsonb_array_length(v_active)),
      'selection_count', jsonb_array_length(v_selection),
      'onboarding_count', jsonb_array_length(v_onboarding),
      'onboarding_by_cohort', v_onboarding_by_cohort,
      'active_members_count', jsonb_array_length(v_active),
      'generated_at', now()
    )
  );
  RETURN v_result;
END;
$function$;


CREATE OR REPLACE FUNCTION public.get_vep_role_cohort_reconciliation()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_matrix jsonb;
  v_platform_only jsonb;
  v_vep_only jsonb;
  v_plat_total int;
  v_vep_total int;
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
      'detail', 'Você é candidato(a) em um ciclo aberto — impedido por conflito de interesse (ADR-0109).');
  END IF;

  WITH plat AS (
    SELECT DISTINCT ON (e.person_id)
      e.person_id,
      CASE WHEN e.role = 'researcher' THEN 'researcher' WHEN e.role = 'leader' THEN 'leader' ELSE 'other' END AS role,
      COALESCE(sc.cycle_code, 'no_cycle') AS cohort,
      COALESCE(NULLIF(mem.pmi_id, ''), 'e:' || lower(mem.email)) AS match_key,
      va.vep_status_raw AS vep_status
    FROM public.engagements e
    LEFT JOIN public.selection_applications sa ON sa.id = e.selection_application_id
    LEFT JOIN public.selection_cycles sc ON sc.id = sa.cycle_id
    LEFT JOIN LATERAL (
      SELECT m.name, m.email, m.pmi_id FROM public.members m
      WHERE m.person_id = e.person_id
      ORDER BY (m.pmi_id IS NOT NULL) DESC, m.updated_at DESC NULLS LAST LIMIT 1
    ) mem ON true
    LEFT JOIN LATERAL (
      SELECT s.vep_status_raw FROM public.selection_applications s
      WHERE (s.pmi_id = mem.pmi_id AND s.pmi_id IS NOT NULL AND s.pmi_id <> '') OR lower(s.email) = lower(mem.email)
      ORDER BY s.imported_at DESC NULLS LAST LIMIT 1
    ) va ON true
    WHERE e.kind = 'volunteer' AND e.legal_basis = 'contract' AND e.status = 'active'
    ORDER BY e.person_id, e.start_date DESC NULLS LAST
  ),
  vep AS (
    SELECT DISTINCT ON (COALESCE(NULLIF(a.pmi_id, ''), 'e:' || lower(a.email)))
      COALESCE(NULLIF(a.pmi_id, ''), 'e:' || lower(a.email)) AS match_key,
      CASE WHEN a.role_applied = 'researcher' THEN 'researcher' WHEN a.role_applied = 'leader' THEN 'leader' ELSE 'other' END AS role,
      COALESCE(c.cycle_code, 'no_cycle') AS cohort
    FROM public.selection_applications a
    LEFT JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE a.vep_status_raw = 'Active'
    ORDER BY COALESCE(NULLIF(a.pmi_id, ''), 'e:' || lower(a.email)), a.imported_at DESC NULLS LAST
  ),
  joined AS (
    SELECT COALESCE(p.role, v.role) AS role, COALESCE(p.cohort, v.cohort) AS cohort,
      p.match_key AS plat_key, v.match_key AS vep_key
    FROM plat p FULL OUTER JOIN vep v ON v.match_key = p.match_key
  ),
  cells AS (
    SELECT role, cohort, count(plat_key) AS platform_active, count(vep_key) AS vep_active
    FROM joined GROUP BY role, cohort
  )
  SELECT
    COALESCE(jsonb_agg(jsonb_build_object('role', role, 'cohort', cohort,
      'platform_active', platform_active, 'vep_active', vep_active, 'delta', platform_active - vep_active
    ) ORDER BY role, cohort), '[]'::jsonb),
    COALESCE(sum(platform_active), 0), COALESCE(sum(vep_active), 0)
  INTO v_matrix, v_plat_total, v_vep_total FROM cells;

  WITH plat AS (
    SELECT DISTINCT ON (e.person_id)
      e.person_id,
      CASE WHEN e.role = 'researcher' THEN 'researcher' WHEN e.role = 'leader' THEN 'leader' ELSE 'other' END AS role,
      COALESCE(sc.cycle_code, 'no_cycle') AS cohort,
      COALESCE(NULLIF(mem.pmi_id, ''), 'e:' || lower(mem.email)) AS match_key,
      mem.name AS member_name, mem.email, mem.pmi_id, va.vep_status_raw AS vep_status
    FROM public.engagements e
    LEFT JOIN public.selection_applications sa ON sa.id = e.selection_application_id
    LEFT JOIN public.selection_cycles sc ON sc.id = sa.cycle_id
    LEFT JOIN LATERAL (
      SELECT m.name, m.email, m.pmi_id FROM public.members m
      WHERE m.person_id = e.person_id ORDER BY (m.pmi_id IS NOT NULL) DESC, m.updated_at DESC NULLS LAST LIMIT 1
    ) mem ON true
    LEFT JOIN LATERAL (
      SELECT s.vep_status_raw FROM public.selection_applications s
      WHERE (s.pmi_id = mem.pmi_id AND s.pmi_id IS NOT NULL AND s.pmi_id <> '') OR lower(s.email) = lower(mem.email)
      ORDER BY s.imported_at DESC NULLS LAST LIMIT 1
    ) va ON true
    WHERE e.kind = 'volunteer' AND e.legal_basis = 'contract' AND e.status = 'active'
    ORDER BY e.person_id, e.start_date DESC NULLS LAST
  ),
  vep_keys AS (
    SELECT DISTINCT COALESCE(NULLIF(a.pmi_id, ''), 'e:' || lower(a.email)) AS match_key
    FROM public.selection_applications a WHERE a.vep_status_raw = 'Active'
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'member_name', p.member_name, 'email', p.email, 'pmi_id', p.pmi_id, 'role', p.role, 'cohort', p.cohort,
    'vep_status_raw', COALESCE(p.vep_status, '(sem app VEP)'),
    'suggested_action', 'Verificar VEP: ativo na plataforma mas mirror não está Active (sync defasado ou oferta não estendida)'
  ) ORDER BY p.member_name), '[]'::jsonb) INTO v_platform_only
  FROM plat p WHERE p.match_key NOT IN (SELECT match_key FROM vep_keys);

  WITH plat_keys AS (
    SELECT DISTINCT COALESCE(NULLIF(mem.pmi_id, ''), 'e:' || lower(mem.email)) AS match_key
    FROM public.engagements e
    LEFT JOIN LATERAL (
      SELECT m.pmi_id, m.email FROM public.members m
      WHERE m.person_id = e.person_id ORDER BY (m.pmi_id IS NOT NULL) DESC, m.updated_at DESC NULLS LAST LIMIT 1
    ) mem ON true
    WHERE e.kind = 'volunteer' AND e.legal_basis = 'contract' AND e.status = 'active' AND mem.email IS NOT NULL
  ),
  vep AS (
    SELECT DISTINCT ON (COALESCE(NULLIF(a.pmi_id, ''), 'e:' || lower(a.email)))
      COALESCE(NULLIF(a.pmi_id, ''), 'e:' || lower(a.email)) AS match_key,
      CASE WHEN a.role_applied = 'researcher' THEN 'researcher' WHEN a.role_applied = 'leader' THEN 'leader' ELSE 'other' END AS role,
      COALESCE(c.cycle_code, 'no_cycle') AS cohort, a.applicant_name, a.email, a.pmi_id, m.is_active AS member_is_active
    FROM public.selection_applications a
    LEFT JOIN public.selection_cycles c ON c.id = a.cycle_id
    LEFT JOIN LATERAL (
      SELECT mm.is_active FROM public.members mm
      WHERE (mm.pmi_id = a.pmi_id AND a.pmi_id IS NOT NULL AND a.pmi_id <> '') OR lower(mm.email) = lower(a.email)
      ORDER BY (mm.pmi_id IS NOT NULL) DESC LIMIT 1
    ) m ON true
    WHERE a.vep_status_raw = 'Active'
    ORDER BY COALESCE(NULLIF(a.pmi_id, ''), 'e:' || lower(a.email)), a.imported_at DESC NULLS LAST
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'applicant_name', v.applicant_name, 'email', v.email, 'pmi_id', v.pmi_id, 'role', v.role, 'cohort', v.cohort,
    'member_is_active', v.member_is_active,
    'suggested_action', CASE
      WHEN v.member_is_active IS FALSE THEN 'Ativo no VEP mas offboarded na plataforma — reativar contrato ou encerrar no VEP'
      WHEN v.member_is_active IS NULL THEN 'Ativo no VEP sem member na plataforma — verificar cadastro/vínculo'
      ELSE 'Ativo no VEP sem contrato de voluntário ativo — verificar engajamento na plataforma'
    END
  ) ORDER BY v.applicant_name), '[]'::jsonb) INTO v_vep_only
  FROM vep v WHERE v.match_key NOT IN (SELECT match_key FROM plat_keys);

  RETURN jsonb_build_object(
    'matrix', v_matrix, 'platform_only', v_platform_only, 'vep_only', v_vep_only,
    'totals', jsonb_build_object(
      'platform_active', v_plat_total, 'vep_active_mirror', v_vep_total, 'delta', v_plat_total - v_vep_total,
      'platform_only_count', jsonb_array_length(v_platform_only), 'vep_only_count', jsonb_array_length(v_vep_only)
    ),
    'mirror_note', 'vep_active_mirror = selection_applications.vep_status_raw=Active (espelho do worker pmi-vep-sync). Pode divergir do dashboard PMI ao vivo; use como piso reconciliável, não como verdade externa.',
    'generated_at', now()
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
