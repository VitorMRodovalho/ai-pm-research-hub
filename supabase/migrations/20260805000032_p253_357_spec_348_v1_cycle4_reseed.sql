-- ============================================================
-- p253 #357 — SPEC #348 Child #4 Cycle4 Reseed (researcher evaluators + booking URLs)
-- ------------------------------------------------------------
-- WHAT: One-off data seed for cycle4-2026 to activate per-evaluator booking
--   URL routing (researcher track). Two operations + sanity gate, all in
--   one DO block, idempotent via ON CONFLICT:
--   1. UPDATE public.members SET interview_booking_url for Vitor + Fabricio
--      (researcher-track individual calendar pool URLs). The member.global
--      URL is the canonical source for SPEC #348 §3 ladder
--      "committee override → member global → cycle fallback".
--   2. INSERT INTO public.selection_committee for cycle4-2026 with both
--      members as role='evaluator' + can_interview=true. UNIQUE
--      (cycle_id, member_id) plus ON CONFLICT DO NOTHING makes the seed
--      idempotent (re-running this migration is a no-op once both rows
--      exist).
--   3. admin_audit_log row (actor_id=NULL — service-role migration context;
--      mirrors p240 backfill pattern; canonical action namespace
--      'selection.committee_seeded').
--   4. Sanity DO RAISES EXCEPTION if cycle4-2026 ends with fewer than 2
--      role='evaluator' + can_interview=true rows (catches partial INSERT
--      / typo regression / explicit DELETE that would re-orphan the cycle).
--
-- WHY: After #356 shipped the admin UI to populate members.interview_booking_url,
--   the next mile is wiring cycle4-2026 to actually use per-evaluator routing.
--   SPEC #348 Step 2 (p243 origin) split URL ownership across three layers
--   so the dispatch decision is driven by application.role_applied. With this
--   seed:
--     - researcher-track apps in cycle4 → #355 RPC ladder picks the
--       least-recently-dispatched between Vitor and Fabricio per LRD
--       (selection_dispatch_url_log) → individual booking URL goes in the
--       Resend cutoff-approved email.
--     - leader-track apps in cycle4 → #355 RPC continues to use the cycle
--       group/dual link (https://calendar.app.google/XPiGWLh9JaLVFKJc6,
--       seeded in p243); selection_committee.interview_booking_url stays
--       NULL so the cycle-level fallback fires.
--   PM rules respected:
--     - selection_committee.role='evaluator' (NOT 'researcher' — that is
--       application-side; CHECK constraint enforces it; forward-defense test
--       locks it).
--     - cycle.interview_booking_url NOT modified (leader flow preservation).
--     - can_interview=true (explicit; mirrors column default but documents
--       intent + makes diff readable).
--
-- SPEC DRIFT RESOLVED: none. #357 ships the planned reseed; SPEC #348 §8
--   Child #4 unblocked by #356 (admin UI) merge of #360.
--
-- ROLLBACK:
--   DELETE FROM public.selection_committee
--     WHERE cycle_id = '08c1e301-9f7b-4d01-a13c-43ac7775c0f7'
--       AND member_id IN ('880f736c-3e76-4df4-9375-33575c190305',
--                         '92d26057-5550-4f15-a3bf-b00eed5f32f9');
--   UPDATE public.members SET interview_booking_url = NULL
--     WHERE id IN ('880f736c-3e76-4df4-9375-33575c190305',
--                  '92d26057-5550-4f15-a3bf-b00eed5f32f9');
--   -- admin_audit_log row left in place (audit trail is append-only by
--   -- convention; rollback would also INSERT a 'selection.committee_unseeded'
--   -- row out of scope here).
--
-- INVARIANTS: 19/19=0 unchanged. No tables / FKs / columns / triggers
--   touched. Only data rows added in additive way.
--
-- CROSS-REF:
--   Parent:        #348 (roadmap)
--   This:          #357 (Child #4 Cycle4 reseed)
--   Predecessors:  #354 (Foundation DDL, p250) · #355 (RPC routing, p251) ·
--                  #356 (Admin UI, p252)
--   SPEC doc:      docs/specs/SPEC_348_BOOKING_URL_PER_EVALUATOR.md §8 Child #4
--   p243 origin:   docs/ops/WATCH_240_C_CYCLE4_CUTOFF_DISPATCH_RUNBOOK.md
-- ============================================================

