-- Onda 5a (#1473) — Painel "Minha Pontuação, auditável"
-- ---------------------------------------------------------------------------
-- Objetivo: o ledger fato-a-fato (get_my_points_statement, #1087 wave 2) já
-- existe, mas mostra `created_at` (data de ATRIBUIÇÃO) e não diz a QUAL CICLO
-- cada fato pertence. Após a Onda 3 (#1464) a coluna `occurred_at` (data DO
-- FATO) é a fonte canônica de janelamento. A 5a expõe, por linha de fato:
--   • occurred_at (data do fato) + effective_at (COALESCE occurred_at,created_at)
--   • cycle_code / cycle_label do ciclo a que o fato pertence (resolvido pela
--     janela do ciclo que contém effective_at) — responde "de onde vêm estes
--     pontos e em qual ciclo" (o caso Jefferson).
--
-- Forma (respeitando o guard anti-IDOR do #1087 wave1):
--   1. _points_statement_json(member,org,scope,...) — helper INTERNO (SECDEF,
--      revogado de todos os roles). Constrói o extrato. Garante que a visão do
--      próprio membro e a visão admin mostrem FATOS BYTE-IDÊNTICOS (crítico p/
--      uma feature "auditável").
--   2. get_my_points_statement(text,text,integer,integer) — MESMA assinatura
--      self-only (sem p_member_id — o guard 1087-wave1 continua válido), passa
--      a delegar ao helper.
--   3. get_member_points_ledger(p_member_id,...) — NOVO, gate admin (view_pii +
--      chapter scope, espelhando get_member_cycle_xp). Superfície ?member=.
-- ---------------------------------------------------------------------------

-- 1) Helper interno ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public._points_statement_json(
  p_member_id uuid,
  p_org_id uuid,
  p_scope text DEFAULT 'cycle'::text,
  p_category text DEFAULT NULL::text,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_limit integer;
  v_offset integer;
  v_cycle_code text;
  v_from timestamptz;
  v_to timestamptz;
BEGIN
  IF p_scope NOT IN ('cycle','lifetime') THEN
    RAISE EXCEPTION 'invalid scope: % (must be cycle or lifetime)', p_scope;
  END IF;
  v_limit := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
  v_offset := GREATEST(COALESCE(p_offset, 0), 0);

  IF p_scope = 'cycle' THEN
    SELECT c.cycle_code, c.cycle_start::timestamptz,
           CASE WHEN c.cycle_end IS NULL THEN NULL
                ELSE (c.cycle_end + interval '1 day')::timestamptz END
      INTO v_cycle_code, v_from, v_to
    FROM public.cycles c
    WHERE c.is_current = true
    LIMIT 1;
  END IF;

  RETURN (
    WITH filtered AS (
      SELECT gp.id, gp.created_at, gp.occurred_at,
             COALESCE(gp.occurred_at, gp.created_at) AS effective_at,
             gp.points, gp.category, gp.reason, gp.ref_id, gp.granted_by,
             r.pillar, r.display_name_i18n,
             cyc.cycle_code AS fact_cycle_code, cyc.cycle_label AS fact_cycle_label
      FROM public.gamification_points gp
      LEFT JOIN LATERAL (
        SELECT gr.pillar, gr.display_name_i18n
        FROM public.gamification_rules gr
        WHERE gr.organization_id = gp.organization_id
          AND gr.slug = gp.category
        ORDER BY gr.effective_from DESC
        LIMIT 1
      ) r ON true
      LEFT JOIN LATERAL (
        SELECT c.cycle_code, c.cycle_label
        FROM public.cycles c
        WHERE COALESCE(gp.occurred_at, gp.created_at) >= c.cycle_start::timestamptz
          AND (c.cycle_end IS NULL
               OR COALESCE(gp.occurred_at, gp.created_at) < (c.cycle_end + interval '1 day')::timestamptz)
        ORDER BY c.cycle_start DESC
        LIMIT 1
      ) cyc ON true
      WHERE gp.member_id = p_member_id
        AND gp.organization_id = p_org_id
        AND (
          p_scope = 'lifetime'
          OR (COALESCE(gp.occurred_at, gp.created_at) >= v_from AND (v_to IS NULL OR COALESCE(gp.occurred_at, gp.created_at) < v_to))
        )
        AND (p_category IS NULL OR gp.category = p_category)
    )
    SELECT jsonb_build_object(
      'member_id', p_member_id,
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
          'occurred_at', e.occurred_at,
          'effective_at', e.effective_at,
          'points', e.points,
          'category', e.category,
          'pillar', e.pillar,
          'rule_display_name_i18n', e.display_name_i18n,
          'cycle_code', e.fact_cycle_code,
          'cycle_label', e.fact_cycle_label,
          'reason', e.reason,
          'ref_id', e.ref_id,
          'granted_by', e.granted_by,
          'granted_by_name', e.granted_by_name,
          'is_reversal', e.is_reversal,
          'champion', e.champion
        ) ORDER BY e.effective_at DESC, e.created_at DESC, e.id DESC)
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
          ORDER BY f.effective_at DESC, f.created_at DESC, f.id DESC
          LIMIT v_limit OFFSET v_offset
        ) e
      ), '[]'::jsonb)
    )
  );
