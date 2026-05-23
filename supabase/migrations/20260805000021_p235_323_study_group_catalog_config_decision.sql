-- p235 #323 (Gap C of #230 reframe) — study_group_* engagement_kinds catalog config decision
--
-- WHAT
-- Resolves the engagement_kinds catalog inconsistency surfaced by the p230
-- audit: two catalog rows (study_group_owner + study_group_participant)
-- declared requires_agreement=true with agreement_template=NULL. That state
-- means any consumer of `engagement_kinds.agreement_template` cannot mint a
-- termo for those kinds, and the p203 pending_agreement queue routes the
-- rows to 'decide_template_for_kind_then_issue' indefinitely.
--
-- Per PM decision (#323 close, 2026-05-23):
--   - study_group_owner: KEEP requires_agreement=true, assign placeholder
--     agreement_template='study_group_owner_agreement_v1'. Owner is a
--     leadership/execution role (ADR-0006 line 56 Herlon canonical example;
--     ADR-0008 lifecycle "VEP fast-track → Termo → 9m → 5yr retention").
--     The actual template body and legal workflow are a follow-up — slug is
--     forward-declared per the placeholder precedent established for
--     external_reviewer in ADR-0078 D5.
--   - study_group_participant: FLIP requires_agreement=false. Participant is
--     course/enrollment participation, not operational authority. ADR-0008
--     "Consent + termo de uso" is read as platform-wide TOS (consent), not
--     per-engagement. Participant must not enter the pending_agreement queue.
--
-- WHY (operational evidence at boot, 2026-05-23 UTC)
--   - engagement_kinds.agreement_template is a forward-declared TEXT slug
--     with NO consumer code (`sign_volunteer_agreement` and
--     `external_reviewer` mint paths are hardcoded; nothing auto-reads the
--     slug). Placeholder slug = catalog/intent marker, not an active mint
--     trigger.
--   - The only active study_group_participant engagement in the live DB is
--     Fernando Maquiaveli (member_id c8b930c3-62ec-4d38-881e-307cd57a44f7)
--     with role=leader on initiative "Grupo de Estudos CPMAI™". He also
--     holds the study_group_owner row on the same initiative — the redundant
--     double-engagement is a separate data-quality carry, NOT a #323
--     blocker (PM directive 2026-05-23).
--   - engagement_kind_permissions for (study_group_participant, role=leader)
--     is empty. Flipping requires_agreement=false on the kind means
--     Fernando's participant row becomes is_authoritative=true via the
--     auth_engagements derivation, but his role=leader matches NO permission
--     seed for the participant kind — zero new capabilities granted to him.
--   - The single permission seeded for (study_group_participant,
--     role=participant, write_board, scope=initiative) applies prospectively
--     to future enrollees, granting board write without a termo. This
--     matches PM's course-enrollee intent.
--   - PM directive (carried verbatim from p230 → p235): "Do NOT mint Herlon
--     term." Herlon's only active engagements are ambassador + observer,
--     neither requires_agreement. This migration neither references nor
--     affects Herlon.
--
-- INVARIANT (catalog forward-defense, #323 AC)
--   After apply: 0 rows in public.engagement_kinds where
--     requires_agreement = true
--     AND agreement_template IS NULL
--     AND slug NOT IN ('volunteer')
--   The 'volunteer' allowlist entry mirrors the existing exception — its
--   mint path is hardcoded in sign_volunteer_agreement(), not template-based.
--
-- ROLLBACK
--   BEGIN;
--     UPDATE public.engagement_kinds
--       SET agreement_template = NULL, updated_at = now()
--       WHERE slug = 'study_group_owner'
--         AND agreement_template = 'study_group_owner_agreement_v1';
--     UPDATE public.engagement_kinds
--       SET requires_agreement = true, updated_at = now()
--       WHERE slug = 'study_group_participant'
--         AND requires_agreement = false;
--     -- Informational rollback audit row (forward audit trail preserved per
--     -- LGPD Art. 37; original action rows from this migration stay).
--     INSERT INTO public.admin_audit_log (action, target_type, target_id, metadata)
--     VALUES ('engagement_kind.catalog_config_decision', 'engagement_kinds', NULL,
--             jsonb_build_object('rollback_of', '20260805000021',
--                                'rolled_back_at', now()));
--     NOTIFY pgrst, 'reload schema';
--   COMMIT;
--   -- Note: after rollback, Fernando's participant row reverts to
--   -- is_authoritative=false and re-enters the pending_agreement queue.
--   -- Owner row is unaffected by either direction (still
--   -- requires_agreement=true; placeholder slug just disappears).
--
-- CROSS-REF
--   - GH #323 (this issue, Gap C of #230 reframe)
--   - GH #230 (parent umbrella; close-trigger once #323 ships)
--   - GH #321 (closed p233, Gap A — sync trigger + 30-row phantom backfill)
--   - GH #322 (closed p234, Gap B — classification leftovers + forward guard)
--   - ADR-0006 line 56 (Herlon as study_group_owner canonical V4 example)
--   - ADR-0008 (per-kind engagement lifecycle; study_group_owner +
--     study_group_participant rows with explicit lifecycle declarations)
--   - ADR-0078 D5 (external_reviewer placeholder slug precedent — body
--     still pending legal-counsel)
--   - Migration 20260413500000 (original lifecycle setup that introduced
--     requires_agreement=true for both kinds)
--   - Migration 20260725000000 (p203 #177 pending_agreement queue —
--     'decide_template_for_kind_then_issue' route that this fix retires
--     for participant + keeps for owner pending follow-up template)
--   - Migration 20260803000001 (p217 #160 ambassador catalog fix — same
--     forward-defense + sanity DO pattern reused here)
--   - View public.auth_engagements (derives requires_agreement from
--     engagement_kinds; this migration changes derivation behaviour for
--     study_group_participant rows only)

BEGIN;

-- 1) study_group_owner: keep requires_agreement=true, assign placeholder
--    agreement_template slug. Idempotent guard: only update when
--    agreement_template is still NULL, so re-running is a no-op.
UPDATE public.engagement_kinds
SET
  agreement_template = 'study_group_owner_agreement_v1',
  updated_at = now()
WHERE slug = 'study_group_owner'
  AND agreement_template IS NULL;

-- 2) study_group_participant: flip requires_agreement=false. Idempotent
--    guard: only update when still TRUE. legal_basis stays 'contract'
--    (curso execution — Lei 9.608 framing). The downstream effect on
--    auth_engagements.is_authoritative is acceptable per the permissions
--    audit above (no role=leader privilege escalation; role=participant
--    gains write_board prospectively as designed).
UPDATE public.engagement_kinds
SET
  requires_agreement = false,
  updated_at = now()
