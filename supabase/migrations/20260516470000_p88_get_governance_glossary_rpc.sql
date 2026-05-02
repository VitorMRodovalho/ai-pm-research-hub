-- p88: RPC pública para glossário canônico (Política §13)
-- Use case: URL `/governance/glossario` referenciada em §13.5 da Política como
-- espelho dinâmico do glossário current. Retorna latest version (locked se existir;
-- senão draft com flag de status) + history list. Anon-grant porque glossário
-- contém apenas definições genéricas (Track A/B/C, licenças CC/MIT/Apache, termos
-- operacionais) — não há informação sensível.

CREATE OR REPLACE FUNCTION public.get_governance_glossary()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_policy_doc_id uuid := 'cfb15185-2800-4441-9ff1-f36096e83aa8';
  v_latest record;
  v_current_locked record;
  v_history jsonb;
BEGIN
  -- Latest version (locked OR draft) — para preview do glossário em revisão
  SELECT dv.id, dv.version_number, dv.version_label, dv.content_html,
         dv.locked_at, dv.authored_at
  INTO v_latest
  FROM public.document_versions dv
  WHERE dv.document_id = v_policy_doc_id
  ORDER BY dv.version_number DESC LIMIT 1;

  -- Current locked (the official one)
  SELECT dv.id, dv.version_number, dv.version_label, dv.content_html,
         dv.locked_at
  INTO v_current_locked
  FROM public.governance_documents gd
  JOIN public.document_versions dv ON dv.id = gd.current_version_id
  WHERE gd.id = v_policy_doc_id;

  -- History: all versions (locked + draft) with metadata
  SELECT jsonb_agg(jsonb_build_object(
    'version_id', dv.id,
    'version_label', dv.version_label,
    'version_number', dv.version_number,
    'is_locked', dv.locked_at IS NOT NULL,
    'is_current', dv.id = v_current_locked.id,
    'date', COALESCE(dv.locked_at, dv.authored_at)
  ) ORDER BY dv.version_number DESC)
  INTO v_history
  FROM public.document_versions dv
  WHERE dv.document_id = v_policy_doc_id;

  RETURN jsonb_build_object(
    'latest', jsonb_build_object(
      'version_id', v_latest.id,
      'version_label', v_latest.version_label,
      'version_number', v_latest.version_number,
      'content_html', v_latest.content_html,
      'is_locked', v_latest.locked_at IS NOT NULL,
      'date', COALESCE(v_latest.locked_at, v_latest.authored_at)
    ),
    'current_locked', CASE WHEN v_current_locked.id IS NULL THEN NULL ELSE jsonb_build_object(
      'version_id', v_current_locked.id,
      'version_label', v_current_locked.version_label,
      'version_number', v_current_locked.version_number,
      'content_html', v_current_locked.content_html,
      'locked_at', v_current_locked.locked_at
    ) END,
    'history', COALESCE(v_history, '[]'::jsonb)
  );
END;
$function$;

COMMENT ON FUNCTION public.get_governance_glossary() IS
  'Retorna glossário §13 da Política — latest version (locked OR draft) + current_locked + history list. Anon-grant: glossário contém apenas definições genéricas (Track A/B/C, licenças CC/MIT/Apache). Use case: URL canônica /governance/glossario espelho dinâmico (Política §13.5).';

GRANT EXECUTE ON FUNCTION public.get_governance_glossary() TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
