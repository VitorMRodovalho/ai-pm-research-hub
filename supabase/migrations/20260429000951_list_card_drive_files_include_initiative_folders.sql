-- Mayanna report (28/Abr p79): "Não há drive integrado ou pasta de arquivos da comunicação".
-- Root cause: CardDriveFiles esconde-se com 0 arquivos. Hub Comunicação initiative tem 2 Drive
-- folders linked (folder + atas) via initiative_drive_links, mas UI não expõe.
--
-- Fix: list_card_drive_files retorna AGORA tanto card-files quanto initiative-folders + board-folders.
-- Frontend renderiza sempre que houver folders OU files.

CREATE OR REPLACE FUNCTION public.list_card_drive_files(p_board_item_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_files jsonb;
  v_initiative_folders jsonb;
  v_board_folders jsonb;
  v_board_id uuid;
  v_initiative_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT bi.board_id, pb.initiative_id
    INTO v_board_id, v_initiative_id
  FROM public.board_items bi
  JOIN public.project_boards pb ON pb.id = bi.board_id
  WHERE bi.id = p_board_item_id;

  IF v_board_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Card not found');
  END IF;

  -- Card-level files
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', f.id,
    'drive_file_id', f.drive_file_id,
    'drive_file_url', f.drive_file_url,
    'filename', f.filename,
    'mime_type', f.mime_type,
    'size_bytes', f.size_bytes,
    'uploaded_by_name', m.name,
    'uploaded_via', f.uploaded_via,
    'created_at', f.created_at
  ) ORDER BY f.created_at DESC), '[]'::jsonb)
  INTO v_files
  FROM public.board_item_files f
  LEFT JOIN public.members m ON m.id = f.uploaded_by
  WHERE f.board_item_id = p_board_item_id AND f.deleted_at IS NULL;

  -- Initiative-level folder links (Hub de Comunicacao folder + Atas)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', l.id,
    'drive_folder_id', l.drive_folder_id,
    'drive_folder_url', l.drive_folder_url,
    'drive_folder_name', l.drive_folder_name,
    'link_purpose', l.link_purpose,
    'linked_at', l.linked_at
  ) ORDER BY l.link_purpose NULLS LAST, l.linked_at), '[]'::jsonb)
  INTO v_initiative_folders
  FROM public.initiative_drive_links l
  WHERE l.initiative_id = v_initiative_id AND l.unlinked_at IS NULL;

  -- Board-level folder links (rare but supported)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', l.id,
    'drive_folder_id', l.drive_folder_id,
    'drive_folder_url', l.drive_folder_url,
    'drive_folder_name', l.drive_folder_name,
    'linked_at', l.linked_at
  ) ORDER BY l.linked_at), '[]'::jsonb)
  INTO v_board_folders
  FROM public.board_drive_links l
  WHERE l.board_id = v_board_id AND l.unlinked_at IS NULL;

  RETURN jsonb_build_object(
    'board_item_id', p_board_item_id,
    'files', v_files,
    'initiative_folders', v_initiative_folders,
    'board_folders', v_board_folders,
    'fetched_at', now()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.list_card_drive_files(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_card_drive_files(uuid) TO authenticated;

COMMENT ON FUNCTION public.list_card_drive_files(uuid) IS
'Mayanna Item 07: lista arquivos do card + folder links da iniciativa + folder links do board. Card-files via board_item_files, folders via initiative_drive_links + board_drive_links (unlinked_at IS NULL).';

NOTIFY pgrst, 'reload schema';
