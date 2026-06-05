-- Migration: 20260805000046_p266_382_w4f_blind_review_primitives
-- Date:      2026-05-26 (Session p266)
-- Issue:     #382 (W4f blind-review primitives — Primitives PR-B of 2) — CLOSES #382
-- ADR:       0099 (content_products canonical surface — §2.7 + §7 steps 10-11)
-- Spec ref:  SPEC_GOVERNANCE_DOCUMENTS_END_TO_END §6.1 row 4 + §11 row 4 + §15.7 step 5
-- Predecessor: 20260805000045 (PR-A Foundation — content_products + bridges + reader/list + invariant W)
--
-- WHAT
-- ----
-- Primitives PR-B for #382. Creates the 3 blind-review tables anchored to
-- content_products.id (ADR-0099 §2.7 load-bearing), enforces reviewer
-- isolation under content_products.review_mode='independent_blind' via
-- RLS + reader RPC defense-in-depth, ships 2 writer RPCs (submit_blind_parecer
-- + release_blind_reviews) + 1 reader RPC (get_blind_review_session), and
-- adds invariant X_blind_review_pareceres_session_product_match (total 22 -> 23).
-- Sessions and assignments are created via admin/service-role path in this
-- wave (start_blind_review_session + assign_blind_reviewer deferred per PM D3).
--
-- WHY
-- ---
-- Per #382 acceptance criteria + ADR-0099 §2.7: blind-review primitives must
-- (a) anchor exclusively to content_products.id (no polymorphic FK at review
-- surface) and (b) honor review_mode='independent_blind' visibility -- reviewer
-- A must not see reviewer B's parecer until both have submitted. The Foundation
-- (PR-A) shipped the content_products surface and review_mode enum; this PR-B
-- ships the review tables themselves.
--
-- PM ratified (p266 dispatch via AskUserQuestion 2026-05-26):
-- - D1: release = auto-when-all-submitted + explicit fallback (no threshold %)
-- - D2: isolation = RLS + reader RPC (defense in depth)
-- - D3: writer scope = submit_blind_parecer + release_blind_reviews only
--       (start_blind_review_session + assign_blind_reviewer deferred to PR
--       when admin UI ships)
-- - D4: invariant X_blind_review_pareceres_session_product_match (22 -> 23)
--
-- Sediments respected
-- -------------------
-- - SEDIMENT-186.C: new contract test file `tests/contracts/p266-382-w4f-blind-review-primitives.test.mjs`
--   added to BOTH `test` and `test:contracts` whitelists pre-`npm test`.
-- - SEDIMENT-225.B: inline -- comments minimized inside $function$ blocks;
--   Phase C body-drift gate must pass after deploy (new RPCs are first capture).
-- - SEDIMENT-226.C: DB-gated smoke uses JWT-claim DO blocks for two distinct
--   member contexts to prove reviewer A cannot read reviewer B's parecer in
--   independent_blind mode pre-submission.
-- - SEDIMENT-238.C: check_schema_invariants() CREATE OR REPLACE preserves all
--   22 existing RETURN QUERY blocks verbatim (A1, A2, A3, B, C, D, E, F, J,
--   K, L, M, N, O, P, Q, R, S, T, V_prime, V_status, W) before appending X.
-- - SEDIMENT-239b.A (CRITICAL): submit_blind_parecer.reviewer_member_id is FK
--   to members(id); MUST resolve via `members WHERE auth_id=auth.uid()` and
--   use v_caller_member_id local; never auth.uid() direct. Same for
--   release_blind_reviews.released_by_member_id. Contract test asserts FK
--   column source explicitly (forward-defense regression class lock).
-- - SEDIMENT-254.A: NO ad-hoc cleanup of supabase_migrations.schema_migrations;
--   shadow row from apply_migration MCP will be inspected post-apply and
--   cleaned via EXACT `WHERE version = '20260805000046'` only.
--
-- ROLLBACK
-- --------
-- (Reverse order; preserve atomicity; assumes no consumer started writing yet)
-- 1.  Restore check_schema_invariants() to pre-p266 body (without X).
-- 2.  DROP FUNCTION public.get_blind_review_session(uuid);
-- 3.  DROP FUNCTION public.release_blind_reviews(uuid, text);
-- 4.  DROP FUNCTION public.submit_blind_parecer(uuid, text, text);
-- 5.  DROP TRIGGER trg_blind_review_pareceres_updated_at ON public.blind_review_pareceres;
-- 6.  DROP FUNCTION public.trg_blind_review_pareceres_set_updated_at();
-- 7.  DROP TRIGGER trg_blind_review_sessions_updated_at ON public.blind_review_sessions;
-- 8.  DROP FUNCTION public.trg_blind_review_sessions_set_updated_at();
-- 9.  DROP TABLE public.blind_review_pareceres CASCADE;
-- 10. DROP TABLE public.blind_review_assignments CASCADE;
-- 11. DROP TABLE public.blind_review_sessions CASCADE;
-- 12. NOTIFY pgrst, 'reload schema';
-- (Data loss only if blind-review writes happened post-apply; greenfield expected.)

BEGIN;

-- ============================================================================
-- §7 STEP 10a -- blind_review_sessions
-- ============================================================================

