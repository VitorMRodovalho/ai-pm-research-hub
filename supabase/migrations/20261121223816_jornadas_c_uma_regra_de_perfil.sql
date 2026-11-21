-- Jornadas fatia C: uma regra de perfil (decisão do GP, 21/11).
--
-- Antes havia quatro caminhos com três listas de campos, e nenhuma das duas regras de onboarding era a do Termo:
--   sign_volunteer_agreement / check_my_tcv_readiness / tela do Termo: pmi_id, phone, address, city, state, country,
--     birth_date (a mesma lista em todas as capturas desde 15/04/2026);
--   check_pre_onboarding_auto_steps: photo_url, phone, linkedin_url, pmi_id, address, city, birth_date;
--   auto_detect_onboarding_completions: 4 de 6 entre name, photo_url, state, country, linkedin_url, pmi_id;
--   o clique (closed_by = 'member').
--
-- 1. complete_profile passa a closed_by = 'fact': as portas de clique já recusam etapa de fato (fatia B).
-- 2. _member_profile_ready(member): os 7 campos da assinatura. O guard compara a lista com sign_volunteer_agreement.
-- 3. check_pre_onboarding_auto_steps e o lote usam o helper. Os três primeiros blocos do lote passam a só tocar
--    pending/overdue de quem a etapa vale (antes, status != 'completed' sobrescreveria um skipped), e todos os blocos
--    leem o papel pela jornada (#3152).
-- 4. Gatilho em members: fecha na hora em que os 7 campos ficam completos. Dispara só por UPDATE OF desses campos,
--    com WHEN de mudança real e membro ativo; sai cedo sem etapa aberta; escreve só em onboarding_progress, e nenhum
--    gatilho dessa tabela escreve em members.
-- 5. get_onboarding_journey_admin: evidência {kind: 'profile'} quando o helper é verdadeiro.
--
-- Só daqui para frente: nada rebaixa completed. Os concluídos sem os 7 campos aparecem como "sem evidência".
-- members.profile_completed_at e o marco profile_complete (primeiro salvamento) não mudam: são outro fato.
-- Guard: tests/contracts/jornadas-fatia-c-uma-regra-de-perfil.test.mjs.

UPDATE public.onboarding_steps SET closed_by = 'fact' WHERE id = 'complete_profile';

CREATE OR REPLACE FUNCTION public._member_profile_ready(p_member_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT COALESCE((
    SELECT m.pmi_id IS NOT NULL AND length(trim(m.pmi_id)) > 0
       AND m.phone IS NOT NULL AND length(trim(m.phone)) > 0
       AND m.address IS NOT NULL AND length(trim(m.address)) > 0
       AND m.city IS NOT NULL AND length(trim(m.city)) > 0
       AND m.state IS NOT NULL AND length(trim(m.state)) > 0
       AND m.country IS NOT NULL AND length(trim(m.country)) > 0
       AND m.birth_date IS NOT NULL
    FROM public.members m WHERE m.id = p_member_id), false);
$function$;

REVOKE ALL ON FUNCTION public._member_profile_ready(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._member_profile_ready(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.check_pre_onboarding_auto_steps(p_member_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_completed int := 0;
  v_member record;
  v_pages int;
  v_has_blog boolean;
  v_profile_complete boolean;
  v_caller_id uuid;
  v_cron_context boolean;
BEGIN
  -- p179 LGPD hardening: defense-in-depth caller auth gate.
  -- Structural protection: REVOKE'd from authenticated. This gate catches
  -- regressions if GRANT changes + ensures internal callers (PERFORM) cannot
  -- bypass when invoked outside the canonical pipeline contexts.
  v_cron_context := (current_setting('role', true) IN ('service_role','postgres')
                     OR current_user IN ('postgres','supabase_admin'));

  IF NOT v_cron_context THEN
    IF auth.uid() IS NULL THEN
      RAISE EXCEPTION 'Unauthorized: authentication required';
    END IF;

    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL THEN
      RAISE EXCEPTION 'Unauthorized: caller is not a registered member';
    END IF;

    IF v_caller_id <> p_member_id
       AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
      RAISE EXCEPTION 'Unauthorized: cannot probe another member''s onboarding';
    END IF;
  END IF;

  SELECT id, auth_id, name, photo_url, credly_url,
         phone, linkedin_url, pmi_id, address, city, birth_date
  INTO v_member
  FROM members WHERE id = p_member_id;

  IF v_member.id IS NULL THEN
    RETURN json_build_object('error', 'Member not found');
  END IF;

  -- Step: create_account
  UPDATE onboarding_progress SET status = 'completed', completed_at = now(), updated_at = now()
  WHERE member_id = p_member_id AND step_key = 'create_account' AND status = 'pending'
  AND v_member.auth_id IS NOT NULL;
  v_completed := v_completed + (SELECT count(*) FROM onboarding_progress WHERE member_id = p_member_id AND step_key = 'create_account' AND status = 'completed' AND completed_at >= now() - interval '1 second');

  -- Step: complete_profile. Jornadas fatia C: a regra única (_member_profile_ready, os 7 campos que a assinatura
  -- do Termo exige), só em etapa aberta e só onde a etapa vale para o papel da jornada (#3152).
  v_profile_complete := public._member_profile_ready(p_member_id);

  UPDATE onboarding_progress op
  SET status = 'completed', completed_at = now(), updated_at = now(),
      metadata = COALESCE(op.metadata, '{}'::jsonb) || jsonb_build_object('completed_via', 'perfil_pronto_para_o_termo')
  WHERE op.member_id = p_member_id AND op.step_key = 'complete_profile' AND op.status IN ('pending', 'overdue')
    AND v_profile_complete
    AND EXISTS (SELECT 1 FROM onboarding_steps s
                WHERE s.id = 'complete_profile'
                  AND public.onboarding_step_applies(s.applies_to_role, public._onboarding_journey_role(p_member_id)));
  v_completed := v_completed + (SELECT count(*) FROM onboarding_progress WHERE member_id = p_member_id AND step_key = 'complete_profile' AND status = 'completed' AND completed_at >= now() - interval '1 second');

  -- Step: setup_credly
  UPDATE onboarding_progress SET status = 'completed', completed_at = now(), updated_at = now()
  WHERE member_id = p_member_id AND step_key = 'setup_credly' AND status = 'pending'
  AND v_member.credly_url IS NOT NULL AND v_member.credly_url != '';
  v_completed := v_completed + (SELECT count(*) FROM onboarding_progress WHERE member_id = p_member_id AND step_key = 'setup_credly' AND status = 'completed' AND completed_at >= now() - interval '1 second');

  -- Step: explore_platform
  SELECT coalesce(sum(pages_visited), 0) INTO v_pages
  FROM member_activity_sessions WHERE member_id = p_member_id;

  UPDATE onboarding_progress SET status = 'completed', completed_at = now(), updated_at = now()
  WHERE member_id = p_member_id AND step_key = 'explore_platform' AND status = 'pending'
  AND v_pages >= 3;
  v_completed := v_completed + (SELECT count(*) FROM onboarding_progress WHERE member_id = p_member_id AND step_key = 'explore_platform' AND status = 'completed' AND completed_at >= now() - interval '1 second');

  -- Step: read_blog
  SELECT EXISTS (
    SELECT 1 FROM member_activity_sessions
    WHERE member_id = p_member_id
    AND (first_page LIKE '%/blog%' OR last_page LIKE '%/blog%')
  ) INTO v_has_blog;

  UPDATE onboarding_progress SET status = 'completed', completed_at = now(), updated_at = now()
  WHERE member_id = p_member_id AND step_key = 'read_blog' AND status = 'pending'
  AND v_has_blog;
  v_completed := v_completed + (SELECT count(*) FROM onboarding_progress WHERE member_id = p_member_id AND step_key = 'read_blog' AND status = 'completed' AND completed_at >= now() - interval '1 second');

  RETURN json_build_object(
    'auto_completed', v_completed,
    'member_id', p_member_id,
    'profile_complete', v_profile_complete
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.auto_detect_onboarding_completions()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Jornadas fatia C: o perfil fecha pela regra única (_member_profile_ready, os 7 campos que a assinatura do Termo
  -- exige), no lugar do "4 de 6". Os três primeiros blocos passam a só tocar pendência de quem a etapa vale.
  -- Todos os blocos leem o papel pelo helper da jornada (#3152).
  INSERT INTO onboarding_progress (member_id, step_key, status, completed_at, metadata)
  SELECT m.id, 'complete_profile', 'completed', now(), jsonb_build_object('completed_via', 'perfil_pronto_para_o_termo')
  FROM members m
  JOIN onboarding_steps s ON s.id = 'complete_profile'
  WHERE m.is_active
    AND public.onboarding_step_applies(s.applies_to_role, public._onboarding_journey_role(m.id))
    AND public._member_profile_ready(m.id)
  ON CONFLICT (member_id, step_key) DO UPDATE
    SET status = 'completed', completed_at = now(), updated_at = now(),
        metadata = COALESCE(onboarding_progress.metadata, '{}'::jsonb) || EXCLUDED.metadata
    WHERE onboarding_progress.status IN ('pending', 'overdue');

  INSERT INTO onboarding_progress (member_id, step_key, status, completed_at)
  SELECT DISTINCT gp.member_id, 'start_trail', 'completed', now()
  FROM gamification_points gp WHERE gp.category = 'trail'
    AND EXISTS (SELECT 1 FROM members m JOIN onboarding_steps s ON s.id = 'start_trail'
                WHERE m.id = gp.member_id AND m.is_active
                  AND public.onboarding_step_applies(s.applies_to_role, public._onboarding_journey_role(m.id)))
  ON CONFLICT (member_id, step_key) DO UPDATE SET status = 'completed', completed_at = now(), updated_at = now()
    WHERE onboarding_progress.status IN ('pending', 'overdue');

  -- PR11 sealing-safety: 'first_meeting' completes only on a PRESENT row (the batch twin of the
  -- auto_complete_first_meeting trigger guard) — a sealed absent row must not complete onboarding.
  INSERT INTO onboarding_progress (member_id, step_key, status, completed_at)
  SELECT DISTINCT a.member_id, 'first_meeting', 'completed', now()
  FROM attendance a
  WHERE a.present = true
    AND EXISTS (SELECT 1 FROM members m JOIN onboarding_steps s ON s.id = 'first_meeting'
                WHERE m.id = a.member_id AND m.is_active
                  AND public.onboarding_step_applies(s.applies_to_role, public._onboarding_journey_role(m.id)))
  ON CONFLICT (member_id, step_key) DO UPDATE SET status = 'completed', completed_at = now(), updated_at = now()
    WHERE onboarding_progress.status IN ('pending', 'overdue');

  -- #2718 regra 1: "Conheça sua tribo" fecha pela presença numa reunião da iniciativa da própria tribo.
  -- Os três blocos #2718 só tocam pendência de quem a etapa vale: concluído e dispensado ficam intocados.
  INSERT INTO onboarding_progress (member_id, step_key, status, completed_at, metadata)
  SELECT m.id, 'meet_tribe', 'completed', now(), jsonb_build_object('completed_via', '2718_presenca_na_tribo')
  FROM members m
  JOIN onboarding_steps s ON s.id = 'meet_tribe'
  WHERE m.is_active
    AND public.onboarding_step_applies(s.applies_to_role, public._onboarding_journey_role(m.id))
    AND EXISTS (SELECT 1 FROM attendance a
                JOIN events e ON e.id = a.event_id
                JOIN initiatives i ON i.id = e.initiative_id
                WHERE a.member_id = m.id AND a.present = true AND i.legacy_tribe_id = m.tribe_id)
  ON CONFLICT (member_id, step_key) DO UPDATE
    SET status = 'completed', completed_at = now(), updated_at = now(),
        metadata = COALESCE(onboarding_progress.metadata, '{}'::jsonb) || EXCLUDED.metadata
    WHERE onboarding_progress.status IN ('pending', 'overdue');

  -- #2718 regra 5: o vídeo de captação fecha quando a tribo da pessoa tem vídeo cadastrado.
  INSERT INTO onboarding_progress (member_id, step_key, status, completed_at, metadata)
  SELECT m.id, 'leader_capture_video', 'completed', now(), jsonb_build_object('completed_via', '2718_video_da_tribo')
  FROM members m
  JOIN onboarding_steps s ON s.id = 'leader_capture_video'
  JOIN tribes t ON t.id = m.tribe_id
  WHERE m.is_active
    AND public.onboarding_step_applies(s.applies_to_role, public._onboarding_journey_role(m.id))
    AND NULLIF(btrim(COALESCE(t.video_url, '')), '') IS NOT NULL
  ON CONFLICT (member_id, step_key) DO UPDATE
    SET status = 'completed', completed_at = now(), updated_at = now(),
        metadata = COALESCE(onboarding_progress.metadata, '{}'::jsonb) || EXCLUDED.metadata
    WHERE onboarding_progress.status IN ('pending', 'overdue');

  -- #2718 regra 5: o tema fecha com quadrante e descrição (initiatives.description_i18n, fonte única desde a #2609).
  INSERT INTO onboarding_progress (member_id, step_key, status, completed_at, metadata)
  SELECT m.id, 'leader_refine_theme', 'completed', now(), jsonb_build_object('completed_via', '2718_tema_da_tribo')
  FROM members m
  JOIN onboarding_steps s ON s.id = 'leader_refine_theme'
  JOIN tribes t ON t.id = m.tribe_id
  WHERE m.is_active
    AND public.onboarding_step_applies(s.applies_to_role, public._onboarding_journey_role(m.id))
    AND t.quadrant IS NOT NULL
    AND EXISTS (SELECT 1 FROM initiatives i, jsonb_each_text(COALESCE(i.description_i18n, '{}'::jsonb)) d
                WHERE i.legacy_tribe_id = t.id AND NULLIF(btrim(d.value), '') IS NOT NULL)
  ON CONFLICT (member_id, step_key) DO UPDATE
    SET status = 'completed', completed_at = now(), updated_at = now(),
        metadata = COALESCE(onboarding_progress.metadata, '{}'::jsonb) || EXCLUDED.metadata
    WHERE onboarding_progress.status IN ('pending', 'overdue');
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
             WHEN 'complete_profile' THEN (
               -- fatia C: a mesma regra única do lote e do gatilho; sem data própria, porque o fato é o estado do perfil.
               CASE WHEN public._member_profile_ready(mem.id) THEN jsonb_build_object('kind', 'profile') END)
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

CREATE OR REPLACE FUNCTION public._trg_complete_profile_on_ready_fields()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Sai cedo: sem etapa de perfil aberta, nada a fazer (o caso de quem já concluiu).
  IF NOT EXISTS (SELECT 1 FROM public.onboarding_progress op
                 WHERE op.member_id = NEW.id AND op.step_key = 'complete_profile'
                   AND op.status IN ('pending', 'overdue')) THEN
    RETURN NULL;
  END IF;

  UPDATE public.onboarding_progress op
  SET status = 'completed', completed_at = now(), updated_at = now(),
      metadata = COALESCE(op.metadata, '{}'::jsonb) || jsonb_build_object('completed_via', 'perfil_pronto_para_o_termo')
  WHERE op.member_id = NEW.id AND op.step_key = 'complete_profile' AND op.status IN ('pending', 'overdue')
    AND public._member_profile_ready(NEW.id)
    AND EXISTS (SELECT 1 FROM public.onboarding_steps s
                WHERE s.id = 'complete_profile'
                  AND public.onboarding_step_applies(s.applies_to_role, public._onboarding_journey_role(NEW.id)));
  RETURN NULL;
END;
$function$;

REVOKE ALL ON FUNCTION public._trg_complete_profile_on_ready_fields() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_complete_profile_on_ready_fields ON public.members;
CREATE TRIGGER trg_complete_profile_on_ready_fields
  AFTER UPDATE OF pmi_id, phone, address, city, state, country, birth_date ON public.members
  FOR EACH ROW
  WHEN (NEW.is_active
        AND (OLD.pmi_id, OLD.phone, OLD.address, OLD.city, OLD.state, OLD.country, OLD.birth_date)
            IS DISTINCT FROM
            (NEW.pmi_id, NEW.phone, NEW.address, NEW.city, NEW.state, NEW.country, NEW.birth_date))
  EXECUTE FUNCTION public._trg_complete_profile_on_ready_fields();

NOTIFY pgrst, 'reload schema';
