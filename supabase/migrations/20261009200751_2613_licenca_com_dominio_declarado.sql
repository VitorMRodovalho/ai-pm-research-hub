-- #2613 (seguimento) -- licenca da obra e da colecao com dominio declarado (#1822)
--
-- 20261009193146_2613_biblioteca_pagina_por_obra criou public_publications.license e
-- publication_collections.license com CHECK de FORMATO (regex). O ratchet do #1822 conta coluna de
-- estado sem dominio declarado, e 'license' ja tem dominio em wiki_pages; as duas colunas novas
-- subiram a base de 56 para 58.
--
-- O dominio passa a ser o mesmo de wiki_pages.license. Dados vivos (09/10/2026): 1 obra e 1 colecao
-- com 'CC-BY-4.0', o resto NULL; todos cabem no dominio.
--
-- ROLLBACK: recriar os CHECKs de formato de 20261009193146.

ALTER TABLE public.public_publications DROP CONSTRAINT IF EXISTS public_publications_license_format;
ALTER TABLE public.public_publications ADD CONSTRAINT public_publications_license_format
  CHECK (license IS NULL OR license = ANY (ARRAY['CC-BY-4.0', 'CC-BY-SA-4.0', 'MIT', 'proprietary']));

ALTER TABLE public.publication_collections DROP CONSTRAINT IF EXISTS publication_collections_license_check;
ALTER TABLE public.publication_collections DROP CONSTRAINT IF EXISTS publication_collections_license_format;
ALTER TABLE public.publication_collections ADD CONSTRAINT publication_collections_license_format
  CHECK (license IS NULL OR license = ANY (ARRAY['CC-BY-4.0', 'CC-BY-SA-4.0', 'MIT', 'proprietary']));

DO $postcondition$
DECLARE
  v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM pg_catalog.pg_constraint c
  JOIN pg_catalog.pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
  WHERE c.contype = 'c' AND a.attname = 'license'
    AND c.conrelid IN ('public.public_publications'::regclass, 'public.publication_collections'::regclass);
  IF v_n <> 2 THEN RAISE EXCEPTION '#2613: esperado 1 CHECK de licenca por tabela, achados %', v_n; END IF;

  SELECT count(*) INTO v_n FROM public._audit_undeclared_state_domain() r
  WHERE r.tabela IN ('public_publications', 'publication_collections') AND r.coluna = 'license' AND r.sem_dominio_declarado;
  IF v_n <> 0 THEN RAISE EXCEPTION '#2613: % coluna(s) license ainda sem dominio declarado', v_n; END IF;
END
$postcondition$;
