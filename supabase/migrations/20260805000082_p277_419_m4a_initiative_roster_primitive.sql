-- #419 metric 4 (tribe_roster / member_count) — PR4-A: the canonical roster primitive.
-- ADR-0100 §2.2: member_count = DISTINCT persons with an ACTIVE, NON-OBSERVER ROLE engagement on the
-- resolved initiative. Filters on ROLE (role<>'observer'), NEVER on kind — kind='volunteer' is the bug
-- that drops the curator (Roberto Macêdo, role=curator/kind=observer). An active engagement IS the
-- current-cycle cohort (engagements has no cycle_id); members.current_cycle_active is the drifting gate
-- that over-counts (the digest's offboarded Maria).
--
-- ADDITIVE ONLY — no surface RPC is touched in PR4-A. The tribe/initiative-keyed RPCs converge onto this
-- in the follow-up PRs (4-B initiative RPCs, 4-C tribe RPCs incl. exec_tribe_dashboard 5->6 +
-- get_weekly_tribe_digest 7->6, 4-D frontend, 4-F conditional get_member_tribe axis).
--
-- Tribe -> initiative bridge uses the EXISTING resolve_initiative_id(integer)->uuid (ADR-0005); the inverse
-- resolve_tribe_id(uuid)->integer also already exists. Reused, NOT duplicated.
--
-- Live canonical per-tribe (verified): t1=4 t2=5 t4=5 t5=3 t6=6 t7=4 t8=6 (t3 has no active research_tribe
-- roster). Tribe 8 = 6 INCLUDING the curator Roberto (the row the volunteer-kind predicate drops to 5).

CREATE OR REPLACE VIEW public.v_initiative_roster AS
  SELECT DISTINCT
    e.initiative_id,
    i.legacy_tribe_id,
    e.person_id,
    m.id   AS member_id,
    m.name,
    e.role,
    e.kind,
    COALESCE(m.gamification_opt_out, false) AS gamification_opt_out
  FROM public.engagements e
  JOIN public.initiatives i ON i.id = e.initiative_id
  LEFT JOIN public.members m ON m.person_id = e.person_id   -- live join path (members.person_id)
  WHERE e.status = 'active'
    AND e.role <> 'observer';   -- ROLE axis, never kind

COMMENT ON VIEW public.v_initiative_roster IS
  '#419 metric 4 canonical roster: DISTINCT person with an active, non-observer ROLE engagement on the initiative. member_count = COUNT over this. Filters on role (NOT kind) — kind=volunteer wrongly drops curators. An active engagement is the current-cycle cohort (engagements has no cycle_id). Bridge tribe<->initiative via resolve_initiative_id / resolve_tribe_id (ADR-0005).';

CREATE OR REPLACE FUNCTION public.get_initiative_roster_count(p_initiative_id uuid)
  RETURNS integer
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT COUNT(DISTINCT person_id)::int
  FROM public.v_initiative_roster
  WHERE initiative_id = p_initiative_id;
$function$;

COMMENT ON FUNCTION public.get_initiative_roster_count(uuid) IS
  '#419 metric 4 canonical member_count for an initiative (DISTINCT person, active non-observer-role engagement). Tribe-keyed callers: get_initiative_roster_count(resolve_initiative_id(tribe_id)).';

REVOKE ALL ON FUNCTION public.get_initiative_roster_count(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_initiative_roster_count(uuid) TO authenticated, service_role;
-- The view inherits invoker privileges; expose read to the authenticated roles the consuming SECDEF RPCs use.
REVOKE ALL ON public.v_initiative_roster FROM PUBLIC;
GRANT SELECT ON public.v_initiative_roster TO authenticated, service_role;
