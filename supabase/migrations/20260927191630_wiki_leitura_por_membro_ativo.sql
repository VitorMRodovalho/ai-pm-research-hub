-- #2495: o wiki passa a ser lido so por membro ativo (decisao do GP, 27/09/2026).
--
-- Antes: wiki_pages_read decidia por rls_is_member(), que so pergunta se existe cadastro com
-- aquele login. Medido em 27/09: 116 contas com login liam o wiki, 25 delas sem cadastro ativo
-- (19 alumni, 4 sem papel, 2 convidados).
--
-- Depois: o mesmo portao canonico das outras 27 politicas de leitura da fase 2 de RLS
-- (20260805000246), rls_is_authoritative_member(): cadastro ativo e papel diferente de guest e
-- institutional_auditor. Leitores passam a ser 86 contas. Isso corta tambem 5 convidados ATIVOS,
-- escolha explicita do GP (portao canonico no lugar de um helper so de is_active).
--
-- So wiki_pages muda. As outras politicas que ainda usam rls_is_member() (acervo, knowledge_*,
-- events, site_config e outras) ficam como estao: a decisao foi sobre o wiki.
--
-- Todo leitor de wiki_pages passa por esta politica: get_wiki_page, search_wiki_pages,
-- wiki_health_report e get_decision_log sao SECURITY INVOKER, e a unica SECURITY DEFINER que
-- cita a tabela (generate_institutional_export_manifest) so a lista como excluida do dump.

ALTER POLICY wiki_pages_read ON public.wiki_pages
  USING ((SELECT public.rls_is_authoritative_member()));
