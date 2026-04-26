-- Track R batch 1 — pg_graphql anon table exposure REVOKE (defense-in-depth)
-- Triggered by Supabase advisor `pg_graphql_anon_table_exposed` (165 WARN
-- surfaced in p59). Anon role had SELECT grant on 155 tables + 10 views,
-- exposing schemas via pg_graphql even where RLS denied actual reads.
--
-- Per-table audit (see docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md Track R section):
-- - 25 z_archive.* tables: REVOKE (archived, 0 callers)
-- - 70 public.* tables (RLS already blocks anon reads + 0 anon-tier .from()
--   callers in src/): REVOKE
-- - 7 views (0 anon-tier .from() callers; member-tier callers retain
--   authenticated grant): REVOKE
--
-- PRESERVED (anon-tier .from() readers — REVOKE would break homepage):
--   * public.hub_resources (ResourcesSection.astro, library.astro)
--   * public.site_config (ChaptersSection, WeeklyScheduleSection,
--     ReportPage)
--
-- PRESERVED (intentional public per ADR-0024 / ADR-0010):
--   * public.public_members (advisor ERROR — accepted risk)
--   * public.members_public_safe (intentional public view)
--
-- PRESERVED (tables with RLS policies permitting anon reads — verified via
-- has_anon_select_policy check; revoking would break homepage SECDEF readers
-- that depend on table grants):
--   * Many tables already have RLS that selectively permits anon. The
--     authenticated/service_role grants retained throughout. Tables
--     listed below are explicitly REVOKE'd because their RLS policies
--     do NOT permit anon reads (has_anon_select_policy=false), so REVOKE
--     is purely defense-in-depth with no behavioral change.
--
-- Pattern: REVOKE SELECT ON <table> FROM anon.
-- authenticated + service_role grants retained throughout.

-- ============================================================
-- (a) z_archive.* — archived legacy tables, no app callers (25)
-- ============================================================
REVOKE SELECT ON z_archive.comms_token_alerts FROM anon;
REVOKE SELECT ON z_archive.governance_bundle_snapshots FROM anon;
REVOKE SELECT ON z_archive.ingestion_alert_events FROM anon;
REVOKE SELECT ON z_archive.ingestion_alert_remediation_rules FROM anon;
REVOKE SELECT ON z_archive.ingestion_alert_remediation_runs FROM anon;
REVOKE SELECT ON z_archive.ingestion_alerts FROM anon;
REVOKE SELECT ON z_archive.ingestion_apply_locks FROM anon;
REVOKE SELECT ON z_archive.ingestion_batch_files FROM anon;
REVOKE SELECT ON z_archive.ingestion_batches FROM anon;
REVOKE SELECT ON z_archive.ingestion_provenance_signatures FROM anon;
REVOKE SELECT ON z_archive.ingestion_rollback_plans FROM anon;
REVOKE SELECT ON z_archive.ingestion_run_ledger FROM anon;
REVOKE SELECT ON z_archive.legacy_member_links FROM anon;
REVOKE SELECT ON z_archive.legacy_tribe_board_links FROM anon;
REVOKE SELECT ON z_archive.member_chapter_affiliations FROM anon;
REVOKE SELECT ON z_archive.member_role_changes FROM anon;
REVOKE SELECT ON z_archive.member_status_transitions FROM anon;
REVOKE SELECT ON z_archive.notion_import_staging FROM anon;
REVOKE SELECT ON z_archive.platform_settings_log FROM anon;
REVOKE SELECT ON z_archive.portfolio_data_sanity_runs FROM anon;
REVOKE SELECT ON z_archive.presentations FROM anon;
REVOKE SELECT ON z_archive.publication_submission_events FROM anon;
REVOKE SELECT ON z_archive.readiness_slo_alerts FROM anon;
REVOKE SELECT ON z_archive.release_readiness_history FROM anon;
REVOKE SELECT ON z_archive.rollback_audit_events FROM anon;

-- ============================================================
-- (b) public.* — RLS blocks anon reads + 0 anon-tier .from() callers (70)
-- ============================================================

-- Admin / audit / observability
REVOKE SELECT ON public.admin_audit_log FROM anon;
REVOKE SELECT ON public.admin_links FROM anon;
REVOKE SELECT ON public.broadcast_log FROM anon;
REVOKE SELECT ON public.data_anomaly_log FROM anon;
REVOKE SELECT ON public.data_quality_audit_snapshots FROM anon;
REVOKE SELECT ON public.data_retention_policy FROM anon;
REVOKE SELECT ON public.email_webhook_events FROM anon;
REVOKE SELECT ON public.mcp_usage_log FROM anon;
REVOKE SELECT ON public.platform_settings FROM anon;
REVOKE SELECT ON public.release_readiness_policies FROM anon;
REVOKE SELECT ON public.trello_import_log FROM anon;

-- LGPD / PII
REVOKE SELECT ON public.persons FROM anon;
REVOKE SELECT ON public.pii_access_log FROM anon;
REVOKE SELECT ON public.member_offboarding_records FROM anon;

