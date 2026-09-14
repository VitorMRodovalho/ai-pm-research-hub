-- #2278 — a presenca lida pelo MCP para de afirmar que quem faltou esteve na reuniao.
--
-- O DEFEITO, literal. `get_event_detail` montava o bloco de presenca assim:
--
--     'present_count', (SELECT COUNT(*) FROM attendance WHERE event_id = p_event_id),
--     'present', true,                        -- literal: NUNCA lia a.present
--     'excused', COALESCE(a.excused, false)   -- este lia o banco de verdade
--
-- Ela assumia que existir linha em `attendance` significa ter comparecido. Isso era verdade
-- enquanto ausencia nao era registravel, e deixou de ser quando a plataforma passou a gravar
-- `present = false` e `excused`. A funcao nao acompanhou.
--
-- O sintoma que o proprio payload exibia, e que denunciou o defeito: um registro saindo como
-- `excused: true, present: true` — justificado E presente ao mesmo tempo.
--
-- MEDIDO EM 14/09, no evento que motivou o relato de um lider de tribo (`8c3fa194`):
--   a RPC devolvia  43 membros, TODOS present:true, present_count 43
--   a tabela tinha  43 registros = 37 presentes + 6 ausentes
--   a UI mostrava   37/88  (correta, e reproduzivel a partir de get_tribe_event_roster)
--
-- Seis pessoas que faltaram foram apresentadas como tendo comparecido. A conclusao que circulou
-- no grupo foi "MCP certo, UI errada"; era o inverso.
--
-- ALCANCE no acervo: 2.709 registros, 2.367 presentes reais, 342 ausencias (12,6%) que a RPC
-- convertia em presenca, sobre 108 eventos.
--
-- POR QUE SO APARECEU AGORA: o registro de ausencia saltou para 174 em agosto e 81 em setembro,
-- contra 3 a 38 nos meses anteriores. A funcao sempre esteve errada; antes acertava por acidente,
-- porque quase nao havia ausencia gravada para ela descartar.

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- `get_event_detail` — le a coluna em vez de afirmar o valor
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Alem de corrigir `present`, o payload passa a trazer `absent_count` EXPLICITO. Sem ele, quem le
-- precisa inferir a ausencia pela diferenca entre dois numeros, e foi exatamente esse tipo de
-- inferencia (43 linhas = 43 presentes) que produziu o defeito.
CREATE OR REPLACE FUNCTION public.get_event_detail(p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_event record;
  v_event_tribe_id int;
  v_engaged_confidential boolean;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  SELECT * INTO v_event FROM events WHERE id = p_event_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Event not found'); END IF;

  IF NOT public.rls_can_see_initiative(v_event.initiative_id) THEN
    RETURN jsonb_build_object('error', 'Event not found');
  END IF;

  v_engaged_confidential := (v_event.initiative_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.initiatives i
    JOIN public.auth_engagements ae ON ae.initiative_id = i.id
    WHERE i.id = v_event.initiative_id
      AND i.visibility = 'confidential'
      AND ae.auth_id = auth.uid()
      AND ae.is_authoritative = true
  ));

  IF v_event.visibility = 'gp_only'
     AND NOT public.can_by_member(v_caller.id, 'manage_platform')
     AND NOT v_engaged_confidential THEN
    RETURN jsonb_build_object('error', 'Restricted content');
  END IF;

  IF v_event.visibility = 'leadership'
     AND NOT public.can_by_member(v_caller.id, 'manage_event')
     AND NOT v_engaged_confidential THEN
    RETURN jsonb_build_object('error', 'Restricted content');
  END IF;

  v_event_tribe_id := public.resolve_tribe_id(v_event.initiative_id);

  SELECT jsonb_build_object(
    'event', jsonb_build_object(
      'id', v_event.id,
      'title', v_event.title,
      'date', v_event.date,
      'type', v_event.type,
      'tribe_id', v_event_tribe_id,
      'duration_minutes', v_event.duration_minutes,
      'duration_actual', v_event.duration_actual,
      'meeting_link', v_event.meeting_link,
      'is_recorded', v_event.is_recorded,
      'youtube_url', v_event.youtube_url,
      'recording_url', v_event.recording_url,
      'recording_type', v_event.recording_type,
      'visibility', v_event.visibility
    ),
    'agenda', jsonb_build_object(
      'text', v_event.agenda_text,
      'url', v_event.agenda_url,
      'posted_at', v_event.agenda_posted_at,
      'posted_by', (SELECT m.name FROM members m WHERE m.id = v_event.agenda_posted_by)
    ),
    'minutes', jsonb_build_object(
      'text', v_event.minutes_text,
      'url', v_event.minutes_url,
      'posted_at', v_event.minutes_posted_at,
      'posted_by', (SELECT m.name FROM members m WHERE m.id = v_event.minutes_posted_by)
    ),
    'action_items', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', ai.id,
        'description', ai.description,
        'assignee_id', ai.assignee_id,
        'assignee_name', COALESCE(ai.assignee_name, am.name),
        'due_date', ai.due_date,
        'status', ai.status,
        'carried_to_event_id', ai.carried_to_event_id
      ) ORDER BY ai.created_at), '[]'::jsonb)
      FROM meeting_action_items ai
      LEFT JOIN members am ON am.id = ai.assignee_id
      WHERE ai.event_id = p_event_id AND ai.status != 'cancelled'
    ),
    'attendance', jsonb_build_object(
      -- #2278: conta PRESENTES, nao linhas. `COUNT(*)` respondia 43 onde havia 37.
      'present_count', (SELECT COUNT(*) FROM attendance
                         WHERE event_id = p_event_id AND present IS TRUE),
      -- #2278: explicito, para que ninguem precise inferir ausencia por subtracao.
      'absent_count',  (SELECT COUNT(*) FROM attendance
                         WHERE event_id = p_event_id AND present IS NOT TRUE),
      'excused_count', (SELECT COUNT(*) FROM attendance
                         WHERE event_id = p_event_id AND excused IS TRUE),
      'record_count',  (SELECT COUNT(*) FROM attendance WHERE event_id = p_event_id),
      'members', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'id', a.member_id,
          'name', m.name,
          -- #2278: A CORRECAO. Era o literal `true`.
          'present', COALESCE(a.present, false),
          'excused', COALESCE(a.excused, false)
        ) ORDER BY m.name), '[]'::jsonb)
        FROM attendance a
        JOIN members m ON m.id = a.member_id
        WHERE a.event_id = p_event_id
      )
    ),
    'showcases', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', es.id,
        'member_id', es.member_id,
        'member_name', m.name,
        'showcase_type', es.showcase_type,
        'title', es.title,
        'duration_min', es.duration_min
      ) ORDER BY es.created_at), '[]'::jsonb)
      FROM event_showcases es
      JOIN members m ON m.id = es.member_id
      WHERE es.event_id = p_event_id
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

COMMENT ON FUNCTION public.get_event_detail(uuid) IS
  '#2278 — `present` vem de `a.present` (era o literal `true`, que afirmava presenca de quem faltou em 108 eventos) e `present_count` conta presentes (contava linhas). Traz `absent_count`/`excused_count`/`record_count` explicitos para que a leitura nunca precise inferir ausencia por subtracao.';