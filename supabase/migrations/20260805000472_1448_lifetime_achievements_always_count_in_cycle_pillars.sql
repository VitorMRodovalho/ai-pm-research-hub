-- #1448: conquistas vitalícias (certificações + badges Credly) somem na visão "Ciclo Atual".
--
-- Causa: get_member_xp_pillars janela TODOS os gamification_points por created_at >= cycle_start.
-- Certs/badges recebem created_at da data de importação (ex.: uma CPMAI de 2025), então caem
-- fora do ciclo corrente e o card de "Certificações" mostra 0 — o membro acha que "não pontua".
--
-- Decisão de produto (sessão dedicada 2026-07-21, híbrido surface-aware):
--   - PERFIL/pilares: o pilar `certificacoes` (badge + cert_*) SEMPRE conta com valor vitalício,
--     mesmo no escopo 'cycle'. Só XP de fluxo (presença/champions/curadoria/trilha/produção) é
--     janelado por ciclo. Marcamos o pilar com is_lifetime=true para a UI rotular "vitalício".
--   - RANKING: usa get_gamification_leaderboard (RPC distinta, cycle-scoped) — INTOCADO por design;
--     estoque de certs de anos anteriores não deve inflar o ranking competitivo do ciclo.
--
-- Nenhuma mudança de assinatura; CREATE OR REPLACE preserva grants existentes.

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
        -- mesmo na visão de ciclo. Só XP de fluxo é janelado por created_at.
        OR EXISTS (
          SELECT 1 FROM gamification_rules r_win
          WHERE r_win.organization_id = gp.organization_id
            AND r_win.slug = gp.category
            AND r_win.pillar = 'certificacoes'
        )
        OR (gp.created_at >= v_cycle_start
            AND (v_cycle_end IS NULL OR gp.created_at < (v_cycle_end + interval '1 day')))
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
        END
      ) FROM pillar_agg
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;
