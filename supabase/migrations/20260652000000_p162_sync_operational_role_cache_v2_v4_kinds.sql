-- p162 Track E — Fix sync_operational_role_cache trigger
-- Refs: ADR-0080 (V4 engagement canonical), ADR-0007 (can() authority)
-- Root cause: trigger CASE chain mapped only kind='volunteer' roles + 'observer/alumni/sponsor/chapter_board/candidate' kinds.
-- New V4 kinds (study_group_owner, committee_member, committee_coordinator, workgroup_member, workgroup_coordinator)
-- fell to ELSE 'guest' — silent demotion if member's ONLY authoritative engagement was one of these.
--
-- Affected case found in audit (p162): Herlon (study_group_owner leader, no parallel volunteer)
-- Other 12 V4-kind members have parallel volunteer engagements that win, so trigger gap was silent.
--
-- Note: is_authoritative is a VIEW-computed column (auth_engagements view), derived from:
--   engagement.status='active' AND start_date<=today AND (end_date IS NULL OR end_date>=today)
--   AND (agreement_certificate_id IS NOT NULL OR NOT engagement_kinds.requires_agreement).
-- So a leader engagement only becomes authoritative when the member signs the relevant agreement.
-- This trigger fix ensures correct mapping ONCE the agreement is signed — does NOT bypass the
-- agreement requirement.
--
-- Fix: extend CASE chain to map V4 leader/coordinator/owner roles to 'tribe_leader',
--      and V4 researcher/contributor/member roles to 'researcher'.

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
      WHEN bool_or(
        (ae.kind = 'volunteer' AND ae.role IN ('leader','comms_leader'))
        OR (ae.kind IN ('study_group_owner','committee_coordinator','workgroup_coordinator')
            AND ae.role IN ('leader','co_leader','owner','coordinator'))
        OR (ae.kind IN ('committee_member','workgroup_member')
            AND ae.role IN ('leader','coordinator'))
      ) THEN 'tribe_leader'
      WHEN bool_or(
        (ae.kind = 'volunteer' AND ae.role IN ('researcher','facilitator','communicator','curator'))
        OR (ae.kind IN ('committee_member','workgroup_member','study_group_owner')
            AND ae.role IN ('researcher','contributor','member','participant'))
      ) THEN 'researcher'
      WHEN bool_or(ae.kind = 'external_signer') THEN 'external_signer'
      WHEN bool_or(ae.kind = 'observer') THEN 'observer'
      WHEN bool_or(ae.kind = 'alumni') THEN 'alumni'
      WHEN bool_or(ae.kind = 'sponsor') THEN 'sponsor'
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

COMMENT ON FUNCTION public.sync_operational_role_cache() IS
'V4 engagement → operational_role cache sync. Extended p162 (Track E) to cover study_group_owner / committee_member / committee_coordinator / workgroup_member / workgroup_coordinator kinds — previously falling to ELSE guest. Ver ADR-0080 + memory/feedback_v4_authority_audit_methodology.md.';

NOTIFY pgrst, 'reload schema';

-- Rollback: revert to original CASE chain (manager/deputy_manager/tribe_leader/researcher
-- only mapped for volunteer kind, observer/alumni/sponsor/chapter_board/candidate by kind only).
