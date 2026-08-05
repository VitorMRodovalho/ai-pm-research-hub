-- #1613 — R1: gate único de fase objetiva na ENTRADA do estágio de entrevista.
--
-- O arco #1584 / #1594 / #1595 / #1598 fechou a porta de SAÍDA (quem recebe o convite).
-- Esta migration fecha a de ENTRADA (quem acaba em `interview_scheduled`).
--
-- Opção 1 da SPEC_INTERVIEW_BOOKING_INTEGRITY §4.1, ratificada pelo PM em 2026-08-05:
-- trigger BEFORE UPDATE em `selection_applications`, e não helper chamado pelos escritores.
-- A Opção 2 é exatamente o padrão que produziu a Classe A, onde o gate existia num dos
-- caminhos e não nos outros — hoje são SETE escritores, e o oitavo não vai lembrar de chamar
-- helper nenhum.
--
-- O trigger NÃO levanta exceção: SUPRIME a transição (`NEW.status := OLD.status`) e registra
-- `selection.interview_stage_blocked`. O motivo está na §4.1 — o cron 49 processa em laço, uma
-- candidatura por iteração, e uma exceção abortaria a função inteira. Suprimir com registro
-- atende o R1.2; suprimir calado, não.
--
-- Medido em 2026-08-05 22:20 UTC, antes de aplicar:
--   • passivo em repouso (interview_scheduled/interview_done sem nota, ciclo aberto): 0
--     (0 também somando TODOS os ciclos) — o gate é puramente PREVENTIVO, não há backfill
--   • linhas de selection_interviews criadas em 90d: 73; dessas, de candidatura sem nota: 6
--     (todas as 6 já em desfecho posterior: 2 final_eval, 3 approved, 1 rejected)
--   • ciclo aberto: 81 candidaturas
--   • gate_attempts de schedule_interview com bypass CONCEDIDO: 26, o último em 2026-08-04;
--     em 3 deles a nota objetiva era NULL no momento. Esse caminho está VIVO — daí o R1.4
--     abaixo não ser formalidade: sem ele o gate faria o bypass do admin falhar CALADO.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) R1.4 — o caminho de exceção, declarado como exceção
-- ─────────────────────────────────────────────────────────────────────────────
-- `admin_update_application` já era, na prática, a porta de exceção do GP: exigia
-- `manage_platform` e escrevia qualquer status. O que faltava era ser DECLARADA — não pedia
-- motivo e não registrava a exceção como exceção. O override passa a morar na própria
-- candidatura, com autor e motivo.

ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS interview_stage_override_at     timestamptz,
  ADD COLUMN IF NOT EXISTS interview_stage_override_by     uuid REFERENCES public.members(id),
  ADD COLUMN IF NOT EXISTS interview_stage_override_reason text;

COMMENT ON COLUMN public.selection_applications.interview_stage_override_at IS
  '#1613 R1.4 — quando o GP autorizou esta candidatura a entrar em interview_scheduled sem nota objetiva. Lido por _trg_gate_interview_stage_entry.';
COMMENT ON COLUMN public.selection_applications.interview_stage_override_by IS
  '#1613 R1.4 — quem autorizou (members.id).';
