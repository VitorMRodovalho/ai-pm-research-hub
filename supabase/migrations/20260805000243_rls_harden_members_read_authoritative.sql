-- Harden the members cross-read so non-authoritative members (pre-onboarding guests)
-- can no longer read the full member directory PII (email/phone/pmi_id/address/birth_date).
-- rls_is_member() is row-existence only; members_read_by_members (USING is_active AND rls_is_member())
-- therefore let ANY authenticated member-row holder (incl. guest callers) read all active members.
-- Surgical fix: gate this one policy on authoritative membership. Own-row reads remain via
-- members_select_own (auth_id=auth.uid()); admin/stakeholder/tribe-leader read paths are separate
-- permissive policies and are untouched. #867 follow-up / LGPD.
--
-- Safety (live grounding at apply time): of 63 active members with auth_id, the predicate keeps the
-- 40 non-guest (researcher/tribe_leader/chapter_liaison/manager/observer/sponsor) and blocks the 23
-- guest callers. operational_role is the V4 cache maintained by sync_operational_role_cache from
-- authoritative engagements; 'guest' == no authoritative engagement.

CREATE OR REPLACE FUNCTION public.rls_is_authoritative_member()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.auth_id = auth.uid()
      AND m.is_active = true
      AND m.operational_role IS NOT NULL
      AND m.operational_role <> 'guest'
  );
$function$;

COMMENT ON FUNCTION public.rls_is_authoritative_member() IS
  'RLS helper: caller is an ACTIVE member with an authoritative engagement (operational_role <> guest). Stricter than rls_is_member() (row-existence). Gate for member-directory PII reads so pre-onboarding / non-authoritative members cannot read other members'' PII. #867 follow-up / LGPD.';

DROP POLICY IF EXISTS members_read_by_members ON public.members;
CREATE POLICY members_read_by_members ON public.members
  FOR SELECT TO authenticated
  USING (is_active = true AND public.rls_is_authoritative_member());

NOTIFY pgrst, 'reload schema';