-- V4 authority / engagements
REVOKE SELECT ON public.engagement_kind_permissions FROM anon;
REVOKE SELECT ON public.engagement_kinds FROM anon;
REVOKE SELECT ON public.engagements FROM anon;
REVOKE SELECT ON public.organizations FROM anon;

-- Notifications / preferences (member-tier)
REVOKE SELECT ON public.notification_preferences FROM anon;
REVOKE SELECT ON public.notifications FROM anon;
REVOKE SELECT ON public.onboarding_steps FROM anon;

-- Initiatives / tribes (member-tier)
REVOKE SELECT ON public.initiative_kinds FROM anon;
REVOKE SELECT ON public.initiative_member_progress FROM anon;
REVOKE SELECT ON public.initiatives FROM anon;
REVOKE SELECT ON public.tribe_continuity_overrides FROM anon;
REVOKE SELECT ON public.tribe_lineage FROM anon;

-- Board (member-tier)
REVOKE SELECT ON public.board_item_assignments FROM anon;
REVOKE SELECT ON public.board_item_checklists FROM anon;
REVOKE SELECT ON public.board_item_tag_assignments FROM anon;
REVOKE SELECT ON public.event_audience_rules FROM anon;
REVOKE SELECT ON public.event_invited_members FROM anon;
REVOKE SELECT ON public.event_tag_assignments FROM anon;

-- Comms (admin/operational)
REVOKE SELECT ON public.campaign_templates FROM anon;
REVOKE SELECT ON public.comms_media_items FROM anon;
REVOKE SELECT ON public.comms_metrics_daily FROM anon;
REVOKE SELECT ON public.comms_metrics_ingestion_log FROM anon;
REVOKE SELECT ON public.comms_token_alerts FROM anon;
REVOKE SELECT ON public.communication_templates FROM anon;

-- Curation / governance docs (admin/leader-tier; anon reaches via SECDEF RPCs)
REVOKE SELECT ON public.cr_approvals FROM anon;
REVOKE SELECT ON public.governance_documents FROM anon;
REVOKE SELECT ON public.manual_sections FROM anon;

-- Knowledge / wiki (admin/member-tier via SECDEF RPCs)
REVOKE SELECT ON public.knowledge_assets FROM anon;
REVOKE SELECT ON public.knowledge_chunks FROM anon;
REVOKE SELECT ON public.knowledge_ingestion_runs FROM anon;
REVOKE SELECT ON public.knowledge_insights FROM anon;
REVOKE SELECT ON public.wiki_pages FROM anon;
REVOKE SELECT ON public.meeting_action_items FROM anon;

-- Sustainability / KPI (admin)
REVOKE SELECT ON public.cost_categories FROM anon;
REVOKE SELECT ON public.cost_entries FROM anon;
REVOKE SELECT ON public.revenue_categories FROM anon;
REVOKE SELECT ON public.revenue_entries FROM anon;
REVOKE SELECT ON public.sustainability_kpi_targets FROM anon;

-- Selection / VEP (admin)
REVOKE SELECT ON public.selection_membership_snapshots FROM anon;
REVOKE SELECT ON public.selection_ranking_snapshots FROM anon;
REVOKE SELECT ON public.vep_opportunities FROM anon;

-- Partner CRUD (admin/leader-tier)
REVOKE SELECT ON public.partner_cards FROM anon;
REVOKE SELECT ON public.partner_chapters FROM anon;
REVOKE SELECT ON public.partner_interactions FROM anon;

-- Publication submissions internals (member-tier via SECDEF RPCs)
REVOKE SELECT ON public.publication_submission_authors FROM anon;
REVOKE SELECT ON public.publication_submission_events FROM anon;

-- Course / member-tier learning data
REVOKE SELECT ON public.course_progress FROM anon;

-- Misc (admin)
REVOKE SELECT ON public.chapter_needs FROM anon;
REVOKE SELECT ON public.chapter_registry FROM anon;
REVOKE SELECT ON public.privacy_policy_versions FROM anon;
REVOKE SELECT ON public.tags FROM anon;
REVOKE SELECT ON public.taxonomy_tags FROM anon;
REVOKE SELECT ON public.webinar_lifecycle_events FROM anon;
REVOKE SELECT ON public.ingestion_remediation_escalation_matrix FROM anon;
REVOKE SELECT ON public.ingestion_source_controls FROM anon;
REVOKE SELECT ON public.ingestion_source_sla FROM anon;

-- ============================================================
-- (c) Views — 0 anon-tier .from() callers (7)
-- ============================================================
REVOKE SELECT ON public.auth_engagements FROM anon;
REVOKE SELECT ON public.impact_hours_summary FROM anon;
REVOKE SELECT ON public.member_attendance_summary FROM anon;
REVOKE SELECT ON public.recurring_event_groups FROM anon;
REVOKE SELECT ON public.vw_exec_cert_timeline FROM anon;
REVOKE SELECT ON public.vw_exec_skills_radar FROM anon;
REVOKE SELECT ON public.cycle_tribe_dim FROM anon;
