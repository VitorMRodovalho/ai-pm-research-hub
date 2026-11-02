-- #2393, fatia 3 (ADR-0134, decisão do GP em 02/11/2026): marcador de piloto por vaga, parte 1 de 2.
--
-- vep_opportunities.evaluation_track separa duas coisas que is_active misturava: is_active segue
-- governando SÓ a importação do VEP; evaluation_track governa SÓ a avaliação. 'general' (default) é o
-- fluxo do comitê do ciclo; 'line_pilot' é a vaga de linha avaliada em três partes (ADR-0134 §3, §4 e
-- P2), fora do comitê geral. Com o default, nenhuma vaga muda de comportamento com esta migration.
--
-- _na_avaliacao_geral(uuid): a candidatura NÃO é de vaga 'line_pilot'? O marcador segue a vaga, não o
-- ciclo (opportunity_id é único): candidatura redirecionada de ciclo pelo worker continua fora da
-- avaliação geral. Candidatura sem vaga é da avaliação geral.
--
-- Esta parte cobre a FILA e a AVALIAÇÃO do comitê:
--   get_selection_dashboard      linha piloto só para manage_platform, com evaluation_track e
--                                line_pilot_total; posição objetiva separada por trilha. As contagens
--                                do topo seguem sendo do ciclo inteiro (agregado, sem identificação).
--   get_my_pending_evaluations   piloto fora da fila, do concluído e do total do avaliador.
--   get_my_committee_assignments piloto fora das atribuições.
--   get_evaluation_form          recusa piloto antes do registro de acesso (D1: para todos).
--   submit_evaluation            recusa piloto (D1: para todos, inclusive manage_platform).
-- A parte 2 cobre as automações.
--
-- Os 5 corpos são os das capturas vigentes mais as linhas marcadas "#2393 fatia 3". CREATE OR REPLACE
-- preserva dono e privilégios: nenhum GRANT ou REVOKE dessas 5 muda aqui.

ALTER TABLE public.vep_opportunities
  ADD COLUMN IF NOT EXISTS evaluation_track text NOT NULL DEFAULT 'general';

ALTER TABLE public.vep_opportunities
  ADD CONSTRAINT vep_opportunities_evaluation_track_check
  CHECK (evaluation_track IN ('general', 'line_pilot'));

COMMENT ON COLUMN public.vep_opportunities.evaluation_track IS
  'ADR-0134 (#2393): trilha de avaliação da vaga. general = comitê do ciclo; line_pilot = piloto da linha, fora da avaliação geral. is_active governa só a importação.';

