-- #2392 (item da #2542, etapa 0 da ADR-0134): aprovar com menos avaliadores objetivos que o mínimo
-- do ciclo passa a exigir justificativa.
--
-- O portão da #1572 só pedia justificativa quando a candidatura tinha ZERO avaliações, de qualquer
-- tipo. Uma candidatura com UMA objetiva, num ciclo de `min_evaluators = 2`, passava calada: foi o
-- caso das 3 aprovações registradas como Aceite Antecipado em 02/10/2026. Decisão do GP no mesmo dia:
-- exceção registrada e trava daqui para frente, contando também a candidatura ligada (no par
-- `dual_track` a objetiva fica numa das pontas).
--
-- Medido em 30/10/2026 no cycle4-2026, pela régua nova (avaliadores objetivos distintos do par):
--   approved com o mínimo atingido ......................... 72
--   approved abaixo do mínimo, com Aceite Antecipado ........ 3  (os de 02/10)
--   approved abaixo do mínimo, sem carimbo .................. 2  (entraram aprovados pela importação
--                                                                 do VEP, balde qualified, sem passar
--                                                                 por estas funções; fora desta trava)
--   `min_evaluators` = 2 nos 4 ciclos.
--
-- O que muda:
--   1. `_selection_objective_evaluators`: uma fonte só para a régua.
--   2. `admin_update_application` e `finalize_decisions`: o portão compara com o mínimo do ciclo.
--      O resto dos corpos é o da migration 20260815234545, sem mudança.
--   3. O retorno e o log deixam de levar `evaluations_submitted` (contava avaliação de qualquer
--      tipo) e passam a levar `objective_evaluators` e `min_evaluators`. Chave nova para significado
--      novo: a mesma chave com outro sentido misturaria o histórico do `data_anomaly_log`.
--   4. Os comentários das colunas do Aceite Antecipado passam a dizer "abaixo do mínimo".
--
-- `admin_decide_dual_track` não muda: ele delega as duas pontas para `admin_update_application`, e
-- as duas pontas agora leem a mesma contagem do par.

-- ── 1. Quantos avaliadores objetivos o PAR tem ──────────────────────────────────────────────────────
-- Conta avaliador DISTINTO, porque `min_evaluators` fala de pessoas: o mesmo avaliador nas duas
-- pontas do par é uma avaliação, não duas. O par segue o vínculo nos dois sentidos, porque em
-- 30/10/2026 havia 1 vínculo gravado só de um lado.

CREATE OR REPLACE FUNCTION public._selection_objective_evaluators(p_application_id uuid)
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $function$
  SELECT count(DISTINCT e.evaluator_id)::integer
  FROM public.selection_evaluations e
  WHERE e.evaluation_type = 'objective'
    AND e.submitted_at IS NOT NULL
    AND e.application_id IN (
      SELECT a.id FROM public.selection_applications a
       WHERE a.id = p_application_id
      UNION
      SELECT a.linked_application_id FROM public.selection_applications a
       WHERE a.id = p_application_id AND a.linked_application_id IS NOT NULL
      UNION
      SELECT a.id FROM public.selection_applications a
       WHERE a.linked_application_id = p_application_id
    );
$function$;

COMMENT ON FUNCTION public._selection_objective_evaluators(uuid) IS
  '#2392: avaliadores objetivos distintos, com avaliação submetida, somando a candidatura ligada nos dois sentidos. Régua do portão de aprovação de admin_update_application e finalize_decisions.';

-- Chamada só de dentro das funções de decisão, que rodam como dono. O service_role lê para o guard.
REVOKE EXECUTE ON FUNCTION public._selection_objective_evaluators(uuid) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._selection_objective_evaluators(uuid) TO service_role;

