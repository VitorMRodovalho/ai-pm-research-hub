-- #3168: o aviso de filiacao pendente (entry_chapter_action_needed) sai tambem na aprovacao, sob o mesmo interruptor.
--
-- Ordem da issue cumprida: o cron affiliation-action-needed-nudge-daily disparou em 23/11/2026 12:30 UTC com o aviso
-- ligado, antes deste gatilho existir.
--
-- Nada de segunda regra. A variante e o envio saem do cron para funcoes unicas, que o cron e a aprovacao chamam:
--   - affiliation_nudge_variant(member): o CASE que estava em affiliation_nudge_plan, para um membro. O plano passa a
--     chama-la, com a mesma coorte (member_status active e affiliation_needs_review) e a mesma ordem;
--   - affiliation_nudge_deliver(member, variant): o dedupe de 30 dias e o create_notification que estavam no laco de
--     nudge_entry_chapter_cohort. Devolve true se enviou, false se o dedupe barrou. O cron passa a chama-la; o resto do
--     corpo dele fica igual;
--   - affiliation_nudge_on_approval(member): desligado => 'disabled', sem ler mais nada; fora da coorte do cron =>
--     'not_needed'; na coorte sem variante (a VEP mostra filiacao e o portao nao abriu) => 'internal_only'; senao
--     deliver, 'sent' ou 'skipped_recent'. Devolve {status, variant};
--   - approve_selection_application: corpo identico a captura vigente (20261120043026, md5 normalizado d9a3759a
--     conferido contra o vivo pela orquestradora em 23/11/2026), mais a chamada depois do aviso de aprovado e o campo
--     'affiliation_nudge' no log e no retorno.
--
-- Sem duplicar com o cron: a aprovacao grava o mesmo tipo, e o dedupe do cron le o tipo nos ultimos 30 dias.
-- Erro no envio derruba a aprovacao, como ja acontece com o aviso de aprovado: nada e engolido em silencio.
--
-- Rollback: recriar affiliation_nudge_plan e nudge_entry_chapter_cohort pela captura 20261120204018 e
-- approve_selection_application pela 20261120043026; DROP FUNCTION public.affiliation_nudge_on_approval(uuid),
-- public.affiliation_nudge_deliver(uuid, text), public.affiliation_nudge_variant(uuid).

-- 0) o plano de antes, para a pos-condicao provar que ele nao mudou
-- sem ON COMMIT DROP: se a migration nao rodar numa transacao, ela sumiria antes da pos-condicao
CREATE TEMP TABLE _3168_plano_antes AS
  SELECT member_id, variant FROM public.affiliation_nudge_plan();

-- 1) a variante de um membro, num lugar so
CREATE FUNCTION public.affiliation_nudge_variant(p_member_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
           WHEN x.reason = 'entry_chapter_required'          THEN 'ambiguous'
           WHEN x.reason = 'not_affiliated'                  THEN 'not_affiliated'
           WHEN x.bucket = 'profile_private'                 THEN 'profile_private'
           WHEN x.bucket IS NULL OR x.bucket = 'no_fetch'    THEN 'no_fetch'
           ELSE NULL  -- a VEP mostra filiacao e o portao nao abriu: trabalho da Diretoria, nao da pessoa
         END
  FROM (
    SELECT public.affiliation_gate(p_member_id) ->> 'reason' AS reason,
           public.affiliation_vep_snapshot(p_member_id) ->> 'bucket' AS bucket
  ) x;
$function$;

-- 2) o plano chama a variante
CREATE OR REPLACE FUNCTION public.affiliation_nudge_plan()
 RETURNS TABLE(member_id uuid, variant text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT m.id AS member_id,
         public.affiliation_nudge_variant(m.id) AS variant
  FROM public.members m
  WHERE m.member_status = 'active'
    AND public.affiliation_needs_review(m.id)
  ORDER BY m.id;
$function$;

-- 3) dedupe e envio, num lugar so
CREATE FUNCTION public.affiliation_nudge_deliver(p_member_id uuid, p_variant text)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_text jsonb;
BEGIN
  -- Dedup: do not re-fire if this member already got the nudge in the last 30 days.
  IF EXISTS (
    SELECT 1 FROM public.notifications n
    WHERE n.recipient_id = p_member_id
      AND n.type = 'entry_chapter_action_needed'
      AND n.created_at > now() - interval '30 days'
  ) THEN
    RETURN false;
  END IF;

  v_text := public.affiliation_nudge_text(p_variant);
  PERFORM public.create_notification(
    p_member_id,
    'entry_chapter_action_needed',
    v_text ->> 'title',
    v_text ->> 'body',
    '/profile#entry-chapter-card',
    'affiliation_nudge.' || p_variant,
    NULL::uuid
  );
  RETURN true;
END;
$function$;