CREATE OR REPLACE FUNCTION public._na_avaliacao_geral(p_application_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT NOT EXISTS (
    SELECT 1
    FROM public.selection_applications sa
    JOIN public.vep_opportunities vo ON vo.opportunity_id = sa.vep_opportunity_id
    WHERE sa.id = p_application_id
      AND vo.evaluation_track = 'line_pilot'
  );
$function$;

REVOKE ALL ON FUNCTION public._na_avaliacao_geral(uuid) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public._na_avaliacao_geral(uuid) IS
  'ADR-0134 (#2393): a candidatura pertence à avaliação geral do comitê? false quando a vaga dela é line_pilot. Só para funções SECURITY DEFINER.';

CREATE OR REPLACE FUNCTION public.get_selection_dashboard(p_cycle_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_id uuid;
  v_result jsonb;
  v_stats_a jsonb;
  v_stats_b jsonb;
  v_via_committee boolean := false;   -- #1591
  v_ve_piloto boolean := false;       -- #2393 fatia 3
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  -- #1591: o comite de selecao e autoridade de LEITURA desta tela. Ate aqui a porta so
  -- falava `view_internal_analytics`, que um avaliador nao tem: o dominio sabia quem era do
  -- comite e a RPC nao. O ciclo EXATO e conferido logo abaixo, depois de resolvido.
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    v_via_committee := public.is_selection_committee_member(v_caller_id, NULL);
    IF NOT v_via_committee THEN
      RETURN jsonb_build_object('error', 'Unauthorized');
    END IF;
  END IF;
  IF p_cycle_code IS NOT NULL THEN
    SELECT id INTO v_cycle_id FROM public.selection_cycles WHERE cycle_code = p_cycle_code;
  ELSE
    -- #1446: prefer the current OPEN cycle; only fall back to newest created_at
    -- when no cycle is open. Fixes the historical-reimport shadowing bug.
    SELECT id INTO v_cycle_id FROM public.selection_cycles ORDER BY (status = 'open') DESC, created_at DESC LIMIT 1;
  END IF;
  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'No cycle found', 'cycle', null, 'applications', '[]'::jsonb, 'stats', jsonb_build_object('total', 0));
  END IF;

  -- #1591: entrou pelo comite -> so pode ler o ciclo DELE. Sem isto, ser do comite do ciclo
  -- vivo abriria o PII de candidato de todos os ciclos passados.
  IF v_via_committee AND NOT public.is_selection_committee_member(v_caller_id, v_cycle_id) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- ADR-0109 PR-2 COI recusal: an active candidate in this cycle is recused from this selection surface.
  IF public.selection_coi_recused(v_caller_id, v_cycle_id) THEN
    RETURN jsonb_build_object('error', 'recused_conflict_of_interest',
      'detail', 'Você é candidato(a) neste ciclo — as visões de seleção estão impedidas por conflito de interesse (ADR-0109).');
  END IF;

  -- #2393 fatia 3: candidatura de vaga piloto da linha (vep_opportunities.evaluation_track) fica fora
  -- da avaliação geral. Nesta tela só a gestão a vê, marcada pela trilha. As contagens do topo seguem
  -- sendo do ciclo inteiro: são agregadas e não identificam ninguém.
  v_ve_piloto := public.can_by_member(v_caller_id, 'manage_platform');

  v_stats_a := jsonb_build_object(
    'total', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id),
    'approved', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status IN ('approved', 'converted')),
    'rejected', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status IN ('rejected', 'objective_cutoff')),
    'pending', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status IN ('submitted', 'screening', 'objective_eval', 'interview_pending', 'interview_scheduled', 'interview_done', 'final_eval')),
    'cancelled', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status IN ('cancelled', 'withdrawn')),
    'waitlist', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND status = 'waitlist'),
    'leader_ranked', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND rank_leader IS NOT NULL),
    'researcher_ranked', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND rank_researcher IS NOT NULL),
    'ai_analysis_done_count', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND consent_ai_analysis_at IS NOT NULL AND ai_analysis IS NOT NULL),
    'consent_ai_pending', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND consent_ai_analysis_at IS NULL),
    'consent_ai_consented', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND consent_ai_analysis_at IS NOT NULL AND consent_ai_analysis_revoked_at IS NULL),
    'consent_ai_revoked', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND consent_ai_analysis_revoked_at IS NOT NULL)
  );

  v_stats_b := jsonb_build_object(
    'line_pilot_total', CASE WHEN v_ve_piloto THEN (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND NOT public._na_avaliacao_geral(id)) END,  -- #2393 fatia 3
    'with_peer_evals_2plus', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND (SELECT count(DISTINCT e.evaluator_id) FROM public.selection_evaluations e WHERE e.application_id = a.id AND e.evaluation_type = 'objective' AND e.submitted_at IS NOT NULL) >= 2),
    'with_interview_scheduled', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND EXISTS (SELECT 1 FROM public.selection_interviews si WHERE si.application_id = a.id AND si.status IN ('scheduled','completed','rescheduled'))),
    'with_interview_today', (
      SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id
        AND EXISTS (SELECT 1 FROM public.selection_interviews si WHERE si.application_id = a.id
          AND si.status = 'scheduled'
          AND (si.scheduled_at AT TIME ZONE 'America/Sao_Paulo')::date = (now() AT TIME ZONE 'America/Sao_Paulo')::date)
    ),
    'with_video_uploaded', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND EXISTS (SELECT 1 FROM public.pmi_video_screenings v WHERE v.application_id = a.id AND v.status IN ('uploaded','transcribing','transcribed'))),
    'with_video_opted_out', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND EXISTS (SELECT 1 FROM public.pmi_video_screenings v WHERE v.application_id = a.id) AND NOT EXISTS (SELECT 1 FROM public.pmi_video_screenings v WHERE v.application_id = a.id AND v.status IN ('uploaded','transcribing','transcribed'))),
    'with_pmi_member_active', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND pmi_id IS NOT NULL AND pmi_id <> '' AND service_latest_end_date >= CURRENT_DATE),
    'with_chapter_canonical', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND service_history_chapters IS NOT NULL AND service_history_chapters <> '' AND service_history_chapters <> 'PMI Global'),
    'with_re_applicants', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND COALESCE(application_count, 1) > 1),
    'with_briefing_generated', (SELECT count(*) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND last_briefing_at IS NOT NULL),
    'shadow_vep_count', (
      SELECT count(*) FROM public.selection_applications a
      WHERE a.cycle_id = v_cycle_id
        AND a.status IN ('approved', 'converted', 'cancelled', 'rejected', 'withdrawn')
        -- #2393: a mesma regra do is_shadow_vep da linha. Uma funcao, uma definicao de sombra.
        AND NOT EXISTS (
          SELECT 1 FROM public.vep_opportunities o
          WHERE o.opportunity_id = a.vep_opportunity_id
            AND o.initiative_id IS NOT NULL
        )
        AND EXISTS (
          SELECT 1 FROM public.members m
          WHERE m.is_active = true
            AND lower(m.email) = lower(a.email)
            AND m.created_at < a.created_at
        )
    ),
    'my_evals_submitted', (SELECT count(*) FROM public.selection_evaluations e JOIN public.selection_applications a ON a.id = e.application_id WHERE a.cycle_id = v_cycle_id AND e.evaluator_id = v_caller_id AND e.submitted_at IS NOT NULL),
    'my_evals_pending', (SELECT count(*) FROM public.selection_applications a WHERE a.cycle_id = v_cycle_id AND EXISTS (SELECT 1 FROM public.notifications n WHERE n.type = 'peer_review_requested' AND n.source_id = a.id AND n.recipient_id = v_caller_id) AND NOT EXISTS (SELECT 1 FROM public.selection_evaluations e WHERE e.application_id = a.id AND e.evaluator_id = v_caller_id))
  );

  SELECT jsonb_build_object(
    'cycle', (SELECT jsonb_build_object(
      'id', c.id, 'cycle_code', c.cycle_code, 'title', c.title, 'status', c.status,
      'interview_booking_url', c.interview_booking_url,
      'interview_questions', COALESCE(c.interview_questions, '[]'::jsonb),
      'pert_cutoff', (SELECT jsonb_build_object(
        'target_score', MAX(pert_target_score),
        'band_lower', MAX(pert_band_lower),
        'band_upper', MAX(pert_band_upper),
        'cohort_n', MAX(pert_cohort_n),
        'method', MAX(pert_cutoff_method),
        'calc_at', MAX(pert_calc_at),
        'apps_with_pert', COUNT(*) FILTER (WHERE pert_target_score IS NOT NULL),
        'apps_total', COUNT(*)
      ) FROM public.selection_applications WHERE cycle_id = v_cycle_id),
      'leader_extra_cutoff', (SELECT jsonb_build_object(
        'target_score', MAX(leader_extra_pert_target),
        'band_lower', MAX(leader_extra_pert_band_lower),
        'band_upper', MAX(leader_extra_pert_band_upper),
        'cohort_n', MAX(leader_extra_pert_cohort_n),
        'method', MAX(leader_extra_pert_cutoff_method),
        'calc_at', MAX(leader_extra_pert_calc_at),
        'apps_with_pert', COUNT(*) FILTER (WHERE leader_extra_pert_target IS NOT NULL),
        'apps_with_score', COUNT(*) FILTER (WHERE leader_extra_pert_score IS NOT NULL),
        'apps_total', COUNT(*)
      ) FROM public.selection_applications WHERE cycle_id = v_cycle_id),
      'final_score_cutoff_researcher', (SELECT jsonb_build_object(
        'target_score', MAX(final_score_pert_target),
        'band_lower', MAX(final_score_pert_band_lower),
        'band_upper', MAX(final_score_pert_band_upper),
        'cohort_n', MAX(final_score_pert_cohort_n),
        'method', MAX(final_score_pert_cutoff_method),
        'calc_at', MAX(final_score_pert_calc_at),
        'apps_with_pert', COUNT(*) FILTER (WHERE final_score_pert_target IS NOT NULL),
        'apps_with_score', COUNT(*) FILTER (WHERE final_score IS NOT NULL),
        'apps_total', COUNT(*)
      ) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND role_applied = 'researcher'),
      'final_score_cutoff_leader', (SELECT jsonb_build_object(
        'target_score', MAX(final_score_pert_target),
        'band_lower', MAX(final_score_pert_band_lower),
        'band_upper', MAX(final_score_pert_band_upper),
        'cohort_n', MAX(final_score_pert_cohort_n),
        'method', MAX(final_score_pert_cutoff_method),
        'calc_at', MAX(final_score_pert_calc_at),
        'apps_with_pert', COUNT(*) FILTER (WHERE final_score_pert_target IS NOT NULL),
        'apps_with_score', COUNT(*) FILTER (WHERE final_score IS NOT NULL),
        'apps_total', COUNT(*)
      ) FROM public.selection_applications WHERE cycle_id = v_cycle_id AND role_applied = 'leader')
    ) FROM public.selection_cycles c WHERE c.id = v_cycle_id),
    'applications', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', a.id, 'applicant_name', a.applicant_name, 'email', a.email,
          'phone', a.phone,
          'role_applied', a.role_applied, 'chapter', a.chapter, 'status', a.status,
          'objective_score', a.objective_score_avg, 'final_score', a.final_score,
          'research_score', a.research_score, 'leader_score', a.leader_score,
          'rank_researcher', a.rank_researcher, 'rank_leader', a.rank_leader,
          'promotion_path', a.promotion_path, 'linked_application_id', a.linked_application_id,
          'rank_chapter', a.rank_chapter, 'rank_overall', a.rank_overall,
          'objective_rank', a.objective_rank,
          'linkedin_url', a.linkedin_url, 'resume_url', a.resume_url,
          'resume_storage_path', a.resume_storage_path,
          'resume_synced_at', a.resume_synced_at,
          'tags', a.tags, 'feedback', a.feedback,
          'motivation', a.motivation_letter, 'experience_years', a.seniority_years,
          'membership_status', a.membership_status, 'certifications', a.certifications,
          'is_returning_member', a.is_returning_member, 'application_date', a.application_date,
          'academic_background', a.academic_background, 'areas_of_interest', a.areas_of_interest,
          'availability_declared', a.availability_declared, 'non_pmi_experience', a.non_pmi_experience,
          'proposed_theme', a.proposed_theme, 'leadership_experience', a.leadership_experience,
          'created_at', a.created_at,
          -- #1587: `interview_status` era um cache que NUNCA assumia 'completed' -- nenhuma das
          -- 29 funcoes vivas que tocam selection_interviews o escrevia com esse valor. Medido em
          -- 14/08/2026: 106 das 170 candidaturas exibiam aqui um estado divergente do que as
          -- proprias linhas de entrevista provam (65 diziam 'none' e 32 'scheduled' para
          -- candidaturas com entrevista JA REALIZADA). A tela passa a ler o estado DERIVADO da
          -- view canonica; o cache continua no payload sob outra chave, para o ratchet poder
          -- medir a divergencia encolher sem depender de consulta manual.
          'interview_status', COALESCE(
            (SELECT v.interview_state FROM public.v_application_interview_state v
              WHERE v.application_id = a.id),
            a.interview_status
          ),
          'interview_status_cache', a.interview_status,
          'interview_reschedule_reason', a.interview_reschedule_reason,
          'interview_reschedule_requested_at', a.interview_reschedule_requested_at,
          'consent_ai_status', CASE
            WHEN a.consent_ai_analysis_revoked_at IS NOT NULL THEN 'revoked'
            WHEN a.consent_ai_analysis_at IS NOT NULL THEN 'consented'
            ELSE 'pending'
          END,
          'consent_ai_at', a.consent_ai_analysis_at,
          'consent_ai_revoked_at', a.consent_ai_analysis_revoked_at,
          'member_credly_url', (SELECT m.credly_url FROM public.members m WHERE lower(m.email) = lower(a.email) LIMIT 1),
          'member_photo_url', (SELECT m.photo_url FROM public.members m WHERE lower(m.email) = lower(a.email) LIMIT 1),
          'leader_extra_pert_score', a.leader_extra_pert_score
        ) || jsonb_build_object(
          'interview_score', a.interview_score,
          'cutoff_approved_email_sent_at', a.cutoff_approved_email_sent_at,
          'final_score_pert_target', a.final_score_pert_target,
          'final_score_pert_band_lower', a.final_score_pert_band_lower,
          'final_score_pert_band_upper', a.final_score_pert_band_upper,
          'final_score_pert_cutoff_method', a.final_score_pert_cutoff_method,
          'final_score_pert_cohort_n', a.final_score_pert_cohort_n,
          'final_score_pert_calc_at', a.final_score_pert_calc_at,
          'peer_eval_count', (
            SELECT count(*)::int FROM public.selection_evaluations e
            WHERE e.application_id = a.id AND e.evaluation_type = 'objective' AND e.submitted_at IS NOT NULL
          ),
          'peer_extra', jsonb_build_object(
            'distinct_evaluators', (
              SELECT count(DISTINCT e.evaluator_id)::int FROM public.selection_evaluations e
              WHERE e.application_id = a.id AND e.evaluation_type = 'objective' AND e.submitted_at IS NOT NULL
            ),
            'invites_pending', (
              SELECT count(*)::int FROM public.notifications n
              WHERE n.type = 'peer_review_requested' AND n.source_id = a.id
                AND NOT EXISTS (SELECT 1 FROM public.selection_evaluations e2 WHERE e2.application_id = a.id AND e2.evaluator_id = n.recipient_id)
            )
          ),
          'meta', jsonb_build_object(
            'ai_analysis_done', (a.consent_ai_analysis_at IS NOT NULL AND a.ai_analysis IS NOT NULL),
            'interview_scheduled', EXISTS (SELECT 1 FROM public.selection_interviews si WHERE si.application_id = a.id AND si.status IN ('scheduled', 'completed', 'rescheduled')),
            'interview_next_at', (
              SELECT MIN(si.scheduled_at) FROM public.selection_interviews si
              WHERE si.application_id = a.id
                AND si.status = 'scheduled'
                AND si.scheduled_at >= now() - interval '12 hours'
            ),
            'has_interview_today', EXISTS (
              SELECT 1 FROM public.selection_interviews si
              WHERE si.application_id = a.id
                AND si.status = 'scheduled'
                AND (si.scheduled_at AT TIME ZONE 'America/Sao_Paulo')::date = (now() AT TIME ZONE 'America/Sao_Paulo')::date
            ),
            'token_consumed', EXISTS (SELECT 1 FROM public.onboarding_tokens t WHERE t.source_id = a.id AND t.source_type = 'pmi_application' AND COALESCE(t.access_count, 0) > 0),
            'video_screening_done', EXISTS (SELECT 1 FROM public.pmi_video_screenings v WHERE v.application_id = a.id AND v.status IN ('uploaded', 'transcribing', 'transcribed', 'opted_out')),
            'interview_stuck', (
              a.status = 'interview_scheduled'
              AND EXISTS (
                SELECT 1 FROM public.selection_interviews si
                WHERE si.application_id = a.id
                  AND si.status = 'scheduled'
                  AND si.conducted_at IS NULL
                  AND si.scheduled_at IS NOT NULL
                  AND si.scheduled_at < now() - COALESCE(
                        (SELECT value_interval FROM public.sla_policies WHERE policy_key = 'stuck_scheduled_grace'),
                        interval '48 hours')
              )
            )
          ),
          'video_agg', jsonb_build_object(
            'status_agg', (SELECT CASE WHEN count(*) = 0 THEN 'none' WHEN count(*) FILTER (WHERE v.status IN ('uploaded','transcribing','transcribed')) > 0 THEN 'uploaded' WHEN count(*) FILTER (WHERE v.status = 'opted_out') = count(*) THEN 'opted_out' ELSE 'partial' END FROM public.pmi_video_screenings v WHERE v.application_id = a.id),
            'uploaded_count', (SELECT count(*)::int FROM public.pmi_video_screenings v WHERE v.application_id = a.id AND v.status IN ('uploaded','transcribing','transcribed')),
            'total_rows', (SELECT count(*)::int FROM public.pmi_video_screenings v WHERE v.application_id = a.id)
          ),
          'pmi_canonical', jsonb_build_object(
            'chapter_canonical', (
              SELECT trim(c) FROM unnest(string_to_array(COALESCE(a.service_history_chapters, ''), ';')) AS c
              WHERE trim(c) <> '' AND trim(c) <> 'PMI Global' LIMIT 1
            ),
            'pmi_memberships', COALESCE(a.pmi_memberships, '[]'::jsonb),
            'is_pmi_member', (a.pmi_id IS NOT NULL AND a.pmi_id <> ''),
            'member_status', CASE
              WHEN a.pmi_id IS NULL OR a.pmi_id = '' THEN 'unknown'
              WHEN a.service_latest_end_date IS NULL THEN 'unknown'
              WHEN a.service_latest_end_date >= CURRENT_DATE THEN 'active'
              ELSE 'past'
            END,
            'member_since', a.service_first_start_date,
            'member_until', a.service_latest_end_date,
            'service_history_count', COALESCE(a.service_history_count, 0),
            'phase_b_fetched_at', a.pmi_data_fetched_at,
            'pmi_id', a.pmi_id
          ),
          'extra_flags', jsonb_build_object(
            'application_count', COALESCE(a.application_count, 1),
            'has_briefing', (a.last_briefing_at IS NOT NULL),
            'briefing_at', a.last_briefing_at,
            'briefing_model', a.last_briefing_model,
            'ai_triage_score', a.ai_triage_score,
            'ai_triage_confidence', a.ai_triage_confidence,
            'is_shadow_vep', (
              a.status IN ('approved', 'converted', 'cancelled', 'rejected', 'withdrawn')
              -- #2393: candidatura a vaga ligada a uma iniciativa nunca e sombra (decisao do GP,
              -- 30/10/2026). Le so a existencia da iniciativa; nenhuma coluna da vaga sai daqui.
              AND NOT EXISTS (
                SELECT 1 FROM public.vep_opportunities o
                WHERE o.opportunity_id = a.vep_opportunity_id
                  AND o.initiative_id IS NOT NULL
              )
              AND EXISTS (
                SELECT 1 FROM public.members m
                WHERE m.is_active = true
                  AND lower(m.email) = lower(a.email)
                  AND m.created_at < a.created_at
              )
            ),
            'pdf_likely_invalid', EXISTS (
              SELECT 1 FROM storage.objects so
              WHERE so.bucket_id = 'selection-resumes'
                AND so.name = a.resume_storage_path
                AND (so.metadata->>'size')::int < 1000
            )
          ),
          'vep_recon', jsonb_build_object(
            'status_raw', a.vep_status_raw,
            'last_seen_at', a.vep_last_seen_at,
            'reconciled_at', a.vep_reconciled_at,
            'offer_expires_at', a.vep_offer_expires_at,
            'expired_at', a.vep_expired_at
          ),
          'my_eval_status', COALESCE(
            (SELECT CASE WHEN e.submitted_at IS NOT NULL THEN 'submitted' ELSE 'draft' END
              FROM public.selection_evaluations e WHERE e.application_id = a.id AND e.evaluator_id = v_caller_id LIMIT 1),
            CASE WHEN EXISTS (SELECT 1 FROM public.notifications n WHERE n.type = 'peer_review_requested' AND n.source_id = a.id AND n.recipient_id = v_caller_id) THEN 'invited' ELSE 'not_invited' END
          ),
          'my_eval_score', (SELECT e.weighted_subtotal FROM public.selection_evaluations e WHERE e.application_id = a.id AND e.evaluator_id = v_caller_id AND e.submitted_at IS NOT NULL LIMIT 1)
        )
        -- #2393 fatia 3: a trilha de avaliação da vaga. Num || próprio, antes da chave da vaga, que fecha o objeto.
        || jsonb_build_object('evaluation_track', CASE WHEN public._na_avaliacao_geral(a.id) THEN 'general' ELSE 'line_pilot' END)
        -- #2393: a vaga do VEP da candidatura. Por `||` porque o objeto acima esta perto do teto de
        -- 100 argumentos do jsonb_build_object. So o id: o titulo fica com a RLS da vep_opportunities.
        || jsonb_build_object('vep_opportunity_id', a.vep_opportunity_id)
      ORDER BY COALESCE(a.leader_score, a.research_score, a.final_score) DESC NULLS LAST)
      FROM (
        SELECT
          sa.*,
          ROW_NUMBER() OVER (
            PARTITION BY sa.role_applied, public._na_avaliacao_geral(sa.id)  -- #2393 fatia 3: o piloto não divide posição com a avaliação geral
            ORDER BY sa.objective_score_avg DESC NULLS LAST, sa.id ASC
          )::int AS objective_rank
        FROM public.selection_applications sa
        WHERE sa.cycle_id = v_cycle_id
          AND (v_ve_piloto OR public._na_avaliacao_geral(sa.id))  -- #2393 fatia 3
      ) a
    ), '[]'::jsonb),
    'stats', v_stats_a || v_stats_b
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

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
    AND public._na_avaliacao_geral(sa.id)  -- #2393 fatia 3: piloto da linha fora da fila geral
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
    AND public._na_avaliacao_geral(sa.id)  -- #2393 fatia 3
    AND sa.status <> ALL (v_terminal)
    AND se.evaluator_id = v_caller_member_id
    AND se.submitted_at IS NOT NULL;

  -- Total = apps avaliáveis do ciclo (denominador alinhado com a fila).
  SELECT count(*) INTO v_total_count
  FROM public.selection_applications
  WHERE cycle_id = v_cycle.id
    AND public._na_avaliacao_geral(id)  -- #2393 fatia 3
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

