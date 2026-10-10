-- /cpmai: Grupo de Estudos CPMAI · Piloto, só para participantes e gestão (decisão do GP, 09/10/2026).
--
-- Antes (medido em 09/10/2026):
--   * /cpmai estava no menu do visitante; anon lia get_public_cpmai_course (#2555, de 08/10).
--   * qualquer membro se autoinscrevia por join_initiative, que NÃO lia initiatives.join_policy: valia
--     para qualquer iniciativa, inclusive as 40 'invite_only' (das 41, só o CPMAI era 'request_to_join';
--     nenhuma 'open'). Engajamentos com a marca de motivation de join_initiative: 5, sendo 4 da carga de
--     23/05 e 1 autoinscrição no CPMAI em 10/07 (hoje expired). Nenhum em iniciativa fechada.
--   * get_cpmai_course_dashboard devolvia sessões (com meeting_link) e o contador a qualquer membro.
--
-- Agora:
--   (1) a iniciativa CPMAI passa a 'invite_only' (entrada pela gestão), por configuração, não por id no código;
--   (2) join_initiative recusa autoinscrição fora de join_policy = 'open' (vale para todas as iniciativas);
--   (3) get_cpmai_course_dashboard: só engajados na iniciativa (ativo/onboarding) e manage_platform, e o
--       portão da ADR-0105;
--   (4) get_public_cpmai_course: sem EXECUTE para PUBLIC, anon e authenticated (só /cpmai a chamava).
-- Os corpos partem dos vivos de 09/10/2026, idênticos às capturas 20260685000000 (join_initiative,
-- md5 a836a5f94c28e6ba4dc5a3ddddcc168c) e 20260684000000 (get_cpmai_course_dashboard,
-- md5 82e3f91a8ac4eb59a3fd0a29d2c86fbc). Assinatura, SECURITY DEFINER e search_path mantidos.
--
-- Rollback: join_policy do CPMAI de volta a 'request_to_join'; recriar as duas funções pelas capturas
--   citadas; GRANT EXECUTE ON FUNCTION public.get_public_cpmai_course() TO anon, authenticated.

UPDATE public.initiatives SET join_policy = 'invite_only', updated_at = now()
WHERE id = '2f5846f3-5b6b-4ce1-9bc6-e07bdb22cd19' AND join_policy = 'request_to_join';

CREATE OR REPLACE FUNCTION public.join_initiative(p_initiative_id uuid, p_motivation text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_person_id uuid; v_member_id uuid; v_initiative record; v_kind_row record;
  v_default_engagement_kind text; v_engagement_id uuid; v_current_count integer;
BEGIN
  SELECT m.id, m.person_id INTO v_member_id, v_person_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_person_id IS NULL THEN RAISE EXCEPTION 'Not authenticated or no person record' USING ERRCODE = 'P0002'; END IF;
  SELECT * INTO v_initiative FROM public.initiatives WHERE id = p_initiative_id;
  IF v_initiative IS NULL THEN RAISE EXCEPTION 'Initiative not found: %', p_initiative_id USING ERRCODE = 'P0002'; END IF;
  -- Autoinscrição direta só onde a iniciativa declara join_policy = 'open'. 'request_to_join' passa por
  -- request_to_join_initiative (pedido que a liderança revisa); 'invite_only' entra pela gestão.
  IF v_initiative.join_policy IS DISTINCT FROM 'open' THEN
    RAISE EXCEPTION 'Self-enrollment not allowed for this initiative (join_policy=%)', v_initiative.join_policy
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO v_kind_row FROM public.initiative_kinds WHERE slug = v_initiative.kind;
  IF (v_initiative.metadata->>'max_enrollment') IS NOT NULL THEN
    SELECT count(*) INTO v_current_count FROM public.engagements WHERE initiative_id = p_initiative_id AND status IN ('active', 'onboarding');
    IF v_current_count >= (v_initiative.metadata->>'max_enrollment')::integer THEN
      RAISE EXCEPTION 'Initiative is at capacity' USING ERRCODE = 'P0005';
    END IF;
  END IF;
  IF EXISTS (SELECT 1 FROM public.engagements WHERE person_id = v_person_id AND initiative_id = p_initiative_id AND status IN ('active', 'onboarding')) THEN
    RAISE EXCEPTION 'Already enrolled in this initiative' USING ERRCODE = 'P0009';
  END IF;
  IF array_length(v_kind_row.allowed_engagement_kinds, 1) = 1 THEN
    v_default_engagement_kind := v_kind_row.allowed_engagement_kinds[1];
  ELSE
    SELECT ek INTO v_default_engagement_kind FROM unnest(v_kind_row.allowed_engagement_kinds) ek WHERE ek != ALL(v_kind_row.required_engagement_kinds) LIMIT 1;
    IF v_default_engagement_kind IS NULL THEN v_default_engagement_kind := v_kind_row.allowed_engagement_kinds[1]; END IF;
  END IF;
  INSERT INTO public.engagements (person_id, initiative_id, kind, role, status, metadata, organization_id)
  VALUES (v_person_id, p_initiative_id, v_default_engagement_kind, 'participant', 'active', jsonb_build_object('motivation', p_motivation) || p_metadata, public.auth_org())
  RETURNING id INTO v_engagement_id;
  RETURN v_engagement_id;
END;

$function$;

CREATE OR REPLACE FUNCTION public.get_cpmai_course_dashboard(p_course_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid; v_person_id uuid; v_initiative_id uuid; v_initiative record; v_result jsonb;
BEGIN
  SELECT m.id, m.person_id INTO v_member_id, v_person_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member_id IS NULL THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  IF p_course_id IS NOT NULL THEN
    SELECT * INTO v_initiative FROM public.initiatives WHERE metadata->>'cpmai_legacy_course_id' = p_course_id::text AND kind = 'study_group';
  ELSE
    SELECT * INTO v_initiative FROM public.initiatives WHERE kind = 'study_group' AND status != 'archived' ORDER BY created_at DESC LIMIT 1;
  END IF;
  IF v_initiative IS NULL THEN RETURN jsonb_build_object('error', 'No course found'); END IF;
  -- Só quem está engajado na iniciativa (ativo ou em onboarding) e a gestão veem o grupo: o painel traz
  -- sessões com link de reunião e progresso. Nunca a iniciativa confidencial a quem não a enxerga.
  IF NOT public.rls_can_see_initiative(v_initiative.id)
     OR NOT (public.can_by_member(v_member_id, 'manage_platform')
             OR EXISTS (SELECT 1 FROM public.engagements e
                        WHERE e.initiative_id = v_initiative.id AND e.person_id = v_person_id
                          AND e.status IN ('active', 'onboarding'))) THEN
    RETURN jsonb_build_object('error', 'forbidden');
  END IF;
  v_initiative_id := v_initiative.id;
  SELECT jsonb_build_object(
    'course', jsonb_build_object('id', v_initiative.id, 'title', v_initiative.title, 'description', v_initiative.description, 'status', v_initiative.status,
      'max_capacity', (v_initiative.metadata->>'max_enrollment')::integer, 'enrollment_deadline', v_initiative.metadata->>'enrollment_deadline',
      'start_date', v_initiative.metadata->>'start_date', 'end_date', v_initiative.metadata->>'end_date',
      'min_attendance_pct', (v_initiative.metadata->>'min_attendance_pct')::numeric, 'min_mock_score', (v_initiative.metadata->>'min_mock_score')::numeric),
    'domains', COALESCE(v_initiative.metadata->'domains', '[]'::jsonb),
    'my_enrollment', (SELECT jsonb_build_object('id', e.id, 'status', e.status, 'enrolled_at', e.start_date, 'completed_at', e.end_date, 'certificate_issued_at', NULL)
      FROM public.engagements e WHERE e.initiative_id = v_initiative_id AND e.person_id = v_person_id AND e.kind IN ('study_group_participant', 'study_group_owner') LIMIT 1),
    'my_progress', COALESCE((SELECT jsonb_agg(jsonb_build_object('module_id', p.payload->>'module_id', 'status', p.payload->>'status', 'completed_at', p.payload->>'completed_at'))
      FROM public.initiative_member_progress p WHERE p.initiative_id = v_initiative_id AND p.person_id = v_person_id AND p.progress_type = 'module_completion'), '[]'::jsonb),
    'my_mock_scores', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', p.id, 'score_pct', (p.payload->>'score_pct')::numeric, 'total_questions', (p.payload->>'total_questions')::integer,
      'correct_answers', (p.payload->>'correct_answers')::integer, 'mock_source', p.payload->>'mock_source', 'taken_at', p.recorded_at) ORDER BY p.recorded_at DESC)
      FROM public.initiative_member_progress p WHERE p.initiative_id = v_initiative_id AND p.person_id = v_person_id AND p.progress_type = 'mock_score'), '[]'::jsonb),
    'upcoming_sessions', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', ev.id, 'title', ev.title, 'session_type', ev.type, 'scheduled_at', ev.date,
      'duration_minutes', ev.duration_minutes, 'external_url', ev.meeting_link, 'recording_url', NULL, 'domain_id', NULL) ORDER BY ev.date)
      FROM public.events ev WHERE ev.initiative_id = v_initiative_id AND ev.date >= now() - interval '1 day'), '[]'::jsonb),
    'enrollment_count', (SELECT count(*) FROM public.engagements WHERE initiative_id = v_initiative_id AND kind IN ('study_group_participant', 'study_group_owner') AND status IN ('active', 'offboarded'))
  ) INTO v_result;
  RETURN v_result;
