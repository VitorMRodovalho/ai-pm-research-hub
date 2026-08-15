-- #1791: o guard derivado por chave estrangeira passa a classificar tambem a forma da ESCRITA
--
-- O _audit_confidential_gate_coverage() do #1784 acha as filhas do card por FK, mas so olha policies
-- de SELECT/ALL pelo USING: ele classifica a LEITURA. Foi por isso que ele ficou verde durante todo
-- o #1784 enquanto quatro portas de INSERT seguiam abertas.
--
-- Este irmao usa o MESMO conjunto derivado por FK, e classifica a direcao de escrita:
--
--   explicito    policy RESTRICTIVE cobrindo comando de escrita, chamando rls_can_see_*
--   sem_escrita  nenhuma policy PERMISSIVE de escrita (a porta do PostgREST esta fechada)
--   no_predicado sem restritiva, mas TODA permissiva de escrita olha o recurso
--                (rls_can_for_initiative / can_manage_card_* / rls_can_see_*)
--   ausente      decide so por capacidade organizacional, sem olhar o card
--
-- Duas formas contam como cobertas de proposito. 'sem_escrita' e a porta fechada: nao ha o que
-- gatear. 'no_predicado' e a forma que board_items usa desde o #785 (rls_can_for_initiative no
-- proprio predicado permissivo), que resolve o mesmo problema sem restritiva.

CREATE OR REPLACE FUNCTION public._audit_confidential_write_gate_coverage()
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
  ),
  esc AS (
    -- uma linha por policy que alcanca comando de ESCRITA, com o predicado das duas bordas juntas:
    -- INSERT decide por WITH CHECK e DELETE por USING, entao olhar so uma perde metade dos casos.
    SELECT p.tablename::text AS tabela,
           p.permissive,
           coalesce(p.qual, '') || ' ' || coalesce(p.with_check, '') AS predicado,
           coalesce(p.qual, p.with_check, 'true') AS bruto
    FROM pg_policies p
    WHERE p.schemaname = 'public' AND p.cmd IN ('ALL', 'INSERT', 'UPDATE', 'DELETE')
  )
  SELECT f.tabela, f.aponta_para,
    CASE
      WHEN EXISTS (SELECT 1 FROM esc e
                   WHERE e.tabela = f.tabela AND e.permissive = 'RESTRICTIVE'
                     AND e.predicado ILIKE '%rls_can_see_%') THEN 'explicito'
      WHEN NOT EXISTS (SELECT 1 FROM esc e
                       WHERE e.tabela = f.tabela AND e.permissive = 'PERMISSIVE'
                         AND e.bruto <> 'false') THEN 'sem_escrita'
      WHEN NOT EXISTS (SELECT 1 FROM esc e
                       WHERE e.tabela = f.tabela AND e.permissive = 'PERMISSIVE'
                         AND e.bruto <> 'false'
                         AND e.predicado NOT ILIKE '%rls_can_see_%'
                         AND e.predicado NOT ILIKE '%rls_can_for_initiative%'
                         AND e.predicado NOT ILIKE '%can_manage_card_%') THEN 'no_predicado'
      ELSE 'ausente'
    END::text AS forma
  FROM filhas f
  ORDER BY 1;
$function$;

COMMENT ON FUNCTION public._audit_confidential_write_gate_coverage() IS
  '#1791: classifica a forma do gate de visibilidade confidencial na direcao de ESCRITA, sobre as '
  'filhas de board_items/project_boards derivadas por chave estrangeira. Irmao do '
  '_audit_confidential_gate_coverage() do #1784, que classifica a leitura.';

-- CREATE FUNCTION nasce com EXECUTE para PUBLIC: helper de auditoria nao se publica para anon.
REVOKE ALL ON FUNCTION public._audit_confidential_write_gate_coverage() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._audit_confidential_write_gate_coverage() TO service_role;
