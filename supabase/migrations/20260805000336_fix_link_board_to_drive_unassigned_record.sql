-- 336: link_board_to_drive quebrava em TODA chamada com "record v_existing is not
-- assigned yet": `SELECT id INTO v_existing.id` atribui a um campo de record nunca
-- inicializado (plpgsql exige o record atribuído antes de tocar um campo).
-- Fix body-only: variável escalar v_existing_id uuid. Assinatura inalterada.
-- Aplicada em prod via apply_migration em 2026-07-04 (sessão kickoff C4).

CREATE OR REPLACE FUNCTION public.link_board_to_drive(p_board_id uuid, p_drive_folder_id text, p_drive_folder_url text, p_drive_folder_name text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_is_authorized boolean;
  v_existing_id uuid;
  v_new_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- Authority: manage_member (admin/GP) OR board_admin
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

  -- Reuse if already linked (and active) — return existing instead of dup error
  SELECT id INTO v_existing_id FROM public.board_drive_links
  WHERE board_id = p_board_id AND drive_folder_id = p_drive_folder_id AND unlinked_at IS NULL;
  IF v_existing_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'existing', true,
      'link_id', v_existing_id
    );
  END IF;

  INSERT INTO public.board_drive_links (
    board_id, drive_folder_id, drive_folder_url, drive_folder_name, linked_by
  ) VALUES (
    p_board_id, p_drive_folder_id, p_drive_folder_url, p_drive_folder_name, v_caller_id
  )
  RETURNING id INTO v_new_id;

  RETURN jsonb_build_object(
    'success', true,
    'link_id', v_new_id,
    'board_id', p_board_id,
    'drive_folder_id', p_drive_folder_id
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
