-- #1801 — a classe inteira: "o ciclo ativo" deixa de ser resolvido por `created_at`.
--
-- `selection_cycles.created_at` é a data em que a LINHA foi escrita, não a do ciclo. O backfill do
-- `cycle2-2025` entrou em 2026-07-13, então a linha de um ciclo FECHADO de 2025 é a mais nova da
-- tabela, e todo `ORDER BY created_at DESC LIMIT 1` passou a apontar para ele.
--
-- A #1802 corrigiu `get_selection_health`. Esta migration fecha o resto da classe, medida sobre
-- `pg_proc` em 16/08/2026 (não sobre o repositório) e triada uma a uma — o critério é "esta função
-- escolhe UM ciclo para chamar de ativo?", não "esta função cita created_at".
--
-- Impacto medido em 16/08/2026, e ele não é cosmético:
--
--   | ciclo                        | candidaturas | aprovadas | avaliações | avaliadores |
--   |------------------------------|-------------:|----------:|-----------:|------------:|
--   | `cycle2-2025` (resolvido HOJE) |            8 |         6 |          0 |           0 |
--   | `cycle4-2026` (o correto)      |           81 |        57 |        238 |           2 |
--
-- Ou seja: o painel de calibração de avaliadores roda, por padrão, sobre um ciclo com ZERO
-- avaliações; o funil e o dashboard de diversidade descrevem 8 candidaturas em vez de 81; e o
-- ranking sai de um ciclo sem nenhuma nota.
--
-- ── O padrão canônico, agora com UM dono ─────────────────────────────────────────────────────────
-- A #1802 escreveu a ordenação certa inline. Repeti-la em mais seis lugares é como a classe volta,
-- então ela vira função: `selection_active_cycle_id()`. Três chaves, nesta ordem:
--   1. `status = 'open'` — a resposta certa quando existe ciclo aberto;
--   2. `open_date DESC` — a data do FATO, que sobrevive a backfill;
--   3. `created_at DESC` — último desempate, nunca o critério.
-- A chave 2 importa: o domínio do CHECK de `status` é
-- ('draft','open','evaluation','interview','decision','closed'), então um ciclo que avance de `open`
-- para `evaluation` deixaria de existir para um filtro `status = 'open'` puro. Ordenar em vez de
-- filtrar degrada com elegância em vez de devolver NULL.
--
-- ── Triagem: o que NÃO foi mexido, e por quê ─────────────────────────────────────────────────────
--   · `get_selection_cycles` — LISTA ciclos; ordenar por `created_at` ali é legítimo.
--   · `compute_ai_calibration_weekly` e `recompute_all_active_pert_cutoffs` — LOOP sem LIMIT: a
--     ordenação é ordem de iteração, não escolha. (Ambas filtram por `phase`, não por `status`;
--     isso é outra classe, relatada na issue e fora do escopo desta correção.)
--   · `check_application_score_consistency`, `link_my_credly_badge`, `get_cycle_renewal_radar`,
--     `nucleo_contract_cohort_cycle_id` — falso positivo da varredura por texto: o `created_at` /
--     `LIMIT 1` é de `selection_applications`, e o ciclo entra por chave estrangeira.

-- ─────────────────────────────────────────────────────────────────────────────────────────────────
-- 1. O helper canônico
-- ─────────────────────────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.selection_active_cycle_id()
RETURNS uuid
LANGUAGE sql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
  -- #1801 — o ciclo ativo por ESTADO. `created_at` é a data de escrita da linha e só entra como
  -- último desempate, depois de `open_date`, que é a data do fato.
  SELECT c.id
  FROM public.selection_cycles c
  ORDER BY (c.status = 'open') DESC,
           c.open_date  DESC NULLS LAST,
           c.created_at DESC
  LIMIT 1;
$function$;

COMMENT ON FUNCTION public.selection_active_cycle_id() IS
  '#1801 — resolve o ciclo de seleção ATIVO por estado (status open > open_date > created_at). '
  'Toda função que precise escolher UM ciclo deve chamar esta, nunca ORDER BY created_at DESC LIMIT 1: '
  'created_at é a data de escrita da linha, e um backfill histórico a torna a mais nova.';

