-- #2974 (d): registro do primeiro download do certificado pela própria pessoa.
--
-- As páginas /certificates e /gamification chamam record_certificate_download({ p_cert_id }) antes de gerar o PDF,
-- e a função não existia: a chamada voltava erro calada e certificates.downloaded_at nunca foi escrita.
--
-- Decisão do GP em 04/11/2026: criar a função. Só a própria pessoa registra, e só o primeiro download.
--
-- record_certificate_download(p_cert_id uuid):
--   - sem membro na sessão: {error: not_authenticated};
--   - certificado inexistente ou de outra pessoa: {error: not_found}, a mesma resposta, para não revelar que o id
--     existe;
--   - grava downloaded_at = now() só se estiver nula; a condição vai no próprio UPDATE, então dois cliques ao mesmo
--     tempo gravam uma vez;
--   - não mexe em updated_at: baixar não muda o certificado;
--   - devolve {success: true, recorded: true} no primeiro download e {success: true, recorded: false} depois.
--
-- Rollback: DROP FUNCTION public.record_certificate_download(uuid). As linhas com downloaded_at ficam, como fato.

CREATE OR REPLACE FUNCTION public.record_certificate_download(p_cert_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_owner_id  uuid;
  v_rows      integer;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  SELECT c.member_id INTO v_owner_id FROM public.certificates c WHERE c.id = p_cert_id;
  IF v_owner_id IS NULL OR v_owner_id IS DISTINCT FROM v_caller_id THEN
    RETURN jsonb_build_object('error', 'not_found');
  END IF;

  UPDATE public.certificates
     SET downloaded_at = now()
   WHERE id = p_cert_id
     AND member_id = v_caller_id
     AND downloaded_at IS NULL;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  RETURN jsonb_build_object('success', true, 'recorded', v_rows = 1);
END;
$function$;
REVOKE ALL ON FUNCTION public.record_certificate_download(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_certificate_download(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ── pós-condição ─────────────────────────────────────────────────────────────
DO $postcondition$
BEGIN
  IF has_function_privilege('anon', 'public.record_certificate_download(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.record_certificate_download(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '#2974 (d): privilégio fora do esperado';
  END IF;
  -- a migration não tem sessão: a função recusa sem gravar nada
  IF (public.record_certificate_download(gen_random_uuid())->>'error') IS DISTINCT FROM 'not_authenticated' THEN
    RAISE EXCEPTION '#2974 (d): a função não recusou chamada sem sessão';
  END IF;
END
$postcondition$;
