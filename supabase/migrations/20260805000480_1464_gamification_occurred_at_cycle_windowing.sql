-- #1464 (Onda 3 / B0 gamificação) — atribuição de ciclo por DATA DO FATO, não data do lançamento.
--
-- Achado (auditoria 2026-07-21, docs/audit/2026-07-21_scoring_merit_audit.md, seção B0; re-aterrado
-- 2026-07-22): o placar do "ciclo atual" janela gamification_points por created_at (quando o ponto foi
-- LANÇADO). A EF sync-attendance-points (cron a cada 5 dias + botão admin) insere presença com
-- ref_id=attendance.id e SEM created_at -> created_at=now() do run. O flush de 2026-07-11 despejou 560
-- linhas de presença histórica (eventos de 2025-10 a 2026-07) no ciclo corrente. Ao vivo: 526 linhas /
-- 5260 pts de presença resolvem para eventos < cycle_start (2026-07-09) e estavam mal-atribuídas a C4.
-- A MATEMÁTICA de agregação está correta (soma/pilares auditados); o erro é ATRIBUIÇÃO DE CICLO.
--
-- Correção (4 partes):
--   1. Coluna occurred_at (data real do fato). Backfill: presença = events.date (via ref_id -> attendance
--      -> event  OU ref_id -> event, os dois esquemas históricos); demais categorias = created_at (o
--      lançamento em tempo real É o fato). occurred_at fica populado em TODAS as linhas existentes.
--   2. Trigger BEFORE INSERT caller-agnóstico: normaliza occurred_at de presença a partir do ref_id em
--      qualquer caminho de escrita (EF cron/admin, SQL sync, futuro) — impede recorrência de presença
--      marcada com atraso cross-ciclo. Valor explícito de occurred_at sempre vence (backfill/testes).
--   3. Rejanela de ciclo por COALESCE(occurred_at, created_at) em get_member_gamification_stats,
--      get_member_xp_pillars (ramo cycle) e get_gamification_leaderboard (colunas cycle_* + membership).
--      created_at continua sendo "quando foi lançado" (auditoria). Base = corpo VIVO via pg_get_functiondef.
--      get_public_leaderboard NÃO muda (é vitalício puro, sem janela de ciclo).
--   4. get_member_xp_pillars: ORDER BY CASE pillar ganha 'protagonismo' (posição 7, após champions;
--      casa PILLAR_EMOJI/PILLAR_I18N do frontend). Antes caía em NULL -> ordenação indefinida.
--
-- PRESERVADO (#1448/mig 472): o pilar certificacoes conta VITALÍCIO mesmo no escopo cycle (EXISTS de
-- certificacoes intacto). A rejanela por occurred_at é só para XP de FLUXO (presença etc.).
--
-- IMPACTO VISÍVEL (decisão humana ratificada antes de aplicar): re-atribuição RETROATIVA muda o placar
-- do ciclo corrente para membros (49 mudam; total de C4 ~7510 -> ~2250 pts; ex.: rank 1 -> 24). Vitalício
-- NÃO muda; nada é revogado. Só a atribuição de ciclo.

-- ============================================================================
-- 1. Coluna occurred_at + backfill (data do fato).
-- ============================================================================
ALTER TABLE public.gamification_points ADD COLUMN IF NOT EXISTS occurred_at timestamptz;

COMMENT ON COLUMN public.gamification_points.occurred_at IS
  'Data REAL do fato que gerou os pontos (#1464). Presenca = events.date; demais = created_at (lançamento em tempo real É o fato). Janela de ciclo usa COALESCE(occurred_at, created_at); created_at = quando foi lançado (auditoria).';

-- Esquema A: ref_id = attendance.id -> attendance.event_id -> events.date (o flush da EF).
UPDATE public.gamification_points gp
SET occurred_at = (e.date + time '12:00') AT TIME ZONE 'America/Sao_Paulo'
FROM public.attendance a
JOIN public.events e ON e.id = a.event_id
WHERE a.id = gp.ref_id
  AND gp.category = 'attendance'
  AND e.date IS NOT NULL
  AND gp.occurred_at IS NULL;

-- Esquema B: ref_id = events.id (função SQL sync_attendance_points) -> events.date.
UPDATE public.gamification_points gp
SET occurred_at = (e.date + time '12:00') AT TIME ZONE 'America/Sao_Paulo'
FROM public.events e
WHERE e.id = gp.ref_id
  AND gp.category = 'attendance'
  AND e.date IS NOT NULL
  AND gp.occurred_at IS NULL;

-- Fallback: demais categorias (e presença órfã sem evento resolvível) = created_at.
UPDATE public.gamification_points
SET occurred_at = created_at
WHERE occurred_at IS NULL;

-- ============================================================================
-- 2. Trigger BEFORE INSERT caller-agnóstico — normaliza occurred_at de presença futura.
-- ============================================================================
CREATE OR REPLACE FUNCTION public._gp_set_occurred_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_date date;
BEGIN
  -- Valor explícito sempre vence (backfill/correções/testes).
  IF NEW.occurred_at IS NOT NULL THEN
    RETURN NEW;
  END IF;
  -- Presença: derivar a data do FATO (evento) do ref_id, independente do caminho de escrita
  -- (EF usa ref_id=attendance.id; SQL sync usa ref_id=event.id). #1464.
  IF NEW.category = 'attendance' AND NEW.ref_id IS NOT NULL THEN
    SELECT e.date INTO v_date
    FROM public.attendance a
    JOIN public.events e ON e.id = a.event_id
    WHERE a.id = NEW.ref_id;
    IF v_date IS NULL THEN
      SELECT e.date INTO v_date FROM public.events e WHERE e.id = NEW.ref_id;
    END IF;
  END IF;
  NEW.occurred_at := COALESCE(
    CASE WHEN v_date IS NOT NULL THEN (v_date + time '12:00') AT TIME ZONE 'America/Sao_Paulo' END,
    NEW.created_at,
    now()
  );
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public._gp_set_occurred_at() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_gp_set_occurred_at ON public.gamification_points;
CREATE TRIGGER trg_gp_set_occurred_at
  BEFORE INSERT ON public.gamification_points
  FOR EACH ROW EXECUTE FUNCTION public._gp_set_occurred_at();

-- ============================================================================
-- 3a. get_member_gamification_stats — janela por occurred_at (streaks + points_this_cycle).
-- ============================================================================
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

