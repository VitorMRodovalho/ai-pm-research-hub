-- #3152: a jornada de onboarding lê o papel que vale para a jornada, sem mudar a autoridade.
--
-- Quem tem vínculo ativo de kind com requires_agreement e ainda sem certificado de Termo fica com
-- is_authoritative = false, e _derive_operational_role (#1925) devolve guest. Isso é a regra de autoridade e fica
-- como está. Mas a aprovação semeia a jornada com o papel-alvo, e os leitores filtram as etapas pelo papel atual:
-- a pessoa perdia o checklist inteiro, inclusive a etapa do Termo, que é a que a tira desse estado.
--
-- 1. _onboarding_journey_role(member): operational_role; se for guest e houver vínculo ativo, vigente, que pede
--    Termo e não tem certificado, o papel que esse vínculo dará quando o Termo for assinado. Os papéis são os
--    mesmos degraus da escada (_derive_operational_role); o guard confere as listas contra a escada.
--    Só a jornada lê este helper. can(), a escada, o cache e o trigger sync_operational_role_cache não mudam.
-- 2. get_my_onboarding, _trg_record_onboarding_complete_milestone e get_onboarding_journey_admin passam a chamá-lo.
--    Na leitura da gestão, steps ganha COALESCE para '[]' e o membro ganha journey_role.
--
-- Fora daqui (pendência da filiação): get_affiliation_verification_queue, get_affiliation_chapter_rollup e
-- v4_notify_expiring_affiliations usam o mesmo predicado com operational_role.
-- Guard: tests/contracts/3152-jornada-antes-do-termo.test.mjs.

CREATE OR REPLACE FUNCTION public._onboarding_journey_role(p_member_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
      WHEN m.operational_role IS DISTINCT FROM 'guest' THEN m.operational_role
      ELSE COALESCE((
        SELECT CASE
            WHEN bool_or(ae.kind = 'volunteer' AND ae.role IN ('leader','comms_leader')) THEN 'tribe_leader'
            WHEN bool_or(
              (ae.kind = 'volunteer' AND ae.role IN ('researcher','facilitator','communicator','curator'))
              OR (ae.kind = 'study_group_owner'
                  AND ae.role IN ('leader','co_leader','owner','coordinator','researcher','contributor','member','participant'))
            ) THEN 'researcher'
          END
        FROM public.auth_engagements ae
        WHERE ae.person_id = m.person_id
          AND ae.status = 'active'
          AND ae.start_date <= CURRENT_DATE AND (ae.end_date IS NULL OR ae.end_date >= CURRENT_DATE)
          AND ae.requires_agreement IS TRUE
          AND ae.agreement_certificate_id IS NULL
      ), m.operational_role)
    END
  FROM public.members m
  WHERE m.id = p_member_id;
$function$;

REVOKE ALL ON FUNCTION public._onboarding_journey_role(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._onboarding_journey_role(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.get_my_onboarding()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_member_role text;
  v_has_req_agreement_engagement boolean;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id
  FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  -- #3152: o papel da jornada, não o cache de autoridade
  v_member_role := public._onboarding_journey_role(v_member_id);

  -- #322 close-review: mirror the approve_selection_application forward guard here.
  SELECT EXISTS (
    SELECT 1 FROM public.engagements e
    JOIN public.members m ON m.id = v_member_id
    JOIN public.engagement_kinds ek ON ek.slug = e.kind
    WHERE e.person_id = m.person_id
      AND e.status = 'active'
      AND ek.requires_agreement = true
  ) INTO v_has_req_agreement_engagement;

  -- Auto-generate progress rows (guarded: volunteer_term only with an active
  -- requires_agreement engagement; #1103: only steps that apply to this member's role)
  INSERT INTO onboarding_progress (member_id, step_key, status)
  SELECT v_member_id, s.id, 'pending'
  FROM onboarding_steps s
  WHERE NOT EXISTS (SELECT 1 FROM onboarding_progress op WHERE op.member_id = v_member_id AND op.step_key = s.id)
    AND NOT (s.id = 'volunteer_term' AND NOT v_has_req_agreement_engagement)
    AND public.onboarding_step_applies(s.applies_to_role, v_member_role);

  SELECT jsonb_build_object(
    'member_id', v_member_id,
    'total_steps', (SELECT count(*) FROM onboarding_steps s
      WHERE s.is_required AND public.onboarding_step_applies(s.applies_to_role, v_member_role)),
    'completed_steps', (SELECT count(*) FROM onboarding_progress
      WHERE member_id = v_member_id AND status IN ('completed', 'skipped')
        AND step_key IN (SELECT id FROM onboarding_steps s
          WHERE public.onboarding_step_applies(s.applies_to_role, v_member_role))),
    'all_complete', (NOT EXISTS (
      SELECT 1 FROM onboarding_steps s
      JOIN onboarding_progress op ON op.step_key = s.id AND op.member_id = v_member_id
      WHERE s.is_required AND op.status NOT IN ('completed', 'skipped')
        AND public.onboarding_step_applies(s.applies_to_role, v_member_role)
    )),
    'steps', (SELECT jsonb_agg(row_to_json(t) ORDER BY t.step_order) FROM (
      SELECT s.id AS step_id, s.step_order, s.label_pt, s.label_en, s.label_es,
        s.description_pt, s.description_en, s.description_es, s.icon, s.is_required, s.closed_by,
        COALESCE(op.status, 'pending') AS status, op.completed_at, op.metadata
      FROM onboarding_steps s
      LEFT JOIN onboarding_progress op ON op.step_key = s.id AND op.member_id = v_member_id
      WHERE public.onboarding_step_applies(s.applies_to_role, v_member_role)
      ORDER BY s.step_order
    ) t)
  ) INTO v_result;
  RETURN v_result;
END; $function$;

CREATE OR REPLACE FUNCTION public._trg_record_onboarding_complete_milestone()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_all_complete boolean;
  v_member_role text;
BEGIN
  IF NEW.member_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.status NOT IN ('completed', 'skipped') THEN RETURN NEW; END IF;
  -- #3152: o papel da jornada, não o cache de autoridade
  v_member_role := public._onboarding_journey_role(NEW.member_id);
  -- #2718: etapa que não vale para o papel da pessoa não conclui a jornada dela. Sem isto, quem não tem
  -- nenhuma etapa (convidado, patrocinador...) gravaria o marco no primeiro clique, por vacuidade.
  IF NOT EXISTS (SELECT 1 FROM public.onboarding_steps s
                 WHERE s.id = NEW.step_key
                   AND public.onboarding_step_applies(s.applies_to_role, v_member_role)) THEN
    RETURN NEW;
  END IF;
  SELECT NOT EXISTS (
    SELECT 1 FROM public.onboarding_steps s
    WHERE s.is_required
      AND public.onboarding_step_applies(s.applies_to_role, v_member_role)
      AND (
        EXISTS (SELECT 1 FROM public.onboarding_progress op
                WHERE op.step_key = s.id AND op.member_id = NEW.member_id
                  AND op.status NOT IN ('completed', 'skipped'))
        OR (s.id <> 'volunteer_term'
            AND NOT EXISTS (SELECT 1 FROM public.onboarding_progress op
                            WHERE op.step_key = s.id AND op.member_id = NEW.member_id))
      )
  ) INTO v_all_complete;
  IF v_all_complete THEN
    PERFORM public.record_milestone(NEW.member_id, 'onboarding_complete', 'onboarding', NEW.id,
      jsonb_build_object('via', 'onboarding_progress_trigger'));
  END IF;
  RETURN NEW;
END; $function$;

CREATE OR REPLACE FUNCTION public.get_onboarding_journey_admin(p_member_id uuid DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_designations text[];
  v_chapter text;
  v_global boolean;
  v_chapter_scope boolean;
  v_lines integer[];
  v_result jsonb;
BEGIN
  SELECT id, COALESCE(designations, '{}'::text[]), chapter INTO v_caller_id, v_designations, v_chapter
  FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: not a member' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_global := public.can_by_member(v_caller_id, 'manage_member')
    OR v_designations && ARRAY['voluntariado_director', 'filiacao_director', 'certificacao_director', 'deputy_manager', 'co_gp']::text[];
  v_chapter_scope := v_designations && ARRAY['sponsor', 'chapter_vice_president']::text[]
    AND COALESCE(v_chapter, '') <> '';
  SELECT array_agg(DISTINCT i.legacy_tribe_id) INTO v_lines
  FROM engagements e
  JOIN members lm ON lm.person_id = e.person_id
  JOIN initiatives i ON i.id = e.initiative_id
  WHERE lm.id = v_caller_id AND e.status = 'active' AND e.role IN ('leader', 'co_leader')
    AND i.legacy_tribe_id IS NOT NULL
    AND e.start_date <= CURRENT_DATE AND (e.end_date IS NULL OR e.end_date >= CURRENT_DATE);
  IF NOT public.can_by_member(v_caller_id, 'manage_initiative') THEN
    v_lines := NULL;
  END IF;

  IF NOT (v_global OR v_chapter_scope OR v_lines IS NOT NULL) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member, a director designation, a chapter presidency or an active line leadership'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  WITH mem AS (
    SELECT m.id, m.name, m.chapter, m.tribe_id, m.operational_role, m.member_status, m.email,
           public._onboarding_journey_role(m.id) AS journey_role
    FROM members m
    WHERE ((p_member_id IS NULL AND m.member_status = 'active'
            AND EXISTS (SELECT 1 FROM onboarding_progress op0 WHERE op0.member_id = m.id))
           OR m.id = p_member_id)
      AND (v_global
           OR (v_chapter_scope AND m.chapter = v_chapter)
           OR m.tribe_id = ANY (v_lines))
  ),
  jr AS (
    SELECT mem.id AS member_id, s.id AS step_key, s.step_order, s.closed_by AS step_closed_by,
           op.status, op.completed_at, op.sla_deadline, op.metadata, op.application_id,
           CASE s.id
             WHEN 'volunteer_term' THEN (
               SELECT jsonb_build_object('kind', 'certificate', 'certificate_id', c.id,
                                         'verification_code', c.verification_code, 'at', c.issued_at)
               FROM certificates c
               WHERE c.member_id = mem.id AND c.type = 'volunteer_agreement' AND c.revoked_at IS NULL
               ORDER BY c.issued_at DESC NULLS LAST LIMIT 1)
             WHEN 'vep_acceptance' THEN (
               SELECT jsonb_build_object('kind', 'vep', 'application_id', sa.id,
                                         'vep_status', sa.vep_status_raw, 'at', sa.vep_last_seen_at)
               FROM selection_applications sa
               WHERE (sa.id = op.application_id OR lower(sa.email) = lower(mem.email))
                 AND sa.vep_status_raw IN ('Active', 'Complete')
               ORDER BY sa.vep_last_seen_at DESC NULLS LAST LIMIT 1)
             WHEN 'start_trail' THEN (
               -- a mesma regra do lote auto_detect_onboarding_completions: existe ponto de trilha.
               SELECT jsonb_build_object('kind', 'trail', 'courses', count(*),
                                         'at', min(COALESCE(gp.occurred_at, gp.created_at)))
               FROM gamification_points gp
               WHERE gp.member_id = mem.id AND gp.category = 'trail'
               HAVING count(*) > 0)
             WHEN 'first_meeting' THEN (
               -- o fato decide pela EXISTÊNCIA da presença, em qualquer evento; o título e o id só saem
               -- a quem pode ver a iniciativa do evento (ADR-0105, #785): evento de iniciativa
               -- confidencial vira 'restricted' para a presidência ou o líder de linha.
               SELECT jsonb_build_object('kind', 'attendance', 'at', e.date)
                      || CASE WHEN public.rls_can_see_initiative(e.initiative_id)
                              THEN jsonb_build_object('event_id', e.id, 'title', e.title)
                              ELSE jsonb_build_object('restricted', true)
                         END
               FROM attendance a JOIN events e ON e.id = a.event_id
               WHERE a.member_id = mem.id AND a.present
               ORDER BY e.date ASC NULLS LAST LIMIT 1)
             WHEN 'meet_tribe' THEN (
               -- a tribo atual; sem tribo hoje, qualquer tribo (quem saiu da tribo esteve nela).
               SELECT jsonb_build_object('kind', 'tribe_attendance', 'event_id', e.id, 'title', e.title,
                                         'at', e.date, 'tribe_id', i.legacy_tribe_id)
               FROM attendance a JOIN events e ON e.id = a.event_id JOIN initiatives i ON i.id = e.initiative_id
               WHERE a.member_id = mem.id AND a.present
                 AND i.legacy_tribe_id IS NOT NULL
                 AND (mem.tribe_id IS NULL OR i.legacy_tribe_id = mem.tribe_id)
               ORDER BY e.date ASC NULLS LAST LIMIT 1)
           END AS evidence
    FROM mem
    JOIN onboarding_steps s ON public.onboarding_step_applies(s.applies_to_role, mem.journey_role)
    LEFT JOIN onboarding_progress op ON op.member_id = mem.id AND op.step_key = s.id
  ),
  srcd AS (
    SELECT r.*,
           CASE
             WHEN r.status IS DISTINCT FROM 'completed' THEN NULL
             WHEN r.metadata->>'closed_by' = 'gp' THEN 'gp'
             WHEN r.step_closed_by = 'member' THEN 'clique'
             WHEN r.evidence IS NOT NULL THEN 'fato'
             ELSE 'sem_evidencia'
           END AS source
    FROM jr r
  )
  SELECT jsonb_build_object(
    'scope', jsonb_build_object('global', v_global,
                                'chapter', CASE WHEN v_chapter_scope THEN v_chapter END,
                                'lines', to_jsonb(v_lines)),
    'steps', (SELECT jsonb_agg(jsonb_build_object(
                'id', s.id, 'step_order', s.step_order, 'closed_by', s.closed_by, 'is_required', s.is_required,
                'label_pt', s.label_pt, 'label_en', s.label_en, 'label_es', s.label_es) ORDER BY s.step_order)
              FROM onboarding_steps s),
    'members', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'member_id', mem.id, 'name', mem.name, 'chapter', mem.chapter, 'tribe_id', mem.tribe_id,
               'operational_role', mem.operational_role, 'journey_role', mem.journey_role,
               'member_status', mem.member_status,
               'steps', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                           'step_key', x.step_key,
                           'status', COALESCE(x.status, 'not_seeded'),
                           'completed_at', x.completed_at,
                           'sla_deadline', x.sla_deadline,
                           'source', x.source,
                           'evidence', x.evidence,
                           'gp', CASE WHEN x.metadata->>'closed_by' = 'gp' THEN jsonb_build_object(
                                   'member_id', x.metadata->>'gp_member_id',
                                   'name', (SELECT g.name FROM members g WHERE g.id::text = x.metadata->>'gp_member_id'),
                                   'note', x.metadata->>'gp_note', 'at', x.metadata->>'gp_at') END,
                           'reopen_history', x.metadata->'reopen_history'
                         ) ORDER BY x.step_order)
                         FROM srcd x WHERE x.member_id = mem.id), '[]'::jsonb)
             ) ORDER BY mem.name)
      FROM mem), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
