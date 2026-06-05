-- ============================================================
-- p250 #354 — SPEC #348 Child #1 Foundation (DDL only, no behavior change)
-- ------------------------------------------------------------
-- WHAT: Schema groundwork for per-evaluator booking URL routing.
--   1. ALTER members ADD COLUMN interview_booking_url text (personal evaluator
--      calendar/booking pool URL).
--   2. ALTER selection_committee ADD COLUMN interview_booking_url text (optional
--      cycle-scoped override of the member-global URL).
--   3. CREATE TABLE selection_dispatch_url_log (audit log of which URL was
--      resolved + which path produced it per dispatch) with V4 canonical RLS
--      (deny-all + org-scope pair).
--
-- WHY: Cycle 4 dispatch (p243) used selection_cycles.interview_booking_url
--   group/dual link as the only option. SPEC #348 (p249) splits routing by
--   track: researcher → per-evaluator (committee override → member global
--   → cycle fallback) with LRD round-robin; leader → cycle-level group.
--   #354 ships the SCHEMA only; routing logic lands in Child #2 (#355).
--   No RPC body changes here — submit_evaluation, notify_selection_cutoff_approved,
--   compute_application_scores, and friends are untouched.
--
-- ROLLBACK: drop in reverse order:
--   DROP TABLE public.selection_dispatch_url_log;
--   ALTER TABLE public.selection_committee DROP COLUMN interview_booking_url;
--   ALTER TABLE public.members DROP COLUMN interview_booking_url;
--   Safe because no dependent RPC, no UI surface, no live data when this lands.
--
-- INVARIANTS: 19/19=0 unchanged. No domain entity changes; new audit table is
--   additive and org-scoped per the same pattern as selection_evaluations,
--   selection_interviews, selection_committee, etc.
--
-- RLS NOTE (p250 PM ratification): spec §4.1 draft used
--   `rls_can('view_selection') OR rls_can('manage_member')` but 'view_selection'
--   is not in engagement_kind_permissions and would silently deny everyone
--   except manage_member holders. The dominant convention across selection_*
--   tables is the V4 deny-all + org-scope pair (rpc_only_deny_all + v4_org_scope).
--   All reads happen via SECDEF RPCs. Admin/audit RPC can be added in Child #2
--   or later if direct SELECT becomes useful. PM ratified Option A 2026-05-24.
--
-- Cross-refs:
--   - Spec: docs/specs/SPEC_348_BOOKING_URL_PER_EVALUATOR.md §4.1 (RLS section
--     amended to match this migration).
--   - Parent issue: #348 (PM 4-step booking_url roadmap)
--   - This issue: #354 (Child #1 Foundation)
--   - Child #2: #355 (RPC body — gated on this migration)
--   - Child #3: #356 (admin UI for members.interview_booking_url)
--   - Child #4: #357 (cycle4-2026 committee seed; URLs NULL)
-- ============================================================

-- 1. Per-evaluator URL (global, member-level)
ALTER TABLE public.members
  ADD COLUMN interview_booking_url text;

COMMENT ON COLUMN public.members.interview_booking_url IS
  'Personal calendar/booking pool URL for this evaluator. Used by selection auto-dispatch when this member is on the researcher-track committee. Falls back to cycle-level URL if NULL. See SPEC #348 / issue #354.';

-- 2. Per-cycle committee override (optional)
ALTER TABLE public.selection_committee
  ADD COLUMN interview_booking_url text;

COMMENT ON COLUMN public.selection_committee.interview_booking_url IS
  'Optional cycle-scoped override of members.interview_booking_url. Use when a single evaluator runs a different calendar pool for this specific cycle. See SPEC #348 / issue #354.';

-- 3. Dispatch audit (capture which URL was used per dispatch)
CREATE TABLE IF NOT EXISTS public.selection_dispatch_url_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES public.selection_applications(id),
  cycle_id uuid NOT NULL REFERENCES public.selection_cycles(id),
  track text NOT NULL CHECK (track IN ('researcher', 'leader')),
  resolved_url text NOT NULL,
  resolution_path text NOT NULL CHECK (resolution_path IN (
    'committee_override', 'member_global', 'cycle_fallback'
  )),
  resolved_evaluator_id uuid REFERENCES public.members(id),
  dispatched_at timestamptz NOT NULL DEFAULT now(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id)
);

