-- p277 / #419 (ADR-0100) metric 4 — revise the canonical member definition to PARTICIPANTS ONLY.
--
-- PM decision (2026-06-01, supersedes the original M4.2 ratification): curators/observers do NOT count
-- as members of a tribe/initiative — member_count = participants. A "participant" is anyone whose
-- engagement KIND is participatory; kind='observer' is the explicit non-participation marker. So the
-- canonical roster excludes observers on BOTH axes: role<>'observer' AND kind<>'observer'.
--
-- This drops the 4 people who sit on the role-vs-kind boundary (all kind='observer'): Roberto Macêdo
-- (tribe-8, role=curator) + three observer-kind reviewers — Welma (Grupo CPMAI), Fabricio + Sarah
-- (LATAM LIM). It KEEPS the active external_reviewer (Mario, kind=external_reviewer) and all speakers.
--
-- This unifies member_count and attendance-eligibility onto the SAME (kind) axis: get_member_tribe
-- already filters kind='volunteer', so the kind-vs-role divergence that PR-F (D-M4-AXIS) would have
-- introduced disappears entirely. PR-F is therefore NOT applied — get_member_tribe stays as-is, and
-- metric-3 (which reads operational_role + get_member_tribe, NOT this view) is unaffected.
--
-- Because M4-A/B/C routed every member-count surface through this single primitive, revising the ONE
-- view propagates everywhere automatically (no PR is reverted — the routing stays; the definition is
-- updated). Verified-live antes→depois: tribe-8 6→5 (get_tribe_stats / exec_tribe_dashboard / digest /
-- exec_cross all follow); native LATAM 5→3, Grupo CPMAI 4→3; Mesa Redonda 4→4 (its observers were
-- already role=observer); all other tribes/initiatives unchanged. exec_tribe_dashboard tribe-8
-- tribe_total_xp 2815→2535 (Roberto's XP leaves the cohort).
--
-- Re-asserts the mig-085 anon lockdown (CREATE OR REPLACE VIEW can reset reloptions/grants — the
-- pg_default_acl trap): security_invoker=true + REVOKE anon/PUBLIC + GRANT authenticated/service_role.
-- Rollback: restore the WHERE to `e.status='active' AND e.role <> 'observer'` (the M4-A/mig-082 form).
-- Cross-ref: ADR-0100 §M4 (revised); issue #419; supersedes the role<>'observer' rule of mig 082.

CREATE OR REPLACE VIEW public.v_initiative_roster AS
  SELECT DISTINCT e.initiative_id,
    i.legacy_tribe_id,
    e.person_id,
    m.id AS member_id,
    m.name,
    e.role,
    e.kind,
    COALESCE(m.gamification_opt_out, false) AS gamification_opt_out
   FROM engagements e
     JOIN initiatives i ON i.id = e.initiative_id
     LEFT JOIN members m ON m.person_id = e.person_id
  WHERE e.status = 'active'::text
    AND e.role <> 'observer'::text
    AND e.kind <> 'observer'::text;   -- participants only (PM 2026-06-01): observers don't count as members

-- re-assert the mig-085 anon PII lockdown (REVOKE FROM PUBLIC strips the default grant anon inherits)
ALTER VIEW public.v_initiative_roster SET (security_invoker = true);
REVOKE ALL ON public.v_initiative_roster FROM anon, PUBLIC;
GRANT SELECT ON public.v_initiative_roster TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
