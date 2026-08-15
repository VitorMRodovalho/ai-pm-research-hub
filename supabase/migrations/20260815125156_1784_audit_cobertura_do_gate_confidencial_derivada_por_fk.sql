-- #1784 — o guard do gate confidencial deixa de ser uma LISTA e passa a ser DERIVADO do catalogo.
--
-- O invariante AJ do #785 PR-2 enumera 8 tabelas. Uma lista so cobre o que alguem lembrou de
-- escrever nela: as seis tabelas-filhas corrigidas neste patch nao estavam la, e uma tabela-filha
-- criada amanha tambem nao estaria. Este helper deriva o conjunto por CHAVE ESTRANGEIRA para
-- board_items / project_boards e classifica a forma do gate em cada uma.
--
-- Formas aceitas (as tres barram o mesmo):
--   explicito   — policy RESTRICTIVE cuja USING chama rls_can_see_* (a forma deste patch)
--   transitivo  — o predicado passa pelo pai (board_items/project_boards), que carrega o gate;
--                 vale por RESTRICTIVE (board_item_checklists) ou por ser a UNICA leitura
--                 permissiva possivel (board_item_comments)
--   sem_leitura — a tabela nao tem caminho de leitura permissivo (rpc_only_deny_all ou nenhuma
--                 policy de SELECT): mais fechado que o gate
--   ausente     — nenhuma das formas acima
--
-- Consumido por tests/contracts/1784-gate-confidencial-tabelas-filhas.test.mjs, que trava as
-- tabelas-filhas do proprio card em nao-'ausente' e mantem as demais numa linha de base que so
-- pode encolher.

CREATE OR REPLACE FUNCTION public._audit_confidential_gate_coverage()
RETURNS TABLE(tabela text, aponta_para text, forma text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH filhas AS (
    SELECT DISTINCT c.relname::text AS tabela, cf.relname::text AS aponta_para
    FROM pg_constraint k
    JOIN pg_class c  ON c.oid = k.conrelid
    JOIN pg_class cf ON cf.oid = k.confrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE k.contype = 'f' AND n.nspname = 'public' AND c.relkind = 'r'
      AND cf.relname IN ('board_items', 'project_boards')
      AND c.relname <> cf.relname
  )
  SELECT f.tabela, f.aponta_para,
    CASE
      WHEN EXISTS (SELECT 1 FROM pg_policies p
                   WHERE p.schemaname = 'public' AND p.tablename = f.tabela
                     AND p.permissive = 'RESTRICTIVE' AND p.cmd IN ('SELECT', 'ALL')
                     AND p.qual ILIKE '%rls_can_see_%') THEN 'explicito'
      WHEN EXISTS (SELECT 1 FROM pg_policies p
                   WHERE p.schemaname = 'public' AND p.tablename = f.tabela
                     AND p.permissive = 'RESTRICTIVE' AND p.cmd IN ('SELECT', 'ALL')
                     AND (p.qual ILIKE '%board_items%' OR p.qual ILIKE '%project_boards%')) THEN 'transitivo'
      WHEN NOT EXISTS (SELECT 1 FROM pg_policies p
                       WHERE p.schemaname = 'public' AND p.tablename = f.tabela
                         AND p.permissive = 'PERMISSIVE' AND p.cmd IN ('SELECT', 'ALL')
                         AND coalesce(p.qual, 'true') <> 'false') THEN 'sem_leitura'
      WHEN NOT EXISTS (SELECT 1 FROM pg_policies p
                       WHERE p.schemaname = 'public' AND p.tablename = f.tabela
                         AND p.permissive = 'PERMISSIVE' AND p.cmd IN ('SELECT', 'ALL')
                         AND coalesce(p.qual, 'true') <> 'false'
                         AND p.qual NOT ILIKE '%board_items%'
                         AND p.qual NOT ILIKE '%project_boards%') THEN 'transitivo'
      ELSE 'ausente'
    END::text AS forma
  FROM filhas f
  ORDER BY 1;
$function$;

COMMENT ON FUNCTION public._audit_confidential_gate_coverage() IS
  '#1784 — cobertura do gate de visibilidade confidencial (ADR-0105/#785) nas tabelas-filhas de board_items/project_boards, derivada por FK em vez de lista. Consumido por contrato; service_role apenas.';

REVOKE ALL ON FUNCTION public._audit_confidential_gate_coverage() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._audit_confidential_gate_coverage() TO service_role;