CREATE OR REPLACE FUNCTION public.get_my_committee_assignments()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_committee_cycles uuid[];
  v_assignments jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;

  -- Cycles where caller is in committee
  SELECT array_agg(DISTINCT cycle_id) INTO v_committee_cycles
  FROM public.selection_committee
  WHERE member_id = v_caller_id;

  IF v_committee_cycles IS NULL OR array_length(v_committee_cycles, 1) IS NULL THEN
    RETURN jsonb_build_object(
      'is_committee_member', false,
      'assignments', '[]'::jsonb,
      'count', 0
    );
  END IF;

  -- Applications in those cycles + caller's evaluation status per app
  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.created_at DESC), '[]'::jsonb) INTO v_assignments
  FROM (
    SELECT
      a.id AS application_id,
      a.cycle_id,
      sc.cycle_code,
      sc.phase AS cycle_phase,
      a.applicant_name,
      a.role_applied,
      a.promotion_path,
      a.status,
      a.created_at,
      -- Caller's own evaluation status on this app
      EXISTS (
        SELECT 1 FROM public.selection_evaluations e
        WHERE e.application_id = a.id
          AND e.evaluator_id = v_caller_id
          AND e.submitted_at IS NOT NULL
      ) AS i_have_submitted,
      (
        SELECT count(*)::int FROM public.selection_evaluations e
        WHERE e.application_id = a.id
          AND e.evaluator_id = v_caller_id
      ) AS my_evaluation_rows,
      sc.min_evaluators
    FROM public.selection_applications a
    JOIN public.selection_cycles sc ON sc.id = a.cycle_id
    WHERE a.cycle_id = ANY(v_committee_cycles)
      AND a.status NOT IN ('withdrawn','cancelled')
      AND public._na_avaliacao_geral(a.id)  -- #2393 fatia 3: piloto da linha fora da avaliação geral
  ) r;

  RETURN jsonb_build_object(
    'is_committee_member', true,
    'cycle_ids', to_jsonb(v_committee_cycles),
    'assignments', v_assignments,
    'count', jsonb_array_length(v_assignments)
  );