CREATE TABLE public.blind_review_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  content_product_id uuid NOT NULL
    REFERENCES public.content_products(id) ON DELETE RESTRICT,
  organization_id uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid
    REFERENCES public.organizations(id) ON DELETE RESTRICT,
  review_round smallint NOT NULL DEFAULT 1
    CONSTRAINT chk_blind_review_sessions_round_positive CHECK (review_round >= 1),
  status text NOT NULL DEFAULT 'open'
    CONSTRAINT chk_blind_review_sessions_status
      CHECK (status IN ('open','released','closed')),
  released_at timestamptz NULL,
  released_by_member_id uuid NULL REFERENCES public.members(id) ON DELETE SET NULL,
  release_kind text NULL
    CONSTRAINT chk_blind_review_sessions_release_kind
      CHECK (release_kind IS NULL OR release_kind IN ('auto_all_submitted','explicit_admin','explicit_curator')),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid NULL REFERENCES public.members(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  closed_at timestamptz NULL,
  CONSTRAINT chk_blind_review_sessions_released_consistency
    CHECK (
      (released_at IS NULL AND release_kind IS NULL AND released_by_member_id IS NULL)
      OR (released_at IS NOT NULL AND release_kind = 'auto_all_submitted')
      OR (released_at IS NOT NULL AND release_kind IN ('explicit_admin','explicit_curator')
          AND released_by_member_id IS NOT NULL)
    )
);

CREATE INDEX idx_blind_review_sessions_content_product
  ON public.blind_review_sessions(content_product_id);

CREATE INDEX idx_blind_review_sessions_status
  ON public.blind_review_sessions(status);

CREATE INDEX idx_blind_review_sessions_released_at
  ON public.blind_review_sessions(released_at)
  WHERE released_at IS NOT NULL;

ALTER TABLE public.blind_review_sessions ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.trg_blind_review_sessions_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_blind_review_sessions_updated_at
BEFORE UPDATE ON public.blind_review_sessions
FOR EACH ROW
EXECUTE FUNCTION public.trg_blind_review_sessions_set_updated_at();

-- ============================================================================
-- §7 STEP 10b -- blind_review_assignments
-- ============================================================================

CREATE TABLE public.blind_review_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL
    REFERENCES public.blind_review_sessions(id) ON DELETE CASCADE,
  reviewer_member_id uuid NOT NULL
    REFERENCES public.members(id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'active'
    CONSTRAINT chk_blind_review_assignments_status
      CHECK (status IN ('active','withdrawn','replaced')),
  assigned_at timestamptz NOT NULL DEFAULT now(),
  assigned_by_member_id uuid NULL REFERENCES public.members(id) ON DELETE SET NULL,
  withdrawn_at timestamptz NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT uq_blind_review_assignments_session_reviewer
    UNIQUE (session_id, reviewer_member_id)
);

CREATE INDEX idx_blind_review_assignments_reviewer
  ON public.blind_review_assignments(reviewer_member_id);

CREATE INDEX idx_blind_review_assignments_session
  ON public.blind_review_assignments(session_id);

CREATE INDEX idx_blind_review_assignments_active
  ON public.blind_review_assignments(session_id, reviewer_member_id)
  WHERE status = 'active';

ALTER TABLE public.blind_review_assignments ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- §7 STEP 10c -- blind_review_pareceres
-- ============================================================================

CREATE TABLE public.blind_review_pareceres (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL
    REFERENCES public.blind_review_sessions(id) ON DELETE CASCADE,
  reviewer_member_id uuid NOT NULL
    REFERENCES public.members(id) ON DELETE RESTRICT,
  parecer_body text NULL,
  recommendation text NULL
    CONSTRAINT chk_blind_review_pareceres_recommendation
      CHECK (recommendation IS NULL OR recommendation IN ('accept','minor_revisions','major_revisions','reject','abstain')),
  submitted_at timestamptz NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_blind_review_pareceres_session_reviewer
    UNIQUE (session_id, reviewer_member_id),
  CONSTRAINT chk_blind_review_pareceres_submitted_body
    CHECK (submitted_at IS NULL OR (parecer_body IS NOT NULL AND length(trim(parecer_body)) > 0))
);

CREATE INDEX idx_blind_review_pareceres_session
  ON public.blind_review_pareceres(session_id);

CREATE INDEX idx_blind_review_pareceres_reviewer
  ON public.blind_review_pareceres(reviewer_member_id);

CREATE INDEX idx_blind_review_pareceres_submitted
  ON public.blind_review_pareceres(session_id, submitted_at)
  WHERE submitted_at IS NOT NULL;

ALTER TABLE public.blind_review_pareceres ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.trg_blind_review_pareceres_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_blind_review_pareceres_updated_at
BEFORE UPDATE ON public.blind_review_pareceres
FOR EACH ROW
EXECUTE FUNCTION public.trg_blind_review_pareceres_set_updated_at();

-- ============================================================================
-- §7 STEP 10d -- RLS policies (defense-in-depth reviewer isolation; ADR §2.7 + PM D2)
-- ============================================================================

-- blind_review_sessions: assignees + admin/curator can SELECT
CREATE POLICY blind_review_sessions_select
  ON public.blind_review_sessions FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid() AND m.is_active = true
        AND (
          public.can_by_member(m.id, 'manage_member')
          OR public.can_by_member(m.id, 'curate_content')
          OR EXISTS (
            SELECT 1 FROM public.blind_review_assignments a
            WHERE a.session_id = blind_review_sessions.id
              AND a.reviewer_member_id = m.id
              AND a.status = 'active'
          )
        )
    )
  );

-- blind_review_sessions: admin/curator can INSERT/UPDATE/DELETE for v1 (per PM D3, no dedicated start RPC yet)
CREATE POLICY blind_review_sessions_admin_curator_write
  ON public.blind_review_sessions FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid() AND m.is_active = true
        AND (public.can_by_member(m.id, 'manage_member') OR public.can_by_member(m.id, 'curate_content'))
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid() AND m.is_active = true
        AND (public.can_by_member(m.id, 'manage_member') OR public.can_by_member(m.id, 'curate_content'))
    )
  );

