-- #1217 Direction A: the tribe/initiative members list must derive from the engagement PRIMITIVE
-- (v_initiative_roster), NOT the single-slot members.initiative_id cache.
--
-- Root cause (audited 2026-07-08): /tribe/[id] filtered members by public_members.initiative_id — a
-- SINGLE-slot cache maintained by _sync_member_initiative_from_engagement, a FILL-ONLY trigger (writes
-- only when the cache is NULL, never overwrites nor clears). When a C4 leader joined the "Kickoff Ciclo 4"
-- workgroup while their cache was NULL, the slot locked onto the workgroup initiative; when their tribe
-- engagement was later pointed at the tribe initiative the trigger (by design) did not correct it, so the
-- leader vanished from their OWN tribe page (5 leaders affected). The single-slot cache is semantically
-- incapable of representing a multi-engagement member (leader + workgroup is the NORMAL C4 case).
--
-- Fix: a read-only SECURITY DEFINER RPC that returns the tribe page's member-card shape from
-- v_initiative_roster (#419 canonical roster: DISTINCT person with an active, non-observer-ROLE engagement
-- on the initiative). A leader with an active leader engagement on the tribe initiative appears here
-- regardless of which initiative their cache slot holds — robust to any future cache drift.
--
-- Confidential-initiative gate (ADR-0105): reuses rls_can_see_initiative — anon/non-engaged get [] for a
-- confidential initiative, identical to public_members' RLS carve-out. Authenticated-only (the tribe page
-- denies anon before the members load via canExploreTribes), matching get_initiative_members. Read-only,
-- so outside the #965 side-effect SECDEF sweep.
--
-- Display columns are exactly the public_members subset the page already consumed (no new PII: name,
-- photo_url, chapter, operational_role, designations, share_whatsapp — never email/phone). DISTINCT ON
-- person keeps the highest-authority role so a member with two engagements collapses to one card.

CREATE OR REPLACE FUNCTION public.get_initiative_roster_members(p_initiative_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT public.rls_can_see_initiative(p_initiative_id) THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT coalesce(jsonb_agg(row_to_json(x) ORDER BY x.name), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT DISTINCT ON (r.person_id)
      pm.id,
      pm.name,
      pm.photo_url,
      pm.chapter,
      pm.operational_role,
      pm.designations,
      pm.tribe_id,
      pm.initiative_id,
      pm.share_whatsapp,
      pm.current_cycle_active,
      pm.is_active
    FROM public.v_initiative_roster r
    JOIN public.public_members pm ON pm.id = r.member_id
    WHERE r.initiative_id = p_initiative_id
    ORDER BY r.person_id,
      CASE r.role
        WHEN 'leader' THEN 0
        WHEN 'comms_leader' THEN 1
        WHEN 'coordinator' THEN 2
        WHEN 'participant' THEN 3
        ELSE 4
      END
  ) x;

  RETURN coalesce(v_result, '[]'::jsonb);
END;
$function$;

COMMENT ON FUNCTION public.get_initiative_roster_members(uuid) IS
  '#1217 canonical tribe/initiative member-card list, derived from v_initiative_roster (engagement primitive, DISTINCT person, active non-observer role) — NOT the members.initiative_id single-slot cache. Confidential-gated (rls_can_see_initiative). Fixes the leader vanishing from their own tribe page when the fill-only cache slot is held by a workgroup engagement.';

REVOKE ALL ON FUNCTION public.get_initiative_roster_members(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_initiative_roster_members(uuid) TO authenticated, service_role;