END; $function$;

CREATE OR REPLACE FUNCTION public.get_evaluation_form(p_application_id uuid, p_evaluation_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_cycle record;
  v_committee record;
  v_draft record;
  v_criteria jsonb;
  v_criteria_enriched jsonb;
  v_max_weighted numeric := 0;
  v_returning_match record;
  v_app_core jsonb;
  v_app_body jsonb;
  v_app_profile jsonb;
  v_app_pmi_history jsonb;
  v_app_returning jsonb;
  v_app_ai jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Unauthorized: member not found'; END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN RAISE EXCEPTION 'Application not found: %', p_application_id; END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  SELECT * INTO v_committee FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: not a committee member';
  END IF;

  -- #2393 fatia 3 (D1): candidatura de vaga piloto da linha não passa pela avaliação geral.
  IF NOT public._na_avaliacao_geral(p_application_id) THEN
    RAISE EXCEPTION 'Unauthorized: pilot_track application is not evaluated through the general committee (ADR-0134)'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  PERFORM public._log_application_pii_access(
    p_application_id, v_caller.id,
    ARRAY[
      'email','applicant_name','linkedin_url','resume_url','resume_storage_path','cv_extracted_text',
      'motivation_letter','leadership_experience','academic_background','reason_for_applying',
      'profile_about_me','profile_specialties','profile_company','profile_designation',
      'profile_industry','profile_certifications','profile_linkedin_url',
      'service_history_chapters','pmi_memberships','previous_cycles','linkedin_relevant_posts'
    ],
    'get_evaluation_form:' || p_evaluation_type
  );

  v_criteria := CASE p_evaluation_type
    WHEN 'objective' THEN v_cycle.objective_criteria
    WHEN 'interview' THEN v_cycle.interview_criteria
    WHEN 'leader_extra' THEN v_cycle.leader_extra_criteria
    ELSE '[]'::jsonb
  END;

  SELECT * INTO v_draft FROM public.selection_evaluations
  WHERE application_id = p_application_id
    AND evaluator_id = v_caller.id
    AND evaluation_type = p_evaluation_type;

  SELECT jsonb_agg(
    jsonb_build_object(
      'key', c->>'key', 'label', c->>'label', 'guide', c->>'guide',
      'weight', COALESCE((c->>'weight')::numeric, 1),
      'max', COALESCE((c->>'max')::numeric, 10),
      'max_weighted_contribution', COALESCE((c->>'weight')::numeric, 1) * COALESCE((c->>'max')::numeric, 10),
      'your_score', CASE WHEN v_draft.scores IS NOT NULL AND v_draft.scores ? (c->>'key')
                          THEN (v_draft.scores->>(c->>'key'))::numeric ELSE NULL END,
      'your_weighted_contribution', CASE WHEN v_draft.scores IS NOT NULL AND v_draft.scores ? (c->>'key')
                                          THEN COALESCE((c->>'weight')::numeric, 1) * (v_draft.scores->>(c->>'key'))::numeric ELSE NULL END,
      'your_criterion_note', CASE WHEN v_draft.criterion_notes IS NOT NULL AND v_draft.criterion_notes ? (c->>'key')
                                   THEN v_draft.criterion_notes->>(c->>'key') ELSE NULL END
    )
  ) INTO v_criteria_enriched
  FROM jsonb_array_elements(v_criteria) c;

  SELECT SUM(COALESCE((c->>'weight')::numeric, 1) * COALESCE((c->>'max')::numeric, 10))
  INTO v_max_weighted
  FROM jsonb_array_elements(v_criteria) c;

  SELECT id, name, member_status, operational_role, offboarded_at
  INTO v_returning_match
  FROM public.members WHERE lower(email) = lower(v_app.email) LIMIT 1;

  -- Build application object in chunks (PG jsonb_build_object 100-arg cap workaround)
  v_app_core := jsonb_build_object(
    'id', v_app.id,
    'applicant_name', v_app.applicant_name,
    'email', v_app.email,
    'chapter', v_app.chapter,
    'role_applied', v_app.role_applied,
    'promotion_path', v_app.promotion_path,
    'certifications', v_app.certifications,
    'linkedin_url', v_app.linkedin_url,
    'resume_url', v_app.resume_url,
    'resume_storage_path', v_app.resume_storage_path,
    'resume_synced_at', v_app.resume_synced_at,
    'cv_extracted_text', v_app.cv_extracted_text,
    'membership_status', v_app.membership_status,
    'status', v_app.status,
    'credly_url', v_app.credly_url,
    'is_open_to_volunteer', v_app.is_open_to_volunteer
  );

  v_app_body := jsonb_build_object(
    'motivation_letter', v_app.motivation_letter,
    'reason_for_applying', v_app.reason_for_applying,
    'chapter_affiliation', v_app.chapter_affiliation,
    'non_pmi_experience', v_app.non_pmi_experience,
    'areas_of_interest', v_app.areas_of_interest,
    'availability_declared', v_app.availability_declared,
    'proposed_theme', v_app.proposed_theme,
    'leadership_experience', v_app.leadership_experience,
    'academic_background', v_app.academic_background
  );

  v_app_profile := jsonb_build_object(
    'profile_about_me', v_app.profile_about_me,
    'profile_specialties', v_app.profile_specialties,
    'profile_company', v_app.profile_company,
    'profile_designation', v_app.profile_designation,
    'profile_industry', v_app.profile_industry,
    'profile_certifications', v_app.profile_certifications,
    'profile_volunteer_interest', v_app.profile_volunteer_interest,
    'profile_location', v_app.profile_location,
    'profile_state', v_app.profile_state,
    'profile_country', v_app.profile_country,
    'profile_linkedin_url', v_app.profile_linkedin_url,
    'linkedin_relevant_posts', v_app.linkedin_relevant_posts,
    'ai_pm_focus_tags', v_app.ai_pm_focus_tags
  );

  v_app_pmi_history := jsonb_build_object(
    'service_history_count', v_app.service_history_count,
    'service_history_chapters', v_app.service_history_chapters,
    'service_first_start_date', v_app.service_first_start_date,
    'service_latest_end_date', v_app.service_latest_end_date,
    'pmi_memberships', v_app.pmi_memberships
  );

  v_app_returning := jsonb_build_object(
    'is_returning_member', v_app.is_returning_member,
    'previous_cycles', v_app.previous_cycles,
    'application_count', v_app.application_count,
    'returning_member_match', CASE WHEN v_returning_match.id IS NOT NULL THEN jsonb_build_object(
      'member_id', v_returning_match.id,
      'name', v_returning_match.name,
      'member_status', v_returning_match.member_status,
      'operational_role', v_returning_match.operational_role,
      'offboarded_at', v_returning_match.offboarded_at
    ) ELSE NULL END
  );

  v_app_ai := jsonb_build_object(
    'consent_ai_analysis_at', v_app.consent_ai_analysis_at,
    'ai_analysis', v_app.ai_analysis,
    'ai_triage_score', v_app.ai_triage_score,
    'ai_triage_reasoning', v_app.ai_triage_reasoning,
    'ai_triage_confidence', v_app.ai_triage_confidence,
    'ai_triage_at', v_app.ai_triage_at,
    'ai_triage_model', v_app.ai_triage_model,
    'last_briefing_jsonb', v_app.last_briefing_jsonb,
    'last_briefing_at', v_app.last_briefing_at,
    'last_briefing_model', v_app.last_briefing_model
  );

  RETURN jsonb_build_object(
    'application', v_app_core || v_app_body || v_app_profile || v_app_pmi_history || v_app_returning || v_app_ai,
    'criteria', v_criteria,
    'criteria_with_weights', COALESCE(v_criteria_enriched, '[]'::jsonb),
    'max_weighted_subtotal', v_max_weighted,
    'pert_cutoff', jsonb_build_object(
      'target_score', v_app.pert_target_score,
      'band_lower', v_app.pert_band_lower,
      'band_upper', v_app.pert_band_upper,
      'cohort_n', v_app.pert_cohort_n,
      'method', v_app.pert_cutoff_method,
      'calc_at', v_app.pert_calc_at
    ),
    'evaluation_type', p_evaluation_type,
    'committee_role', COALESCE(v_committee.role, 'platform_admin'),
    'draft', CASE WHEN v_draft IS NOT NULL THEN jsonb_build_object(
      'id', v_draft.id, 'scores', v_draft.scores, 'notes', v_draft.notes,
      'criterion_notes', COALESCE(v_draft.criterion_notes, '{}'::jsonb),
      'weighted_subtotal', v_draft.weighted_subtotal, 'submitted_at', v_draft.submitted_at
    ) ELSE NULL END,
    'is_locked', CASE WHEN v_draft.submitted_at IS NOT NULL THEN true ELSE false END
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.submit_evaluation(p_application_id uuid, p_evaluation_type text, p_scores jsonb, p_notes text DEFAULT NULL::text, p_criterion_notes jsonb DEFAULT NULL::jsonb, p_ai_suggestion_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_cycle record;
  v_committee record;
  v_criteria jsonb;
  v_criterion jsonb;
  v_key text;
  v_score numeric;
  v_weight numeric;
  v_max numeric;
  v_weighted_sum numeric := 0;
  v_eval_id uuid;
  v_total_evaluators int;
  v_submitted_count int;
  v_all_subtotals numeric[];
  v_pert_score numeric;
  v_min_sub numeric;
  v_max_sub numeric;
  v_avg_sub numeric;
  v_cutoff numeric;
  v_median numeric;
  v_new_status text;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Unauthorized: member not found'; END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN RAISE EXCEPTION 'Application not found'; END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  SELECT * INTO v_committee FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;
  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: not a committee member';
  END IF;

  -- #1591 — OBSERVADOR OBSERVA, nao avalia.
  -- Ate aqui estar no comite bastava: nem esta funcao nem `get_my_pending_evaluations` olhavam o
  -- `role`. Na pratica os 4 observadores do ciclo vivo nunca submeteram (455 avaliacoes, TODAS de
  -- `evaluator`), entao o comportamento estava certo por HABITO das pessoas, nao por trava. Uma
  -- capacidade que so nao e exercida por costume nao e uma regra.
  -- Decisao do PM (07/08/2026): peer review aberto a todo o comite, EXCETO observadores.
  -- O escape de `manage_platform` continua, para nao mudar a autoridade de quem administra.
  IF v_committee.role = 'observer'
     AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: observer role does not evaluate'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- #2393 fatia 3 (D1): candidatura de vaga piloto da linha não passa pela avaliação geral.
  IF NOT public._na_avaliacao_geral(p_application_id) THEN
    RAISE EXCEPTION 'Unauthorized: pilot_track application is not evaluated through the general committee (ADR-0134)'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.selection_evaluations
    WHERE application_id = p_application_id
      AND evaluator_id = v_caller.id
      AND evaluation_type = p_evaluation_type
      AND submitted_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Evaluation already submitted and locked';
  END IF;

  v_criteria := CASE p_evaluation_type
    WHEN 'objective' THEN v_cycle.objective_criteria
    WHEN 'interview' THEN v_cycle.interview_criteria
    WHEN 'leader_extra' THEN v_cycle.leader_extra_criteria
    ELSE '[]'::jsonb
  END;

  FOR v_criterion IN SELECT * FROM jsonb_array_elements(v_criteria)
  LOOP
    v_key := v_criterion ->> 'key';
    v_weight := COALESCE((v_criterion ->> 'weight')::numeric, 1);
    v_max := COALESCE((v_criterion ->> 'max')::numeric, 10);
    IF NOT (p_scores ? v_key) THEN RAISE EXCEPTION 'Missing score for criterion: %', v_key; END IF;
    v_score := (p_scores ->> v_key)::numeric;
    IF v_score IS NULL THEN RAISE EXCEPTION 'Score for % must be numeric', v_key; END IF;
    IF v_score < 0 OR v_score > v_max THEN
      RAISE EXCEPTION 'Score % for criterion "%" must be between 0 and % (schema max)', v_score, v_key, v_max;
    END IF;
    v_weighted_sum := v_weighted_sum + (v_weight * v_score);
  END LOOP;

  INSERT INTO public.selection_evaluations (
    application_id, evaluator_id, evaluation_type,
    scores, weighted_subtotal, notes, criterion_notes, submitted_at
  ) VALUES (
    p_application_id, v_caller.id, p_evaluation_type,
    p_scores, ROUND(v_weighted_sum, 2), p_notes,
    COALESCE(p_criterion_notes, '{}'::jsonb), now()
  )
  ON CONFLICT (application_id, evaluator_id, evaluation_type)
  DO UPDATE SET
    scores = EXCLUDED.scores,
    weighted_subtotal = EXCLUDED.weighted_subtotal,
    notes = EXCLUDED.notes,
    criterion_notes = EXCLUDED.criterion_notes,
    submitted_at = now()
  RETURNING id INTO v_eval_id;

  SELECT COUNT(*) INTO v_total_evaluators FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND role IN ('evaluator', 'lead');

  SELECT COUNT(*) INTO v_submitted_count FROM public.selection_evaluations
  WHERE application_id = p_application_id AND evaluation_type = p_evaluation_type AND submitted_at IS NOT NULL;

  IF v_submitted_count >= v_cycle.min_evaluators THEN
    SELECT ARRAY_AGG(weighted_subtotal ORDER BY weighted_subtotal) INTO v_all_subtotals
    FROM public.selection_evaluations
    WHERE application_id = p_application_id AND evaluation_type = p_evaluation_type AND submitted_at IS NOT NULL;

    v_min_sub := v_all_subtotals[1];
    v_max_sub := v_all_subtotals[array_upper(v_all_subtotals, 1)];
    SELECT AVG(unnest) INTO v_avg_sub FROM unnest(v_all_subtotals);
    v_pert_score := ROUND((2 * v_min_sub + 4 * v_avg_sub + 2 * v_max_sub) / 8, 2);

    IF p_evaluation_type = 'objective' THEN
      UPDATE public.selection_applications SET objective_score_avg = v_pert_score, updated_at = now() WHERE id = p_application_id;
      SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY objective_score_avg) INTO v_median
      FROM public.selection_applications WHERE cycle_id = v_app.cycle_id AND objective_score_avg IS NOT NULL;
      v_cutoff := ROUND(COALESCE(v_median, 0) * 0.75, 2);
      IF v_pert_score < v_cutoff AND v_cutoff > 0 THEN v_new_status := 'objective_cutoff'; ELSE v_new_status := 'interview_pending'; END IF;
      UPDATE public.selection_applications SET status = v_new_status, updated_at = now()
      WHERE id = p_application_id AND status IN ('submitted', 'screening', 'objective_eval');
    ELSIF p_evaluation_type = 'interview' THEN
      UPDATE public.selection_applications
        SET interview_score = v_pert_score,
            status = 'final_eval',
            updated_at = now()
      WHERE id = p_application_id;
      PERFORM public.compute_application_scores(p_application_id);
    ELSIF p_evaluation_type = 'leader_extra' THEN
      UPDATE public.selection_applications
        SET leader_extra_pert_score = v_pert_score,
            updated_at = now()
      WHERE id = p_application_id;
      PERFORM public.compute_application_scores(p_application_id);
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'evaluation_id', v_eval_id, 'weighted_subtotal', ROUND(v_weighted_sum, 2),
    'all_submitted', v_submitted_count >= v_cycle.min_evaluators,
    'pert_score', v_pert_score, 'new_status', v_new_status
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
