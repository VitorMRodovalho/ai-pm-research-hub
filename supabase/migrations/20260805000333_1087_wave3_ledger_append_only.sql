-- #1087 Onda 3 (G5 parte 2) — gamification ledger append-only.
--
-- Antes desta migration, TRÊS funções faziam HARD-DELETE em gamification_points
-- (revoke_champion, revoke_agenda_block_xp, remove_event_showcase), destruindo o
-- trilho de auditoria. A partir daqui o ledger é APPEND-ONLY para lógica de negócio:
-- revogações inserem ESTORNO (pontos negativos espelhando o net por member/org/categoria,
-- mesmo ref_id, granted_by = quem revogou). Rollups são SUM cru (net absorve o estorno);
-- get_my_points_statement já rotula is_reversal = points < 0 (Onda 2 renderiza).
--
-- Guard HAVING SUM(points) <> 0 torna o estorno idempotente e net-zero-safe
-- (segunda chamada não insere nada; drift parcial é zerado exatamente).
--
-- Bug latente corrigido em remove_event_showcase: o DELETE antigo casava só
-- category = 'showcase' (bare, 12 linhas legadas de 2026-04); a escrita atual usa
-- slugs granulares showcase_<type> (p165 config-driven) → remover um showcase
-- deixava o XP órfão. O estorno agora casa category LIKE 'showcase%' via ref_id.
--
-- Exceção deliberada que NÃO é lógica de negócio: apagamento LGPD (erasure de membro)
-- continua permitido — a invariante é "nenhuma RPC de negócio deleta linhas do ledger"
-- (contract test 1087-wave3-ledger-append-only), não um trigger BEFORE DELETE.
--
-- Também nesta migration:
--   * get_member_xp_pillars.earned_count deixa de contar linhas de estorno (points < 0)
--     como "earned" — pts continua SUM cru (net).
--   * higiene de grants: remove_event_showcase tinha EXECUTE para anon/PUBLIC
--     (inócuo — a função gateia via auth.uid — mas fora do padrão; revogado).

-- ── 1. revoke_champion: estorno em vez de DELETE ─────────────────────────────────

