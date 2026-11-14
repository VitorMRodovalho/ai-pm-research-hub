-- #3067: o MCP entrega o CV da candidatura por link assinado curto, sem chave administrativa.
--
-- Hoje o PDF do currículo só sai pelo botão do admin (link assinado de 7 dias) ou por quem tem a chave de serviço.
-- O GP pediu em 14/11/2026 que a lane de avaliação baixe o CV pelo MCP, com a conta dele.
--
-- Esta função dá só o CAMINHO do arquivo, e só a quem já pode ler o bucket: o mesmo portão da política de storage
-- `selection_resumes_read_view_pii` (view_pii). O link assinado é criado pelo MCP com o cliente do PRÓPRIO usuário,
-- então a política de storage decide de novo. Cada chamada fica no registro de acesso a dado pessoal.

CREATE OR REPLACE FUNCTION public.get_application_resume_path(p_application_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_path text;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- O mesmo portão da leitura do bucket: sem view_pii, nem o caminho sai.
  IF NOT public.can_by_member(v_caller_id, 'view_pii'::text) THEN
    RAISE EXCEPTION 'Unauthorized: view_pii required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT sa.resume_storage_path INTO v_path FROM public.selection_applications sa WHERE sa.id = p_application_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Application not found: %', p_application_id;
  END IF;

  PERFORM public._log_application_pii_access(
    p_application_id, v_caller_id, ARRAY['resume_storage_path'], 'get_application_resume_path'
  );

  RETURN jsonb_build_object('application_id', p_application_id, 'resume_storage_path', v_path);
END;
$function$;

REVOKE ALL ON FUNCTION public.get_application_resume_path(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_application_resume_path(uuid) TO authenticated;

COMMENT ON FUNCTION public.get_application_resume_path(uuid) IS
  '#3067: o caminho do CV no bucket selection-resumes, só para quem tem view_pii (o mesmo portão da política do bucket), com registro em pii_access_log. O MCP (application_get scope=cv) cria o link assinado curto com o cliente do próprio usuário.';
