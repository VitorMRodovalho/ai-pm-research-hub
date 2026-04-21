-- ============================================================================
-- ADR-0015 Phase 3e follow-up #2 — sweep de 5 RPCs com refs stale a events.tribe_id
--
-- Contexto:
--   Phase 3e (commit 4d2a10d, migration 20260428050000) dropou events.tribe_id
--   em 2026-04-18. Batch B (20260427150000) auditou prosrc olhando apenas
--   cláusulas UPDATE SET e classificou 6 funções como no-op (header lines 13-22).
--   A auditoria ignorou refs em SELECT ... INTO e WHERE que fazem tribe-scope
--   enforcement. Stragglers (20260428180000) cobriu 7 funções mas deixou 5
--   afetadas que só são descobertas em execução. Sweep anterior (20260505010000)
--   focou em project_boards/board_items e também não cobriu essas funções.
--
-- Bug reportado (issue #79): chamar update_event_instance retornou
-- `ERROR 42703: column "tribe_id" does not exist` em tentativa de mover evento
-- Tribo 06 de 22/04 → 24/04 via MCP em 2026-04-20.
--
-- Funções refatoradas (todas preservando signature, semântica, return shape):
--   1. update_event_instance        (SELECT + WHERE stale)
--   2. update_future_events_in_group (SELECT stale)
--   3. drop_event_instance          (SELECT stale)
--   4. generate_agenda_template     (WHERE stale)
--   5. admin_bulk_mark_attendance   (SELECT stale no caminho tribe_leader)
--
-- Padrão de fix (canônico, idêntico a 20260428180000 e 20260505010000):
--   - Derivar legacy_tribe_id via events.initiative_id → initiatives.legacy_tribe_id
--   - Manter NULL semantics: eventos sem initiative_id (ex.: geral) resolvem
--     para legacy_tribe_id = NULL, replicando o comportamento pre-Phase 3e
--     em que events.tribe_id era NULL para events.type='geral'.
--
-- Scope: 5/5 funções. Sweep completo de refs stale a events.tribe_id em prod
-- (confirmado via pg_proc + regex varredura em 14 tabelas que tiveram tribe_id
-- dropado). check_schema_invariants() 11/11 limpo antes e depois.
--
-- Rollback: re-apply migrations 20260409010000, 20260421020000, 20260424040000
-- (restaura bodies pre-fix via CREATE OR REPLACE) — mas continuará quebrado
-- enquanto events.tribe_id não for recriado.
--
-- ADR: ADR-0015 (domain_model_v4), ADR-0011 (auth pattern preservado).
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. update_event_instance — SELECT + EXISTS refactored
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.update_event_instance(
  p_event_id uuid,
  p_new_date date DEFAULT NULL::date,
  p_new_time_start time without time zone DEFAULT NULL::time without time zone,
  p_new_duration_minutes integer DEFAULT NULL::integer,
  p_meeting_link text DEFAULT NULL::text,
  p_notes text DEFAULT NULL::text,
  p_agenda_text text DEFAULT NULL::text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_caller_tribe int;
  v_event_tribe int;
  v_event_exists boolean;
  v_updated text[] := '{}';
BEGIN
  SELECT id, operational_role, tribe_id INTO v_caller_id, v_caller_role, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT true, i.legacy_tribe_id
    INTO v_event_exists, v_event_tribe
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.id = p_event_id;
  IF v_event_exists IS NOT TRUE THEN RAISE EXCEPTION 'Event not found'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event permission';
  END IF;
  IF v_caller_role = 'tribe_leader' AND v_caller_tribe IS DISTINCT FROM v_event_tribe THEN
    RAISE EXCEPTION 'Unauthorized: tribe_leader can only manage events of own tribe';
  END IF;

  IF p_new_date IS NOT NULL THEN
    IF v_event_tribe IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.events e2
      JOIN public.initiatives i2 ON i2.id = e2.initiative_id
      WHERE i2.legacy_tribe_id = v_event_tribe
        AND e2.date = p_new_date
        AND e2.id <> p_event_id
    ) THEN
      RAISE EXCEPTION 'Ja existe um evento desta tribo na data %', p_new_date;
    END IF;
    UPDATE public.events SET date = p_new_date, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'date');
  END IF;
  IF p_new_time_start IS NOT NULL THEN
    UPDATE public.events SET time_start = p_new_time_start, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'time_start');
  END IF;
  IF p_new_duration_minutes IS NOT NULL THEN
    UPDATE public.events SET duration_minutes = p_new_duration_minutes, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'duration_minutes');
  END IF;
  IF p_meeting_link IS NOT NULL THEN
    UPDATE public.events SET meeting_link = p_meeting_link, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'meeting_link');
  END IF;
  IF p_notes IS NOT NULL THEN
    UPDATE public.events SET notes = p_notes, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'notes');
  END IF;
  IF p_agenda_text IS NOT NULL THEN
    UPDATE public.events SET agenda_text = p_agenda_text, updated_at = now() WHERE id = p_event_id;
    v_updated := array_append(v_updated, 'agenda_text');
  END IF;

  RETURN json_build_object(
    'success', true,
    'event_id', p_event_id,
    'updated_fields', to_json(v_updated)
  );
