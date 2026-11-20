-- #3100: o portao de filiacao chega a selecao.
--
-- O portao (affiliation_gate, #2585) so rodava na assinatura do Termo de Voluntariado, no fim do onboarding. Quem nao
-- tem afiliacao verificada a um capitulo participante era aprovado, ganhava o vinculo volunteer ativo na aprovacao,
-- entrava na contagem de voluntarios e ficava parado no termo. Medido em 19/11/2026: um voluntario ativo nessa situacao.
--
-- Esta migration NAO cria uma segunda regra. Ela:
--   1) fatora em affiliation_gate_first_term a regra que get_my_affiliation_gate ja aplicava (renovacao passa; primeiro
--      termo, operational_role = 'guest', le affiliation_gate). get_my_affiliation_gate passa a delegar, sem mudar o
--      resultado;
--   2) approve_selection_application devolve o portao no resultado ('affiliation_gate') e grava no data_anomaly_log.
--      AVISA, NAO BLOQUEIA: o dado de filiacao da candidatura e uma foto da busca na VEP (pmi_data_fetched_at), a pessoa
--      pode se filiar depois dela, e o caminho B do portao (verificacao manual da Diretoria de Filiacao) e gravado por
--      member_id, que so existe a partir da aprovacao. Bloquear tiraria de quem se filia depois o unico caminho de entrada.
--      Corpo identico a captura vigente (20260816040153, md5 do corpo normalizado conferido contra o vivo em 19/11/2026),
--      mais a leitura do portao depois do vinculo e o campo novo no retorno e no log;
--   3) get_volunteers_with_closed_affiliation_gate: lista quem tem vinculo volunteer ativo e o portao fechado, com o
--      motivo. Mesma audiencia da fila de filiacao (filiacao_director ou manage_member).

-- 1) a regra do primeiro termo, num lugar so
CREATE OR REPLACE FUNCTION public.affiliation_gate_first_term(p_member_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Renovacao nao passa pelo portao (mesma regra do termo): o portao so vale para o primeiro termo.
  RETURN CASE
    WHEN EXISTS (SELECT 1 FROM public.members WHERE id = p_member_id AND operational_role IS DISTINCT FROM 'guest')
      THEN jsonb_build_object('open', true, 'path', 'renewal')
    ELSE public.affiliation_gate(p_member_id)
  END;
END;
$function$;

-- 2) a tela do termo le o portao da propria pessoa pela mesma regra
CREATE OR REPLACE FUNCTION public.get_my_affiliation_gate()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- E checagem de estado da propria pessoa, nao de autoridade.
  RETURN public.affiliation_gate_first_term(v_member_id);
END;
$function$;

