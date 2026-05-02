-- p88: Adiciona get_next_draft_version() para PM revisar próximas iterações draft
-- Espelha get_previous_locked_version mas em direção forward (drafts pendentes,
-- locked_at IS NULL, version_number > current). Inclui notes (changelog).
-- Use case: ADR-0068 redraft framework — 5 docs com v3 drafts pendentes curadoria.

CREATE OR REPLACE FUNCTION public.get_next_draft_version(
  p_version_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_current record;
  v_draft record;
BEGIN
  SELECT dv.id, dv.document_id, dv.version_number
  INTO v_current
  FROM public.document_versions dv WHERE dv.id = p_version_id;
  IF v_current.id IS NULL THEN
    RETURN jsonb_build_object('error','version_not_found');
  END IF;

  SELECT dv.id, dv.version_number, dv.version_label, dv.content_html,
         dv.content_markdown, dv.authored_at, dv.notes
  INTO v_draft
  FROM public.document_versions dv
  WHERE dv.document_id = v_current.document_id
    AND dv.version_number > v_current.version_number
    AND dv.locked_at IS NULL
  ORDER BY dv.version_number ASC
  LIMIT 1;

  IF v_draft.id IS NULL THEN
    RETURN jsonb_build_object('exists', false);
  END IF;

  RETURN jsonb_build_object(
    'exists', true,
    'version_id', v_draft.id,
    'version_number', v_draft.version_number,
    'version_label', v_draft.version_label,
    'content_html', v_draft.content_html,
    'content_markdown', v_draft.content_markdown,
    'authored_at', v_draft.authored_at,
    'notes', v_draft.notes
  );
END;
$function$;

COMMENT ON FUNCTION public.get_next_draft_version(uuid) IS
  'Retorna próxima document_version draft (locked_at IS NULL, version_number > current) para PM revisar redraft pendente. Returns {exists:false} quando não há draft. Use case: ADR-0068 5 docs governance redraft (p88).';

GRANT EXECUTE ON FUNCTION public.get_next_draft_version(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
