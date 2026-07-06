-- Espelho PÚBLICO do glossário: apenas versões LACRADAS + rótulo público limpo.
-- Fecha exposição anon do draft em revisão (label + content_html) e do sedimento
-- interno de labels (p128, roberto-comment, adr0068, p90x). Draft/labels internos
-- seguem no /admin/governance (autenticado). Ver PR feat/glossario-guia-voluntario.
--
-- Backward-compat: emite version_label JÁ LIMPO (= public_label). O frontend novo
-- usa public_label; o frontend deployado (antigo) lê version_label e passa a ver o
-- rótulo saneado (v2.7...) sem esperar o deploy do PR.
CREATE OR REPLACE FUNCTION public.get_governance_glossary()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_policy_doc_id uuid := 'cfb15185-2800-4441-9ff1-f36096e83aa8';
  v_latest record;
  v_current_locked record;
  v_history jsonb;
  v_label_re text := '^([vV][0-9]+(?:\.[0-9]+)?)';
BEGIN
  -- Latest LACRADA (nunca draft) — evita servir content_html em revisão ao anon
  SELECT dv.id, dv.version_number, dv.version_label, dv.content_html,
         dv.locked_at, dv.authored_at
  INTO v_latest
  FROM public.document_versions dv
  WHERE dv.document_id = v_policy_doc_id
    AND dv.locked_at IS NOT NULL
  ORDER BY dv.version_number DESC LIMIT 1;

  -- Current locked (a oficial vigente)
  SELECT dv.id, dv.version_number, dv.version_label, dv.content_html,
         dv.locked_at
  INTO v_current_locked
  FROM public.governance_documents gd
  JOIN public.document_versions dv ON dv.id = gd.current_version_id
  WHERE gd.id = v_policy_doc_id
    AND dv.locked_at IS NOT NULL;

  -- History: só LACRADAS, com rótulo limpo (semver, sem sedimento interno).
  -- version_label e public_label carregam o MESMO valor saneado.
  SELECT jsonb_agg(jsonb_build_object(
    'version_id', dv.id,
    'version_label', COALESCE(NULLIF(substring(dv.version_label from v_label_re), ''), 'v' || dv.version_number),
    'public_label', COALESCE(NULLIF(substring(dv.version_label from v_label_re), ''), 'v' || dv.version_number),
    'version_number', dv.version_number,
    'is_locked', true,
    'is_current', dv.id = v_current_locked.id,
    'date', dv.locked_at
  ) ORDER BY dv.version_number DESC)
  INTO v_history
  FROM public.document_versions dv
  WHERE dv.document_id = v_policy_doc_id
    AND dv.locked_at IS NOT NULL;

  RETURN jsonb_build_object(
    'latest', CASE WHEN v_latest.id IS NULL THEN NULL ELSE jsonb_build_object(
      'version_id', v_latest.id,
      'version_label', COALESCE(NULLIF(substring(v_latest.version_label from v_label_re), ''), 'v' || v_latest.version_number),
      'public_label', COALESCE(NULLIF(substring(v_latest.version_label from v_label_re), ''), 'v' || v_latest.version_number),
      'version_number', v_latest.version_number,
      'content_html', v_latest.content_html,
      'is_locked', true,
      'date', v_latest.locked_at
    ) END,
    'current_locked', CASE WHEN v_current_locked.id IS NULL THEN NULL ELSE jsonb_build_object(
      'version_id', v_current_locked.id,
      'version_label', COALESCE(NULLIF(substring(v_current_locked.version_label from v_label_re), ''), 'v' || v_current_locked.version_number),
      'public_label', COALESCE(NULLIF(substring(v_current_locked.version_label from v_label_re), ''), 'v' || v_current_locked.version_number),
      'version_number', v_current_locked.version_number,
      'content_html', v_current_locked.content_html,
      'locked_at', v_current_locked.locked_at
    ) END,
    'history', COALESCE(v_history, '[]'::jsonb)
  );
END;
$function$;