-- blind_review_assignments: assignees see all assignments in their sessions; admin/curator see all
CREATE POLICY blind_review_assignments_select
  ON public.blind_review_assignments FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid() AND m.is_active = true
        AND (
          public.can_by_member(m.id, 'manage_member')
          OR public.can_by_member(m.id, 'curate_content')
          OR EXISTS (
            SELECT 1 FROM public.blind_review_assignments a2
            WHERE a2.session_id = blind_review_assignments.session_id
              AND a2.reviewer_member_id = m.id
              AND a2.status = 'active'
          )
        )
    )
  );

-- blind_review_assignments: admin/curator can INSERT/UPDATE/DELETE for v1 (per PM D3)
CREATE POLICY blind_review_assignments_admin_curator_write
  ON public.blind_review_assignments FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid() AND m.is_active = true
        AND (public.can_by_member(m.id, 'manage_member') OR public.can_by_member(m.id, 'curate_content'))
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid() AND m.is_active = true
        AND (public.can_by_member(m.id, 'manage_member') OR public.can_by_member(m.id, 'curate_content'))
    )
  );

-- blind_review_pareceres SELECT: defense-in-depth reviewer-isolation (ADR-0099 §2.7)
-- Permissive policies (OR semantics):
--   policy A (admin/curator bypass): operational access for GP/curator
--   policy B (assignee isolation):
--     (b1) own parecer always visible to assignee
--     (b2) released session: all pareceres visible
--     (b3) non-blind mode (collaborative/sequential/governance_commentary): peer visible
--     (b4) blind mode + own submitted_at NOT NULL + peer submitted_at NOT NULL: peer visible
CREATE POLICY blind_review_pareceres_admin_curator_read
  ON public.blind_review_pareceres FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid() AND m.is_active = true
        AND (public.can_by_member(m.id, 'manage_member') OR public.can_by_member(m.id, 'curate_content'))
    )
  );

CREATE POLICY blind_review_pareceres_assignee_isolation_read
  ON public.blind_review_pareceres FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members m
      JOIN public.blind_review_assignments a
        ON a.session_id = blind_review_pareceres.session_id
        AND a.reviewer_member_id = m.id
        AND a.status = 'active'
      WHERE m.auth_id = auth.uid() AND m.is_active = true
    )
    AND (
      reviewer_member_id = (
        SELECT m.id FROM public.members m
        WHERE m.auth_id = auth.uid() AND m.is_active = true LIMIT 1
      )
      OR EXISTS (
        SELECT 1 FROM public.blind_review_sessions s
        WHERE s.id = blind_review_pareceres.session_id
          AND s.released_at IS NOT NULL
      )
      OR EXISTS (
        SELECT 1 FROM public.blind_review_sessions s
        JOIN public.content_products cp ON cp.id = s.content_product_id
        WHERE s.id = blind_review_pareceres.session_id
          AND cp.review_mode IN (
            'collaborative'::public.review_mode,
            'sequential'::public.review_mode,
            'governance_commentary'::public.review_mode
          )
      )
      OR (
        blind_review_pareceres.submitted_at IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM public.blind_review_pareceres own_p
          JOIN public.members own_m ON own_m.id = own_p.reviewer_member_id
          WHERE own_m.auth_id = auth.uid()
            AND own_p.session_id = blind_review_pareceres.session_id
            AND own_p.submitted_at IS NOT NULL
        )
      )
    )
  );

-- blind_review_pareceres UPDATE: reviewer can update own un-submitted parecer (edit-before-submit path)
CREATE POLICY blind_review_pareceres_own_update
  ON public.blind_review_pareceres FOR UPDATE TO authenticated
  USING (
    reviewer_member_id = (
      SELECT m.id FROM public.members m
      WHERE m.auth_id = auth.uid() AND m.is_active = true LIMIT 1
    )
    AND submitted_at IS NULL
  )
  WITH CHECK (
    reviewer_member_id = (
      SELECT m.id FROM public.members m
      WHERE m.auth_id = auth.uid() AND m.is_active = true LIMIT 1
    )
  );

