-- #1791: o gate de visibilidade confidencial (ADR-0105 / #785) passa a valer na direcao de ESCRITA
--
-- O #1784 fechou a LEITURA das tabelas-filhas do card e registrou, no proprio cabecalho, que a
-- direcao de escrita ficava fora daquele patch. As policies de escrita destas tabelas decidem por
-- capacidade organizacional e nao olham o recurso: e a classe que o #1778 fechou no checklist.
--
-- Medido por impersonacao em transacao abortada (15/08/2026), com sujeito que TEM a capacidade e
-- NAO enxerga o board confidencial (nem por engajamento, nem por superadmin, nem por
-- manage_platform):
--
--   | porta                                             | antes  |
--   |---------------------------------------------------|--------|
--   | INSERT de papel no card confidencial              | PASSOU |
--   | INSERT de atividade no card confidencial          | PASSOU |
--   | INSERT de tag no card confidencial                | PASSOU |
--   | INSERT no log de ciclo de vida do board           | PASSOU |
--   | leitura das mesmas linhas (controle, #1784)       |      0 |
--
-- Populacao que satisfaz o predicado de escrita e nao enxerga: 66 por write_board, 12 por write.
--
-- UPDATE e DELETE de linha existente ja estavam barrados, mas por efeito INDIRETO: o Postgres aplica
-- as policies de SELECT ao UPDATE/DELETE que referencia colunas, e o gate de leitura do #1784 esconde
-- a linha-alvo. O controle inverso na MESMA transacao mostra que a autoridade existe: o mesmo
-- sujeito apagou 1 papel de um card nao-confidencial, logo o zero veio do gate, nao de falta de
-- permissao. O INSERT escapava justamente porque nao le linha nenhuma.
--
-- Forma: a MESMA policy RESTRICTIVE do #1784, promovida de FOR SELECT para FOR ALL com WITH CHECK.
-- Uma policy por tabela cobre as duas direcoes, e a barreira de escrita deixa de depender de um
-- efeito colateral da barreira de leitura.
--
-- Raio de acao: fora da iniciativa confidencial o predicado e verdadeiro por construcao
-- (rls_can_see_initiative devolve true quando a iniciativa nao e confidencial ou e nula), entao
-- nenhum escritor legitimo perde acesso. Os 3 engajamentos autoritativos na confidencial sao todos
-- de superadmin, que passa pelo proprio helper.
--
-- SECURITY DEFINER continua contornando isto de proposito (#1778): as RPCs que administram o card
-- carregam o gate DENTRO, em can_manage_card_checklist. Esta policy fecha a porta do PostgREST.

-- papeis do card (autor / contribuidor)
DROP POLICY IF EXISTS assignments_confidential_visibility ON public.board_item_assignments;
CREATE POLICY assignments_confidential_visibility
  ON public.board_item_assignments AS RESTRICTIVE FOR ALL
  USING (public.rls_can_see_item(item_id))
  WITH CHECK (public.rls_can_see_item(item_id));

-- tags do card
DROP POLICY IF EXISTS tag_assignments_confidential_visibility ON public.board_item_tag_assignments;
CREATE POLICY tag_assignments_confidential_visibility
  ON public.board_item_tag_assignments AS RESTRICTIVE FOR ALL
  USING (public.rls_can_see_item(board_item_id))
  WITH CHECK (public.rls_can_see_item(board_item_id));

-- atividades do card (a tabela que o #1778 tratou pela RPC; a porta do PostgREST seguia aberta)
-- Aqui o gate deixa de ser o EXISTS transitivo sobre o pai e passa a ser o predicado explicito: a
-- barreira nao pode depender de a RLS de board_items continuar restritiva.
DROP POLICY IF EXISTS checklists_confidential_visibility ON public.board_item_checklists;
CREATE POLICY checklists_confidential_visibility
  ON public.board_item_checklists AS RESTRICTIVE FOR ALL
  USING (public.rls_can_see_item(board_item_id))
  WITH CHECK (public.rls_can_see_item(board_item_id));

-- vinculo do card com evento
DROP POLICY IF EXISTS board_item_event_links_confidential_visibility ON public.board_item_event_links;
CREATE POLICY board_item_event_links_confidential_visibility
  ON public.board_item_event_links AS RESTRICTIVE FOR ALL
  USING (public.rls_can_see_item(board_item_id))
  WITH CHECK (public.rls_can_see_item(board_item_id));

-- log de ciclo de vida. As DUAS pernas: board_id e nulavel (o CHECK da tabela exige board_id OU
-- item_id), e hoje nenhuma das 3336 linhas tem board_id nulo, contencao por DADO, nao por
-- estrutura. Sem a perna de item_id, uma linha futura com board_id nulo apontando para card
-- confidencial passaria, porque rls_can_see_board(NULL) e verdadeiro por construcao.
DROP POLICY IF EXISTS board_lifecycle_events_confidential_visibility ON public.board_lifecycle_events;
CREATE POLICY board_lifecycle_events_confidential_visibility
  ON public.board_lifecycle_events AS RESTRICTIVE FOR ALL
  USING (public.rls_can_see_board(board_id) AND public.rls_can_see_item(item_id))
  WITH CHECK (public.rls_can_see_board(board_id) AND public.rls_can_see_item(item_id));
