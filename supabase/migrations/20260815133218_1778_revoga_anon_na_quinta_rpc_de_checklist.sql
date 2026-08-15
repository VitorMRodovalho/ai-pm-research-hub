-- #1778 — a quinta RPC da familia tinha a mesma deriva de grant.
--
-- complete_checklist_item nao teve o gate alterado (a regra dela ja e mais larga: dono da
-- atividade ou engajado na iniciativa), mas nasceu com EXECUTE para PUBLIC como as outras
-- quatro. Fecha por dentro, e ainda assim e uma RPC de ESCRITA alcancavel por PostgREST com
-- a chave anon. Mesma classe, mesmo fechamento.

REVOKE ALL ON FUNCTION public.complete_checklist_item(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_checklist_item(uuid, boolean) TO authenticated, service_role;
