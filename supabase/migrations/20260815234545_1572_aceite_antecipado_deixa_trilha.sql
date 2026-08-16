-- #1572 — aprovar sem nenhuma avaliação registrada é estado VÁLIDO, mas deixa de ser INDISTINGUÍVEL
-- de uma aprovação com lastro.
--
-- Levantado em 03/08/2026: duas candidaturas do cycle4-2026 estavam `approved` com zero avaliação,
-- `objective_score_avg` e `final_score` nulos, e os membros já onboardados. O ciclo se chama "Aceite
-- Antecipado", então o bypass é intencional por desenho — o problema é que não havia registro de
-- QUEM aprovou nem COM BASE EM QUÊ. Decisão do PM (15/08): manter o estado válido e exigir
-- justificativa, em vez de gatear por `min_evaluators`.
--
-- Medido em 15/08 antes desta migration:
--   decididas (approved/rejected) com ZERO avaliação: 15
--     cycle2-2025    6 approved + 2 rejected  — nenhuma trilha em log nenhum
--     cycle3-2026    3 approved + 3 rejected
--     cycle4-2026                1 rejected
--   `selection_cycles.min_evaluators` = 2 nos 4 ciclos, e nada o consultava no momento da decisão.
--
-- Escopo deliberado: o portão de escrita cobre APROVAÇÃO (é o que o conceito de aceite antecipado
-- descreve). Rejeição sem avaliação é contada e exposta, mas não bloqueada — a decisão de estendê-la
-- é do PM e mudaria o que o GP experimenta no meio de um ciclo aberto.

-- ── 1. A candidatura passa a carregar o próprio aceite antecipado ─────────────────────────────────
-- Sem booleano espelho: `early_acceptance_at IS NOT NULL` É a flag. Um booleano ao lado do carimbo
-- é uma segunda fonte da mesma verdade, e as duas derivam.

ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS early_acceptance_at     timestamptz,
  ADD COLUMN IF NOT EXISTS early_acceptance_by     uuid,
  ADD COLUMN IF NOT EXISTS early_acceptance_reason text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.selection_applications'::regclass
      AND conname  = 'selection_applications_early_acceptance_by_fkey'
  ) THEN
    ALTER TABLE public.selection_applications
      ADD CONSTRAINT selection_applications_early_acceptance_by_fkey
      FOREIGN KEY (early_acceptance_by) REFERENCES public.members(id) ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.selection_applications'::regclass
      AND conname  = 'selection_applications_early_acceptance_complete'
  ) THEN
    -- O carimbo nunca existe sozinho: quem carimbou e por quê entram na mesma transação, senão a
    -- coluna vira mais um registro que diz que houve decisão sem dizer nada sobre ela.
    ALTER TABLE public.selection_applications
      ADD CONSTRAINT selection_applications_early_acceptance_complete
      CHECK (
        early_acceptance_at IS NULL
        OR (early_acceptance_by IS NOT NULL AND length(btrim(coalesce(early_acceptance_reason, ''))) >= 20)
      );
  END IF;
END $$;

COMMENT ON COLUMN public.selection_applications.early_acceptance_at IS
  '#1572 — carimbo do aceite antecipado (aprovação com ZERO avaliação submetida). NULL = não houve. Esta coluna É a flag; não existe booleano espelho.';
COMMENT ON COLUMN public.selection_applications.early_acceptance_by IS
  '#1572 — members.id de quem aprovou sem lastro avaliativo.';
COMMENT ON COLUMN public.selection_applications.early_acceptance_reason IS
  '#1572 — justificativa obrigatória (>= 20 caracteres) do aceite antecipado.';

-- ── 2. admin_update_application — o caminho de decisão de UMA candidatura ─────────────────────────
-- É também o caminho do `admin_decide_dual_track`, que delega as duas pontas do par para cá.

CREATE OR REPLACE FUNCTION public.admin_update_application(p_application_id uuid, p_data jsonb)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_caller_id        uuid;
  v_caller_name      text;
  v_app              record;
  v_old_status       text;
  v_new_status       text;
  v_requested_status text;
  v_gate_suppressed  boolean := false;
  v_canonical_result jsonb := NULL;
  v_member_id        uuid := NULL;
  v_seeded_count     int := 0;
  v_promoted         boolean := false;
  v_target_role      text;
  v_eval_count       int := NULL;
  v_early_reason     text := NULL;
