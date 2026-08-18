-- #1838 -- o avaliador do comite deixa de ser barrado nas telas ao redor da entrevista.
-- Lote 4 de 4: get_vep_role_cohort_reconciliation (LEITURA).
--
-- Decisao do PM (17/08): gate por participacao no comite do ciclo somada a view_pii; as
-- ESCRITAS restritas aos papeis que decidem (evaluator, lead) -- observador observa. O dominio
-- de selection_committee.role e ('evaluator','lead','observer'), entao a lista de dois exclui
-- EXATAMENTE o observador: recorte exaustivo, nao amostra que envelhece.
--
-- Gate ADITIVO: quem passava antes continua passando. Nenhuma capacidade ampliada, nenhum combo
-- de engagement_kind_permissions semeado -- isto e scoping inline de RPC, o terceiro caminho de
-- autoridade do V4 (docs/reference/V4_AUTHORITY_MODEL.md).
--
-- is_selection_committee_member(id, NULL) e selection_committee_role_for(id) compartilham o
-- predicado (status='open' OR phase='evaluating'), que e o sinal publicado para a pagina, entao
-- tela e servidor nao divergem (#1590).
--
-- Corpos extraidos das capturas (md5 normalizado conferido IDENTICO ao vivo antes de editar),
-- com substituicoes CONTADAS e diferenca revisada. CREATE FUNCTION virou CREATE OR REPLACE onde
-- a captura era antiga, porque OR REPLACE preserva as ACLs.

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
  -- #1838: alem de view_internal_analytics, o avaliador do comite do ciclo (aberto ou em
  -- avaliacao) com view_pii tambem opera esta tela. is_selection_committee_member(id, NULL) usa
  -- o MESMO predicado de selection_committee_role_for(), que e o sinal que a pagina publica,
  -- entao o gate da tela e o do servidor nao divergem.
  IF NOT (
       public.can_by_member(v_caller_id, 'view_internal_analytics')
    OR (public.is_selection_committee_member(v_caller_id, NULL)
        AND public.can_by_member(v_caller_id, 'view_pii'))
  ) THEN
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