-- ── 2. admin_update_application: o caminho de decisão de UMA candidatura ────────────────────────────

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
  v_objective_evaluators int := NULL;
  v_min_evaluators       int := NULL;
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

  -- #2392 — aprovar abaixo do mínimo de avaliadores objetivos do ciclo (somando a candidatura ligada)
  -- continua permitido, como Aceite Antecipado, mas exige justificativa. Antes a régua era "zero
  -- avaliações de qualquer tipo", e uma candidatura com UMA objetiva passava calada. Mínimo vazio
  -- conta como não atingido: a trava não abre por falta de dado.
  -- #1572 — a recusa acontece ANTES do UPDATE: uma aprovação sem lastro que gravasse status e só
  -- depois falhasse deixaria a candidatura aprovada sem o carimbo que a explica.
  IF v_requested_status = 'approved' AND v_old_status <> 'approved' THEN
    v_objective_evaluators := public._selection_objective_evaluators(p_application_id);

    SELECT c.min_evaluators INTO v_min_evaluators
    FROM public.selection_cycles c
    WHERE c.id = v_app.cycle_id;

    IF v_min_evaluators IS NULL OR v_objective_evaluators < v_min_evaluators THEN
      v_early_reason := btrim(coalesce(p_data->>'early_acceptance_reason', ''));
      IF length(v_early_reason) < 20 THEN
        RETURN json_build_object(
          'error',   format('Aprovação com %s avaliador(es) objetivo(s), abaixo do mínimo do ciclo (%s), exige justificativa de pelo menos 20 caracteres em early_acceptance_reason (Aceite Antecipado). A contagem soma a candidatura ligada.',
                            v_objective_evaluators, coalesce(v_min_evaluators::text, 'não definido')),
          'code',    'early_acceptance_reason_required',
          'objective_evaluators', v_objective_evaluators,
          'min_evaluators',       v_min_evaluators
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
      'objective_evaluators',  v_objective_evaluators,
      'min_evaluators',        v_min_evaluators,
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
    'objective_evaluators',  v_objective_evaluators,
    'min_evaluators',        v_min_evaluators,
    'early_acceptance',      v_early_reason IS NOT NULL,
    'canonical',         v_canonical_result
  );
END;
$function$;

-- ── 3. finalize_decisions: o caminho em LOTE ─────────────────────────────────────────────────────────

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
  v_objective_evaluators int;
  v_min_evaluators      int;
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

  -- #2392 — o lote é de UM ciclo, então o mínimo é lido uma vez.
  SELECT c.min_evaluators INTO v_min_evaluators
  FROM public.selection_cycles c
  WHERE c.id = p_cycle_id;

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
    v_objective_evaluators := NULL;
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
      -- #2392 — mesma régua do caminho de UMA candidatura: avaliadores objetivos do par contra o
      -- mínimo do ciclo, e mínimo vazio conta como não atingido.
      -- #1572 — no lote a recusa não aborta as outras decisões: a candidatura entra em `refused` e o
      -- chamador vê o que NÃO foi aplicado, em vez de ler um `approved` menor do que pediu e não
      -- saber quais ficaram de fora.
      v_objective_evaluators := public._selection_objective_evaluators(v_app_id);

      IF v_min_evaluators IS NULL OR v_objective_evaluators < v_min_evaluators THEN
        v_early_reason := btrim(coalesce(v_decision->>'early_acceptance_reason', ''));
        IF length(v_early_reason) < 20 THEN
          v_refused := v_refused || jsonb_build_array(jsonb_build_object(
            'application_id', v_app_id,
            'code',           'early_acceptance_reason_required',
            'reason',         format('Aprovação com %s avaliador(es) objetivo(s), abaixo do mínimo do ciclo (%s), exige justificativa de pelo menos 20 caracteres em early_acceptance_reason (Aceite Antecipado). A contagem soma a candidatura ligada.',
                                     v_objective_evaluators, coalesce(v_min_evaluators::text, 'não definido')),
            'objective_evaluators', v_objective_evaluators,
            'min_evaluators',       v_min_evaluators
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
        'objective_evaluators',  v_objective_evaluators,
        'min_evaluators',        v_min_evaluators,
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

-- ── 4. As colunas do Aceite Antecipado dizem a régua nova ───────────────────────────────────────────

COMMENT ON COLUMN public.selection_applications.early_acceptance_at IS
  '#1572, #2392: carimbo do Aceite Antecipado (aprovação abaixo do mínimo de avaliadores objetivos do ciclo, somando a candidatura ligada; inclui zero). NULL = não houve. Esta coluna É a flag; não existe booleano espelho.';
COMMENT ON COLUMN public.selection_applications.early_acceptance_by IS
  '#1572, #2392: members.id de quem aprovou abaixo do mínimo de avaliadores objetivos.';
COMMENT ON COLUMN public.selection_applications.early_acceptance_reason IS
  '#1572, #2392: justificativa obrigatória (>= 20 caracteres) do Aceite Antecipado.';
