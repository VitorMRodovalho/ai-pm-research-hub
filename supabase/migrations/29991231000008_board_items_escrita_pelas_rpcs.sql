-- =====================================================================================
-- board_items: escrita de card so pelas RPCs da plataforma
--
-- Toda criacao, alteracao e remocao de card passa pelas RPCs SECURITY DEFINER da plataforma
-- (criacao, edicao, movimento, arquivamento, fluxo da curadoria), que aplicam as regras de cada
-- campo e registram o historico. Os papeis da borda (authenticated, anon, PUBLIC) deixam de ter
-- INSERT, UPDATE e DELETE direto na tabela; as RPCs rodam como dono e nao sao afetadas.
--
-- Medido em 2026-10-09: as funcoes vivas que inserem, alteram ou removem board_items sao todas
-- SECURITY DEFINER; a tela, as Edge Functions e os testes so leem a tabela direto; os scripts de
-- importacao usam a chave de servico. As policies de escrita ficam (defesa em profundidade, caso
-- um GRANT volte).
--
-- ROLLBACK: GRANT INSERT, UPDATE, DELETE ON public.board_items TO authenticated; (nao restaura
--   grant por coluna; nenhum foi medido como necessario)
-- =====================================================================================

REVOKE INSERT, UPDATE, DELETE ON TABLE public.board_items FROM PUBLIC, anon, authenticated;

-- Privilegio de coluna concedido a parte nao cai com o REVOKE da tabela: revoga o que restar,
-- lendo o catalogo (attacl), e falha a migration se ainda sobrar escrita para a borda.
DO $$
DECLARE
  c record;
BEGIN
  FOR c IN
    SELECT a.attname AS col,
           x.privilege_type AS priv,
           CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE x.grantee::regrole::text END AS who
      FROM pg_attribute a
      CROSS JOIN LATERAL aclexplode(a.attacl) x
     WHERE a.attrelid = 'public.board_items'::regclass
       AND a.attacl IS NOT NULL
       AND NOT a.attisdropped
       AND x.privilege_type IN ('INSERT', 'UPDATE')
       AND (x.grantee = 0 OR x.grantee IN ('anon'::regrole, 'authenticated'::regrole))
  LOOP
    -- PUBLIC e palavra-chave, nao papel; regrole::text ja vem citado quando precisa.
    IF c.who = 'PUBLIC' THEN
      EXECUTE format('REVOKE %s (%I) ON public.board_items FROM PUBLIC', c.priv, c.col);
    ELSE
      EXECUTE format('REVOKE %s (%I) ON public.board_items FROM %s', c.priv, c.col, c.who);
    END IF;
  END LOOP;

  IF EXISTS (SELECT 1 FROM information_schema.role_table_grants
              WHERE table_schema = 'public' AND table_name = 'board_items'
                AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE')
                AND grantee IN ('anon', 'authenticated', 'PUBLIC'))
     OR EXISTS (SELECT 1 FROM pg_attribute a CROSS JOIN LATERAL aclexplode(a.attacl) x
                 WHERE a.attrelid = 'public.board_items'::regclass AND NOT a.attisdropped
                   AND x.privilege_type IN ('INSERT', 'UPDATE')
                   AND (x.grantee = 0 OR x.grantee IN ('anon'::regrole, 'authenticated'::regrole))) THEN
    RAISE EXCEPTION 'board_items: escrita ainda concedida a anon, authenticated ou PUBLIC';
  END IF;
END $$;