REVOKE ALL ON FUNCTION public.selection_active_cycle_id() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.selection_active_cycle_id() TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────────────────────────
-- 2. get_diversity_dashboard — o ciclo padrão descrevia 8 candidaturas em vez de 81
-- ─────────────────────────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_diversity_dashboard(p_cycle_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_id uuid;
  v_by_gender jsonb;
  v_by_chapter jsonb;
  v_by_sector jsonb;
  v_by_seniority jsonb;
  v_by_region jsonb;
  v_applicants_total int;
  v_approved_total int;
  v_snapshots jsonb;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  IF NOT (public.can_by_member(v_caller_id, 'view_internal_analytics') OR public.can_by_member(v_caller_id, 'view_aggregate_analytics')) THEN
    RAISE EXCEPTION 'Unauthorized: admin or sponsor required';
  END IF;

  -- #1801 — era `ORDER BY created_at DESC LIMIT 1`, que devolvia o `cycle2-2025` (fechado).
  v_cycle_id := COALESCE(p_cycle_id, public.selection_active_cycle_id());
  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'no_cycle_found');
  END IF;

  SELECT COUNT(*) INTO v_applicants_total FROM public.selection_applications WHERE cycle_id = v_cycle_id;
  SELECT COUNT(*) INTO v_approved_total FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status IN ('approved', 'converted');

  SELECT jsonb_agg(jsonb_build_object('gender', gender_label, 'applicants', applicants, 'approved', approved))
  INTO v_by_gender
  FROM (
    SELECT CASE sa.gender
      WHEN 'M' THEN 'Masculino'
      WHEN 'F' THEN 'Feminino'
      ELSE COALESCE(sa.gender, 'Não informado')
    END as gender_label,
    COUNT(*) AS applicants,
    COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa WHERE sa.cycle_id = v_cycle_id GROUP BY gender_label ORDER BY applicants DESC
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('chapter', COALESCE(chapter, 'Não informado'), 'applicants', applicants, 'approved', approved))
  INTO v_by_chapter
  FROM (
    SELECT sa.chapter, COUNT(*) AS applicants, COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa WHERE sa.cycle_id = v_cycle_id GROUP BY sa.chapter ORDER BY applicants DESC
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('sector', COALESCE(sector, 'Não informado'), 'applicants', applicants, 'approved', approved))
  INTO v_by_sector
  FROM (
    SELECT sa.sector, COUNT(*) AS applicants, COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa WHERE sa.cycle_id = v_cycle_id GROUP BY sa.sector ORDER BY applicants DESC
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('band', band, 'applicants', applicants, 'approved', approved))
  INTO v_by_seniority
  FROM (
    SELECT CASE
      WHEN sa.seniority_years IS NULL THEN 'Não informado'
      WHEN sa.seniority_years < 3 THEN '0-2 anos'
      WHEN sa.seniority_years < 6 THEN '3-5 anos'
      WHEN sa.seniority_years < 11 THEN '6-10 anos'
      WHEN sa.seniority_years < 16 THEN '11-15 anos'
      ELSE '16+ anos'
    END AS band,
    COUNT(*) AS applicants, COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa WHERE sa.cycle_id = v_cycle_id GROUP BY band ORDER BY band
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('region', COALESCE(region, 'Não informado'), 'applicants', applicants, 'approved', approved))
  INTO v_by_region
  FROM (
    SELECT CASE
      WHEN sa.country IS NULL OR sa.country = '' THEN COALESCE(sa.state, 'Não informado')
      WHEN sa.country IN ('Brazil', 'BR', 'Brasil') THEN COALESCE(sa.state, 'Brasil')
      WHEN sa.state IS NOT NULL AND sa.state != '' THEN sa.state || ' (' || sa.country || ')'
      ELSE sa.country
    END AS region,
    COUNT(*) AS applicants, COUNT(*) FILTER (WHERE sa.status IN ('approved', 'converted')) AS approved
    FROM public.selection_applications sa WHERE sa.cycle_id = v_cycle_id GROUP BY region ORDER BY applicants DESC
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('snapshot_type', sds.snapshot_type, 'metrics', sds.metrics, 'created_at', sds.created_at) ORDER BY sds.created_at DESC)
  INTO v_snapshots
  FROM public.selection_diversity_snapshots sds WHERE sds.cycle_id = v_cycle_id;

  RETURN jsonb_build_object(
    'cycle_id', v_cycle_id,
    'applicants_total', v_applicants_total,
    'approved_total', v_approved_total,
    'by_gender', COALESCE(v_by_gender, '[]'::jsonb),
    'by_chapter', COALESCE(v_by_chapter, '[]'::jsonb),
    'by_sector', COALESCE(v_by_sector, '[]'::jsonb),
    'by_seniority', COALESCE(v_by_seniority, '[]'::jsonb),
    'by_region', COALESCE(v_by_region, '[]'::jsonb),
    'snapshots', COALESCE(v_snapshots, '[]'::jsonb)
  );
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────────────────────────
-- 3. get_entry_chapter_diagnosis — diagnosticava 6 aprovadas em vez de 57
-- ─────────────────────────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_entry_chapter_diagnosis(p_cycle_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(application_id uuid, member_id uuid, applicant_name text, bucket text, active_br_codes text[], entry_chapter_code text, member_chapter text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_id  uuid := p_cycle_id;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'Unauthorized: get_entry_chapter_diagnosis requires manage_platform';
    END IF;
  ELSIF current_setting('role', true) NOT IN ('service_role', 'postgres')
        AND current_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Unauthorized: get_entry_chapter_diagnosis requires authentication';
  END IF;

  -- #1801 — era `ORDER BY sc.created_at DESC LIMIT 1`.
  IF v_cycle_id IS NULL THEN
    v_cycle_id := public.selection_active_cycle_id();
  END IF;

  RETURN QUERY
  SELECT
    sa.id,
    m.id,
    sa.applicant_name,
    (cls->>'bucket')::text,
    ARRAY(SELECT jsonb_array_elements_text(cls->'active_br_codes')),
    m.entry_chapter_code,
    m.chapter
  FROM public.selection_applications sa
  LEFT JOIN public.members m ON lower(m.email) = lower(sa.email)
  CROSS JOIN LATERAL public.classify_entry_chapter(
    sa.pmi_memberships, sa.community_profile_private, sa.pmi_data_fetched_at
  ) AS cls
  WHERE sa.cycle_id = v_cycle_id
    AND sa.status = 'approved'
  ORDER BY sa.applicant_name;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────────────────────────
-- 4. get_evaluator_calibration_stats — calibrava sobre um ciclo com ZERO avaliações
-- ─────────────────────────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_evaluator_calibration_stats(p_cycle_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_id uuid;
  v_overall_mean numeric;
  v_overall_stddev numeric;
  v_total_apps integer;
  v_total_evals integer;
  v_per_evaluator jsonb;
  v_pair_divergence jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Not authorized: requires view_internal_analytics');
  END IF;

  IF p_cycle_code IS NOT NULL THEN
    SELECT id INTO v_cycle_id FROM public.selection_cycles WHERE cycle_code = p_cycle_code;
  ELSE
    -- #1801 — era `ORDER BY created_at DESC LIMIT 1`, e o `cycle2-2025` tem 0 avaliações.
    v_cycle_id := public.selection_active_cycle_id();
  END IF;

  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'No cycle found');
  END IF;

  -- Overall mean + stddev (de todas evaluations submitted no ciclo)
  SELECT
    AVG(e.weighted_subtotal),
    STDDEV_POP(e.weighted_subtotal),
    COUNT(DISTINCT e.application_id),
    COUNT(*)
  INTO v_overall_mean, v_overall_stddev, v_total_apps, v_total_evals
  FROM public.selection_evaluations e
  JOIN public.selection_applications a ON a.id = e.application_id
  WHERE a.cycle_id = v_cycle_id AND e.submitted_at IS NOT NULL;

  -- Per evaluator: mean, stddev, bias signed, bias abs, anomaly count
  SELECT jsonb_agg(jsonb_build_object(
    'member_id', t.evaluator_id,
    'name', m.name,
    'evaluations_count', t.eval_count,
    'mean_score', round(t.eval_mean, 2),
    'stddev', round(COALESCE(t.eval_stddev, 0), 2),
    'bias_signed', round(t.eval_mean - v_overall_mean, 2),
    'bias_abs', round(abs(t.eval_mean - v_overall_mean), 2),
    'anomaly_count', COALESCE(an.cnt, 0)
  ) ORDER BY abs(t.eval_mean - v_overall_mean) DESC)
  INTO v_per_evaluator
  FROM (
    SELECT
      e.evaluator_id,
      COUNT(*) AS eval_count,
      AVG(e.weighted_subtotal) AS eval_mean,
      STDDEV_POP(e.weighted_subtotal) AS eval_stddev
    FROM public.selection_evaluations e
    JOIN public.selection_applications a ON a.id = e.application_id
    WHERE a.cycle_id = v_cycle_id AND e.submitted_at IS NOT NULL
    GROUP BY e.evaluator_id
    HAVING COUNT(*) >= 1
  ) t
  JOIN public.members m ON m.id = t.evaluator_id
  LEFT JOIN (
    SELECT
      (payload->>'evaluator_id')::uuid AS evaluator_id,
      COUNT(*) AS cnt
    FROM public.selection_evaluation_anomalies
    WHERE cycle_id = v_cycle_id
      AND payload ? 'evaluator_id'
    GROUP BY (payload->>'evaluator_id')::uuid
  ) an ON an.evaluator_id = t.evaluator_id;

  -- Pair divergence: top 5 pares com maior |mean_a - mean_b| no MESMO conjunto
  -- de candidatos (intersect só)
  SELECT jsonb_agg(jsonb_build_object(
    'evaluator_a_id', p.eval_a,
    'evaluator_a_name', ma.name,
    'evaluator_b_id', p.eval_b,
    'evaluator_b_name', mb.name,
    'shared_applications', p.shared,
    'mean_diff_abs', round(p.diff, 2)
  ) ORDER BY p.diff DESC)
  INTO v_pair_divergence
  FROM (
    SELECT
      e1.evaluator_id AS eval_a,
      e2.evaluator_id AS eval_b,
      COUNT(*) AS shared,
      ABS(AVG(e1.weighted_subtotal - e2.weighted_subtotal)) AS diff
    FROM public.selection_evaluations e1
    JOIN public.selection_evaluations e2
      ON e2.application_id = e1.application_id
      AND e2.evaluation_type = e1.evaluation_type
      AND e2.evaluator_id > e1.evaluator_id  -- avoid (a,b) and (b,a) duplicates
      AND e2.submitted_at IS NOT NULL
    JOIN public.selection_applications a ON a.id = e1.application_id
    WHERE a.cycle_id = v_cycle_id AND e1.submitted_at IS NOT NULL
    GROUP BY e1.evaluator_id, e2.evaluator_id
    HAVING COUNT(*) >= 2  -- pares com pelo menos 2 avaliações compartilhadas
    ORDER BY diff DESC
    LIMIT 5
  ) p
  JOIN public.members ma ON ma.id = p.eval_a
  JOIN public.members mb ON mb.id = p.eval_b;

  RETURN jsonb_build_object(
    'cycle_summary', jsonb_build_object(
      'cycle_id', v_cycle_id,
      'total_applications', v_total_apps,
      'total_evaluators', (SELECT COUNT(DISTINCT evaluator_id) FROM public.selection_evaluations e
                           JOIN public.selection_applications a ON a.id=e.application_id
                           WHERE a.cycle_id=v_cycle_id AND e.submitted_at IS NOT NULL),
      'total_evaluations', v_total_evals,
      'overall_mean', round(COALESCE(v_overall_mean, 0), 2),
      'overall_stddev', round(COALESCE(v_overall_stddev, 0), 2)
    ),
    'per_evaluator', COALESCE(v_per_evaluator, '[]'::jsonb),
    'pair_divergence', COALESCE(v_pair_divergence, '[]'::jsonb),
    'fetched_at', now()
  );
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────────────────────────
-- 5. get_selection_pipeline_metrics — o funil descrevia 8 candidaturas em vez de 81
-- ─────────────────────────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_selection_pipeline_metrics(p_cycle_id uuid DEFAULT NULL::uuid, p_chapter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_id uuid;
  v_funnel jsonb;
  v_by_chapter jsonb;
  v_conversion_rate numeric;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  -- V4: view_internal_analytics covers admin/GP + sponsor + chapter_liaison
  IF NOT (public.can_by_member(v_caller_id, 'view_internal_analytics') OR public.can_by_member(v_caller_id, 'view_aggregate_analytics')) THEN
    RAISE EXCEPTION 'Unauthorized: admin or sponsor required';
  END IF;

  IF p_cycle_id IS NOT NULL THEN
    v_cycle_id := p_cycle_id;
  ELSE
    -- #1801 — era `ORDER BY created_at DESC LIMIT 1`.
    v_cycle_id := public.selection_active_cycle_id();
  END IF;

  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'no_cycle_found');
  END IF;

  -- ADR-0109 PR-2 COI recusal: an active candidate in this cycle is recused from this selection surface.
  IF public.selection_coi_recused(v_caller_id, v_cycle_id) THEN
    RETURN jsonb_build_object('error', 'recused_conflict_of_interest',
      'detail', 'Você é candidato(a) neste ciclo — as visões de seleção estão impedidas por conflito de interesse (ADR-0109).');
  END IF;

  SELECT jsonb_build_object(
    'total_applications', COUNT(*),
    'screening', COUNT(*) FILTER (WHERE status = 'screening'),
    'objective_eval', COUNT(*) FILTER (WHERE status = 'objective_eval'),
    'passed_cutoff', COUNT(*) FILTER (WHERE status NOT IN ('submitted', 'screening', 'objective_eval', 'objective_cutoff', 'rejected', 'withdrawn', 'cancelled')),
    'interview_pending', COUNT(*) FILTER (WHERE status = 'interview_pending'),
    'interview_scheduled', COUNT(*) FILTER (WHERE status = 'interview_scheduled'),
    'interview_done', COUNT(*) FILTER (WHERE status = 'interview_done'),
    'interview_noshow', COUNT(*) FILTER (WHERE status = 'interview_noshow'),
    'final_eval', COUNT(*) FILTER (WHERE status = 'final_eval'),
    'approved', COUNT(*) FILTER (WHERE status = 'approved'),
    'rejected', COUNT(*) FILTER (WHERE status = 'rejected'),
    'waitlist', COUNT(*) FILTER (WHERE status = 'waitlist'),
    'converted', COUNT(*) FILTER (WHERE status = 'converted'),
    'withdrawn', COUNT(*) FILTER (WHERE status = 'withdrawn')
  ) INTO v_funnel
  FROM public.selection_applications
  WHERE cycle_id = v_cycle_id
    AND (p_chapter IS NULL OR chapter = p_chapter);

  SELECT jsonb_agg(
    jsonb_build_object(
      'chapter', chapter,
      'total', total,
      'approved', approved,
      'rejected', rejected,
      'waitlist', waitlist,
      'converted', converted,
      'avg_score', avg_score
    )
  ) INTO v_by_chapter
  FROM (
    SELECT
      sa.chapter,
      COUNT(*) AS total,
      COUNT(*) FILTER (WHERE sa.status = 'approved') AS approved,
      COUNT(*) FILTER (WHERE sa.status = 'rejected') AS rejected,
      COUNT(*) FILTER (WHERE sa.status = 'waitlist') AS waitlist,
      COUNT(*) FILTER (WHERE sa.status = 'converted') AS converted,
      ROUND(AVG(sa.final_score), 2) AS avg_score
    FROM public.selection_applications sa
    WHERE sa.cycle_id = v_cycle_id
      AND (p_chapter IS NULL OR sa.chapter = p_chapter)
    GROUP BY sa.chapter
    ORDER BY sa.chapter
  ) sub;

  v_conversion_rate := CASE
    WHEN (v_funnel->>'total_applications')::int > 0
    THEN ROUND(((v_funnel->>'approved')::int + (v_funnel->>'converted')::int)::numeric /
         (v_funnel->>'total_applications')::int * 100, 1)
    ELSE 0
  END;

  RETURN jsonb_build_object(
    'cycle_id', v_cycle_id,
    'chapter_filter', p_chapter,
    'funnel', v_funnel,
    'by_chapter', COALESCE(v_by_chapter, '[]'::jsonb),
    'conversion_rate', v_conversion_rate
  );
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────────────────────────
-- 6. get_selection_rankings — ranqueava um ciclo sem nenhuma nota
-- ─────────────────────────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_selection_rankings(p_cycle_code text DEFAULT NULL::text, p_track text DEFAULT 'both'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_id uuid;
  v_pert_cutoff jsonb;
  v_researcher jsonb;
  v_leader jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Unauthorized: admin/GP/curator only');
  END IF;

  IF p_cycle_code IS NOT NULL THEN
    SELECT id INTO v_cycle_id FROM public.selection_cycles WHERE cycle_code = p_cycle_code;
  ELSE
    -- #1801 — era `ORDER BY created_at DESC LIMIT 1`.
    v_cycle_id := public.selection_active_cycle_id();
  END IF;

  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'No cycle found');
  END IF;

  -- ADR-0109 COI recusal
  IF public.selection_coi_recused(v_caller_id, v_cycle_id) THEN
    RETURN jsonb_build_object('error', 'recused_conflict_of_interest',
      'detail', 'Você é candidato(a) neste ciclo — as visões de seleção estão impedidas por conflito de interesse (ADR-0109).');
  END IF;

  SELECT jsonb_build_object(
    'target_score', MAX(pert_target_score),
    'band_lower', MAX(pert_band_lower),
    'band_upper', MAX(pert_band_upper),
    'cohort_n', MAX(pert_cohort_n),
    'method', MAX(pert_cutoff_method),
    'calc_at', MAX(pert_calc_at)
  ) INTO v_pert_cutoff
  FROM public.selection_applications WHERE cycle_id = v_cycle_id;

  -- Audit A1: rank calculado ao vivo (RANK() sobre research_score), mesmos filtros de
  -- recalculate_cycle_rankings; inclui TODAS as linhas ranqueáveis (não descarta rank NULL).
  IF p_track IN ('researcher', 'both') THEN
    WITH ranked AS (
      SELECT a.applicant_name, a.chapter, a.research_score, a.status, a.promotion_path,
             a.pert_band_lower, a.pert_band_upper,
             RANK() OVER (ORDER BY a.research_score DESC NULLS LAST, a.applicant_name ASC) AS live_rank
      FROM public.selection_applications a
      WHERE a.cycle_id = v_cycle_id
        AND a.role_applied = 'researcher'
        AND a.research_score IS NOT NULL
        AND a.status NOT IN ('withdrawn','rejected','cancelled','merged')
        AND NOT EXISTS (
          SELECT 1 FROM public.selection_applications la
          WHERE la.id = a.linked_application_id
            AND la.role_applied = 'leader'
            AND la.status IN ('approved','converted')
        )
    )
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'rank', live_rank,
      'applicant_name', applicant_name,
      'chapter', chapter,
      'research_score', research_score,
      'status', status,
      'promotion_path', promotion_path,
      'pert_band_position', CASE
        WHEN research_score IS NULL OR pert_band_lower IS NULL OR pert_band_upper IS NULL THEN NULL
        WHEN research_score < pert_band_lower THEN 'below'
        WHEN research_score > pert_band_upper THEN 'above'
        ELSE 'within'
      END
    ) ORDER BY live_rank), '[]'::jsonb)
    INTO v_researcher
    FROM ranked;
  END IF;

  IF p_track IN ('leader', 'both') THEN
    WITH ranked AS (
      SELECT a.applicant_name, a.chapter, a.research_score, a.leader_score, a.status, a.promotion_path,
             a.pert_band_lower, a.pert_band_upper,
             RANK() OVER (ORDER BY a.leader_score DESC NULLS LAST, a.applicant_name ASC) AS live_rank
      FROM public.selection_applications a
      WHERE a.cycle_id = v_cycle_id
        AND (a.role_applied = 'leader' OR a.promotion_path = 'triaged_to_leader')
        AND a.leader_score IS NOT NULL
        AND a.status NOT IN ('withdrawn','rejected','cancelled','merged')
    )
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'rank', live_rank,
      'applicant_name', applicant_name,
      'chapter', chapter,
      'research_score', research_score,
      'leader_score', leader_score,
      'status', status,
      'promotion_path', promotion_path,
      'pert_band_position', CASE
        WHEN leader_score IS NULL OR pert_band_lower IS NULL OR pert_band_upper IS NULL THEN NULL
        WHEN leader_score < pert_band_lower THEN 'below'
        WHEN leader_score > pert_band_upper THEN 'above'
        ELSE 'within'
      END
    ) ORDER BY live_rank), '[]'::jsonb)
    INTO v_leader
    FROM ranked;
  END IF;

  RETURN jsonb_build_object(
    'cycle_id', v_cycle_id,
    'track', p_track,
    'pert_cutoff', v_pert_cutoff,
    'rank_source', 'live_readtime',
    'researcher_track', COALESCE(v_researcher, '[]'::jsonb),
    'leader_track', COALESCE(v_leader, '[]'::jsonb),
    'formula', jsonb_build_object(
      'research_score', 'objective_pert + interview_pert',
      'leader_score', 'research_score * 0.7 + leader_extra_pert * 0.3',
      'tiebreaker', 'Standard Competition Ranking (ISO 80000-2) + applicant_name ASC'
    )
  );
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────────────────────────
-- 7. get_chapter_selection_summary — o "último ciclo" do capítulo, e o defeito DORMENTE
-- ─────────────────────────────────────────────────────────────────────────────────────────────────
-- O ramo `open` já filtrava `status = 'open'` e por isso a #1801 o citava como referência; o que
-- ninguém tinha lido era o ramo `last`, que não filtra nada. Como os 4 ciclos são do mesmo capítulo
-- (`PMI-GO`), ele devolve hoje o `cycle2-2025` (encerrado em 30/11/2025) como "último ciclo", em vez
-- do `cycle4-2026` (30/06/2026).
--
-- O defeito está DORMENTE: a tela (`ChapterDashboard`) só renderiza `last` quando NÃO há ciclo
-- aberto, e hoje há. Ele acorda sozinho no dia em que o `cycle4-2026` fechar — que é exatamente o
-- tipo de bug que não se quer descobrir em produção.
--
-- `last` passa a ordenar pela data do FATO (`close_date`, depois `open_date`); no ramo `open`,
-- `created_at` deixa de ser a primeira chave pelo mesmo motivo, caso um capítulo venha a ter dois
-- ciclos abertos.

