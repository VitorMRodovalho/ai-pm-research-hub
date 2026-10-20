-- #2749 (decisão do GP, 19/10/2026): o ranking da trilha na home passou a exigir sessão (#2748). Esconder a seção
-- não fechava a fonte: get_public_trail_ranking seguia com EXECUTE para anon e entregava nome, foto e percentual a
-- qualquer um com a chave pública. Esta migration tira o acesso de anon. authenticated (home com sessão, MCP) e
-- service_role continuam. O grant a anon vinha da 20260805000493 (#1527), que o mantinha aberto como feed público.
-- Rollback: GRANT EXECUTE ON FUNCTION public.get_public_trail_ranking() TO anon;
REVOKE EXECUTE ON FUNCTION public.get_public_trail_ranking() FROM anon;
