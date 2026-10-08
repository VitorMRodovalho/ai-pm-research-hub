-- #2585 (ajuste, decisao do GP de 08/10/2026): o aviso de "Ja me filiei" vai so para o administrador da plataforma
-- (manage_platform), como no desenho de 06/10. E ele quem atualiza o JSON da VEP; a ingestao do pmi-vep-sync grava a
-- filiacao (member_chapter_affiliations, pmi_vep) e o portao abre pelo caminho A. A designacao filiacao_director saiu
-- dos destinatarios.

CREATE OR REPLACE FUNCTION public.request_affiliation_recheck()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_inicio timestamptz := date_trunc('day', now() AT TIME ZONE 'America/Sao_Paulo') AT TIME ZONE 'America/Sao_Paulo';
  v_novos int;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, is_read, delivery_mode)
  SELECT m.id,
         'system_alert',
         'Pedido de verificação de filiação',
         'Uma pessoa em pré-onboarding informou que se filiou a um capítulo participante. Atualize o JSON da VEP: '
         'a ingestão grava a filiação e o Termo de Voluntariado abre sozinho. Se a filiação não aparecer na VEP, '
         'registre a verificação na fila de filiação.',
         '/admin/filiacao',
         'affiliation_recheck',
         v_member_id,
         false,
         'transactional_immediate'
  FROM public.members m
  WHERE m.is_active IS TRUE
    AND m.id <> v_member_id
    AND public.can_by_member(m.id, 'manage_platform')
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.recipient_id = m.id AND n.source_type = 'affiliation_recheck'
        AND n.source_id = v_member_id AND n.created_at >= v_inicio
    );
  GET DIAGNOSTICS v_novos = ROW_COUNT;
  RETURN jsonb_build_object('success', true, 'notified', v_novos);
END;
$function$;

NOTIFY pgrst, 'reload schema';
