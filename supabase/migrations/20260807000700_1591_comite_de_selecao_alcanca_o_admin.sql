-- #1591 — o comitê de seleção não alcançava a tela que ele opera.
--
-- O DIAGNÓSTICO: TRÊS CAMADAS, TRÊS VOCABULÁRIOS
-- Medido em 07/08/2026 sobre um avaliador real do ciclo aberto:
--
--   camada          linguagem                                   ele passa?
--   domínio         selection_committee.role = 'evaluator'         SIM
--   menu (nav)      designations + minTier                         não (designations vazio)
--   dados (RPC)     can() -> view_internal_analytics               não
--
-- Ou seja: a plataforma SABE que a pessoa é do comitê e não deixa nem o menu aparecer nem a RPC
-- responder. É a mesma família do #1590 ("o menu e o servidor falam línguas diferentes"), com o
-- sinal invertido: lá 56 de 89 viam o que não podiam; aqui quem pode não vê.
--
-- ⚠️ POR QUE MENU E DADOS ANDAM JUNTOS NESTA MIGRATION
-- Dar só a entrada de menu seria PIOR que não fazer nada: a página carregaria e a RPC devolveria
-- `Unauthorized`, o que lê como bug para o usuário e como acesso concedido para quem audita.
--
-- POR QUE NÃO A SAÍDA FÁCIL
-- Havia duas tentações, ambas recusadas:
--   1. `allowedOperationalRoles: ['tribe_leader']` no nav — abriria a rota `lgpdSensitive` para
--      TODO tribe_leader, e é exatamente o que o `route-acl.test.mjs` barra. O comitê tem 7
--      pessoas; tribe_leader tem muitas mais, e a tela expõe PII de candidato.
--   2. Semear `view_internal_analytics` para o comitê em `engagement_kind_permissions` — é o
--      anti-padrão "seed expansion como atalho" que `.claude/rules/database.md` proíbe: a action
--      vale para a organização inteira e vazaria muito além desta tela.
--
-- A saída correta é um QUARTO EIXO, derivado do domínio: `is_selection_committee_member()`.
-- Não é coluna espelho mantida à mão — espelho envelhece e passa a conceder o que já acabou.
--
-- ESCOPO DE CICLO, QUE É A PARTE QUE SE ERRA CALADO
-- A porta de `get_selection_dashboard` roda ANTES de o ciclo ser resolvido, então ela pergunta
-- "é de algum comitê vivo?". Sozinho isso deixaria um membro do comitê do ciclo atual LER o PII
-- de candidato de todos os ciclos passados. Por isso a segunda checagem, depois de `v_cycle_id`
-- resolvido: quem entrou PELO comitê só lê o ciclo em que está no comitê. Conferido:
-- o predicado devolve `false` para o mesmo avaliador num ciclo que não é dele.
--
-- A recusa por conflito de interesse (ADR-0109) continua onde estava, e continua valendo primeiro
-- para candidato do próprio ciclo.
--
-- COMO ESTE ARQUIVO FOI PRODUZIDO
-- Os corpos abaixo são o `prosrc` VIVO, extraído do banco e escrito em disco por script, não
-- transcrito. A alteração foi aplicada por substituição ancorada (`replace`) com `RAISE` se
-- qualquer âncora não casasse, sobre `pg_get_functiondef`, justamente para não reescrever 19 KB
-- de função à mão. O que está aqui é byte-igual ao que roda.
--
-- Refs #1591, #1590, ADR-0109

-- ─────────────────────────────────────────────────────────────────────────────
-- O quarto eixo, como predicado reutilizável.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.is_selection_committee_member(
  p_member_id uuid,
  p_cycle_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.selection_committee sc
    JOIN public.selection_cycles c ON c.id = sc.cycle_id
    WHERE sc.member_id = p_member_id
      AND (
        (p_cycle_id IS NOT NULL AND sc.cycle_id = p_cycle_id)
        OR
        (p_cycle_id IS NULL AND (c.status = 'open' OR c.phase = 'evaluating'))
      )
  );
$function$;

COMMENT ON FUNCTION public.is_selection_committee_member(uuid, uuid) IS
  '#1591 — quarto eixo de autoridade: participacao no comite de selecao. Com p_cycle_id, pergunta '
  'sobre AQUELE ciclo; sem ele, sobre qualquer ciclo vivo (open ou evaluating). Existe porque o '
  'dominio sabe quem e do comite (selection_committee.role) e nem o menu nem as RPCs de dashboard '
  'falavam essa lingua: gateavam por designations e por view_internal_analytics, que um avaliador '
  'nao tem. NAO concede escrita: e predicado de LEITURA.';

-- `FROM PUBLIC` sozinho não fecha nada: `anon` e `authenticated` têm GRANT próprio herdado do
-- schema. Os três precisam sair, e só `service_role` entra — os chamadores são SECDEF.
REVOKE ALL ON FUNCTION public.is_selection_committee_member(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_selection_committee_member(uuid, uuid) TO service_role;

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
          'created_at', a.created_at, 'interview_status', a.interview_status,
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
      ORDER BY COALESCE(a.leader_score, a.research_score, a.final_score) DESC NULLS LAST)
      FROM (
        SELECT
          sa.*,
          ROW_NUMBER() OVER (
            PARTITION BY sa.role_applied
            ORDER BY sa.objective_score_avg DESC NULLS LAST, sa.id ASC
          )::int AS objective_rank
        FROM public.selection_applications sa
        WHERE sa.cycle_id = v_cycle_id
      ) a
    ), '[]'::jsonb),
    'stats', v_stats_a || v_stats_b
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_member_by_auth()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_email text;
  v_member_id uuid;
  v_existing_auth_id uuid;
  v_result json;