DO $$
DECLARE
  -- Cycle + member identities resolved from live state pre-migration (p252):
  --   selection_cycles WHERE cycle_code='cycle4-2026' → 08c1e301-…
  --   members          WHERE email='vitor.rodovalho@outlook.com' → 880f736c-…
  --   members          WHERE email='fabriciorcc@gmail.com'        → 92d26057-…
  v_cycle_id     uuid := '08c1e301-9f7b-4d01-a13c-43ac7775c0f7';
  v_vitor_id     uuid := '880f736c-3e76-4df4-9375-33575c190305';
  v_fabricio_id  uuid := '92d26057-5550-4f15-a3bf-b00eed5f32f9';
  -- Personal booking pool URLs (PM-provided 2026-05-24):
  v_vitor_url    text := 'https://calendar.app.google/q9urWE15HYZRNymd7';
  v_fabricio_url text := 'https://calendar.app.google/1jDNjPpoGCkV2V9A6';
  v_inserted_count int;
  v_evaluators_post int;
BEGIN
  -- Sanity-check the cycle exists and is the one we expect (catches drift if
  -- cycle4 gets renamed / archived between authoring + apply).
  IF NOT EXISTS (
    SELECT 1 FROM public.selection_cycles
    WHERE id = v_cycle_id AND cycle_code = 'cycle4-2026'
  ) THEN
    RAISE EXCEPTION 'Pre-seed sanity: cycle id % is not cycle4-2026 in live state', v_cycle_id;
  END IF;

  -- (1) Populate per-member individual researcher-pool URLs. UPDATE is
  --     idempotent — re-running the migration overwrites with the same value.
  --     Per SPEC #348 §3, the column is the canonical "member global" tier
  --     in the routing ladder used by notify_selection_cutoff_approved (#355).
  UPDATE public.members
     SET interview_booking_url = v_vitor_url
   WHERE id = v_vitor_id;

  UPDATE public.members
     SET interview_booking_url = v_fabricio_url
   WHERE id = v_fabricio_id;

  -- (2) Seed selection_committee for cycle4-2026. PM rule: role='evaluator'.
  --     CHECK constraint enforces role ∈ ('evaluator','lead','observer') so
  --     a typo to 'researcher' would 23514. selection_committee.
  --     interview_booking_url left NULL so the routing ladder skips the
  --     committee-override tier and falls through to the member-global URL
  --     (the column populated above).
  INSERT INTO public.selection_committee (cycle_id, member_id, role, can_interview)
  VALUES
    (v_cycle_id, v_vitor_id,    'evaluator', true),
    (v_cycle_id, v_fabricio_id, 'evaluator', true)
  ON CONFLICT (cycle_id, member_id) DO NOTHING;
  GET DIAGNOSTICS v_inserted_count = ROW_COUNT;

  -- (3) Audit row in admin_audit_log. actor_id NULL because the migration
  --     runs in a service-role context (auth.uid() unavailable); mirrors
  --     p240 backfill convention. Conditional on v_inserted_count > 0 so a
  --     re-run after the seed is already in place stays a true no-op (no
  --     phantom audit churn).
  IF v_inserted_count > 0 THEN
    INSERT INTO public.admin_audit_log (action, actor_id, target_type, target_id, metadata)
    VALUES (
      'selection.committee_seeded',
      NULL,
      'selection_cycle',
      v_cycle_id,
      jsonb_build_object(
        'reason',                'p253_357_cycle4_reseed_researcher_evaluators',
        'migration',             '20260805000032',
        'cycle_code',            'cycle4-2026',
        'inserted_committee_rows', v_inserted_count,
        'committee_role',        'evaluator',
        'can_interview',         true,
        'members', jsonb_build_array(
          jsonb_build_object('member_id', v_vitor_id,    'role_track', 'researcher', 'url_present', v_vitor_url IS NOT NULL),
          jsonb_build_object('member_id', v_fabricio_id, 'role_track', 'researcher', 'url_present', v_fabricio_url IS NOT NULL)
        )
      )
    );
  END IF;

  -- (4) Sanity: cycle4 must have >= 2 evaluator+can_interview rows post-seed.
  --     Catches: partial INSERT / typo regression / explicit DELETE between
  --     INSERT and sanity check / wrong v_cycle_id pinned at the top.
  SELECT count(*) INTO v_evaluators_post
    FROM public.selection_committee
   WHERE cycle_id = v_cycle_id
     AND role = 'evaluator'
     AND can_interview = true;
  IF v_evaluators_post < 2 THEN
    RAISE EXCEPTION 'Post-seed sanity: cycle4-2026 expected >= 2 evaluator+can_interview rows, got %', v_evaluators_post;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
