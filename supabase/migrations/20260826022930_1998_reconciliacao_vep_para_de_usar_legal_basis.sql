-- #1998 -- a reconciliacao VEP deixa de usar legal_basis como prova de vinculo.
--
-- Sintoma que o PM levantou em 25/08 olhando /admin/vep-reconciliation: a lista "Ativo no VEP
-- sem contrato de voluntario ativo" acusava pessoas que TEM engajamento ativo. Medido em
-- 26/08: 5 de 5 linhas da lista eram falso positivo (Gerson, Guilherme, Gustavo, Ligia e
-- Rogerio). A 6a linha (Vinicyus) saiu sozinha quando o pmi-vep-sync reimportou 26/08 01:45 UTC
-- e o espelho dele virou 'Complete'.
--
-- CAUSA. As tres CTEs do lado plataforma filtravam `e.legal_basis = 'contract'`. legal_basis e
-- a base legal LGPD Art. 7 do engajamento, nao um estado de fluxo: usa-la para responder "essa
-- pessoa e voluntaria ativa?" e erro de categoria. Na pratica ela funcionava como proxy de "foi
-- criado por approve_selection_application", porque a coluna tem DEFAULT 'consent' e os outros
-- caminhos de entrada nao a escrevem. Medido em engajamentos volunteer ativos:
--   approve_selection_application 51 + backfill_v4_phase3 21  -> contract
--   tribe_request_approved 31 + audit_1247 7 + outros 6       -> consent (o DEFAULT)
-- get_vep_role_cohort_reconciliation e a UNICA funcao viva que filtra por esse valor.
--
-- TAMANHO REAL, que desmente o corpo da issue. Sao 44 engajamentos 'consent', mas 39 daquelas
-- pessoas TAMBEM tem um engajamento 'contract' e ja apareciam. Pessoas realmente invisiveis: 5.
-- (78 pessoas distintas com volunteer ativo: 34 so contract, 39 ambos, 5 so consent.)
--
-- TRES MUDANCAS, e as duas ultimas existem por causa da primeira:
--
--  1. O filtro de legal_basis sai das 3 CTEs do lado plataforma.
--
--  2. O DISTINCT ON passa a preferir a linha que carrega selection_application_id. SEM isso,
--     largar o filtro reclassifica 38 das 73 pessoas: o desempate era so start_date DESC, e a
--     linha 'consent' costuma ser mais nova, entao a matriz elegeria uma linha sem FK e as
--     pessoas sem coorte no lado plataforma saltariam de 2 para 45. Medido: com o desempate,
--     1 troca de linha (Vitor, manager/contract -> coordinator/consent, mesmo balde 'other'),
--     0 mudancas de coorte.
--
--  3. A coorte cai para a candidatura resolvida POR CHAVE quando a FK esta ausente, reusando a
--     lateral `va` que a propria funcao ja monta para o vep_status. As 5 pessoas corrigidas nao
--     tem selection_application_id, mas as 5 tem candidatura achavel por pmi_id/e-mail
--     (4 em cycle3-2026, 1 em cycle4-2026). Sem esse passo elas entrariam em 'no_cycle', ou
--     seja, a correcao trocaria 5 falsos positivos numa lista por 5 linhas fora de lugar na
--     matriz.
--
-- EFEITO MEDIDO (26/08, antes -> depois):
--   vep_only (a lista que o PM olhou)   5 -> 0
--   plat_keys (denominador plataforma) 73 -> 78
--   platform_only                       5 -> 5  (as MESMAS pessoas, nenhuma nova)
--   matriz researcher/cycle3-2026   delta -4 -> 0   (plat 7 -> 12, VEP 11 -> 12)
--   matriz researcher/cycle4-2026   delta +2 -> +3  (plat 48 -> 49, VEP 46; o Rogerio ja
--                                   contava do lado VEP e faltava do lado plataforma)
--   matriz researcher/no_cycle      a celula SOME   (a pessoa e o par VEP dela migram p/ cycle3)
--
-- As celulas da matriz saem do FULL OUTER JOIN, que reclassifica o lado VEP pela coorte do lado
-- plataforma quando o par casa: por isso o ANTES tem de ser medido com a MESMA cadeia de CTEs,
-- e nao somando os dois lados em separado. O delta total continua 5, igual a platform_only.
--
-- Corpo derivado da captura 20260818102206, cujo md5 normalizado foi conferido IDENTICO ao vivo
-- (23855d6448ec8f2c666be38cb5b1cfb5, 8403 bytes) antes de qualquer edicao. Substituicoes
-- contadas, com controle negativo sobre o lado VEP (c.cycle_code), no script de build.
--
-- NAO mexe em dado: os 44 'consent' continuam 'consent'. Se a base legal deles esta certa e
-- decisao de LGPD, nao de tela, e o catalogo (engagement_kinds.volunteer = 'contract') diverge
-- das linhas sem nenhum guard olhando. Fica em issue propria.

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
      COALESCE(sc.cycle_code, va.cycle_code, 'no_cycle') AS cohort,
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
      SELECT s.vep_status_raw, vc.cycle_code FROM public.selection_applications s
      LEFT JOIN public.selection_cycles vc ON vc.id = s.cycle_id
      WHERE (s.pmi_id = mem.pmi_id AND s.pmi_id IS NOT NULL AND s.pmi_id <> '') OR lower(s.email) = lower(mem.email)
      ORDER BY s.imported_at DESC NULLS LAST LIMIT 1
    ) va ON true
    WHERE e.kind = 'volunteer' AND e.status = 'active'
    ORDER BY e.person_id, (e.selection_application_id IS NOT NULL) DESC, e.start_date DESC NULLS LAST
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
      COALESCE(sc.cycle_code, va.cycle_code, 'no_cycle') AS cohort,
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
      SELECT s.vep_status_raw, vc.cycle_code FROM public.selection_applications s
      LEFT JOIN public.selection_cycles vc ON vc.id = s.cycle_id
      WHERE (s.pmi_id = mem.pmi_id AND s.pmi_id IS NOT NULL AND s.pmi_id <> '') OR lower(s.email) = lower(mem.email)
      ORDER BY s.imported_at DESC NULLS LAST LIMIT 1
    ) va ON true
    WHERE e.kind = 'volunteer' AND e.status = 'active'
    ORDER BY e.person_id, (e.selection_application_id IS NOT NULL) DESC, e.start_date DESC NULLS LAST
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
    WHERE e.kind = 'volunteer' AND e.status = 'active' AND mem.email IS NOT NULL
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
      ELSE 'Ativo no VEP sem engajamento de voluntário ativo — verificar vínculo na plataforma'
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
