-- p200 (OPP-196.E, ADR-0087 §1, 2026-05-19): correct curate_content scope
-- to 'organization' (not 'initiative'). Curator authority is cross-initiative
-- by design (per ADR-0086: curators review content from any tribe/initiative).
--
-- Empirical discovery during seed verification: with scope='initiative' AND
-- can_by_member called without p_resource_id, can() requires either
-- ae.initiative_id = p_resource_id (impossible when caller is null) OR
-- ae.legacy_tribe_id IS NOT NULL (V3 escape hatch). Roberto's engagement
-- happened to have legacy_tribe_id; Fabricio + Sarah's did not. Result was
-- inconsistent (Roberto=true, Fabricio/Sarah=false) — not the intended
-- semantic.
--
-- Switch to scope='organization' which matches platform-wide curator
-- authority: anyone with active committee_coordinator (coordinator/leader)
-- OR observer.curator engagement gets curate_content regardless of which
-- initiative the content belongs to.
--
-- Operational invariant (documented in ADR-0087 §1 footnote):
-- The `committee_coordinator` engagement kind is reserved for the Curation
-- Committee role-set in this taxonomy. Currently 2 initiatives have active
-- committee_coordinator engagements: Comitê de Curadoria (init 6a93cc94,
-- the canonical curation committee) and Publicações & Submissões (init
-- e885525e, where Fabricio holds dual hat as curator + publications lead).
-- Future committees that should NOT inherit curate_content (e.g., a
-- hypothetical Selection Committee) must use a different engagement kind
-- to avoid auto-grant.
--
-- ROLLBACK:
--   UPDATE engagement_kind_permissions SET scope='initiative'
--   WHERE action='curate_content';

UPDATE engagement_kind_permissions
SET scope = 'organization'
WHERE action = 'curate_content';

NOTIFY pgrst, 'reload schema';
