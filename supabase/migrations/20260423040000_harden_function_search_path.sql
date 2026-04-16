-- ═══════════════════════════════════════════════════════════════
-- Harden function search_path for 49 WARN-level advisor findings
-- Why: function_search_path_mutable is a CVE-2018-1058-style risk —
-- functions without SET search_path can be tricked into resolving
-- unqualified names via role-controlled search_path.
-- Approach: ALTER FUNCTION ... SET search_path = public, pg_temp;
-- (does not rewrite bodies; only tightens default search_path)
-- Rollback: ALTER FUNCTION ... RESET search_path; per function.
-- ═══════════════════════════════════════════════════════════════

ALTER FUNCTION public.admin_get_anomaly_report() SET search_path = public, pg_temp;
ALTER FUNCTION public.admin_send_campaign(p_template_id uuid, p_audience_filter jsonb, p_scheduled_at timestamp with time zone, p_external_contacts jsonb) SET search_path = public, pg_temp;
ALTER FUNCTION public.assert_initiative_capability(p_initiative_id uuid, p_capability text) SET search_path = public, pg_temp;
ALTER FUNCTION public.broadcast_count_today_v4(p_initiative_id uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.calc_attendance_pct() SET search_path = public, pg_temp;
ALTER FUNCTION public.calc_trail_completion_pct() SET search_path = public, pg_temp;
ALTER FUNCTION public.can(p_person_id uuid, p_action text, p_resource_type text, p_resource_id uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.can_by_member(p_member_id uuid, p_action text, p_resource_type text, p_resource_id uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.counter_sign_certificate(p_certificate_id uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.create_initiative(p_kind text, p_title text, p_description text, p_metadata jsonb, p_parent_initiative_id uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.exec_initiative_dashboard(p_initiative_id uuid, p_cycle text) SET search_path = public, pg_temp;
ALTER FUNCTION public.exec_portfolio_health(p_cycle_code text) SET search_path = public, pg_temp;
ALTER FUNCTION public.export_my_data() SET search_path = public, pg_temp;
ALTER FUNCTION public.get_active_engagements(p_person_id uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_annual_kpis(p_cycle integer, p_year integer) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_board_by_domain(p_domain_key text, p_tribe_id integer, p_initiative_id uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_cpmai_course_dashboard(p_course_id uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_diversity_dashboard(p_cycle_id uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_essay_field(p_mapping jsonb, p_index text) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_evaluation_form(p_application_id uuid, p_evaluation_type text) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_executive_kpis() SET search_path = public, pg_temp;
ALTER FUNCTION public.get_person(p_person_id uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_public_impact_data() SET search_path = public, pg_temp;
ALTER FUNCTION public.get_selection_dashboard(p_cycle_code text) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_sustainability_dashboard(p_cycle integer) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_volunteer_agreement_status() SET search_path = public, pg_temp;
ALTER FUNCTION public.handle_new_user() SET search_path = public, pg_temp;
ALTER FUNCTION public.join_initiative(p_initiative_id uuid, p_motivation text, p_metadata jsonb) SET search_path = public, pg_temp;
ALTER FUNCTION public.list_initiative_boards(p_initiative_id uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.list_initiative_deliverables(p_initiative_id uuid, p_cycle_code text) SET search_path = public, pg_temp;
ALTER FUNCTION public.list_initiative_meeting_artifacts(p_limit integer, p_initiative_id uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.list_initiatives(p_kind text, p_status text) SET search_path = public, pg_temp;
ALTER FUNCTION public.parse_vep_chapters(p_membership text) SET search_path = public, pg_temp;
ALTER FUNCTION public.platform_activity_summary() SET search_path = public, pg_temp;
ALTER FUNCTION public.resolve_initiative_id(p_tribe_id integer) SET search_path = public, pg_temp;
ALTER FUNCTION public.resolve_tribe_id(p_initiative_id uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.search_initiative_board_items(p_query text, p_initiative_id uuid) SET search_path = public, pg_temp;
ALTER FUNCTION public.submit_interview_scores(p_interview_id uuid, p_scores jsonb, p_theme text, p_notes text, p_criterion_notes jsonb) SET search_path = public, pg_temp;
ALTER FUNCTION public.sync_initiative_from_tribe() SET search_path = public, pg_temp;
ALTER FUNCTION public.sync_operational_role_cache() SET search_path = public, pg_temp;
ALTER FUNCTION public.sync_tribe_from_initiative() SET search_path = public, pg_temp;
ALTER FUNCTION public.trg_validate_initiative_metadata_fn() SET search_path = public, pg_temp;
ALTER FUNCTION public.update_application_contact(p_application_id uuid, p_phone text, p_linkedin_url text) SET search_path = public, pg_temp;
ALTER FUNCTION public.update_initiative(p_initiative_id uuid, p_title text, p_description text, p_status text, p_metadata jsonb) SET search_path = public, pg_temp;
ALTER FUNCTION public.v4_expire_engagements() SET search_path = public, pg_temp;
ALTER FUNCTION public.v4_expire_engagements_shadow() SET search_path = public, pg_temp;
ALTER FUNCTION public.v4_notify_expiring_engagements() SET search_path = public, pg_temp;
ALTER FUNCTION public.validate_initiative_metadata(p_kind text, p_metadata jsonb) SET search_path = public, pg_temp;
ALTER FUNCTION public.why_denied(p_person_id uuid, p_action text, p_resource_type text, p_resource_id uuid) SET search_path = public, pg_temp;
