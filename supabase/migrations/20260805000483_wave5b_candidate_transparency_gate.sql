-- Onda 5b (arco de auditoria pontuacao/merito, umbrella #1465) — transparencia do candidato pos-decisao.
-- Politica ratificada pelo owner (2026-07-23): candidato APROVADO/CONVERTIDO ve seu breakdown por criterio
-- (scores agregados por pilar + posicao vs banda de corte + rank) SOMENTE apos o anuncio (fase 'announcement');
-- candidato REJEITADO (ou qualquer status nao-selecionado) ve SO "nao selecionado", sem breakdown numerico.
-- A politica e imposta na FONTE (RPC), nao no cliente: os numeros nao trafegam no payload para quem nao passou.
-- Alcanca TODA superficie de auto-servico (web + MCP), pois ambos usam o mesmo auth.uid()/self-only.
-- Notas e identidades de avaliadores NUNCA sao expostas por auto-servico a nenhum status (reservadas ao Art. 18).
-- Parecer legal-counsel + ux-leader (2026-07-23) ratificado. Fecha exposicao viva do cycle3-2026 (announcement).

-- =====================================================================================================
-- 1) get_my_selection_result() — breakdown/rank revelados so a aprovado/convertido pos-anuncio.
--    Remove own_evaluations_sample (amostra por-avaliador, vazamento de-anonimizante e nao-agregado).
--    Adiciona final_score + banda PERT (final_score_pert_band_lower/upper/target + pert_target_score).
-- =====================================================================================================
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

  -- Onda 5b: corrige bug latente pre-existente (ORDER BY (app_data->>'created_at') aplicava ->> sobre
  -- tipo record, que nao existe; a funcao lancava erro para todo chamador autenticado real -- nunca pego
  -- porque nenhuma pagina a consumia e o teste p511 so exercita o caminho service-role/early-return).
  SELECT coalesce(jsonb_agg(row_to_json(app_data) ORDER BY app_data.created_at DESC), '[]'::jsonb)
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
      -- Onda 5b: breakdown numerico revelado SOMENTE ao candidato aprovado/convertido E apos a decisao
      -- (fase 'announcement'). Rejeitados e nao-anunciados recebem NULL na fonte (politica "rejeitado ve
      -- so nao selecionado"). Notas/nomes de avaliadores nunca trafegam por aqui.
      (a.status = ANY(ARRAY['approved','converted']) AND sc.phase = 'announcement') as reveal_breakdown,
      CASE WHEN a.status = ANY(ARRAY['approved','converted']) AND sc.phase = 'announcement'
        THEN a.objective_score_avg ELSE NULL END as objective_score,
      CASE WHEN a.status = ANY(ARRAY['approved','converted']) AND sc.phase = 'announcement'
        THEN a.interview_score ELSE NULL END as interview_score,
      CASE WHEN a.status = ANY(ARRAY['approved','converted']) AND sc.phase = 'announcement'
        THEN a.research_score ELSE NULL END as research_score,
      CASE WHEN a.status = ANY(ARRAY['approved','converted']) AND sc.phase = 'announcement'
        THEN a.leader_score ELSE NULL END as leader_score,
      CASE WHEN a.status = ANY(ARRAY['approved','converted']) AND sc.phase = 'announcement'
        THEN a.final_score ELSE NULL END as final_score,
      CASE WHEN a.status = ANY(ARRAY['approved','converted']) AND sc.phase = 'announcement'
        THEN a.final_score_pert_band_lower ELSE NULL END as band_lower,
      CASE WHEN a.status = ANY(ARRAY['approved','converted']) AND sc.phase = 'announcement'
        THEN a.final_score_pert_band_upper ELSE NULL END as band_upper,
      CASE WHEN a.status = ANY(ARRAY['approved','converted']) AND sc.phase = 'announcement'
        THEN a.final_score_pert_target ELSE NULL END as band_target,
      CASE WHEN a.status = ANY(ARRAY['approved','converted']) AND sc.phase = 'announcement'
        THEN a.pert_target_score ELSE NULL END as objective_target,
      -- Rank (Audit A1: RANK() ao vivo), revelado sob a mesma condicao do breakdown.
      CASE
        WHEN a.status = ANY(ARRAY['approved','converted']) AND sc.phase = 'announcement'
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
        WHEN a.status = ANY(ARRAY['approved','converted']) AND sc.phase = 'announcement'
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
      CASE
        WHEN a.status = ANY(ARRAY['approved','converted']) AND sc.phase = 'announcement'
        THEN (
          SELECT count(*) FROM selection_applications sa2
          WHERE sa2.cycle_id = a.cycle_id
            AND sa2.role_applied = a.role_applied
            AND sa2.status NOT IN ('withdrawn','cancelled')
        )
        ELSE NULL
      END as track_pool_size
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
    'note', 'Breakdown numerico e posicao sao exibidos apenas para candidaturas aprovadas apos o anuncio do resultado. Notas e identidades de avaliadores nunca sao expostas.'
  );