CREATE OR REPLACE FUNCTION public.revoke_champion(p_champion_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller members%ROWTYPE;
  v_champ champions_awarded%ROWTYPE;
  v_is_within_window boolean;
  v_is_platform_admin boolean;
  v_reversal_rows int;
  v_reversal_points int;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;

  IF length(trim(coalesce(p_reason,''))) < 10 THEN
    RETURN jsonb_build_object('error','reason_required','detail','provide >=10 char reason');
  END IF;

  SELECT * INTO v_champ FROM champions_awarded WHERE id = p_champion_id;
  IF v_champ.id IS NULL THEN
    RETURN jsonb_build_object('error','champion_not_found');
  END IF;
  IF v_champ.status = 'revoked' THEN
    RETURN jsonb_build_object('error','already_revoked');
  END IF;

  v_is_platform_admin := public.can_by_member(v_caller.id, 'manage_platform'::text);
  v_is_within_window := v_champ.created_at >= now() - interval '7 days';

  IF NOT (v_is_platform_admin OR (v_champ.awarded_by = v_caller.id AND v_is_within_window)) THEN
    RETURN jsonb_build_object('error','not_authorized','detail',
      CASE
        WHEN v_champ.awarded_by = v_caller.id THEN '7-day window expired; only manage_platform can revoke'
        ELSE 'only original awarder (within 7 days) or platform admin can revoke'
      END);
  END IF;

  UPDATE champions_awarded SET
    status = 'revoked',
    revoked_at = now(),
    revoked_by = v_caller.id,
    revoked_reason = p_reason,
    updated_at = now()
  WHERE id = p_champion_id;

  -- #1087 Onda 3: ledger append-only — estorno (pontos negativos) em vez de DELETE.
  -- Net por member/org/categoria absorve qualquer drift; HAVING <> 0 = idempotente.
  WITH net AS (
    SELECT gp.member_id, gp.organization_id, gp.category, SUM(gp.points) AS pts
    FROM gamification_points gp
    WHERE gp.ref_id = p_champion_id
      AND gp.category LIKE 'champion_%'
    GROUP BY gp.member_id, gp.organization_id, gp.category
    HAVING SUM(gp.points) <> 0
  ), reversal AS (
    INSERT INTO gamification_points (member_id, organization_id, points, category, reason, ref_id, granted_by)
    SELECT n.member_id, n.organization_id, -n.pts, n.category,
           'Estorno (champion revogado): ' || p_reason, p_champion_id, v_caller.id
    FROM net n
    RETURNING points
  )
  SELECT count(*), COALESCE(SUM(points), 0)::int
    INTO v_reversal_rows, v_reversal_points
  FROM reversal;

  RETURN jsonb_build_object(
    'success', true,
    'champion_id', p_champion_id,
    'points_removed', v_reversal_rows,
    'reversal_points', v_reversal_points,
    'revoked_by', v_caller.id,
    'revoked_within_window', v_is_within_window,
    'by_platform_admin', v_is_platform_admin AND v_champ.awarded_by != v_caller.id
  );
END;
$function$;

-- ── 2. revoke_agenda_block_xp: estorno em vez de DELETE ──────────────────────────

CREATE OR REPLACE FUNCTION public.revoke_agenda_block_xp(p_block_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller  uuid;
  v_block   record;
  v_reversal_rows int := 0;
  v_reversal_points int := 0;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT public.can_by_member(v_caller, 'manage_event') THEN
    RETURN jsonb_build_object('error', 'access_denied', 'required', 'manage_event');
  END IF;

  SELECT * INTO v_block FROM public.event_agenda_blocks WHERE id = p_block_id FOR UPDATE;
  IF v_block.id IS NULL THEN RETURN jsonb_build_object('error', 'block_not_found'); END IF;
  -- A cancelled block has its own terminal outcome; do not overwrite it with no_show.
  IF v_block.status = 'cancelled' THEN
    RETURN jsonb_build_object('error', 'cannot_revoke_cancelled', 'block_id', p_block_id);
  END IF;

  -- #1087 Onda 3: ledger append-only — estorno (pontos negativos) em vez de DELETE.
  WITH net AS (
    SELECT gp.member_id, gp.organization_id, gp.category, SUM(gp.points) AS pts
    FROM public.gamification_points gp
    WHERE gp.ref_id = p_block_id
      AND gp.category = 'agenda_block_protagonismo'
      AND gp.member_id = v_block.owner_member_id
    GROUP BY gp.member_id, gp.organization_id, gp.category
    HAVING SUM(gp.points) <> 0
  ), reversal AS (
    INSERT INTO public.gamification_points (member_id, organization_id, points, category, reason, ref_id, granted_by)
    SELECT n.member_id, n.organization_id, -n.pts, n.category,
           'Estorno (protagonismo revogado): ' || COALESCE(p_reason, 'no_show'), p_block_id, v_caller
    FROM net n
    RETURNING points
  )
  SELECT count(*), COALESCE(SUM(points), 0)::int
    INTO v_reversal_rows, v_reversal_points
  FROM reversal;

  UPDATE public.event_agenda_blocks
     SET status = 'no_show', confirmed_at = NULL,
         cancelled_by = v_caller, cancelled_reason = COALESCE(p_reason, cancelled_reason)
   WHERE id = p_block_id;

  RETURN jsonb_build_object('success', true, 'block_id', p_block_id, 'status', 'no_show',
                            'xp_revoked', v_reversal_rows,
                            'reversal_points', v_reversal_points);
END;
$function$;

-- ── 3. remove_event_showcase: estorno (LIKE 'showcase%') em vez de DELETE ────────

CREATE OR REPLACE FUNCTION public.remove_event_showcase(p_showcase_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_reversal_rows int := 0;
  v_reversal_points int := 0;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_event'::text) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM event_showcases WHERE id = p_showcase_id) THEN
    RETURN jsonb_build_object('error', 'Showcase not found');
  END IF;

  -- #1087 Onda 3: ledger append-only — estorno em vez de DELETE. O matcher antigo
  -- (category = 'showcase', bare) só existia nas linhas legadas de 2026-04; a escrita
  -- atual usa showcase_<type> (p165) e o DELETE deixava XP órfão. LIKE 'showcase%'
  -- via ref_id cobre legado + granular.
  WITH net AS (
    SELECT gp.member_id, gp.organization_id, gp.category, SUM(gp.points) AS pts
    FROM gamification_points gp
    WHERE gp.ref_id = p_showcase_id
      AND gp.category LIKE 'showcase%'
    GROUP BY gp.member_id, gp.organization_id, gp.category
    HAVING SUM(gp.points) <> 0
  ), reversal AS (
    INSERT INTO gamification_points (member_id, organization_id, points, category, reason, ref_id, granted_by)
    SELECT n.member_id, n.organization_id, -n.pts, n.category,
           'Estorno (showcase removido)', p_showcase_id, v_caller.id
    FROM net n
    RETURNING points
  )
  SELECT count(*), COALESCE(SUM(points), 0)::int
    INTO v_reversal_rows, v_reversal_points
  FROM reversal;

  DELETE FROM event_showcases WHERE id = p_showcase_id;

  RETURN jsonb_build_object('success', true, 'removed_id', p_showcase_id,
                            'reversal_rows', v_reversal_rows,
                            'reversal_points', v_reversal_points);
END;
$function$;

-- Higiene de grants (padrão #883 Onda A): a função gateia via auth.uid + can_by_member,
-- mas EXECUTE para anon/PUBLIC está fora do padrão das RPCs de escrita.
REVOKE EXECUTE ON FUNCTION public.remove_event_showcase(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.remove_event_showcase(uuid) FROM anon;

-- ── 4. get_member_xp_pillars: earned_count ignora estornos ───────────────────────
-- Única mudança vs corpo anterior (mig 289 FU-2 Slice C): COUNT(...) ganha
-- FILTER (WHERE p.points > 0) — uma linha de estorno não é um "earned"; pts segue SUM cru.

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

NOTIFY pgrst, 'reload schema';