CREATE OR REPLACE FUNCTION public.get_chapter_selection_summary(p_chapter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_chapter text;
  v_chapter text;
BEGIN
  SELECT m.id, m.chapter INTO v_caller_id, v_caller_chapter
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- V4 gate (mirrors get_chapter_dashboard): cross-chapter for view_internal_analytics OR the
  -- external aggregate auditor (view_aggregate_analytics, ADR-0111 amendment), else own chapter.
  IF public.can_by_member(v_caller_id, 'view_internal_analytics')
     OR public.can_by_member(v_caller_id, 'view_aggregate_analytics') THEN
    v_chapter := COALESCE(p_chapter, v_caller_chapter);
  ELSIF p_chapter IS NULL OR p_chapter = v_caller_chapter THEN
    v_chapter := v_caller_chapter;
  ELSE
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  IF v_chapter IS NULL THEN
    RETURN jsonb_build_object('error', 'No chapter specified');
  END IF;

  RETURN jsonb_build_object(
    'open', (
      SELECT jsonb_build_object(
        'cycle_code', sc.cycle_code,
        'title', sc.title,
        'close_date', sc.close_date,
        'booking_url', sc.interview_booking_url,
        'open_apps', (SELECT count(*) FROM public.selection_applications sa WHERE sa.cycle_id = sc.id)
      )
      FROM public.selection_cycles sc
      WHERE sc.contracting_chapter = v_chapter AND sc.status = 'open'
      ORDER BY sc.open_date DESC NULLS LAST, sc.created_at DESC LIMIT 1
    ),
    'last', (
      SELECT jsonb_build_object('title', sc.title, 'close_date', sc.close_date)
      FROM public.selection_cycles sc
      WHERE sc.contracting_chapter = v_chapter
      ORDER BY sc.close_date DESC NULLS LAST, sc.open_date DESC NULLS LAST, sc.created_at DESC LIMIT 1
    )
  );
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────────────────────────
-- 8. get_my_pending_evaluations — zero mudança hoje, e é de propósito
-- ─────────────────────────────────────────────────────────────────────────────────────────────────
-- Esta filtra por `phase = 'evaluating'`, que é ESTADO, então nunca chegou a cair no `cycle2-2025`
-- (que está em `planning`). Medido em 16/08: antes e depois resolvem o mesmo `cycle4-2026`.
--
-- Ainda assim entra, por dois motivos. Primeiro, `created_at` era a PRIMEIRA chave de desempate
-- entre ciclos em `evaluating`, e a divergência phase × status já existe no dado (`cycle2-2025` está
-- `closed` com phase `planning`): um ciclo fechado com a phase parada em `evaluating` capturaria a
-- fila. Segundo, o portão de autorização logo abaixo é escopado no ciclo escolhido, então "qual
-- ciclo" também decide "quem pode ler" — não é lugar para desempate por data de escrita.
--
-- O #298 pediu determinismo, e o determinismo continua: a ordenação é total, só que por estado.

CREATE OR REPLACE FUNCTION public.get_my_pending_evaluations()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_cycle record;
  v_pending jsonb;
  v_completed_count int;
  v_total_count int;
  -- #705 Bug 1/3 — terminais NÃO são avaliáveis: excluídos da fila, do numerador
  -- (completed) E do denominador (total) para o indicador fechar (pending +
  -- completed = total; progress_pct <= 100).
  v_terminal constant text[] := ARRAY['rejected','withdrawn','cancelled','approved','converted','waitlist','interview_noshow'];
BEGIN
  -- Authenticate caller
  SELECT m.id INTO v_caller_member_id
  FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Pick the evaluating cycle deterministically (fix #298 A+ part 1), por ESTADO (#1801):
  -- `created_at` é a data de escrita da linha e só entra como último desempate.
  SELECT * INTO v_cycle FROM public.selection_cycles
  WHERE phase = 'evaluating'
    AND status <> 'closed'
  ORDER BY (status = 'open') DESC,
           open_date DESC NULLS LAST,
           created_at DESC
  LIMIT 1;

  -- No evaluating cycle -> return empty consistently (no info leak)
  IF v_cycle.id IS NULL THEN
    RETURN jsonb_build_object('cycle', null, 'pending', '[]'::jsonb, 'completed_count', 0, 'total_count', 0);
  END IF;

  -- Gate scoped to picked cycle's committee OR admin manage_member bypass (fix #298 A+ part 2)
  IF NOT EXISTS (
    SELECT 1 FROM public.selection_committee sc
    WHERE sc.member_id = v_caller_member_id AND sc.cycle_id = v_cycle.id
  ) AND NOT public.can_by_member(v_caller_member_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: caller is not on this cycle committee'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Pending = EVALUÁVEIS (não-terminais) do ciclo onde o avaliador ainda não submeteu.
  -- #705 Bug 1: faltava o filtro de status -> terminais poluíam a fila.
  SELECT jsonb_agg(jsonb_build_object(
    'application_id', sa.id,
    'applicant_name', sa.applicant_name,
    'role_applied', sa.role_applied,
    'promotion_path', sa.promotion_path,
    'created_at', sa.created_at,
    'has_my_evaluation_in_progress',
      EXISTS (SELECT 1 FROM public.selection_evaluations se
              WHERE se.application_id = sa.id AND se.evaluator_id = v_caller_member_id
                AND se.submitted_at IS NULL)
  ) ORDER BY sa.created_at)
  INTO v_pending
  FROM public.selection_applications sa
  WHERE sa.cycle_id = v_cycle.id
    AND sa.status <> ALL (v_terminal)
    AND NOT EXISTS (
      SELECT 1 FROM public.selection_evaluations se
      WHERE se.application_id = sa.id
        AND se.evaluator_id = v_caller_member_id
        AND se.submitted_at IS NOT NULL
    );

  -- Completed = apps avaliáveis DISTINTOS que o avaliador já submeteu.
  -- #705 Bug 3: era count(*) sobre o JOIN de evals -> fan-out fazia completed > total.
  SELECT count(DISTINCT sa.id)
  INTO v_completed_count
  FROM public.selection_applications sa
  JOIN public.selection_evaluations se ON se.application_id = sa.id
  WHERE sa.cycle_id = v_cycle.id
    AND sa.status <> ALL (v_terminal)
    AND se.evaluator_id = v_caller_member_id
    AND se.submitted_at IS NOT NULL;

  -- Total = apps avaliáveis do ciclo (denominador alinhado com a fila).
  SELECT count(*) INTO v_total_count
  FROM public.selection_applications
  WHERE cycle_id = v_cycle.id
    AND status <> ALL (v_terminal);

  RETURN jsonb_build_object(
    'cycle_code', v_cycle.cycle_code,
    'cycle_phase', v_cycle.phase,
    'pending', COALESCE(v_pending, '[]'::jsonb),
    'pending_count', COALESCE(jsonb_array_length(v_pending), 0),
    'completed_count', v_completed_count,
    'total_count', v_total_count,
    'progress_pct', CASE WHEN v_total_count > 0 THEN round((v_completed_count::numeric / v_total_count) * 100, 1) ELSE 0 END
  );
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────────────────────────
-- 9. _test_invariants_with_synthetic_breach — qualquer ciclo serve, mas o guard não sabe disso
-- ─────────────────────────────────────────────────────────────────────────────────────────────────
-- Esta só precisa de um `cycle_id` válido para semear a violação sintética, então o ciclo escolhido
-- é indiferente ao resultado. Passa a usar o helper mesmo assim: assim o ratchet do #1801 nasce com
-- linha de base VAZIA, em vez de carregar uma exceção que o próximo leitor teria de reavaliar.

CREATE OR REPLACE FUNCTION public._test_invariants_with_synthetic_breach(p_breach text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_cycle_id uuid;
  v_org_id uuid;
  v_test_email text;
  v_result jsonb;
BEGIN
  IF current_setting('role', true) NOT IN ('service_role', 'postgres')
     AND current_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Unauthorized: _test_invariants_with_synthetic_breach requires service_role';
  END IF;

  IF p_breach NOT IN ('R', 'S') THEN
    RAISE EXCEPTION 'Invalid p_breach value: % (must be ''R'' or ''S'')', p_breach;
  END IF;

  -- #1801 — era `ORDER BY created_at DESC LIMIT 1`. Qualquer ciclo serviria aqui; usa o helper
  -- para que a classe não tenha exceção.
  v_cycle_id := public.selection_active_cycle_id();
  SELECT organization_id
  INTO v_org_id
  FROM public.selection_cycles
  WHERE id = v_cycle_id;

  IF v_cycle_id IS NULL THEN
    RAISE EXCEPTION 'No selection_cycles available — cannot seed synthetic breach';
  END IF;

  v_test_email := '__test_invariant_' || lower(p_breach) || '_' ||
                  replace(gen_random_uuid()::text, '-', '') || '@invariant.test';

  INSERT INTO public.selection_applications (
    cycle_id, organization_id, applicant_name, email, role_applied, status
  ) VALUES (
    v_cycle_id, v_org_id,
    '__test_invariant_synthetic__', v_test_email,
    'researcher', 'approved'
  );

  IF p_breach = 'S' THEN
    INSERT INTO public.members (
      organization_id, name, email, member_status, person_id, chapter
    ) VALUES (
      v_org_id, '__test_invariant_synthetic__', v_test_email,
      'active', NULL, 'Outro'
    );
  END IF;

  SELECT jsonb_agg(row_to_json(t) ORDER BY t.invariant_name)
  INTO v_result
  FROM public.check_schema_invariants() t
  WHERE t.invariant_name IN (
    'R_approved_application_has_member',
    'S_approved_member_has_person_id'
  );

  RETURN v_result;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────────────────────────
-- 10. O ratchet: um guard DERIVADO do catálogo, não uma lista de nomes
-- ─────────────────────────────────────────────────────────────────────────────────────────────────
-- A #1586(b) já tinha corrigido exatamente este defeito em `detect_stuck_selection_funnel`, com a
-- nota certa no corpo. O que faltou foi varrer a classe — e sem guard, a classe volta pela próxima
-- função nova. Uma lista de nomes cobriria só o que alguém lembrou de escrever nela, que é como
-- `get_entry_chapter_diagnosis` e o ramo `last` do `get_chapter_selection_summary` passaram
-- despercebidos na primeira varredura (a issue listava 10 funções; o catálogo tinha 12).
--
-- O predicado é afiado de propósito: viola quem escolhe UMA linha de `selection_cycles`
-- (`FROM ... selection_cycles ... LIMIT 1`) tendo `created_at` como PRIMEIRA chave do `ORDER BY`.
-- `created_at` como último desempate é legítimo e não acusa. Validado contra o catálogo vivo em
-- 16/08: acusava as 8 funções acima e liberava as 6 que já faziam certo, sem falso positivo.
--
-- ⚠️ Duas armadilhas de regex do Postgres que este corpo evita, ambas medidas:
--   · `\b` é BACKSPACE no ARE do Postgres, não fronteira de palavra (isso é `\y`). Com `\b` o
--     guard devolvia zero linhas e parecia "nada a corrigir".
--   · a preferência gulosa/não-gulosa do RE INTEIRO vem do PRIMEIRO quantificador com preferência,
--     então `\s+` guloso antes de `[^;]*?` torna o conjunto guloso. Por isso a janela é limitada
--     (`{0,250}`) em vez de não-gulosa.

CREATE OR REPLACE FUNCTION public._audit_selection_cycle_resolution()
RETURNS TABLE(funcao text, args text, resolve_por_created_at boolean, usa_helper boolean, exemplo text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH fragmento AS (
    SELECT p.proname::text AS funcao,
           pg_get_function_identity_arguments(p.oid)::text AS args,
           (p.prosrc ~* 'selection_active_cycle_id\s*\(') AS usa_helper,
           m[1] AS trecho
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace,
    LATERAL regexp_matches(p.prosrc, '(from\s+(public\.)?selection_cycles\y[^;]{0,250})', 'gi') AS m
    WHERE n.nspname = 'public'
      AND p.prosrc ILIKE '%selection_cycles%'
      AND p.proname <> '_audit_selection_cycle_resolution'
  ),
  escolha AS (
    SELECT * FROM fragmento WHERE trecho ~* 'limit\s+1'
  )
  SELECT e.funcao,
         e.args,
         bool_or(e.trecho ~* 'order\s+by\s+[a-z_]*\.?created_at'),
         bool_or(e.usa_helper),
         left(regexp_replace(
           COALESCE(
             min(e.trecho) FILTER (WHERE e.trecho ~* 'order\s+by\s+[a-z_]*\.?created_at'),
             min(e.trecho)
           ), '\s+', ' ', 'g'), 200)
  FROM escolha e
  GROUP BY e.funcao, e.args
  ORDER BY 3 DESC, 1;
$function$;

COMMENT ON FUNCTION public._audit_selection_cycle_resolution() IS
  '#1801 — ratchet: lista toda função que escolhe UMA linha de selection_cycles e marca quem resolve '
  'por created_at como primeira chave de ordenacao. Derivado de pg_proc, nao de lista de nomes. '
  'Linha de base esperada: ZERO com resolve_por_created_at = true.';

REVOKE ALL ON FUNCTION public._audit_selection_cycle_resolution() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._audit_selection_cycle_resolution() TO service_role;

NOTIFY pgrst, 'reload schema';