-- ============================================================================
-- §7 STEP 10e -- RPC submit_blind_parecer (SECDEF)
-- Inserts caller's parecer with submitted_at = now(); if all active assignments
-- have submitted, auto-releases session with release_kind='auto_all_submitted'.
-- SEDIMENT-239b.A: caller resolved via members WHERE auth_id=auth.uid();
-- v_caller_member_id used as FK source for reviewer_member_id (never auth.uid()).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.submit_blind_parecer(
  p_session_id uuid,
  p_parecer_body text,
  p_recommendation text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_session public.blind_review_sessions%ROWTYPE;
  v_assignment_exists boolean;
  v_existing_parecer_id uuid;
  v_existing_submitted_at timestamptz;
  v_parecer_id uuid;
  v_active_assignments int;
  v_submitted_pareceres int;
  v_auto_released boolean := false;
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no active member record' USING ERRCODE = '42501';
  END IF;

  IF p_parecer_body IS NULL OR length(trim(p_parecer_body)) = 0 THEN
    RAISE EXCEPTION 'Invalid argument: parecer body must be non-empty'
      USING ERRCODE = '22023';
  END IF;

  IF p_recommendation IS NOT NULL
     AND p_recommendation NOT IN ('accept','minor_revisions','major_revisions','reject','abstain') THEN
    RAISE EXCEPTION 'Invalid argument: recommendation must be accept/minor_revisions/major_revisions/reject/abstain'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_session
  FROM public.blind_review_sessions
  WHERE id = p_session_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Not found: blind_review_session does not exist'
      USING ERRCODE = '02000';
  END IF;
  IF v_session.status <> 'open' THEN
    RAISE EXCEPTION 'Conflict: session status is %, expected open', v_session.status
      USING ERRCODE = '40000';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.blind_review_assignments
    WHERE session_id = p_session_id
      AND reviewer_member_id = v_caller_member_id
      AND status = 'active'
  ) INTO v_assignment_exists;
  IF NOT v_assignment_exists THEN
    RAISE EXCEPTION 'Unauthorized: caller has no active assignment in this session'
      USING ERRCODE = '42501';
  END IF;

  SELECT id, submitted_at INTO v_existing_parecer_id, v_existing_submitted_at
  FROM public.blind_review_pareceres
  WHERE session_id = p_session_id
    AND reviewer_member_id = v_caller_member_id;
  IF v_existing_submitted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Conflict: parecer already submitted; resubmission not allowed in v1'
      USING ERRCODE = '40000';
  END IF;

  IF v_existing_parecer_id IS NULL THEN
    INSERT INTO public.blind_review_pareceres (
      session_id, reviewer_member_id, parecer_body, recommendation, submitted_at
    ) VALUES (
      p_session_id, v_caller_member_id, p_parecer_body, p_recommendation, now()
    )
    RETURNING id INTO v_parecer_id;
  ELSE
    UPDATE public.blind_review_pareceres
    SET parecer_body = p_parecer_body,
        recommendation = p_recommendation,
        submitted_at = now()
    WHERE id = v_existing_parecer_id;
    v_parecer_id := v_existing_parecer_id;
  END IF;

  SELECT count(*) INTO v_active_assignments
  FROM public.blind_review_assignments
  WHERE session_id = p_session_id AND status = 'active';

  SELECT count(*) INTO v_submitted_pareceres
  FROM public.blind_review_pareceres p
  JOIN public.blind_review_assignments a
    ON a.session_id = p.session_id
    AND a.reviewer_member_id = p.reviewer_member_id
    AND a.status = 'active'
  WHERE p.session_id = p_session_id AND p.submitted_at IS NOT NULL;

  IF v_active_assignments > 0 AND v_submitted_pareceres >= v_active_assignments THEN
    UPDATE public.blind_review_sessions
    SET released_at = now(),
        released_by_member_id = NULL,
        release_kind = 'auto_all_submitted',
        status = 'released'
    WHERE id = p_session_id AND released_at IS NULL;
    IF FOUND THEN
      v_auto_released := true;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'parecer_id', v_parecer_id,
    'session_id', p_session_id,
    'submitted_at', now(),
    'auto_released', v_auto_released,
    'active_assignments', v_active_assignments,
    'submitted_pareceres', v_submitted_pareceres
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.submit_blind_parecer(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_blind_parecer(uuid, text, text) TO authenticated;

-- ============================================================================
-- §7 STEP 10f -- RPC release_blind_reviews (SECDEF)
-- Flips session.released_at + released_by_member_id + release_kind.
-- Gates: admin (manage_member) OR curator (curate_content) OR assignee with
-- own submitted parecer (#382 acceptance criteria + PM D1).
-- Idempotent on already-released sessions.
-- SEDIMENT-239b.A: released_by_member_id FK source is v_caller_member_id
-- resolved via members WHERE auth_id=auth.uid(), never auth.uid() direct.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.release_blind_reviews(
  p_session_id uuid,
  p_release_kind text DEFAULT 'explicit_admin'
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_caller_is_admin boolean := false;
  v_caller_is_curator boolean := false;
  v_caller_has_submitted boolean := false;
  v_session public.blind_review_sessions%ROWTYPE;
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no active member record' USING ERRCODE = '42501';
  END IF;

  IF p_release_kind NOT IN ('explicit_admin','explicit_curator') THEN
    RAISE EXCEPTION 'Invalid argument: release_kind must be explicit_admin or explicit_curator'
      USING ERRCODE = '22023';
  END IF;

  v_caller_is_admin := public.can_by_member(v_caller_member_id, 'manage_member');
  v_caller_is_curator := public.can_by_member(v_caller_member_id, 'curate_content');

  SELECT EXISTS (
    SELECT 1
    FROM public.blind_review_assignments a
    JOIN public.blind_review_pareceres p
      ON p.session_id = a.session_id
      AND p.reviewer_member_id = a.reviewer_member_id
    WHERE a.session_id = p_session_id
      AND a.reviewer_member_id = v_caller_member_id
      AND a.status = 'active'
      AND p.submitted_at IS NOT NULL
  ) INTO v_caller_has_submitted;

  IF NOT (v_caller_is_admin OR v_caller_is_curator OR v_caller_has_submitted) THEN
    RAISE EXCEPTION 'Unauthorized: release_blind_reviews requires manage_member, curate_content, or own submitted parecer'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_session
  FROM public.blind_review_sessions
  WHERE id = p_session_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Not found: blind_review_session does not exist'
      USING ERRCODE = '02000';
  END IF;

  IF v_session.released_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'ok', true,
      'session_id', p_session_id,
      'released_at', v_session.released_at,
      'release_kind', v_session.release_kind,
      'released_by_member_id', v_session.released_by_member_id,
      'idempotent', true
    );
  END IF;

  UPDATE public.blind_review_sessions
  SET released_at = now(),
      released_by_member_id = v_caller_member_id,
      release_kind = p_release_kind,
      status = 'released'
  WHERE id = p_session_id AND released_at IS NULL;

  RETURN jsonb_build_object(
    'ok', true,
    'session_id', p_session_id,
    'released_at', now(),
    'release_kind', p_release_kind,
    'released_by_member_id', v_caller_member_id,
    'idempotent', false
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.release_blind_reviews(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.release_blind_reviews(uuid, text) TO authenticated;

-- ============================================================================
-- §7 STEP 10g -- RPC get_blind_review_session (SECDEF, mode-aware visibility)
-- Reader returning session metadata + assignments list + pareceres with
-- mode-aware parecer_body/recommendation redaction.
--
-- Visibility table:
--   own parecer:                always visible
--   admin/curator:              all visible
--   released session:           all visible
--   non-blind mode:             all visible to assignees
--   independent_blind + caller submitted + peer submitted: peer visible
--   else: redacted (parecer_body NULL, is_redacted true, recommendation NULL)
--
-- Mirror p263 W4d + p264 W4e patterns:
--   gate 1: active membership (RAISE 42501)
--   gate 2: privacy-preserving null-envelope on session-not-found OR
--           on caller-not-assignee-not-admin-not-curator (no leakage about existence)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_blind_review_session(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_caller_is_admin boolean := false;
  v_caller_is_curator boolean := false;
  v_caller_is_assignee boolean := false;
  v_caller_submitted boolean := false;
  v_session public.blind_review_sessions%ROWTYPE;
  v_content_product public.content_products%ROWTYPE;
  v_assignments jsonb;
  v_pareceres jsonb;
  v_can_see_peer_pareceres boolean := false;
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no active member record' USING ERRCODE = '42501';
  END IF;

  v_caller_is_admin := public.can_by_member(v_caller_member_id, 'manage_member');
  v_caller_is_curator := public.can_by_member(v_caller_member_id, 'curate_content');

  SELECT * INTO v_session
  FROM public.blind_review_sessions
  WHERE id = p_session_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'session', NULL);
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.blind_review_assignments
    WHERE session_id = p_session_id
      AND reviewer_member_id = v_caller_member_id
      AND status = 'active'
  ) INTO v_caller_is_assignee;

  IF NOT (v_caller_is_admin OR v_caller_is_curator OR v_caller_is_assignee) THEN
    RETURN jsonb_build_object('ok', true, 'session', NULL);
  END IF;

  SELECT * INTO v_content_product
  FROM public.content_products
  WHERE id = v_session.content_product_id;

  SELECT EXISTS (
    SELECT 1 FROM public.blind_review_pareceres
    WHERE session_id = p_session_id
      AND reviewer_member_id = v_caller_member_id
      AND submitted_at IS NOT NULL
  ) INTO v_caller_submitted;

  v_can_see_peer_pareceres := (
    v_caller_is_admin
    OR v_caller_is_curator
    OR v_session.released_at IS NOT NULL
    OR v_content_product.review_mode IN (
      'collaborative'::public.review_mode,
      'sequential'::public.review_mode,
      'governance_commentary'::public.review_mode
    )
    OR (v_content_product.review_mode = 'independent_blind'::public.review_mode AND v_caller_submitted)
  );

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', a.id,
    'reviewer_member_id', a.reviewer_member_id,
    'status', a.status,
    'assigned_at', a.assigned_at,
    'withdrawn_at', a.withdrawn_at
  ) ORDER BY a.assigned_at, a.id), '[]'::jsonb)
  INTO v_assignments
  FROM public.blind_review_assignments a
  WHERE a.session_id = p_session_id;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'reviewer_member_id', p.reviewer_member_id,
    'parecer_body', CASE
      WHEN p.reviewer_member_id = v_caller_member_id THEN p.parecer_body
      WHEN v_can_see_peer_pareceres AND p.submitted_at IS NOT NULL THEN p.parecer_body
      ELSE NULL
    END,
    'recommendation', CASE
      WHEN p.reviewer_member_id = v_caller_member_id THEN p.recommendation
      WHEN v_can_see_peer_pareceres AND p.submitted_at IS NOT NULL THEN p.recommendation
      ELSE NULL
    END,
    'submitted_at', p.submitted_at,
    'is_own', (p.reviewer_member_id = v_caller_member_id),
    'is_redacted', NOT (
      p.reviewer_member_id = v_caller_member_id
      OR (v_can_see_peer_pareceres AND p.submitted_at IS NOT NULL)
    ),
    'created_at', p.created_at,
    'updated_at', p.updated_at
  ) ORDER BY p.created_at, p.id), '[]'::jsonb)
  INTO v_pareceres
  FROM public.blind_review_pareceres p
  WHERE p.session_id = p_session_id
    AND (
      v_caller_is_admin
      OR v_caller_is_curator
      OR p.reviewer_member_id = v_caller_member_id
      OR v_session.released_at IS NOT NULL
      OR v_content_product.review_mode <> 'independent_blind'::public.review_mode
      OR (v_content_product.review_mode = 'independent_blind'::public.review_mode
          AND p.submitted_at IS NOT NULL
          AND v_caller_submitted)
    );

  RETURN jsonb_build_object(
    'ok', true,
    'session', jsonb_build_object(
      'id', v_session.id,
      'content_product_id', v_session.content_product_id,
      'organization_id', v_session.organization_id,
      'review_round', v_session.review_round,
      'status', v_session.status,
      'released_at', v_session.released_at,
      'released_by_member_id', v_session.released_by_member_id,
      'release_kind', v_session.release_kind,
      'created_at', v_session.created_at,
      'updated_at', v_session.updated_at,
      'closed_at', v_session.closed_at
    ),
    'content_product', jsonb_build_object(
      'id', v_content_product.id,
      'title', v_content_product.title,
      'review_mode', v_content_product.review_mode,
      'status', v_content_product.status,
      'target_instrument', v_content_product.target_instrument
    ),
    'caller_context', jsonb_build_object(
      'member_id', v_caller_member_id,
      'is_admin', v_caller_is_admin,
      'is_curator', v_caller_is_curator,
      'is_assignee', v_caller_is_assignee,
      'has_submitted', v_caller_submitted,
      'can_see_peer_pareceres', v_can_see_peer_pareceres
    ),
    'assignments', v_assignments,
    'pareceres', v_pareceres
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_blind_review_session(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_blind_review_session(uuid) TO authenticated;

-- ============================================================================
-- §7 STEP 11 -- Invariant X in check_schema_invariants()
-- X_blind_review_pareceres_session_product_match: every parecer must have an
-- active assignment in the same session (assignment-parecer integrity).
-- ADR-0099 §2.7 + PM D4. Mirrors V/V'/T/W ratchet pattern.
-- Preserves all 22 existing RETURN QUERY blocks verbatim (SEDIMENT-238.C).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_schema_invariants()
 RETURNS TABLE(invariant_name text, description text, severity text, violation_count integer, sample_ids uuid[])
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NULL
     AND current_setting('role', true) NOT IN ('service_role', 'postgres')
     AND current_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Unauthorized: check_schema_invariants requires authentication';
  END IF;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status = 'alumni' AND operational_role IS DISTINCT FROM 'alumni'
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'A1_alumni_role_consistency'::text,
         'member_status=alumni must coerce operational_role=alumni (B7 trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status = 'observer' AND operational_role NOT IN ('observer','guest','none')
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'A2_observer_role_consistency'::text,
         'member_status=observer must coerce operational_role IN (observer,guest,none) (B7 trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH computed AS (
    SELECT m.id AS member_id,
      CASE
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'manager')        THEN 'manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'co_gp')          THEN 'manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'deputy_manager') THEN 'deputy_manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role IN ('leader','comms_leader')) THEN 'tribe_leader'
        WHEN bool_or(
          (ae.kind = 'volunteer' AND ae.role IN ('researcher','facilitator','communicator','curator'))
          OR (ae.kind IN ('committee_member','workgroup_member','study_group_owner')
              AND ae.role IN ('leader','co_leader','owner','coordinator','researcher','contributor','member','participant'))
          OR (ae.kind IN ('committee_coordinator','workgroup_coordinator')
              AND ae.role IN ('leader','co_leader','owner','coordinator'))
        ) THEN 'researcher'
        WHEN bool_or(ae.kind = 'external_signer') THEN 'external_signer'
        WHEN bool_or(ae.kind = 'observer') THEN 'observer'
        WHEN bool_or(ae.kind = 'alumni') THEN 'alumni'
        WHEN bool_or(ae.kind = 'sponsor') THEN 'sponsor'
        WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
        WHEN bool_or(ae.kind = 'candidate') THEN 'candidate'
        ELSE 'guest'
      END AS expected_role
    FROM public.members m
    LEFT JOIN public.auth_engagements ae ON ae.person_id = m.person_id AND ae.is_authoritative = true
    WHERE m.member_status='active' AND m.name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND m.name NOT LIKE '%_synthetic%'
    GROUP BY m.id
  ),
  drift AS (
    SELECT c.member_id FROM computed c
    JOIN public.members m ON m.id = c.member_id
    WHERE m.operational_role IS DISTINCT FROM c.expected_role
  )
  SELECT 'A3_active_role_engagement_derivation'::text,
         'active member operational_role must equal priority-ladder derivation from active engagements (cache trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE ((member_status='active' AND is_active=false) OR (member_status IN ('observer','alumni','inactive') AND is_active=true))
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'B_is_active_status_mismatch'::text,
         'members.is_active must match member_status mapping (active=true, terminal=false)'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive') AND designations IS NOT NULL AND array_length(designations,1)>0
  )
  SELECT 'C_designations_in_terminal_status'::text,
         'members.designations must be empty when member_status is observer/alumni/inactive'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    JOIN public.persons p ON p.id = m.person_id
    WHERE m.auth_id IS NOT NULL AND p.auth_id IS NOT NULL AND m.auth_id IS DISTINCT FROM p.auth_id
  )
  SELECT 'D_auth_id_mismatch_person_member'::text,
         'persons.auth_id and members.auth_id must agree when both are set (ghost resolution sync)'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT ae.engagement_id AS e_id FROM public.auth_engagements ae
    JOIN public.members m ON m.person_id = ae.person_id
    WHERE ae.status='active' AND m.member_status IN ('observer','alumni','inactive')
      AND ae.kind NOT IN ('observer','alumni','external_signer','sponsor','chapter_board','partner_contact')
  )
  SELECT 'E_engagement_active_with_terminal_member'::text,
         'engagement.status=active is inconsistent with member.member_status in (observer/alumni/inactive) unless kind matches'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(e_id ORDER BY e_id) FROM (SELECT e_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT i.id AS initiative_id FROM public.initiatives i
    WHERE i.legacy_tribe_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.tribes t WHERE t.id = i.legacy_tribe_id)
  )
  SELECT 'F_initiative_legacy_tribe_orphan'::text,
         'initiatives.legacy_tribe_id must point to an existing tribe (bridge integrity)'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(initiative_id ORDER BY initiative_id) FROM (SELECT initiative_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    LEFT JOIN public.document_versions dv ON dv.id = gd.current_version_id
    WHERE gd.current_version_id IS NOT NULL
      AND (dv.id IS NULL OR dv.locked_at IS NULL)
      AND NOT EXISTS (
        SELECT 1 FROM public.approval_chains ac
        WHERE ac.document_id = gd.id
          AND ac.status IN ('review','approved','activated')
          AND ac.closed_at IS NULL
      )
  )
  SELECT 'J_current_version_published'::text,
         'governance_documents.current_version_id must point to a document_versions row with locked_at IS NOT NULL — unless an open approval_chain (review/approved/activated, closed_at NULL) is in flight that will lock the version on close (Phase IP-1, chain-aware).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    WHERE m.operational_role='external_signer'
      AND NOT EXISTS (
        SELECT 1 FROM public.auth_engagements ae
        WHERE ae.person_id=m.person_id AND ae.kind='external_signer' AND ae.status='active' AND ae.is_authoritative=true
      )
  )
  SELECT 'K_external_signer_integrity'::text,
         'members.operational_role=external_signer must have an active auth_engagements row with kind=external_signer (Phase IP-1).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    WHERE m.member_status IN ('alumni','observer','inactive') AND m.anonymized_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM public.member_offboarding_records r WHERE r.member_id=m.id)
  )
  SELECT 'L_offboarding_record_present'::text,
         'members in alumni/observer/inactive (not anonymized) must have a member_offboarding_records row (#91 G3 trigger).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH expected AS (
    SELECT a.id AS application_id, a.research_score AS cached,
      CASE
        WHEN e.obj_avg IS NOT NULL AND e.int_avg IS NOT NULL THEN round(e.obj_avg + e.int_avg, 2)
        WHEN e.obj_avg IS NOT NULL THEN round(e.obj_avg, 2)
        ELSE NULL
      END AS expected
    FROM public.selection_applications a
    CROSS JOIN LATERAL (
      SELECT AVG(weighted_subtotal) FILTER (WHERE evaluation_type='objective' AND submitted_at IS NOT NULL) AS obj_avg,
        AVG(weighted_subtotal) FILTER (WHERE evaluation_type='interview' AND submitted_at IS NOT NULL) AS int_avg
      FROM public.selection_evaluations WHERE application_id=a.id
    ) e
  ),
  drift AS (
    SELECT application_id FROM expected
    WHERE (cached IS NULL) IS DISTINCT FROM (expected IS NULL)
       OR (cached IS NOT NULL AND expected IS NOT NULL AND ABS(cached - expected) > 0.01)
  )
  SELECT 'M_application_score_consistency'::text,
         'selection_applications.research_score must equal compute_application_scores(application_id) derivation (sync trigger trg_recompute_application_scores).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(application_id ORDER BY application_id) FROM (SELECT application_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive')
      AND offboarded_at IS NULL AND anonymized_at IS NULL
      AND name <> 'VP Desenvolvimento Profissional (PMI-GO)'
  )
  SELECT 'N_terminal_status_offboarded_at_present'::text,
         'members in alumni/observer/inactive (not anonymized) must have offboarded_at NOT NULL (ARM-9 G6 defense-in-depth complement to L).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT ma.id AS artifact_id FROM public.meeting_artifacts ma
    WHERE ma.event_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.events e WHERE e.id = ma.event_id)
  )
  SELECT 'O_meeting_artifact_event_orphan'::text,
         'meeting_artifacts.event_id must point to an existing event when not NULL (FK defense).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(artifact_id ORDER BY artifact_id) FROM (SELECT artifact_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  SELECT 'P_tribe_initiative_bridge_complete'::text,
         'tribes.is_active=true must have at least one initiative.legacy_tribe_id pointing to it (V3-V4 bridge; cron leader digest depends).'::text,
         'medium'::text,
         (SELECT COUNT(*)::integer FROM public.tribes t
          WHERE t.is_active = true
            AND NOT EXISTS (SELECT 1 FROM public.initiatives i WHERE i.legacy_tribe_id = t.id)),
         NULL::uuid[];

  RETURN QUERY
  WITH drift AS (
    SELECT id AS engagement_id FROM public.engagements
    WHERE status = 'expired' AND end_date > CURRENT_DATE
  )
  SELECT 'Q_expired_engagement_end_date'::text,
         'engagements.status=expired requires end_date <= CURRENT_DATE (impossible to be expired in the future; VEP service_latest_end_date is source of truth).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(engagement_id ORDER BY engagement_id) FROM (SELECT engagement_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT a.id AS application_id
    FROM public.selection_applications a
    WHERE a.status = 'approved'
      AND a.email IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.members m WHERE lower(m.email) = lower(a.email)
      )
  )
  SELECT 'R_approved_application_has_member'::text,
         'selection_applications.status=approved must have a matching members row by lower(email). Bypass of approve_selection_application() canonical RPC creates this drift (Issue #180).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(application_id ORDER BY application_id) FROM (SELECT application_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT DISTINCT m.id AS member_id
    FROM public.selection_applications a
    JOIN public.members m ON lower(m.email) = lower(a.email)
    WHERE a.status = 'approved' AND m.person_id IS NULL
  )
  SELECT 'S_approved_member_has_person_id'::text,
         'members tied to an approved selection_applications row must have person_id NOT NULL (V4 graph anchor for engagements). Issue #180.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH primary_email_counts AS (
    SELECT m.id AS member_id,
           COUNT(me.id) FILTER (WHERE me.is_primary = true) AS primary_count
    FROM public.members m
    LEFT JOIN public.member_emails me ON me.member_id = m.id
    WHERE m.name NOT LIKE '%_synthetic%'
    GROUP BY m.id
  ),
  drift AS (
    SELECT member_id FROM primary_email_counts
    WHERE primary_count <> 1
  )
  SELECT 'T_member_has_exactly_one_primary_email'::text,
         'Every member must have exactly one primary email in member_emails (Issue #205).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    WHERE gd.status = 'pending_proposer_consent'
      AND EXISTS (
        SELECT 1 FROM public.approval_chains ac
        WHERE ac.document_id = gd.id
          AND ac.status NOT IN ('withdrawn','superseded')
      )
  )
  SELECT 'V_prime_pending_proposer_consent_no_open_chain'::text,
         'status=pending_proposer_consent must not have non-cancelled approval_chains rows (#315 P0-Q7 + Amendment A2 — pending_proposer_consent precedes any chain).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    WHERE gd.status IN ('approved','active')
      AND gd.current_ratified_chain_id IS NULL
  )
  SELECT 'V_status_chain_coherence'::text,
         'governance_documents with status approved/active must have current_ratified_chain_id NOT NULL (#315 P0-Q6 + #367 Wave 1b first leaf). NO carve-out: 7 legacy pre-chain docs backfilled with PM-designated synthetic chains via migration 20260805000038 (acknowledge signoffs, metadata.legacy_migration=true, role=migration_attestation).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT cp.id AS product_id
    FROM public.content_products cp
    WHERE
      CASE cp.source_kind
        WHEN 'governance_document_version' THEN
          NOT (cp.source_document_version_id IS NOT NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_publication_idea_id IS NULL
               AND cp.source_external_uri IS NULL)
        WHEN 'board_item' THEN
          NOT (cp.source_board_item_id IS NOT NULL
               AND cp.source_document_version_id IS NULL
               AND cp.source_publication_idea_id IS NULL
               AND cp.source_external_uri IS NULL)
        WHEN 'publication_idea' THEN
          NOT (cp.source_publication_idea_id IS NOT NULL
               AND cp.source_document_version_id IS NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_external_uri IS NULL)
        WHEN 'external' THEN
          NOT (cp.source_external_uri IS NOT NULL
               AND cp.source_document_version_id IS NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_publication_idea_id IS NULL)
        WHEN 'none' THEN
          NOT (cp.source_document_version_id IS NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_publication_idea_id IS NULL
               AND cp.source_external_uri IS NULL)
        ELSE TRUE
      END
  )
  SELECT 'W_content_product_source_integrity'::text,
         'content_products row must satisfy chk_content_products_source_integrity CHECK semantics (exactly one source FK populated per source_kind; ADR-0099 §2.2 + §6 step 9). Defense-in-depth complement to the CHECK constraint; mirrors V/V''/T pattern.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(product_id ORDER BY product_id) FROM (SELECT product_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT p.id AS parecer_id
    FROM public.blind_review_pareceres p
    WHERE NOT EXISTS (
      SELECT 1 FROM public.blind_review_assignments a
      WHERE a.session_id = p.session_id
        AND a.reviewer_member_id = p.reviewer_member_id
        AND a.status = 'active'
    )
  )
  SELECT 'X_blind_review_pareceres_session_product_match'::text,
         'blind_review_pareceres.reviewer_member_id must have an active blind_review_assignments row in the same session (assignment-parecer integrity; ADR-0099 §2.7 + §7 step 11). Defense-in-depth complement to FK constraints; catches drift if assignment is withdrawn while parecer remains. #382 PR-B.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(parecer_id ORDER BY parecer_id) FROM (SELECT parecer_id FROM drift LIMIT 10) s)
  FROM drift;

