-- ============================================================================
-- #2449 fatia A — anexo do card: leitura so para quem ve o card
-- ============================================================================
--
-- WHAT: as policies de storage do bucket board-attachments passam a exigir, alem do bucket,
--   membro autoritativo e visibilidade do quadro (rls_can_see_board), lido do primeiro segmento do
--   caminho `<board_id>/<item_id>/<arquivo>` que a tela sempre gravou.
-- WHY: o bucket e privado desde a criacao, e a tela gravava URL publica, que nao serve o arquivo
--   (400 medido em 24/09/2026, igual ao controle com caminho inexistente). A correcao da tela e
--   gerar link ASSINADO; antes disso a leitura tem de ter o gate do card, porque a policy de SELECT
--   liberava o bucket inteiro a qualquer `authenticated` (inclusive conta sem membro), e link
--   assinado de card confidencial ficaria ao alcance de qualquer conta logada.
-- MEDIDO ANTES: 40 objetos, 40 no formato `<uuid>/<uuid>/...`, 40 com quadro e card existentes e o
--   card pertencendo ao quadro, 0 em iniciativa confidencial. A regra nova nao esconde arquivo
--   legitimo nenhum.
-- CASE (e nao AND) para a ordem de avaliacao: o cast para uuid so roda quando o formato bate.
-- ROLLBACK: recriar board_attach_select/board_attach_insert com o USING/WITH CHECK antigos
--   (bucket_id = 'board-attachments').
-- CROSS-REF: #2449 · #1784 · ADR-0105
-- ============================================================================

CREATE OR REPLACE FUNCTION public._board_attachment_visible(p_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT CASE
           WHEN split_part(p_name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
             THEN public.rls_is_authoritative_member()
                  AND public.rls_can_see_board(split_part(p_name, '/', 1)::uuid)
           ELSE false
         END;
$fn$;

REVOKE ALL ON FUNCTION public._board_attachment_visible(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._board_attachment_visible(text) TO authenticated;

DROP POLICY IF EXISTS board_attach_select ON storage.objects;
CREATE POLICY board_attach_select ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'board-attachments' AND public._board_attachment_visible(name));

DROP POLICY IF EXISTS board_attach_insert ON storage.objects;
CREATE POLICY board_attach_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'board-attachments' AND public._board_attachment_visible(name));

-- Auditoria para o guard: as policies do bucket, lidas do catalogo (service_role apenas).
CREATE OR REPLACE FUNCTION public._audit_board_attachment_policies()
RETURNS TABLE (policyname name, cmd text, qual text, with_check text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT p.policyname, p.cmd, p.qual, p.with_check
    FROM pg_policies p
   WHERE p.schemaname = 'storage' AND p.tablename = 'objects'
     AND p.policyname LIKE 'board_attach_%';
$fn$;

REVOKE ALL ON FUNCTION public._audit_board_attachment_policies() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._audit_board_attachment_policies() TO service_role;