-- 3) a aprovacao devolve o portao
CREATE OR REPLACE FUNCTION public.approve_selection_application(p_application_id uuid, p_decision jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id        uuid;
  v_caller_name      text;
  v_caller_person_id uuid;
  v_caller_org_id    uuid;
  v_app              record;
  v_member_id        uuid;
  v_person_id        uuid;
  v_member_role      text;
  v_member_status    text;
  v_target_role      text;
  v_engagement_role  text;
  v_engagement_kind  text := 'volunteer';
  v_legal_basis      text := 'contract';
  v_cycle_end_date   date;
  v_member_chapter   text;
  v_default_days     int;
  v_requires_agreement boolean;
  v_engagement_id    uuid;
  v_existing_engagement_id uuid;
  v_seeded_count     int := 0;
  v_promoted         boolean := false;
  v_member_created   boolean := false;
  v_person_created   boolean := false;
  v_engagement_created boolean := false;
  v_classify         jsonb;
  v_br_codes         text[];
  v_code             text;
  v_entry_derived    text;
  v_affiliation_gate jsonb;
BEGIN
  SELECT id, name, person_id, organization_id
    INTO v_caller_id, v_caller_name, v_caller_person_id, v_caller_org_id
  FROM public.members WHERE auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Application not found');
  END IF;
  IF v_app.status NOT IN ('approved', 'converted') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Application status must be approved or converted',
      'current_status', v_app.status
    );
  END IF;
  IF v_app.email IS NULL OR length(trim(v_app.email)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Application has no email');
  END IF;

  SELECT sc.close_date
    INTO v_cycle_end_date
  FROM public.selection_cycles sc
  WHERE sc.id = v_app.cycle_id;

  IF v_cycle_end_date IS NOT NULL AND v_cycle_end_date < CURRENT_DATE THEN
    v_cycle_end_date := NULL;
  END IF;

  v_member_chapter := COALESCE(
    NULLIF(trim(v_app.chapter), ''),
    'Outro'
  );

  v_target_role := CASE
    WHEN v_app.role_applied = 'leader'     THEN 'tribe_leader'
    WHEN v_app.role_applied = 'researcher' THEN 'researcher'
    ELSE NULL
  END;

  -- #1163: match the member by pmi_id first (stable identity key), email as fallback. Matching by
  -- email alone missed members whose PMI-registered email diverges from the application email, then
  -- the INSERT path collided on members_pmi_id_key (UNIQUE pmi_id) -> 23505 -> PostgREST 409.
  SELECT id, person_id, operational_role, member_status
    INTO v_member_id, v_person_id, v_member_role, v_member_status
  FROM public.members
  WHERE (NULLIF(trim(v_app.pmi_id), '') IS NOT NULL AND pmi_id = NULLIF(trim(v_app.pmi_id), ''))
     OR lower(email) = lower(v_app.email)
  ORDER BY CASE
    WHEN NULLIF(trim(v_app.pmi_id), '') IS NOT NULL AND pmi_id = NULLIF(trim(v_app.pmi_id), '') THEN 0
    ELSE 1
  END
  LIMIT 1;

  IF v_member_id IS NULL THEN
    INSERT INTO public.members (
      organization_id,
      name, email, pmi_id, chapter,
      operational_role, is_active, current_cycle_active
    )
    VALUES (
      v_app.organization_id,
      v_app.applicant_name, v_app.email, v_app.pmi_id, v_member_chapter,
      COALESCE(v_target_role, 'researcher'),
      true, true
    )
    RETURNING id, person_id, operational_role, member_status
      INTO v_member_id, v_person_id, v_member_role, v_member_status;
    v_member_created := true;
  ELSE
    UPDATE public.members SET
      is_active = true,
      current_cycle_active = true,
      updated_at = now()
    WHERE id = v_member_id
      AND (is_active = false OR current_cycle_active = false);

    -- #1163: a researcher approved on the leader track is a genuine elevation to tribe_leader.
    -- The prior set omitted 'researcher', so leader promotions of an already-active researcher
    -- silently did not take effect. Only researcher -> tribe_leader is added here; this is never a
    -- demotion (target 'researcher' does not promote a researcher, higher roles are left untouched).
    IF v_target_role IS NOT NULL
       AND v_member_status = 'active'
       AND (
         v_member_role IN ('observer', 'guest', 'none', 'alumni', 'inactive')
         OR (v_member_role = 'researcher' AND v_target_role = 'tribe_leader')
       )
    THEN
      UPDATE public.members
      SET operational_role = v_target_role, updated_at = now()
      WHERE id = v_member_id;
      v_promoted := true;
    END IF;
  END IF;

  IF v_person_id IS NULL THEN
    -- #1163: same identity-drift class — prefer pmi_id so we do not fork identity into a duplicate
    -- person (persons has no unique on pmi_id/email, so an email-only match silently created one).
    SELECT id INTO v_person_id
    FROM public.persons
    WHERE (NULLIF(trim(v_app.pmi_id), '') IS NOT NULL AND pmi_id = NULLIF(trim(v_app.pmi_id), ''))
       OR lower(email) = lower(v_app.email)
    ORDER BY CASE
      WHEN NULLIF(trim(v_app.pmi_id), '') IS NOT NULL AND pmi_id = NULLIF(trim(v_app.pmi_id), '') THEN 0
      ELSE 1
    END
    LIMIT 1;

    IF v_person_id IS NULL THEN
      INSERT INTO public.persons (
        organization_id, name, email, pmi_id, phone,
        consent_status, legacy_member_id
      )
      VALUES (
        v_app.organization_id,
        v_app.applicant_name, v_app.email, v_app.pmi_id, v_app.phone,
        'pending', v_member_id
      )
      RETURNING id INTO v_person_id;
      v_person_created := true;
    END IF;

    UPDATE public.members SET person_id = v_person_id, updated_at = now()
    WHERE id = v_member_id AND person_id IS NULL;
  END IF;

  IF v_person_id IS NOT NULL THEN
    v_classify := public.classify_entry_chapter(
      v_app.pmi_memberships, v_app.community_profile_private, v_app.pmi_data_fetched_at
    );
    v_br_codes := ARRAY(SELECT jsonb_array_elements_text(v_classify->'active_br_codes'));

    IF v_br_codes IS NOT NULL AND array_length(v_br_codes, 1) >= 1 THEN
      FOREACH v_code IN ARRAY v_br_codes LOOP
        PERFORM public.upsert_chapter_affiliation(v_person_id, v_code, 'pmi_vep', false);
      END LOOP;

      IF array_length(v_br_codes, 1) = 1 THEN
        v_entry_derived := v_br_codes[1];
        UPDATE public.members
        SET entry_chapter_code = v_entry_derived, updated_at = now()
        WHERE id = v_member_id AND entry_chapter_code IS DISTINCT FROM v_entry_derived;
      END IF;
    END IF;
  END IF;

  v_engagement_role := CASE
    -- #1805: 'coordinator' saiu da lista -- nao existe no dominio do CHECK de
    -- role_applied ('researcher','leader','both','manager'), entao era ramo
    -- morto. 'both' NAO entra aqui de proposito: cai no ELSE e vira researcher,
    -- comportamento preexistente e inalterado por esta correcao.
    WHEN v_app.role_applied IN ('leader', 'researcher', 'manager') THEN v_app.role_applied
    ELSE 'researcher'
  END;

  SELECT ek.default_duration_days, ek.requires_agreement
    INTO v_default_days, v_requires_agreement
  FROM public.engagement_kinds ek WHERE ek.slug = v_engagement_kind;

  SELECT id INTO v_existing_engagement_id
  FROM public.engagements
  WHERE person_id = v_person_id
    AND kind = v_engagement_kind
    AND status = 'active'
  ORDER BY start_date DESC
  LIMIT 1;

  IF v_existing_engagement_id IS NULL THEN
    INSERT INTO public.engagements (
      person_id, organization_id,
      kind, role, status,
      start_date, end_date,
      legal_basis,
      selection_application_id,
      granted_by, granted_at,
      metadata
    )
    VALUES (
      v_person_id,
      v_app.organization_id,
      v_engagement_kind, v_engagement_role, 'active',
      CURRENT_DATE,
      -- #1362: prefer the Núcleo contract end (#1316 SSOT) so the engagement authority window covers
      -- the full contract, not just the cycle close (a 1-year contract crosses two semesters).
      COALESCE(
        v_app.nucleo_contract_end,
        v_cycle_end_date,
        CURRENT_DATE + (COALESCE(v_default_days, 180) || ' days')::interval
      ),
      v_legal_basis,
      p_application_id,
      v_caller_person_id,
      now(),
      jsonb_build_object(
        'source', 'approve_selection_application',
        'role_applied', v_app.role_applied,
        'application_status', v_app.status,
        'chapter_source', CASE
          WHEN NULLIF(trim(v_app.chapter), '') IS NOT NULL THEN 'application'
          ELSE 'no_chapter_declared'
        END,
        'member_chapter', v_member_chapter
      )
    )
    RETURNING id INTO v_engagement_id;
    v_engagement_created := true;
  ELSE
    -- #1362: a promotion/renewal re-points the existing active engagement at the newly-approved
    -- application. The authority window (auth_engagements.is_authoritative requires
    -- end_date >= CURRENT_DATE) must track the new contract, otherwise a leader promoted off a
    -- researcher contract keeps the OLD end_date and silently drops to guest once it passes (the
    -- 2026-07-13 Paulo regression). Extend end_date to the new contract end when it lasts longer;
    -- never shrink a perpetual (NULL) or already-longer window. The application pointer keeps its
    -- prior set-if-null semantics.
    UPDATE public.engagements
    SET selection_application_id = COALESCE(selection_application_id, p_application_id),
        end_date = CASE
          WHEN end_date IS NOT NULL
           AND v_app.nucleo_contract_end IS NOT NULL
           AND end_date < v_app.nucleo_contract_end
          THEN v_app.nucleo_contract_end
          ELSE end_date
        END,
        updated_at = now()
    WHERE id = v_existing_engagement_id;
    v_engagement_id := v_existing_engagement_id;
  END IF;

  INSERT INTO public.onboarding_progress (application_id, member_id, step_key, status, metadata)
  SELECT p_application_id, v_member_id, s.id, 'pending', '{}'::jsonb
  FROM public.onboarding_steps s
  WHERE s.is_required = true
    AND NOT (s.id = 'volunteer_term' AND NOT COALESCE(v_requires_agreement, FALSE))
    AND public.onboarding_step_applies(s.applies_to_role, COALESCE(v_target_role, 'researcher'))
    AND NOT EXISTS (
      SELECT 1 FROM public.onboarding_progress op
      WHERE op.member_id = v_member_id AND op.step_key = s.id
    );
  GET DIAGNOSTICS v_seeded_count = ROW_COUNT;

  INSERT INTO public.onboarding_progress (application_id, member_id, step_key, status, sla_deadline)
  SELECT p_application_id, v_member_id, (step->>'key'), 'pending',
         now() + ((step->>'sla_days')::int || ' days')::interval
  FROM public.selection_cycles sc, jsonb_array_elements(sc.onboarding_steps) AS step
  WHERE sc.id = v_app.cycle_id
    AND NOT EXISTS (
      SELECT 1 FROM public.onboarding_progress
      WHERE member_id = v_member_id AND step_key = (step->>'key')
    );

  PERFORM public.check_pre_onboarding_auto_steps(v_member_id);

  -- #3100: o portao de filiacao, lido no instante da aprovacao. Avisa, nao bloqueia: o dado da VEP da candidatura
  -- e uma foto da data da busca, e o caminho B (verificacao manual da Diretoria de Filiacao) so existe depois que o
  -- membro existe. Lido aqui, depois do vinculo e das afiliacoes acima, porque o papel operacional (guest = primeiro
  -- termo) so se acomoda depois do vinculo, e as afiliacoes pmi_vep acabaram de ser gravadas a partir da candidatura.
  v_affiliation_gate := public.affiliation_gate_first_term(v_member_id);

  IF NOT EXISTS (
    SELECT 1 FROM public.notifications
    WHERE recipient_id = v_member_id
      AND type = 'selection_approved'
      AND source_id = p_application_id
  ) THEN
    PERFORM public.create_notification(
      v_member_id,
      'selection_approved',
      'Parabens! Voce foi aprovado no Nucleo IA',
      'Sua candidatura foi aprovada. Acesse a plataforma para iniciar o onboarding.',
      '/onboarding',
      'selection_application',
      p_application_id
    );
  END IF;

  INSERT INTO public.data_anomaly_log (anomaly_type, severity, description, context)
  VALUES (
    'selection_approval_canonical',
    'info',
    'Canonical approval for ' || v_app.applicant_name || ' (' || v_app.status || ')',
    jsonb_build_object(
      'application_id',     p_application_id,
      'application_status', v_app.status,
      'actor_id',           v_caller_id,
      'actor_name',         v_caller_name,
      'member_id',          v_member_id,
      'person_id',          v_person_id,
      'engagement_id',      v_engagement_id,
      'member_created',     v_member_created,
      'person_created',     v_person_created,
      'engagement_created', v_engagement_created,
      'onboarding_seeded',  v_seeded_count,
      'role_promoted',      v_promoted,
      'promoted_to',        CASE WHEN v_promoted THEN v_target_role ELSE NULL END,
      'requires_agreement', v_requires_agreement,
      'agreement_pending',  v_requires_agreement,
      'member_chapter',     v_member_chapter,
      'chapter_source',     CASE
        WHEN NULLIF(trim(v_app.chapter), '') IS NOT NULL THEN 'application'
        ELSE 'no_chapter_declared'
      END,
      'chapter_diagnosis',      v_classify->>'bucket',
      'chapter_active_br_codes', COALESCE(v_classify->'active_br_codes', '[]'::jsonb),
      'entry_chapter_derived',   v_entry_derived,
      'affiliation_gate',        v_affiliation_gate
    )
  );

  RETURN jsonb_build_object(
    'success',            true,
    'application_id',     p_application_id,
    'member_id',          v_member_id,
    'person_id',          v_person_id,
    'engagement_id',      v_engagement_id,
    'member_created',     v_member_created,
    'person_created',     v_person_created,
    'engagement_created', v_engagement_created,
    'onboarding_seeded',  v_seeded_count,
    'role_promoted',      v_promoted,
    'promoted_to',        CASE WHEN v_promoted THEN v_target_role ELSE NULL END,
    'agreement_pending',  v_requires_agreement,
    'member_chapter',     v_member_chapter,
    'chapter_diagnosis',      v_classify->>'bucket',
    'chapter_active_br_codes', COALESCE(v_classify->'active_br_codes', '[]'::jsonb),
    'entry_chapter_derived',   v_entry_derived,
    'affiliation_gate',        v_affiliation_gate
  );
END;
$function$;

-- 4) quem ja tem vinculo volunteer ativo e o portao fechado
CREATE OR REPLACE FUNCTION public.get_volunteers_with_closed_affiliation_gate()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id           uuid;
  v_caller_designations text[];
