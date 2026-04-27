-- ADR-0032 (p66) defense-in-depth REVOKE
-- pg_policy precondition: zero RLS refs verified pre-apply.

REVOKE EXECUTE ON FUNCTION public.admin_archive_project_board(uuid, text, boolean) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_restore_project_board(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_update_board_columns(uuid, jsonb) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_list_archived_board_items(uuid, integer) FROM PUBLIC, anon;