WHERE slug = 'study_group_participant'
  AND requires_agreement = true;

-- 3) Audit log entries — one per catalog change. action matches the
--    admin_audit_log_action_pattern CHECK
--    (regex ^[a-z][a-z0-9_]*(\.[a-z0-9_]+)*$, max length 80).
--    target_type='engagement_kinds' is the established canonical value
--    (count=7 historical entries). target_id NULL because engagement_kinds
--    is slug-keyed, not uuid-keyed.
INSERT INTO public.admin_audit_log (action, target_type, target_id, actor_id, metadata)
SELECT
  'engagement_kind.catalog_config_decision' AS action,
  'engagement_kinds' AS target_type,
  NULL::uuid AS target_id,
  NULL::uuid AS actor_id,
  jsonb_build_object(
    'migration', '20260805000021',
    'issue', 'gh-323',
    'kind', x.slug,
    'change', x.change,
    'pm_decision_session', 'p235',
    'pm_decision_at', '2026-05-23',
    'rationale', x.rationale
  ) AS metadata
FROM (VALUES
  ('study_group_owner',
   'assign_placeholder_template_slug',
   'Keep requires_agreement=true; agreement_template=study_group_owner_agreement_v1 (template body deferred to follow-up legal-counsel issue). Preserves ADR-0006/0008 termo intent; mirrors ADR-0078 D5 external_reviewer slug placeholder precedent.'),
  ('study_group_participant',
   'flip_requires_agreement_false',
   'Course enrollee model. ADR-0008 "termo de uso" treated as platform-wide TOS (consent), not per-engagement. legal_basis stays contract (curso execution).')
) AS x(slug, change, rationale);

-- 4) Sanity DO block: RAISE EXCEPTION if catalog still violates the #323
--    invariant after the apply. Hard-fails at write time so the migration
--    is rejected outright rather than leaving the catalog half-fixed.
DO $$
DECLARE
  v_violations integer;
  v_offenders text;
BEGIN
  SELECT count(*), string_agg(slug, ', ' ORDER BY slug)
  INTO v_violations, v_offenders
  FROM public.engagement_kinds
  WHERE requires_agreement = true
    AND agreement_template IS NULL
    AND slug NOT IN ('volunteer');

  IF v_violations > 0 THEN
    RAISE EXCEPTION
      'p235 #323 catalog invariant violation: % engagement_kinds row(s) have requires_agreement=true with agreement_template NULL outside the non-template allowlist. Offenders: %',
      v_violations, v_offenders;
  END IF;
END;
$$;

-- 5) Reload PostgREST schema cache. engagement_kinds is exposed via
--    PostgREST so cache eviction is defensive even though no signature
--    changed in this migration.
NOTIFY pgrst, 'reload schema';

COMMIT;
