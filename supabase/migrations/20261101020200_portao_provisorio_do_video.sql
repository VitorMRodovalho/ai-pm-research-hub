-- ADR-0134 §4 e §6: portão provisório do vídeo do candidato, até existir a leitura por atribuição.
-- Decisão do GP em 01/11/2026.
--
-- Vê o vídeo de uma candidatura:
--   - quem tem `manage_platform`;
--   - o assento `lead` ou `evaluator` do comitê do ciclo da candidatura.
-- Deixam de ver: quem só tinha `view_internal_analytics` (patrocínio, ponto de contato de capítulo,
-- curadoria) e o assento `observer`. O painel do ciclo segue com as contagens de vídeo, sem link e sem
-- transcrição.
--
-- Também passam a valer, como nas outras superfícies de seleção:
--   - a candidatura tem de ser da organização do caller (auth_org()) e não pode estar anonimizada;
--   - a recusa por conflito de interesse (ADR-0109);
--   - o registro obrigatório de cada leitura (_log_opening_application_access, #2393): se não gravar,
--     a leitura falha e nada é devolvido.
-- Até a autoridade, toda recusa é 'Unauthorized'. A saída é a de antes, menos `failure_reason`, que a
-- aba Vídeos não usa e pode trazer texto interno de erro. `drive_folder_id` fica: a aba o usa quando
-- falta `drive_file_id`.
-- Depende de 20261101020000_leitura_por_vaga_acao_e_registro.sql (o registro estrito).

CREATE OR REPLACE FUNCTION public.get_application_video_screenings(p_application_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_id uuid;
  v_result jsonb;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT sa.cycle_id INTO v_cycle_id
  FROM public.selection_applications sa
  WHERE sa.id = p_application_id
    AND sa.organization_id = public.auth_org()
    AND sa.anonymized_at IS NULL;
  IF v_cycle_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  IF NOT (
    public.can_by_member(v_caller_id, 'manage_platform')
    OR EXISTS (
      SELECT 1
      FROM public.selection_committee sc
      WHERE sc.cycle_id = v_cycle_id
        AND sc.member_id = v_caller_id
        AND sc.role IN ('lead', 'evaluator')
    )
  ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  IF public.selection_coi_recused(v_caller_id, v_cycle_id) THEN
    RETURN jsonb_build_object('error', 'recused_conflict_of_interest',
      'detail', 'Você é candidato(a) neste ciclo: os vídeos das candidaturas estão impedidos por conflito de interesse (ADR-0109).');
  END IF;

  PERFORM public._log_opening_application_access(
    p_application_id, v_caller_id,
    ARRAY['video_drive_file', 'video_youtube_url', 'video_transcription'],
    'get_application_video_screenings'
  );

  SELECT jsonb_build_object(
    'application_id', p_application_id,
    'rows', COALESCE(jsonb_agg(jsonb_build_object(
      'id', v.id,
      'pillar', v.pillar,
      'question_index', v.question_index,
      'question_text', v.question_text,
      'status', v.status,
      'storage_provider', v.storage_provider,
      'drive_folder_id', v.drive_folder_id,
      'drive_file_id', v.drive_file_id,
      'drive_file_name', v.drive_file_name,
      'youtube_url', v.youtube_url,
      'duration_seconds', v.duration_seconds,
      'file_size_bytes', v.file_size_bytes,
      'mime_type', v.mime_type,
      'transcription', v.transcription,
      'transcription_provider', v.transcription_provider,
      'transcription_model_version', v.transcription_model_version,
      'transcription_at', v.transcription_at,
      'transcription_confidence', v.transcription_confidence,
      'retry_count', v.retry_count,
      'uploaded_at', v.uploaded_at,
      'created_at', v.created_at,
      'updated_at', v.updated_at
    ) ORDER BY v.pillar, v.question_index), '[]'::jsonb),
    'summary', jsonb_build_object(
      'total', count(*),
      'uploaded', count(*) FILTER (WHERE v.status IN ('uploaded','transcribing','transcribed')),
      'opted_out', count(*) FILTER (WHERE v.status = 'opted_out'),
      'failed', count(*) FILTER (WHERE v.status = 'failed'),
      'first_uploaded_at', min(v.uploaded_at) FILTER (WHERE v.uploaded_at IS NOT NULL),
      'last_uploaded_at', max(v.uploaded_at) FILTER (WHERE v.uploaded_at IS NOT NULL),
      'total_duration_seconds', COALESCE(sum(v.duration_seconds) FILTER (WHERE v.status IN ('uploaded','transcribed')), 0)::int
    )
  ) INTO v_result
  FROM public.pmi_video_screenings v
  WHERE v.application_id = p_application_id;

  RETURN COALESCE(v_result, jsonb_build_object(
    'application_id', p_application_id, 'rows', '[]'::jsonb,
    'summary', jsonb_build_object('total', 0, 'uploaded', 0, 'opted_out', 0, 'failed', 0)
  ));
END;
$function$;

REVOKE ALL ON FUNCTION public.get_application_video_screenings(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_application_video_screenings(uuid) TO authenticated;

COMMENT ON FUNCTION public.get_application_video_screenings(uuid) IS
  'ADR-0134 (portão provisório): vídeos de uma candidatura para manage_platform ou para o assento lead/evaluator do comitê do ciclo dela. Conflito de interesse recusa; cada leitura tem registro obrigatório em pii_access_log.';

NOTIFY pgrst, 'reload schema';
