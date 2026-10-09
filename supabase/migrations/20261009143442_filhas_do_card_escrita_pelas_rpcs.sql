-- =====================================================================================
-- Tabelas do card: escrita somente pelas RPCs da plataforma
--
-- Participantes, checklist, classificacao, vinculos com eventos, historico e registro da
-- curadoria do card passam a ser escritos somente pelas RPCs da plataforma. As policies de
-- escrita permanecem.
--
-- ROLLBACK: GRANT INSERT, UPDATE, DELETE nas seis tabelas abaixo TO authenticated (nao
--   restaura grant por coluna).
-- =====================================================================================

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE
  public.board_item_assignments,
  public.board_item_checklists,
  public.board_item_tag_assignments,
  public.board_item_event_links,
  public.board_lifecycle_events,
  public.curation_review_log
  FROM PUBLIC, anon, authenticated;

DO $$
DECLARE
  v_tables regclass[] := ARRAY[
    'public.board_item_assignments'::regclass,
    'public.board_item_checklists'::regclass,
    'public.board_item_tag_assignments'::regclass,
    'public.board_item_event_links'::regclass,
    'public.board_lifecycle_events'::regclass,
    'public.curation_review_log'::regclass
  ];
  c record;
BEGIN
  -- Grant por coluna nao cai com o REVOKE da tabela: revoga o que restar, lido do catalogo.
  FOR c IN
    SELECT a.attrelid::regclass AS tbl,
           a.attname AS col,
           x.privilege_type AS priv,
           CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE x.grantee::regrole::text END AS who
      FROM pg_attribute a
      CROSS JOIN LATERAL aclexplode(a.attacl) x
     WHERE a.attrelid = ANY (v_tables)
       AND a.attacl IS NOT NULL
       AND NOT a.attisdropped
       AND x.privilege_type IN ('INSERT', 'UPDATE', 'REFERENCES')
       AND (x.grantee = 0 OR x.grantee IN ('anon'::regrole, 'authenticated'::regrole))
  LOOP
    -- PUBLIC e palavra-chave, nao papel; regrole::text ja vem citado quando precisa.
    IF c.who = 'PUBLIC' THEN
      EXECUTE format('REVOKE %s (%I) ON %s FROM PUBLIC', c.priv, c.col, c.tbl);
    ELSE
      EXECUTE format('REVOKE %s (%I) ON %s FROM %s', c.priv, c.col, c.tbl, c.who);
    END IF;
  END LOOP;

  -- Pos-condicao pelo efeito (has_*_privilege cobre heranca de papel e PUBLIC).
  IF EXISTS (
    SELECT 1
      FROM unnest(v_tables) t(tbl)
      CROSS JOIN unnest(ARRAY['public', 'anon', 'authenticated']) r(rol)
      CROSS JOIN unnest(ARRAY['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) p(priv)
     WHERE has_table_privilege(r.rol, t.tbl, p.priv)
        OR (p.priv IN ('INSERT', 'UPDATE') AND has_any_column_privilege(r.rol, t.tbl, p.priv))
  ) THEN
    RAISE EXCEPTION 'tabelas do card: escrita ainda concedida a PUBLIC, anon ou authenticated';
  END IF;
END $$;