END;
$function$;

-- ============================================================================
-- Sanity DO block — assert greenfield + 23 invariants + 0 violations
-- ============================================================================

DO $sanity$
DECLARE
  v_tables int;
  v_session_rows int;
  v_assignment_rows int;
  v_parecer_rows int;
  v_invariant_count int;
  v_violation_count int;
  v_x_invariant_present boolean;
BEGIN
  SELECT count(*) INTO v_tables
  FROM information_schema.tables
  WHERE table_schema = 'public'
    AND table_name IN ('blind_review_sessions','blind_review_assignments','blind_review_pareceres');
  IF v_tables <> 3 THEN
    RAISE EXCEPTION 'p266 migration sanity: expected 3 blind_review_* tables, found %', v_tables;
  END IF;

  SELECT count(*) INTO v_session_rows FROM public.blind_review_sessions;
  SELECT count(*) INTO v_assignment_rows FROM public.blind_review_assignments;
  SELECT count(*) INTO v_parecer_rows FROM public.blind_review_pareceres;
  IF v_session_rows <> 0 OR v_assignment_rows <> 0 OR v_parecer_rows <> 0 THEN
    RAISE EXCEPTION 'p266 migration sanity: greenfield expectation violated (sessions=%, assignments=%, pareceres=%)',
      v_session_rows, v_assignment_rows, v_parecer_rows;
  END IF;

  SELECT count(*) INTO v_invariant_count FROM public.check_schema_invariants();
  SELECT count(*) INTO v_violation_count
  FROM public.check_schema_invariants() WHERE violation_count > 0;
  SELECT EXISTS (
    SELECT 1 FROM public.check_schema_invariants()
    WHERE invariant_name = 'X_blind_review_pareceres_session_product_match'
  ) INTO v_x_invariant_present;

  IF v_invariant_count <> 23 THEN
    RAISE EXCEPTION 'p266 migration sanity: expected 23 invariants post-X-add, found %', v_invariant_count;
  END IF;
  IF v_violation_count <> 0 THEN
    RAISE EXCEPTION 'p266 migration sanity: % invariant violations detected (should be 0 on greenfield)',
      v_violation_count;
  END IF;
  IF NOT v_x_invariant_present THEN
    RAISE EXCEPTION 'p266 migration sanity: invariant X_blind_review_pareceres_session_product_match missing';
  END IF;

  RAISE NOTICE 'p266 migration OK: 3 tables created, greenfield (0/0/0 rows), 23 invariants, 0 violations, X present';
END;
$sanity$;

-- ============================================================================
-- Reload PostgREST schema cache
-- ============================================================================
NOTIFY pgrst, 'reload schema';

COMMIT;
