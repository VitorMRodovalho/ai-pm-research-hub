-- WS-A2: tribes.whatsapp_url and drive_url must never be SELECT-able by anon or
-- authenticated via a direct table read. They are served only through SECURITY
-- DEFINER RPCs (get_tribe_group_link, exec_tribe_dashboard, admin_list_tribes),
-- which run as the function owner and bypass these column grants. This closes the
-- direct-read bypass — including an authenticated *pre-onboarding* member querying
-- the table directly, which the gated RPC alone could not prevent.
--
-- anon/authenticated currently hold BOTH a table-level SELECT and column-level
-- SELECT on these columns (the permissive Supabase default). has_column_privilege
-- is true if EITHER grants it, so we must drop both and re-grant only safe columns.
--
-- Rollback: GRANT SELECT ON public.tribes TO anon, authenticated;

REVOKE SELECT ON public.tribes FROM anon, authenticated;
REVOKE SELECT (whatsapp_url, drive_url) ON public.tribes FROM anon, authenticated;

GRANT SELECT (
  id, name, quadrant, quadrant_name, leader_member_id, meeting_schedule,
  meeting_time_start, meeting_time_end, miro_url, meeting_link, notes,
  updated_at, updated_by, is_active, workstream_type, legacy_board_url,
  video_url, video_duration, name_i18n, quadrant_name_i18n, organization_id
) ON public.tribes TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
