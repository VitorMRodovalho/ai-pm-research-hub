-- Leituras de card e do portfólio seguem a política de leitura das tabelas (membro com vínculo vigente).
--
-- Mesma regra das funções de 20261005183507 e do lote 2a (20261005191818): a quem chama pela API
-- (_request_is_rest_caller(), #684), a leitura segue a política da tabela, que é membro com vínculo vigente
-- (rls_is_authoritative_member()). A recusa devolve o formato que cada função já usa: conjunto vazio na linha do tempo
-- do card, e by_lane vazio no resumo por quadro (função SQL, a regra entra no WHERE dos quadros). Chamadas internas e
-- membros com vínculo vigente seguem iguais.
--
-- Cada CREATE OR REPLACE é a captura vigente da função, byte a byte, mais a regra. Nenhuma assinatura muda.

-- get_card_timeline: captura de 20260805000274_p785_gate_content_readers_confidential.sql
CREATE OR REPLACE FUNCTION public.get_card_timeline(p_item_id uuid)
 RETURNS TABLE(id bigint, action text, previous_status text, new_status text, reason text, actor_name text, created_at timestamp with time zone, review_score jsonb, review_round integer, sla_deadline timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Leitura pela API segue a política de leitura de board_lifecycle_events (membro com vínculo vigente).
  IF public._request_is_rest_caller() AND NOT public.rls_is_authoritative_member() THEN RETURN; END IF;
  -- #785: confidential gate (item->board->initiative)
  IF NOT public.rls_can_see_item(p_item_id) THEN RETURN; END IF;
  RETURN QUERY
  SELECT
    e.id,
    e.action,
    e.previous_status,
    e.new_status,
    e.reason,
    m.name AS actor_name,
    e.created_at,
    e.review_score,
    e.review_round,
    e.sla_deadline
  FROM board_lifecycle_events e
  LEFT JOIN members m ON m.id = e.actor_member_id
  WHERE e.item_id = p_item_id
  ORDER BY e.created_at DESC;
END;
$function$;

-- exec_portfolio_board_summary: captura de 20260805000321_932_confidential_aggregate_exclusion_part2.sql
CREATE OR REPLACE FUNCTION public.exec_portfolio_board_summary(p_include_inactive boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH boards AS (
    SELECT
      pb.id AS board_id, pb.board_name, pb.board_scope,
      COALESCE(pb.domain_key, 'tribe_general') AS domain_key,
      i.legacy_tribe_id AS tribe_id,
      i.title AS tribe_name
    FROM public.project_boards pb
    LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
    WHERE (p_include_inactive OR pb.is_active = true) AND NOT public.is_confidential_board(pb.id)
      -- Leitura pela API segue a política de leitura de board_items (membro com vínculo vigente).
      AND (NOT public._request_is_rest_caller() OR public.rls_is_authoritative_member())
  ),
  items AS (
    SELECT
      b.board_scope, b.domain_key,
      count(bi.id) AS total_cards,
      count(*) FILTER (WHERE bi.status = 'backlog') AS backlog,
      count(*) FILTER (WHERE bi.status = 'todo') AS todo,
      count(*) FILTER (WHERE bi.status = 'in_progress') AS in_progress,
      count(*) FILTER (WHERE bi.status = 'review') AS review,
      count(*) FILTER (WHERE bi.status = 'done') AS done,
      count(*) FILTER (WHERE bi.status = 'archived') AS archived,
      count(*) FILTER (WHERE bi.assignee_id IS NULL AND bi.status <> 'archived') AS orphan_cards,
      count(*) FILTER (WHERE bi.due_date::date < current_date AND bi.status NOT IN ('done', 'archived')) AS overdue_cards
    FROM boards b
    LEFT JOIN public.board_items bi ON bi.board_id = b.board_id
    GROUP BY b.board_scope, b.domain_key
  )
  SELECT jsonb_build_object(
    'generated_at', now(),
    'by_lane', COALESCE(jsonb_agg(jsonb_build_object(
      'board_scope', i.board_scope, 'domain_key', i.domain_key,
      'total_cards', i.total_cards, 'backlog', i.backlog, 'todo', i.todo,
      'in_progress', i.in_progress, 'review', i.review, 'done', i.done,
      'archived', i.archived, 'orphan_cards', i.orphan_cards, 'overdue_cards', i.overdue_cards
    ) ORDER BY i.board_scope, i.domain_key), '[]'::jsonb)
  )
  FROM items i;
$function$;

NOTIFY pgrst, 'reload schema';
