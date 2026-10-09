-- =====================================================================================
-- #2624 -- publicacao precisa de exatamente um formato (subtipo), na marcacao e no envio
--
-- MEDIDO em 2026-10-09 (cards com is_portfolio_item, fora archived): 35 artefatos do tipo
-- 'publicacao', 23 sem formato e 12 com um; 0 com dois. Dos 23: 6 em leader_review, 12 feitos em
-- rascunho e 5 em andamento ou backlog, em 6 quadros. A comunicacao nao planeja canal, formato
-- nem esforco a partir da 'publicacao' generica.
--
-- DECISAO DO GP (09/10/2026): a regra entra na MARCACAO e no ENVIO; o predicado
-- _board_item_needs_curation fica como esta (os 23 seguem publicaveis e as revisoes de par e de
-- lider seguem); quando o backfill dos lideres zerar os 23, a regra pode entrar no predicado.
-- Os campos de canal, formato e esforco do catalogo ficam para uma PR seguinte, com o time de
-- comunicacao.
--
-- O QUE MUDA
--   1. set_board_item_artifact_type: marcar 'publicacao' sem formato e recusado. Corpo vivo ==
--      captura 20260924151234 (md5 normalizado, conferido em 09/10).
--   2. Gatilho novo trg_curation_entry_requires_subtype (BEFORE UPDATE OF curation_status ON
--      board_items, so na TRANSICAO para curation_pending): publicacao com zero ou mais de um
--      formato nao entra na curadoria. Uma trava so para TODO caminho de entrada (envio direto,
--      aprovacao do lider, designacao de parecerista), sem tocar no corpo de cada um. Item que ja
--      esta em curation_pending nao e afetado. Efeito conhecido: designar parecerista em card
--      concluido e em rascunho envia o card a curadoria (gatilho do p197), entao para publicacao
--      sem formato a designacao passa a ser recusada ate o formato ser escolhido. A tela traduz.
--   As duas mensagens comecam com 'Publicação precisa de exatamente um formato', padrao novo
--   traduzido na tela (REVIEW_ERRORS do CardDetail, chave reviewErrNoSubtype nas 3 linguas).
--
-- ROLLBACK: DROP TRIGGER trg_curation_entry_requires_subtype ON public.board_items;
--   DROP FUNCTION public.trg_curation_entry_requires_subtype(); reaplicar a captura
--   20260924151234 de set_board_item_artifact_type.
-- =====================================================================================

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

  -- #2624: publicacao e CATEGORIA, nao folha: toda publicacao escolhe exatamente um formato
  -- (subtipo). A comunicacao planeja canal e esforco pelo formato; a generica nao diz nada.
  IF p_type = 'publicacao' AND p_subtype IS NULL THEN
    RAISE EXCEPTION 'Publicação precisa de exatamente um formato: escolha o formato da publicação no card.';
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

CREATE OR REPLACE FUNCTION public.trg_curation_entry_requires_subtype()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_is_pub  boolean;
  v_formats integer;
BEGIN
  SELECT coalesce(bool_or(g.tier = 'system' AND g.name = 'publicacao'), false),
         count(*) FILTER (WHERE g.tier = 'administrative' AND g.requires_curation IS TRUE)
    INTO v_is_pub, v_formats
    FROM public.board_item_tag_assignments a
    JOIN public.tags g ON g.id = a.tag_id
   WHERE a.board_item_id = NEW.id
     AND g.domain = 'board_item';

  IF v_is_pub AND v_formats <> 1 THEN
    RAISE EXCEPTION 'Publicação precisa de exatamente um formato: escolha o formato da publicação no card antes de seguir para a curadoria.';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.trg_curation_entry_requires_subtype() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_curation_entry_requires_subtype ON public.board_items;
CREATE TRIGGER trg_curation_entry_requires_subtype
  BEFORE UPDATE OF curation_status ON public.board_items
  FOR EACH ROW
  WHEN (NEW.curation_status = 'curation_pending' AND OLD.curation_status IS DISTINCT FROM 'curation_pending')
  EXECUTE FUNCTION public.trg_curation_entry_requires_subtype();