END;

$function$;

REVOKE ALL ON FUNCTION public.get_public_cpmai_course() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_cpmai_course() TO service_role;

-- ── pós-condição: aborta a migration inteira se algo saiu errado ─────────────
DO $postcondition$
BEGIN
  IF (SELECT join_policy FROM public.initiatives WHERE id = '2f5846f3-5b6b-4ce1-9bc6-e07bdb22cd19') <> 'invite_only' THEN
    RAISE EXCEPTION 'cpmai: a iniciativa não ficou invite_only';
  END IF;
  IF has_function_privilege('anon', 'public.get_public_cpmai_course()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.get_public_cpmai_course()', 'EXECUTE') THEN
    RAISE EXCEPTION 'cpmai: get_public_cpmai_course segue executável por anon ou authenticated';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.pronamespace = 'public'::regnamespace
                 AND p.proname = 'join_initiative' AND p.prosecdef
                 AND p.proconfig @> ARRAY['search_path=public, pg_temp']
                 AND p.prosrc LIKE '%join_policy IS DISTINCT FROM ''open''%') THEN
    RAISE EXCEPTION 'cpmai: join_initiative sem a checagem de join_policy, SECURITY DEFINER ou search_path';
  END IF;
END
$postcondition$;

NOTIFY pgrst, 'reload schema';
