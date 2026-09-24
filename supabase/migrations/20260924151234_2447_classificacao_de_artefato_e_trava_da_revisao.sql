-- ============================================================================
-- #2447 fatia A — o tipo de artefato ganha caminho de escrita, e revisao/curadoria
--                 passam a valer so para artefato publicavel
-- ============================================================================
--
-- WHAT:
--   * tags.requires_curation marca os tipos que passam por peer review -> revisao do lider ->
--     curadoria (decisao do GP, 24/09/2026): publicacao e os subtipos artigo_academico,
--     artigo_linkedin, ebook, estudo_caso, infografico, report.
--   * _board_item_needs_curation(item): o card e entregavel de portfolio E tem um desses tipos.
--   * get_artifact_classification / set_board_item_artifact_type: a leitura e a escrita do tipo
--     pela tela, na MESMA taxonomia que o painel de portfolio le.
--   * complete_peer_review, complete_leader_review (aprovar/dispensar) e submit_for_curation
--     recusam card que nao seja artefato publicavel. Devolver continua sempre possivel.
-- WHY: medido em 24/09/2026, nenhuma tela nem funcao gravava o tipo (o card grava so tags livres),
--   e a secao de revisao aparecia em todo card em draft: 5 dos 16 cards parados em leader_review
--   nao eram artefato.
-- TIPO x SUBTIPO: "tipo" = tag system/board_item exceto entregavel_lider (a mesma definicao de
--   audit_portfolio_flag_tag_gaps); "subtipo" = tag administrative com requires_curation (so existe
--   debaixo de publicacao). Marcadores como gate_a, entrega_final e entregavel_lider nao sao tocados.
-- ROLLBACK: reaplicar as versoes anteriores das 3 RPCs; DROP das 3 funcoes novas;
--   ALTER TABLE tags DROP COLUMN requires_curation.
-- CROSS-REF: #2447 · #2444 · p197 · ADR-0086
-- ============================================================================

-- (1) Quais tipos passam por curadoria: configuracao na propria taxonomia -----------------
ALTER TABLE public.tags ADD COLUMN IF NOT EXISTS requires_curation boolean NOT NULL DEFAULT false;

UPDATE public.tags SET requires_curation = true
 WHERE domain = 'board_item'
   AND name IN ('publicacao', 'artigo_academico', 'artigo_linkedin', 'ebook', 'estudo_caso', 'infografico', 'report');

COMMENT ON COLUMN public.tags.requires_curation IS
  '#2447 — o tipo de artefato passa por peer review, revisao do lider e curadoria. Decisao do GP em 24/09/2026.';