END;
$function$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. update_future_events_in_group — SELECT refactored
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.update_future_events_in_group(
  p_event_id uuid,
  p_new_time_start time without time zone DEFAULT NULL::time without time zone,
  p_duration_minutes integer DEFAULT NULL::integer,
  p_meeting_link text DEFAULT NULL::text,
  p_notes text DEFAULT NULL::text,
  p_visibility text DEFAULT NULL::text,
  p_type text DEFAULT NULL::text,
  p_nature text DEFAULT NULL::text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_caller_tribe int;
  v_event_tribe int;
  v_event_date date;
  v_rec_group uuid;
  v_updated_count int;
BEGIN
  SELECT id, operational_role, tribe_id INTO v_caller_id, v_caller_role, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT i.legacy_tribe_id, e.date, e.recurrence_group
    INTO v_event_tribe, v_event_date, v_rec_group
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.id = p_event_id;
  IF v_event_date IS NULL THEN RAISE EXCEPTION 'Event not found'; END IF;
  IF v_rec_group IS NULL THEN RAISE EXCEPTION 'Event is not part of a recurring series'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event permission';
  END IF;
  IF v_caller_role = 'tribe_leader' AND v_caller_tribe IS DISTINCT FROM v_event_tribe THEN
    RAISE EXCEPTION 'Unauthorized: tribe_leader can only manage events of own tribe';
  END IF;

  IF p_type IS NOT NULL AND p_type NOT IN ('geral','tribo','lideranca','kickoff','comms','parceria','entrevista','1on1','evento_externo','webinar') THEN
    RAISE EXCEPTION 'Invalid event type: %', p_type;
  END IF;
  IF p_nature IS NOT NULL AND p_nature NOT IN ('kickoff','recorrente','avulsa','encerramento','workshop','entrevista_selecao') THEN
    RAISE EXCEPTION 'Invalid event nature: %', p_nature;
  END IF;

  WITH updated AS (
    UPDATE public.events SET
      time_start = COALESCE(p_new_time_start, time_start),
      duration_minutes = COALESCE(p_duration_minutes, duration_minutes),
      meeting_link = COALESCE(p_meeting_link, meeting_link),
      notes = COALESCE(p_notes, notes),
      visibility = COALESCE(p_visibility, visibility),
      type = COALESCE(p_type, type),
      nature = COALESCE(p_nature, nature),
      updated_at = now()
    WHERE recurrence_group = v_rec_group AND date >= v_event_date
    RETURNING id
  )
  SELECT count(*) INTO v_updated_count FROM updated;

  RETURN json_build_object(
    'success', true,
    'recurrence_group', v_rec_group,
    'anchor_date', v_event_date,
    'updated_count', v_updated_count
  );
END;
$function$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. drop_event_instance — SELECT refactored
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.drop_event_instance(
  p_event_id uuid,
  p_force_delete_attendance boolean DEFAULT false
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_caller_tribe int;
  v_event_tribe int;
  v_event_date date;
  v_event_title text;
  v_att_count int;
  v_blocker text;
BEGIN
  SELECT id, operational_role, tribe_id INTO v_caller_id, v_caller_role, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT i.legacy_tribe_id, e.date, e.title
    INTO v_event_tribe, v_event_date, v_event_title
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.id = p_event_id;
  IF v_event_date IS NULL THEN RAISE EXCEPTION 'Event not found'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event permission';
  END IF;
  IF v_caller_role = 'tribe_leader' AND v_caller_tribe IS DISTINCT FROM v_event_tribe THEN
    RAISE EXCEPTION 'Unauthorized: tribe_leader can only manage events of own tribe';
  END IF;

  SELECT count(*) INTO v_att_count FROM public.attendance WHERE event_id = p_event_id;
  IF v_att_count > 0 AND NOT p_force_delete_attendance THEN
    RAISE EXCEPTION 'attendance_exists:%', v_att_count
      USING HINT = 'Evento possui ' || v_att_count || ' presença(s) registrada(s). Re-chame com p_force_delete_attendance=true para remover.';
  END IF;

  v_blocker := '';
  IF EXISTS (SELECT 1 FROM public.meeting_artifacts WHERE event_id = p_event_id) THEN v_blocker := v_blocker || 'meeting_artifacts, '; END IF;
  IF EXISTS (SELECT 1 FROM public.cost_entries WHERE event_id = p_event_id) THEN v_blocker := v_blocker || 'cost_entries, '; END IF;
  IF EXISTS (SELECT 1 FROM public.cpmai_sessions WHERE event_id = p_event_id) THEN v_blocker := v_blocker || 'cpmai_sessions, '; END IF;
  IF EXISTS (SELECT 1 FROM public.webinars WHERE event_id = p_event_id) THEN v_blocker := v_blocker || 'webinars, '; END IF;
  IF EXISTS (SELECT 1 FROM public.event_showcases WHERE event_id = p_event_id) THEN v_blocker := v_blocker || 'event_showcases, '; END IF;
  IF EXISTS (SELECT 1 FROM public.meeting_action_items WHERE carried_to_event_id = p_event_id) THEN v_blocker := v_blocker || 'meeting_action_items (carried_to), '; END IF;
  IF v_blocker <> '' THEN
    v_blocker := rtrim(v_blocker, ', ');
    RAISE EXCEPTION 'Evento possui dependencias que impedem a exclusao: %', v_blocker;
  END IF;

  IF v_att_count > 0 AND p_force_delete_attendance THEN
    DELETE FROM public.attendance WHERE event_id = p_event_id;
  END IF;
  DELETE FROM public.events WHERE id = p_event_id;

  RETURN json_build_object(
    'success', true,
    'deleted_event_id', p_event_id,
    'deleted_date', v_event_date,
    'deleted_title', v_event_title,
    'deleted_attendance_count', COALESCE(v_att_count, 0),
    'force_used', p_force_delete_attendance
  );
END;
$function$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. generate_agenda_template — WHERE refactored
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.generate_agenda_template(p_tribe_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_last_event record;
  v_template text;
  v_actions text;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  IF v_caller.is_superadmin IS NOT TRUE
     AND v_caller.operational_role NOT IN ('manager', 'deputy_manager')
     AND NOT (v_caller.operational_role = 'tribe_leader' AND v_caller.tribe_id = p_tribe_id) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT e.* INTO v_last_event
  FROM public.events e
  JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE i.legacy_tribe_id = p_tribe_id
    AND e.date < CURRENT_DATE
    AND e.type IN ('tribo', 'kickoff')
  ORDER BY e.date DESC
  LIMIT 1;

  SELECT string_agg(
    '- [ ] ' || ai.description
      || COALESCE(' (@' || ai.assignee_name || ')', '')
      || COALESCE(' — prazo: ' || ai.due_date::text, ''),
    E'\n'
  ) INTO v_actions
  FROM public.meeting_action_items ai
  WHERE ai.event_id = v_last_event.id AND ai.status = 'open';

  v_template := '## Pauta da Reunião' || E'\n\n' || '### 1. Abertura e check-in' || E'\n\n';
  IF v_actions IS NOT NULL THEN
    v_template := v_template || '### 2. Revisão de ações pendentes' || E'\n' || v_actions || E'\n\n';
  ELSE
    v_template := v_template || '### 2. Revisão da reunião anterior' || E'\n\n';
  END IF;
  v_template := v_template
    || '### 3. Tópicos da semana' || E'\n- ' || E'\n\n'
    || '### 4. Próximos passos e ações' || E'\n- [ ] ' || E'\n\n'
    || '### 5. Encerramento' || E'\n';

  RETURN jsonb_build_object(
    'success', true,
    'template', v_template,
    'last_event_title', v_last_event.title,
    'last_event_date', v_last_event.date,
    'open_actions_count', COALESCE(array_length(string_to_array(v_actions, E'\n'), 1), 0)
  );
END;
$function$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. admin_bulk_mark_attendance — SELECT refactored (caminho tribe_leader)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_bulk_mark_attendance(
  p_event_id uuid,
  p_member_ids uuid[],
  p_present boolean
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_event_tribe_id int;
  v_count int := 0;
  v_mid uuid;
BEGIN
  SELECT id, operational_role, is_superadmin, tribe_id
  INTO v_caller
  FROM public.members WHERE auth_id = auth.uid();

  IF NOT (v_caller.is_superadmin IS TRUE OR v_caller.operational_role IN ('manager', 'deputy_manager', 'tribe_leader')) THEN
    RETURN json_build_object('success', false, 'error', 'permission_denied');
  END IF;

  IF v_caller.operational_role = 'tribe_leader' AND v_caller.is_superadmin IS NOT TRUE THEN
    SELECT i.legacy_tribe_id INTO v_event_tribe_id
    FROM public.events e
    LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.id = p_event_id;

    IF v_event_tribe_id IS NOT NULL AND v_event_tribe_id != v_caller.tribe_id THEN
      RETURN json_build_object('success', false, 'error', 'not_your_tribe',
        'message', 'Líderes só podem ajustar presença de eventos da própria tribo.');
    END IF;
  END IF;

  IF p_present THEN
    FOREACH v_mid IN ARRAY p_member_ids LOOP
      INSERT INTO public.attendance (event_id, member_id, checked_in_at, marked_by)
      VALUES (p_event_id, v_mid, now(), v_caller.id)
      ON CONFLICT (event_id, member_id)
      DO UPDATE SET checked_in_at = now(), marked_by = v_caller.id;
      v_count := v_count + 1;
    END LOOP;
  ELSE
    FOREACH v_mid IN ARRAY p_member_ids LOOP
      DELETE FROM public.attendance
      WHERE event_id = p_event_id AND member_id = v_mid;
      v_count := v_count + 1;
    END LOOP;
  END IF;

  RETURN json_build_object('success', true, 'marked', v_count);
END;
$function$;

-- Reload PostgREST cache
NOTIFY pgrst, 'reload schema';
