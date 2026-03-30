-- Security hardening based on Supabase advisor audit (29/Mar)
-- 1. Fix search_path on ~35 functions (prevents search_path injection)
-- 2. Tighten overly permissive RLS policies

-- ══ search_path fixes (webinar functions) ══
ALTER FUNCTION public.notify_webinar_status_change() SET search_path = public;
ALTER FUNCTION public.get_webinar_lifecycle(uuid) SET search_path = public;
ALTER FUNCTION public.list_webinars_v2(text, text, integer) SET search_path = public;
ALTER FUNCTION public.link_webinar_event(uuid, uuid) SET search_path = public;
ALTER FUNCTION public.log_webinar_created() SET search_path = public;
ALTER FUNCTION public.webinars_set_updated_at() SET search_path = public;
ALTER FUNCTION public.webinars_pending_comms() SET search_path = public;
ALTER FUNCTION public.upsert_webinar(uuid, text, text, timestamptz, integer, text, text, integer, uuid, uuid[], text, text, text, uuid) SET search_path = public;

-- ══ search_path fixes (core functions) ══
ALTER FUNCTION public.compute_legacy_role(text, text[]) SET search_path = public;
ALTER FUNCTION public.compute_legacy_roles(text, text[]) SET search_path = public;
ALTER FUNCTION public.create_notification(uuid, text, text, text, text, text, uuid) SET search_path = public;
ALTER FUNCTION public.create_notification(uuid, text, text, uuid, text, uuid) SET search_path = public;
ALTER FUNCTION public.get_my_notifications(integer, boolean) SET search_path = public;
ALTER FUNCTION public.move_board_item(uuid, text, integer, text) SET search_path = public;
ALTER FUNCTION public.analytics_is_leadership_role(text, text[]) SET search_path = public;
ALTER FUNCTION public.analytics_role_bucket(text, text[]) SET search_path = public;
ALTER FUNCTION public.enforce_project_board_taxonomy() SET search_path = public;
ALTER FUNCTION public.enforce_board_item_source_tribe_integrity() SET search_path = public;
ALTER FUNCTION public.set_curation_due_date() SET search_path = public;
ALTER FUNCTION public.suggest_tags(text, text, text) SET search_path = public;
ALTER FUNCTION public.set_progress(text, text, text) SET search_path = public;
ALTER FUNCTION public.get_tribe_counts() SET search_path = public;
ALTER FUNCTION public.title_case(text) SET search_path = public;

-- ══ search_path fixes (trigger functions) ══
ALTER FUNCTION public.board_source_tribe_map_set_updated_at() SET search_path = public;
ALTER FUNCTION public.tribe_lineage_set_updated_at() SET search_path = public;
ALTER FUNCTION public.ingestion_batch_files_set_updated_at() SET search_path = public;
ALTER FUNCTION public.set_hub_resources_updated_at() SET search_path = public;
ALTER FUNCTION public.set_knowledge_updated_at() SET search_path = public;
ALTER FUNCTION public.ingestion_run_ledger_set_updated_at() SET search_path = public;
ALTER FUNCTION public.legacy_tribes_set_updated_at() SET search_path = public;
ALTER FUNCTION public.set_comms_channel_config_updated_at() SET search_path = public;
ALTER FUNCTION public.tribe_continuity_overrides_set_updated_at() SET search_path = public;
ALTER FUNCTION public.set_comms_metrics_updated_at() SET search_path = public;
ALTER FUNCTION public.notion_import_staging_set_updated_at() SET search_path = public;
ALTER FUNCTION public.project_boards_set_updated_at() SET search_path = public;
ALTER FUNCTION public.update_sustainability_timestamp() SET search_path = public;
ALTER FUNCTION public.project_memberships_set_updated_at() SET search_path = public;
ALTER FUNCTION public.legacy_member_links_set_updated_at() SET search_path = public;
ALTER FUNCTION public.board_items_set_updated_at() SET search_path = public;
ALTER FUNCTION public.set_knowledge_insights_updated_at() SET search_path = public;
ALTER FUNCTION public.tribe_deliverables_set_updated_at() SET search_path = public;
ALTER FUNCTION public.update_pub_sub_event_timestamp() SET search_path = public;
ALTER FUNCTION public.legacy_tribe_board_links_set_updated_at() SET search_path = public;
ALTER FUNCTION public.events_default_duration_actual() SET search_path = public;

-- ══ RLS tightening ══

-- course_progress: was USING(true) for ALL — now restricted to own rows
DROP POLICY IF EXISTS "Auth update progress" ON public.course_progress;
CREATE POLICY "Auth update progress" ON public.course_progress
  FOR ALL TO authenticated
  USING (member_id IN (SELECT id FROM members WHERE auth_id = auth.uid()))
  WITH CHECK (member_id IN (SELECT id FROM members WHERE auth_id = auth.uid()));

-- webinar_lifecycle_events: INSERT was WITH CHECK(true) — now requires auth.uid()
DROP POLICY IF EXISTS "wle_insert" ON public.webinar_lifecycle_events;
CREATE POLICY "wle_insert" ON public.webinar_lifecycle_events
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL);

-- Note: notifications.notif_insert_system and visitor_leads.Anyone can submit lead
-- are intentionally permissive (system inserts and public lead capture respectively)