BEGIN
  -- Mesma audiencia da fila de filiacao (get_affiliation_verification_queue): filiacao_director OR manage_member.
  SELECT m.id, m.designations INTO v_caller_id, v_caller_designations
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT ('filiacao_director' = ANY(COALESCE(v_caller_designations, '{}'::text[])))
     AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Forbidden: requires filiacao_director designation or platform manager authority'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- O portao cru (affiliation_gate), nao o do primeiro termo: quem ja assinou tambem aparece, marcado por first_term,
  -- porque a pergunta aqui e "esta pessoa conta como voluntario sem filiacao verificada?".
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'member_id',        x.id,
      'name',             x.name,
      'chapter',          x.chapter,
      'operational_role', x.operational_role,
      'first_term',       x.operational_role = 'guest',
      'engagement_start', x.engagement_start,
      'reason',           x.gate ->> 'reason',
      'chapters',         COALESCE(x.gate -> 'chapters', '[]'::jsonb)
    ) ORDER BY (x.operational_role = 'guest') DESC, x.engagement_start DESC, x.name)
    FROM (
      SELECT m.id, m.name, m.chapter, m.operational_role, v.engagement_start,
             public.affiliation_gate(m.id) AS gate
      FROM public.members m
      JOIN LATERAL (
        SELECT max(e.start_date) AS engagement_start
        FROM public.engagements e
        WHERE e.person_id = m.person_id AND e.kind = 'volunteer' AND e.status = 'active'
      ) v ON v.engagement_start IS NOT NULL
    ) x
    WHERE NOT COALESCE((x.gate ->> 'open')::boolean, false)
  ), '[]'::jsonb);