END;
$function$;

-- =====================================================================================================
-- 2) get_my_evaluation_feedback() — scores numericos so a aprovado/convertido; feedback qualitativo
--    (narrative) permanece a todos os status finais; array por-avaliador (notes+scores) REMOVIDO do
--    auto-servico (reservado ao canal formal Art. 18, com cegamento). Gate de fase pre-existente mantido.
-- =====================================================================================================
CREATE OR REPLACE FUNCTION public.get_my_evaluation_feedback()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_reveal_scores boolean;
  v_reveal_phases text[] := ARRAY['evaluations_closed','interviews','interviews_closed','ranking','announcement','onboarding']::text[];
BEGIN
  SELECT id, email, name INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;

  -- Most recent application
  SELECT a.id, a.objective_score_avg, a.interview_score, a.research_score, a.leader_score,
         a.feedback, a.status, sc.phase, sc.cycle_code
  INTO v_app
  FROM public.selection_applications a
  JOIN public.selection_cycles sc ON sc.id = a.cycle_id
  -- #511: match caller's PRIMARY email OR any member_emails alternate (leak-safe: member_emails.email globally UNIQUE).
  WHERE lower(trim(a.email)) IN (
    SELECT lower(trim(m.email::text))  FROM public.members m        WHERE m.id = v_caller.id         AND m.email IS NOT NULL
    UNION
    SELECT lower(trim(me.email::text)) FROM public.member_emails me WHERE me.member_id = v_caller.id AND me.email IS NOT NULL
  )
  ORDER BY a.created_at DESC
  LIMIT 1;

  IF v_app.id IS NULL THEN
    RETURN jsonb_build_object('error','no_application');
  END IF;

  -- Gate: only post-reveal phase OR final status
  IF NOT (v_app.phase = ANY(v_reveal_phases))
     AND v_app.status NOT IN ('approved','converted','rejected','objective_cutoff') THEN
    RETURN jsonb_build_object(
      'feedback_available', false,
      'reason', 'phase_not_revealed',
      'current_phase', v_app.phase,
      'note', 'Feedback sera disponibilizado quando o ciclo entrar em fase de revelacao (evaluations_closed em diante).'
    );
  END IF;

  -- Onda 5b: scores numericos revelados SOMENTE a aprovados/convertidos (politica "rejeitado ve so nao
  -- selecionado"). Feedback qualitativo (narrative) permanece a todos os status finais. Notas e scores
  -- por-avaliador NUNCA sao expostos por auto-servico (reservados ao canal formal Art. 18 com cegamento).
  v_reveal_scores := v_app.status = ANY(ARRAY['approved','converted']);

  RETURN jsonb_build_object(
    'feedback_available', true,
    'application_id', v_app.id,
    'cycle_code', v_app.cycle_code,
    'phase', v_app.phase,
    'status', v_app.status,
    'scores_revealed', v_reveal_scores,
    'objective_score_avg', CASE WHEN v_reveal_scores THEN v_app.objective_score_avg ELSE NULL END,
    'interview_score', CASE WHEN v_reveal_scores THEN v_app.interview_score ELSE NULL END,
    'research_score', CASE WHEN v_reveal_scores THEN v_app.research_score ELSE NULL END,
    'leader_score', CASE WHEN v_reveal_scores THEN v_app.leader_score ELSE NULL END,
    'narrative_feedback', v_app.feedback
  );
END;
$function$;
