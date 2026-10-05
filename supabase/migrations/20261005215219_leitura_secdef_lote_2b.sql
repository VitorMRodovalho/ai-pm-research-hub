-- Funções SECURITY DEFINER seguem a política das tabelas (lote 2b, decisões do GP em 05/10/2026).
--
-- 1. Escrita em submissões: incluir, trocar ou remover autor e editar a submissão passam a exigir o
--    autor principal, quem a criou, a gestão ou a liderança de Publicações & Submissões. Antes, remover
--    autor bastava estar logado, e incluir autor ou editar bastava ser membro ativo.
-- 2. list_webinars_v2 segue a política de webinars (confirmados e concluídos para quem tem login).
-- 3. Gamificação: sem vínculo vigente, só a própria estatística e o ranking sem papel e designações;
--    quem saiu do ranking só aparece para si e para quem gere membros.
-- Tudo vale para quem chama pela API (_request_is_rest_caller(), #684). Chamadas internas seguem iguais.

CREATE OR REPLACE FUNCTION public._can_manage_publication_submission(p_submission_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- Quem gerencia uma submissão (#2565, decisão do GP em 05/10/2026): o autor principal, quem a
  -- criou, a gestão (manage_platform) e a liderança de Publicações & Submissões, isto é, papel de
  -- líder ou coordenador vigente no grupo de trabalho dono do quadro de publicações.
  SELECT EXISTS (
    SELECT 1
    FROM public.members m
    JOIN public.publication_submissions ps ON ps.id = p_submission_id
    WHERE m.auth_id = auth.uid()
      AND m.is_active IS TRUE
      AND (
        ps.primary_author_id = m.id
        OR ps.created_by = m.id
        OR public.can_by_member(m.id, 'manage_platform')
        OR EXISTS (
          SELECT 1
          FROM public.engagements e
          JOIN public.initiatives i ON i.id = e.initiative_id
          WHERE e.person_id = m.person_id
            AND e.status = 'active'
            AND (e.end_date IS NULL OR e.end_date >= CURRENT_DATE)
            AND e.role IN ('leader', 'coordinator')
            AND i.kind = 'workgroup'
            AND EXISTS (
              SELECT 1 FROM public.project_boards pb
              WHERE pb.initiative_id = i.id
                AND pb.domain_key = 'publications_submissions'
                AND pb.is_active IS TRUE
            )
        )
      )
  );
$function$;

COMMENT ON FUNCTION public._can_manage_publication_submission(uuid) IS
  '#2565: quem gerencia uma submissão (autor principal, quem criou, gestão, liderança de P&S). Devolve só verdadeiro ou falso.';
REVOKE ALL ON FUNCTION public._can_manage_publication_submission(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._can_manage_publication_submission(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.add_publication_submission_author(p_submission_id uuid, p_member_id uuid, p_author_order integer DEFAULT 2, p_is_corresponding boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_id uuid;
  v_caller_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.members WHERE auth_id = v_caller_id AND is_active = true) THEN
    RAISE EXCEPTION 'Not an active member';
  END IF;
  -- Quem gerencia a submissão: autor principal, quem a criou, a gestão e a liderança de P&S.
  IF public._request_is_rest_caller() AND NOT public._can_manage_publication_submission(p_submission_id) THEN
    RAISE EXCEPTION 'Not authorized to manage this submission';
  END IF;
  
  INSERT INTO public.publication_submission_authors (submission_id, member_id, author_order, is_corresponding)
  VALUES (p_submission_id, p_member_id, p_author_order, p_is_corresponding)
  ON CONFLICT (submission_id, member_id) DO UPDATE SET
    author_order = EXCLUDED.author_order,
    is_corresponding = EXCLUDED.is_corresponding
  RETURNING id INTO v_id;
  
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.remove_publication_submission_author(p_submission_id uuid, p_member_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  -- Quem gerencia a submissão: autor principal, quem a criou, a gestão e a liderança de P&S.
  IF public._request_is_rest_caller() AND NOT public._can_manage_publication_submission(p_submission_id) THEN
    RAISE EXCEPTION 'Not authorized to manage this submission';
  END IF;
  
  DELETE FROM public.publication_submission_authors
  WHERE submission_id = p_submission_id AND member_id = p_member_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_publication_submission(p_id uuid, p_title text DEFAULT NULL::text, p_abstract text DEFAULT NULL::text, p_target_name text DEFAULT NULL::text, p_target_url text DEFAULT NULL::text, p_submission_date date DEFAULT NULL::date, p_review_deadline date DEFAULT NULL::date, p_acceptance_date date DEFAULT NULL::date, p_presentation_date date DEFAULT NULL::date, p_estimated_cost_brl numeric DEFAULT NULL::numeric, p_actual_cost_brl numeric DEFAULT NULL::numeric, p_cost_paid_by text DEFAULT NULL::text, p_reviewer_feedback text DEFAULT NULL::text, p_doi_or_url text DEFAULT NULL::text, p_board_item_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.members WHERE auth_id = v_caller_id AND is_active = true) THEN
    RAISE EXCEPTION 'Not an active member';
  END IF;
  -- Quem gerencia a submissão: autor principal, quem a criou, a gestão e a liderança de P&S.
  IF public._request_is_rest_caller() AND NOT public._can_manage_publication_submission(p_id) THEN
    RAISE EXCEPTION 'Not authorized to manage this submission';
  END IF;
  
  UPDATE public.publication_submissions SET
    title = COALESCE(p_title, title),
    abstract = COALESCE(p_abstract, abstract),
    target_name = COALESCE(p_target_name, target_name),
    target_url = COALESCE(p_target_url, target_url),
    submission_date = COALESCE(p_submission_date, submission_date),
    review_deadline = COALESCE(p_review_deadline, review_deadline),
    acceptance_date = COALESCE(p_acceptance_date, acceptance_date),
    presentation_date = COALESCE(p_presentation_date, presentation_date),
    estimated_cost_brl = COALESCE(p_estimated_cost_brl, estimated_cost_brl),
    actual_cost_brl = COALESCE(p_actual_cost_brl, actual_cost_brl),
    cost_paid_by = COALESCE(p_cost_paid_by, cost_paid_by),
    reviewer_feedback = COALESCE(p_reviewer_feedback, reviewer_feedback),
    doi_or_url = COALESCE(p_doi_or_url, doi_or_url),
    board_item_id = COALESCE(p_board_item_id, board_item_id),
    updated_at = now()
  WHERE id = p_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_webinars_v2(p_status text DEFAULT NULL::text, p_chapter text DEFAULT NULL::text, p_tribe_id integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result jsonb;
  -- Leitura pela API segue a política de webinars: confirmados e concluídos para quem tem login;
  -- os demais status, e o card ligado (board_items), só para membro com vínculo vigente.
  v_full boolean := NOT public._request_is_rest_caller() OR public.rls_is_authoritative_member();
BEGIN
  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.scheduled_at DESC), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      w.id, w.title, w.description, w.scheduled_at, w.duration_min,
      w.status, w.chapter_code,
      i.legacy_tribe_id AS tribe_id,
      w.organizer_id,
      w.co_manager_ids, w.meeting_link, w.youtube_url, w.notes,
      w.event_id, w.board_item_id,
      w.created_at, w.updated_at,
      m.name AS organizer_name,
      i.title AS tribe_name,
      e.date AS event_date,
      e.type AS event_type,
      (SELECT COUNT(*) FROM public.attendance a WHERE a.event_id = w.event_id AND a.present = true) AS attendee_count,
      (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', cm.id, 'name', cm.name)), '[]'::jsonb)
       FROM public.members cm WHERE cm.id = ANY(w.co_manager_ids)) AS co_managers,
      CASE WHEN v_full THEN bi.title END AS board_item_title,
      CASE WHEN v_full THEN bi.status END AS board_item_status,
      -- #1029 nudge: webinar já passou da data mas segue sem status terminal (completed|cancelled).
      -- Sem cron de auto-transição (past-dated sem event/presença não têm sinal confiável de que
      -- ocorreram) — o organizador marca à mão. Este flag só destaca a fila no admin. Ver #479.
      (w.status IN ('planned', 'confirmed') AND w.scheduled_at < now()) AS needs_status_review
    FROM public.webinars w
    LEFT JOIN public.members m ON m.id = w.organizer_id
    LEFT JOIN public.initiatives i ON i.id = w.initiative_id
    LEFT JOIN public.events e ON e.id = w.event_id
    LEFT JOIN public.board_items bi ON bi.id = w.board_item_id
    WHERE (p_status IS NULL OR w.status = p_status)
      AND (p_chapter IS NULL OR w.chapter_code = p_chapter)
      AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)
      AND public.rls_can_see_initiative(w.initiative_id)
      AND (v_full OR w.status IN ('confirmed', 'completed'))
  ) r;
  RETURN v_result;
END; $function$;

CREATE OR REPLACE FUNCTION public.get_member_gamification_stats(p_member_ids uuid[])
 RETURNS TABLE(member_id uuid, current_streak_count integer, points_this_cycle integer, active_cycles_count integer, longest_streak_count integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_current_sort integer;
  v_cycle_start date;
  v_cycle_end date;
  v_input_size integer;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_member_ids IS NULL THEN
    RETURN;
  END IF;

  v_input_size := COALESCE(array_length(p_member_ids, 1), 0);
  IF v_input_size = 0 THEN
    RETURN;
  END IF;
  IF v_input_size > 200 THEN
    RAISE EXCEPTION 'Too many member_ids (max 200, got %)', v_input_size
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Pela API: sem vínculo vigente, só a própria estatística; quem saiu do ranking só aparece para si
  -- e para quem gere membros (exceção da ADR-0100). Chamadas internas seguem iguais.
  IF public._request_is_rest_caller() THEN
    p_member_ids := ARRAY(
      SELECT DISTINCT mid FROM unnest(p_member_ids) mid
      WHERE mid = v_caller_id
         OR (public.rls_is_authoritative_member()
             AND (public.can_by_member(v_caller_id, 'manage_member')
                  OR NOT EXISTS (SELECT 1 FROM public.members mo WHERE mo.id = mid AND mo.gamification_opt_out IS TRUE)))
    );
  END IF;

  SELECT c.sort_order, c.cycle_start, c.cycle_end
  INTO v_current_sort, v_cycle_start, v_cycle_end
  FROM public.cycles c WHERE c.is_current = true LIMIT 1;

  IF v_current_sort IS NULL THEN
    RETURN QUERY
    SELECT mid, 0::integer, 0::integer, 0::integer, 0::integer
    FROM unnest(p_member_ids) mid;
    RETURN;
  END IF;

  RETURN QUERY
  WITH
  member_cycles AS (
    SELECT
      gp.member_id,
      c.sort_order
    FROM public.gamification_points gp
    JOIN public.cycles c
      -- #1464: atribuição de ciclo por data do FATO (occurred_at), não do lançamento (created_at).
      ON COALESCE(gp.occurred_at, gp.created_at) >= c.cycle_start::timestamp
     AND (c.cycle_end IS NULL OR COALESCE(gp.occurred_at, gp.created_at) < (c.cycle_end + interval '1 day')::timestamp)
    WHERE gp.member_id = ANY(p_member_ids)
    GROUP BY gp.member_id, c.sort_order
  ),
  walked AS (
    SELECT
      mc.member_id,
      mc.sort_order,
      mc.sort_order + ROW_NUMBER() OVER (PARTITION BY mc.member_id ORDER BY mc.sort_order DESC) AS run_key
    FROM member_cycles mc
    WHERE mc.sort_order <= v_current_sort
  ),
  runs AS (
    SELECT
      w.member_id,
      w.run_key,
      COUNT(*)::integer AS streak_length,
      MAX(w.sort_order) AS last_sort
    FROM walked w
    GROUP BY w.member_id, w.run_key
  ),
  current_streaks AS (
    SELECT
      r.member_id,
      MAX(r.streak_length) FILTER (WHERE r.last_sort >= v_current_sort - 1) AS current_streak,
      MAX(r.streak_length) AS longest_streak
    FROM runs r
    GROUP BY r.member_id
  ),
  cycle_pts AS (
    SELECT
      gp.member_id,
      SUM(gp.points)::integer AS pts_this_cycle
    FROM public.gamification_points gp
    WHERE gp.member_id = ANY(p_member_ids)
      -- #1464: janela do ciclo corrente por occurred_at.
      AND COALESCE(gp.occurred_at, gp.created_at) >= v_cycle_start::timestamp
      AND (v_cycle_end IS NULL OR COALESCE(gp.occurred_at, gp.created_at) < (v_cycle_end + interval '1 day')::timestamp)
    GROUP BY gp.member_id
  ),
  active_counts AS (
    SELECT mc.member_id, COUNT(*)::integer AS cnt
    FROM member_cycles mc
    GROUP BY mc.member_id
  )
  SELECT
    mid::uuid AS member_id,
    COALESCE(cs.current_streak, 0)::integer AS current_streak_count,
    COALESCE(cp.pts_this_cycle, 0)::integer AS points_this_cycle,
    COALESCE(ac.cnt, 0)::integer AS active_cycles_count,
    COALESCE(cs.longest_streak, 0)::integer AS longest_streak_count
  FROM unnest(p_member_ids) AS mid
  LEFT JOIN current_streaks cs ON cs.member_id = mid
  LEFT JOIN cycle_pts cp ON cp.member_id = mid
  LEFT JOIN active_counts ac ON ac.member_id = mid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_gamification_leaderboard(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_cycle_code text DEFAULT NULL::text, p_scope_kind text DEFAULT 'global'::text, p_chapter_code text DEFAULT NULL::text, p_initiative_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(member_id uuid, name text, chapter text, photo_url text, operational_role text, designations text[], total_points integer, attendance_points integer, learning_points integer, cert_points integer, badge_points integer, artifact_points integer, course_points integer, showcase_points integer, bonus_points integer, producao_points integer, curadoria_points integer, champions_points integer, cycle_points integer, cycle_attendance_points integer, cycle_course_points integer, cycle_artifact_points integer, cycle_showcase_points integer, cycle_bonus_points integer, cycle_learning_points integer, cycle_cert_points integer, cycle_badge_points integer, cycle_producao_points integer, cycle_curadoria_points integer, cycle_champions_points integer, total_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid; v_cycle_start date; v_cycle_end date; v_total_count int;
  -- Papel e designações só para membro com vínculo vigente; os demais veem o ranking público.
  v_full boolean := NOT public._request_is_rest_caller() OR public.rls_is_authoritative_member();
  v_effective_limit int; v_effective_offset int; v_scope text;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege'; END IF;
  v_effective_limit := GREATEST(1, LEAST(COALESCE(p_limit, 50), 200));
  v_effective_offset := GREATEST(0, COALESCE(p_offset, 0));
  v_scope := COALESCE(NULLIF(trim(p_scope_kind), ''), 'global');
  IF v_scope NOT IN ('global', 'chapter', 'tribe') THEN
    RAISE EXCEPTION 'invalid_scope_kind: % (allowed: global|chapter|tribe)', v_scope USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_scope = 'chapter' AND (p_chapter_code IS NULL OR trim(p_chapter_code) = '') THEN
    RAISE EXCEPTION 'chapter_code_required' USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_scope = 'tribe' AND p_initiative_id IS NULL THEN
    RAISE EXCEPTION 'initiative_id_required' USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF p_cycle_code IS NOT NULL THEN
    SELECT c.cycle_start, c.cycle_end INTO v_cycle_start, v_cycle_end FROM public.cycles c WHERE c.cycle_code = p_cycle_code;
    IF v_cycle_start IS NULL THEN RAISE EXCEPTION 'cycle_not_found: %', p_cycle_code USING ERRCODE = 'no_data_found'; END IF;
  ELSE
    SELECT c.cycle_start, c.cycle_end INTO v_cycle_start, v_cycle_end FROM public.cycles c WHERE c.is_current = true LIMIT 1;
  END IF;

  SELECT COUNT(*) INTO v_total_count FROM public.members m
  WHERE m.gamification_opt_out = false
    AND (m.current_cycle_active = true
         OR EXISTS (SELECT 1 FROM public.gamification_points gp_check
                    WHERE gp_check.member_id = m.id
                      AND COALESCE(gp_check.occurred_at, gp_check.created_at) >= v_cycle_start
                      AND (v_cycle_end IS NULL OR COALESCE(gp_check.occurred_at, gp_check.created_at) < (v_cycle_end + INTERVAL '1 day'))))
    AND (v_scope = 'global'
         OR (v_scope = 'chapter' AND m.chapter = p_chapter_code)
         OR (v_scope = 'tribe' AND EXISTS (
             SELECT 1 FROM public.persons p JOIN public.auth_engagements ae ON ae.person_id = p.id
             WHERE p.legacy_member_id = m.id AND ae.is_authoritative = true AND ae.initiative_id = p_initiative_id)));

  RETURN QUERY
  SELECT m.id, m.name, m.chapter, m.photo_url, CASE WHEN v_full THEN m.operational_role END, CASE WHEN v_full THEN m.designations END,
    COALESCE(sum(gp.points), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'presenca'), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'trilha'), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'certificacoes' AND gr.slug LIKE 'cert_%'), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.slug = 'badge'), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.slug = 'artifact_published'), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'trilha'), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.slug LIKE 'showcase%'), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar IS NULL OR gr.pillar NOT IN ('presenca','trilha','certificacoes','producao','curadoria','champions')), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'producao' AND gr.slug <> 'artifact_published' AND gr.slug NOT LIKE 'showcase%'), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'curadoria'), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'champions'), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE COALESCE(gp.occurred_at, gp.created_at) >= v_cycle_start AND (v_cycle_end IS NULL OR COALESCE(gp.occurred_at, gp.created_at) < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'presenca' AND COALESCE(gp.occurred_at, gp.created_at) >= v_cycle_start AND (v_cycle_end IS NULL OR COALESCE(gp.occurred_at, gp.created_at) < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'trilha' AND COALESCE(gp.occurred_at, gp.created_at) >= v_cycle_start AND (v_cycle_end IS NULL OR COALESCE(gp.occurred_at, gp.created_at) < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.slug = 'artifact_published' AND COALESCE(gp.occurred_at, gp.created_at) >= v_cycle_start AND (v_cycle_end IS NULL OR COALESCE(gp.occurred_at, gp.created_at) < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.slug LIKE 'showcase%' AND COALESCE(gp.occurred_at, gp.created_at) >= v_cycle_start AND (v_cycle_end IS NULL OR COALESCE(gp.occurred_at, gp.created_at) < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE (gr.pillar IS NULL OR gr.pillar NOT IN ('presenca','trilha','certificacoes','producao','curadoria','champions')) AND COALESCE(gp.occurred_at, gp.created_at) >= v_cycle_start AND (v_cycle_end IS NULL OR COALESCE(gp.occurred_at, gp.created_at) < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'trilha' AND COALESCE(gp.occurred_at, gp.created_at) >= v_cycle_start AND (v_cycle_end IS NULL OR COALESCE(gp.occurred_at, gp.created_at) < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'certificacoes' AND gr.slug LIKE 'cert_%' AND COALESCE(gp.occurred_at, gp.created_at) >= v_cycle_start AND (v_cycle_end IS NULL OR COALESCE(gp.occurred_at, gp.created_at) < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.slug = 'badge' AND COALESCE(gp.occurred_at, gp.created_at) >= v_cycle_start AND (v_cycle_end IS NULL OR COALESCE(gp.occurred_at, gp.created_at) < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'producao' AND gr.slug <> 'artifact_published' AND gr.slug NOT LIKE 'showcase%' AND COALESCE(gp.occurred_at, gp.created_at) >= v_cycle_start AND (v_cycle_end IS NULL OR COALESCE(gp.occurred_at, gp.created_at) < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'curadoria' AND COALESCE(gp.occurred_at, gp.created_at) >= v_cycle_start AND (v_cycle_end IS NULL OR COALESCE(gp.occurred_at, gp.created_at) < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer,
    COALESCE(sum(gp.points) FILTER (WHERE gr.pillar = 'champions' AND COALESCE(gp.occurred_at, gp.created_at) >= v_cycle_start AND (v_cycle_end IS NULL OR COALESCE(gp.occurred_at, gp.created_at) < (v_cycle_end + INTERVAL '1 day'))), 0::bigint)::integer,
    v_total_count
  FROM public.members m
    LEFT JOIN public.gamification_points gp ON gp.member_id = m.id
    LEFT JOIN public.gamification_rules gr ON gr.organization_id = gp.organization_id AND gr.slug = gp.category
  WHERE m.gamification_opt_out = false
    AND (m.current_cycle_active = true
         OR EXISTS (SELECT 1 FROM public.gamification_points gp_check
                    WHERE gp_check.member_id = m.id
                      AND COALESCE(gp_check.occurred_at, gp_check.created_at) >= v_cycle_start
                      AND (v_cycle_end IS NULL OR COALESCE(gp_check.occurred_at, gp_check.created_at) < (v_cycle_end + INTERVAL '1 day'))))
    AND (v_scope = 'global'
         OR (v_scope = 'chapter' AND m.chapter = p_chapter_code)
         OR (v_scope = 'tribe' AND EXISTS (
             SELECT 1 FROM public.persons p JOIN public.auth_engagements ae ON ae.person_id = p.id
             WHERE p.legacy_member_id = m.id AND ae.is_authoritative = true AND ae.initiative_id = p_initiative_id)))
  GROUP BY m.id, m.name, m.chapter, m.photo_url, m.operational_role, m.designations
  ORDER BY COALESCE(sum(gp.points), 0::bigint) DESC, m.name ASC
  LIMIT v_effective_limit OFFSET v_effective_offset;
END;
$function$;
