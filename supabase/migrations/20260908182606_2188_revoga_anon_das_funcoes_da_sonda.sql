-- #2188 — `REVOKE ... FROM PUBLIC` nao tira o EXECUTE concedido nominalmente a `anon`.
--
-- O ACHADO, medido DEPOIS de aplicar a onda e reler o catalogo. As duas funcoes novas estavam com
-- `{postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}`, apesar
-- do `REVOKE ALL ... FROM PUBLIC` que a migration original ja trazia. O Supabase concede EXECUTE
-- nominalmente a `anon` e `authenticated` em funcao nova do schema public (default privileges), e
-- revogar de PUBLIC nao alcanca uma concessao nominal.
--
-- POR QUE IMPORTAVA, e nao era cosmetico. Na ESCRITA isso era exploravel: `anon` podia gravar
-- sondagem arbitraria, e uma linha `ok=true, days_open=0` forjada para a URL de um avaliador e
-- exatamente o que a fase 2 vai ler para decidir se ele sai do rodizio de entrevistas. O caminho
-- de escrita e o endpoint interno com service_role; ninguem mais precisa dele.
--
-- A pos-condicao NAO e o texto do REVOKE, e sim o privilegio: `has_function_privilege('anon', oid,
-- 'EXECUTE')` = false nas duas (medido em 08/09 depois desta aplicacao). Guard afirmando a LINHA do
-- REVOKE em vez do privilegio ja passou por meses afirmando o contrario do real (#883).

REVOKE ALL ON FUNCTION public.record_interview_agenda_probe(text, integer, integer, date, date, boolean, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_interview_agenda_probe(text, integer, integer, date, date, boolean, text) TO service_role;

-- O leitor continua acessivel a `authenticated` (a UI de admin o chamara), mas nao a `anon`. O gate
-- interno de manage_member ja barrava; agora a superficie tambem barra. Defesa em profundidade, e
-- um `anon` que executa uma SECURITY DEFINER ja e um alvo de sondagem por si so.
REVOKE ALL ON FUNCTION public.get_interview_agenda_health() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_interview_agenda_health() TO authenticated, service_role;
