-- Wave 1 (Ivan / LATAM LIM) — sponsor must outrank researcher in the operational_role derivation.
--
-- Problem: sync_operational_role_cache derives operational_role from auth_engagements with a CASE
-- precedence where the `researcher` branch (which also catches committee_member / workgroup roles)
-- is checked BEFORE `sponsor`. Ivan Lourenço (host-chapter PMI-GO sponsor, LATAM LIM presenter) is
-- also LEADER of the "GP × Presidência — Governança do Núcleo" committee → he matched `researcher`
-- and derived operational_role='researcher' → badge "Pesquisador" + the researcher tier (no admin.*).
--
-- Blast radius (grounded 2026-06-28): of the 5 members with an authoritative sponsor engagement,
-- 4 (PMI-MG/CE/RS/DF chapter sponsors) already derive 'sponsor' (no committee engagement). ONLY Ivan
-- derived 'researcher'. Moving the `sponsor` branch above `researcher` flips ONLY Ivan; zero collateral.
-- Kept BELOW manager/deputy_manager/tribe_leader so an operational leader who also sponsors stays a leader.
--
-- (Wave 2 — separate — will handle chapter_board→chapter_liaison precedence for all sede/chapter
-- directors + the access-restriction decision per directorate/chapter layer.)

CREATE OR REPLACE FUNCTION public.sync_operational_role_cache()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_new_role text;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE person_id = COALESCE(NEW.person_id, OLD.person_id);
  IF v_member_id IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;

  SELECT CASE
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'manager')        THEN 'manager'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'co_gp')          THEN 'manager'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'deputy_manager') THEN 'deputy_manager'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role IN ('leader','comms_leader')) THEN 'tribe_leader'
      -- Wave 1 fix: sponsor outranks researcher (committee/workgroup) so a sponsor who also sits on a
      -- committee (e.g. the governance committee) shows as a sponsor, not a researcher.
      WHEN bool_or(ae.kind = 'sponsor') THEN 'sponsor'
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
      WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
      WHEN bool_or(ae.kind = 'candidate') THEN 'candidate'
      ELSE 'guest'
    END INTO v_new_role
  FROM public.auth_engagements ae
  WHERE ae.person_id = COALESCE(NEW.person_id, OLD.person_id) AND ae.is_authoritative = true;

  UPDATE public.members SET operational_role = COALESCE(v_new_role, 'guest'), updated_at = now()
    WHERE id = v_member_id AND operational_role IS DISTINCT FROM COALESCE(v_new_role, 'guest');

  RETURN COALESCE(NEW, OLD);
END;
$function$;