END;
$function$;

-- 5) audiencia das reunioes da organizacao (target_type 'all_active_operational'), decisao do GP em 19/11/2026:
--    o voluntario aceito em onboarding (operational_role = 'guest' com vinculo volunteer ativo) faz parte dela.
--    Antes, register_own_presence e get_my_meetings excluiam todo guest, e essas pessoas recebiam 'not_in_audience'
--    na Reuniao Geral. A regra passa a morar aqui, e as duas leitoras chamam esta funcao.
--    De proposito NAO muda: o selo de presenca (_seal_event_attendance_apply / preview_seal_attendance), que monta a
--    coorte de faltas por v_member_operational_tiers (researcher, tribe_leader, manager) e nao por esta regra. Quem
--    esta em onboarding pode marcar presenca, mas o selo nao grava falta para essa pessoa.
CREATE OR REPLACE FUNCTION public._in_all_active_operational(p_member_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT COALESCE((
    SELECT m.current_cycle_active IS TRUE
       AND (m.operational_role <> 'guest'
            OR EXISTS (SELECT 1 FROM public.engagements e
                       WHERE e.person_id = m.person_id AND e.kind = 'volunteer' AND e.status = 'active'))
    FROM public.members m
    WHERE m.id = p_member_id
  ), false)
$function$;

-- 6) check-in: corpo identico a captura vigente (20261113013658), com a audiencia pela funcao acima
CREATE OR REPLACE FUNCTION public.register_own_presence(p_event_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id          uuid;
  v_member_role        text;
  v_member_designations text[];
  v_member_tribe       int;
  v_member_active      boolean;
  v_event_date         date;
  v_event_status       text;
  v_event_ts           timestamptz;
  v_is_admin           boolean;
  v_has_rules          boolean;
  v_in_audience        boolean;
  v_window_hours       int;
BEGIN
  SELECT id, operational_role, designations, tribe_id, current_cycle_active
    INTO v_member_id, v_member_role, v_member_designations, v_member_tribe, v_member_active
  FROM public.members WHERE auth_id = auth.uid();

  IF v_member_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  SELECT date, status INTO v_event_date, v_event_status FROM public.events WHERE id = p_event_id;
  IF v_event_date IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'event_not_found');
  END IF;

  -- #3050: evento cancelado nao recebe check-in, de ninguem.
  IF v_event_status = 'cancelled' THEN
    RETURN json_build_object('success', false, 'error', 'event_cancelled',
      'message', 'Este encontro foi cancelado e nao recebe check-in.');
  END IF;

  v_event_ts := v_event_date::timestamptz;
  v_is_admin := public.can_by_member(v_member_id, 'manage_event'::text);

  -- Time window check: V4 manage_event holders bypass
  IF NOT v_is_admin THEN
    -- self-check-in window (SSOT: platform_settings 'attendance.self_checkin_window_hours', default 72h)
    v_window_hours := COALESCE(
      (public.get_platform_setting('attendance.self_checkin_window_hours') #>> '{}')::int, 72);
    IF now() > v_event_ts + make_interval(hours => v_window_hours) THEN
      RETURN json_build_object('success', false, 'error', 'checkin_window_expired',
        'message', 'O prazo de ' || v_window_hours || 'h para check-in expirou. Solicite ao gestor.');
    END IF;
    IF now() < v_event_ts - interval '2 hours' THEN
      RETURN json_build_object('success', false, 'error', 'checkin_too_early',
        'message', 'O check-in abre 2h antes do evento.');
    END IF;

    -- p276 fix: audience gate — eventos com regras só aceitam quem está na regra.
    SELECT EXISTS (
      SELECT 1 FROM public.event_audience_rules
      WHERE event_id = p_event_id AND attendance_type = 'mandatory'
    ) INTO v_has_rules;

    IF v_has_rules THEN
      SELECT EXISTS (
        SELECT 1 FROM public.event_audience_rules ar
        WHERE ar.event_id = p_event_id
          AND ar.attendance_type = 'mandatory'
          AND (
            (ar.target_type = 'role' AND (
              v_member_role = ar.target_value
              OR ar.target_value = ANY(COALESCE(v_member_designations, '{}'))
            ))
            OR (ar.target_type = 'tribe' AND v_member_tribe IS NOT NULL AND v_member_tribe::text = ar.target_value)
            OR (ar.target_type = 'all_active_operational'
                AND public._in_all_active_operational(v_member_id))
            OR (ar.target_type = 'specific_members' AND EXISTS (
              SELECT 1 FROM public.event_invited_members im
              WHERE im.event_id = p_event_id AND im.member_id = v_member_id
            ))
          )
      ) INTO v_in_audience;

      IF NOT v_in_audience THEN
        RETURN json_build_object('success', false, 'error', 'not_in_audience',
          'message', 'Voce nao esta na audiencia prevista para este evento. Solicite ao gestor para marcar presenca.');
      END IF;
    END IF;
  END IF;

  INSERT INTO public.attendance (event_id, member_id, checked_in_at)
  VALUES (p_event_id, v_member_id, now())
  ON CONFLICT (event_id, member_id)
  DO UPDATE SET checked_in_at = now();

  RETURN json_build_object('success', true, 'member_id', v_member_id);
END;
$function$;

-- 7) minhas reunioes: corpo identico a captura vigente (20260805000421), espelho do check-in na audiencia
CREATE OR REPLACE FUNCTION public.get_my_meetings(
  p_days_back integer DEFAULT 30,
  p_days_forward integer DEFAULT 60
)
RETURNS TABLE(
  event_id uuid,
  event_title text,
  event_date date,
  event_type text,
  duration_minutes integer,
  initiative_id uuid,
  initiative_title text,
  attendance_present boolean,
  excused boolean
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_member_id uuid;
  v_tribe_id integer;
  v_member_role text;
  v_member_designations text[];
  v_member_active boolean;
BEGIN
  SELECT m.id, m.tribe_id, m.operational_role, m.designations, m.current_cycle_active
    INTO v_member_id, v_tribe_id, v_member_role, v_member_designations, v_member_active
  FROM public.members m
  WHERE m.auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  RETURN QUERY
  SELECT
    e.id,
    e.title,
    e.date,
    e.type,
    e.duration_minutes,
    e.initiative_id,
    i.title,
    a.present,
    a.excused
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  LEFT JOIN public.attendance a ON a.event_id = e.id AND a.member_id = v_member_id
  WHERE e.status <> 'cancelled'
    AND e.date BETWEEN (CURRENT_DATE - p_days_back) AND (CURRENT_DATE + p_days_forward)
    AND (
      -- tribe events for the caller's tribe (kept explicit: no regression, and covers tribe events
      -- whose audience rule may be absent/atypical).
      (e.initiative_id IS NOT NULL AND i.legacy_tribe_id = v_tribe_id)
      -- OR the caller is in the event's mandatory audience — mirrors register_own_presence exactly.
      OR EXISTS (
        SELECT 1 FROM public.event_audience_rules ar
        WHERE ar.event_id = e.id
          AND ar.attendance_type = 'mandatory'
          AND (
            (ar.target_type = 'role' AND (
              v_member_role = ar.target_value
              OR ar.target_value = ANY(COALESCE(v_member_designations, '{}'))
            ))
            OR (ar.target_type = 'tribe' AND v_tribe_id IS NOT NULL AND v_tribe_id::text = ar.target_value)
            OR (ar.target_type = 'all_active_operational'
                AND public._in_all_active_operational(v_member_id))
            OR (ar.target_type = 'specific_members' AND EXISTS (
              SELECT 1 FROM public.event_invited_members im
              WHERE im.event_id = e.id AND im.member_id = v_member_id
            ))
          )
      )
      -- OR the caller already has an attendance record for this event (their own history —
      -- never hide a meeting they actually attended, e.g. bulk-marked at an ad-hoc event).
      OR a.member_id IS NOT NULL
    )
    AND public.rls_can_see_initiative(e.initiative_id)  -- #785 confidential gate
  ORDER BY e.date DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.affiliation_gate_first_term(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.affiliation_gate_first_term(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.get_my_affiliation_gate() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_affiliation_gate() TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.approve_selection_application(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_selection_application(uuid, jsonb) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_volunteers_with_closed_affiliation_gate() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_volunteers_with_closed_affiliation_gate() TO authenticated, service_role;
REVOKE ALL ON FUNCTION public._in_all_active_operational(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._in_all_active_operational(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.get_my_meetings(integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_meetings(integer, integer) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
