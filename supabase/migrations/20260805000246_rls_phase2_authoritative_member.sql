-- RLS Phase 2 — tighten the remaining rls_is_member() SELECT policies to rls_is_authoritative_member()
--
-- Follow-up to Phase 1 (20260805000243, #869). Phase 1 hardened ONE policy
-- (members_read_by_members). This migration handles the remaining SELECT policies that
-- still gated on rls_is_member() = EXISTS(member row for auth.uid()) — row-existence only,
-- which is TRUE for pre-onboarding GUESTS (operational_role='guest', unsigned volunteer term,
-- non-authoritative engagement). A guest therefore read the FULL collaborative dataset on
-- every one of these tables, identical to a real member (verified live, audit
-- docs/audit/RLS_PHASE2_RLS_IS_MEMBER_AUDIT_2026-06-24.md).
--
-- rls_is_authoritative_member() (Phase 1 helper) = active member with operational_role <> 'guest'.
-- Swapping removes ONLY guests; the 40 authoritative members keep access (behavior-neutral for them).
-- Only DIRECT PostgREST .from() reads under the end-user JWT are affected; SECURITY DEFINER RPCs
-- and service_role paths bypass RLS and are unaffected.
--
-- Grouping (see audit doc):
--   A/B: plain swap (no guest-reachable direct read).
--   C:   own-row carve-out (gamification_points/attendance/publication_submissions have a guest-reachable
--        self-scoped direct read with NO separate own-row policy → keep self-read, drop directory read).
--   D:   course_progress plain swap (own-row preserved by the separate 'Auth update progress' policy).
--   E:   publication_series — also fix role divergence {public}→{authenticated}.
--   F:   events — LEAVE (events_select_org_scope is genuinely PERMISSIVE and backfills; semi-public by design).
-- Plus: REVOKE latent anon SELECT grants (no anon SELECT policy exists; events anon grant is load-bearing, kept).
--
-- ROLLBACK: restore each policy's USING to public.rls_is_member() (Group A/B/C/D) /
--   restore publication_series_read_members TO public USING rls_is_member() (Group E) /
--   GRANT SELECT ... TO anon (revokes).

BEGIN;

-- ── Group A: plain swap rls_is_member() → rls_is_authoritative_member() ───────────────
ALTER POLICY board_items_read_members          ON public.board_items                  USING (public.rls_is_authoritative_member());
ALTER POLICY assignments_read_members          ON public.board_item_assignments       USING (public.rls_is_authoritative_member());
ALTER POLICY checklists_read_members           ON public.board_item_checklists        USING (public.rls_is_authoritative_member());
ALTER POLICY tag_assignments_read_members      ON public.board_item_tag_assignments   USING (public.rls_is_authoritative_member());
ALTER POLICY project_boards_read_members       ON public.project_boards               USING (public.rls_is_authoritative_member());
ALTER POLICY audience_rules_read_members       ON public.event_audience_rules         USING (public.rls_is_authoritative_member());
ALTER POLICY invited_read_members              ON public.event_invited_members        USING (public.rls_is_authoritative_member());
ALTER POLICY event_tags_read_members           ON public.event_tag_assignments        USING (public.rls_is_authoritative_member());
ALTER POLICY webinars_read_authenticated       ON public.webinars                     USING (public.rls_is_authoritative_member() OR status = ANY (ARRAY['confirmed'::text, 'completed'::text]));
ALTER POLICY wle_read_members                  ON public.webinar_lifecycle_events     USING (public.rls_is_authoritative_member());
ALTER POLICY sub_authors_read_members          ON public.publication_submission_authors USING (public.rls_is_authoritative_member());
ALTER POLICY sub_events_read_members           ON public.publication_submission_events  USING (public.rls_is_authoritative_member());
ALTER POLICY partners_read_members             ON public.partner_entities             USING (public.rls_is_authoritative_member());  -- HIGH: contact_email/contact_name PII
ALTER POLICY cr_read_members                   ON public.change_requests              USING (public.rls_is_authoritative_member());
ALTER POLICY drive_file_discoveries_read_authenticated ON public.drive_file_discoveries USING (public.rls_is_authoritative_member());
ALTER POLICY initiative_drive_links_read_authenticated ON public.initiative_drive_links USING (public.rls_is_authoritative_member());

-- ── Group B: plain swap (board_item_files keeps its deleted_at guard) ─────────────────
ALTER POLICY board_item_files_read_authenticated ON public.board_item_files           USING (deleted_at IS NULL AND public.rls_is_authoritative_member());
ALTER POLICY board_drive_links_read_authenticated ON public.board_drive_links         USING (public.rls_is_authoritative_member());

-- ── Group C: own-row carve-out (preserve the guest/member self-read on /profile + /gamification) ──
ALTER POLICY gamification_read_members ON public.gamification_points
  USING (public.rls_is_authoritative_member() OR member_id IN (SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid()));
ALTER POLICY attendance_read_members ON public.attendance
  USING (public.rls_is_authoritative_member() OR member_id IN (SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid()));
ALTER POLICY submissions_read_members ON public.publication_submissions
  USING (public.rls_is_authoritative_member() OR primary_author_id IN (SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid()));

-- ── Group D: course_progress — own-row already preserved by separate 'Auth update progress' policy ──
ALTER POLICY course_progress_read_members ON public.course_progress USING (public.rls_is_authoritative_member());

-- ── Group E: publication_series — fix role divergence ({public}→{authenticated}) + swap ──
ALTER POLICY publication_series_read_members ON public.publication_series TO authenticated USING (public.rls_is_authoritative_member());

-- ── Latent anon SELECT grant revoke (defense-in-depth; no anon SELECT policy uses these;
--    events anon grant is load-bearing for the public homepage and is intentionally kept) ──
REVOKE SELECT ON public.board_item_files       FROM anon;
REVOKE SELECT ON public.board_drive_links      FROM anon;
REVOKE SELECT ON public.drive_file_discoveries FROM anon;
REVOKE SELECT ON public.gamification_points    FROM anon;
REVOKE SELECT ON public.initiative_drive_links FROM anon;

NOTIFY pgrst, 'reload schema';

COMMIT;
