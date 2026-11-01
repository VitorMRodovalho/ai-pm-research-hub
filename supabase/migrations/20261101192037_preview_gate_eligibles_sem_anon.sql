-- preview_gate_eligibles(text, uuid) deixa de ser executavel por anon.
--
-- A funcao e SECURITY DEFINER e nao tem portao de sessao. Nenhuma migration declarava o ACL dela,
-- entao valia o default do projeto: EXECUTE para PUBLIC, anon, authenticated e service_role. O unico
-- consumidor, src/components/governance/DocumentVersionEditor.tsx, chama com sessao.
--
--   * REVOKE ALL e o idioma do repo para funcao: em funcao, o unico privilegio e EXECUTE.
--   * O REVOKE de PUBLIC sozinho nao fecha: o default do projeto da EXECUTE a anon explicitamente.
--   * O GRANT a authenticated e service_role repete o que eles ja tem, para o ACL ficar declarado.
--   * O corpo da funcao nao muda.
--
-- Rollback: GRANT EXECUTE ON FUNCTION public.preview_gate_eligibles(text, uuid) TO PUBLIC, anon;

REVOKE ALL ON FUNCTION public.preview_gate_eligibles(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.preview_gate_eligibles(text, uuid) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
