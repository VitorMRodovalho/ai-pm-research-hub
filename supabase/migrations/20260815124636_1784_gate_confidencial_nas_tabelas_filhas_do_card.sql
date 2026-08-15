-- #1784 — o gate de visibilidade confidencial (ADR-0105 / #785) alcanca as tabelas-filhas do card
--
-- board_items e project_boards ja carregam o gate por policy RESTRICTIVE; board_item_checklists e
-- board_item_comments o herdam pela propagacao transitiva do EXISTS sobre o pai. As seis tabelas
-- abaixo nao tinham nenhuma das duas formas: a leitura decidia apenas por "e membro autoritativo",
-- e board_item_event_links por USING (true).
--
-- Medido por impersonacao em transacao abortada ANTES deste patch: um membro que nao enxerga o
-- board confidencial (rls_can_see_board = false) lia 25 linhas de papeis do card e 100 linhas do
-- log de ciclo de vida daquele board, enquanto cards e checklists do mesmo board devolviam 0.
--
-- Forma escolhida: o predicado explicito rls_can_see_item()/rls_can_see_board() (SECURITY DEFINER,
-- ja existentes) em vez do EXISTS transitivo, para que a barreira nao dependa de a RLS do pai
-- continuar restritiva e para que o guard possa procurar o predicado pelo nome.
--
-- A direcao de ESCRITA fica fora deste patch e registrada na issue: as policies de escrita destas
-- tabelas decidem por capacidade organizacional e nao olham o recurso (a classe do #1778).

CREATE POLICY assignments_confidential_visibility
  ON public.board_item_assignments AS RESTRICTIVE FOR SELECT
  USING (public.rls_can_see_item(item_id));

CREATE POLICY board_item_files_confidential_visibility
  ON public.board_item_files AS RESTRICTIVE FOR SELECT
  USING (public.rls_can_see_item(board_item_id));

CREATE POLICY tag_assignments_confidential_visibility
  ON public.board_item_tag_assignments AS RESTRICTIVE FOR SELECT
  USING (public.rls_can_see_item(board_item_id));

CREATE POLICY board_item_event_links_confidential_visibility
  ON public.board_item_event_links AS RESTRICTIVE FOR SELECT
  USING (public.rls_can_see_item(board_item_id));

CREATE POLICY board_lifecycle_events_confidential_visibility
  ON public.board_lifecycle_events AS RESTRICTIVE FOR SELECT
  USING (public.rls_can_see_board(board_id));

CREATE POLICY board_drive_links_confidential_visibility
  ON public.board_drive_links AS RESTRICTIVE FOR SELECT
  USING (public.rls_can_see_board(board_id));

-- A permissiva de vinculo com evento era USING (true): valia para qualquer sessao autenticada,
-- inclusive ghost user sem registro de membro. Alinha com as irmas (membro autoritativo).
DROP POLICY IF EXISTS board_item_event_links_select_authenticated ON public.board_item_event_links;
CREATE POLICY board_item_event_links_select_authenticated
  ON public.board_item_event_links FOR SELECT TO authenticated
  USING (public.rls_is_authoritative_member());
