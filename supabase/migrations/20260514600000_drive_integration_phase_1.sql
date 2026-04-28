-- Drive Integration Phase 1: schema + RPCs (Mayanna Item 07).
-- Service account model: institutional account nucleoia@pmigo.org.br (Workspace)
-- + backup admin vitorodovalho@gmail.com. Service Account email é adicionado
-- a cada pasta shared como Editor — no Domain-Wide Delegation needed.
-- Setup steps em docs/SETUP_GOOGLE_DRIVE_INTEGRATION.md (PM action).

CREATE TABLE IF NOT EXISTS public.board_drive_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  board_id uuid NOT NULL REFERENCES public.project_boards(id) ON DELETE CASCADE,
  drive_folder_id text NOT NULL,
  drive_folder_url text NOT NULL,
  drive_folder_name text,
  linked_by uuid NOT NULL REFERENCES public.members(id),
  linked_at timestamptz NOT NULL DEFAULT now(),
  unlinked_at timestamptz,
  unlinked_by uuid REFERENCES public.members(id),
  UNIQUE(board_id, drive_folder_id)
);

CREATE INDEX IF NOT EXISTS idx_board_drive_links_board_id ON public.board_drive_links(board_id);
CREATE INDEX IF NOT EXISTS idx_board_drive_links_active ON public.board_drive_links(board_id) WHERE unlinked_at IS NULL;

ALTER TABLE public.board_drive_links ENABLE ROW LEVEL SECURITY;

CREATE POLICY board_drive_links_read_authenticated ON public.board_drive_links
  FOR SELECT TO authenticated
  USING (rls_is_member());

CREATE TABLE IF NOT EXISTS public.board_item_files (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  board_item_id uuid NOT NULL REFERENCES public.board_items(id) ON DELETE CASCADE,
  drive_file_id text NOT NULL,
  drive_file_url text NOT NULL,
  filename text NOT NULL,
  mime_type text,
  size_bytes bigint,
  uploaded_by uuid REFERENCES public.members(id),
  uploaded_via text DEFAULT 'platform' CHECK (uploaded_via IN ('platform', 'drive_native_synced')),
  created_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_board_item_files_item_id ON public.board_item_files(board_item_id);
CREATE INDEX IF NOT EXISTS idx_board_item_files_drive_file_id ON public.board_item_files(drive_file_id);
CREATE INDEX IF NOT EXISTS idx_board_item_files_active ON public.board_item_files(board_item_id) WHERE deleted_at IS NULL;

ALTER TABLE public.board_item_files ENABLE ROW LEVEL SECURITY;

CREATE POLICY board_item_files_read_authenticated ON public.board_item_files
  FOR SELECT TO authenticated
  USING (deleted_at IS NULL AND rls_is_member());

CREATE OR REPLACE FUNCTION public.link_board_to_drive(
  p_board_id uuid,
  p_drive_folder_id text,
  p_drive_folder_url text,
  p_drive_folder_name text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_is_authorized boolean;
  v_existing record;
  v_new_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  v_is_authorized := public.can_by_member(v_caller_id, 'manage_member')
    OR EXISTS (
      SELECT 1 FROM public.board_members bm
      WHERE bm.board_id = p_board_id AND bm.member_id = v_caller_id AND bm.board_role = 'admin'
    );

  IF NOT v_is_authorized THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_member or board admin');
  END IF;

  IF coalesce(trim(p_drive_folder_id), '') = '' OR coalesce(trim(p_drive_folder_url), '') = '' THEN
    RETURN jsonb_build_object('error', 'drive_folder_id and drive_folder_url required');
  END IF;

  SELECT id INTO v_existing.id FROM public.board_drive_links
  WHERE board_id = p_board_id AND drive_folder_id = p_drive_folder_id AND unlinked_at IS NULL;
  IF v_existing.id IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'existing', true, 'link_id', v_existing.id);
  END IF;

  INSERT INTO public.board_drive_links (
    board_id, drive_folder_id, drive_folder_url, drive_folder_name, linked_by
  ) VALUES (
    p_board_id, p_drive_folder_id, p_drive_folder_url, p_drive_folder_name, v_caller_id
  )
  RETURNING id INTO v_new_id;

  RETURN jsonb_build_object('success', true, 'link_id', v_new_id, 'board_id', p_board_id, 'drive_folder_id', p_drive_folder_id);
END;
$$;

REVOKE ALL ON FUNCTION public.link_board_to_drive(uuid, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.link_board_to_drive(uuid, text, text, text) TO authenticated;

COMMENT ON FUNCTION public.link_board_to_drive(uuid, text, text, text) IS
'Mayanna Item 07: vincula uma pasta Drive a um board. Authority: manage_member OR board_admin. Reuse-on-duplicate (idempotent).';

CREATE OR REPLACE FUNCTION public.get_board_drive_links(p_board_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', l.id,
    'drive_folder_id', l.drive_folder_id,
    'drive_folder_url', l.drive_folder_url,
    'drive_folder_name', l.drive_folder_name,
    'linked_by_name', m.name,
    'linked_at', l.linked_at
  ) ORDER BY l.linked_at DESC), '[]'::jsonb)
  INTO v_result
  FROM public.board_drive_links l
  LEFT JOIN public.members m ON m.id = l.linked_by
  WHERE l.board_id = p_board_id AND l.unlinked_at IS NULL;

  RETURN jsonb_build_object('board_id', p_board_id, 'drive_links', v_result, 'fetched_at', now());
