-- webinar_audience_snapshots: a leitura fica restrita a membro, como o resto de public desde
-- 20260925183649 (rls_leitura_restrita_a_membro). A política de 20261114030747 usava USING (true) para
-- authenticated, e um usuário autenticado sem linha em members lia a tabela; o guard
-- leitura-por-nao-membro-derivada-do-catalogo reprovou no CI da PR #3059.
-- Rollback: ALTER POLICY ... USING (true).

ALTER POLICY was_select_authenticated ON public.webinar_audience_snapshots
  USING ((SELECT public.rls_is_member()));
