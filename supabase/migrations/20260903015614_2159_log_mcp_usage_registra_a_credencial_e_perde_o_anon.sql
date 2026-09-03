-- WHAT: `log_mcp_usage` passa a registrar a credencial do chamador por conta propria, e deixa de
--       ser executavel por `anon` e por `PUBLIC`.
--
-- WHY (medido em 03/09/2026, antes de escrever qualquer linha):
--
--         mcp_usage_log ......... 2.862 linhas, 03/06 a 03/09
--           tool_name ........... 2.862 de 2.862
--           member_id ........... 2.740 de 2.862  (95,7%)
--           auth_user_id ........     0 de 2.862  <- coluna morta desde sempre
--
--       A coluna nao esta vazia por acidente de esquema: `nucleo-mcp/index.ts:312` passa
--       `p_auth_user_id: null` LITERAL, e a RPC insere o que recebe. Sao **1791** chamadas de
--       `logUsage` naquele arquivo, e o handler nao tem o `sub` em escopo (nao ha um unico
--       `getUser()` na Edge Function).
--
--       Dai a escolha de preencher AQUI e nao la: a EF propaga o Bearer do chamador
--       (`createAuthenticatedClient(token)`), entao `auth.uid()` dentro desta funcao E a
--       credencial que se quer registrar. Um COALESCE cobre os 1791 pontos sem tocar em nenhum,
--       sem deploy de EF e sem um round-trip de `getUser()` por chamada.
--
--       O COALESCE preserva o parametro: quem ja passa um valor explicito continua mandando.
--
-- POR QUE O REVOKE VEM JUNTO, e nao depois: a decisao do dono (02/09) foi ter **rastro** de quem
--       leu PII por qual credencial. Um log que `anon` pode escrever nao serve de rastro, porque
--       qualquer linha dele pode ter sido plantada. Medido antes: EXECUTE estava concedido a
--       `PUBLIC, postgres, anon, authenticated, service_role`. Encerrar a coluna morta e deixar a
--       porta aberta entregaria auditoria com aparencia de prova.
--
-- O QUE CONTINUA NULO DE PROPOSITO: as 122 chamadas sem `member_id` sao quase todas automacao
--       (109 de `sync-artia` por cron, mais 12 `event_write` e 1 `get_my_profile`). Cron roda como
--       `service_role`, onde `auth.uid()` e NULL. Isso esta certo: fluxo automatico nao tem
--       credencial de pessoa, e inventar uma seria pior que registrar a ausencia.
--
-- ROLLBACK: reaplicar o corpo anterior (o INSERT com `p_auth_user_id` cru) e
--           `GRANT EXECUTE ... TO anon, PUBLIC`.
--
-- CROSS-REF: #2159

CREATE OR REPLACE FUNCTION public.log_mcp_usage(
  p_auth_user_id uuid,
  p_member_id uuid,
  p_tool_name text,
  p_success boolean DEFAULT true,
  p_error_message text DEFAULT NULL::text,
  p_execution_ms integer DEFAULT NULL::integer,
  p_result_kind text DEFAULT 'execute'::text,
  p_response_summary jsonb DEFAULT NULL::jsonb
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  INSERT INTO mcp_usage_log (
    auth_user_id, member_id, tool_name,
    success, error_message, execution_ms, result_kind, response_summary
  )
  VALUES (
    -- #2159: o chamador explicito ganha; na ausencia dele, a credencial da sessao. A EF manda
    -- null literal em 1791 pontos, entao na pratica quem preenche e o auth.uid().
    COALESCE(p_auth_user_id, auth.uid()), p_member_id, p_tool_name,
    p_success, p_error_message, p_execution_ms, p_result_kind, p_response_summary
  );
$function$;

REVOKE EXECUTE ON FUNCTION public.log_mcp_usage(uuid, uuid, text, boolean, text, integer, text, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.log_mcp_usage(uuid, uuid, text, boolean, text, integer, text, jsonb) FROM anon;
-- Reafirmados porque o REVOKE de PUBLIC pode ter sido a unica fonte de acesso deles.
GRANT EXECUTE ON FUNCTION public.log_mcp_usage(uuid, uuid, text, boolean, text, integer, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.log_mcp_usage(uuid, uuid, text, boolean, text, integer, text, jsonb) TO service_role;

-- POS-CONDICOES. Afirmam o PRIVILEGIO via has_function_privilege, nunca a existencia da linha de
-- REVOKE: um guard que confere o texto do REVOKE fica verde com `anon` executando (#588).
DO $$
DECLARE
  v_sig  text := 'public.log_mcp_usage(uuid, uuid, text, boolean, text, integer, text, jsonb)';
  v_corpo_tem_coalesce boolean;
BEGIN
  IF has_function_privilege('anon', v_sig, 'EXECUTE') THEN
    RAISE EXCEPTION 'POS-CONDICAO: anon ainda executa log_mcp_usage';
  END IF;
  IF has_function_privilege('public', v_sig, 'EXECUTE') THEN
    RAISE EXCEPTION 'POS-CONDICAO: PUBLIC ainda executa log_mcp_usage';
  END IF;

  -- CONTROLE POSITIVO: o revoke nao pode ter derrubado quem precisa escrever. Se estes virarem
  -- false, o MCP para de logar em silencio, que e pior que a coluna morta que estamos fechando.
  IF NOT has_function_privilege('authenticated', v_sig, 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTROLE: authenticated perdeu EXECUTE em log_mcp_usage';
  END IF;
  IF NOT has_function_privilege('service_role', v_sig, 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTROLE: service_role perdeu EXECUTE em log_mcp_usage';
  END IF;

  -- A assinatura tem de continuar unica: uma sobrecarga faria a EF chamar a versao velha.
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = 'log_mcp_usage') <> 1 THEN
    RAISE EXCEPTION 'POS-CONDICAO: log_mcp_usage ficou sobrecarregada';
  END IF;

  -- E o corpo tem de ser o novo. Afirmado sobre prosrc, que e o que o Postgres executa.
  SELECT prosrc ~ 'COALESCE\(p_auth_user_id, auth\.uid\(\)\)' INTO v_corpo_tem_coalesce
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'log_mcp_usage';
  IF NOT v_corpo_tem_coalesce THEN
    RAISE EXCEPTION 'POS-CONDICAO: o corpo vivo nao tem o COALESCE';
  END IF;
END $$;
