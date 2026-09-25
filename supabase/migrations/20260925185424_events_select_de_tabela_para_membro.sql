-- Corrige 20260925183649_rls_leitura_restrita_a_membro no eixo de events.
--
-- O grant por coluna valia para anon E authenticated, mas o nucleo-mcp le a ata direto pelo
-- PostgREST com o JWT do membro (meeting_minutes e o contexto de iniciativa), e grant por coluna
-- nao distingue membro de nao-membro. Entao:
--   * authenticated volta a ter SELECT de tabela em events (o membro le a ata como antes);
--   * events_read_authenticated passa a exigir membro: o autenticado sem linha em members deixa de
--     ler as linhas geral/webinar (continua vendo-as deslogado, como anon);
--   * anon segue com o SELECT por coluna da migration anterior, sem ata, notas, historico de
--     edicao da ata e participantes externos.
GRANT SELECT ON public.events TO authenticated;

DROP POLICY IF EXISTS events_read_authenticated ON public.events;
CREATE POLICY events_read_authenticated ON public.events
  FOR SELECT TO authenticated
  USING ((SELECT public.rls_is_member()));
