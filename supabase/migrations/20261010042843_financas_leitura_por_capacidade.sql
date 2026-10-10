-- =====================================================================================
-- Tabelas de financas: leitura direta exige a capacidade de financas (view_finance)
--
-- cost_entries, revenue_entries e sustainability_kpi_targets passam a ser lidas direto so por
-- quem tem view_finance na organizacao (ou superadmin), a mesma regra das RPCs de financas. A
-- escrita continua somente pelas RPCs da plataforma.
--
-- ROLLBACK: recriar as policies *_select_org da migration 20260520000000 e
--   GRANT SELECT nas tres tabelas TO authenticated (a escrita nao volta).
-- =====================================================================================

ALTER TABLE public.cost_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.revenue_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sustainability_kpi_targets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cost_entries_select_org ON public.cost_entries;
DROP POLICY IF EXISTS cost_entries_select_finance ON public.cost_entries;
CREATE POLICY cost_entries_select_finance ON public.cost_entries
  FOR SELECT TO authenticated
  USING (public.rls_is_superadmin()
         OR (organization_id = public.auth_org() AND public.rls_can('view_finance')));

DROP POLICY IF EXISTS revenue_entries_select_org ON public.revenue_entries;
DROP POLICY IF EXISTS revenue_entries_select_finance ON public.revenue_entries;
CREATE POLICY revenue_entries_select_finance ON public.revenue_entries
  FOR SELECT TO authenticated
  USING (public.rls_is_superadmin()
         OR (organization_id = public.auth_org() AND public.rls_can('view_finance')));

DROP POLICY IF EXISTS sustainability_kpi_targets_select_org ON public.sustainability_kpi_targets;
DROP POLICY IF EXISTS sustainability_kpi_targets_select_finance ON public.sustainability_kpi_targets;
CREATE POLICY sustainability_kpi_targets_select_finance ON public.sustainability_kpi_targets
  FOR SELECT TO authenticated
  USING (public.rls_is_superadmin()
         OR (organization_id = public.auth_org() AND public.rls_can('view_finance')));

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE
  public.cost_entries, public.revenue_entries, public.sustainability_kpi_targets
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE
  public.cost_entries, public.revenue_entries, public.sustainability_kpi_targets
  FROM anon;

DO $$
DECLARE
  v_tables regclass[] := ARRAY[
    'public.cost_entries'::regclass,
    'public.revenue_entries'::regclass,
    'public.sustainability_kpi_targets'::regclass
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
    IF c.who = 'PUBLIC' THEN
      EXECUTE format('REVOKE %s (%I) ON %s FROM PUBLIC', c.priv, c.col, c.tbl);
    ELSE
      EXECUTE format('REVOKE %s (%I) ON %s FROM %s', c.priv, c.col, c.tbl, c.who);
    END IF;
  END LOOP;

  -- Pos-condicao 1, pelo efeito: a borda nao escreve e anon nao le.
  IF EXISTS (
    SELECT 1
      FROM unnest(v_tables) t(tbl)
      CROSS JOIN unnest(ARRAY['public', 'anon', 'authenticated']) r(rol)
      CROSS JOIN unnest(ARRAY['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) p(priv)
     WHERE has_table_privilege(r.rol, t.tbl, p.priv)
        OR (p.priv IN ('INSERT', 'UPDATE') AND has_any_column_privilege(r.rol, t.tbl, p.priv))
  ) OR EXISTS (
    SELECT 1 FROM unnest(v_tables) t(tbl) WHERE has_table_privilege('anon', t.tbl, 'SELECT')
  ) THEN
    RAISE EXCEPTION 'financas: escrita da borda ou leitura anonima ainda concedida';
  END IF;

  -- Pos-condicao 2: RLS ligada e toda policy permissiva de leitura exige view_finance.
  IF EXISTS (SELECT 1 FROM pg_class WHERE oid = ANY (v_tables) AND NOT relrowsecurity)
     OR EXISTS (
       SELECT 1 FROM pg_policies p
        WHERE p.schemaname = 'public'
          AND p.tablename IN ('cost_entries', 'revenue_entries', 'sustainability_kpi_targets')
          AND p.permissive = 'PERMISSIVE'
          AND p.cmd IN ('SELECT', 'ALL')
          AND coalesce(p.qual, '') NOT LIKE '%view_finance%')
     OR (SELECT count(*) FROM pg_policies p
          WHERE p.schemaname = 'public'
            AND p.tablename IN ('cost_entries', 'revenue_entries', 'sustainability_kpi_targets')
            AND p.cmd = 'SELECT' AND p.qual LIKE '%view_finance%') <> 3 THEN
    RAISE EXCEPTION 'financas: policy de leitura sem a capacidade de financas';
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