END;
$$;

REVOKE ALL ON FUNCTION public.get_board_drive_links(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_board_drive_links(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.unlink_board_from_drive(p_link_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_link record;
  v_is_authorized boolean;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT * INTO v_link FROM public.board_drive_links WHERE id = p_link_id;
  IF v_link.id IS NULL THEN
    RETURN jsonb_build_object('error', 'Link not found');
  END IF;

  IF v_link.unlinked_at IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Already unlinked');
  END IF;

  v_is_authorized := public.can_by_member(v_caller_id, 'manage_member')
    OR EXISTS (
      SELECT 1 FROM public.board_members bm
      WHERE bm.board_id = v_link.board_id AND bm.member_id = v_caller_id AND bm.board_role = 'admin'
    );

  IF NOT v_is_authorized THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  UPDATE public.board_drive_links
  SET unlinked_at = now(), unlinked_by = v_caller_id
  WHERE id = p_link_id;

  RETURN jsonb_build_object('success', true, 'link_id', p_link_id);
END;
$$;

REVOKE ALL ON FUNCTION public.unlink_board_from_drive(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unlink_board_from_drive(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.list_card_drive_files(p_board_item_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

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
  INTO v_result
  FROM public.board_item_files f
  LEFT JOIN public.members m ON m.id = f.uploaded_by
  WHERE f.board_item_id = p_board_item_id AND f.deleted_at IS NULL;

  RETURN jsonb_build_object('board_item_id', p_board_item_id, 'files', v_result, 'fetched_at', now());
END;
$$;

REVOKE ALL ON FUNCTION public.list_card_drive_files(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_card_drive_files(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.register_card_drive_file(
  p_board_item_id uuid,
  p_drive_file_id text,
  p_drive_file_url text,
  p_filename text,
  p_mime_type text DEFAULT NULL,
  p_size_bytes bigint DEFAULT NULL,
  p_uploaded_via text DEFAULT 'platform'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_new_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF p_uploaded_via NOT IN ('platform', 'drive_native_synced') THEN
    RETURN jsonb_build_object('error', 'Invalid uploaded_via');
  END IF;

  INSERT INTO public.board_item_files (
    board_item_id, drive_file_id, drive_file_url, filename, mime_type,
    size_bytes, uploaded_by, uploaded_via
  ) VALUES (
    p_board_item_id, p_drive_file_id, p_drive_file_url, p_filename,
    p_mime_type, p_size_bytes, v_caller_id, p_uploaded_via
  )
  RETURNING id INTO v_new_id;

  RETURN jsonb_build_object('success', true, 'file_id', v_new_id, 'drive_file_id', p_drive_file_id);
END;
$$;

REVOKE ALL ON FUNCTION public.register_card_drive_file(uuid, text, text, text, text, bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_card_drive_file(uuid, text, text, text, text, bigint, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
