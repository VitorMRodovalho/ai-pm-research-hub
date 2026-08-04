-- #1595 — helper de introspecção por CLASSE: quais funções públicas casam um padrão no corpo.
--
-- O aceite da #1595 pede um guard de classe, não por nome: "nenhuma RPC viva de `public` contém
-- `calendar.app.google`". Um guard por nome só protege as três funções que já se sabe que
-- entregavam o link cru — e o defeito da #1595 é justamente que uma QUARTA porta nasceu sem
-- ninguém notar. Um guard que enumera nomes não impede a quinta.
--
-- Os dois helpers existentes não servem para isso:
--   • `_audit_list_public_function_bodies()` devolve md5 + tamanho, nunca o texto — dá para detectar
--     drift, não para afirmar sobre o conteúdo.
--   • `_audit_function_source(p_proname)` devolve o texto, mas de UMA função por chamada. Varrer o
--     schema inteiro por ele seria mais de mil round-trips por corrida de teste.
--
-- Devolve só a identificação (nome + argumentos), nunca o corpo: para um guard de ausência, a lista
-- de infratores é a resposta inteira, e o corpo carrega predicado de autoridade e nome de tabela.
--
-- Escopo: apenas funções do schema public, apenas leitura, funções de extensão excluídas.

CREATE OR REPLACE FUNCTION public._audit_functions_matching(p_pattern text)
 RETURNS TABLE(proname text, identity_args text, is_secdef boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT
    p.proname::text,
    pg_catalog.pg_get_function_identity_arguments(p.oid)::text,
    p.prosecdef
  FROM pg_catalog.pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace
    AND p.prokind = 'f'
    AND p.prosrc ~ p_pattern
    AND NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_depend d
      JOIN pg_catalog.pg_extension e ON e.oid = d.refobjid
      WHERE d.objid = p.oid AND d.deptype = 'e'
    )
  ORDER BY p.proname, p.oid;
$function$;

-- Saber QUAIS funções mencionam um padrão já é informação de superfície de ataque. Fica em
-- service_role, como os outros dois helpers de auditoria.
-- ⚠️ `FROM PUBLIC` sozinho não fecha nada neste projeto: o `ALTER DEFAULT PRIVILEGES` concede
-- EXECUTE a anon e authenticated NOMINALMENTE, e revogar de PUBLIC remove um privilégio que PUBLIC
-- nunca teve. Os papéis têm de ser nomeados.
REVOKE ALL ON FUNCTION public._audit_functions_matching(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._audit_functions_matching(text) TO service_role;

COMMENT ON FUNCTION public._audit_functions_matching(text) IS
  'Read-only class-level introspection: which public functions match a regex in their body. Backs '
  'contract guards that must assert absence across the WHOLE schema instead of a named list (#1595). '
  'Returns identity only, never the body. service_role only.';

NOTIFY pgrst, 'reload schema';
