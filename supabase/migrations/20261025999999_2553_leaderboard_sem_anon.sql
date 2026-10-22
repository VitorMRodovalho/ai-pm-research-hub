-- #2553 D4 (GP 20/10/2026): o leaderboard com nomes deixa de responder a quem não entrou.
--
-- get_public_leaderboard devolve nome, capítulo, tribo e XP de cada membro do ciclo. Desde a PR de front da #2553 o
-- /gamification do visitante lê o agregado get_public_gamification_summary, e nenhum arquivo de src chama a antiga
-- (guard 2553-ranking-do-visitante-agregado, A1). O membro usa get_gamification_leaderboard, que não muda.
--
-- A função nunca teve REVOKE de PUBLIC (gc162 só concedeu a anon e authenticated), e o EXECUTE padrão de PUBLIC
-- alcança o anon: por isso o REVOKE inclui PUBLIC. O authenticated sai também (decisão da orquestradora, 21/10/2026,
-- pela regra 6 do CLAUDE.md: anon e ghost não recebem nada de tabela com PII): o autenticado sem linha em members
-- via os mesmos nomes, e nenhum caminho autenticado chama a função (o membro usa get_gamification_leaderboard).
-- Fica só a service_role, que é o que o contrato p276 usa.
--
-- Rollback: GRANT EXECUTE ON FUNCTION public.get_public_leaderboard(integer) TO PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.get_public_leaderboard(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_leaderboard(integer) TO service_role;

NOTIFY pgrst, 'reload schema';