-- (2) O card precisa de revisao e curadoria? --------------------------------------------
CREATE OR REPLACE FUNCTION public._board_item_needs_curation(p_item_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT EXISTS (
    SELECT 1
      FROM public.board_items bi
      JOIN public.board_item_tag_assignments a ON a.board_item_id = bi.id
      JOIN public.tags g ON g.id = a.tag_id
     WHERE bi.id = p_item_id
       AND bi.is_portfolio_item IS TRUE
       AND g.domain = 'board_item'
       AND g.requires_curation IS TRUE
  );
$fn$;

REVOKE ALL ON FUNCTION public._board_item_needs_curation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._board_item_needs_curation(uuid) TO authenticated, service_role;

-- (3) Leitura da classificacao para a tela ---------------------------------------------
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

REVOKE ALL ON FUNCTION public.get_artifact_classification(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_artifact_classification(uuid) TO authenticated;

-- (4) Escrita do tipo: quem ja pode marcar o card como entregavel de portfolio ------------
CREATE OR REPLACE FUNCTION public.set_board_item_artifact_type(p_item_id uuid, p_type text, p_subtype text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_caller uuid;
  v_item   public.board_items%ROWTYPE;
  v_init   uuid;
  v_type_id uuid;
  v_sub_id  uuid;
  v_label   text;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_item FROM public.board_items WHERE id = p_item_id;
  IF NOT FOUND OR NOT public.rls_can_see_item(p_item_id) THEN
    RAISE EXCEPTION 'Item not found';
  END IF;

  SELECT pb.initiative_id INTO v_init FROM public.project_boards pb WHERE pb.id = v_item.board_id;
  -- Mesmo gate da marcacao de portfolio na tela: lider da iniciativa ou GP.
  IF NOT ((v_init IS NOT NULL AND public.can_by_member(v_caller, 'manage_board_admin', 'initiative', v_init))
          OR public.can_by_member(v_caller, 'manage_platform')) THEN
    RAISE EXCEPTION 'Requires initiative leadership or platform management';
  END IF;

  IF p_type IS NOT NULL THEN
    SELECT id INTO v_type_id FROM public.tags
     WHERE name = p_type AND tier = 'system' AND domain = 'board_item' AND name <> 'entregavel_lider';
    IF v_type_id IS NULL THEN RAISE EXCEPTION 'Tipo de artefato desconhecido: %', p_type; END IF;
  END IF;

  IF p_subtype IS NOT NULL THEN
    IF p_type IS DISTINCT FROM 'publicacao' THEN
      RAISE EXCEPTION 'Subtipo so existe para publicacao';
    END IF;
    SELECT id INTO v_sub_id FROM public.tags
     WHERE name = p_subtype AND tier = 'administrative' AND domain = 'board_item' AND requires_curation IS TRUE;
    IF v_sub_id IS NULL THEN RAISE EXCEPTION 'Subtipo de publicacao desconhecido: %', p_subtype; END IF;
  END IF;

  -- Troca o tipo e o subtipo; marcadores (entregavel_lider, gate_a, entrega_final...) ficam.
  DELETE FROM public.board_item_tag_assignments a
   USING public.tags g
   WHERE a.tag_id = g.id AND a.board_item_id = p_item_id AND g.domain = 'board_item'
     AND ((g.tier = 'system' AND g.name <> 'entregavel_lider')
          OR (g.tier = 'administrative' AND g.requires_curation IS TRUE));

  IF v_type_id IS NOT NULL THEN
    INSERT INTO public.board_item_tag_assignments (board_item_id, tag_id) VALUES (p_item_id, v_type_id);
  END IF;
  IF v_sub_id IS NOT NULL THEN
    INSERT INTO public.board_item_tag_assignments (board_item_id, tag_id) VALUES (p_item_id, v_sub_id);
  END IF;

  SELECT coalesce(string_agg(g.label_pt, ' / ' ORDER BY g.tier DESC), 'sem tipo') INTO v_label
    FROM public.tags g WHERE g.id IN (v_type_id, v_sub_id);

  INSERT INTO public.board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
  VALUES (v_item.board_id, p_item_id, 'portfolio_flag_changed', 'Tipo de artefato: ' || v_label, v_caller);

  RETURN jsonb_build_object('type', p_type, 'subtype', p_subtype,
                            'needs_curation', public._board_item_needs_curation(p_item_id));
END;
$fn$;

REVOKE ALL ON FUNCTION public.set_board_item_artifact_type(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_board_item_artifact_type(uuid, text, text) TO authenticated;

-- (5) As tres portas do fluxo recusam card que nao seja artefato publicavel ------------------
CREATE OR REPLACE FUNCTION public.complete_peer_review(p_item_id uuid, p_summary text DEFAULT NULL::text, p_waived boolean DEFAULT false, p_waiver_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller members%ROWTYPE;
  v_item   board_items%ROWTYPE;
  v_initiative_id uuid;
  v_is_authorized boolean := false;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_item FROM public.board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found: %', p_item_id; END IF;

  IF v_item.curation_status NOT IN ('draft', 'peer_review') THEN
    RAISE EXCEPTION 'Peer review can only be completed from draft or peer_review status (current: %)', v_item.curation_status;
  END IF;

  IF p_waived AND (p_waiver_reason IS NULL OR length(trim(p_waiver_reason)) = 0) THEN
    RAISE EXCEPTION 'Waiver requires a reason (per manual §4.2 adaptações)';
  END IF;

  -- #2447: peer review, revisao do lider e curadoria valem so para artefato publicavel.
  IF NOT public._board_item_needs_curation(p_item_id) THEN
    RAISE EXCEPTION 'Revisão e curadoria valem só para artefato publicável: marque o card como entregável de portfólio e escolha um tipo de publicação.';
  END IF;

  -- p197 fix H4: gate by assignee (intellectual author), tribe leader, or governance reviewer.
  -- Dropped board_items.created_by branch (often GP doing data entry, not author).
  SELECT pb.initiative_id INTO v_initiative_id
    FROM public.project_boards pb WHERE pb.id = v_item.board_id;

  IF v_item.assignee_id = v_caller.id THEN
    v_is_authorized := true;
  ELSIF EXISTS (
    SELECT 1 FROM public.board_item_assignments bia
    WHERE bia.item_id = p_item_id
      AND bia.member_id = v_caller.id
      AND bia.role IN ('author', 'contributor')
  ) THEN
    v_is_authorized := true;
  ELSIF v_initiative_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.engagements e
    JOIN public.persons p ON p.id = e.person_id
    WHERE e.initiative_id = v_initiative_id
      AND e.status = 'active'
      AND e.role = 'leader'
      AND p.auth_id = auth.uid()
  ) THEN
    v_is_authorized := true;
  ELSIF public.can_by_member(v_caller.id, 'participate_in_governance_review') THEN
    v_is_authorized := true;
  END IF;

  IF NOT v_is_authorized THEN
    RAISE EXCEPTION 'Requires authorship (assignee or assignments role author/contributor), tribe leadership, or governance reviewer authority';
  END IF;

  UPDATE public.board_items
  SET curation_status = 'leader_review',
      peer_review_completed_at = now(),
      peer_review_summary = COALESCE(p_summary, peer_review_summary),
      peer_review_waived = p_waived,
      peer_review_waived_reason = CASE WHEN p_waived THEN p_waiver_reason ELSE NULL END,
      updated_at = now()
  WHERE id = p_item_id;

  -- p197 fix B1: use distinct action 'peer_review_completed' (NOT 'curation_review')
  INSERT INTO public.board_lifecycle_events
    (board_id, item_id, action, reason, actor_member_id)
  VALUES (
    v_item.board_id,
    p_item_id,
    'peer_review_completed',
    CASE WHEN p_waived
         THEN 'Peer review dispensado: ' || p_waiver_reason
         ELSE 'Peer review concluído (colegiado §4.2 etapa 5)' || COALESCE(' — ' || p_summary, '')
    END,
    v_caller.id
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.complete_leader_review(p_item_id uuid, p_decision text, p_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller members%ROWTYPE;
  v_item   board_items%ROWTYPE;
  v_initiative_id uuid;
  v_is_leader boolean := false;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF p_decision NOT IN ('approved', 'returned', 'waived') THEN
    RAISE EXCEPTION 'Decision must be one of: approved, returned, waived (got: %)', p_decision;
  END IF;

  SELECT * INTO v_item FROM public.board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found: %', p_item_id; END IF;

  IF v_item.curation_status NOT IN ('leader_review', 'draft') THEN
    RAISE EXCEPTION 'Leader review can only be completed from leader_review or draft (current: %)', v_item.curation_status;
  END IF;

  SELECT pb.initiative_id INTO v_initiative_id
    FROM public.project_boards pb WHERE pb.id = v_item.board_id;

  IF v_initiative_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.engagements e
    JOIN public.persons p ON p.id = e.person_id
    WHERE e.initiative_id = v_initiative_id
      AND e.status = 'active'
      AND e.role = 'leader'
      AND p.auth_id = auth.uid()
  ) THEN
    v_is_leader := true;
  ELSIF public.can_by_member(v_caller.id, 'participate_in_governance_review') THEN
    v_is_leader := true;
  END IF;

  IF NOT v_is_leader THEN
    RAISE EXCEPTION 'Leader review requires tribe leadership of card''s initiative or governance reviewer authority';
  END IF;

  -- #2447: so artefato publicavel segue para a curadoria. Devolver continua sempre possivel,
  -- e e a saida para os cards que entraram no fluxo sem ser artefato.
  IF p_decision IN ('approved', 'waived') AND NOT public._board_item_needs_curation(p_item_id) THEN
    RAISE EXCEPTION 'Só artefato publicável segue para a curadoria: classifique o card como entregável de portfólio com um tipo de publicação, ou use Devolver.';
  END IF;

  IF p_decision IN ('approved', 'waived') THEN
    UPDATE public.board_items
    SET curation_status = 'curation_pending',
        leader_review_completed_at = now(),
        leader_review_decision = p_decision,
        leader_review_notes = p_notes,
        leader_reviewer_id = v_caller.id,
        updated_at = now()
    WHERE id = p_item_id;

    -- Use distinct action for analytics clarity (added to CHECK in B1 fix)
    INSERT INTO public.board_lifecycle_events
      (board_id, item_id, action, reason, actor_member_id)
    VALUES (
      v_item.board_id,
      p_item_id,
      'leader_review_completed',
      'Leader review ' || p_decision || ' → submetido à curadoria' || COALESCE(' — ' || p_notes, ''),
      v_caller.id
    );
  ELSIF p_decision = 'returned' THEN
    -- p197 fix H2: ALSO reset waiver state when returning. Without this,
    -- author who waived peer review then got returned would have stale
    -- "waived" flag persisting and potentially skip peer review on retry.
    UPDATE public.board_items
    SET curation_status = 'draft',
        leader_review_completed_at = now(),
        leader_review_decision = p_decision,
        leader_review_notes = p_notes,
        leader_reviewer_id = v_caller.id,
        peer_review_completed_at = NULL,
        peer_review_summary = NULL,
        peer_review_waived = false,
        peer_review_waived_reason = NULL,
        updated_at = now()
    WHERE id = p_item_id;

    INSERT INTO public.board_lifecycle_events
      (board_id, item_id, action, reason, actor_member_id)
    VALUES (
      v_item.board_id,
      p_item_id,
      'leader_review_completed',
      'Leader review devolvido ao autor' || COALESCE(' — ' || p_notes, ''),
      v_caller.id
    );

    -- p197 fix H1: pass 'board_item' literal as p_source_type
    -- (NOT board_id::text — frontend needs semantic type for deep link)
    IF v_item.assignee_id IS NOT NULL THEN
      PERFORM public.create_notification(
        v_item.assignee_id,
        'card_moved',
        'board_item',
        v_item.id,
        v_item.title,
        v_caller.id,
        'Líder devolveu sua peça para revisão' || COALESCE(': ' || p_notes, '')
      );
    END IF;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.submit_for_curation(p_item_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller members%rowtype;
  v_item board_items%rowtype;
  v_sla_days int;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  -- ADR-0041: V4 catalog OR Path Y (tribe_leader operational handoff)
  IF NOT (
    public.can_by_member(v_caller.id, 'participate_in_governance_review')
    OR v_caller.operational_role = 'tribe_leader'
  ) THEN
    RAISE EXCEPTION 'Requires participate_in_governance_review or tribe_leader';
  END IF;

  SELECT * INTO v_item FROM board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found'; END IF;
  IF v_item.curation_status NOT IN ('leader_review', 'draft') THEN
    RAISE EXCEPTION 'Item must be in leader_review or draft status';
  END IF;

  -- #2447: so artefato publicavel entra na fila da curadoria.
  IF NOT public._board_item_needs_curation(p_item_id) THEN
    RAISE EXCEPTION 'Só artefato publicável entra na curadoria: marque o card como entregável de portfólio e escolha um tipo de publicação.';
  END IF;

  SELECT sla_days INTO v_sla_days FROM board_sla_config WHERE board_id = v_item.board_id;

  UPDATE board_items
  SET curation_status = 'curation_pending',
      curation_due_at = now() + make_interval(days => coalesce(v_sla_days, 7)),
      updated_at = now()
  WHERE id = p_item_id;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, actor_member_id, sla_deadline)
  VALUES (v_item.board_id, p_item_id, 'submitted_for_curation', v_caller.id,
    now() + make_interval(days => coalesce(v_sla_days, 7)));
END;
$function$;
