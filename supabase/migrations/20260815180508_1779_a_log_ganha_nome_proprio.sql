-- #1779: o log de ciclo de vida ganha nome proprio, e 'atividades' passa a significar uma coisa so
--
-- get_board_activities estava sobrecarregada com dois sentidos OPOSTOS:
--
--   (p_board_id, p_limit)                                    o LOG de ciclo de vida
--   (p_board_id, p_assignee, p_status, p_period)             as TAREFAS (atividades do card)
--
-- O MCP chamava a primeira; a segunda so era usada pelo frontend. Nao havia porta agregada de
-- tarefas no semantico: para saber quem responde por que, e ate quando, era card a card.
--
-- Varrida a Fase 1 do #1780: e caso UNICO no schema. De todas as proname duplicadas em public, so
-- esta significa duas coisas.
--
-- Qual dos dois nomes estava errado: no produto, uma linha de board_item_checklists CHAMA-SE
-- atividade (e o verbo "adicionar atividade" que o #1778 destravou). Entao 'atividades' e das
-- tarefas, e quem precisava de nome proprio era o log. Depois desta migration e da que apaga a
-- assinatura velha, get_board_activities significa UMA coisa.
--
-- Ordem de implantacao, para nao haver janela quebrada: esta migration CRIA o nome novo e deixa a
-- assinatura velha viva; a EF passa a chamar o nome novo e e implantada; so entao a velha e
-- apagada. A EF em producao nunca aponta para uma funcao inexistente.
--
-- Envelope: a chave passa de 'activities' para 'events'. A funcao devolve evento de ciclo de vida,
-- nao atividade, e os dois unicos consumidores (as duas chamadas da EF) mudam junto.

CREATE OR REPLACE FUNCTION public.get_board_lifecycle_log(p_board_id uuid DEFAULT NULL, p_limit integer DEFAULT 20)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record;
  v_result jsonb;
BEGIN
  SELECT id, tribe_id, is_superadmin, operational_role
  INTO v_member FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(evt)::jsonb ORDER BY evt.created_at DESC), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      ble.id,
      ble.action,
      ble.previous_status,
      ble.new_status,
      ble.reason,
      ble.created_at,
      ble.review_round,
      bi.title as item_title,
      m.name as actor_name
    FROM board_lifecycle_events ble
    JOIN board_items bi ON bi.id = ble.item_id
    LEFT JOIN members m ON m.id = ble.actor_member_id
    WHERE (p_board_id IS NULL OR ble.board_id = p_board_id)
      AND public.rls_can_see_board(bi.board_id)
    ORDER BY ble.created_at DESC
    LIMIT p_limit
  ) evt;

  RETURN jsonb_build_object(
    'events', v_result,
    'count', jsonb_array_length(v_result)
  );
END;
$function$;

COMMENT ON FUNCTION public.get_board_lifecycle_log(uuid, integer) IS
  '#1779: log de ciclo de vida do board (acao, status anterior/novo, motivo, ator). Nome proprio '
  'da assinatura (uuid, integer) que antes se chamava get_board_activities, onde colidia com as '
  'TAREFAS do board. Envelope: {events, count}.';

-- CREATE FUNCTION nasce com EXECUTE para PUBLIC. A ACL espelha a da funcao de origem: authenticated
-- e service_role, nunca anon (o log carrega nome de ator).
REVOKE ALL ON FUNCTION public.get_board_lifecycle_log(uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_board_lifecycle_log(uuid, integer) TO authenticated, service_role;