BEGIN
  SELECT id, name INTO v_caller_id, v_caller_name FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN json_build_object('error', 'Unauthorized'); END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN json_build_object('error', 'Unauthorized');
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF NOT FOUND THEN RETURN json_build_object('error', 'Application not found'); END IF;

  v_old_status       := v_app.status;
  v_requested_status := coalesce(p_data->>'status', v_old_status);
  v_new_status       := v_requested_status;

  -- #1572 — aprovar sem NENHUMA avaliação submetida continua permitido (é o Aceite Antecipado), mas
  -- passa a exigir justificativa. A recusa acontece ANTES do UPDATE: uma aprovação sem lastro que
  -- gravasse status e só depois falhasse deixaria a candidatura aprovada sem o carimbo que a explica.
  IF v_requested_status = 'approved' AND v_old_status <> 'approved' THEN
    SELECT count(*) INTO v_eval_count
    FROM public.selection_evaluations e
    WHERE e.application_id = p_application_id;

    IF v_eval_count = 0 THEN
      v_early_reason := btrim(coalesce(p_data->>'early_acceptance_reason', ''));
      IF length(v_early_reason) < 20 THEN
        RETURN json_build_object(
          'error',   'Aprovação sem nenhuma avaliação registrada exige justificativa de pelo menos 20 caracteres em early_acceptance_reason (Aceite Antecipado).',
          'code',    'early_acceptance_reason_required',
          'evaluations_submitted', v_eval_count
        );
      END IF;
    END IF;
  END IF;

  UPDATE public.selection_applications SET
    status            = v_requested_status,
    feedback          = coalesce(p_data->>'feedback', feedback),
    tags              = CASE WHEN p_data ? 'tags'              THEN ARRAY(SELECT jsonb_array_elements_text(p_data->'tags')) ELSE tags END,
    role_applied      = coalesce(p_data->>'role_applied', role_applied),
    converted_from    = CASE WHEN p_data ? 'converted_from'    THEN p_data->>'converted_from'    ELSE converted_from END,
    converted_to      = CASE WHEN p_data ? 'converted_to'      THEN p_data->>'converted_to'      ELSE converted_to END,
    conversion_reason = CASE WHEN p_data ? 'conversion_reason' THEN p_data->>'conversion_reason' ELSE conversion_reason END,
    updated_at        = now()
  WHERE id = p_application_id
  RETURNING status INTO v_new_status;

  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Application not found');
  END IF;

  -- #1613 — o gate de entrada pode suprimir `* → interview_scheduled` quando não há nota
  -- objetiva e não há override do R1.4. Devolver o status PEDIDO como se tivesse sido
  -- gravado era a forma exata de recusa-lida-como-sucesso. Este RPC é o caminho de exceção
  -- de FATO do GP, mas a exceção passa a exigir `grant_interview_stage_override` — com
  -- motivo — em vez de acontecer por acidente aqui.
  v_gate_suppressed := (v_new_status IS DISTINCT FROM v_requested_status);

  IF v_new_status = 'approved' AND v_old_status <> 'approved' THEN
    -- #1572 — o carimbo entra DEPOIS do UPDATE, e só quando o `approved` realmente pegou: se o gate
    -- do #1613 suprimir o status, não houve aceite antecipado para registrar.
    IF v_early_reason IS NOT NULL THEN
      UPDATE public.selection_applications SET
        early_acceptance_at     = now(),
        early_acceptance_by     = v_caller_id,
        early_acceptance_reason = v_early_reason
      WHERE id = p_application_id;
    END IF;

    -- #1175 D2: partner-chapter tag semantics centralized (no_partner_chapter /
    -- partner_chapter_at_risk) — see apply_partner_chapter_tags.
    PERFORM public.apply_partner_chapter_tags(p_application_id);

    v_canonical_result := public.approve_selection_application(p_application_id, p_data);

    -- Council fix: RAISE so the entire transaction rolls back if canonical fails
    -- (otherwise the UPDATE status='approved' above commits without member/person/
    -- engagement, creating an invariant-R violation).
    IF (v_canonical_result->>'success') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Canonical approval failed: %', coalesce(v_canonical_result->>'error', 'unknown')
        USING ERRCODE = 'P0001',
              DETAIL = v_canonical_result::text;
    END IF;

    v_member_id      := (v_canonical_result->>'member_id')::uuid;
    v_seeded_count   := coalesce((v_canonical_result->>'onboarding_seeded')::int, 0);
    v_promoted       := coalesce((v_canonical_result->>'role_promoted')::boolean, false);
    v_target_role    := v_canonical_result->>'promoted_to';
  END IF;

  INSERT INTO public.data_anomaly_log (anomaly_type, severity, description, context)
  VALUES (
    'selection_status_change',
    'info',
    'Application ' || v_app.applicant_name || ': ' || v_old_status || ' → ' || v_new_status
      || CASE WHEN v_gate_suppressed THEN ' (pedido: ' || v_requested_status || ' — suprimido pelo gate #1613)' ELSE '' END,
    jsonb_build_object(
      'application_id',    p_application_id,
      'old_status',        v_old_status,
      'new_status',        v_new_status,
      'requested_status',  v_requested_status,
      'gate_suppressed',   v_gate_suppressed,
      'actor',             v_caller_name,
      'actor_id',          v_caller_id,
      'member_id',         v_member_id,
      'onboarding_seeded', v_seeded_count,
      'role_promoted',     v_promoted,
      'promoted_to',       CASE WHEN v_promoted THEN v_target_role ELSE NULL END,
      'canonical_invoked', v_canonical_result IS NOT NULL,
      'evaluations_submitted', v_eval_count,
      'early_acceptance',      v_early_reason IS NOT NULL
    )
  );

  RETURN json_build_object(
    'success',           true,
    'old_status',        v_old_status,
    'new_status',        v_new_status,
    'requested_status',  v_requested_status,
    'gate_suppressed',   v_gate_suppressed,
    'onboarding_seeded', v_seeded_count,
    'role_promoted',     v_promoted,
    'promoted_to',       CASE WHEN v_promoted THEN v_target_role ELSE NULL END,
    'evaluations_submitted', v_eval_count,
    'early_acceptance',      v_early_reason IS NOT NULL,
    'canonical',         v_canonical_result
  );
