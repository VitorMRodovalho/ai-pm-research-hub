-- WHAT: devolve EXECUTE de `log_mcp_usage` a PUBLIC/anon, revogado uma migration antes
--       (20260903015614). A metade que a #2159 de fato entrega — a derivacao da credencial no
--       CORPO — fica.
--
-- POR QUE O REVOKE ESTAVA ERRADO, e quem me disse foi um guard, nao eu: o ratchet do #965
--       reprovou apontando que `log_mcp_usage` saiu da varredura, e a entrada dele na allowlist
--       carrega uma justificativa de #1551 que eu nao tinha lido antes de revogar:
--
--         "KEPT — the MCP EF logs through anon-key+caller-JWT and logUsage() swallows errors,
--          so revoking silently ends the audit trail instead of failing loudly."
--
--       Conferido no codigo, e o aviso procede. `createAuthenticatedClient(token?)` monta o
--       cliente com a ANON KEY e so acrescenta `Authorization` SE houver token:
--
--         createClient(SUPABASE_URL, SUPABASE_ANON_KEY,
--                      { global: { headers: token ? { Authorization: `Bearer ${token}` } : {} } })
--
--       Sem token o papel no Postgres e `anon` — e esse e exatamente o caminho que registra
--       "Not authenticated". Sao 388 chamadas de `logUsage(sb, null, ...)` na EF. Como
--       `logUsage` engole a excecao num try/catch, o revoke nao daria erro: apagaria em silencio
--       a classe de evento MAIS interessante para uma auditoria de acesso, que e a tentativa sem
--       credencial. Auditoria que emudece sozinha e pior que auditoria ausente, porque o vazio
--       passa a ler como "ninguem tentou".
--
-- O QUE ISTO NAO DESFAZ: o `COALESCE(p_auth_user_id, auth.uid())` continua. E ele e justamente o
--       que a #1551 dizia ser a saida certa — "the fix is a body derivation, not an ACL change".
--       Quando o chamador vem sem credencial, `auth.uid()` e NULL e a coluna registra NULL, que e
--       a resposta honesta: nao houve credencial apresentada.
--
-- EFEITO COLATERAL BOM, e a razao de a allowlist do #965 poder catracar para baixo mesmo com o
--       GRANT de volta: a varredura de `_audit_secdef_public_grant_drift()` exclui funcao cujo
--       corpo contenha 'auth.uid()'. Ao acrescentar o COALESCE, `log_mcp_usage` deixou a
--       varredura por CONSULTAR A SESSAO, e nao por ter perdido o privilegio. Medido depois de
--       aplicar: anon_executa = true e log_mcp_na_varredura = 0, e a pos-condicao afirma as duas
--       coisas juntas justamente para nao deixar a saida ser confundida com um revoke.
--
-- ROLLBACK: `REVOKE EXECUTE ... FROM PUBLIC, anon` — sabendo que isso reintroduz o silencio acima.
--
-- CROSS-REF: #2159, #1551, #965

GRANT EXECUTE ON FUNCTION public.log_mcp_usage(uuid, uuid, text, boolean, text, integer, text, jsonb) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.log_mcp_usage(uuid, uuid, text, boolean, text, integer, text, jsonb) TO anon;
GRANT EXECUTE ON FUNCTION public.log_mcp_usage(uuid, uuid, text, boolean, text, integer, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.log_mcp_usage(uuid, uuid, text, boolean, text, integer, text, jsonb) TO service_role;

DO $$
DECLARE
  v_sig text := 'public.log_mcp_usage(uuid, uuid, text, boolean, text, integer, text, jsonb)';
  v_tem_coalesce boolean;
  v_tem_authuid  boolean;
  v_na_varredura int;
BEGIN
  IF NOT has_function_privilege('anon', v_sig, 'EXECUTE') THEN
    RAISE EXCEPTION 'POS-CONDICAO: anon continua sem EXECUTE, e os 388 pontos que logam sem membro seguem mudos';
  END IF;
  IF NOT has_function_privilege('authenticated', v_sig, 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTROLE: authenticated perdeu EXECUTE';
  END IF;
  IF NOT has_function_privilege('service_role', v_sig, 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTROLE: service_role perdeu EXECUTE';
  END IF;

  SELECT prosrc ~ 'COALESCE\(p_auth_user_id, auth\.uid\(\)\)',
         position('auth.uid()' in prosrc) > 0
    INTO v_tem_coalesce, v_tem_authuid
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'log_mcp_usage';

  IF NOT v_tem_coalesce THEN
    RAISE EXCEPTION 'POS-CONDICAO: a derivacao no corpo, que e o que a #2159 de fato entrega, foi perdida junto com o revoke';
  END IF;

  SELECT count(*) INTO v_na_varredura
    FROM public._audit_secdef_public_grant_drift() d WHERE d.proname = 'log_mcp_usage';

  IF v_na_varredura <> 0 THEN
    RAISE EXCEPTION 'POS-CONDICAO: log_mcp_usage aparece % vez(es) na varredura, esperava 0', v_na_varredura;
  END IF;
  -- CONTROLE que impede a leitura errada: sair da varredura tem duas causas possiveis, e so uma
  -- delas e aceitavel aqui. Sem esta linha, um revoke acidental no futuro faria a pos-condicao
  -- acima passar pelo motivo oposto ao pretendido.
  IF NOT v_tem_authuid THEN
    RAISE EXCEPTION 'CONTROLE: saiu da varredura SEM ter auth.uid() no corpo, logo saiu por ACL e nao por derivacao';
  END IF;
END $$;
