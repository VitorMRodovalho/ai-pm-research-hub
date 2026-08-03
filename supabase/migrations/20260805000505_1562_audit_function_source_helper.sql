-- #1562 — helper de introspecção que devolve o TEXTO do corpo de uma função pública.
--
-- `_audit_list_public_function_bodies()` devolve md5 + tamanho, que servem para detectar drift mas
-- não permitem afirmar nada SOBRE o conteúdo. Um guard que precisa dizer "esta cláusula não existe
-- no corpo vivo" não tem como fazê-lo, e a alternativa — comparar contra o arquivo de migration —
-- amarra o teste ao local da definição e barra refatoração legítima.
--
-- Sem este helper, o guard de #1562 cairia num catch e passaria sempre: uma defesa decorativa, que
-- é pior que nenhuma, porque dá a impressão de cobertura.
--
-- Escopo: apenas funções do schema public, apenas leitura. SECURITY DEFINER porque pg_proc.prosrc
-- não é legível por papéis sem privilégio, e a ACL abaixo limita quem chega aqui.

CREATE OR REPLACE FUNCTION public._audit_function_source(p_proname text)
 RETURNS TABLE(proname text, identity_args text, prosrc text, is_secdef boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT
    p.proname::text,
    pg_catalog.pg_get_function_identity_arguments(p.oid)::text,
    p.prosrc::text,
    p.prosecdef
  FROM pg_catalog.pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace
    AND p.prokind = 'f'
    AND p.proname = p_proname
    AND NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_depend d
      JOIN pg_catalog.pg_extension e ON e.oid = d.refobjid
      WHERE d.objid = p.oid AND d.deptype = 'e'
    )
  ORDER BY p.oid;
$function$;

-- O corpo de uma função pode conter nomes de tabela, predicados de autoridade e comentários sobre
-- o modelo de ameaça. Isso não vai para anon nem para o membro autenticado.
REVOKE ALL ON FUNCTION public._audit_function_source(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._audit_function_source(text) FROM anon;
REVOKE ALL ON FUNCTION public._audit_function_source(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public._audit_function_source(text) TO service_role;

COMMENT ON FUNCTION public._audit_function_source(text) IS
  'Read-only introspection of a public function body, for contract guards that must assert on the LIVE body instead of on a migration file. service_role only (#1562).';
