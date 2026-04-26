-- Track Q-D batch 3b — internal helpers REVOKE (defense-in-depth)
-- See docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md (Phase Q-D charter).
--
-- Internal helper = SECDEF function called only by other SECDEF functions
-- (and/or by EF via service_role). Never reachable from a `.rpc(name)` call
-- in `src/`. The `authenticated` (or PUBLIC) grant on these is unused
-- attack surface; removing it is defense-in-depth without behavioural change
-- because the SECDEF chain runs as definer (postgres) and EF connects as
-- service_role.
--
-- 20 fns triaged via:
--   * tight `.rpc('<name>')` regex grep across `src/` + `supabase/functions/`
--   * `pg_proc.prosrc` regex `\m<name>\s*\(` to count SECDEF callers
--   * confirmed 0 frontend .rpc() calls and 0-1 EF (service_role) caller
--
-- Caller chains documented inline.
--
-- Pattern: REVOKE FROM PUBLIC, anon, authenticated.
-- postgres + service_role retained throughout.

-- Governance gate notification chain
REVOKE EXECUTE ON FUNCTION public._enqueue_gate_notifications(uuid, text, text)
  FROM PUBLIC, anon, authenticated;
  -- callers: lock_document_version, trg_approval_signoff_notify_fn

-- Analytics scope helper (shared by 4 exec_* sub-queries)
REVOKE EXECUTE ON FUNCTION public.analytics_member_scope(text, integer, text)
  FROM PUBLIC, anon, authenticated;
  -- callers: exec_certification_delta, exec_chapter_roi, exec_funnel_summary, exec_impact_hours_v2

-- V4 capability assertion helper (used by initiative readers)
REVOKE EXECUTE ON FUNCTION public.assert_initiative_capability(uuid, text)
  FROM PUBLIC, anon, authenticated;
  -- callers: list_initiative_boards, list_initiative_deliverables,
  --          list_initiative_meeting_artifacts, search_initiative_board_items

-- V4 org-resolution helper
REVOKE EXECUTE ON FUNCTION public.auth_org()
  FROM PUBLIC, anon, authenticated;
  -- callers: create_initiative, join_initiative, list_initiatives

-- Broadcast counting helpers (legacy + V4)
REVOKE EXECUTE ON FUNCTION public.broadcast_count_today(integer)
  FROM PUBLIC, anon, authenticated;
  -- caller: broadcast_count_today_v4
REVOKE EXECUTE ON FUNCTION public.broadcast_count_today_v4(uuid)
  FROM PUBLIC, anon, authenticated;
  -- 0 SECDEF callers, 0 app callers — appears dead;
  -- preserved (not dropped) pending PM review of broadcast pipeline.

-- V4 authority core
REVOKE EXECUTE ON FUNCTION public.can(uuid, text, text, uuid)
  FROM PUBLIC, anon, authenticated;
  -- callers: activate_initiative, can_by_member, create_initiative_event,
  --          get_active_engagements, get_initiative_member_contacts, get_person,
  --          manage_initiative_engagement, rls_can (8 fns total)
  -- frontend never calls `can` directly (uses cached operational_role per
  -- src/lib/permissions.ts comment); EF calls `can_by_member` instead.
REVOKE EXECUTE ON FUNCTION public.can_by_member(uuid, text, text, uuid)
  FROM PUBLIC, anon, authenticated;
  -- callers: 100 SECDEF V4 admin fns + 1 EF (nucleo-mcp/canV4 wrapper);
  -- EF runs as service_role → role retains EXECUTE; frontend never calls
  -- directly (uses cached operational_role).

-- Onboarding / pre-onboarding helper
REVOKE EXECUTE ON FUNCTION public.check_pre_onboarding_auto_steps(uuid)
  FROM PUBLIC, anon, authenticated;
  -- callers: admin_update_application, finalize_decisions, get_candidate_onboarding_progress

-- Offboarding cascade helper
REVOKE EXECUTE ON FUNCTION public.detect_orphan_assignees_from_offboards(uuid)
  FROM PUBLIC, anon, authenticated;
  -- caller: notify_offboard_cascade

-- Analytics dashboard sub-queries
REVOKE EXECUTE ON FUNCTION public.exec_analytics_v2_quality(text, integer, text)
  FROM PUBLIC, anon, authenticated;
  -- 0 SECDEF callers; calls 3 sub-helpers (chapter_roi, funnel_summary,
  -- impact_hours_v2). Possibly orchestrator-only or admin-cron caller;
  -- preserved (not dropped) pending PM review.
REVOKE EXECUTE ON FUNCTION public.exec_certification_delta(text, integer, text)
  FROM PUBLIC, anon, authenticated;
  -- 0 SECDEF callers; preserved pending PM review.
REVOKE EXECUTE ON FUNCTION public.exec_chapter_roi(text, integer, text)
  FROM PUBLIC, anon, authenticated;
  -- caller: exec_analytics_v2_quality
REVOKE EXECUTE ON FUNCTION public.exec_funnel_summary(text, integer, text)
  FROM PUBLIC, anon, authenticated;
  -- caller: exec_analytics_v2_quality
REVOKE EXECUTE ON FUNCTION public.exec_impact_hours_v2(text, integer, text)
  FROM PUBLIC, anon, authenticated;
  -- caller: exec_analytics_v2_quality

-- Adoption / dashboard sub-queries
REVOKE EXECUTE ON FUNCTION public.get_auth_provider_stats()
  FROM PUBLIC, anon, authenticated;
  -- caller: get_adoption_dashboard
REVOKE EXECUTE ON FUNCTION public.get_impact_hours_excluding_excused()
  FROM PUBLIC, anon, authenticated;
  -- callers: get_admin_dashboard (SECDEF), sync-artia EF (service_role)
REVOKE EXECUTE ON FUNCTION public.get_mcp_adoption_stats()
  FROM PUBLIC, anon, authenticated;
  -- callers: get_adoption_dashboard (SECDEF), nucleo-mcp EF (service_role)

-- Member tribe lookup helper
REVOKE EXECUTE ON FUNCTION public.get_member_tribe(uuid)
  FROM PUBLIC, anon, authenticated;
  -- callers: 8 SECDEF fns (exec_tribe_dashboard, get_admin_dashboard,
  --          get_adoption_dashboard, get_attendance_grid, get_campaign_analytics,
  --          get_my_member_record, get_tribe_attendance_grid, sign_volunteer_agreement)

-- Refresh utility
REVOKE EXECUTE ON FUNCTION public.refresh_cycle_tribe_dim()
  FROM PUBLIC, anon, authenticated;
  -- caller: trigger_refresh_cycle_tribe_dim