-- 4) o gatilho da aprovacao
CREATE FUNCTION public.affiliation_nudge_on_approval(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_variant text;
BEGIN
  IF NOT public.affiliation_nudge_enabled() THEN
    RETURN jsonb_build_object('status', 'disabled', 'variant', NULL);
  END IF;

  -- a mesma coorte do plano do cron
  IF NOT EXISTS (SELECT 1 FROM public.members m WHERE m.id = p_member_id AND m.member_status = 'active')
     OR NOT public.affiliation_needs_review(p_member_id) THEN
    RETURN jsonb_build_object('status', 'not_needed', 'variant', NULL);
  END IF;

  v_variant := public.affiliation_nudge_variant(p_member_id);
  IF v_variant IS NULL THEN
    RETURN jsonb_build_object('status', 'internal_only', 'variant', NULL);
  END IF;

  IF public.affiliation_nudge_deliver(p_member_id, v_variant) THEN
    RETURN jsonb_build_object('status', 'sent', 'variant', v_variant);
  END IF;
  RETURN jsonb_build_object('status', 'skipped_recent', 'variant', v_variant);
END;
$function$;

REVOKE ALL ON FUNCTION public.affiliation_nudge_variant(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.affiliation_nudge_deliver(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.affiliation_nudge_on_approval(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.affiliation_nudge_variant(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.affiliation_nudge_deliver(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.affiliation_nudge_on_approval(uuid) TO service_role;

-- 5) o cron chama o envio unico
CREATE OR REPLACE FUNCTION public.nudge_entry_chapter_cohort(p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_enabled   boolean;
  v_rec       record;
  v_sent      int := 0;
  v_skipped   int := 0;
  v_internal  int := 0;
  v_plan      jsonb := '[]'::jsonb;
BEGIN
  -- manage_platform, or service_role/postgres (cron/tests) — same gate as before (#684).
  IF auth.uid() IS NOT NULL THEN
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'Unauthorized: nudge_entry_chapter_cohort requires manage_platform';
    END IF;
  ELSIF public._request_is_rest_caller() THEN
    RAISE EXCEPTION 'Unauthorized: nudge_entry_chapter_cohort requires authentication';
  END IF;

  v_enabled := public.affiliation_nudge_enabled();

  FOR v_rec IN SELECT p.member_id, p.variant FROM public.affiliation_nudge_plan() p LOOP
    IF v_rec.variant IS NULL THEN
      v_internal := v_internal + 1;
      CONTINUE;
    END IF;

    -- O plano leva so o id opaco e a variante: o ensaio nao expoe nome.
    v_plan := v_plan || jsonb_build_object('member_id', v_rec.member_id, 'variant', v_rec.variant);

    -- Nada sai em ensaio, nem com o aviso desligado (a chave e ligada e pausada pela tela de /admin/filiacao).
    IF p_dry_run OR NOT v_enabled THEN
      CONTINUE;
    END IF;

    -- #3168: dedupe de 30 dias e envio num lugar so, o mesmo da aprovacao.
    IF NOT public.affiliation_nudge_deliver(v_rec.member_id, v_rec.variant) THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;
    v_sent := v_sent + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'dry_run', p_dry_run,
    'enabled', v_enabled,
    'paused', NOT p_dry_run AND NOT v_enabled,
    'candidates', jsonb_array_length(v_plan),
    'internal_only', v_internal,
    'sent', v_sent,
    'skipped_recent', v_skipped,
    'plan', v_plan
  );
END;
$function$;

-- 6) a aprovacao chama o gatilho
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
  v_affiliation_nudge jsonb;
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

  -- #3168: o aviso de filiacao pendente tambem na aprovacao, sob o mesmo interruptor e com o mesmo dedupe do cron.
  -- Depois do aviso de aprovado, para a pessoa receber primeiro a boa noticia.
  v_affiliation_nudge := public.affiliation_nudge_on_approval(v_member_id);

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
      'affiliation_gate',        v_affiliation_gate,
      'affiliation_nudge',       v_affiliation_nudge
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
    'affiliation_gate',        v_affiliation_gate,
    'affiliation_nudge',       v_affiliation_nudge
  );
END;
$function$;

-- 7) as ACLs de sempre, repetidas (CREATE OR REPLACE ja as preserva)
REVOKE ALL ON FUNCTION public.affiliation_nudge_plan() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.affiliation_nudge_plan() TO service_role;
REVOKE ALL ON FUNCTION public.nudge_entry_chapter_cohort(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.nudge_entry_chapter_cohort(boolean) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.approve_selection_application(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_selection_application(uuid, jsonb) TO authenticated, service_role;

-- pos-condicao, sem enviar nada
DO $postcondition$
DECLARE
  v_diff int;
BEGIN
  SELECT count(*) INTO v_diff FROM (
    (SELECT member_id, variant FROM _3168_plano_antes
     EXCEPT ALL SELECT member_id, variant FROM public.affiliation_nudge_plan())
    UNION ALL
    (SELECT member_id, variant FROM public.affiliation_nudge_plan()
     EXCEPT ALL SELECT member_id, variant FROM _3168_plano_antes)
  ) d;
  IF v_diff <> 0 THEN
    RAISE EXCEPTION '#3168: o plano mudou com a variante fatorada (% linhas diferentes)', v_diff;
  END IF;

  IF has_function_privilege('anon', 'public.affiliation_nudge_on_approval(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.affiliation_nudge_on_approval(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.affiliation_nudge_deliver(uuid, text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.affiliation_nudge_variant(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '#3168: uma funcao interna do aviso ficou exposta';
  END IF;
  IF has_function_privilege('anon', 'public.approve_selection_application(uuid, jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.nudge_entry_chapter_cohort(boolean)', 'EXECUTE') THEN
    RAISE EXCEPTION '#3168: anon executa a aprovacao ou o aviso';
  END IF;
  RAISE NOTICE '#3168 ok: plano igual (% linhas)', (SELECT count(*) FROM _3168_plano_antes);
END
$postcondition$;

DROP TABLE _3168_plano_antes;

NOTIFY pgrst, 'reload schema';
