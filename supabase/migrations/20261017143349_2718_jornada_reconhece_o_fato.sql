-- #2718 (#1995, fatia 2): a jornada de onboarding reconhece o fato e vale por papel.
--
-- A fatia 1 pôs a jornada de cada pessoa na fila de /admin/filiacao. Esta fatia corrige a própria jornada, pelas
-- regras que o GP decidiu em 16/10/2026 na #2718:
--
--   1. "Conheça sua tribo" fecha pela presença registrada numa reunião da iniciativa da própria tribo. O clique
--      continua valendo. Quem está sem tribo segue sinalizado como bloqueado por dependência (sinal da fatia 1).
--   2. "Inicie a Trilha" continua fechando pelo badge do Credly; a etapa passa a dizer isso, e a tela do membro
--      avisa quem não tem Credly no perfil (OnboardingChecklist).
--   3. "Código de Conduta" segue como etapa separada, por clique. A fila já sinaliza quem assinou o Termo
--      (conduct_pending_term_signed, fatia 1); nada muda aqui.
--   4. Só voluntários recebem as etapas de membro: pesquisador e líder. Feito no CATÁLOGO, pelo mesmo predicado
--      que a #1103 criou para as etapas de líder (onboarding_step_applies). As pendências dos outros papéis deixam
--      de contar na leitura, e nenhuma linha de onboarding_progress é apagada ou reescrita: se o papel da pessoa
--      mudar para pesquisador, as etapas voltam a valer com o estado que tinham. Todo leitor da jornada que a tela
--      e o MCP usam já aplica o predicado (os 6 da #1103); a fila da fatia 1 passa a aplicar aqui.
--   5. Etapas de líder com fato medível fecham por ele: o vídeo pela tribes.video_url; o tema pelo quadrante
--      (tribes.quadrant) e pela descrição da iniciativa da tribo (initiatives.description_i18n, a fonte única da
--      descrição desde a #2609 e o campo que o líder edita na página da tribo). Roadmap e revisão seguem por clique.
--
-- A detecção roda no lote diário auto_detect_onboarding_completions (cron 12:40 UTC, #2323) e, para a regra 1,
-- também no instante da presença, por gatilho em attendance (o gêmeo do first_meeting). As regras novas só
-- tocam pendência (pending/overdue) de quem a etapa vale: concluído e dispensado ficam intocados.
--
-- A etapa que não vale para o papel da pessoa também deixa de concluir a jornada dela: sem isso, a regra 4
-- faria qualquer clique de um convidado gravar o marco onboarding_complete, porque nenhuma etapa vale para ele.
--
-- O alcance de cada regra no dia da aplicação é medido antes e depois e registrado na PR.
--
-- Rollback: recriar get_affiliation_verification_queue pela captura 20261017044608,
-- auto_detect_onboarding_completions pela 20260805000079, _trg_record_onboarding_complete_milestone pela
-- 20260805000339; DROP TRIGGER trg_complete_meet_tribe_on_presence ON public.attendance e DROP FUNCTION
-- public._trg_complete_meet_tribe_on_presence(); UPDATE onboarding_steps SET applies_to_role = NULL WHERE
-- applies_to_role = ARRAY['researcher','tribe_leader'], e as descrições anteriores (estão nos comentários abaixo).
-- O lote que esta migration roda conclui etapas; desfazer isso é decisão à parte, linha a linha pelo
-- metadata.completed_via.

-- ── catálogo: etapas de membro só para voluntários (regra 4) ────────────────
UPDATE public.onboarding_steps
   SET applies_to_role = ARRAY['researcher', 'tribe_leader']
 WHERE applies_to_role IS NULL;

-- ── catálogo: a etapa diz como fecha (regras 1, 2 e 5) ──────────────────────
-- Antes: 'Visite a página da sua tribo: líder, agenda, WhatsApp.'
UPDATE public.onboarding_steps SET
  description_pt = 'Visite a página da sua tribo: líder, agenda, WhatsApp. A etapa fecha sozinha quando sua presença é registrada numa reunião da tribo.',
  description_en = 'Visit your stream page: leader, schedule, WhatsApp. This step closes on its own once your attendance is recorded at a meeting of your stream.',
  description_es = 'Visite la página de su línea: líder, agenda, WhatsApp. El paso se cierra solo cuando su asistencia se registra en una reunión de su línea.'
WHERE id = 'meet_tribe';
-- Antes: '7 cursos obrigatórios com badges Credly. Complete pelo menos 1.'
UPDATE public.onboarding_steps SET
  description_pt = '7 cursos obrigatórios com badges Credly. Complete pelo menos 1. A etapa fecha sozinha quando o badge chega pelo Credly ligado ao seu perfil.',
  description_en = '7 mandatory courses with Credly badges. Complete at least 1. This step closes on its own when the badge arrives through the Credly linked to your profile.',
  description_es = '7 cursos obligatorios con badges Credly. Complete al menos 1. El paso se cierra solo cuando la insignia llega por el Credly vinculado a su perfil.'
WHERE id = 'start_trail';
-- Antes: 'Descreva o tema em 1 parágrafo, escolha o quadrante (1–4) e a vertical quando aplicável.'
UPDATE public.onboarding_steps SET
  description_pt = 'Descreva o tema em 1 parágrafo, escolha o quadrante (1–4) e a vertical quando aplicável. A etapa fecha sozinha quando a página da tribo tem quadrante e descrição.',
  description_en = 'Describe the theme in 1 paragraph, choose the quadrant (1–4) and the vertical when applicable. This step closes on its own once the tribe page has a quadrant and a description.',
  description_es = 'Describe el tema en 1 párrafo, elige el cuadrante (1–4) y la vertical cuando aplique. El paso se cierra solo cuando la página de tu tribu tiene cuadrante y descripción.'
WHERE id = 'leader_refine_theme';
-- Antes: 'Grave um vídeo curto de captação; o link fica registrado na página da tribo.'
UPDATE public.onboarding_steps SET
  description_pt = 'Grave um vídeo curto de captação; o link fica registrado na página da tribo. A etapa fecha sozinha quando o vídeo está cadastrado.',
  description_en = 'Record a short recruitment video; the link is stored on your tribe page. This step closes on its own once the video is registered.',
  description_es = 'Graba un video corto de captación; el enlace queda en la página de tu tribu. El paso se cierra solo cuando el video está registrado.'
WHERE id = 'leader_capture_video';

-- ── lote diário: as regras 1 e 5 ────────────────────────────────────────────
-- Corpo = vivo em 17/10 (captura 20260805000079) + os três blocos #2718 no fim.
CREATE OR REPLACE FUNCTION public.auto_detect_onboarding_completions()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  INSERT INTO onboarding_progress (member_id, step_key, status, completed_at)
  SELECT m.id, 'complete_profile', 'completed', now()
  FROM members m WHERE m.is_active AND (
    (m.name IS NOT NULL AND m.name != '')::int + (m.photo_url IS NOT NULL AND m.photo_url != '')::int +
    (m.state IS NOT NULL AND m.state != '')::int + (m.country IS NOT NULL AND m.country != '')::int +
    (m.linkedin_url IS NOT NULL AND m.linkedin_url != '')::int + (m.pmi_id IS NOT NULL)::int
  ) >= 4
  ON CONFLICT (member_id, step_key) DO UPDATE SET status = 'completed', completed_at = now() WHERE onboarding_progress.status != 'completed';

  INSERT INTO onboarding_progress (member_id, step_key, status, completed_at)
  SELECT DISTINCT gp.member_id, 'start_trail', 'completed', now()
  FROM gamification_points gp WHERE gp.category = 'trail'
  ON CONFLICT (member_id, step_key) DO UPDATE SET status = 'completed', completed_at = now() WHERE onboarding_progress.status != 'completed';

  -- PR11 sealing-safety: 'first_meeting' completes only on a PRESENT row (the batch twin of the
  -- auto_complete_first_meeting trigger guard) — a sealed absent row must not complete onboarding.
  INSERT INTO onboarding_progress (member_id, step_key, status, completed_at)
  SELECT DISTINCT a.member_id, 'first_meeting', 'completed', now()
  FROM attendance a
  WHERE a.present = true
  ON CONFLICT (member_id, step_key) DO UPDATE SET status = 'completed', completed_at = now() WHERE onboarding_progress.status != 'completed';

  -- #2718 regra 1: "Conheça sua tribo" fecha pela presença numa reunião da iniciativa da própria tribo.
  -- Os três blocos #2718 só tocam pendência de quem a etapa vale: concluído e dispensado ficam intocados.
  INSERT INTO onboarding_progress (member_id, step_key, status, completed_at, metadata)
  SELECT m.id, 'meet_tribe', 'completed', now(), jsonb_build_object('completed_via', '2718_presenca_na_tribo')
  FROM members m
  JOIN onboarding_steps s ON s.id = 'meet_tribe'
  WHERE m.is_active
    AND public.onboarding_step_applies(s.applies_to_role, m.operational_role)
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
    AND public.onboarding_step_applies(s.applies_to_role, m.operational_role)
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
    AND public.onboarding_step_applies(s.applies_to_role, m.operational_role)
    AND t.quadrant IS NOT NULL
    AND EXISTS (SELECT 1 FROM initiatives i, jsonb_each_text(COALESCE(i.description_i18n, '{}'::jsonb)) d
                WHERE i.legacy_tribe_id = t.id AND NULLIF(btrim(d.value), '') IS NOT NULL)
  ON CONFLICT (member_id, step_key) DO UPDATE
    SET status = 'completed', completed_at = now(), updated_at = now(),
        metadata = COALESCE(onboarding_progress.metadata, '{}'::jsonb) || EXCLUDED.metadata
    WHERE onboarding_progress.status IN ('pending', 'overdue');
END; $function$;

-- ── regra 1 no instante da presença ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._trg_complete_meet_tribe_on_presence()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
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
                   AND public.onboarding_step_applies(s.applies_to_role, m.operational_role));
  RETURN NEW;
END; $function$;

REVOKE ALL ON FUNCTION public._trg_complete_meet_tribe_on_presence() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_complete_meet_tribe_on_presence ON public.attendance;
CREATE TRIGGER trg_complete_meet_tribe_on_presence
  AFTER INSERT OR UPDATE OF present ON public.attendance
  FOR EACH ROW WHEN (NEW.present = true)
  EXECUTE FUNCTION public._trg_complete_meet_tribe_on_presence();

-- ── o marco de jornada concluída só conta etapa que vale para a pessoa ──────
-- Corpo = vivo em 17/10 (captura 20260805000339) + o retorno antecipado #2718.
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
  SELECT operational_role INTO v_member_role FROM public.members WHERE id = NEW.member_id;
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

-- ── fila de filiação: a jornada só com etapas que valem para o papel ────────
-- Corpo = captura 20261017044608 + o predicado da regra 4 + o sinal tribe_pending_but_attended passa a exigir que
-- nenhuma presença seja da própria tribo (a que é já fecha a etapa pela regra 1).
CREATE OR REPLACE FUNCTION public.get_affiliation_verification_queue(p_scope text DEFAULT 'queue'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id           uuid;
  v_caller_designations text[];
  v_result              jsonb;
  v_member_ids          uuid[];
  v_current_cycle_id    uuid;
  v_term_soon_days      int := 180;  -- ~one renewal cycle (cycle_4.cycle_end open); raw date also surfaced
BEGIN
  -- Auth-resolve + function-anchored gate (mirror verify_member_affiliation, mig 148).
  SELECT m.id, m.designations INTO v_caller_id, v_caller_designations
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  -- Least-privilege: read audience == write audience (filiacao_director OR manage_member).
  IF NOT ('filiacao_director' = ANY(COALESCE(v_caller_designations, '{}'::text[])))
     AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Forbidden: requires filiacao_director designation or platform manager authority';
  END IF;

  -- Current selection cycle, tied to the current operational cycle by number (dynamic — no hardcoded
  -- cycle_code; survives C4→C5). selection_cycles has no is_current column; two selection rows can be
  -- status='open' at once, so we anchor on cycles.is_current, then take the latest open_date.
  SELECT sc.id INTO v_current_cycle_id
  FROM public.selection_cycles sc
  WHERE regexp_replace(sc.cycle_code, '\D', '', 'g')
        LIKE (SELECT regexp_replace(c.cycle_code, '\D', '', 'g') FROM public.cycles c WHERE c.is_current LIMIT 1) || '%'
  ORDER BY sc.open_date DESC NULLS LAST
  LIMIT 1;

  WITH cohort AS (
    SELECT
      m.id  AS member_id,
      m.name,
      m.email,
      m.chapter,
      m.operational_role,
      m.pmi_id_verified,
      COALESCE(pre.flag, false)  AS is_pre_onboarding,
      vep.vep_status_raw,
      vep.vep_last_seen_at,
      vep.pmi_memberships,
      vep.pmi_id,
      vep.service_first_start_date,
      vep.service_latest_end_date,
      vep.service_history_count,
      vep.pmi_data_fetched_at,
      aff.created_at            AS aff_created_at,
      aff.membership_active     AS aff_membership_active,
      aff.membership_expires_on AS aff_membership_expires_on,
      aff.method                AS aff_method,
      aff.chapter_verified      AS aff_chapter_verified,
      -- #1129 cohort (by email set; current-cycle preferred)
      sel.sel_cycle_code,
      sel.sel_role,
      sel.sel_is_current,
      sel.has_selection,
      -- #1129 term validity
      term.term_end_date,
      -- #1192 SSOT chapter read-through
      aff2.chapter_affiliations,
      -- #1995 jornada de onboarding (fatia 1)
      ob.onboarding,
      -- #1995 fatia 1b: tribo pela coluna que confere com o engajamento volunteer
      m.tribe_id,
      tr.name AS tribe_name
    FROM public.members m
    LEFT JOIN public.tribes tr ON tr.id = m.tribe_id
    -- VEP + PMI membership detail from the latest matching application (shape from admin_list_members).
    LEFT JOIN LATERAL (
      SELECT a.vep_status_raw, a.vep_last_seen_at, a.pmi_memberships,
             a.pmi_id, a.service_first_start_date, a.service_latest_end_date,
             a.service_history_count, a.pmi_data_fetched_at
      FROM public.selection_applications a
      WHERE lower(a.email) = lower(m.email)
        AND a.vep_status_raw IS NOT NULL
      ORDER BY a.vep_last_seen_at DESC NULLS LAST
      LIMIT 1
    ) vep ON true
    -- #625 C0 pre-onboarding flag — VERBATIM from admin_list_members (mig 148).
    LEFT JOIN LATERAL (
      SELECT (
        m.member_status = 'active'
        AND EXISTS (
          SELECT 1 FROM public.engagements e
          WHERE e.person_id = m.person_id AND e.status = 'active'
        )
        AND NOT EXISTS (
          SELECT 1 FROM public.engagements e
          JOIN public.engagement_kinds ek ON ek.slug = e.kind
          WHERE e.person_id = m.person_id AND e.status = 'active'
            AND (ek.requires_agreement IS NOT TRUE OR e.agreement_certificate_id IS NOT NULL)
        )
      ) AS flag
    ) pre ON true
    -- Latest verification from the append-only trail.
    LEFT JOIN LATERAL (
      SELECT mav.created_at, mav.membership_active, mav.membership_expires_on,
             mav.method, mav.chapter_verified
      FROM public.member_affiliation_verifications mav
      WHERE mav.member_id = m.id
      ORDER BY mav.created_at DESC
      LIMIT 1
    ) aff ON true
    -- #1129 cohort: most-relevant approved/converted selection application across the member's full
    -- email set (primary + member_emails), preferring the current cycle. NULL row ⇒ non_selection.
    LEFT JOIN LATERAL (
      SELECT sc.cycle_code                     AS sel_cycle_code,
             a.role_applied                    AS sel_role,
             (a.cycle_id = v_current_cycle_id) AS sel_is_current,
             true                              AS has_selection
      FROM public.selection_applications a
      JOIN public.selection_cycles sc ON sc.id = a.cycle_id
      WHERE a.status IN ('approved','converted')
        AND ( lower(a.email) = lower(m.email)
              OR lower(a.email) IN (SELECT lower(me.email) FROM public.member_emails me WHERE me.member_id = m.id) )
      ORDER BY (a.cycle_id = v_current_cycle_id) DESC, sc.open_date DESC NULLS LAST
      LIMIT 1
    ) sel ON true
    -- #1129 term boundary: the active agreement-requiring engagement's end_date (volunteer term).
    LEFT JOIN LATERAL (
      SELECT e.end_date AS term_end_date
      FROM public.engagements e
      JOIN public.engagement_kinds ek ON ek.slug = e.kind
      WHERE e.person_id = m.person_id
        AND e.status = 'active'
        AND ek.requires_agreement = true
      ORDER BY e.end_date DESC NULLS LAST
      LIMIT 1
    ) term ON true
    -- #1192 chapter_affiliations: SSOT rows (member_chapter_affiliations × chapter_registry) with the
    -- matching raw membership's expiry paired via resolve_br_chapter_code, UNION raw names that resolve
    -- via the registry but have no SSOT row yet ('vep_raw', provisional). ALL name→code resolution runs
    -- here, in the one SSOT resolver — the client never re-parses names to decide anything.
    LEFT JOIN LATERAL (
      SELECT jsonb_agg(x.obj ORDER BY x.is_primary DESC, x.chapter_code) AS chapter_affiliations
      FROM (
        SELECT mca.chapter_code, mca.is_primary,
               jsonb_build_object(
                 'chapter_code', mca.chapter_code,
                 'chapter_label', cr.state,
                 'source', mca.source,
                 'verified_at', mca.verified_at,
                 'is_primary', mca.is_primary,
                 'raw_name', raw.raw_name,
                 'expiry', raw.expiry
               ) AS obj
        FROM public.member_chapter_affiliations mca
        JOIN public.chapter_registry cr
          ON cr.chapter_code = mca.chapter_code AND cr.is_active = true
        LEFT JOIN LATERAL (
          SELECT CASE WHEN jsonb_typeof(e) = 'string' THEN e #>> '{}' ELSE e->>'chapterName' END AS raw_name,
                 CASE WHEN jsonb_typeof(e) = 'string' THEN NULL ELSE e->>'expiryDate' END AS expiry
          FROM jsonb_array_elements(COALESCE(vep.pmi_memberships, '[]'::jsonb)) e
          WHERE public.resolve_br_chapter_code(
                  CASE WHEN jsonb_typeof(e) = 'string' THEN e #>> '{}' ELSE e->>'chapterName' END
                ) = mca.chapter_code
          LIMIT 1
        ) raw ON true
        WHERE mca.person_id = m.person_id
        UNION ALL
        SELECT rr.code, false,
               jsonb_build_object(
                 'chapter_code', rr.code,
                 'chapter_label', cr2.state,
                 'source', 'vep_raw',
                 'verified_at', NULL,
                 'is_primary', false,
                 'raw_name', rr.raw_name,
                 'expiry', rr.expiry
               )
        FROM (
          SELECT DISTINCT ON (t.code) t.code, t.raw_name, t.expiry
          FROM (
            SELECT public.resolve_br_chapter_code(CASE WHEN jsonb_typeof(e) = 'string' THEN e #>> '{}' ELSE e->>'chapterName' END) AS code,
                   CASE WHEN jsonb_typeof(e) = 'string' THEN e #>> '{}' ELSE e->>'chapterName' END AS raw_name,
                   CASE WHEN jsonb_typeof(e) = 'string' THEN NULL ELSE e->>'expiryDate' END AS expiry
            FROM jsonb_array_elements(COALESCE(vep.pmi_memberships, '[]'::jsonb)) e
          ) t
          WHERE t.code IS NOT NULL
          ORDER BY t.code, (t.expiry IS NULL)
        ) rr
        JOIN public.chapter_registry cr2 ON cr2.chapter_code = rr.code AND cr2.is_active = true
        WHERE NOT EXISTS (
          SELECT 1 FROM public.member_chapter_affiliations mca2
          WHERE mca2.person_id = m.person_id AND mca2.chapter_code = rr.code)
      ) x
    ) aff2 ON true
    -- #1995 (fatia 1): a jornada de onboarding da pessoa e os sinais de trava medidos em 16/10/2026. X/Y usa o Y
    -- real da pessoa (o total de passos varia por papel) e só passos do catálogo (#2009); 'overdue' conta como
    -- pendente. Um sinal diz quando a etapa está pendente por dependência ou porque mede clique, não o fato.
    LEFT JOIN LATERAL (
      SELECT CASE WHEN count(*) = 0 THEN NULL ELSE jsonb_build_object(
        'total', count(*),
        'done', count(*) FILTER (WHERE op.status IN ('completed', 'skipped')),
        'pending', count(*) FILTER (WHERE op.status IN ('pending', 'overdue')),
        'stage', (array_agg(op.step_key ORDER BY s.step_order) FILTER (WHERE op.status IN ('pending', 'overdue')))[1],
        'stage_label', (array_agg(jsonb_build_object('pt-BR', s.label_pt, 'en-US', s.label_en, 'es-LATAM', s.label_es)
                          ORDER BY s.step_order) FILTER (WHERE op.status IN ('pending', 'overdue')))[1],
        'started_at', min(op.created_at),
        'last_progress_at', max(op.completed_at),
        'stalled_days', CASE WHEN count(*) FILTER (WHERE op.status IN ('pending', 'overdue')) > 0
                             THEN floor(extract(epoch FROM now() - COALESCE(max(op.completed_at), min(op.created_at))) / 86400)::int
                        END,
        'last_sign_in_at', (SELECT u.last_sign_in_at FROM auth.users u WHERE u.id = m.auth_id),
        'signals', to_jsonb(array_remove(ARRAY[
          -- "Conheça sua tribo" não fecha sem tribo: bloqueio por dependência, não atraso da pessoa
          CASE WHEN bool_or(op.step_key = 'meet_tribe' AND op.status IN ('pending', 'overdue')) AND m.tribe_id IS NULL
               THEN 'tribe_blocked_no_tribe' END,
          -- #2718: a etapa fecha pela presença numa reunião da própria tribo; aqui a pessoa tem tribo e já foi
          -- a reunião, mas nenhuma da tribo dela, então só o clique fecha
          CASE WHEN bool_or(op.step_key = 'meet_tribe' AND op.status IN ('pending', 'overdue')) AND m.tribe_id IS NOT NULL
                    AND EXISTS (SELECT 1 FROM public.attendance a WHERE a.member_id = m.id AND a.present)
                    AND NOT EXISTS (SELECT 1 FROM public.attendance a
                                    JOIN public.events e ON e.id = a.event_id
                                    JOIN public.initiatives i ON i.id = e.initiative_id
                                    WHERE a.member_id = m.id AND a.present AND i.legacy_tribe_id = m.tribe_id)
               THEN 'tribe_pending_but_attended' END,
          -- a trilha só fecha com badge do Credly sincronizado; sem Credly no perfil, a plataforma nunca vê o curso
          CASE WHEN bool_or(op.step_key = 'start_trail' AND op.status IN ('pending', 'overdue'))
                    AND NULLIF(btrim(COALESCE(m.credly_url, '')), '') IS NULL
               THEN 'trail_without_credly' END,
          -- o Código de Conduta só fecha por clique; a pessoa já assinou o Termo
          CASE WHEN bool_or(op.step_key = 'code_of_conduct' AND op.status IN ('pending', 'overdue'))
                    AND bool_or(op.step_key = 'volunteer_term' AND op.status = 'completed')
               THEN 'conduct_pending_term_signed' END,
          -- a detecção da primeira reunião funciona: aqui não há presença registrada em reunião nenhuma
          CASE WHEN bool_or(op.step_key = 'first_meeting' AND op.status IN ('pending', 'overdue'))
                    AND NOT EXISTS (SELECT 1 FROM public.attendance a WHERE a.member_id = m.id AND a.present)
               THEN 'never_present' END
        ], NULL))
      ) END AS onboarding
      FROM public.onboarding_progress op
      JOIN public.onboarding_steps s ON s.id = op.step_key
      WHERE op.member_id = m.id
        -- #2718 regra 4: só as etapas que valem para o papel da pessoa (o predicado de get_my_onboarding)
        AND public.onboarding_step_applies(s.applies_to_role, m.operational_role)
    ) ob ON true
    WHERE m.member_status = 'active'
      AND (
        p_scope = 'all'                                                -- #1364b full roster (verified + unverified)
        OR COALESCE(pre.flag, false)                                   -- pre-onboarding (urgent)
        OR COALESCE(m.pmi_id_verified, false) = false                  -- cache says unverified
        OR NOT EXISTS (                                                -- never verified at all
          SELECT 1 FROM public.member_affiliation_verifications mv
          WHERE mv.member_id = m.id
        )
      )
  )
  SELECT
    COALESCE(jsonb_agg(jsonb_build_object(
      'member_id', c.member_id,
      'name', c.name,
      'email', c.email,
      'chapter', c.chapter,
      'operational_role', c.operational_role,
      'is_pre_onboarding', c.is_pre_onboarding,
      'pmi_id_verified', COALESCE(c.pmi_id_verified, false),
      'vep_status_raw', c.vep_status_raw,
      'vep_last_seen_at', c.vep_last_seen_at,
      'pmi_memberships', COALESCE(c.pmi_memberships, '[]'::jsonb),
      -- #1192 SSOT chapter read-through (see lateral above)
      'chapter_affiliations', COALESCE(c.chapter_affiliations, '[]'::jsonb),
      'pmi_profile', CASE
        WHEN c.pmi_id IS NULL AND c.service_first_start_date IS NULL
             AND c.service_latest_end_date IS NULL AND c.service_history_count IS NULL
             AND c.pmi_data_fetched_at IS NULL
        THEN NULL
        ELSE jsonb_build_object(
          'pmi_id', c.pmi_id,
          'member_since', c.service_first_start_date,
          'member_until', c.service_latest_end_date,
          'volunteer_count', c.service_history_count,
          'last_sync', c.pmi_data_fetched_at
        )
      END,
      -- #1129 cohort + volunteer-term validity
      'cohort_class', CASE
        WHEN NOT COALESCE(c.has_selection, false) THEN 'non_selection'
        WHEN c.sel_is_current THEN 'current_selection'
        ELSE 'carryover'
      END,
      'cohort_cycle_code', c.sel_cycle_code,
      'cohort_role', c.sel_role,
      'term_end_date', c.term_end_date,
      'term_status', CASE
        WHEN c.term_end_date IS NULL THEN 'none'
        WHEN c.term_end_date < CURRENT_DATE THEN 'expired'
        WHEN c.term_end_date <= CURRENT_DATE + (v_term_soon_days || ' days')::interval THEN 'expiring'
        ELSE 'valid'
      END,
      -- #1995 (fatia 1)
      'onboarding', c.onboarding,
      -- #1995 (fatia 1b): null = sem tribo
      'tribe', CASE WHEN c.tribe_id IS NULL THEN NULL ELSE jsonb_build_object('id', c.tribe_id, 'name', c.tribe_name) END,
      'latest_verification', CASE WHEN c.aff_created_at IS NULL THEN NULL ELSE jsonb_build_object(
        'created_at', c.aff_created_at,
        'membership_active', c.aff_membership_active,
        'membership_expires_on', c.aff_membership_expires_on,
        'method', c.aff_method,
        'chapter_verified', c.aff_chapter_verified
      ) END
    ) ORDER BY c.is_pre_onboarding DESC, c.name),
    '[]'::jsonb),
    ARRAY_AGG(c.member_id)
  INTO v_result, v_member_ids
  FROM cohort c;

  -- LGPD Art. 37 — nominal read of affiliation data by the office (SPEC §6.2.3(4)). cohort/term/
  -- chapter_affiliations are derived from selection/engagement/affiliation data the office already
  -- reads; no new raw identity column ('chapter' + 'membership_dates' cover the read-through).
  PERFORM public.log_pii_access_batch(
    v_member_ids,
    ARRAY['pmi_id','chapter','membership_status','membership_dates','onboarding_progress','last_sign_in'],
    'affiliation_verification_queue',
    'Diretoria de Filiação — leitura da fila de verificação de filiação');

  RETURN v_result;
END;
$function$;

-- ── o lote roda agora, para o efeito valer no dia da aplicação ──────────────
SELECT public.auto_detect_onboarding_completions();

-- ── pós-condição ─────────────────────────────────────────────────────────────
DO $postcondition$
DECLARE
  v_msg text;
  v_n int;
BEGIN
  -- regra 4: nenhuma etapa vale para todos os papéis
  SELECT count(*) INTO v_n FROM public.onboarding_steps WHERE applies_to_role IS NULL;
  IF v_n <> 0 THEN RAISE EXCEPTION '#2718: % etapa(s) ainda valem para todos os papéis', v_n; END IF;
  IF public.onboarding_step_applies(ARRAY['researcher', 'tribe_leader'], 'guest')
     OR NOT public.onboarding_step_applies(ARRAY['researcher', 'tribe_leader'], 'researcher')
     OR NOT public.onboarding_step_applies(ARRAY['researcher', 'tribe_leader'], NULL) THEN
    RAISE EXCEPTION '#2718: o predicado não separa voluntário de convidado';
  END IF;

  -- regra 1: depois do lote, nenhuma pendência de "Conheça sua tribo" com presença na própria tribo
  SELECT count(*) INTO v_n
  FROM public.onboarding_progress op
  JOIN public.members m ON m.id = op.member_id
  JOIN public.onboarding_steps s ON s.id = op.step_key
  WHERE op.step_key = 'meet_tribe' AND op.status IN ('pending', 'overdue') AND m.is_active
    AND public.onboarding_step_applies(s.applies_to_role, m.operational_role)
    AND EXISTS (SELECT 1 FROM public.attendance a
                JOIN public.events e ON e.id = a.event_id
                JOIN public.initiatives i ON i.id = e.initiative_id
                WHERE a.member_id = m.id AND a.present AND i.legacy_tribe_id = m.tribe_id);
  IF v_n <> 0 THEN RAISE EXCEPTION '#2718 regra 1: % pendência(s) com presença na própria tribo ficaram', v_n; END IF;

  -- regra 5: nenhuma pendência de vídeo com vídeo cadastrado, nem de tema com quadrante e descrição
  SELECT count(*) INTO v_n
  FROM public.onboarding_progress op
  JOIN public.members m ON m.id = op.member_id
  JOIN public.tribes t ON t.id = m.tribe_id
  WHERE op.step_key = 'leader_capture_video' AND op.status IN ('pending', 'overdue') AND m.is_active
    AND m.operational_role = 'tribe_leader'
    AND NULLIF(btrim(COALESCE(t.video_url, '')), '') IS NOT NULL;
  IF v_n <> 0 THEN RAISE EXCEPTION '#2718 regra 5: % pendência(s) de vídeo com vídeo cadastrado ficaram', v_n; END IF;

  SELECT count(*) INTO v_n
  FROM public.onboarding_progress op
  JOIN public.members m ON m.id = op.member_id
  JOIN public.tribes t ON t.id = m.tribe_id
  WHERE op.step_key = 'leader_refine_theme' AND op.status IN ('pending', 'overdue') AND m.is_active
    AND m.operational_role = 'tribe_leader' AND t.quadrant IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.initiatives i, jsonb_each_text(COALESCE(i.description_i18n, '{}'::jsonb)) d
                WHERE i.legacy_tribe_id = t.id AND NULLIF(btrim(d.value), '') IS NOT NULL);
  IF v_n <> 0 THEN RAISE EXCEPTION '#2718 regra 5: % pendência(s) de tema com quadrante e descrição ficaram', v_n; END IF;

  -- o gatilho da regra 1 existe de fato, e a função dele não é chamável pela API
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                 WHERE tgname = 'trg_complete_meet_tribe_on_presence'
                   AND tgrelid = 'public.attendance'::regclass AND NOT tgisinternal) THEN
    RAISE EXCEPTION '#2718: o gatilho trg_complete_meet_tribe_on_presence não existe';
  END IF;
  IF has_function_privilege('anon', 'public._trg_complete_meet_tribe_on_presence()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public._trg_complete_meet_tribe_on_presence()', 'EXECUTE') THEN
    RAISE EXCEPTION '#2718: a função do gatilho ficou executável por anon ou authenticated';
  END IF;

  -- a fila continua recusando quem não tem sessão, antes de ler qualquer linha
  BEGIN
    PERFORM public.get_affiliation_verification_queue('all');
    RAISE EXCEPTION '#2718: a fila respondeu sem sessão';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'Forbidden: authentication required%' THEN
      RAISE EXCEPTION '#2718: recusa inesperada sem sessão: %', v_msg;
    END IF;
  END;
END
$postcondition$;