COMMENT ON COLUMN public.selection_applications.interview_stage_override_reason IS
  '#1613 R1.4 — motivo obrigatório da exceção. Uma exceção sem motivo é indistinguível de um descuido.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) O gate
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._trg_gate_interview_stage_entry()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_actor uuid;
BEGIN
  -- Só a TRANSIÇÃO de ENTRADA importa.
  IF NEW.status IS DISTINCT FROM 'interview_scheduled' THEN
    RETURN NEW;
  END IF;

  -- R1.3 / R1.5 — estado em repouso e reescrita idempotente passam sem tocar em nada.
  -- É por isso que a migration não invalida nenhuma linha existente: o gate olha a
  -- transição, nunca o estado.
  IF OLD.status IS NOT DISTINCT FROM 'interview_scheduled' THEN
    RETURN NEW;
  END IF;

  -- O caso normal: fase objetiva concluída.
  IF NEW.objective_score_avg IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- R1.4 — override explícito. Lê NEW, e não OLD, de propósito: o escritor pode carimbar o
  -- override no MESMO UPDATE que promove o status, que é o que schedule_interview faz no
  -- caminho de bypass do admin.
  IF NEW.interview_stage_override_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- R1.5 — quem JÁ esteve no estágio de entrevista está REAGENDANDO, não entrando.
  -- Dois sinais, ambos necessários porque `interview_pending` é ambíguo (é tanto o estado
  -- pré-entrada quanto o estado pós-cancelamento):
  --   (a) o status de origem já é posterior à entrada;
  --   (b) existe entrevista MATERIALIZADA e já resolvida.
  -- ⚠️ (b) NÃO pode ser "existe linha de entrevista": o calendar-webhook insere a linha
  -- ANTES de promover o status, então essa isenção reabriria exatamente o buraco que este
  -- gate fecha. Uma linha recém-inserida tem status 'scheduled' e conducted_at NULL, e
  -- portanto não casa aqui.
  IF OLD.status IN ('interview_done', 'interview_noshow', 'final_eval') THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.selection_interviews si
    WHERE si.application_id = NEW.id
      AND ( si.conducted_at IS NOT NULL
            OR si.status IN ('completed', 'noshow', 'rescheduled', 'cancelled') )
  ) THEN
    RETURN NEW;
  END IF;

  -- Recusa: suprimir a transição, não levantar exceção (§4.1).
  NEW.status := OLD.status;

  BEGIN
    SELECT m.id INTO v_actor FROM public.members m WHERE m.auth_id = auth.uid();

    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      v_actor,
      'selection.interview_stage_blocked',
      'selection_application',
      NEW.id,
      jsonb_build_object(
        'status', jsonb_build_object('attempted', 'interview_scheduled', 'kept', OLD.status)
      ),
      jsonb_build_object(
        'issue',           1613,
        'reason',          'objective_score_avg IS NULL',
        'from_status',     OLD.status,
        'has_auth_uid',    (auth.uid() IS NOT NULL),
        'interview_rows',  (SELECT count(*) FROM public.selection_interviews si2 WHERE si2.application_id = NEW.id),
        'source',          '_trg_gate_interview_stage_entry'
      )
    );
  EXCEPTION WHEN OTHERS THEN
    -- A recusa já aconteceu na linha acima; falhar aqui derrubaria o UPDATE do chamador,
    -- que é justamente o que a §4.1 proíbe. Mesma política de _log_gate_attempt.
    RAISE WARNING '_trg_gate_interview_stage_entry: audit falhou: %', SQLERRM;
  END;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public._trg_gate_interview_stage_entry() FROM PUBLIC, anon, authenticated;

