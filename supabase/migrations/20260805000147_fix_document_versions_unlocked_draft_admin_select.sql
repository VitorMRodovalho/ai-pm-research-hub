-- BUG (#632 round-2, 2026-06-11): edit_document_version_draft (MCP/web governed
-- surface) NÃO consegue editar NENHUM draft unlocked. Causa-raiz provada com
-- queries ao vivo: o handler da EF faz um pré-SELECT direto
--   sb.from('document_versions').select('document_id').eq('id', …).single()
-- que roda sob RLS com o JWT do usuário. A única policy SELECT
-- (document_versions_read_published) tem um branch-2 admin
--   OR EXISTS(members m WHERE m.auth_id = auth.uid() AND can_by_member(m.id,'manage_member'))
-- que DEVERIA expor drafts unlocked a quem tem manage_member, mas colapsa na
-- enforcement do RLS (sob auth.uid() correto, só as versões LOCKED aparecem via
-- branch-1; 0 das unlocked) — provável barreira de planner com o EXISTS aninhado
-- + função SECURITY DEFINER não-leakproof. O write em si passa por
-- upsert_document_version (SECURITY DEFINER, bypassa RLS), por isso
-- propose_new_version (INSERT, sem pré-SELECT) funciona e só o EDIT quebra.
--
-- FIX (aditivo, mínimo, espelha as policies INSERT/DELETE de draft que JÁ
-- funcionam): policy SELECT dedicada que expõe drafts unlocked a manage_member
-- holders via o helper canônico rls_can('manage_member') — boolean top-level
-- (sem EXISTS aninhado), resolvendo via persons.auth_id = auth.uid() (o mesmo
-- caminho de get_my_member_record/get_my_profile, comprovadamente funcional).
-- Não toca a policy existente (branch-1 de visibilidade e locked permanecem).
-- Sem vazamento: rls_can gateia em manage_member; não-admin não ganha nada.
-- Rollback: DROP POLICY document_versions_read_unlocked_drafts_admin.

CREATE POLICY document_versions_read_unlocked_drafts_admin
  ON public.document_versions
  FOR SELECT
  TO authenticated
  USING (locked_at IS NULL AND public.rls_can('manage_member'));
