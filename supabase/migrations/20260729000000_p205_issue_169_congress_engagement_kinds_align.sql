-- ============================================================================
-- p205 / Issue #169 — align engagement_kinds.initiative_kinds_allowed
-- for congress (unblock PM add-member UX)
-- ============================================================================
--
-- Context
-- -------
-- The platform has two parallel sources of truth for "which engagement kinds
-- are allowed on which initiative kinds":
--
--   1. `initiative_kinds.allowed_engagement_kinds`  (initiative-side view)
--   2. `engagement_kinds.initiative_kinds_allowed`  (kind-side view)
--
-- The `manage_initiative_engagement` RPC validates against the kind-side
-- view (#2). The admin UI dropdown shows kinds from the initiative-side
-- view (#1). When the two drift, the dropdown surfaces kinds that the RPC
-- subsequently rejects with "Engagement kind X not allowed for initiative
-- kind Y" — the exact error PM hit while adding members to the Vassouras
-- initiative (#169, p205).
--
-- For `congress`, initiative_kinds lists [volunteer, speaker, guest,
-- observer] as allowed. But the engagement_kinds inverse side only had
-- `speaker` and `guest` including 'congress' in their initiative_kinds_
-- allowed. So volunteer + observer were impossible to add via RPC.
--
-- Also: workgroup_coordinator + workgroup_member did NOT include congress
-- either, even though João's coordinator engagement was direct-INSERT-seeded
-- in 20260728000000. So no second workgroup_coordinator (e.g. co-coordinator
-- like another initiative leader) could be added via UI without bypass.
--
-- Fix
-- ---
-- Append 'congress' to initiative_kinds_allowed for these 4 kinds, aligning
-- the kind-side view with the initiative-side intent + supporting the
-- student-collaboration / PMI-RJ-observer / co-coordinator use cases per
-- PM decision at p205 close.
--
-- This affects ALL initiatives of kind=congress. Today only LATAM LIM
-- exists (does not use volunteer/observer/workgroup_*) so no operational
-- impact beyond Vassouras.
--
-- Per ADR-0009 "new initiative types = config not code": this is config
-- table data, not code change.
--
-- Idempotency
-- -----------
-- Re-running is a no-op via `array_append … ON CONFLICT` semantics —
-- guarded with NOT 'congress' = ANY(initiative_kinds_allowed) check.
--
-- Rollback
-- --------
-- UPDATE public.engagement_kinds
-- SET initiative_kinds_allowed = array_remove(initiative_kinds_allowed, 'congress')
-- WHERE slug IN ('volunteer','observer','workgroup_coordinator','workgroup_member');
--
-- Council Tier 1 note (WATCH-205.A backlog item #82): this migration
-- partially closes WATCH-205.A. Remaining drift: `initiative_kinds.
-- allowed_engagement_kinds` for congress STILL excludes workgroup_*.
-- A symmetric initiative-side update could be added but is unnecessary
-- for the UI (which reads from initiative-side via different path that
-- doesn't gate the UX). Document the asymmetric resolution in WATCH-205.A
-- closure note rather than do a second symmetric migration.
-- ============================================================================

UPDATE public.engagement_kinds
SET initiative_kinds_allowed = array_append(initiative_kinds_allowed, 'congress'),
    updated_at = now()
WHERE slug = 'volunteer'
  AND NOT ('congress' = ANY(initiative_kinds_allowed));

UPDATE public.engagement_kinds
SET initiative_kinds_allowed = array_append(initiative_kinds_allowed, 'congress'),
    updated_at = now()
WHERE slug = 'observer'
  AND NOT ('congress' = ANY(initiative_kinds_allowed));

UPDATE public.engagement_kinds
SET initiative_kinds_allowed = array_append(initiative_kinds_allowed, 'congress'),
    updated_at = now()
WHERE slug = 'workgroup_coordinator'
  AND NOT ('congress' = ANY(initiative_kinds_allowed));

UPDATE public.engagement_kinds
SET initiative_kinds_allowed = array_append(initiative_kinds_allowed, 'congress'),
    updated_at = now()
WHERE slug = 'workgroup_member'
  AND NOT ('congress' = ANY(initiative_kinds_allowed));

NOTIFY pgrst, 'reload schema';