-- ============================================================================
-- 3b. get_member_xp_pillars — ramo cycle por occurred_at + ORDER BY ganha protagonismo.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_member_xp_pillars(p_member_id uuid DEFAULT NULL::uuid, p_cycle_code text DEFAULT NULL::text, p_scope text DEFAULT 'lifetime'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller members%ROWTYPE;
  v_target_id uuid;
  v_target members%ROWTYPE;
  v_is_self boolean;
  v_can_view_pii boolean;
  v_scope text;
  v_cycle_code text;
  v_cycle_start timestamptz;
  v_cycle_end timestamptz;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;

  IF p_scope NOT IN ('cycle','lifetime') THEN
    RETURN jsonb_build_object('error','invalid_scope','detail','must be cycle or lifetime');
  END IF;

  v_target_id := COALESCE(p_member_id, v_caller.id);
  v_is_self := (v_target_id = v_caller.id);

  SELECT * INTO v_target FROM members WHERE id = v_target_id;
  IF v_target.id IS NULL THEN
    RETURN jsonb_build_object('error','member_not_found');
  END IF;
  IF v_target.organization_id != v_caller.organization_id THEN
    RETURN jsonb_build_object('error','member_not_in_org');
  END IF;

  IF NOT v_is_self THEN
    v_can_view_pii := public.can_by_member(v_caller.id, 'view_pii'::text);
    -- FU-2 Slice C: an org-scoped view_pii grant must not elevate a chapter-restricted caller
    -- (partner-chapter leader) past another chapter's gamification opt-out. GP/sede (scope NULL)
    -- keep the elevation; everyone else falls back to the public/opt-out path cross-chapter.
    v_scope := public.caller_chapter_scope();
    IF v_can_view_pii AND v_scope IS NOT NULL AND v_target.chapter IS DISTINCT FROM v_scope THEN
      v_can_view_pii := false;
    END IF;
    IF NOT v_can_view_pii AND COALESCE(v_target.gamification_opt_out, false) THEN
      RETURN jsonb_build_object('error','member_opted_out_from_public');
    END IF;
  END IF;

  IF p_scope = 'cycle' THEN
    IF p_cycle_code IS NULL THEN
      SELECT cycle_code, cycle_start::timestamptz, cycle_end::timestamptz
        INTO v_cycle_code, v_cycle_start, v_cycle_end
      FROM cycles WHERE is_current = true LIMIT 1;
    ELSE
      SELECT cycle_code, cycle_start::timestamptz, cycle_end::timestamptz
        INTO v_cycle_code, v_cycle_start, v_cycle_end
      FROM cycles WHERE cycle_code = p_cycle_code LIMIT 1;
      IF v_cycle_code IS NULL THEN
        RETURN jsonb_build_object('error','cycle_not_found');
      END IF;
    END IF;
  END IF;
  -- lifetime: v_cycle_* stay NULL

  WITH points_filtered AS (
    SELECT gp.category, gp.points
    FROM gamification_points gp
    WHERE gp.member_id = v_target_id
      AND gp.organization_id = v_caller.organization_id
      AND (
        p_scope = 'lifetime'
        -- #1448: conquistas vitalícias (pilar certificacoes = badges + cert_*) sempre contam,
        -- mesmo na visão de ciclo. Só XP de fluxo é janelado por occurred_at (data do fato, #1464).
        OR EXISTS (
          SELECT 1 FROM gamification_rules r_win
          WHERE r_win.organization_id = gp.organization_id
            AND r_win.slug = gp.category
            AND r_win.pillar = 'certificacoes'
        )
        OR (COALESCE(gp.occurred_at, gp.created_at) >= v_cycle_start
            AND (v_cycle_end IS NULL OR COALESCE(gp.occurred_at, gp.created_at) < (v_cycle_end + interval '1 day')))
      )
  ),
  rule_breakdown AS (
    SELECT
      r.pillar,
      r.slug,
      r.display_name_i18n,
      r.description_i18n,
      r.base_points,
      r.cap_points,
      r.trigger_source,
      COALESCE(SUM(p.points), 0)::int AS pts,
      -- #1087 Onda 3: estorno (points < 0) não conta como "earned"; pts segue SUM cru (net).
      (COUNT(p.points) FILTER (WHERE p.points > 0))::int AS earned_count
    FROM gamification_rules r
    LEFT JOIN points_filtered p ON p.category = r.slug
    WHERE r.organization_id = v_caller.organization_id
      AND r.active = true
    GROUP BY r.pillar, r.slug, r.display_name_i18n, r.description_i18n, r.base_points, r.cap_points, r.trigger_source
  ),
  pillar_agg AS (
    SELECT
      pillar,
      SUM(pts)::int AS total_pts,
      SUM(earned_count)::int AS earned_count,
      jsonb_agg(
        jsonb_build_object(
          'slug', slug,
          'display_name_i18n', display_name_i18n,
          'description_i18n', description_i18n,
          'base_points', base_points,
          'cap_points', cap_points,
          'trigger_source', trigger_source,
          'pts', pts,
          'count', earned_count
        ) ORDER BY pts DESC, slug
      ) AS rules
    FROM rule_breakdown
    GROUP BY pillar
  )
  SELECT jsonb_build_object(
    'member_id', v_target_id,
    'member_name', v_target.name,
    'is_self', v_is_self,
    'scope', p_scope,
    'cycle_code', v_cycle_code,
    'cycle_start', v_cycle_start,
    'cycle_end', v_cycle_end,
    'total_pts', COALESCE((SELECT SUM(total_pts)::int FROM pillar_agg), 0),
    'pillars', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'pillar', pillar,
          'total_pts', total_pts,
          'earned_count', earned_count,
          -- #1448: pilar vitalício (não janelado por ciclo) — UI rotula "vitalício" no modo ciclo.
          'is_lifetime', (pillar = 'certificacoes'),
          'rules', rules
        )
        ORDER BY CASE pillar
          WHEN 'presenca' THEN 1
          WHEN 'trilha' THEN 2
          WHEN 'certificacoes' THEN 3
          WHEN 'producao' THEN 4
          WHEN 'curadoria' THEN 5
          WHEN 'champions' THEN 6
          WHEN 'protagonismo' THEN 7
        END
      ) FROM pillar_agg
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- ============================================================================
-- 3c. get_gamification_leaderboard — colunas cycle_* + membership por occurred_at.
--     (colunas vitalícias = SUM cru, sem janela, INTOCADAS.)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_gamification_leaderboard(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_cycle_code text DEFAULT NULL::text, p_scope_kind text DEFAULT 'global'::text, p_chapter_code text DEFAULT NULL::text, p_initiative_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(member_id uuid, name text, chapter text, photo_url text, operational_role text, designations text[], total_points integer, attendance_points integer, learning_points integer, cert_points integer, badge_points integer, artifact_points integer, course_points integer, showcase_points integer, bonus_points integer, producao_points integer, curadoria_points integer, champions_points integer, cycle_points integer, cycle_attendance_points integer, cycle_course_points integer, cycle_artifact_points integer, cycle_showcase_points integer, cycle_bonus_points integer, cycle_learning_points integer, cycle_cert_points integer, cycle_badge_points integer, cycle_producao_points integer, cycle_curadoria_points integer, cycle_champions_points integer, total_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid; v_cycle_start date; v_cycle_end date; v_total_count int;
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
  SELECT m.id, m.name, m.chapter, m.photo_url, m.operational_role, m.designations,
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


-- ============================================================================
-- 3d. Demais leitores de ciclo de gamification_points — rejanela por occurred_at (#1464).
--     Mesmo COALESCE(occurred_at, created_at) SÓ nos predicados de janela-de-ciclo; usos
--     de created_at para exibição/ordenação/outras tabelas preservados. Base = corpo VIVO
--     (pg_get_functiondef); fidelidade provada por reverse-substitution. get_member_cycle_xp
--     alimenta cycle_points + rank do PERFIL (consistência com o leaderboard).
-- ============================================================================

-- 3d — get_member_cycle_xp
CREATE OR REPLACE FUNCTION public.get_member_cycle_xp(p_member_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  cycle_start_date date;
  v_rank int;
  v_total int;
  result json;
  v_caller_id uuid;
  v_scope text;
begin
  -- XP gate: SECDEF + authenticated-grant allowed enumerating any member's XP/rank by id.
  select id into v_caller_id from public.members where auth_id = auth.uid() and is_active = true;
  if v_caller_id is null then
    raise exception 'Not authenticated' using errcode = 'insufficient_privilege';
  end if;
  if p_member_id <> v_caller_id and not public.can_by_member(v_caller_id, 'view_pii') then
    raise exception 'Unauthorized' using errcode = 'insufficient_privilege';
  end if;

  -- FU-2 Slice A: chapter-scope — non-GP/non-sede callers may not read out-of-chapter XP.
  if p_member_id <> v_caller_id then
    v_scope := public.caller_chapter_scope();
    if v_scope is not null
       and (select chapter from public.members where id = p_member_id) is distinct from v_scope then
      raise exception 'Unauthorized' using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- Cycle window comes solely from the current cycle (the prior hardcoded literal fallback was removed).
  select cycle_start into cycle_start_date
  from public.cycles where is_current = true limit 1;

  -- M5 (#419 D1): rank by THIS cycle's XP (matches the displayed cycle_points), with a
  -- deterministic member_id tiebreak. Previously ranked on lifetime SUM(points), which
  -- contradicted the cycle_points shown and reshuffled ties non-deterministically.
  WITH ranked AS (
    SELECT member_id,
           COALESCE(SUM(points) FILTER (WHERE COALESCE(occurred_at, created_at) >= cycle_start_date), 0) as cycle_pts,
           ROW_NUMBER() OVER (
             ORDER BY COALESCE(SUM(points) FILTER (WHERE COALESCE(occurred_at, created_at) >= cycle_start_date), 0) DESC,
                      member_id
           ) as pos
    FROM public.gamification_points
    GROUP BY member_id
  )
  SELECT pos, (SELECT COUNT(DISTINCT member_id) FROM public.gamification_points)
  INTO v_rank, v_total
  FROM ranked WHERE member_id = p_member_id;

  -- #1080: buckets derived from the canonical pillar taxonomy via LEFT JOIN to gamification_rules.
  -- cycle_points/lifetime_points remain a plain SUM over all categories (bucket-independent).
  select json_build_object(
    'lifetime_points', coalesce(sum(gp.points), 0)::int,
    'cycle_points', coalesce(sum(gp.points) filter (where COALESCE(gp.occurred_at, gp.created_at) >= cycle_start_date), 0)::int,
    'cycle_attendance', coalesce(sum(gp.points) filter (where r.pillar = 'presenca' and COALESCE(gp.occurred_at, gp.created_at) >= cycle_start_date), 0)::int,
    'cycle_learning', coalesce(sum(gp.points) filter (where r.pillar = 'trilha' and COALESCE(gp.occurred_at, gp.created_at) >= cycle_start_date), 0)::int,
    'cycle_certs', coalesce(sum(gp.points) filter (where r.pillar = 'certificacoes' and COALESCE(gp.occurred_at, gp.created_at) >= cycle_start_date), 0)::int,
    'cycle_courses', coalesce(sum(gp.points) filter (where r.pillar = 'trilha' and COALESCE(gp.occurred_at, gp.created_at) >= cycle_start_date), 0)::int,
    'cycle_artifacts', coalesce(sum(gp.points) filter (where r.pillar = 'producao' and gp.category not like 'showcase%' and COALESCE(gp.occurred_at, gp.created_at) >= cycle_start_date), 0)::int,
    'cycle_showcase', coalesce(sum(gp.points) filter (where r.pillar = 'producao' and gp.category like 'showcase%' and COALESCE(gp.occurred_at, gp.created_at) >= cycle_start_date), 0)::int,
    'cycle_bonus', coalesce(sum(gp.points) filter (where (r.pillar is null or r.pillar not in ('presenca','trilha','certificacoes','producao')) and COALESCE(gp.occurred_at, gp.created_at) >= cycle_start_date), 0)::int,
    'cycle_code', (select cycle_code from public.cycles where is_current = true limit 1),
    'cycle_label', (select cycle_label from public.cycles where is_current = true limit 1),
    'rank_position', coalesce(v_rank, 0),
    'total_ranked', coalesce(v_total, 0)
  ) into result
  from public.gamification_points gp
  left join public.gamification_rules r
    on r.slug = gp.category and r.organization_id = gp.organization_id
  where gp.member_id = p_member_id;

  return coalesce(result, '{}');
end;
$function$;

-- 3d — get_my_points_statement
CREATE OR REPLACE FUNCTION public.get_my_points_statement(p_scope text DEFAULT 'cycle'::text, p_category text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_member_id uuid;
  v_org_id uuid;
  v_limit integer;
  v_offset integer;
  v_cycle_code text;
  v_from timestamptz;
  v_to timestamptz;
BEGIN
  SELECT m.id, m.organization_id INTO v_member_id, v_org_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  IF p_scope NOT IN ('cycle','lifetime') THEN
    RAISE EXCEPTION 'invalid scope: % (must be cycle or lifetime)', p_scope;
  END IF;
  v_limit := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
  v_offset := GREATEST(COALESCE(p_offset, 0), 0);

  IF p_scope = 'cycle' THEN
    -- current-cycle window: same convention as get_member_xp_pillars / award_champion
    SELECT c.cycle_code, c.cycle_start::timestamptz,
           CASE WHEN c.cycle_end IS NULL THEN NULL
                ELSE (c.cycle_end + interval '1 day')::timestamptz END
      INTO v_cycle_code, v_from, v_to
    FROM public.cycles c
    WHERE c.is_current = true
    LIMIT 1;
  END IF;
  -- lifetime (or no current cycle): v_from/v_to stay NULL → no window filter when lifetime;
  -- cycle scope with no current cycle yields an empty statement (v_from NULL fails the >=).

  RETURN (
    WITH filtered AS (
      SELECT gp.id, gp.created_at, gp.points, gp.category, gp.reason, gp.ref_id, gp.granted_by,
             r.pillar, r.display_name_i18n
      FROM public.gamification_points gp
      LEFT JOIN LATERAL (
        SELECT gr.pillar, gr.display_name_i18n
        FROM public.gamification_rules gr
        WHERE gr.organization_id = gp.organization_id
          AND gr.slug = gp.category
        ORDER BY gr.effective_from DESC
        LIMIT 1
      ) r ON true
      WHERE gp.member_id = v_member_id
        AND gp.organization_id = v_org_id
        AND (
          p_scope = 'lifetime'
          OR (COALESCE(gp.occurred_at, gp.created_at) >= v_from AND (v_to IS NULL OR COALESCE(gp.occurred_at, gp.created_at) < v_to))
        )
        AND (p_category IS NULL OR gp.category = p_category)
    )
    SELECT jsonb_build_object(
      'member_id', v_member_id,
      'scope', p_scope,
      'cycle_code', CASE WHEN p_scope = 'cycle' THEN v_cycle_code END,
      'category_filter', p_category,
      'total_count', (SELECT count(*) FROM filtered),
      'total_points', COALESCE((SELECT sum(f.points) FROM filtered f), 0),
      'limit', v_limit,
      'offset', v_offset,
      'entries', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', e.id,
          'created_at', e.created_at,
          'points', e.points,
          'category', e.category,
          'pillar', e.pillar,
          'rule_display_name_i18n', e.display_name_i18n,
          'reason', e.reason,
          'ref_id', e.ref_id,
          'granted_by', e.granted_by,
          'granted_by_name', e.granted_by_name,
          'is_reversal', e.is_reversal,
          'champion', e.champion
        ) ORDER BY e.created_at DESC, e.id DESC)
        FROM (
          SELECT f.*, gm.name AS granted_by_name,
                 (f.points < 0) AS is_reversal,
                 CASE WHEN f.category LIKE 'champion\_%' THEN (
                   SELECT jsonb_build_object(
                     'awarded_by_name', am.name,
                     'justification', ca.justification,
                     'criteria_met', ca.criteria_met,
                     'status', ca.status
                   )
                   FROM public.champions_awarded ca
                   LEFT JOIN public.members am ON am.id = ca.awarded_by
                   WHERE ca.id = f.ref_id
                 ) END AS champion
          FROM filtered f
          LEFT JOIN public.members gm ON gm.id = f.granted_by
          ORDER BY f.created_at DESC, f.id DESC
          LIMIT v_limit OFFSET v_offset
        ) e
      ), '[]'::jsonb)
    )
  );
END;
$function$;

-- 3d — get_admin_dashboard
CREATE OR REPLACE FUNCTION public.get_admin_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb; v_cycle_start date; v_current_cycle int;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT (public.can_by_member(v_caller_id, 'manage_platform')
          OR public.can_by_member(v_caller_id, 'view_chapter_dashboards')) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform or view_chapter_dashboards permission';
  END IF;

  SELECT cycle_start,
    CASE WHEN cycle_code ~ '^\w+_\d+$' THEN substring(cycle_code from '\d+')::int ELSE sort_order END
  INTO v_cycle_start, v_current_cycle
  FROM public.cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := '2026-01-01'; END IF;
  IF v_current_cycle IS NULL THEN v_current_cycle := 3; END IF;

  SELECT jsonb_build_object(
    'generated_at', now(),
    'kpis', jsonb_build_object(
      'active_members', (SELECT count(*) FROM public.v_operational_members),
      'adoption_7d', (SELECT ROUND(count(*) FILTER (WHERE m.last_seen_at > now() - interval '7 days')::numeric / NULLIF(count(*), 0) * 100, 1) FROM public.members m WHERE m.id IN (SELECT id FROM public.v_operational_members)),
      'deliverables_completed', (SELECT count(*) FROM public.board_items WHERE status = 'done' AND NOT public.is_confidential_board(board_id)),
      'deliverables_total', (SELECT count(*) FROM public.board_items WHERE status != 'archived' AND NOT public.is_confidential_board(board_id)),
      'impact_hours', (SELECT COALESCE(public.get_impact_hours_excluding_excused(), 0)),
      'cpmai_current', (SELECT count(DISTINCT member_id) FROM public.gamification_points WHERE category = 'cert_cpmai' AND COALESCE(occurred_at, created_at) >= v_cycle_start),
      'cpmai_target', (SELECT target_value FROM public.annual_kpi_targets WHERE kpi_key = 'cpmai_certified' AND cycle = v_current_cycle LIMIT 1),
      'chapters_current', (public.get_chapter_metrics()->>'signed')::int,
      'chapters_in_negotiation', (public.get_chapter_metrics()->>'in_negotiation')::int,
      'chapters_engaged', (public.get_chapter_metrics()->>'engaged')::int,
      'chapters_target', (SELECT target_value FROM public.annual_kpi_targets WHERE kpi_key = 'chapters_participating' AND cycle = v_current_cycle LIMIT 1)
    ),
    'alerts', (SELECT COALESCE(jsonb_agg(alert), '[]'::jsonb) FROM (
      SELECT jsonb_build_object(
        'severity', 'high',
        'message', count(*) || ' pesquisadores sem tribo',
        'action_label', 'Ir para Tribos',
        'action_href', '/admin/tribes'
      ) AS alert
      FROM public.members m
      WHERE m.is_active = true
        AND public.get_member_tribe(m.id) IS NULL
        AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'manager', 'deputy_manager', 'observer')
      HAVING count(*) > 0

      UNION ALL

      SELECT jsonb_build_object(
        'severity', 'medium',
        'message', count(*) || ' stakeholders sem conta',
        'action_label', 'Ver Membros',
        'action_href', '/admin/members'
      )
      FROM public.members
      WHERE is_active = true AND auth_id IS NULL AND operational_role IN ('sponsor', 'chapter_liaison')
      HAVING count(*) > 0

      UNION ALL

      SELECT jsonb_build_object(
        'severity', 'medium',
        'message', count(*) || ' membros em risco de dropout',
        'action_label', 'Ver lista',
        'action_href', '/admin/members'
      )
      FROM public.members m
      WHERE m.is_active = true AND m.current_cycle_active
        AND public.get_member_tribe(m.id) IS NOT NULL
        AND m.id NOT IN (
          SELECT a.member_id FROM public.attendance a
          JOIN public.events e ON e.id = a.event_id
          WHERE e.date > now() - interval '60 days'
            AND a.present IS TRUE
        )
      HAVING count(*) > 0

      UNION ALL

      SELECT jsonb_build_object(
        'severity', 'high',
        'message', t.name || ' sem reuniao ha ' || (current_date - max(e.date)) || ' dias',
        'action_label', 'Ver Tribo',
        'action_href', '/tribe/' || t.id
      )
      FROM public.tribes t
      LEFT JOIN public.initiatives i ON i.legacy_tribe_id = t.id
      LEFT JOIN public.events e ON e.initiative_id = i.id AND e.type = 'tribo' AND e.date <= current_date
      WHERE t.is_active = true
      GROUP BY t.id, t.name
      HAVING max(e.date) IS NOT NULL AND current_date - max(e.date) > 14

      UNION ALL

      SELECT jsonb_build_object(
        'severity', 'medium',
        'message', count(*) || ' membros detractors (3+ faltas consecutivas)',
        'action_label', 'Quadro de Presenca',
        'action_href', '/attendance?tab=grid'
      )
      FROM public.members m
      WHERE m.is_active AND m.current_cycle_active
        AND public.get_member_tribe(m.id) IS NOT NULL
        AND m.id IN (
          SELECT cand.id
          FROM public.members cand
          WHERE cand.is_active AND cand.current_cycle_active
            AND (
              SELECT count(*) FILTER (WHERE NOT ranked.was_present)
              FROM (
                SELECT (att.present IS TRUE) AS was_present,
                       ROW_NUMBER() OVER (ORDER BY el.event_date DESC, el.event_id DESC) AS rn
                FROM public._attendance_eligible_events(cand.id, NULL) el
                LEFT JOIN public.attendance att ON att.event_id = el.event_id AND att.member_id = cand.id
                WHERE att.excused IS NOT TRUE
              ) ranked
              WHERE ranked.rn <= 3
            ) >= 3
        )
      HAVING count(*) > 0
    ) sub),
    'recent_activity', (SELECT COALESCE(jsonb_agg(r.activity ORDER BY r.ts DESC), '[]'::jsonb) FROM (
      SELECT * FROM (SELECT jsonb_build_object('type', 'audit', 'message', actor.name || ' ' || al.action || ' em ' || COALESCE(target.name, '?'), 'details', al.changes, 'timestamp', al.created_at) as activity, al.created_at as ts FROM public.admin_audit_log al LEFT JOIN public.members actor ON actor.id = al.actor_id LEFT JOIN public.members target ON target.id = al.target_id WHERE al.created_at > now() - interval '7 days' ORDER BY al.created_at DESC LIMIT 10) a1
      UNION ALL SELECT * FROM (SELECT jsonb_build_object('type', 'campaign', 'message', 'Campanha "' || ct.name || '" enviada', 'timestamp', cs.created_at), cs.created_at FROM public.campaign_sends cs JOIN public.campaign_templates ct ON ct.id = cs.template_id WHERE cs.created_at > now() - interval '7 days' ORDER BY cs.created_at DESC LIMIT 5) a2
      UNION ALL SELECT * FROM (SELECT jsonb_build_object('type', 'publication', 'message', m.name || ' submeteu "' || ps.title || '"', 'timestamp', ps.submission_date), ps.submission_date FROM public.publication_submissions ps JOIN public.publication_submission_authors psa ON psa.submission_id = ps.id JOIN public.members m ON m.id = psa.member_id WHERE ps.submission_date > now() - interval '30 days' ORDER BY ps.submission_date DESC LIMIT 5) a3
    ) r LIMIT 15)
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

-- 3d — get_tribe_gamification
CREATE OR REPLACE FUNCTION public.get_tribe_gamification(p_tribe_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_summary jsonb;
  v_members jsonb;
  v_ranking jsonb;
  v_trend jsonb;
  v_total_xp bigint;
  v_member_count int;
  v_cycle_start date;
  v_initiative_id uuid;
  v_member_ids uuid[];
  v_stats jsonb := '{}'::jsonb;
  v_attendance jsonb := '{}'::jsonb;
  v_trail_total int;
  v_trail_completion numeric;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  IF NOT (
    v_caller.tribe_id = p_tribe_id
    OR public.can_by_member(v_caller.id, 'view_internal_analytics')
  ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM cycles WHERE is_current = true LIMIT 1;

  -- M4: canonical member cohort (participants-only roster), single source of truth.
  v_initiative_id := public.resolve_initiative_id(p_tribe_id);
  v_member_count := public.get_initiative_roster_count(v_initiative_id);

  -- #425: roster member ids for the batched coaching-stats call.
  SELECT array_agg(member_id) INTO v_member_ids
  FROM v_initiative_roster WHERE initiative_id = v_initiative_id;

  -- #425: streak / active-cycle coaching signals from the canonical RPC (SSOT).
  -- get_member_gamification_stats RAISEs if the caller is not an active member;
  -- a non-active viewer should still get the table, just with zeroed streaks.
  IF v_member_ids IS NOT NULL THEN
    BEGIN
      SELECT COALESCE(jsonb_object_agg(s.member_id::text, jsonb_build_object(
               'current_streak', s.current_streak_count,
               'longest_streak', s.longest_streak_count,
               'active_cycles', s.active_cycles_count
             )), '{}'::jsonb)
      INTO v_stats
      FROM public.get_member_gamification_stats(v_member_ids) s;
    EXCEPTION WHEN insufficient_privilege OR invalid_parameter_value THEN
      -- non-active viewer (insufficient_privilege) or >200-member cap
      -- (invalid_parameter_value): degrade gracefully to zeroed streaks. Any
      -- OTHER error propagates (schema drift / programming bugs must surface).
      v_stats := '{}'::jsonb;
    END;

    -- #576: batch attendance_rate for the whole roster in ONE grouped scan
    -- (was public.get_attendance_rate(member, cycle) per member = N+1). Mirrors
    -- get_attendance_rate's numerator/denominator/event-window; v_cycle_start is
    -- already resolved above (so the fn's COALESCE-to-current-cycle fallback is
    -- unneeded here). Per-member values (incl. the NULL case) are identical.
    SELECT COALESCE(jsonb_object_agg(ar.member_id::text, ar.rate), '{}'::jsonb)
    INTO v_attendance
    FROM (
      SELECT a.member_id,
        ROUND(
          count(*) FILTER (WHERE a.present = true)::numeric
          / NULLIF(count(*) FILTER (WHERE a.excused IS NOT TRUE), 0), 2) AS rate
      FROM attendance a
      JOIN events e ON e.id = a.event_id
      WHERE a.member_id = ANY(v_member_ids)
        AND e.date >= v_cycle_start
        AND e.date <= CURRENT_DATE
        AND e.status IS DISTINCT FROM 'cancelled'
        AND e.type IN ('geral', 'kickoff', 'tribo', 'lideranca')
      GROUP BY a.member_id
    ) ar;
  END IF;

  -- #425: dynamic trail denominator (no hardcoded 6).
  v_trail_total := (SELECT count(*) FROM courses WHERE is_trail = true);

  WITH points_per_member AS (
    SELECT
      gp.member_id,
      SUM(gp.points)::int AS total_points,
      COALESCE(SUM(gp.points) FILTER (WHERE COALESCE(gp.occurred_at, gp.created_at) >= v_cycle_start), 0)::int AS cycle_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'presenca'), 0)::int AS attendance_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'certificacoes' AND gr.slug LIKE 'cert_%'), 0)::int AS cert_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.slug = 'badge'), 0)::int AS badge_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'trilha'), 0)::int AS learning_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'producao'), 0)::int AS producao_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'curadoria'), 0)::int AS curadoria_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'champions'), 0)::int AS champions_points,
      MAX(gp.created_at) AS last_activity_ts
    FROM gamification_points gp
    LEFT JOIN gamification_rules gr
      ON gr.organization_id = gp.organization_id
     AND gr.slug = gp.category
    WHERE gp.member_id = ANY(v_member_ids)
    GROUP BY gp.member_id
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', m.id, 'name', m.name,
    'total_points', COALESCE(p.total_points, 0),
    'cycle_points', COALESCE(p.cycle_points, 0),
    'attendance_points', COALESCE(p.attendance_points, 0),
    'cert_points', COALESCE(p.cert_points, 0),
    'badge_points', COALESCE(p.badge_points, 0),
    'learning_points', COALESCE(p.learning_points, 0),
    'producao_points', COALESCE(p.producao_points, 0),
    'curadoria_points', COALESCE(p.curadoria_points, 0),
    'champions_points', COALESCE(p.champions_points, 0),
    'credly_badge_count', COALESCE(jsonb_array_length(m.credly_badges), 0),
    'has_cpmai', COALESCE(m.cpmai_certified, false),
    -- #425: trail_progress = completed trail COURSES (course_progress, canonical).
    'trail_progress', (
      SELECT count(*) FROM course_progress cp
      WHERE cp.member_id = m.id AND cp.status = 'completed'
        AND cp.course_id IN (SELECT id FROM courses WHERE is_trail = true)
    ),
    -- #576: attendance_rate served from the pre-batched map (value identical to
    -- the prior per-member public.get_attendance_rate(m.id, v_cycle_start) call).
    'attendance_rate', (v_attendance -> m.id::text),
    'current_streak', COALESCE((v_stats -> m.id::text ->> 'current_streak')::int, 0),
    'longest_streak', COALESCE((v_stats -> m.id::text ->> 'longest_streak')::int, 0),
    'active_cycles', COALESCE((v_stats -> m.id::text ->> 'active_cycles')::int, 0),
    -- #576: last_activity folded into points_per_member's MAX(created_at) — same
    -- value as the prior per-member correlated MAX subquery. last VOLUNTARY
    -- gamification activity (NOT members.last_seen_at — login presence to peers
    -- would be an LGPD Art. 9 minimisation issue).
    'last_activity', to_char(p.last_activity_ts, 'YYYY-MM-DD'),
    'trail_courses', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'course_id', c.id, 'code', c.code, 'name', c.name, 'tier', c.tier,
        'status', COALESCE(cp.status, 'missing')
      ) ORDER BY c.sort_order), '[]'::jsonb)
      FROM courses c
      LEFT JOIN course_progress cp ON cp.course_id = c.id AND cp.member_id = m.id
      WHERE c.is_trail = true
    )
  ) ORDER BY COALESCE(p.total_points, 0) DESC), '[]'::jsonb)
  INTO v_members
  FROM members m
  LEFT JOIN points_per_member p ON p.member_id = m.id
  WHERE m.id = ANY(v_member_ids);

  SELECT COALESCE(SUM((elem->>'total_points')::bigint), 0)
  INTO v_total_xp
  FROM jsonb_array_elements(v_members) elem;

  -- #425: real trail completion = AVG over roster of (completed/total), fraction 0..1.
  SELECT ROUND(AVG(member_pct), 2) INTO v_trail_completion
  FROM (
    SELECT (
      SELECT count(*) FROM course_progress cp
      WHERE cp.member_id = rm.member_id AND cp.status = 'completed'
        AND cp.course_id IN (SELECT id FROM courses WHERE is_trail = true)
    )::numeric / NULLIF(v_trail_total, 0) AS member_pct
    FROM (SELECT DISTINCT u AS member_id FROM unnest(v_member_ids) u) rm
  ) sub;

  v_summary := jsonb_build_object(
    'total_xp', v_total_xp,
    'avg_xp', CASE WHEN v_member_count > 0 THEN ROUND(v_total_xp::numeric / v_member_count) ELSE 0 END,
    'tribe_rank', (
      WITH tribe_totals AS (
        SELECT t.id AS tid, COALESCE(SUM(gp.points), 0) AS txp
        FROM tribes t
        LEFT JOIN (SELECT DISTINCT legacy_tribe_id, member_id FROM v_initiative_roster) m2 ON m2.legacy_tribe_id = t.id
        LEFT JOIN gamification_points gp ON gp.member_id = m2.member_id
        WHERE t.is_active = true
        GROUP BY t.id
      ),
      ranked AS (
        SELECT tid, RANK() OVER (ORDER BY txp DESC) AS rk FROM tribe_totals
      )
      SELECT rk FROM ranked WHERE tid = p_tribe_id
    ),
    'cert_coverage', CASE WHEN v_member_count > 0 THEN ROUND(
      (SELECT count(*) FROM members
        WHERE id = ANY(v_member_ids)
        AND (cpmai_certified = true OR jsonb_array_length(COALESCE(credly_badges, '[]'::jsonb)) > 0)
      )::numeric / v_member_count, 2
    ) ELSE 0 END,
    'trail_completion', COALESCE(v_trail_completion, 0)
  );

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'tribe_id', sub.tid,
      'tribe_name', sub.tname,
      'tribe_name_i18n', sub.tname_i18n,
      'total_xp', sub.txp
    )
    ORDER BY sub.txp DESC
  ), '[]'::jsonb)
  INTO v_ranking
  FROM (
    SELECT t.id AS tid, t.name AS tname, t.name_i18n AS tname_i18n, COALESCE(SUM(gp.points), 0) AS txp
    FROM tribes t
    LEFT JOIN (SELECT DISTINCT legacy_tribe_id, member_id FROM v_initiative_roster) m4 ON m4.legacy_tribe_id = t.id
    LEFT JOIN gamification_points gp ON gp.member_id = m4.member_id
    WHERE t.is_active = true
    GROUP BY t.id, t.name, t.name_i18n
  ) sub;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('month', to_char(month, 'YYYY-MM'), 'xp', month_xp) ORDER BY month), '[]'::jsonb)
  INTO v_trend
  FROM (
    SELECT date_trunc('month', gp.created_at) AS month, SUM(gp.points) AS month_xp
    FROM gamification_points gp
    WHERE gp.member_id = ANY(v_member_ids)
      AND COALESCE(gp.occurred_at, gp.created_at) >= v_cycle_start
    GROUP BY date_trunc('month', gp.created_at)
  ) sub;

  RETURN jsonb_build_object('summary', v_summary, 'members', v_members, 'tribe_ranking', v_ranking, 'monthly_trend', v_trend);
