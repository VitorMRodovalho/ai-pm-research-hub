-- #1316 (parte C) — get_application_returning_context: derivar contexto de retornante do estado VIVO
--
-- Sintoma: um membro ATIVO que re-candidata (ex. Luciana Dutra, Ciclo 1 Goiás via 62106, hoje
--   researcher ativa) aparece no pipeline como "rejeitado" sem sinalizar que já é membro ativo.
--   Causa: `is_returning_member`/`previous_cycles` são lidos das COLUNAS gravadas em
--   selection_applications, que ficam false/null para quem entrou FORA do fluxo de selection_application
--   (34/99 engagements ativos têm selection_application_id=null). 81 applications casam um membro ativo
--   e TODAS têm is_returning_member≠true; 7 delas são `rejected` (a classe "ativo mostrado como rejeitado").
--
-- Fix: derivar ao vivo (sem backfill de dado):
--   - already_active_member = o membro casado por e-mail está ativo e não offboarded.
--   - previous_cycles = ciclos distintos em que o membro aparece no mirror legado volunteer_applications
--     (fallback = coluna gravada). O front destrava o painel e mostra "já é membro ativo".
--
-- Base: corpo VIVO (pg_get_functiondef); adiciona 2 campos derivados nos 3 branches de retorno.
CREATE OR REPLACE FUNCTION public.get_application_returning_context(p_application_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id           uuid;
  v_can_view_full       boolean;
  v_app                 record;
  v_matched_member      record;
  v_offboard_record     record;
  v_category            record;
  v_already_active      boolean := false;
  v_prev_cycles         jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: not authenticated';
  END IF;

  SELECT public.can_by_member(v_caller_id, 'manage_member') INTO v_can_view_full;
  IF NOT v_can_view_full THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member action';
  END IF;

  -- Look up application by id; require email match for member lookup
  SELECT id, email, applicant_name, cycle_id, status, is_returning_member,
         previous_cycles, application_count
  INTO v_app
  FROM public.selection_applications
  WHERE id = p_application_id;

  IF v_app.id IS NULL THEN
    RETURN jsonb_build_object('found', false, 'application_id', p_application_id);
  END IF;

  -- Match via email (canonicalized lowercase)
  SELECT id, name, chapter, member_status, operational_role, offboarded_at
  INTO v_matched_member
  FROM public.members
  WHERE lower(email) = lower(v_app.email)
  LIMIT 1;

  -- #1316 (C): derivar sinais do estado VIVO do membro + mirror legado, não só das colunas gravadas.
  v_already_active := (v_matched_member.id IS NOT NULL
                       AND v_matched_member.member_status = 'active'
                       AND v_matched_member.offboarded_at IS NULL);
  IF v_matched_member.id IS NOT NULL THEN
    SELECT to_jsonb(array_agg(DISTINCT va.cycle ORDER BY va.cycle))
      INTO v_prev_cycles
      FROM public.volunteer_applications va
      WHERE va.member_id = v_matched_member.id AND va.cycle IS NOT NULL;
  END IF;
  IF v_prev_cycles IS NULL OR v_prev_cycles = 'null'::jsonb THEN
    v_prev_cycles := to_jsonb(v_app.previous_cycles);
  END IF;

  IF v_matched_member.id IS NULL THEN
    -- No prior member match — no offboarding context to return
    RETURN jsonb_build_object(
      'found', true,
      'application_id', p_application_id,
      'is_returning_member', v_app.is_returning_member,
      'already_active_member', false,
      'previous_cycles', v_prev_cycles,
      'application_count', v_app.application_count,
      'matched_member', null,
      'offboarding_context', null
    );
  END IF;

  -- Fetch offboarding record if exists
  SELECT *
  INTO v_offboard_record
  FROM public.member_offboarding_records
  WHERE member_id = v_matched_member.id;

  IF v_offboard_record.id IS NULL THEN
    -- Member exists but no offboarding record (active member re-applying, edge case)
    RETURN jsonb_build_object(
      'found', true,
      'application_id', p_application_id,
      'is_returning_member', v_app.is_returning_member,
      'already_active_member', v_already_active,
      'previous_cycles', v_prev_cycles,
      'application_count', v_app.application_count,
      'matched_member', jsonb_build_object(
        'id', v_matched_member.id,
        'name', v_matched_member.name,
        'chapter', v_matched_member.chapter,
        'member_status', v_matched_member.member_status,
        'operational_role', v_matched_member.operational_role,
        'offboarded_at', v_matched_member.offboarded_at
      ),
      'offboarding_context', null
    );
  END IF;

  -- Resolve category label
  IF v_offboard_record.reason_category_code IS NOT NULL THEN
    SELECT code, label_pt, is_volunteer_fault, preserves_return_eligibility
    INTO v_category
    FROM public.offboard_reason_categories
    WHERE code = v_offboard_record.reason_category_code;
  END IF;

  RETURN jsonb_build_object(
    'found', true,
    'application_id', p_application_id,
    'is_returning_member', v_app.is_returning_member,
    'already_active_member', v_already_active,
    'previous_cycles', v_prev_cycles,
    'application_count', v_app.application_count,
    'matched_member', jsonb_build_object(
      'id', v_matched_member.id,
      'name', v_matched_member.name,
      'chapter', v_matched_member.chapter,
      'member_status', v_matched_member.member_status,
      'operational_role', v_matched_member.operational_role,
      'offboarded_at', v_matched_member.offboarded_at
    ),
    'offboarding_context', jsonb_build_object(
      'record_id', v_offboard_record.id,
      'offboarded_at', v_offboard_record.offboarded_at,
      'offboarded_by', v_offboard_record.offboarded_by,
      'reason_category_code', v_offboard_record.reason_category_code,
      'reason_category_label_pt', v_category.label_pt,
      'is_volunteer_fault', COALESCE(v_category.is_volunteer_fault, false),
      'preserves_return_eligibility', COALESCE(v_category.preserves_return_eligibility, true),
      'reason_detail', v_offboard_record.reason_detail,
      'return_interest', v_offboard_record.return_interest,
      'return_window_suggestion', v_offboard_record.return_window_suggestion,
      'lessons_learned', v_offboard_record.lessons_learned,
      'recommendation_for_future', v_offboard_record.recommendation_for_future,
      'tribe_id_at_offboard', v_offboard_record.tribe_id_at_offboard,
      'cycle_code_at_offboard', v_offboard_record.cycle_code_at_offboard,
      'has_full_interview', v_offboard_record.exit_interview_full_text IS NOT NULL
    )
  );
END;
$function$
;
