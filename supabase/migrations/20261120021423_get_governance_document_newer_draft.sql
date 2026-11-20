-- Documento de governança (GP 19/11/2026): a página do documento abre a versão vigente (a última lacrada) e não dizia
-- que existe uma versão mais nova em revisão. Um revisor jurídico trabalhou sobre a vigente de setembro enquanto a v1
-- de 01/11 só aparecia pelo link direto. Esta função diz à página se há uma versão mais nova, ainda não lacrada, que
-- QUEM CHAMA pode abrir. A autorização não é reescrita aqui: ela delega a get_governance_document_draft_preview, a mesma
-- que decide quem abre a prévia, e só devolve id e rótulo da versão, nunca o conteúdo.
-- Rollback: DROP FUNCTION public.get_governance_document_newer_draft(uuid);
CREATE OR REPLACE FUNCTION public.get_governance_document_newer_draft(p_document_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_current_number integer;
  v_newer record;
  v_preview jsonb;
BEGIN
  SELECT dv.version_number INTO v_current_number
  FROM public.governance_documents gd
  JOIN public.document_versions dv ON dv.id = gd.current_version_id
  WHERE gd.id = p_document_id;

  SELECT dv.id, dv.version_label, dv.version_number INTO v_newer
  FROM public.document_versions dv
  WHERE dv.document_id = p_document_id
    AND dv.locked_at IS NULL
    AND dv.version_number > COALESCE(v_current_number, 0)
  ORDER BY dv.version_number DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'newer', NULL);
  END IF;

  BEGIN
    v_preview := public.get_governance_document_draft_preview(p_document_id, v_newer.id);
  EXCEPTION WHEN insufficient_privilege THEN
    RETURN jsonb_build_object('ok', true, 'newer', NULL);
  END;

  IF v_preview -> 'draft_version' IS NULL OR jsonb_typeof(v_preview -> 'draft_version') = 'null' THEN
    RETURN jsonb_build_object('ok', true, 'newer', NULL);
  END IF;

  RETURN jsonb_build_object('ok', true, 'newer', jsonb_build_object(
    'version_id', v_newer.id,
    'version_label', v_newer.version_label,
    'version_number', v_newer.version_number
  ));
END;
$function$;

REVOKE ALL ON FUNCTION public.get_governance_document_newer_draft(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_governance_document_newer_draft(uuid) TO authenticated, service_role;