END;
$function$;

REVOKE ALL ON FUNCTION public._points_statement_json(uuid, uuid, text, text, integer, integer) FROM public, anon, authenticated;

-- 2) Self extrato — MESMA assinatura self-only (sem p_member_id: guard 1087-wave1) ----
DROP FUNCTION IF EXISTS public.get_my_points_statement(text, text, integer, integer);
CREATE FUNCTION public.get_my_points_statement(
  p_scope text DEFAULT 'cycle'::text,
  p_category text DEFAULT NULL::text,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_member_id uuid;
  v_org_id uuid;
BEGIN
  SELECT m.id, m.organization_id INTO v_member_id, v_org_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  RETURN public._points_statement_json(v_member_id, v_org_id, p_scope, p_category, p_limit, p_offset);
END;
$function$;

REVOKE ALL ON FUNCTION public.get_my_points_statement(text, text, integer, integer) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_my_points_statement(text, text, integer, integer) TO authenticated;

-- 3) Admin ledger de outro membro — gate view_pii + chapter scope ----------------
CREATE OR REPLACE FUNCTION public.get_member_points_ledger(
  p_member_id uuid,
  p_scope text DEFAULT 'cycle'::text,
  p_category text DEFAULT NULL::text,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_org uuid;
  v_target_org uuid;
  v_scope text;
BEGIN
  SELECT m.id, m.organization_id INTO v_caller_id, v_caller_org
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  IF p_member_id = v_caller_id THEN
    RETURN public._points_statement_json(v_caller_id, v_caller_org, p_scope, p_category, p_limit, p_offset);
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'view_pii') THEN
    RAISE EXCEPTION 'Unauthorized' USING errcode = 'insufficient_privilege';
  END IF;

  v_scope := public.caller_chapter_scope();
  IF v_scope IS NOT NULL
     AND (SELECT chapter FROM public.members WHERE id = p_member_id) IS DISTINCT FROM v_scope THEN
    RAISE EXCEPTION 'Unauthorized' USING errcode = 'insufficient_privilege';
  END IF;

  SELECT m.organization_id INTO v_target_org FROM public.members m WHERE m.id = p_member_id;
  IF v_target_org IS NULL THEN
    RAISE EXCEPTION 'member_not_found';
  END IF;
  IF v_target_org <> v_caller_org THEN
    RAISE EXCEPTION 'Unauthorized' USING errcode = 'insufficient_privilege';
  END IF;

  RETURN public._points_statement_json(p_member_id, v_target_org, p_scope, p_category, p_limit, p_offset);
END;
$function$;

REVOKE ALL ON FUNCTION public.get_member_points_ledger(uuid, text, text, integer, integer) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_member_points_ledger(uuid, text, text, integer, integer) TO authenticated;

NOTIFY pgrst, 'reload schema';
