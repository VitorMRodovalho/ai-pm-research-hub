-- Audit 2026-07-21 (docs/audit/2026-07-21_scoring_merit_audit.md) — Finding A1 (ALTA)
-- rank_researcher/rank_leader ficavam STALE: nenhum gatilho recomputa o ranking quando um
-- score muda (recalculate_cycle_rankings só roda no botão). Último snapshot 2026-07-02, 26
-- avaliações depois. get_selection_rankings ordenava pelo rank armazenado E DESCARTAVA linhas
-- com rank NULL (13 researchers + 3 líderes sumiam da lista admin; Francisco J. exibido #39 /
-- vivo #7). get_my_selection_result mostrava o rank stale ao candidato (35/41 finais errados).
--
-- Correção: calcular o rank em TEMPO DE LEITURA via RANK() sobre os scores vivos, com os MESMOS
-- filtros de recalculate_cycle_rankings. Elimina a dependência do cache stale sem gatilho nem
-- recompute (ambas as fns são read-only / SECURITY DEFINER de leitura). As colunas
-- rank_researcher/rank_leader continuam existindo (snapshot histórico), mas as superfícies de
-- leitura não dependem mais delas.
--
-- NOTA (sessão main): read-only, sem mudança de dado. Validar após apply com um spot-check
-- (get_selection_rankings deve incluir os 13+3 antes ocultos; Francisco J. deve vir ~#7).

-- ============================================================
-- 1) get_selection_rankings — admin/curador (view_internal_analytics)
-- ============================================================
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
    SELECT id INTO v_cycle_id FROM public.selection_cycles ORDER BY created_at DESC LIMIT 1;
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

-- ============================================================
-- 2) get_my_selection_result — candidato (rank live, revelado só em status final)
--    Troca cirúrgica: as duas expressões CASE de rank agora computam RANK() ao vivo.
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_my_selection_result()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_apps jsonb;
BEGIN
  SELECT id, email, name INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  SELECT coalesce(jsonb_agg(row_to_json(app_data) ORDER BY (app_data->>'created_at') DESC), '[]'::jsonb)
  INTO v_apps
  FROM (
    SELECT
      a.id as application_id,
      a.cycle_id,
      sc.cycle_code,
      sc.title as cycle_title,
      a.role_applied,
      a.promotion_path,
      a.status,
      a.created_at,
      a.status = ANY(ARRAY['approved','converted','rejected','objective_cutoff','withdrawn','cancelled']) as is_final,
      a.objective_score_avg as objective_score,
      a.interview_score,
      a.research_score,
      a.leader_score,
      -- Audit A1: rank calculado ao vivo (RANK() sobre scores vivos), revelado só em status final.
      CASE
        WHEN a.status = ANY(ARRAY['approved','converted','rejected','objective_cutoff','withdrawn','cancelled'])
        THEN (
          SELECT r.rnk FROM (
            SELECT a2.id, RANK() OVER (ORDER BY a2.research_score DESC NULLS LAST, a2.applicant_name ASC) AS rnk
            FROM selection_applications a2
            WHERE a2.cycle_id = a.cycle_id
              AND a2.role_applied = 'researcher'
              AND a2.research_score IS NOT NULL
              AND a2.status NOT IN ('withdrawn','rejected','cancelled','merged')
              AND NOT EXISTS (
                SELECT 1 FROM selection_applications la
                WHERE la.id = a2.linked_application_id
                  AND la.role_applied = 'leader'
                  AND la.status IN ('approved','converted')
              )
          ) r WHERE r.id = a.id
        )
        ELSE NULL
      END as rank_researcher,
      CASE
        WHEN a.status = ANY(ARRAY['approved','converted','rejected','objective_cutoff','withdrawn','cancelled'])
        THEN (
          SELECT r.rnk FROM (
            SELECT a2.id, RANK() OVER (ORDER BY a2.leader_score DESC NULLS LAST, a2.applicant_name ASC) AS rnk
            FROM selection_applications a2
            WHERE a2.cycle_id = a.cycle_id
              AND (a2.role_applied = 'leader' OR a2.promotion_path = 'triaged_to_leader')
              AND a2.leader_score IS NOT NULL
              AND a2.status NOT IN ('withdrawn','rejected','cancelled','merged')
          ) r WHERE r.id = a.id
        )
        ELSE NULL
      END as rank_leader,
      (
        SELECT jsonb_object_agg(
          e.evaluation_type,
          jsonb_build_object(
            'pert_score', e.weighted_subtotal,
            'submitted_at', e.submitted_at
          )
        )
        FROM selection_evaluations e
        WHERE e.application_id = a.id AND e.submitted_at IS NOT NULL
        AND e.evaluator_id IN (
          SELECT evaluator_id FROM selection_evaluations WHERE application_id = a.id AND submitted_at IS NOT NULL LIMIT 1
        )
      ) as own_evaluations_sample,
      (
        SELECT count(*) FROM selection_applications sa2
        WHERE sa2.cycle_id = a.cycle_id
          AND sa2.role_applied = a.role_applied
          AND sa2.status NOT IN ('withdrawn','cancelled')
      ) as track_pool_size
    FROM selection_applications a
    JOIN selection_cycles sc ON sc.id = a.cycle_id
    WHERE lower(trim(a.email)) IN (
      SELECT lower(trim(m.email::text))  FROM public.members m        WHERE m.id = v_caller.id         AND m.email IS NOT NULL
      UNION
      SELECT lower(trim(me.email::text)) FROM public.member_emails me WHERE me.member_id = v_caller.id AND me.email IS NOT NULL
    )
  ) app_data;

  RETURN jsonb_build_object(
    'member_id', v_caller.id,
    'member_name', v_caller.name,
    'applications', v_apps,
    'note', 'Ranks são exibidos apenas após o status final da seleção. Durante o processo, você vê apenas seu status e notas próprias.'
  );
END;
$function$;
