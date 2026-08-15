-- #1778 / #785 — o predicado passa a exigir que o chamador ENXERGUE o card.
--
-- Achado pelo guard 785-secdef-reader-confidential-gate, que acusou can_manage_card_checklist como
-- leitor SECURITY DEFINER de tabelas ligadas a iniciativa sem o gate. Nao era falso positivo:
-- medido por impersonacao em transacao abortada, um membro com write_board e SEM engajamento na
-- iniciativa confidencial (rls_can_see_item = false) conseguia inserir atividade num card daquele
-- board pela RPC — porque SECURITY DEFINER contorna a RLS que barra o caminho direto.
--
-- O MCP ja fazia esse fail-fast como contrato (canSee antes da autoridade); o caminho por
-- PostgREST nao tinha ninguem. Com o gate dentro do predicado, as quatro RPCs passam a carrega-lo
-- de uma vez, e a regra fica a mesma nos dois caminhos.
--
-- Nao ha chamador interno destas RPCs (varrido pg_proc), entao nenhum cron muda de comportamento.

CREATE OR REPLACE FUNCTION public.can_manage_card_checklist(p_member_id uuid, p_card_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT p_member_id IS NOT NULL
     AND p_card_id IS NOT NULL
     -- #785/ADR-0105: nao se administra o trabalho de um card que nao se pode ver
     AND public.rls_can_see_item(p_card_id)
     AND (
       -- capacidade organizacional (o caminho de sempre)
       public.can_by_member(p_member_id, 'write_board')
       -- responsavel pelo card
       OR EXISTS (SELECT 1 FROM public.board_items bi
                  WHERE bi.id = p_card_id AND bi.assignee_id = p_member_id)
       -- autor ou contribuidor do card (#1778: dono do trabalho, ainda que sem capacidade)
       OR EXISTS (SELECT 1 FROM public.board_item_assignments ba
                  WHERE ba.item_id = p_card_id AND ba.member_id = p_member_id
                    AND ba.role IN ('author', 'contributor'))
       -- papel explicito no board
       OR EXISTS (SELECT 1 FROM public.board_items bi
                  JOIN public.board_members bm ON bm.board_id = bi.board_id
                  WHERE bi.id = p_card_id AND bm.member_id = p_member_id
                    AND bm.board_role IN ('admin', 'editor'))
       -- time de comunicacao no board de comunicacao
       OR EXISTS (SELECT 1 FROM public.board_items bi
                  JOIN public.project_boards pb ON pb.id = bi.board_id
                  JOIN public.members m ON m.id = p_member_id
                  WHERE bi.id = p_card_id
                    AND coalesce(pb.domain_key, '') = 'communication'
                    AND (m.operational_role = 'communicator'
                         OR m.designations && ARRAY['comms_team', 'comms_leader', 'comms_member']))
     );
$function$;