COMMENT ON TABLE public.selection_dispatch_url_log IS
  'Audit log: which booking URL was sent to each candidate during selection cutoff dispatch, and which precedence rule produced it (committee_override > member_global > cycle_fallback). Drives LRD round-robin in researcher track. Insert-only via SECDEF RPC notify_selection_cutoff_approved (Child #2 / #355). See SPEC #348.';

CREATE INDEX selection_dispatch_url_log_app_idx
  ON public.selection_dispatch_url_log (application_id);

CREATE INDEX selection_dispatch_url_log_cycle_round_robin_idx
  ON public.selection_dispatch_url_log (cycle_id, track, resolved_evaluator_id, dispatched_at DESC)
  WHERE track = 'researcher';

-- RLS — V4 canonical pair (deny-all + org-scope), matches every other selection_* table
ALTER TABLE public.selection_dispatch_url_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY rpc_only_deny_all
  ON public.selection_dispatch_url_log
  FOR ALL
  USING (false);

CREATE POLICY selection_dispatch_url_log_v4_org_scope
  ON public.selection_dispatch_url_log
  FOR ALL
  USING ((organization_id = auth_org()) OR (organization_id IS NULL));

-- Sanity DO: assert that the three new schema artifacts exist before NOTIFY
DO $$
DECLARE
  v_members_col boolean;
  v_committee_col boolean;
  v_table boolean;
  v_app_idx boolean;
  v_rr_idx boolean;
  v_deny_pol boolean;
  v_orgscope_pol boolean;
BEGIN
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='members'
                    AND column_name='interview_booking_url')
    INTO v_members_col;
  IF NOT v_members_col THEN
    RAISE EXCEPTION 'p250 #354: members.interview_booking_url not created';
  END IF;

  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='selection_committee'
                    AND column_name='interview_booking_url')
    INTO v_committee_col;
  IF NOT v_committee_col THEN
    RAISE EXCEPTION 'p250 #354: selection_committee.interview_booking_url not created';
  END IF;

  SELECT EXISTS (SELECT 1 FROM information_schema.tables
                  WHERE table_schema='public' AND table_name='selection_dispatch_url_log')
    INTO v_table;
  IF NOT v_table THEN
    RAISE EXCEPTION 'p250 #354: selection_dispatch_url_log not created';
  END IF;

  SELECT EXISTS (SELECT 1 FROM pg_indexes
                  WHERE schemaname='public'
                    AND indexname='selection_dispatch_url_log_app_idx')
    INTO v_app_idx;
  SELECT EXISTS (SELECT 1 FROM pg_indexes
                  WHERE schemaname='public'
                    AND indexname='selection_dispatch_url_log_cycle_round_robin_idx')
    INTO v_rr_idx;
  IF NOT v_app_idx OR NOT v_rr_idx THEN
    RAISE EXCEPTION 'p250 #354: required indexes missing (app_idx=%, rr_idx=%)', v_app_idx, v_rr_idx;
  END IF;

  SELECT EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
                  JOIN pg_namespace n ON n.oid = c.relnamespace
                  WHERE n.nspname='public'
                    AND c.relname='selection_dispatch_url_log'
                    AND p.polname='rpc_only_deny_all')
    INTO v_deny_pol;
  SELECT EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
                  JOIN pg_namespace n ON n.oid = c.relnamespace
                  WHERE n.nspname='public'
                    AND c.relname='selection_dispatch_url_log'
                    AND p.polname='selection_dispatch_url_log_v4_org_scope')
    INTO v_orgscope_pol;
  IF NOT v_deny_pol OR NOT v_orgscope_pol THEN
    RAISE EXCEPTION 'p250 #354: RLS V4 pair missing (deny=%, orgscope=%)', v_deny_pol, v_orgscope_pol;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
