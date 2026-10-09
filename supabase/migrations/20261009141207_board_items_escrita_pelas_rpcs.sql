-- =====================================================================================
-- board_items: escrita de card so pelas RPCs da plataforma
--
-- Criacao, alteracao e remocao de card passam a ser feitas somente pelas RPCs da plataforma. As
-- policies de escrita permanecem.
--
-- ROLLBACK: GRANT INSERT, UPDATE, DELETE ON public.board_items TO authenticated; (nao restaura
--   grant por coluna nem TRUNCATE/REFERENCES/TRIGGER; nenhum foi medido como necessario)
-- =====================================================================================

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE public.board_items FROM PUBLIC, anon, authenticated;

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
       AND x.privilege_type IN ('INSERT', 'UPDATE', 'REFERENCES')
       AND (x.grantee = 0 OR x.grantee IN ('anon'::regrole, 'authenticated'::regrole))
  LOOP
    -- PUBLIC e palavra-chave, nao papel; regrole::text ja vem citado quando precisa.
    IF c.who = 'PUBLIC' THEN
      EXECUTE format('REVOKE %s (%I) ON public.board_items FROM PUBLIC', c.priv, c.col);
    ELSE
      EXECUTE format('REVOKE %s (%I) ON public.board_items FROM %s', c.priv, c.col, c.who);
    END IF;
  END LOOP;

  -- Pos-condicao pelo EFEITO (has_table_privilege cobre heranca de papel e PUBLIC).
  IF EXISTS (SELECT 1
               FROM unnest(ARRAY['public', 'anon', 'authenticated']) r(rol)
               CROSS JOIN unnest(ARRAY['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) p(priv)
              WHERE has_table_privilege(r.rol, 'public.board_items', p.priv)
                 OR (p.priv IN ('INSERT', 'UPDATE')
                     AND has_any_column_privilege(r.rol, 'public.board_items', p.priv))) THEN
    RAISE EXCEPTION 'board_items: escrita ainda concedida a PUBLIC, anon ou authenticated';
  END IF;
END $$;