END;
$function$;

-- 3d — get_initiative_gamification
CREATE OR REPLACE FUNCTION public.get_initiative_gamification(p_initiative_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_tribe_id int;
  v_result jsonb;
  v_cycle_start date;
  v_member_ids uuid[];
  v_stats jsonb := '{}'::jsonb;
  v_attendance jsonb := '{}'::jsonb;
  v_trail_total int;
BEGIN
  -- #785 PR-3: confidential gate (covers both the tribe-delegated and standalone paths)
  IF NOT public.rls_can_see_initiative(p_initiative_id) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- #576 (item 5): resolve routing FIRST so tribe-backed initiatives delegate to
  -- get_tribe_gamification (which runs its own auth gate) without a redundant
  -- members-by-auth_id fetch here. The standalone path authenticates below.
  -- Output is identical: a non-member still gets 'Unauthorized' either way.
  v_tribe_id := public.resolve_tribe_id(p_initiative_id);

  IF v_tribe_id IS NOT NULL THEN
    RETURN public.get_tribe_gamification(v_tribe_id);
  END IF;

  -- standalone (non-tribe) initiative path: authenticate the caller.
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;

  -- #600 (#419 M4 residual, sibling of #465/#468): initiative-scoped authority gate —
  -- mirrors get_tribe_gamification's gate (tribe member OR view_internal_analytics).
  -- Without it ANY authenticated member could read ANY standalone initiative's roster
  -- (names + per-pillar XP). Membership = any ACTIVE engagement on the initiative
  -- (observers included — they are initiative insiders; the participants-only filter
  -- applies to who is LISTED, not who may view). Fail-closed default per ADR-0007.
  IF NOT (
    EXISTS (
      SELECT 1 FROM engagements e
      WHERE e.initiative_id = p_initiative_id
        AND e.status = 'active'
        AND e.person_id = v_caller.person_id
    )
    OR public.can_by_member(v_caller.id, 'view_internal_analytics')
  ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT cycle_start INTO v_cycle_start FROM cycles WHERE is_current = true LIMIT 1;

  SELECT array_agg(DISTINCT m.id) INTO v_member_ids
  FROM v_initiative_roster vir JOIN members m ON m.id = vir.member_id
  WHERE vir.initiative_id = p_initiative_id;

  -- #425: streak / active-cycle coaching signals (SSOT), guarded for non-active viewers.
  IF v_member_ids IS NOT NULL THEN
    BEGIN
      SELECT COALESCE(jsonb_object_agg(s.member_id::text, jsonb_build_object(
               'current_streak', s.current_streak_count,
               'longest_streak', s.longest_streak_count,
               'active_cycles', s.active_cycles_count
             )), '{}'::jsonb)
      INTO v_stats
      FROM public.get_member_gamification_stats(v_member_ids) s;
    EXCEPTION WHEN insufficient_privilege OR invalid_parameter_value THEN
      -- non-active viewer (insufficient_privilege) or >200-member cap
      -- (invalid_parameter_value): degrade gracefully to zeroed streaks. Any
      -- OTHER error propagates (schema drift / programming bugs must surface).
      v_stats := '{}'::jsonb;
    END;

    -- #576: batch attendance_rate (was get_attendance_rate per member = N+1).
    SELECT COALESCE(jsonb_object_agg(ar.member_id::text, ar.rate), '{}'::jsonb)
    INTO v_attendance
    FROM (
      SELECT a.member_id,
        ROUND(
          count(*) FILTER (WHERE a.present = true)::numeric
          / NULLIF(count(*) FILTER (WHERE a.excused IS NOT TRUE), 0), 2) AS rate
      FROM attendance a
      JOIN events e ON e.id = a.event_id
      WHERE a.member_id = ANY(v_member_ids)
        AND e.date >= v_cycle_start
        AND e.date <= CURRENT_DATE
        AND e.status IS DISTINCT FROM 'cancelled'
        AND e.type IN ('geral', 'kickoff', 'tribo', 'lideranca')
      GROUP BY a.member_id
    ) ar;
  END IF;

  v_trail_total := (SELECT count(*) FROM courses WHERE is_trail = true);

  WITH init_members AS MATERIALIZED (
    SELECT DISTINCT m.id, m.name, m.cpmai_certified, m.credly_badges
    FROM v_initiative_roster vir
    JOIN members m ON m.id = vir.member_id
    WHERE vir.initiative_id = p_initiative_id
  ),
  points_per_member AS (
    SELECT
      gp.member_id,
      SUM(gp.points)::int AS total_points,
      COALESCE(SUM(gp.points) FILTER (WHERE COALESCE(gp.occurred_at, gp.created_at) >= v_cycle_start), 0)::int AS cycle_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'presenca'), 0)::int AS attendance_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'certificacoes' AND gr.slug LIKE 'cert_%'), 0)::int AS cert_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.slug = 'badge'), 0)::int AS badge_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'trilha'), 0)::int AS learning_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'producao'), 0)::int AS producao_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'curadoria'), 0)::int AS curadoria_points,
      COALESCE(SUM(gp.points) FILTER (WHERE gr.pillar = 'champions'), 0)::int AS champions_points,
      MAX(gp.created_at) AS last_activity_ts
    FROM gamification_points gp
    JOIN init_members im ON im.id = gp.member_id
    LEFT JOIN gamification_rules gr
      ON gr.organization_id = gp.organization_id
     AND gr.slug = gp.category
    GROUP BY gp.member_id
  ),
  member_data AS MATERIALIZED (
    SELECT im.id, im.name,
           COALESCE(p.total_points, 0) AS total_points,
           COALESCE(p.cycle_points, 0) AS cycle_points,
           COALESCE(p.attendance_points, 0) AS attendance_points,
           COALESCE(p.cert_points, 0) AS cert_points,
           COALESCE(p.badge_points, 0) AS badge_points,
           COALESCE(p.learning_points, 0) AS learning_points,
           COALESCE(p.producao_points, 0) AS producao_points,
           COALESCE(p.curadoria_points, 0) AS curadoria_points,
           COALESCE(p.champions_points, 0) AS champions_points,
           COALESCE(jsonb_array_length(im.credly_badges), 0) AS credly_badge_count,
           COALESCE(im.cpmai_certified, false) AS has_cpmai,
           p.last_activity_ts AS last_activity_ts,
           (SELECT count(*) FROM course_progress cp
             WHERE cp.member_id = im.id AND cp.status = 'completed'
               AND cp.course_id IN (SELECT id FROM courses WHERE is_trail = true)) AS trail_progress
    FROM init_members im
    LEFT JOIN points_per_member p ON p.member_id = im.id
  ),
  v_members AS (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', md.id, 'name', md.name,
      'total_points', md.total_points, 'cycle_points', md.cycle_points,
      'attendance_points', md.attendance_points, 'cert_points', md.cert_points,
      'badge_points', md.badge_points, 'learning_points', md.learning_points,
      'producao_points', md.producao_points, 'curadoria_points', md.curadoria_points,
      'champions_points', md.champions_points,
      'credly_badge_count', md.credly_badge_count,
      'has_cpmai', md.has_cpmai,
      'trail_progress', md.trail_progress,
      -- #576: attendance_rate from the pre-batched map (value identical to the
      -- prior per-member public.get_attendance_rate(md.id, v_cycle_start) call).
      'attendance_rate', (v_attendance -> md.id::text),
      'current_streak', COALESCE((v_stats -> md.id::text ->> 'current_streak')::int, 0),
      'longest_streak', COALESCE((v_stats -> md.id::text ->> 'longest_streak')::int, 0),
      'active_cycles', COALESCE((v_stats -> md.id::text ->> 'active_cycles')::int, 0),
      -- #576: last_activity folded into points_per_member's MAX(created_at).
      'last_activity', to_char(md.last_activity_ts, 'YYYY-MM-DD'),
      'trail_courses', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'course_id', c.id, 'code', c.code, 'name', c.name, 'tier', c.tier,
          'status', COALESCE(cp.status, 'missing')
        ) ORDER BY c.sort_order), '[]'::jsonb)
        FROM courses c
        LEFT JOIN course_progress cp ON cp.course_id = c.id AND cp.member_id = md.id
        WHERE c.is_trail = true
      )
    ) ORDER BY md.total_points DESC), '[]'::jsonb) AS members_json
    FROM member_data md
  ),
  v_trend AS (
    SELECT COALESCE(jsonb_agg(jsonb_build_object('month', to_char(month, 'YYYY-MM'), 'xp', month_xp) ORDER BY month), '[]'::jsonb) AS trend_json
    FROM (
      SELECT date_trunc('month', gp.created_at) AS month, SUM(gp.points) AS month_xp
      FROM gamification_points gp
      JOIN init_members im ON im.id = gp.member_id
      WHERE COALESCE(gp.occurred_at, gp.created_at) >= v_cycle_start
      GROUP BY date_trunc('month', gp.created_at)
    ) sub
  ),
  v_trail AS (
    SELECT ROUND(AVG(member_pct), 2) AS pct FROM (
      SELECT (
        SELECT count(*) FROM course_progress cp
        WHERE cp.member_id = im.id AND cp.status = 'completed'
          AND cp.course_id IN (SELECT id FROM courses WHERE is_trail = true)
      )::numeric / NULLIF(v_trail_total, 0) AS member_pct
      FROM init_members im
    ) s
  )
  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total_xp', COALESCE((SELECT SUM(total_points) FROM member_data), 0),
      'avg_xp', CASE WHEN (SELECT count(*) FROM member_data) > 0
                THEN ROUND((SELECT SUM(total_points) FROM member_data)::numeric / (SELECT count(*) FROM member_data))
                ELSE 0 END,
      'tribe_rank', NULL,
      'cert_coverage', CASE WHEN (SELECT count(*) FROM member_data) > 0
                       THEN ROUND((SELECT count(*) FROM member_data WHERE has_cpmai OR credly_badge_count > 0)::numeric / (SELECT count(*) FROM member_data), 2)
                       ELSE 0 END,
      'trail_completion', COALESCE((SELECT pct FROM v_trail), 0)
    ),
    'members', (SELECT members_json FROM v_members),
    'tribe_ranking', '[]'::jsonb,
    'monthly_trend', (SELECT trend_json FROM v_trend)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- 3d — get_gp_cohort_health
