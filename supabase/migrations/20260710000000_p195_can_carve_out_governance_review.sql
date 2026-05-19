-- ============================================================
-- p195: can() carve-out — participate_in_governance_review bypasses
-- the is_authoritative (agreement_certificate_id) requirement
-- ============================================================
-- WHAT: amend public.can() so that for action='participate_in_governance_review'
-- specifically, ANY active engagement with a matching permission row grants
-- the capability — even if the engagement lacks an agreement_certificate_id.
-- Other actions (manage_event, manage_member, etc.) remain strict
-- (is_authoritative=true required, which enforces the agreement).
--
-- WHY (PM decision p195)
-- Three stakeholder groups need to comment on governance documents but
-- cannot — or should not — be required to sign the platform's Volunteer
-- Term first:
--   1. Initiative leaders pending agreement counter-sign
--      (e.g., Herlon Alves, study_group_owner × leader; agreement_certificate_id
--      NULL until Lorena/PMI-GO counter-signs the term)
--   2. PMI chapter directors (PMO PMI-GO: Lorena, Eder, etc.)
--      who participate in governance review as ex-officio observers but
--      do not sign the platform's volunteer term
--   3. External legal counsel (e.g., advogada Angelina, external_reviewer)
--      who reviews docs without joining the platform as a volunteer
--
-- The carve-out is SCOPED to participate_in_governance_review only — a
-- non-destructive comment-only capability. All other actions (sign gates,
-- manage members, write boards) remain bound by is_authoritative.
--
-- SIGN AUTHORITY is enumerated separately by _can_sign_gate() (per gate
-- kind: curator/legal_signer/chapter_board) — NOT changed here. Comment
-- vs sign is a clean separation.
--
-- POST-DEPLOY VALIDATION (verified inline):
--   can_by_member(herlon, 'participate_in_governance_review') = true (was false)
--   can_by_member(herlon, 'manage_event') = false (strict gate preserved)
--
-- ROLLBACK: re-apply prior can() body without the OR clause for the action carve-out.
-- ============================================================

CREATE OR REPLACE FUNCTION public.can(
  p_person_id uuid,
  p_action text,
  p_resource_type text DEFAULT NULL,
  p_resource_id uuid DEFAULT NULL
)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.auth_engagements ae
    JOIN public.engagement_kind_permissions ekp
      ON ekp.kind = ae.kind AND ekp.role = ae.role AND ekp.action = p_action
    WHERE ae.person_id = p_person_id
      AND (
        ae.is_authoritative = true
        -- p195 carve-out: participate_in_governance_review (comment-only) does
        -- not require agreement_certificate_id; active engagement is enough.
        -- Allows PMI chapter directors, external reviewers, and leaders with
        -- pending counter-sign to comment on governance documents.
        OR (p_action = 'participate_in_governance_review' AND ae.status = 'active')
      )
      AND (
        -- Organization/global scope: always grants
        ekp.scope IN ('organization', 'global')
        -- Initiative-scoped: must match the resource
        OR (
          ekp.scope = 'initiative'
          AND ae.initiative_id IS NOT NULL
          AND (
            -- Match by initiative UUID
            ae.initiative_id = p_resource_id
            -- Match by legacy tribe_id (p_resource_id is null but engagement has tribe)
            OR (p_resource_id IS NULL AND ae.legacy_tribe_id IS NOT NULL)
            -- Match by legacy tribe_id integer passed as text in resource_type
            OR (p_resource_type = 'tribe' AND ae.legacy_tribe_id = (p_resource_id::text)::integer)
          )
        )
      )
  );
$function$;