END;
$function$;

-- ── 3. finalize_decisions — o caminho em LOTE ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.finalize_decisions(p_cycle_id uuid, p_decisions jsonb)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_caller              record;
  v_committee           record;
  v_has_manage_platform boolean;
  v_decision            jsonb;
  v_app_id              uuid;
  v_app                 record;
  v_status              text;
  v_feedback            text;
  v_convert_to          text;
  v_approved_count      int := 0;
  v_rejected_count      int := 0;
  v_waitlisted_count    int := 0;
  v_converted_count     int := 0;
  v_created_members     int := 0;
  v_promoted_count      int := 0;
  v_canonical_result    jsonb;
  v_member_id           uuid;
  v_promoted_this_app   boolean;
  v_target_role         text;
  v_eval_count          int;
  v_early_reason        text;
  v_refused             jsonb := '[]'::jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RETURN json_build_object('error', 'Unauthorized');
  END IF;

  SELECT * INTO v_committee FROM public.selection_committee
  WHERE cycle_id = p_cycle_id AND member_id = v_caller.id AND role = 'lead';

  v_has_manage_platform := public.can_by_member(v_caller.id, 'manage_platform'::text);

  IF v_committee IS NULL AND NOT v_has_manage_platform THEN
    RETURN json_build_object('error', 'Unauthorized: must be committee lead or platform admin');
  END IF;

  -- #906: committee leads may reject / waitlist / convert without manage_platform, but
  -- APPROVING runs the canonical member-creation/promotion path, which requires
  -- manage_platform (ADR-0007). Surface that authority error up front instead of letting
  -- the inner gate roll each approval back silently and returning a success-looking
  -- {approved:0}. A decision with a non-empty convert_to takes the conversion path below
  -- and never calls approve_selection_application, so it is excluded here.
  IF NOT v_has_manage_platform AND EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_decisions) d
    WHERE d->>'decision' = 'approved'
      AND coalesce(d->>'convert_to', '') = ''
  ) THEN
    RETURN json_build_object(
      'error', 'Forbidden: approving an applicant requires platform admin (manage_platform). Committee leads may reject, waitlist, or convert roles.',
      'code', 'approve_requires_manage_platform'
    );
  END IF;

  FOR v_decision IN SELECT * FROM jsonb_array_elements(p_decisions)
  LOOP
    v_app_id            := (v_decision->>'application_id')::uuid;
    v_status            := v_decision->>'decision';
    v_feedback          := v_decision->>'feedback';
    v_convert_to        := v_decision->>'convert_to';
    v_promoted_this_app := false;
    v_target_role       := NULL;
    v_member_id         := NULL;
    v_canonical_result  := NULL;
    v_eval_count        := NULL;
    v_early_reason      := NULL;

    SELECT * INTO v_app FROM public.selection_applications WHERE id = v_app_id AND cycle_id = p_cycle_id;
    IF NOT FOUND THEN CONTINUE; END IF;

    IF v_convert_to IS NOT NULL AND v_convert_to != '' THEN
      UPDATE public.selection_applications SET
        status            = 'converted',
        converted_from    = v_app.role_applied,
        converted_to      = v_convert_to,
        conversion_reason = coalesce(v_feedback, 'Promoted by committee'),
        role_applied      = v_convert_to,
        feedback          = coalesce(v_feedback, feedback),
        updated_at        = now()
      WHERE id = v_app_id;
      v_converted_count := v_converted_count + 1;

      PERFORM public.create_notification(
        m.id, 'selection_conversion_offer',
        'Proposta de conversão de papel',
        'O comitê identificou seu perfil para o papel de ' || v_convert_to || '. Acesse a plataforma para mais detalhes.',
        '/admin/selection', 'selection_application', v_app_id
      ) FROM public.members m WHERE lower(m.email) = lower(v_app.email);

      CONTINUE;
    END IF;

    IF v_status = 'approved' THEN
      -- #1572 — mesma régua do caminho de UMA candidatura. No lote a recusa não aborta as outras
      -- decisões: a candidatura entra em `refused` e o chamador vê o que NÃO foi aplicado, em vez de
      -- ler um `approved` menor do que pediu e não saber quais ficaram de fora.
      SELECT count(*) INTO v_eval_count
      FROM public.selection_evaluations e
      WHERE e.application_id = v_app_id;

      IF v_eval_count = 0 THEN
        v_early_reason := btrim(coalesce(v_decision->>'early_acceptance_reason', ''));
        IF length(v_early_reason) < 20 THEN
          v_refused := v_refused || jsonb_build_array(jsonb_build_object(
            'application_id', v_app_id,
            'code',           'early_acceptance_reason_required',
            'reason',         'Aprovação sem nenhuma avaliação registrada exige justificativa de pelo menos 20 caracteres em early_acceptance_reason (Aceite Antecipado).',
            'evaluations_submitted', v_eval_count
          ));
          CONTINUE;
        END IF;
      END IF;

      BEGIN
        UPDATE public.selection_applications SET
          status                  = v_status,
          feedback                = coalesce(v_feedback, feedback),
          early_acceptance_at     = CASE WHEN v_early_reason IS NOT NULL THEN now()          ELSE early_acceptance_at     END,
          early_acceptance_by     = CASE WHEN v_early_reason IS NOT NULL THEN v_caller.id    ELSE early_acceptance_by     END,
          early_acceptance_reason = CASE WHEN v_early_reason IS NOT NULL THEN v_early_reason ELSE early_acceptance_reason END,
          updated_at              = now()
        WHERE id = v_app_id;

        -- #1175 D2: partner-chapter tag semantics centralized (no_partner_chapter /
        -- partner_chapter_at_risk) — see apply_partner_chapter_tags.
        PERFORM public.apply_partner_chapter_tags(v_app_id);

        v_canonical_result := public.approve_selection_application(v_app_id, '{}'::jsonb);

        IF (v_canonical_result->>'success') IS DISTINCT FROM 'true' THEN
          RAISE EXCEPTION 'Canonical approval failed for application %: %',
                          v_app_id,
                          coalesce(v_canonical_result->>'error', 'unknown')
            USING ERRCODE = 'P0001';
        END IF;

        v_approved_count := v_approved_count + 1;
        v_member_id         := (v_canonical_result->>'member_id')::uuid;
        v_promoted_this_app := coalesce((v_canonical_result->>'role_promoted')::boolean, false);
        v_target_role       := v_canonical_result->>'promoted_to';
        IF (v_canonical_result->>'member_created')::boolean THEN
          v_created_members := v_created_members + 1;
        END IF;
        IF v_promoted_this_app THEN
          v_promoted_count := v_promoted_count + 1;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        v_member_id        := NULL;
        v_canonical_result := jsonb_build_object('success', false, 'error', SQLERRM);
        -- #1572 — o `EXCEPTION WHEN OTHERS` engolia a falha e o retorno só mostrava um `approved`
        -- menor. A candidatura que falhou passa a aparecer nominalmente em `refused`.
        v_refused := v_refused || jsonb_build_array(jsonb_build_object(
          'application_id', v_app_id,
          'code',           'canonical_approval_failed',
          'reason',         SQLERRM
        ));
      END;

    ELSIF v_status = 'rejected' THEN
      UPDATE public.selection_applications SET
        status     = v_status,
        feedback   = coalesce(v_feedback, feedback),
        updated_at = now()
      WHERE id = v_app_id;
      v_rejected_count := v_rejected_count + 1;
    ELSIF v_status = 'waitlist' THEN
      UPDATE public.selection_applications SET
        status     = v_status,
        feedback   = coalesce(v_feedback, feedback),
        updated_at = now()
      WHERE id = v_app_id;
      v_waitlisted_count := v_waitlisted_count + 1;
    ELSE
      v_canonical_result := jsonb_build_object('success', false, 'error', 'unknown_decision', 'decision', v_status);
    END IF;

    INSERT INTO public.data_anomaly_log (anomaly_type, severity, description, context)
    VALUES (
      'selection_decision',
      'info',
      v_app.applicant_name || ' → ' || v_status,
      jsonb_build_object(
        'application_id',    v_app_id,
        'decision',          v_status,
        'actor',             v_caller.name,
        'actor_id',          v_caller.id,
        'member_id',         v_member_id,
        'role_promoted',     v_promoted_this_app,
        'promoted_to',       CASE WHEN v_promoted_this_app THEN v_target_role ELSE NULL END,
        'canonical_invoked', v_canonical_result IS NOT NULL,
        'canonical_success', (v_canonical_result->>'success')::boolean,
        'evaluations_submitted', v_eval_count,
        'early_acceptance',      v_early_reason IS NOT NULL
      )
    );
  END LOOP;

  INSERT INTO public.selection_diversity_snapshots (cycle_id, snapshot_type, metrics)
  VALUES (p_cycle_id, 'approved', (
    SELECT jsonb_build_object(
      'by_chapter', (SELECT jsonb_object_agg(coalesce(chapter,'unknown'), cnt) FROM (SELECT chapter, count(*) as cnt FROM public.selection_applications WHERE cycle_id = p_cycle_id AND status = 'approved' GROUP BY chapter) x),
      'by_gender',  (SELECT jsonb_object_agg(coalesce(gender,'unknown'), cnt) FROM (SELECT gender,  count(*) as cnt FROM public.selection_applications WHERE cycle_id = p_cycle_id AND status = 'approved' GROUP BY gender) x),
      'by_role',    (SELECT jsonb_object_agg(role_applied, cnt) FROM (SELECT role_applied, count(*) as cnt FROM public.selection_applications WHERE cycle_id = p_cycle_id AND status = 'approved' GROUP BY role_applied) x),
      'total_approved',  v_approved_count,
      'total_rejected',  v_rejected_count,
      'total_converted', v_converted_count,
      'finalized_at',    now()
    )
  ));

  RETURN json_build_object(
    'approved',         v_approved_count,
    'rejected',         v_rejected_count,
    'waitlisted',       v_waitlisted_count,
    'converted',        v_converted_count,
    'members_created',  v_created_members,
    'members_promoted', v_promoted_count,
    'refused',          v_refused,
    'refused_count',    jsonb_array_length(v_refused),
    'cycle_id',         p_cycle_id
  );
