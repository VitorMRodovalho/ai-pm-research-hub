-- #1990: `manage_event` sem recurso passa a perguntar EXPLICITAMENTE "em algum lugar?".
--
-- Etapa 3 do procedimento, agora em `manage_event`. Mesma troca que o #1977 fez em `write_board`:
-- a forma sem recurso de `can_by_member` resolve o caso resourceless caindo num ramo de `can()`
-- condicionado a `legacy_tribe_id`, coluna que so e preenchida quando a iniciativa e TRIBO.
--
-- Medido antes desta migration, sobre os 94 membros ativos:
--   can_by_member(m.id,'manage_event')            14   <- hoje
--   _can_anywhere_by_member(m.id,'manage_event')  16
--   _can_anywhere(m.person_id,'manage_event')     16
--   perdem acesso                                  0   <- nas duas formas
--
-- ⚠️ A ARMADILHA DE ARGUMENTO, medida e por pouco nao cometida aqui:
--
--   `can_by_member` recebe **member id**; `_can_anywhere` recebe **person id**. Os dois sao `uuid`,
--   entao a troca ingenua `_can_anywhere(m.id, ...)` COMPILA, nao da erro de tipo, e devolve
--   **0 de 94** -- porque `members.person_id = members.id` em **0 de 94** linhas. Esvaziaria a
--   audiencia em silencio, que e exatamente o defeito que o #1978 existe para fechar.
--
--   Por isso a substituicao e feita POR CALL SITE, olhando qual id a linha tem em maos:
--     - so member id  -> `_can_anywhere_by_member(<member>, ...)`  (mesma resolucao de `can_by_member`)
--     - person id ja em maos -> `_can_anywhere(<person>, ...)`
--
--   A forma `_by_member` resolve por `persons.legacy_member_id`, que alcanca **92 dos 94** ativos:
--   2 ativos tem `person_id` preenchido e nenhuma back-reference. Hoje os dois nao tem
--   `manage_event`, por isso as duas formas empatam em 16 -- **empate por coincidencia, nao
--   equivalencia**. Onde a linha ja tem `person_id`, use a forma direta.
--
-- `detect_agenda_blocks_pending_cron` NAO e portao de chamador: o `can_by_member(m.id, ...)` dele
-- escolhe **quem recebe** a notificacao. Alargar ali foi medido contra a porta que a notificacao
-- aponta (`/admin/agenda-viva`), cujo gate ja e `is_superadmin || org_actions || qualquer
-- initiative_actions || qualquer tribe_actions` -- a semantica de `_can_anywhere`, literalmente.
-- As 2 pessoas a mais ja abrem a tela hoje; so nunca eram avisadas do que ha atras dela. O corpo da
-- notificacao carrega titulo, data e contagem de pendentes, sem PII de dono de bloco.
--
-- FORA deste lote, por medicao:
--   `get_recent_showcases_by_member`: o corpo VIVO nao bate com a unica migration que a define
--     (`20260675200000`), e o drift nao esta em allowlist nenhuma nem e acusado pelo Phase C.
--     Editar a partir da captura reverteria producao. Vai em item proprio.
--   `remove_event_showcase`: recebe `p_showcase_id`, que resolve para evento e iniciativa.
--     E (R), nao (A) -- a triagem por parametro errou de novo.
--   Caminho do selo (`_attendance_eligible_events`, `bulk_mark_excused`, `get_attendance_panel`,
--     `preview_seal_attendance`): so depois da gravacao de 27/08, para nao deixar anomalia ambigua
--     entre "o dado mudou" e "trocamos o portao".
--
-- Cada corpo abaixo e a captura vigente com UM termo trocado, com igualdade ao corpo vivo provada
-- por md5 do corpo normalizado antes desta migration existir.


