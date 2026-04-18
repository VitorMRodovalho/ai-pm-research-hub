-- ═══════════════════════════════════════════════════════════════
-- Security sweep: SET search_path for SECURITY DEFINER functions
-- created after 20260423040000 (V4 Phase 3+5 refactor).
-- Why: CVE-2018-1058 — functions without SET search_path can resolve
--      unqualified object names via role-controlled search_path,
--      enabling privilege escalation if a non-superuser can create
--      objects in a schema earlier in the resolved search_path.
-- Scope: 19 functions identified via
--        SELECT proname, pg_get_function_identity_arguments(oid)
--        FROM pg_proc
--        WHERE pronamespace='public'::regnamespace AND prosecdef=true
--          AND NOT (proconfig IS NOT NULL AND array_to_string(proconfig,',') ILIKE '%search_path%');
-- Rollback: ALTER FUNCTION ... RESET search_path; per function.
-- ═══════════════════════════════════════════════════════════════

ALTER FUNCTION public.admin_manage_publication(p_action text, p_data jsonb) SET search_path = public, pg_temp;
ALTER FUNCTION public.auto_publish_approved_article() SET search_path = public, pg_temp;
ALTER FUNCTION public.create_event(p_type text, p_title text, p_date date, p_duration_minutes integer, p_tribe_id integer, p_meeting_link text, p_nature text, p_visibility text, p_agenda_text text, p_agenda_url text, p_external_attendees text[], p_invited_member_ids uuid[], p_audience_level text) SET search_path = public, pg_temp;
ALTER FUNCTION public.create_pilot(p_title text, p_hypothesis text, p_problem_statement text, p_scope text, p_status text, p_tribe_id integer, p_board_id uuid, p_success_metrics jsonb, p_team_member_ids uuid[]) SET search_path = public, pg_temp;
ALTER FUNCTION public.create_publication_submission(p_title text, p_target_type submission_target_type, p_target_name text, p_primary_author_id uuid, p_tribe_id integer, p_board_item_id uuid, p_abstract text, p_target_url text, p_estimated_cost_brl numeric) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_public_publications(p_type text, p_tribe_id integer, p_cycle text, p_search text, p_limit integer) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_publication_detail(p_id uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_publication_submission_detail(p_submission_id uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.link_webinar_event(p_webinar_id uuid, p_event_id uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.list_initiative_deliverables(p_initiative_id uuid, p_cycle_code text) SET search_path = public, pg_temp;
ALTER FUNCTION public.list_meeting_artifacts(p_limit integer, p_tribe_id integer) SET search_path = public, pg_temp;
ALTER FUNCTION public.list_tribe_deliverables(p_tribe_id integer, p_cycle_code text) SET search_path = public, pg_temp;
ALTER FUNCTION public.list_webinars_v2(p_status text, p_chapter text, p_tribe_id integer) SET search_path = public, pg_temp;
ALTER FUNCTION public.rls_can_for_initiative(p_action text, p_initiative_id uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.save_presentation_snapshot(p_title text, p_meeting_date date, p_recording_url text, p_agenda_items text[], p_snapshot jsonb, p_event_id uuid, p_tribe_id integer, p_deliberations text[], p_is_published boolean) SET search_path = public, pg_temp;
ALTER FUNCTION public.update_pilot(p_id uuid, p_title text, p_hypothesis text, p_problem_statement text, p_scope text, p_status text, p_tribe_id integer, p_board_id uuid, p_success_metrics jsonb, p_team_member_ids uuid[], p_lessons_learned jsonb, p_started_at date, p_completed_at date) SET search_path = public, pg_temp;
ALTER FUNCTION public.upsert_tribe_deliverable(p_id uuid, p_tribe_id integer, p_cycle_code text, p_title text, p_description text, p_status text, p_assigned_member_id uuid, p_artifact_id uuid, p_due_date date) SET search_path = public, pg_temp;
ALTER FUNCTION public.upsert_webinar(p_id uuid, p_title text, p_description text, p_scheduled_at timestamp with time zone, p_duration_min integer, p_status text, p_chapter_code text, p_tribe_id integer, p_organizer_id uuid, p_co_manager_ids uuid[], p_meeting_link text, p_youtube_url text, p_notes text, p_board_item_id uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.webinars_pending_comms() SET search_path = public, pg_temp;

NOTIFY pgrst, 'reload schema';