BEGIN
  IF v_uid IS NULL THEN
    RETURN NULL;
  END IF;

  -- Step 1: direct match on members.auth_id (the common case)
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = v_uid LIMIT 1;

  -- Step 2: match on secondary_auth_ids (admin-pre-approved alternates -> safe to rotate)
  IF v_member_id IS NULL THEN
    SELECT id INTO v_member_id
      FROM public.members
     WHERE v_uid = ANY(COALESCE(secondary_auth_ids, '{}'))
     LIMIT 1;

    IF v_member_id IS NOT NULL THEN
      SELECT auth_id INTO v_existing_auth_id FROM public.members WHERE id = v_member_id;

      UPDATE public.members
         SET auth_id            = v_uid,
             secondary_auth_ids = array_append(
                                    array_remove(COALESCE(secondary_auth_ids, '{}'::uuid[]), v_uid),
                                    v_existing_auth_id
                                  ),
             updated_at         = now()
       WHERE id = v_member_id;

      -- p177 D=1 fix: sync persons.auth_id to the new primary (mirror try_auto_link_ghost).
      UPDATE public.persons
         SET auth_id = v_uid
       WHERE legacy_member_id = v_member_id
         AND (auth_id IS NULL OR auth_id <> v_uid);

      INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, changes, metadata)
      VALUES (
        v_member_id,
        'members.auth_id.rotated_secondary_to_primary',
        'member',
        v_member_id,
        jsonb_build_object(
          'promoted_auth_id', v_uid,
          'demoted_auth_id', v_existing_auth_id
        ),
        jsonb_build_object('via', 'get_member_by_auth.step2_secondary_auth_ids_match')
      );
    END IF;
  END IF;

  -- Step 3: PRIMARY email first-link (only when auth_id IS NULL -- genuine ghost first login).
  -- P168 R3-a: dropped the (a) secondary_emails match branch and (b) replace-existing-auth_id
  -- branch. Both were the mechanism behind Paulo Alves identity hijack.
  IF v_member_id IS NULL THEN
    SELECT lower(email) INTO v_email FROM auth.users WHERE id = v_uid;

    IF v_email IS NOT NULL THEN
      SELECT id INTO v_member_id
        FROM public.members
       WHERE lower(email) = v_email
         AND auth_id IS NULL
       LIMIT 1;

      IF v_member_id IS NOT NULL THEN
        UPDATE public.members
           SET auth_id    = v_uid,
               updated_at = now()
         WHERE id = v_member_id;

        -- p177 D=1 fix: sync persons.auth_id on first-link (mirror try_auto_link_ghost).
        UPDATE public.persons
           SET auth_id = v_uid
         WHERE legacy_member_id = v_member_id
           AND (auth_id IS NULL OR auth_id <> v_uid);

        INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, changes, metadata)
        VALUES (
          v_member_id,
          'members.auth_id.first_link',
          'member',
          v_member_id,
          jsonb_build_object(
            'linked_auth_id', v_uid,
            'matched_via',    'primary_email',
            'matched_email',  v_email
          ),
          jsonb_build_object('via', 'get_member_by_auth.step3_primary_email_when_null')
        );
      END IF;
    END IF;
  END IF;

  IF v_member_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Return JSON shape -- adds allow_precise_location_in_public_map (Cycle4 PD-MAP unified opt-in); rest UNCHANGED.
  SELECT row_to_json(q) INTO v_result FROM (
    SELECT m.id, m.name, m.email, m.secondary_emails,
      m.pmi_id, m.phone, m.operational_role, m.designations,
      compute_legacy_role(m.operational_role, m.designations)  AS role,
      compute_legacy_roles(m.operational_role, m.designations) AS roles,
      m.chapter, m.tribe_id, m.current_cycle_active, m.is_superadmin, m.is_active,
      m.member_status, m.state, m.country, m.share_whatsapp, m.signature_url,
      m.address, m.city, m.birth_date,
      m.share_address, m.share_birth_date, m.allow_state_in_public_map, m.allow_precise_location_in_public_map,
      m.privacy_consent_accepted_at, m.privacy_consent_version, m.data_last_reviewed_at,
      m.inactivated_at, m.inactivation_reason,
      m.photo_url, m.linkedin_url, m.auth_id,
      m.credly_url, m.credly_badges, m.cpmai_certified,
      m.created_at, m.updated_at,
      -- #1591: o quarto eixo de autoridade que o nav nao tinha. E DERIVADO do dominio
      -- (selection_committee x ciclo vivo), nunca uma coluna espelho mantida a mao — espelho
      -- envelhece e passa a conceder o que ja acabou.
      public.is_selection_committee_member(m.id) AS selection_committee_active
    FROM public.members m
    WHERE m.id = v_member_id
  ) q;

  RETURN v_result;
END;
$function$;