-- create_governance_document_intake: captura 20260805000040 (20260805000040_p261_312_w4b_sign_proposer_consent.sql), um termo trocado.
CREATE OR REPLACE FUNCTION public.create_governance_document_intake(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_member_id uuid;
  v_caller_org_id uuid;
  v_title text;
  v_doc_type text;
  v_author_label text;
  v_visibility_class text;
  v_description text;
  v_proposer_ack_offline boolean := COALESCE((p_payload->>'proposer_ack_offline')::boolean, false);
  v_proposer_member_id uuid := nullif(p_payload->>'proposer_member_id','')::uuid;
  v_initial_status text;
  v_acknowledgement_mode text;
  v_doc_id uuid;
BEGIN
  SELECT id, organization_id INTO v_caller_member_id, v_caller_org_id
  FROM public.members
  WHERE auth_id = auth.uid() AND is_active = true
  LIMIT 1;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no active member record' USING ERRCODE='42501';
  END IF;

  IF NOT public._can_anywhere_by_member(v_caller_member_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event capability' USING ERRCODE='42501';
  END IF;

  v_title            := nullif(trim(p_payload->>'title'), '');
  v_doc_type         := nullif(trim(p_payload->>'doc_type'), '');
  v_author_label     := nullif(trim(p_payload->>'author_label'), '');
  v_visibility_class := nullif(trim(p_payload->>'visibility_class'), '');
  v_description      := nullif(trim(p_payload->>'description'), '');
  IF v_title IS NULL OR v_doc_type IS NULL OR v_author_label IS NULL
     OR v_visibility_class IS NULL OR v_description IS NULL THEN
    RAISE EXCEPTION 'p256 intake: required fields title/doc_type/author_label/visibility_class/description';
  END IF;
  IF v_visibility_class NOT IN ('public','active_members','legal_scoped','admin_only','audit_restricted') THEN
    RAISE EXCEPTION 'p256 intake: invalid visibility_class';
  END IF;

  IF v_proposer_member_id IS NOT NULL AND v_proposer_member_id = v_caller_member_id THEN
    RAISE EXCEPTION 'p256 intake: proposer_member_id must differ from caller (GP cannot self-attest as proposer)';
  END IF;

  v_acknowledgement_mode := CASE v_doc_type
    WHEN 'manual'                  THEN 'informational'
    WHEN 'editorial_guide'         THEN 'informational'
    WHEN 'governance_guideline'    THEN 'informational'
    WHEN 'executive_summary'       THEN 'informational'
    WHEN 'framework_reference'     THEN 'informational'
    WHEN 'project_charter'         THEN 'informational'
    WHEN 'cooperation_agreement'   THEN 'legal_signature'
    WHEN 'cooperation_addendum'    THEN 'legal_signature'
    WHEN 'volunteer_term_template' THEN 'binding'
    WHEN 'volunteer_addendum'      THEN 'binding'
    WHEN 'policy'                  THEN 'binding'
    ELSE 'informational'
  END;

  v_initial_status := CASE WHEN v_proposer_ack_offline THEN 'draft' ELSE 'pending_proposer_consent' END;

  INSERT INTO public.governance_documents (
    id, doc_type, title, description, status,
    organization_id, visibility_class, acknowledgement_mode,
    proposer_member_id,
    created_at, updated_at
  ) VALUES (
    gen_random_uuid(), v_doc_type, v_title, v_description, v_initial_status,
    v_caller_org_id, v_visibility_class, v_acknowledgement_mode,
    v_proposer_member_id,
    now(), now()
  ) RETURNING id INTO v_doc_id;

  IF v_proposer_ack_offline THEN
    INSERT INTO public.admin_audit_log (actor_id, target_type, target_id, action, metadata)
    VALUES (
      v_caller_member_id, 'governance_document', v_doc_id,
      'governance.proposer_attestation_offline',
      jsonb_build_object(
        'document_id', v_doc_id,
        'author_label', v_author_label,
        'gp_actor_id', v_caller_member_id,
        'proposer_member_id', v_proposer_member_id,
        'note', 'GP-attested proposer intake (offline) — NOT a proposer_consent signoff. Real consent flow ships Wave 1b (p261 #312-W4b sign_proposer_consent).'
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'document_id', v_doc_id,
    'status', v_initial_status,
    'acknowledgement_mode', v_acknowledgement_mode,
    'note', CASE WHEN v_proposer_ack_offline
                 THEN 'Doc in draft. GP attestation registered in admin_audit_log (NOT a proposer_consent signoff — Wave 1b ships real consent flow).'
                 ELSE 'Doc awaiting proposer in-app consent (pending_proposer_consent). Use sign_proposer_consent(document_id) once proposer authenticates.' END
  );
END;
$$;


-- create_next_geral_meeting: captura 20260684000000 (20260684000000_p178_phase_b_drift_capture_1_touch_a_g_69fns.sql), um termo trocado.
CREATE OR REPLACE FUNCTION public.create_next_geral_meeting(p_meeting_link text, p_youtube_url text DEFAULT NULL::text, p_title text DEFAULT NULL::text, p_interval_days integer DEFAULT 14)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_last_date date;
  v_next_date date;
  v_event_id uuid;
  v_recurrence uuid := '8ef692c1-8cae-486c-ab7b-2d3536188ef5';
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public._can_anywhere_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Forbidden: only authorized managers can create general meetings';
  END IF;

  IF p_meeting_link IS NULL OR length(trim(p_meeting_link)) = 0 THEN
    RAISE EXCEPTION 'meeting_link required';
  END IF;

  SELECT MAX(date) INTO v_last_date FROM public.events WHERE type = 'geral';
  v_last_date := COALESCE(v_last_date, CURRENT_DATE);
  v_next_date := GREATEST(v_last_date + p_interval_days, CURRENT_DATE);

  INSERT INTO public.events (
    type, title, date, time_start, duration_minutes,
    meeting_link, youtube_url,
    visibility, audience_level,
    recurrence_group, source,
    created_by, created_at, updated_at
  ) VALUES (
    'geral',
    COALESCE(p_title, 'Reunião Geral — ' || to_char(v_next_date, 'YYYY-MM-DD')),
    v_next_date, '19:30', 90,
    p_meeting_link, p_youtube_url,
    'all', 'all',
    v_recurrence, 'manual',
    v_caller_id, now(), now()
  ) RETURNING id INTO v_event_id;

  RETURN jsonb_build_object(
    'event_id', v_event_id,
    'date', v_next_date,
    'meeting_link', p_meeting_link,
    'youtube_url', p_youtube_url,
    'title', COALESCE(p_title, 'Reunião Geral — ' || to_char(v_next_date, 'YYYY-MM-DD'))
  );
END;
$function$;


-- get_comms_pipeline: captura 20260825031531 (20260825031531_1977_can_anywhere_portao_resourceless_explicito.sql), um termo trocado.
CREATE OR REPLACE FUNCTION public.get_comms_pipeline()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_now timestamptz := now();
  v_urgent_count int;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT (
    public._can_anywhere_by_member(v_caller_id, 'write_board') OR
    public._can_anywhere_by_member(v_caller_id, 'manage_event') OR
    public.can_by_member(v_caller_id, 'manage_member')
  ) THEN
    RAISE EXCEPTION 'Unauthorized: requires comms/board/admin authority';
  END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.scheduled_at), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      w.id AS webinar_id,
      w.title,
      w.scheduled_at,
      w.status,
      w.chapter_code,
      w.format_type,
      w.series_id,
      COALESCE(ps.title_i18n->>'pt-BR', ps.slug) AS series_title,
      ps.slug AS series_slug,
      w.series_position,
      w.tribe_anchors,
      i.title AS initiative_title,
      m.name AS organizer_name,
      w.briefing_doc_url,
      w.sympla_event_url,
      w.promo_kit_url,
      w.comms_kickoff_at,
      (w.briefing_doc_url IS NOT NULL) AS has_briefing,
      (w.sympla_event_url IS NOT NULL) AS has_sympla,
      (w.promo_kit_url IS NOT NULL) AS has_promo_kit,
      (w.comms_kickoff_at IS NOT NULL) AS comms_kickoff_logged,
      (w.scheduled_at - interval '30 days') AS d30_due_at,
      EXTRACT(EPOCH FROM (w.scheduled_at - v_now))::bigint / 86400 AS days_until,
      CASE
        WHEN w.briefing_doc_url IS NOT NULL
         AND w.sympla_event_url IS NOT NULL
         AND w.promo_kit_url IS NOT NULL THEN 'ready'
        WHEN w.briefing_doc_url IS NULL
         AND w.sympla_event_url IS NULL
         AND w.promo_kit_url IS NULL THEN 'not_started'
        ELSE 'in_progress'
      END AS readiness,
      (
        w.scheduled_at <= v_now + interval '30 days'
        AND w.scheduled_at > v_now
        AND (w.briefing_doc_url IS NULL OR w.sympla_event_url IS NULL OR w.promo_kit_url IS NULL)
      ) AS urgent
    FROM public.webinars w
    LEFT JOIN public.initiatives i ON i.id = w.initiative_id
    LEFT JOIN public.members m ON m.id = w.organizer_id
    LEFT JOIN public.publication_series ps ON ps.id = w.series_id
    WHERE w.status IN ('planned', 'confirmed')
      AND w.scheduled_at >= v_now - interval '7 days'
    ORDER BY w.scheduled_at
  ) r;

  SELECT COUNT(*) INTO v_urgent_count
  FROM public.webinars w
  WHERE w.status IN ('planned', 'confirmed')
    AND w.scheduled_at <= v_now + interval '30 days'
    AND w.scheduled_at > v_now
    AND (w.briefing_doc_url IS NULL OR w.sympla_event_url IS NULL OR w.promo_kit_url IS NULL);

  RETURN jsonb_build_object(
    'webinars', v_result,
    'count', jsonb_array_length(v_result),
    'urgent_count', v_urgent_count,
    'generated_at', v_now
  );
END; $function$;


-- get_dropout_risk_members: captura 20260805000485 (20260805000485_1476_wave2_operational_membership_canonical.sql), um termo trocado.
CREATE OR REPLACE FUNCTION public.get_dropout_risk_members(p_threshold integer DEFAULT 3)
 RETURNS TABLE(member_id uuid, member_name text, tribe_id integer, tribe_name text, operational_role text, last_attendance_date date, days_since_last bigint, missed_events integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN;
  END IF;

  IF NOT public._can_anywhere_by_member(v_caller_id, 'manage_event') THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH active_members AS (
    SELECT m.id, m.name, m.tribe_id, t.name AS tname, m.operational_role
    FROM public.members m
    LEFT JOIN public.tribes t ON t.id = m.tribe_id
    WHERE m.is_active AND EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
                                  WHERE vt.member_id = m.id AND vt.operational_tier IN ('researcher','tribe_leader','manager'))
  ),
  -- canonical eligible events per member; excused removed (D1 neutral); most-recent-first rank
  member_eligible AS (
    SELECT am.id AS mid, el.event_date AS edate,
           (att.present IS TRUE) AS was_present,
           ROW_NUMBER() OVER (PARTITION BY am.id ORDER BY el.event_date DESC, el.event_id DESC) AS rn
    FROM active_members am
    CROSS JOIN LATERAL public._attendance_eligible_events(am.id, NULL) el
    LEFT JOIN public.attendance att ON att.event_id = el.event_id AND att.member_id = am.id
    WHERE att.excused IS NOT TRUE
  ),
  -- of the last p_threshold non-excused eligible events, how many were absent (no present row)
  member_recent AS (
    SELECT me.mid, count(*) FILTER (WHERE NOT me.was_present) AS missed
    FROM member_eligible me
    WHERE me.rn <= p_threshold
    GROUP BY me.mid
  ),
  -- most recent present attendance over the member's full eligible set
  member_last AS (
    SELECT me.mid, max(me.edate) FILTER (WHERE me.was_present) AS last_date
    FROM member_eligible me
    GROUP BY me.mid
  )
  SELECT am.id, am.name, am.tribe_id, am.tname, am.operational_role,
         ml.last_date,
         (CURRENT_DATE - COALESCE(ml.last_date, DATE '2025-01-01'))::bigint,
         mr.missed::integer
  FROM active_members am
  JOIN member_recent mr ON mr.mid = am.id
  LEFT JOIN member_last ml ON ml.mid = am.id
  WHERE mr.missed >= p_threshold
  ORDER BY ml.last_date ASC NULLS FIRST;
END;
$function$;


-- get_gamification_category_activity: captura 20260805000488 (20260805000488_1470_digest_rolling_window_occurred_at.sql), um termo trocado.
CREATE OR REPLACE FUNCTION public.get_gamification_category_activity(p_window_days integer DEFAULT 30)
 RETURNS TABLE(slug text, pillar text, display_name text, base_points integer, trigger_source text, active boolean, total_events bigint, unique_members bigint, last_window_events bigint, last_7d_events bigint, last_award timestamp with time zone, status text, is_orphan boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  IF NOT public._can_anywhere_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event';
  END IF;

  RETURN QUERY
  WITH agg AS (
    SELECT
      gp.category,
      count(*)::bigint AS total_events,
      count(DISTINCT gp.member_id)::bigint AS unique_members,
      -- #1470: janela movel de atividade por data do FATO (occurred_at), nao created_at.
      count(*) FILTER (WHERE COALESCE(gp.occurred_at, gp.created_at) >= now() - (p_window_days || ' days')::interval)::bigint AS last_window_events,
      count(*) FILTER (WHERE COALESCE(gp.occurred_at, gp.created_at) >= now() - INTERVAL '7 days')::bigint AS last_7d_events,
      -- last_award permanece o carimbo de concessao (auditoria "quando foi lancado").
      max(gp.created_at) AS last_award
    FROM public.gamification_points gp
    GROUP BY gp.category
  )
  SELECT
    r.slug,
    r.pillar,
    COALESCE(r.display_name_i18n->>'pt-BR', r.slug) AS display_name,
    r.base_points,
    r.trigger_source,
    r.active,
    COALESCE(a.total_events, 0) AS total_events,
    COALESCE(a.unique_members, 0) AS unique_members,
    COALESCE(a.last_window_events, 0) AS last_window_events,
    COALESCE(a.last_7d_events, 0) AS last_7d_events,
    a.last_award,
    CASE
      WHEN NOT r.active THEN 'inactive'
      WHEN COALESCE(a.total_events, 0) = 0 THEN 'never'
      WHEN COALESCE(a.last_window_events, 0) = 0 THEN 'idle'
      WHEN COALESCE(a.last_7d_events, 0) = 0 THEN 'warm'
      ELSE 'healthy'
    END AS status,
    false AS is_orphan
  FROM public.gamification_rules r
  LEFT JOIN agg a ON a.category = r.slug
  UNION ALL
  SELECT
    a.category AS slug,
    'orphan'::text AS pillar,
    a.category AS display_name,
    NULL::int AS base_points,
    NULL::text AS trigger_source,
    NULL::boolean AS active,
    a.total_events,
    a.unique_members,
    a.last_window_events,
    a.last_7d_events,
    a.last_award,
    'orphan'::text AS status,
    true AS is_orphan
  FROM agg a
  WHERE NOT EXISTS (SELECT 1 FROM public.gamification_rules r WHERE r.slug = a.category)
  ORDER BY status, pillar NULLS LAST, slug;
END;
$function$;


-- get_geral_agenda_viva: captura 20260805000499 (20260805000499_agenda_blocks_reach_the_meeting_surfaces.sql), um termo trocado.
CREATE OR REPLACE FUNCTION public.get_geral_agenda_viva(p_limit_events integer DEFAULT 2, p_member_id uuid DEFAULT NULL::uuid, p_window text DEFAULT 'upcoming'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller   uuid;
  v_is_admin boolean := false;
  v_limit    int := LEAST(GREATEST(COALESCE(p_limit_events, 2), 1), 6);
  v_window   text := lower(COALESCE(p_window, 'upcoming'));
  v_result   jsonb;
BEGIN
  IF v_window NOT IN ('upcoming','past_recent','both') THEN
    v_window := 'upcoming';
  END IF;

  -- p_member_id is part of the spec signature, reserved for a future admin "view as member"
  -- mode (slice 3); the caller is always resolved from auth.uid() here (no impersonation yet).
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NOT NULL THEN
    v_is_admin := public._can_anywhere_by_member(v_caller, 'manage_event');
  END IF;

  WITH all_geral AS (
    SELECT e.id, e.title, e.date, e.time_start, e.timezone,
           (e.date + COALESCE(e.time_start,'00:00'::time)) AT TIME ZONE COALESCE(e.timezone,'America/Sao_Paulo') AS start_at
    FROM public.events e
    WHERE e.type = 'geral'
      AND e.status IS DISTINCT FROM 'cancelled'
  ),
  upcoming AS (
    SELECT ag.id, ag.title, ag.date, ag.time_start, ag.timezone, ag.start_at, false AS is_past
    FROM all_geral ag
    WHERE v_window IN ('upcoming','both')
      AND ag.start_at > now()
    ORDER BY ag.start_at
    LIMIT v_limit
  ),
  past AS (
    SELECT ag.id, ag.title, ag.date, ag.time_start, ag.timezone, ag.start_at, true AS is_past
    FROM all_geral ag
    WHERE v_window IN ('past_recent','both')
      AND ag.start_at <= now()
    ORDER BY ag.start_at DESC
    LIMIT 1
  ),
  selected AS (
    SELECT * FROM past
    UNION ALL
    SELECT * FROM upcoming
  ),
  blocks AS (
    SELECT s.is_past, b.event_id, b.id, b.format_slug, b.title, b.duration_min, b.status, b.sort_order,
           b.external_guest, b.owner_member_id, b.guest_name, b.material_url,
           split_part(m.name, ' ', 1) AS owner_first_name,
           m.name AS owner_full_name
    FROM selected s
    JOIN public.event_agenda_blocks b ON b.event_id = s.id
    JOIN public.members m ON m.id = b.owner_member_id
    -- upcoming: reserved+confirmed (futuro reservável); past: confirmed+no_show (realizado/falta).
    -- #1071: past 'reserved' also visible to admins (manage_event) so they can confirm/
    -- no-show a block whose meeting already ended (protagonism never confirmed live).
    WHERE (NOT s.is_past AND b.status IN ('reserved','confirmed'))
       OR (s.is_past     AND b.status IN ('confirmed','no_show'))
       OR (s.is_past AND v_is_admin AND b.status = 'reserved')
  )
  SELECT jsonb_build_object(
    'viewer', jsonb_build_object('is_authenticated', v_caller IS NOT NULL, 'is_admin', v_is_admin),
    'window', v_window,
    'events', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', s.id, 'title', s.title, 'date', s.date, 'time_start', s.time_start,
          'timezone', s.timezone, 'start_at', s.start_at,
          'is_past', s.is_past,
          'capacity_total_min', 90,
          'capacity_used_min', COALESCE((SELECT SUM(duration_min) FROM blocks bk WHERE bk.event_id = s.id), 0),
          'capacity_remaining_min', 90 - COALESCE((SELECT SUM(duration_min) FROM blocks bk WHERE bk.event_id = s.id), 0),
          'blocks', COALESCE((
            SELECT jsonb_agg(
              jsonb_build_object(
                'id', bk.id, 'format_slug', bk.format_slug, 'title', bk.title,
                'duration_min', bk.duration_min, 'status', bk.status, 'sort_order', bk.sort_order,
                'external_guest', bk.external_guest,
                -- LGPD PD-5 (#1548): a regra vive em _agenda_block_owner_visible, nao aqui.
                'owner_first_name', CASE
                  WHEN public._agenda_block_owner_visible(
                         bk.status,
                         (v_caller IS NOT NULL AND bk.owner_member_id = v_caller),
                         v_is_admin)
                    THEN bk.owner_first_name
                  ELSE NULL
                END,
                'is_mine', (v_caller IS NOT NULL AND bk.owner_member_id = v_caller)
              )
              -- authenticated (non-admin) additionally see the material link
              || CASE WHEN v_caller IS NOT NULL
                      THEN jsonb_build_object('material_url', bk.material_url)
                      ELSE '{}'::jsonb END
              -- manage_event sees full detail (owner id + full name + guest PII + raw fields)
              || CASE WHEN v_is_admin
                      THEN jsonb_build_object(
                             'owner_member_id', bk.owner_member_id,
                             'owner_full_name', bk.owner_full_name,
                             'guest_name', bk.guest_name)
                      ELSE '{}'::jsonb END
              ORDER BY bk.sort_order, bk.duration_min DESC
            ) FROM blocks bk WHERE bk.event_id = s.id
          ), '[]'::jsonb)
        ) ORDER BY s.start_at
      ) FROM selected s
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END
$function$;


-- get_recurrence_stockout: captura 20260805000125 (20260805000125_p415_recurrence_stockout_observability.sql), um termo trocado.
CREATE OR REPLACE FUNCTION public.get_recurrence_stockout(p_horizon_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_rows jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  -- gated on manage_event: whoever can create the series (create_recurring_weekly_events) should see
  -- which series need resupplying. Includes tribe leaders for their own meetings.
  IF NOT public._can_anywhere_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event';
  END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.last_date), '[]'::jsonb)
  INTO v_rows
  FROM public._recurrence_stockout_rows(p_horizon_days) r;

  RETURN jsonb_build_object(
    'stockout',     v_rows,
    'total',        jsonb_array_length(v_rows),
    'horizon_days', p_horizon_days,
    'checked_at',   now()
  );
END;
$function$;


-- list_webinar_proposals: captura 20260516640000 (20260516640000_p95_130_webinar_proposals_workflow.sql), um termo trocado.
CREATE OR REPLACE FUNCTION public.list_webinar_proposals(
  p_status_filter text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_is_committee boolean;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  v_is_committee := public._can_anywhere_by_member(v_caller_id, 'manage_event')
                 OR public.can_by_member(v_caller_id, 'manage_member');

  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.created_at DESC), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      wp.id,
      wp.proposed_title,
      wp.format_type,
      wp.status,
      wp.proposed_by_tribe_id,
      wp.proposer_member_id,
      mp.name AS proposer_name,
      wp.series_id,
      COALESCE(ps.title_i18n->>'pt-BR', ps.slug) AS series_title,
      wp.quadrant_anchor,
      q.key AS quadrant_key,
      q.name_pt AS quadrant_name,
      wp.themes,
      wp.proposed_speakers,
      wp.notes,
      wp.rejection_reason,
      wp.reviewed_by,
      mr.name AS reviewer_name,
      wp.reviewed_at,
      wp.webinar_id,
      wp.created_at,
      wp.updated_at
    FROM public.webinar_proposals wp
    LEFT JOIN public.members mp ON mp.id = wp.proposer_member_id
    LEFT JOIN public.members mr ON mr.id = wp.reviewed_by
    LEFT JOIN public.publication_series ps ON ps.id = wp.series_id
    LEFT JOIN public.quadrants q ON q.id = wp.quadrant_anchor
    WHERE (p_status_filter IS NULL OR wp.status = p_status_filter)
      AND (v_is_committee OR wp.proposer_member_id = v_caller_id)
    ORDER BY wp.created_at DESC
  ) r;

  RETURN jsonb_build_object(
    'proposals', v_result,
    'count', jsonb_array_length(v_result),
    'is_committee', v_is_committee
  );
END; $function$;


-- get_member_comms_card: captura 20260805000447 (20260805000447_1383_p0c_member_comms_card_confidential_roles.sql), um termo trocado.
CREATE OR REPLACE FUNCTION public.get_member_comms_card(p_query text DEFAULT NULL::text, p_person_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_person_id uuid;
  v_can boolean;
  v_target uuid;
  v_match_count int;
  v_matches jsonb;
  v_member_id uuid;
  v_member_status text;
  v_clear boolean;
  v_reason text;
  v_like text;
BEGIN
  -- Auth. Resolve the caller's person_id: can() keys on auth_engagements.person_id
  -- (= persons.id), NOT auth.uid() — so the gate MUST pass a person_id.
  SELECT id INTO v_caller_person_id FROM public.persons WHERE auth_id = auth.uid();
  IF v_caller_person_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- Authority gate: comms/event leaders + admin/GP
  v_can := public._can_anywhere(v_caller_person_id, 'manage_event')
        OR public.can(v_caller_person_id, 'manage_member', NULL, NULL);
  IF NOT v_can THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_event or manage_member');
  END IF;

  -- Resolve target person
  IF p_person_id IS NOT NULL THEN
    v_target := p_person_id;
  ELSIF p_query IS NOT NULL AND length(trim(p_query)) >= 2 THEN
    -- Escape LIKE wildcards so a caller cannot pass '%'/'_' to enumerate the directory.
    v_like := '%' || replace(replace(replace(trim(p_query), '\', '\\'), '%', '\%'), '_', '\_') || '%';

    SELECT count(*) INTO v_match_count
    FROM public.persons p
    WHERE p.anonymized_at IS NULL
      AND p.name ILIKE v_like ESCAPE '\';

    IF v_match_count = 0 THEN
      RETURN jsonb_build_object('error', 'No person found matching query');
    ELSIF v_match_count > 1 THEN
      SELECT jsonb_agg(jsonb_build_object(
               'person_id', p.id,
               'name', p.name,
               'has_photo', (p.photo_url IS NOT NULL)
             ) ORDER BY p.name)
        INTO v_matches
      FROM public.persons p
      WHERE p.anonymized_at IS NULL
        AND p.name ILIKE v_like ESCAPE '\';
      RETURN jsonb_build_object('ambiguous', true, 'match_count', v_match_count, 'matches', v_matches);
    ELSE
      SELECT p.id INTO v_target
      FROM public.persons p
      WHERE p.anonymized_at IS NULL
        AND p.name ILIKE v_like ESCAPE '\';
    END IF;
  ELSE
    RETURN jsonb_build_object('error', 'Provide person_id or query (min 2 chars)');
  END IF;

  -- Target must exist and not be anonymized
  IF NOT EXISTS (SELECT 1 FROM public.persons WHERE id = v_target AND anonymized_at IS NULL) THEN
    RETURN jsonb_build_object('error', 'Person not found');
  END IF;

  -- Comms clearance (Cláusula 11): signed term = NOT pre-onboarding for the linked member.
  SELECT m.id, m.member_status INTO v_member_id, v_member_status
  FROM public.members m
  JOIN public.persons p ON p.legacy_member_id = m.id
  WHERE p.id = v_target;

  IF v_member_id IS NULL THEN
    v_clear := false;
    v_reason := 'no_member_record';
  ELSIF public.member_is_pre_onboarding(v_target, v_member_status) THEN
    v_clear := false;
    v_reason := 'pre_onboarding';
  -- #729: honor an image/voice publicity consent REVOCATION (#570 SSOT, consent_records).
  -- "Currently revoked" = a revoked image_voice_publicity consent with NO later active opt-in.
  -- Behavior-neutral today (0 rows; #570 dormant). At #570 go-live, tighten to REQUIRE an
  -- active opt-in rather than only blocking on an explicit revocation (see header note).
  ELSIF EXISTS (
      SELECT 1 FROM public.consent_records cr
      WHERE cr.member_id = v_member_id
        AND cr.policy_type = 'image_voice_publicity'
        AND cr.revoked_at IS NOT NULL
    ) AND NOT EXISTS (
      SELECT 1 FROM public.consent_records cr
      WHERE cr.member_id = v_member_id
        AND cr.policy_type = 'image_voice_publicity'
        AND cr.revoked_at IS NULL
    ) THEN
    v_clear := false;
    v_reason := 'image_consent_revoked';
  ELSE
    v_clear := true;
    v_reason := 'signed_term';
  END IF;

  -- Build the comms card
  RETURN (
    SELECT jsonb_build_object(
      'person_id', p.id,
      'display_name', p.name,
      'headshot_url', p.photo_url,
      'linkedin_url', p.linkedin_url,
      'credly_url', p.credly_url,
      'credentials', COALESCE((
        SELECT jsonb_agg(b->>'name' ORDER BY (b->>'issued_at') DESC)
        FROM jsonb_array_elements(COALESCE(p.credly_badges, '[]'::jsonb)) b
        WHERE b->>'name' IS NOT NULL
      ), '[]'::jsonb),
      'roles', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
                 'initiative', i.title,
                 'kind', e.kind,
                 'role', e.role
               ) ORDER BY e.granted_at DESC)
        FROM public.engagements e
        JOIN public.initiatives i ON i.id = e.initiative_id
        WHERE e.person_id = p.id AND e.status = 'active'
          AND i.visibility IS DISTINCT FROM 'confidential'
      ), '[]'::jsonb),
      'comms_clearance', v_clear,
      'clearance_reason', v_reason
    )
    FROM public.persons p
    WHERE p.id = v_target
  );
END;
$function$;


-- detect_agenda_blocks_pending_cron: captura 20260805000499 (20260805000499_agenda_blocks_reach_the_meeting_surfaces.sql), um termo trocado.
CREATE OR REPLACE FUNCTION public.detect_agenda_blocks_pending_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_events int := 0;
  v_blocks int := 0;
  v_inserted int := 0;
BEGIN
  -- Sem TEMP TABLE de proposito: `CREATE TEMP TABLE ... ON COMMIT DROP` quebra com "relation
  -- already exists" se a funcao for chamada DUAS VEZES na mesma transacao (o que um teste faz).
  -- A view abaixo nao existe como objeto; o SELECT e repetido nas duas leituras.
  SELECT count(*), COALESCE(sum(pm.pending), 0) INTO v_events, v_blocks
  FROM public._agenda_blocks_pending_rows(60) pm;

  IF v_events > 0 THEN
    -- Um aviso por (destinatario, reuniao), re-emitido no maximo a cada 6 dias enquanto a pendencia
    -- durar. source_type/source_id dao a idempotencia; sem eles isto viraria spam diario.
    INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode, created_at)
    SELECT m.id,
           'agenda_blocks_pending',
           format('%s bloco(s) sem confirmar em %s', pm.pending, pm.title),
           format('A reuniao de %s tem %s bloco(s) de protagonismo ainda em "reservado". Enquanto nao forem confirmados (ou marcados como nao realizados) os protagonistas nao recebem XP e os blocos nao aparecem publicamente. Confirme em Admin -> Agenda Viva.',
                  to_char(pm.event_date, 'DD/MM/YYYY'), pm.pending),
           '/admin/agenda-viva',
           'event',
           pm.event_id,
           'digest_weekly',
           now()
    FROM public._agenda_blocks_pending_rows(60) pm
    CROSS JOIN public.members m
    WHERE m.is_active = true
      AND public._can_anywhere(m.person_id, 'manage_event')
      AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = m.id
          AND n.type = 'agenda_blocks_pending'
          AND n.source_id = pm.event_id
          AND n.created_at >= now() - interval '6 days'
      );
    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      NULL, 'cron.detect_agenda_blocks_pending_run', 'system_event', NULL,
      jsonb_build_object('meetings_with_pending', v_events, 'blocks_pending', v_blocks, 'managers_notified', v_inserted, 'horizon_days', 60),
      jsonb_build_object('source', 'cron_detect_agenda_blocks_pending')
    );
  END IF;

  RETURN jsonb_build_object(
    'meetings_with_pending',  v_events,
    'blocks_pending',         v_blocks,
    'notifications_inserted', v_inserted,
    'horizon_days',           60,
    'run_at',                 now()
  );
END;
$function$;