END;
$function$;

-- #1572 / #1592 — `finalize_decisions` carregava `anon=X` no ACL. É fail-closed (a primeira
-- instrução resolve o chamador por `auth.uid()` e retorna 'Unauthorized' com ele nulo), mas é a
-- mesma deriva de EXECUTE que as migrations 459/460/461 vinham revogando, numa SECDEF que cria
-- membro e engajamento. Revogado aqui porque esta migration já toca a função; a varredura do resto
-- da classe segue na #1592.
REVOKE EXECUTE ON FUNCTION public.finalize_decisions(uuid, jsonb) FROM PUBLIC, anon;

-- ── 4. get_selection_health — o contador que faltava ──────────────────────────────────────────────
-- Antes desta migration, "aprovado sem avaliação" só se descobria cruzando `status` com a contagem
-- de `selection_evaluations` na mão. O sinal de saúde olha só o ciclo ATIVO: as 8 linhas do
-- cycle2-2025 são legado e deixariam o painel amarelo para sempre.

CREATE OR REPLACE FUNCTION public.get_selection_health()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_caller_id uuid;
  v_active_cycle jsonb;
  v_application_counts jsonb;
  v_stale_tokens integer;
  v_welcome_backlog integer;
  v_crons jsonb;
  v_health_signal text;
  v_critical_cron_down boolean := false;
  v_decided_no_eval jsonb;
  v_unjustified_active int := 0;
  v_cron_names text[] := ARRAY[
    'send-notification-emails',
    'retry-pending-ai-analyses',
    'nudge-reschedule-pending-daily',
    'detect-onboarding-overdue-daily'
  ];
  v_cron_name text;
  v_cron_data jsonb;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Not authorized: requires view_internal_analytics');
  END IF;

  -- Active cycle
  SELECT jsonb_build_object(
    'id', c.id,
    'cycle_code', c.cycle_code,
    'title', c.title,
    'status', c.status,
    'phase', c.phase,
    'created_at', c.created_at
  )
  INTO v_active_cycle
  FROM public.selection_cycles c
  ORDER BY c.created_at DESC
  LIMIT 1;

  -- ADR-0109 PR-2 COI recusal: an active candidate in the active cycle is recused from this surface.
  IF v_active_cycle IS NOT NULL AND public.selection_coi_recused(v_caller_id, (v_active_cycle->>'id')::uuid) THEN
    RETURN jsonb_build_object('error', 'recused_conflict_of_interest',
      'detail', 'Você é candidato(a) neste ciclo — as visões de seleção estão impedidas por conflito de interesse (ADR-0109).');
  END IF;

  -- Application counts no ciclo ativo
  SELECT jsonb_build_object(
    'total', count(*),
    'submitted', count(*) FILTER (WHERE status='submitted'),
    'screening', count(*) FILTER (WHERE status='screening'),
    'objective_eval', count(*) FILTER (WHERE status='objective_eval'),
    'interview_pending', count(*) FILTER (WHERE status='interview_pending'),
    'interview_scheduled', count(*) FILTER (WHERE status='interview_scheduled'),
    'interview_done', count(*) FILTER (WHERE status='interview_done'),
    'final_eval', count(*) FILTER (WHERE status='final_eval'),
    'approved', count(*) FILTER (WHERE status IN ('approved','converted')),
    'rejected', count(*) FILTER (WHERE status IN ('rejected','objective_cutoff')),
    'cancelled', count(*) FILTER (WHERE status IN ('cancelled','withdrawn')),
    'waitlist', count(*) FILTER (WHERE status='waitlist'),
    'created_last_7d', count(*) FILTER (WHERE created_at >= now() - interval '7 days')
  )
  INTO v_application_counts
  FROM public.selection_applications
  WHERE cycle_id = (v_active_cycle->>'id')::uuid;

  -- #1572 — decidido sem NENHUMA avaliação submetida, separado entre justificado (aceite antecipado
  -- carimbado) e não justificado. `rejected` é CONTADO mas não é bloqueado na escrita: o portão do
  -- #1572 cobre aprovação, e estender para rejeição é decisão do PM.
  SELECT jsonb_build_object(
    'cycle', jsonb_build_object(
      'approved_without_evaluation',            count(*) FILTER (WHERE eh_ciclo AND eh_aprovado AND n_evals = 0),
      'approved_without_evaluation_justified',  count(*) FILTER (WHERE eh_ciclo AND eh_aprovado AND n_evals = 0 AND early_acceptance_at IS NOT NULL),
      'rejected_without_evaluation',            count(*) FILTER (WHERE eh_ciclo AND NOT eh_aprovado AND n_evals = 0)
    ),
    'all_cycles', jsonb_build_object(
      'approved_without_evaluation',            count(*) FILTER (WHERE eh_aprovado AND n_evals = 0),
      'approved_without_evaluation_justified',  count(*) FILTER (WHERE eh_aprovado AND n_evals = 0 AND early_acceptance_at IS NOT NULL),
      'rejected_without_evaluation',            count(*) FILTER (WHERE NOT eh_aprovado AND n_evals = 0)
    )
  )
  INTO v_decided_no_eval
  FROM (
    SELECT a.early_acceptance_at,
           (a.cycle_id = (v_active_cycle->>'id')::uuid) AS eh_ciclo,
           (a.status IN ('approved','converted'))       AS eh_aprovado,
           (SELECT count(*) FROM public.selection_evaluations e WHERE e.application_id = a.id) AS n_evals
    FROM public.selection_applications a
    WHERE a.status IN ('approved','converted','rejected')
  ) z;

  v_unjustified_active := coalesce((v_decided_no_eval->'cycle'->>'approved_without_evaluation')::int, 0)
                        - coalesce((v_decided_no_eval->'cycle'->>'approved_without_evaluation_justified')::int, 0);

  -- Stale tokens: onboarding_tokens não consumidos há >48h
  SELECT count(*) INTO v_stale_tokens
  FROM public.onboarding_tokens t
  JOIN public.selection_applications a ON a.id = t.source_id
  WHERE t.source_type = 'pmi_application'
    AND COALESCE(t.access_count, 0) = 0
    AND t.issued_at < now() - interval '48 hours'
    AND a.cycle_id = (v_active_cycle->>'id')::uuid;

  -- Welcome backlog: approved sem token consumed (proxy para welcome não dispatched)
  SELECT count(*) INTO v_welcome_backlog
  FROM public.selection_applications a
  WHERE a.cycle_id = (v_active_cycle->>'id')::uuid
    AND a.status IN ('approved','converted')
    AND NOT EXISTS (
      SELECT 1 FROM public.onboarding_tokens t
      WHERE t.source_id = a.id AND t.source_type = 'pmi_application' AND COALESCE(t.access_count, 0) > 0
    );

  -- Cron health para cada cron relevante
  v_crons := '[]'::jsonb;
  FOREACH v_cron_name IN ARRAY v_cron_names LOOP
    SELECT jsonb_build_object(
      'jobname', v_cron_name,
      'active', j.active,
      'schedule', j.schedule,
      'last_run_at', (
        SELECT max(start_time) FROM cron.job_run_details d WHERE d.jobid = j.jobid
      ),
      'last_status', (
        SELECT status FROM cron.job_run_details d WHERE d.jobid = j.jobid
        ORDER BY start_time DESC LIMIT 1
      ),
      'last_5_status', (
        SELECT jsonb_agg(jsonb_build_object('start', start_time, 'status', status, 'msg', return_message) ORDER BY start_time DESC)
        FROM (
          SELECT start_time, status, return_message FROM cron.job_run_details d2
          WHERE d2.jobid = j.jobid ORDER BY start_time DESC LIMIT 5
        ) t
      )
    )
    INTO v_cron_data
    FROM cron.job j
    WHERE j.jobname = v_cron_name;

    IF v_cron_data IS NULL THEN
      v_cron_data := jsonb_build_object(
        'jobname', v_cron_name,
        'active', false,
        'error', 'cron job not registered'
      );
      -- Critical: 4 monitored crons, all should exist
      v_critical_cron_down := true;
    END IF;

    v_crons := v_crons || jsonb_build_array(v_cron_data);
  END LOOP;

  -- Health signal
  -- #1572 — aprovação sem lastro E sem justificativa no ciclo ATIVO puxa para amarelo. O escopo é o
  -- ciclo ativo de propósito: contar o histórico deixaria o sinal preso em amarelo pelas linhas de
  -- 2025, que já não têm como ganhar justificativa.
  v_health_signal := CASE
    WHEN v_critical_cron_down OR v_stale_tokens >= 5 THEN 'red'
    WHEN v_stale_tokens > 0 OR v_welcome_backlog > 0 OR v_unjustified_active > 0 THEN 'yellow'
    ELSE 'green'
  END;

  RETURN jsonb_build_object(
    'active_cycle', COALESCE(v_active_cycle, jsonb_build_object('error', 'no cycle found')),
    'application_counts', v_application_counts,
    'decided_without_evaluation', v_decided_no_eval,
    'stale_tokens_48h', v_stale_tokens,
    'welcome_backlog', v_welcome_backlog,
    'crons', v_crons,
    'health_signal', v_health_signal,
    'fetched_at', now()
  );