-- ⚠️ O NOME é decisão de projeto, não acaso. Gatilhos do mesmo evento disparam em ordem
-- ALFABÉTICA. Os BEFORE já existentes em selection_applications são
-- `trg_link_renewal_application`, `trg_purge_ai_analysis_on_consent_revocation` e
-- `trg_stamp_vep_offer_extended`; o prefixo `trg_zz_` põe o gate DEPOIS de todos eles, de
-- modo que qualquer trigger que venha a PREENCHER a nota no mesmo UPDATE já tenha rodado
-- quando o gate lê NEW.objective_score_avg. A ordem é afirmada por teste.
DROP TRIGGER IF EXISTS trg_zz_gate_interview_stage_entry ON public.selection_applications;
CREATE TRIGGER trg_zz_gate_interview_stage_entry
  BEFORE UPDATE OF status ON public.selection_applications
  FOR EACH ROW
  EXECUTE FUNCTION public._trg_gate_interview_stage_entry();

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) R1.4 — RPC do GP, com motivo obrigatório e auditado
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.grant_interview_stage_override(
  p_application_id uuid,
  p_reason         text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_caller_id uuid;
  v_app       record;
  v_reason    text;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthorized',
      'message', 'manage_platform required');
  END IF;

  v_reason := NULLIF(btrim(coalesce(p_reason, '')), '');
  IF v_reason IS NULL OR length(v_reason) < 12 THEN
    RETURN jsonb_build_object('success', false, 'error', 'reason_required',
      'message', 'Motivo obrigatório (mínimo 12 caracteres). O override é a exceção DECLARADA do R1.4; uma exceção sem motivo é indistinguível de um descuido.');
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'application_not_found');
  END IF;

  UPDATE public.selection_applications
     SET interview_stage_override_at     = now(),
         interview_stage_override_by     = v_caller_id,
         interview_stage_override_reason = v_reason,
         updated_at                      = now()
   WHERE id = p_application_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller_id,
    'selection.interview_stage_override_granted',
    'selection_application',
    p_application_id,
    jsonb_build_object(
      'interview_stage_override_reason',
        jsonb_build_object('from', v_app.interview_stage_override_reason, 'to', v_reason)
    ),
    jsonb_build_object(
      'issue',               1613,
      'app_status',          v_app.status,
      'objective_score_avg', v_app.objective_score_avg,
      'cycle_id',            v_app.cycle_id
    )
  );

  RETURN jsonb_build_object(
    'success',        true,
    'application_id', p_application_id,
    'granted_by',     v_caller_id,
    'reason',         v_reason
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.grant_interview_stage_override(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.grant_interview_stage_override(uuid, text) TO authenticated, service_role;

COMMENT ON FUNCTION public.grant_interview_stage_override(uuid, text) IS
  '#1613 R1.4 — autoriza UMA candidatura a entrar em interview_scheduled sem nota objetiva. manage_platform + motivo obrigatório + admin_audit_log.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) Escritor 1/7 — schedule_interview: o bypass do admin É a exceção do R1.4
-- ─────────────────────────────────────────────────────────────────────────────
-- Medido: 26 concessões de bypass, a última em 2026-08-04, 3 delas com a nota objetiva
-- NULL. Sem carimbar o override aqui, o gate suprimiria a promoção e este caminho — o
-- "admin emergency path" de selection.astro — passaria a falhar CALADO, com a entrevista
-- criada e a candidatura para trás. Corpo base: o VIVO em 2026-08-05.
CREATE OR REPLACE FUNCTION public.schedule_interview(
  p_application_id uuid,
  p_interviewer_ids uuid[],
  p_scheduled_at timestamp with time zone,
  p_duration_minutes integer DEFAULT 30,
  p_calendar_event_id text DEFAULT NULL::text,
  p_bypass_gate boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_committee record;
  v_interview_id uuid;
  v_interviewer_id uuid;
  v_eval_count int;
  v_can_bypass boolean;
  v_gate_payload jsonb;
  v_stamp_override boolean;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id AND role = 'lead';

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: must be committee lead or platform admin';
  END IF;

  v_can_bypass := p_bypass_gate AND public.can_by_member(v_caller.id, 'manage_member'::text);

  SELECT COUNT(*) INTO v_eval_count FROM public.selection_evaluations WHERE application_id = p_application_id;
  v_gate_payload := jsonb_build_object(
    'has_consent', (v_app.consent_ai_analysis_at IS NOT NULL),
    'has_ai_analysis', (v_app.ai_analysis IS NOT NULL),
    'eval_count', v_eval_count,
    'objective_score_avg', v_app.objective_score_avg,
    'app_status', v_app.status,
    'gate_mode', CASE WHEN v_can_bypass THEN 'bypass' ELSE 'full' END
  );

  -- Workflow gate
  IF NOT v_can_bypass THEN
    IF v_app.consent_ai_analysis_at IS NULL OR v_app.ai_analysis IS NULL THEN
      PERFORM public._log_gate_attempt(
        p_application_id, 'schedule_interview', v_caller.id, false,
        'P0001', 'GATE_NO_AI', p_bypass_gate, v_can_bypass,
        v_gate_payload, v_app.organization_id
      );
      RETURN jsonb_build_object(
        'success', false,
        'application_id', p_application_id,
        'gate_failed_code', 'P0001',
        'gate_failed_reason', 'GATE_NO_AI',
        'message', 'GATE_NO_AI: candidate has no AI analysis. Use p_bypass_gate=true with manage_member to override.'
      );
    END IF;

    IF v_eval_count < 2 THEN
      PERFORM public._log_gate_attempt(
        p_application_id, 'schedule_interview', v_caller.id, false,
        'P0002', 'GATE_NO_PEER_REVIEW', p_bypass_gate, v_can_bypass,
        v_gate_payload, v_app.organization_id
      );
      RETURN jsonb_build_object(
        'success', false,
        'application_id', p_application_id,
        'gate_failed_code', 'P0002',
        'gate_failed_reason', 'GATE_NO_PEER_REVIEW',
        'message', format('GATE_NO_PEER_REVIEW: candidate has %s peer evaluations (minimum 2 required).', v_eval_count)
      );
    END IF;

    IF v_app.objective_score_avg IS NULL THEN
      PERFORM public._log_gate_attempt(
        p_application_id, 'schedule_interview', v_caller.id, false,
        'P0003', 'GATE_NO_SCORE', p_bypass_gate, v_can_bypass,
        v_gate_payload, v_app.organization_id
      );
      RETURN jsonb_build_object(
        'success', false,
        'application_id', p_application_id,
        'gate_failed_code', 'P0003',
        'gate_failed_reason', 'GATE_NO_SCORE',
        'message', 'GATE_NO_SCORE: objective_score_avg not computed.'
      );
    END IF;
  END IF;

  -- #472 corr.3 — P0004 status gate. O bypass do admin (v_can_bypass = p_bypass_gate AND
  -- manage_member) vale APENAS a partir de um status pré-entrevista que genuinamente ainda não tem
  -- entrevista — ALLOW-LIST, não block-list, para que um status de fase posterior
  -- (interview_done / final_eval) ou terminal NUNCA seja regredido a interview_scheduled pelo
  -- UPDATE incondicional abaixo.
  IF NOT (
       v_app.status IN ('interview_pending', 'interview_scheduled')
       OR ( v_can_bypass AND v_app.status IN ('screening', 'submitted', 'objective_eval', 'objective_cutoff') )
     ) THEN
    PERFORM public._log_gate_attempt(
      p_application_id, 'schedule_interview', v_caller.id, false,
      'P0004', 'INVALID_APP_STATUS:' || v_app.status, p_bypass_gate, v_can_bypass,
      v_gate_payload, v_app.organization_id
    );
    RETURN jsonb_build_object(
      'success', false,
      'application_id', p_application_id,
      'gate_failed_code', 'P0004',
      'gate_failed_reason', 'INVALID_APP_STATUS:' || v_app.status,
      'message', format('Application status %s does not allow scheduling interview', v_app.status)
    );
  END IF;

  -- All gates passed → create interview
  INSERT INTO public.selection_interviews (
    application_id, interviewer_ids, scheduled_at,
    duration_minutes, status, calendar_event_id
  ) VALUES (
    p_application_id, p_interviewer_ids, p_scheduled_at,
    p_duration_minutes, 'scheduled', p_calendar_event_id
  )
  RETURNING id INTO v_interview_id;

  -- #1613 R1.4 — quando o admin usa o bypass numa candidatura SEM nota objetiva, esse ato É
  -- a exceção declarada: carimba o override no MESMO UPDATE que promove o status, para que
  -- trg_zz_gate_interview_stage_entry (que lê NEW) deixe passar. Sem isto, um caminho vivo
  -- (26 usos, 3 sem nota) passaria a suprimir a promoção em silêncio.
  v_stamp_override := v_can_bypass AND v_app.objective_score_avg IS NULL;

  UPDATE public.selection_applications
  SET status = 'interview_scheduled',
      updated_at = now(),
      interview_stage_override_at =
        CASE WHEN v_stamp_override THEN now() ELSE interview_stage_override_at END,
      interview_stage_override_by =
        CASE WHEN v_stamp_override THEN v_caller.id ELSE interview_stage_override_by END,
      interview_stage_override_reason =
        CASE WHEN v_stamp_override
             THEN 'schedule_interview: p_bypass_gate=true (manage_member) — excecao do R1.4 pelo caminho de emergencia do admin'
             ELSE interview_stage_override_reason END
  WHERE id = p_application_id;

  FOREACH v_interviewer_id IN ARRAY p_interviewer_ids
  LOOP
    PERFORM public.create_notification(
      v_interviewer_id,
      'selection_interview_scheduled',
      'Entrevista agendada: ' || v_app.applicant_name,
      'Entrevista com ' || v_app.applicant_name || ' (' || COALESCE(v_app.chapter, '') || ') agendada para ' || to_char(p_scheduled_at, 'DD/MM/YYYY HH24:MI'),
      '/admin/selection',
      'selection_interview',
      v_interview_id
    );
  END LOOP;

  PERFORM public.create_notification(
    m.id,
    'selection_interview_scheduled',
    'Sua entrevista foi agendada',
    'Entrevista agendada para ' || to_char(p_scheduled_at, 'DD/MM/YYYY HH24:MI') || '. Prepare-se!',
    NULL,
    'selection_interview',
    v_interview_id
  )
  FROM public.members m
  WHERE m.email = v_app.email;

  PERFORM public._log_gate_attempt(
    p_application_id, 'schedule_interview', v_caller.id, true,
    NULL, NULL, p_bypass_gate, v_can_bypass,
    v_gate_payload || jsonb_build_object('stage_override_stamped', v_stamp_override),
    v_app.organization_id
  );

  RETURN jsonb_build_object(
    'success', true,
    'interview_id', v_interview_id,
    'scheduled_at', p_scheduled_at,
    'application_status', 'interview_scheduled',
    'gate_bypassed', v_can_bypass,
    'stage_override_stamped', v_stamp_override
  );
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5) Escritor 2/7 — recompute_application_status (cron 49): LER o desfecho
-- ─────────────────────────────────────────────────────────────────────────────
-- O laço tinha `IF FOUND THEN <auditar como aplicado>`. Com o gate, o UPDATE ainda ENCONTRA
-- a linha (o BEFORE devolve NEW com o status antigo e `updated_at` novo), então FOUND sozinho
-- deixou de provar que a mudança pousou — e o laço gravaria `selection.status_recomputed`
-- afirmando uma transição que não houve. É a lição de
-- `reference-exception-to-structured-return-flips-consumer-contract`: mudar o contrato sem
-- inventariar os consumidores só move o defeito.
-- Corpo base: o VIVO em 2026-08-05.
CREATE OR REPLACE FUNCTION public.recompute_application_status(
  p_application_id uuid DEFAULT NULL::uuid,
  p_cycle_id uuid DEFAULT NULL::uuid,
  p_dry_run boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_caller_id uuid;
  v_changes jsonb := '[]'::jsonb;
  v_changed int := 0;
  v_suppressed int := 0;
  v_landed text;
  v_evaluated int := 0;
  v_rec record;
  -- pipeline-stage rank used for the forward-only guard
  v_ladder text[] := ARRAY['submitted','screening','objective_eval','objective_cutoff',
                           'interview_pending','interview_scheduled','interview_done','final_eval'];
BEGIN
  -- Auth: authenticated callers need manage_platform. A no-JWT context
  -- (pg_cron / service_role) is the self-healing path and is allowed; anon is
  -- blocked by the GRANT ladder below, not by reaching here.
  IF auth.uid() IS NOT NULL THEN
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'Unauthorized: manage_platform required';
    END IF;
  END IF;

  FOR v_rec IN
    WITH ev AS (
      SELECT application_id,
             count(*) FILTER (WHERE evaluation_type = 'objective' AND submitted_at IS NOT NULL) AS obj_n
      FROM public.selection_evaluations
      GROUP BY application_id
    ),
    iv AS (
      SELECT application_id,
             bool_or(conducted_at IS NOT NULL OR status = 'completed') AS conducted,
             bool_or(status IN ('scheduled','rescheduled'))            AS sched_active,
             bool_or(status NOT IN ('cancelled','noshow'))             AS has_live_row
      FROM public.selection_interviews
      GROUP BY application_id
    ),
    fully AS (
      -- precise: a CONDUCTED interview row whose EVERY assigned interviewer
      -- submitted an interview eval (mirrors submit_interview_scores' completion
      -- gate; avoids advancing a partial 2-interviewer interview to final_eval).
      SELECT DISTINCT a.id
      FROM public.selection_applications a
      JOIN public.selection_interviews si ON si.application_id = a.id
        AND (si.conducted_at IS NOT NULL OR si.status = 'completed')
        AND si.status NOT IN ('cancelled','noshow')
      WHERE COALESCE(array_length(si.interviewer_ids, 1), 0) >= 1
        AND NOT EXISTS (
          SELECT 1 FROM unnest(si.interviewer_ids) AS iid
          WHERE NOT EXISTS (
            SELECT 1 FROM public.selection_evaluations se
            WHERE se.application_id = a.id
              AND se.evaluator_id = iid
              AND se.evaluation_type = 'interview'
              AND se.submitted_at IS NOT NULL
          )
        )
    ),
    cyc_median AS (
      -- #1468: corte objetivo por mediana e researcher-only (alinha a A3/mig 479).
      SELECT cycle_id,
             ROUND((percentile_cont(0.5) WITHIN GROUP (ORDER BY objective_score_avg))::numeric * 0.75, 2) AS cutoff
      FROM public.selection_applications
      WHERE objective_score_avg IS NOT NULL
        AND role_applied = 'researcher'
      GROUP BY cycle_id
    ),
    base AS (
      SELECT a.id, a.applicant_name, a.cycle_id, a.status AS cur,
             c.min_evaluators, cm.cutoff, a.objective_score_avg, a.interview_score,
             COALESCE(ev.obj_n, 0)        AS obj_n,
             COALESCE(iv.conducted, false) AS conducted,
             COALESCE(iv.sched_active, false) AS sched_active,
             COALESCE(iv.has_live_row, false) AS has_live_row,
             (f.id IS NOT NULL)            AS fully_scored
      FROM public.selection_applications a
      JOIN public.selection_cycles c ON c.id = a.cycle_id
      LEFT JOIN ev ON ev.application_id = a.id
      LEFT JOIN iv ON iv.application_id = a.id
      LEFT JOIN cyc_median cm ON cm.cycle_id = a.cycle_id
      LEFT JOIN fully f ON f.id = a.id
      WHERE (p_application_id IS NULL OR a.id = p_application_id)
        AND (p_cycle_id IS NULL OR a.cycle_id = p_cycle_id)
    ),
    canon AS (
      SELECT *,
        CASE
          WHEN fully_scored OR (interview_score IS NOT NULL AND NOT has_live_row) THEN 'final_eval'
          WHEN conducted    THEN 'interview_done'
          WHEN sched_active THEN 'interview_scheduled'
          WHEN obj_n >= min_evaluators AND objective_score_avg IS NOT NULL THEN
            CASE WHEN cutoff > 0 AND objective_score_avg < cutoff THEN 'objective_cutoff'
                 ELSE 'interview_pending' END
          ELSE NULL
        END AS canonical
      FROM base
    ),
    ranked AS (
      SELECT *,
             array_position(v_ladder, cur)       AS cur_r,
             array_position(v_ladder, canonical) AS can_r
      FROM canon
    )
    SELECT id, applicant_name, cycle_id, cur, canonical, obj_n, objective_score_avg,
           interview_score, conducted, sched_active, fully_scored, cutoff
    FROM ranked
    WHERE cur NOT IN ('approved','rejected','converted','withdrawn','cancelled','waitlist','interview_noshow')
      AND canonical IS NOT NULL
      AND canonical <> cur
      AND ( can_r > cur_r
            OR (can_r = cur_r AND cur IN ('objective_cutoff','interview_pending')) )
  LOOP
    IF NOT p_dry_run THEN
      UPDATE public.selection_applications
         SET status = v_rec.canonical, updated_at = now()
       WHERE id = v_rec.id
         AND status = v_rec.cur   -- snapshot guard: skip if changed concurrently
      RETURNING status INTO v_landed;

      IF FOUND THEN
        -- #1613 — o gate de entrada pode ter SUPRIMIDO a transição devolvendo OLD.status.
        -- O UPDATE encontra a linha do mesmo jeito, então ler o status GRAVADO é o que
        -- separa "aplicou" de "foi recusado". O trigger já registrou o porquê.
        IF v_landed IS DISTINCT FROM v_rec.canonical THEN
          v_suppressed := v_suppressed + 1;
          v_changes := v_changes || jsonb_build_object(
            'application_id', v_rec.id,
            'applicant_name', v_rec.applicant_name,
            'cycle_id',       v_rec.cycle_id,
            'from',           v_rec.cur,
            'to',             v_rec.canonical,
            'landed',         v_landed,
            'suppressed',     true
          );
          CONTINUE;
        END IF;

        v_changed := v_changed + 1;
        v_changes := v_changes || jsonb_build_object(
          'application_id', v_rec.id,
          'applicant_name', v_rec.applicant_name,
          'cycle_id',       v_rec.cycle_id,
          'from',           v_rec.cur,
          'to',             v_rec.canonical
        );

        INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
        VALUES (
          v_caller_id,
          'selection.status_recomputed',
          'selection_application',
          v_rec.id,
          jsonb_build_object('status', jsonb_build_object('from', v_rec.cur, 'to', v_rec.canonical)),
          jsonb_build_object(
            'source',   'recompute_application_status',
            'cycle_id', v_rec.cycle_id,
            'facts', jsonb_build_object(
              'objective_evals',        v_rec.obj_n,
              'objective_score_avg',    v_rec.objective_score_avg,
              'interview_score',        v_rec.interview_score,
              'interview_conducted',    v_rec.conducted,
              'interview_scheduled',    v_rec.sched_active,
              'interview_fully_scored', v_rec.fully_scored,
              'objective_cutoff',       v_rec.cutoff
            )
          )
        );
      END IF;
    ELSE
      v_changed := v_changed + 1;
      v_changes := v_changes || jsonb_build_object(
        'application_id', v_rec.id,
        'applicant_name', v_rec.applicant_name,
        'cycle_id',       v_rec.cycle_id,
        'from',           v_rec.cur,
        'to',             v_rec.canonical
      );
    END IF;
  END LOOP;

  SELECT count(*) INTO v_evaluated
  FROM public.selection_applications a
  WHERE (p_application_id IS NULL OR a.id = p_application_id)
    AND (p_cycle_id IS NULL OR a.cycle_id = p_cycle_id);

  RETURN jsonb_build_object(
    'success',    true,
    'dry_run',    p_dry_run,
    'evaluated',  v_evaluated,
    'changed',    v_changed,
    'suppressed', v_suppressed,
    'changes',    v_changes
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.recompute_application_status(uuid,uuid,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.recompute_application_status(uuid,uuid,boolean) TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6) Escritor 3/7 — admin_update_application: reportar o status que POUSOU
-- ─────────────────────────────────────────────────────────────────────────────
-- Devolvia `new_status` = o status PEDIDO. Com a supressão isso vira uma recusa lida como
-- sucesso pelo front. Corpo base: o VIVO em 2026-08-05.
CREATE OR REPLACE FUNCTION public.admin_update_application(
  p_application_id uuid,
  p_data jsonb
)
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
      'member_id',         v_member_id,
      'onboarding_seeded', v_seeded_count,
      'role_promoted',     v_promoted,
      'promoted_to',       CASE WHEN v_promoted THEN v_target_role ELSE NULL END,
      'canonical_invoked', v_canonical_result IS NOT NULL
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
    'canonical',         v_canonical_result
  );
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7) Escritor 4/7 — o calendar-webhook: recusar ANTES de criar o par inconsistente
-- ─────────────────────────────────────────────────────────────────────────────
-- O webhook cria a linha em selection_interviews E promove o status. Com a supressão sobraria
-- entrevista sem candidatura promovida. A correção é a mesma que o RPC canônico já faz desde
-- o #1450: não materializar a entrevista quando a fase objetiva não fechou. Para isso o
-- matcher passa a devolver a nota — a decisão fica JUNTO do match, em vez de exigir uma
-- segunda ida ao banco.
DROP FUNCTION IF EXISTS public.match_booking_application(text);
CREATE FUNCTION public.match_booking_application(p_guest_email text)
RETURNS TABLE (
  application_id      uuid,
  applicant_name      text,
  app_status          text,
  interview_status    text,
  cycle_id            uuid,
  matched_by          text,
  match_outcome       text,
  objective_score_avg numeric,
  interview_materialized boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_guest text;
  v_guest_member_id uuid;
  v_allow text[] := ARRAY['submitted', 'screening', 'objective_eval', 'objective_cutoff',
                          'interview_pending', 'interview_scheduled'];
  v_row record;
BEGIN
  v_guest := NULLIF(LOWER(TRIM(p_guest_email)), '');
  IF v_guest IS NULL THEN
    -- #1611: nunca mais conjunto vazio. Sem e-mail não há como resolver nada,
    -- e isso é indistinguível de "não existe candidatura" para o chamador.
    RETURN QUERY SELECT NULL::uuid, NULL::text, NULL::text, NULL::text, NULL::uuid,
                        NULL::text, 'no_application'::text, NULL::numeric, false;
    RETURN;
  END IF;

  -- alternate-email bridge: resolve the guest email to a member (if any). Um
  -- candidato PODE já ser membro — medido em 2026-08-05, 51 de 81 candidaturas
  -- do ciclo aberto (63%) já têm o e-mail em member_emails —, então esta ponte
  -- não é o caso raro que o comentário anterior supunha. O que ela exige é o
  -- MESMO member_id nos dois lados, o que zera o risco de casar candidatos
  -- diferentes.
  SELECT me.member_id INTO v_guest_member_id
  FROM public.member_emails me
  WHERE me.email = v_guest::citext
  LIMIT 1;

  -- UMA varredura sobre todas as candidaturas que o e-mail resolve (primária ou
  -- alternada do mesmo membro), classificando cada uma e escolhendo a melhor.
  -- A ordenação põe TODAS as candidaturas elegíveis (ciclo aberto/ativo + status
  -- na allow-list) à frente, e só então aplica o desempate herdado da corr-1
  -- (primária > ciclo aberto mais recente > candidatura mais nova) — de modo que
  -- a linha escolhida no caso `matched` é a MESMA que a versão anterior escolhia.
  SELECT a.id,
         a.applicant_name,
         a.status,
         a.interview_status,
         a.cycle_id,
         a.objective_score_avg,
         (CASE WHEN LOWER(TRIM(a.email)) = v_guest THEN 'primary' ELSE 'alternate' END)::text AS matched_by,
         (CASE
            WHEN c.status IN ('open', 'active') AND a.status = ANY (v_allow) THEN 'matched'
            WHEN c.status IN ('open', 'active')                              THEN 'status_not_allowed'
            ELSE                                                                  'cycle_closed'
          END)::text AS match_outcome,
         -- #1613 — "entrevista já materializada": o mesmo sinal que o gate usa para deixar
         -- passar reagendamento. Uma linha recém-criada (status 'scheduled', conducted_at
         -- NULL) NÃO conta, de propósito.
         EXISTS (
           SELECT 1 FROM public.selection_interviews si
           WHERE si.application_id = a.id
             AND ( si.conducted_at IS NOT NULL
                   OR si.status IN ('completed', 'noshow', 'rescheduled', 'cancelled') )
         ) AS interview_materialized
  INTO v_row
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE (
      LOWER(TRIM(a.email)) = v_guest
      OR (
        v_guest_member_id IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM public.member_emails me2
          WHERE me2.member_id = v_guest_member_id
            AND me2.email = LOWER(TRIM(a.email))::citext
        )
      )
    )
  ORDER BY (CASE
              WHEN c.status IN ('open', 'active') AND a.status = ANY (v_allow) THEN 0
              WHEN c.status IN ('open', 'active')                              THEN 1
              ELSE                                                                  2
            END),
           (LOWER(TRIM(a.email)) = v_guest) DESC,
           c.open_date DESC NULLS LAST,
           a.created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN QUERY SELECT NULL::uuid, NULL::text, NULL::text, NULL::text, NULL::uuid,
                        NULL::text, 'no_application'::text, NULL::numeric, false;
    RETURN;
  END IF;

  -- Nos desfechos de recusa a identidade da candidatura VAI JUNTO de propósito:
  -- é o que permite ao GP ver, na fila de exceção, que a reserva foi recusada
  -- CORRETAMENTE (candidatura já decidida) em vez de perdida. O chamador é
  -- service_role apenas, e o gate de promoção continua sendo `match_outcome`.
  RETURN QUERY SELECT v_row.id, v_row.applicant_name, v_row.status, v_row.interview_status,
                      v_row.cycle_id, v_row.matched_by, v_row.match_outcome,
                      v_row.objective_score_avg, v_row.interview_materialized;
END;
$function$;

REVOKE ALL ON FUNCTION public.match_booking_application(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.match_booking_application(text) TO service_role;

-- O contador do #1609 ganha o desfecho novo. Sem isto ele LEVANTA exceção no outcome
-- desconhecido (é o vocabulário incompleto de discriminador que já fabricou órfã antes), e a
-- recusa do webhook viraria 500 — com o Apps Script reenviando a cada 15 min.
CREATE OR REPLACE FUNCTION public.record_booking_attempt(
  p_calendar_event_id text,
  p_guest_email text,
  p_outcome text,
  p_scheduled_at timestamp with time zone DEFAULT NULL::timestamp with time zone
)
RETURNS TABLE (
  attempts        integer,
  should_audit    boolean,
  suppressed      boolean,
  outcome_changed boolean,
  first_seen_at   timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  -- Corte: a partir daqui a tentativa é contada mas não auditada. 10 é o mesmo
  -- teto do Apps Script corrigido, para que os dois lados desistam juntos.
  c_audit_cut constant integer := 10;
  v_event text;
  v_guest text;
  v_prev  public.selection_booking_attempts%ROWTYPE;
  v_row   public.selection_booking_attempts%ROWTYPE;
  v_changed boolean;
  v_just_suppressed boolean;
BEGIN
  v_event := NULLIF(TRIM(p_calendar_event_id), '');
  v_guest := NULLIF(LOWER(TRIM(p_guest_email)), '');
  IF v_event IS NULL OR v_guest IS NULL THEN
    RAISE EXCEPTION 'record_booking_attempt: calendar_event_id e guest_email são obrigatórios';
  END IF;
  IF p_outcome IS NULL OR p_outcome NOT IN ('matched','no_application','status_not_allowed','cycle_closed','objective_phase_incomplete') THEN
    RAISE EXCEPTION 'record_booking_attempt: outcome inválido: %', COALESCE(p_outcome, '<null>');
  END IF;

  SELECT * INTO v_prev
  FROM public.selection_booking_attempts
  WHERE calendar_event_id = v_event AND guest_email = v_guest;

  INSERT INTO public.selection_booking_attempts AS ba (
    calendar_event_id, guest_email, attempts, first_seen_at, last_seen_at,
    last_outcome, outcome_changed_at, last_scheduled_at, resolved_at, suppressed_at
  )
  VALUES (
    v_event, v_guest, 1, now(), now(),
    p_outcome, now(), p_scheduled_at,
    CASE WHEN p_outcome = 'matched' THEN now() ELSE NULL END,
    NULL
  )
  ON CONFLICT (calendar_event_id, guest_email) DO UPDATE SET
    attempts     = ba.attempts + 1,
    last_seen_at = now(),
    last_outcome = EXCLUDED.last_outcome,
    outcome_changed_at = CASE WHEN ba.last_outcome IS DISTINCT FROM EXCLUDED.last_outcome
                              THEN now() ELSE ba.outcome_changed_at END,
    last_scheduled_at  = COALESCE(EXCLUDED.last_scheduled_at, ba.last_scheduled_at),
    resolved_at = CASE WHEN EXCLUDED.last_outcome = 'matched'
                       THEN COALESCE(ba.resolved_at, now()) ELSE ba.resolved_at END,
    -- `matched` ZERA a supressão: se o par voltar a falhar depois de ter casado,
    -- isso é fato novo e merece uma primeira linha de novo.
    suppressed_at = CASE
                      WHEN EXCLUDED.last_outcome = 'matched'    THEN NULL
                      WHEN ba.suppressed_at IS NOT NULL         THEN ba.suppressed_at
                      WHEN ba.attempts + 1 >= c_audit_cut       THEN now()
                      ELSE NULL
                    END
  RETURNING * INTO v_row;

  v_changed := (v_prev.calendar_event_id IS NULL)
               OR (v_prev.last_outcome IS DISTINCT FROM p_outcome);
  v_just_suppressed := (v_prev.suppressed_at IS NULL) AND (v_row.suppressed_at IS NOT NULL);

  -- Política de auditoria — o teto por par é ~5 linhas, contra as ~1.093 de antes:
  --   • a PRIMEIRA aparição do par sempre entra (é o fato "houve uma reserva órfã");
  --   • uma MUDANÇA de desfecho entra enquanto o par não estiver suprimido;
  --   • o disparo do corte entra UMA vez (é o fato "desisti de logar isto");
  --   • depois do corte, só `matched` volta a entrar — que é a resolução.
  should_audit := (v_row.attempts = 1)
                  OR v_just_suppressed
                  OR (v_changed AND (v_prev.suppressed_at IS NULL OR p_outcome = 'matched'));

  attempts        := v_row.attempts;
  suppressed      := v_row.suppressed_at IS NOT NULL;
  outcome_changed := v_changed;
  first_seen_at   := v_row.first_seen_at;
  RETURN NEXT;
END;
$function$;

REVOKE ALL ON FUNCTION public.record_booking_attempt(text,text,text,timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_booking_attempt(text,text,text,timestamptz) TO service_role;

NOTIFY pgrst, 'reload schema';
