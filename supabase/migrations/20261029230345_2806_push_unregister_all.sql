-- #2806: o membro apaga as inscricoes de push de TODOS os aparelhos dele de uma vez.
--
-- POR QUE: "desconectar clientes MCP" no perfil faz signOut global, que derruba a sessao em todos os aparelhos, mas
-- a inscricao de push de cada aparelho continuava valendo e o titulo dos avisos seguia aparecendo neles (aparelho
-- perdido, navegador compartilhado). unregister_push_subscription so apaga a do endpoint informado, e a lista do
-- membro nao devolve endpoint, de proposito. Decisao do GP em 28/10/2026, depois do cron do envio.
--
-- Mesmo formato de unregister_push_subscription (20261028144246): SECURITY DEFINER, so o proprio membro, sem exigir
-- membro ativo (o inativo ja tem as inscricoes apagadas pelo gatilho; aqui nao ha o que proteger).
-- ROLLBACK: DROP FUNCTION public.unregister_all_my_push_subscriptions();
CREATE OR REPLACE FUNCTION public.unregister_all_my_push_subscriptions()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_deleted integer;
BEGIN
  SELECT m.id INTO v_member_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  DELETE FROM public.push_subscriptions s WHERE s.member_id = v_member_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  RETURN jsonb_build_object('ok', true, 'deleted', v_deleted);
END;
$function$;

REVOKE ALL ON FUNCTION public.unregister_all_my_push_subscriptions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unregister_all_my_push_subscriptions() TO authenticated;

NOTIFY pgrst, 'reload schema';