END;
$function$;

-- ── 5. admin_decide_dual_track — o par pesquisador+líder ──────────────────────────────────────────
-- 10 candidaturas vivas seguem por aqui (medido 15/08), todas pareadas. A função delega as duas
-- pontas para `admin_update_application`, então sem repassar a justificativa o GP bateria numa
-- recusa sem ter onde escrevê-la.
--
-- Muda a contagem de parâmetros (4 → 5): DROP + CREATE, não CREATE OR REPLACE, senão fica overload.
--
-- Segundo defeito corrigido junto, e ele é pré-existente: os retornos de `admin_update_application`
-- eram guardados em `v_researcher_result` / `v_leader_result` e **nunca conferidos**. Uma ponta que
-- voltasse `{"error": ...}` era embrulhada num `success: true`, e a tela dizia "Decisões aplicadas".
-- Com o portão do #1572 esse caminho passaria a ser alcançável de verdade.

DROP FUNCTION IF EXISTS public.admin_decide_dual_track(uuid, text, text, text);

CREATE OR REPLACE FUNCTION public.admin_decide_dual_track(
  p_application_id uuid,
  p_researcher_decision text,
  p_leader_decision text,
  p_feedback text DEFAULT NULL,
  p_early_acceptance_reason text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_caller_id          uuid;
  v_app                record;
  v_sibling_app        record;
  v_researcher_app_id  uuid;
  v_leader_app_id      uuid;
  v_scored             record;
  v_unscored_id        uuid;
  v_researcher_result  json;
  v_leader_result      json;
  v_copied_scores      boolean := false;
  v_allowed_decisions  text[] := ARRAY['approved','rejected','waitlist'];
  v_early              text;
  v_payload            jsonb;
BEGIN
  -- Auth
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN json_build_object('error', 'Unauthorized'); END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN json_build_object('error', 'Unauthorized');
  END IF;

  -- Validate decisions
  IF NOT (p_researcher_decision = ANY(v_allowed_decisions)) THEN
    RETURN json_build_object('error', 'Invalid researcher_decision: ' || p_researcher_decision);
  END IF;
  IF NOT (p_leader_decision = ANY(v_allowed_decisions)) THEN
    RETURN json_build_object('error', 'Invalid leader_decision: ' || p_leader_decision);
  END IF;

  -- Resolve pair
  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF NOT FOUND THEN RETURN json_build_object('error', 'Application not found'); END IF;

  IF v_app.promotion_path IS DISTINCT FROM 'dual_track' OR v_app.linked_application_id IS NULL THEN
    RETURN json_build_object('error', 'Application is not part of a dual_track pair');
  END IF;

  SELECT * INTO v_sibling_app FROM public.selection_applications WHERE id = v_app.linked_application_id;
  IF NOT FOUND THEN RETURN json_build_object('error', 'Sibling application not found'); END IF;

  -- Determine researcher/leader app id
  IF v_app.role_applied = 'researcher' AND v_sibling_app.role_applied = 'leader' THEN
    v_researcher_app_id := v_app.id;
    v_leader_app_id     := v_sibling_app.id;
  ELSIF v_app.role_applied = 'leader' AND v_sibling_app.role_applied = 'researcher' THEN
    v_researcher_app_id := v_sibling_app.id;
    v_leader_app_id     := v_app.id;
  ELSE
    RETURN json_build_object('error', 'Pair roles are not researcher+leader (' || v_app.role_applied || ' + ' || v_sibling_app.role_applied || ')');
  END IF;

  -- Auto-copy role-agnostic scores (objective + interview) from scored to unscored.
  -- Done before applying decisions so that downstream final_score recompute (next ranking
  -- recalc) sees consistent data on both apps.
  SELECT id, objective_score_avg, interview_score INTO v_scored
  FROM   public.selection_applications
  WHERE  id IN (v_researcher_app_id, v_leader_app_id)
    AND  objective_score_avg IS NOT NULL
  ORDER BY (CASE WHEN id = v_leader_app_id THEN 0 ELSE 1 END)  -- prefer leader if both scored
  LIMIT 1;

  IF FOUND THEN
    v_unscored_id := CASE WHEN v_scored.id = v_researcher_app_id THEN v_leader_app_id ELSE v_researcher_app_id END;

    UPDATE public.selection_applications
    SET    objective_score_avg = COALESCE(objective_score_avg, v_scored.objective_score_avg),
           interview_score     = COALESCE(interview_score,     v_scored.interview_score),
           updated_at          = now()
    WHERE  id = v_unscored_id
      AND  (objective_score_avg IS NULL OR interview_score IS NULL);

    IF FOUND THEN v_copied_scores := true; END IF;
  END IF;

  -- #1572 — a justificativa vai para as DUAS pontas. Cada `admin_update_application` conta as
  -- avaliações da SUA candidatura e só exige o campo quando a contagem é zero, então mandar em ambas
  -- não afrouxa nada: na ponta que tem avaliação o campo é ignorado.
  v_early := NULLIF(btrim(coalesce(p_early_acceptance_reason, '')), '');

  -- Apply per-role decisions via existing single-app RPC (preserves onboarding seed,
  -- Op B promotion, notification, audit log behaviors).
  v_payload := jsonb_build_object(
    'status',   p_researcher_decision,
    'feedback', COALESCE(p_feedback, '')
  );
  IF v_early IS NOT NULL THEN
    v_payload := v_payload || jsonb_build_object('early_acceptance_reason', v_early);
  END IF;
  v_researcher_result := public.admin_update_application(v_researcher_app_id, v_payload);

  -- #1572 — a recusa da ponta era engolida: o resultado ia para a variável e ninguém o lia, então
  -- `{"error": ...}` virava `success: true` na tela. RAISE derruba a transação inteira, e as duas
  -- pontas do par voltam juntas em vez de meia decisão gravada.
  IF (v_researcher_result->>'error') IS NOT NULL THEN
    RAISE EXCEPTION 'Decisão do par recusada na ponta pesquisador: %', (v_researcher_result->>'error')
      USING ERRCODE = 'P0001', DETAIL = v_researcher_result::text;
  END IF;

  v_payload := jsonb_build_object(
    'status',   p_leader_decision,
    'feedback', COALESCE(p_feedback, '')
  );
  IF v_early IS NOT NULL THEN
    v_payload := v_payload || jsonb_build_object('early_acceptance_reason', v_early);
  END IF;
  v_leader_result := public.admin_update_application(v_leader_app_id, v_payload);

  IF (v_leader_result->>'error') IS NOT NULL THEN
    RAISE EXCEPTION 'Decisão do par recusada na ponta líder: %', (v_leader_result->>'error')
      USING ERRCODE = 'P0001', DETAIL = v_leader_result::text;
  END IF;

  -- Cross-decision audit entry (separable from per-app audits done by admin_update_application)
  INSERT INTO public.data_anomaly_log (anomaly_type, severity, description, context)
  VALUES (
    'selection_dual_track_decision',
    'info',
    v_app.applicant_name || ': researcher=' || p_researcher_decision || ', leader=' || p_leader_decision,
    jsonb_build_object(
      'researcher_app_id',  v_researcher_app_id,
      'leader_app_id',      v_leader_app_id,
      'researcher_decision', p_researcher_decision,
      'leader_decision',    p_leader_decision,
      'scores_copied',      v_copied_scores,
      'feedback',           p_feedback,
      'caller_id',          v_caller_id,
      'early_acceptance',   v_early IS NOT NULL
    )
  );

  RETURN json_build_object(
    'success',             true,
    'researcher_app_id',   v_researcher_app_id,
    'leader_app_id',       v_leader_app_id,
    'researcher_decision', p_researcher_decision,
    'leader_decision',     p_leader_decision,
    'scores_copied',       v_copied_scores,
    'early_acceptance',    v_early IS NOT NULL,
    'researcher_result',   v_researcher_result,
    'leader_result',       v_leader_result
  );
END;
$function$;

-- `CREATE FUNCTION` nasce com EXECUTE para PUBLIC. A anterior já carregava `anon=X` (a mesma deriva
-- da #1592); a nova nasce fechada, e o GRANT é explícito para quem a chama de fato.
REVOKE EXECUTE ON FUNCTION public.admin_decide_dual_track(uuid, text, text, text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.admin_decide_dual_track(uuid, text, text, text, text) TO authenticated, service_role;