CREATE OR REPLACE FUNCTION public.get_gp_cohort_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller uuid;
  v_is_service boolean;
  v_cycle record;
  v_kickoff uuid;
  v_result jsonb;
BEGIN
  v_is_service := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  ) = 'service_role';
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT coalesce(v_is_service, false)
     AND (v_caller IS NULL
          OR NOT (public.can_by_member(v_caller, 'manage_member')
                  OR public.can_by_member(v_caller, 'view_internal_analytics'))) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_member or view_internal_analytics');
  END IF;

  SELECT cycle_code, cycle_label, cycle_start INTO v_cycle
  FROM public.cycles WHERE is_current = true ORDER BY cycle_start DESC LIMIT 1;

  -- kickoff da coorte corrente: derivado (NAO hardcoded) — type='kickoff' OU titulo ILIKE '%kick%',
  -- primeiro evento nao-cancelado dentro da janela do ciclo. Em C4 o kickoff foi registrado como
  -- type='geral' com "Kick-off" no titulo, dai o OR por titulo.
  SELECT id INTO v_kickoff
  FROM public.events
  WHERE (type = 'kickoff' OR title ILIKE '%kick%')
    AND date >= v_cycle.cycle_start
    AND status IS DISTINCT FROM 'cancelled'
  ORDER BY date ASC LIMIT 1;

  WITH cohort AS (
    SELECT m.id, m.name, m.chapter,
      EXISTS (SELECT 1 FROM public.v_initiative_roster r
              JOIN public.initiatives i2 ON i2.id = r.initiative_id
              WHERE r.member_id = m.id AND i2.kind = 'research_tribe') AS has_tribe,
      -- #1291: curador / membro de comite (engagement ativo em iniciativa kind='committee') —
      -- tribelessness legitima, nao conta como "sem tribo em risco".
      EXISTS (SELECT 1 FROM public.engagements e
              JOIN public.initiatives ic ON ic.id = e.initiative_id
              WHERE e.person_id = m.person_id AND e.status = 'active' AND ic.kind = 'committee') AS is_committee,
      EXISTS (SELECT 1 FROM public.attendance a
              WHERE a.member_id = m.id AND a.event_id = v_kickoff AND a.present = true) AS at_kickoff,
      EXISTS (SELECT 1 FROM public.gamification_points gp
              WHERE gp.member_id = m.id AND COALESCE(gp.occurred_at, gp.created_at) >= v_cycle.cycle_start) AS has_activity
    FROM public.members m
    WHERE m.member_status = 'active'
      AND m.operational_role IN ('researcher', 'tribe_leader')
  ),
  cohort_p AS (
    SELECT c.*, (c.has_tribe OR c.is_committee) AS placed FROM cohort c
  )
  SELECT jsonb_build_object(
    'cycle', jsonb_build_object('code', v_cycle.cycle_code, 'label', v_cycle.cycle_label),
    'kickoff_event_id', v_kickoff,
    'cohort_summary', jsonb_build_object(
      'total',            (SELECT count(*) FROM cohort_p),
      'with_tribe',       (SELECT count(*) FROM cohort_p WHERE has_tribe),
      'committee_members',(SELECT count(*) FROM cohort_p WHERE is_committee),
      'without_tribe',    (SELECT count(*) FROM cohort_p WHERE NOT placed),
      'at_kickoff',       (SELECT count(*) FROM cohort_p WHERE at_kickoff),
      'no_kickoff',       (SELECT count(*) FROM cohort_p WHERE NOT at_kickoff),
      'no_activity',      (SELECT count(*) FROM cohort_p WHERE NOT has_activity)
    ),
    'at_risk_members', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'member_id', c.id, 'name', c.name, 'chapter', c.chapter,
        'is_committee', c.is_committee,
        'no_tribe', NOT c.placed,
        'no_kickoff', NOT c.at_kickoff,
        'no_activity', NOT c.has_activity,
        'risk_count', (CASE WHEN NOT c.placed THEN 1 ELSE 0 END
                     + CASE WHEN NOT c.at_kickoff THEN 1 ELSE 0 END
                     + CASE WHEN NOT c.has_activity THEN 1 ELSE 0 END)
      ) ORDER BY (CASE WHEN NOT c.placed THEN 1 ELSE 0 END
                + CASE WHEN NOT c.at_kickoff THEN 1 ELSE 0 END
                + CASE WHEN NOT c.has_activity THEN 1 ELSE 0 END) DESC, c.name), '[]'::jsonb)
      FROM cohort_p c
      WHERE NOT c.placed OR NOT c.at_kickoff OR NOT c.has_activity
    ),
    'pending_leader_approvals', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'invitation_id', ii.id,
        'requester_member_id', ii.invitee_member_id,
        'requester_name', rm.name,
        'tribe', init.title,
        'legacy_tribe_id', init.legacy_tribe_id,
        'requested_at', ii.created_at,
        'expires_at', ii.expires_at,
        'days_waiting', EXTRACT(day FROM now() - ii.created_at)::int
      ) ORDER BY ii.created_at), '[]'::jsonb)
      FROM public.initiative_invitations ii
      JOIN public.initiatives init ON init.id = ii.initiative_id
      JOIN public.members rm ON rm.id = ii.invitee_member_id
      WHERE ii.status = 'pending' AND init.kind = 'research_tribe'
        AND ii.invitee_member_id = ii.inviter_member_id
        AND ii.expires_at > now()
    ),
    'generated_at', now()
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- 3d — get_event_champion_suggestions
CREATE OR REPLACE FUNCTION public.get_event_champion_suggestions(p_event_id uuid, p_force_derive boolean DEFAULT false)
 RETURNS TABLE(member_id uuid, member_name text, designation_summary text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_org uuid;
  v_event_org uuid;
  v_suggestions uuid[];
  v_cycle_start date;
BEGIN
  SELECT id, organization_id INTO v_caller_id, v_caller_org
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event')
     AND NOT public.can_by_member(v_caller_id, 'award_champion') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event or award_champion';
  END IF;

  SELECT e.suggested_champion_ids, e.organization_id INTO v_suggestions, v_event_org
  FROM public.events e WHERE e.id = p_event_id;

  IF v_event_org IS NULL THEN
    RAISE EXCEPTION 'event_not_found';
  END IF;
  IF v_event_org != v_caller_org THEN
    RAISE EXCEPTION 'event_not_in_caller_org';
  END IF;

  -- Manual override: a curator pre-set the champions-of-the-night → honor it (unless force-derive).
  IF NOT p_force_derive AND v_suggestions IS NOT NULL AND cardinality(v_suggestions) > 0 THEN
    RETURN QUERY
    SELECT
      m.id, m.name,
      CASE WHEN cardinality(m.designations) > 0
        THEN array_to_string(m.designations, ', ')
        ELSE COALESCE(m.operational_role, '—')
      END
    FROM public.members m
    WHERE m.id = ANY(v_suggestions)
      AND m.organization_id = v_caller_org
    ORDER BY m.name;
    RETURN;
  END IF;

  -- Derived: members PRESENT at the event, ranked by current-cycle contribution. Top 12, caller excluded.
  SELECT cycle_start INTO v_cycle_start FROM public.cycles WHERE is_current = true LIMIT 1;

  RETURN QUERY
  SELECT
    m.id, m.name,
    CASE WHEN cardinality(m.designations) > 0
      THEN array_to_string(m.designations, ', ')
      ELSE COALESCE(m.operational_role, '—')
    END
  FROM public.attendance a
  JOIN public.members m ON m.id = a.member_id
  LEFT JOIN LATERAL (
    SELECT COALESCE(SUM(gp.points), 0) AS cyc_pts
    FROM public.gamification_points gp
    WHERE gp.member_id = m.id
      AND COALESCE(gp.occurred_at, gp.created_at) >= COALESCE(v_cycle_start, DATE '2026-01-01')
  ) sig ON true
  WHERE a.event_id = p_event_id
    AND a.present = true
    AND m.organization_id = v_caller_org
    AND m.id <> v_caller_id
  ORDER BY sig.cyc_pts DESC, m.name
  LIMIT 12;
END;
$function$;

NOTIFY pgrst, 'reload schema';
