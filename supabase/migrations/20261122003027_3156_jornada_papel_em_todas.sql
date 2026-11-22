-- #3156: os leitores e escritores da jornada que ainda recortavam as etapas pelo cache de autoridade
-- (members.operational_role) passam a usar o papel da jornada, _onboarding_journey_role (#3152).
-- Quem está antes do Termo é guest no cache, e por isso o clique, o fechamento pela gestão, o progresso do candidato,
-- o painel e o gatilho de presença na tribo tratavam a jornada dessa pessoa como vazia.
-- A autoridade não muda: can(), _derive_operational_role e o cache ficam como estão.
-- Ficam de fora, com o motivo no guard: approve_selection_application (recorta pelo papel-alvo da candidatura) e
-- get_affiliation_verification_queue (filiação, de outra lane).
-- Cada corpo é a captura cujo md5 bate com o vivo em 21/11, mudando só a leitura do papel.

CREATE OR REPLACE FUNCTION public.complete_onboarding_step(p_step_id text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_member_role text;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  -- #3156: o recorte de etapa usa o papel da jornada (#3152), não o cache de autoridade.
  v_member_role := public._onboarding_journey_role(v_member_id);
  IF NOT EXISTS (
    SELECT 1 FROM onboarding_steps s
    WHERE s.id = p_step_id
      AND public.onboarding_step_applies(s.applies_to_role, v_member_role)
  ) THEN
    RETURN jsonb_build_object('error', 'Invalid step'); END IF;
  -- Jornadas fatia B: etapa que fecha por fato (onboarding_steps.closed_by) não fecha por clique.
  IF EXISTS (SELECT 1 FROM onboarding_steps s WHERE s.id = p_step_id AND s.closed_by = 'fact') THEN
    RETURN jsonb_build_object('error', 'step_closed_by_fact', 'step_id', p_step_id);
  END IF;
  INSERT INTO onboarding_progress (member_id, step_key, status, completed_at, metadata, updated_at)
  VALUES (v_member_id, p_step_id, 'completed', now(), p_metadata, now())
  ON CONFLICT (member_id, step_key) DO UPDATE SET
    status = 'completed', completed_at = now(),
    metadata = COALESCE(p_metadata, onboarding_progress.metadata), updated_at = now();
  RETURN jsonb_build_object('success', true, 'step_id', p_step_id);
END; $function$;

CREATE OR REPLACE FUNCTION public.get_candidate_onboarding_progress(p_member_id uuid DEFAULT NULL::uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_mid uuid;
  v_caller uuid;
  v_member_role text;
  v_result json;
BEGIN
  SELECT id INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated');
  END IF;

  v_mid := COALESCE(p_member_id, v_caller);

  IF v_mid <> v_caller
     AND NOT public.can_by_member(v_caller, 'write', NULL, NULL)
     AND NOT public.can_by_member(v_caller, 'manage_member', NULL, NULL) THEN
    RETURN json_build_object('error', 'Unauthorized');
  END IF;

  -- #3156: o recorte de etapa usa o papel da jornada (#3152), não o cache de autoridade.
  v_member_role := public._onboarding_journey_role(v_mid);

  -- First run auto-detection
  PERFORM check_pre_onboarding_auto_steps(v_mid);

  SELECT json_build_object(
    'member_id', v_mid,
    'steps', coalesce((
      SELECT json_agg(json_build_object(
        'step_key', op.step_key,
        'status', op.status,
        'completed_at', op.completed_at,
        'sla_deadline', op.sla_deadline,
        'xp', coalesce((op.metadata->>'xp')::int, 0),
        'phase', coalesce(op.metadata->>'phase', 'onboarding')
      ) ORDER BY
        CASE op.step_key
          WHEN 'create_account' THEN 1
          WHEN 'complete_profile' THEN 2
          WHEN 'setup_credly' THEN 3
          WHEN 'explore_platform' THEN 4
          WHEN 'read_blog' THEN 5
          WHEN 'start_pmi_certs' THEN 6
          WHEN 'code_of_conduct' THEN 7
          WHEN 'volunteer_term' THEN 8
          WHEN 'vep_acceptance' THEN 9
          WHEN 'first_meeting' THEN 10
          WHEN 'meet_tribe' THEN 11
          WHEN 'start_trail' THEN 12
          ELSE 99
        END
      )
      FROM onboarding_progress op
      WHERE op.member_id = v_mid
    ), '[]'::json),
    'pre_onboarding', json_build_object(
      'total', (SELECT count(*) FROM onboarding_progress WHERE member_id = v_mid AND metadata->>'phase' = 'pre_onboarding'),
      'completed', (SELECT count(*) FROM onboarding_progress WHERE member_id = v_mid AND metadata->>'phase' = 'pre_onboarding' AND status = 'completed'),
      'xp_earned', coalesce((SELECT sum((metadata->>'xp')::int) FROM onboarding_progress WHERE member_id = v_mid AND metadata->>'phase' = 'pre_onboarding' AND status = 'completed'), 0),
      'xp_total', coalesce((SELECT sum((metadata->>'xp')::int) FROM onboarding_progress WHERE member_id = v_mid AND metadata->>'phase' = 'pre_onboarding'), 0)
    ),
    'onboarding', json_build_object(
      'total', (SELECT count(*) FROM onboarding_progress WHERE member_id = v_mid
        AND step_key IN (SELECT id FROM onboarding_steps s WHERE public.onboarding_step_applies(s.applies_to_role, v_member_role))),
      'completed', (SELECT count(*) FROM onboarding_progress WHERE member_id = v_mid
        AND step_key IN (SELECT id FROM onboarding_steps s WHERE public.onboarding_step_applies(s.applies_to_role, v_member_role))
        AND status IN ('completed', 'skipped'))
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_complete_onboarding_step(p_member_id uuid, p_step_key text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_role text;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: manage_platform required' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_note IS NULL OR length(btrim(p_note)) < 3 THEN
    RAISE EXCEPTION 'A written reason is required' USING ERRCODE = 'check_violation';
  END IF;
  -- #3156: o recorte de etapa usa o papel da jornada (#3152); o NOT FOUND continua dizendo se o membro existe.
  SELECT public._onboarding_journey_role(m.id) INTO v_role FROM members m WHERE m.id = p_member_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Member not found' USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM onboarding_steps s
                 WHERE s.id = p_step_key AND public.onboarding_step_applies(s.applies_to_role, v_role)) THEN
    RAISE EXCEPTION 'Step % does not apply to this member', p_step_key USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO onboarding_progress (member_id, step_key, status, completed_at, metadata, updated_at)
  VALUES (p_member_id, p_step_key, 'completed', now(),
          jsonb_build_object('closed_by', 'gp', 'gp_member_id', v_caller_id, 'gp_note', btrim(p_note), 'gp_at', now()),
          now())
  ON CONFLICT (member_id, step_key) DO UPDATE SET
    status = 'completed', completed_at = now(),
    metadata = COALESCE(onboarding_progress.metadata, '{}'::jsonb)
      || jsonb_build_object('closed_by', 'gp', 'gp_member_id', v_caller_id, 'gp_note', btrim(p_note), 'gp_at', now()),
    updated_at = now();

  RETURN jsonb_build_object('success', true, 'member_id', p_member_id, 'step_key', p_step_key);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_onboarding_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller_id uuid; v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform'::text) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- #3156: o recorte de etapa usa o papel da jornada (#3152), lido uma vez por membro.
  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total_members', (SELECT count(*) FROM members WHERE is_active AND current_cycle_active),
      'fully_onboarded', (SELECT count(DISTINCT m.id) FROM members m
        CROSS JOIN LATERAL (SELECT public._onboarding_journey_role(m.id) AS journey_role) jr
        WHERE m.is_active AND m.current_cycle_active
        AND NOT EXISTS (SELECT 1 FROM onboarding_steps s JOIN onboarding_progress op ON op.step_key = s.id AND op.member_id = m.id
          WHERE s.is_required AND op.status != 'completed'
            AND public.onboarding_step_applies(s.applies_to_role, jr.journey_role))
        AND EXISTS (SELECT 1 FROM onboarding_progress op2 WHERE op2.member_id = m.id)),
      'not_started', (SELECT count(DISTINCT m.id) FROM members m
        WHERE m.is_active AND m.current_cycle_active
        AND NOT EXISTS (SELECT 1 FROM onboarding_progress op WHERE op.member_id = m.id AND op.status = 'completed'))
    ),
    'members', (SELECT jsonb_agg(row_to_json(t) ORDER BY t.completed_count ASC, t.name) FROM (
      SELECT m.id, m.name, m.photo_url, m.chapter, m.tribe_id,
        (SELECT count(*) FROM onboarding_progress op WHERE op.member_id = m.id AND op.status = 'completed'
          AND op.step_key IN (SELECT id FROM onboarding_steps s WHERE public.onboarding_step_applies(s.applies_to_role, jr.journey_role))) AS completed_count,
        (SELECT count(*) FROM onboarding_steps s WHERE s.is_required
          AND public.onboarding_step_applies(s.applies_to_role, jr.journey_role)) AS total_steps,
        (SELECT max(op.updated_at) FROM onboarding_progress op WHERE op.member_id = m.id) AS last_activity
      FROM members m
      CROSS JOIN LATERAL (SELECT public._onboarding_journey_role(m.id) AS journey_role) jr
      WHERE m.is_active AND m.current_cycle_active
    ) t)
  ) INTO v_result;
  RETURN v_result;
END; $function$;

CREATE OR REPLACE FUNCTION public._trg_complete_meet_tribe_on_presence()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  -- #3156: o recorte usa o papel da jornada (#3152).
  -- #2718 regra 1. O lote diário é o gêmeo que pega correção de presença feita por fora deste gatilho.
  UPDATE public.onboarding_progress op
     SET status = 'completed', completed_at = now(), updated_at = now(),
         metadata = COALESCE(op.metadata, '{}'::jsonb) || jsonb_build_object('completed_via', '2718_presenca_na_tribo')
   WHERE op.member_id = NEW.member_id
     AND op.step_key = 'meet_tribe'
     AND op.status IN ('pending', 'overdue')
     AND EXISTS (SELECT 1 FROM public.members m
                 JOIN public.onboarding_steps s ON s.id = 'meet_tribe'
                 JOIN public.events e ON e.id = NEW.event_id
                 JOIN public.initiatives i ON i.id = e.initiative_id
                 WHERE m.id = NEW.member_id
                   AND i.legacy_tribe_id = m.tribe_id
                   AND public.onboarding_step_applies(s.applies_to_role, public._onboarding_journey_role(m.id)));
  RETURN NEW;
END; $function$;

NOTIFY pgrst, 'reload schema';
