-- #648 follow-up (council security review) — corrige o ESCOPO da policy de leitura do
-- bucket `certificates` introduzida em 20260805000150.
--
-- Achado (security-engineer, MEDIUM): a policy original concedia a TODO `chapter_board`
-- SELECT em TODOS os PDFs de certificado de TODOS os capítulos — mais amplo do que o gate
-- canônico `get_all_certificates` (is_superadmin OR manager/deputy OR can_by_member(curate_content),
-- SEM `chapter_board`) e do que `get_volunteer_agreement_status` (chapter-scoped). Um membro
-- chapter_board do capítulo A poderia gerar signed URL do PDF de um membro do capítulo B.
--
-- Correção: branch admin = paridade EXATA com get_all_certificates; remove o bare chapter_board.
-- (Quem for negado aqui ainda baixa via fallback de rebuild imutável do download — Camada 1 —
-- então não há regressão funcional, só fechamento do over-grant.) + LIMIT 1 defensivo no
-- subselect do dono (guard contra regressão futura de unicidade de members.auth_id).
--
-- Rollback: DROP POLICY "certificates_read_owner_or_admin" ON storage.objects;
--           (a versão 20260805000150 pode ser re-CREATE manualmente se necessário).

DROP POLICY IF EXISTS "certificates_read_owner_or_admin" ON storage.objects;
CREATE POLICY "certificates_read_owner_or_admin" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'certificates'
    AND (
      (storage.foldername(name))[1] = (SELECT m.id::text FROM public.members m WHERE m.auth_id = auth.uid() LIMIT 1)
      OR EXISTS (
        SELECT 1 FROM public.members m
        WHERE m.auth_id = auth.uid()
          AND (
            m.is_superadmin
            OR m.operational_role IN ('manager', 'deputy_manager')
            OR public.can_by_member(m.id, 'curate_content')
          )
      )
    )
  );
