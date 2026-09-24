-- ============================================================================
-- #2455 — revisor de governanca ve o botao da revisao do lider
-- ============================================================================
--
-- WHAT: get_artifact_classification passa a devolver `can_leader_review`, calculado com a MESMA regra
--   de complete_leader_review: lider da iniciativa (engagement leader ativo) OU
--   participate_in_governance_review. O CardDetail usa isto para mostrar "Avaliar como Lider".
-- WHY: medido em 24/09/2026, a RPC aceitava o revisor de governanca e a tela so mostrava o botao a
--   quem tem manage_board_admin na iniciativa: quem o banco autoriza nao via o botao. Hoje ninguem
--   esta bloqueado (os lideres passam no gate da tela); e o caminho de substituicao do lider.
-- ROLLBACK: reaplicar a versao de 20260924151234.
-- CROSS-REF: #2455 · #2444 · #2447
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_artifact_classification(p_item_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_caller uuid;
  v_item   public.board_items%ROWTYPE;
  v_init   uuid;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_item FROM public.board_items WHERE id = p_item_id;
  -- Gate confidencial (ADR-0105): quem nao ve o card nao ve a classificacao dele.
  IF NOT FOUND OR NOT public.rls_can_see_item(p_item_id) THEN
    RAISE EXCEPTION 'Item not found';
  END IF;

  SELECT pb.initiative_id INTO v_init FROM public.project_boards pb WHERE pb.id = v_item.board_id;

  RETURN jsonb_build_object(
    'is_portfolio_item', coalesce(v_item.is_portfolio_item, false),
    'needs_curation', public._board_item_needs_curation(p_item_id),
    'type', (SELECT g.name FROM public.board_item_tag_assignments a JOIN public.tags g ON g.id = a.tag_id
              WHERE a.board_item_id = p_item_id AND g.tier = 'system' AND g.domain = 'board_item'
                AND g.name <> 'entregavel_lider'
              ORDER BY g.requires_curation DESC, g.display_order LIMIT 1),
    'subtype', (SELECT g.name FROM public.board_item_tag_assignments a JOIN public.tags g ON g.id = a.tag_id
                 WHERE a.board_item_id = p_item_id AND g.tier = 'administrative' AND g.domain = 'board_item'
                   AND g.requires_curation IS TRUE
                 ORDER BY g.display_order LIMIT 1),
    'suggested', public.portfolio_suggest_item_type(v_item.title, v_item.tags),
    'can_edit', (v_init IS NOT NULL AND public.can_by_member(v_caller, 'manage_board_admin', 'initiative', v_init))
                OR public.can_by_member(v_caller, 'manage_platform'),
    -- #2455: quem a complete_leader_review aceita, pela MESMA regra: lider da iniciativa (vinculo
    -- ativo) ou revisor de governanca. A tela usa isto em vez de reimplementar a regra.
    'can_leader_review', (v_init IS NOT NULL AND EXISTS (
                            SELECT 1 FROM public.engagements e
                              JOIN public.persons p ON p.id = e.person_id
                             WHERE e.initiative_id = v_init AND e.status = 'active'
                               AND e.role = 'leader' AND p.auth_id = auth.uid()))
                         OR public.can_by_member(v_caller, 'participate_in_governance_review'),
    'types', (SELECT jsonb_agg(jsonb_build_object('name', g.name, 'label_pt', g.label_pt, 'label_en', g.label_en,
                                                  'label_es', g.label_es, 'requires_curation', g.requires_curation)
                               ORDER BY g.display_order)
                FROM public.tags g
               WHERE g.tier = 'system' AND g.domain = 'board_item' AND g.name <> 'entregavel_lider'),
    'subtypes', (SELECT jsonb_agg(jsonb_build_object('name', g.name, 'label_pt', g.label_pt, 'label_en', g.label_en,
                                                     'label_es', g.label_es)
                                  ORDER BY g.display_order)
                   FROM public.tags g
                  WHERE g.tier = 'administrative' AND g.domain = 'board_item' AND g.requires_curation IS TRUE)
  );
END;
$fn$;
