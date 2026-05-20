-- p203 issue #177 — pending agreement queue (visibility-first)
--
-- Per P202_VOLUNTEER_LIFECYCLE_REMEDIATION_SPEC §2 Phase 2.
--
-- Goal: surface the 16 active engagements that require an agreement but have
-- no agreement_certificate_id yet. Visibility ONLY — do NOT auto-issue.
-- Auto-issuance for special kinds (ambassador, study_group_*) requires PM
-- decision on template appropriateness (volunteer_term_template is for
-- volunteer kind only; ambassador and study_group_* have no current template).
--
-- Authority: gated to manage_member via can_by_member(). Returns PII (name,
-- email, chapter) since the use case is admin/GP follow-up; that matches
-- the existing admin queue pattern.
--
-- next_action heuristic helps PM/admin route:
--   - volunteer kind        → notify_member_to_sign_volunteer_term (existing flow works)
--   - ambassador/study_*    → decide_template_for_kind_then_issue (needs PM input)
--   - inactive/missing mem  → investigate / reactivate
--
-- Out of scope:
--   - Auto-issuance (waits on PM template decision for ambassador/study_*)
--   - Notification dispatch (next-action label only; no side effects)
--   - MCP tool exposure (defer per spec §5 until lifecycle RPCs stabilize)
--
-- Rollback: DROP FUNCTION public.get_pending_agreement_engagements();

DROP FUNCTION IF EXISTS public.get_pending_agreement_engagements();

CREATE OR REPLACE FUNCTION public.get_pending_agreement_engagements()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_can_manage boolean;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  v_can_manage := public.can_by_member(v_caller_id, 'manage_member');
  IF NOT v_can_manage THEN
    RETURN jsonb_build_object('error', 'not_authorized');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'generated_at', now(),
    'total', (
      SELECT count(*)
      FROM public.auth_engagements ae
      WHERE ae.status = 'active'
        AND ae.requires_agreement IS TRUE
        AND ae.agreement_certificate_id IS NULL
    ),
    'by_kind_role', (
      SELECT jsonb_agg(jsonb_build_object('kind', x.kind, 'role', x.role, 'count', x.cnt) ORDER BY x.cnt DESC, x.kind, x.role)
      FROM (
        SELECT ae.kind, ae.role, count(*) AS cnt
        FROM public.auth_engagements ae
        WHERE ae.status = 'active'
          AND ae.requires_agreement IS TRUE
          AND ae.agreement_certificate_id IS NULL
        GROUP BY ae.kind, ae.role
      ) x
    ),
    'pending', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'engagement_id', ae.engagement_id,
        'person_id', ae.person_id,
        'member_id', m.id,
        'member_name', m.name,
        'member_email', m.email,
        'chapter', m.chapter,
        'kind', ae.kind,
        'role', ae.role,
        'initiative_id', ae.initiative_id,
        'initiative_title', i.title,
        'start_date', ae.start_date,
        'is_authoritative', ae.is_authoritative,
        'agreement_certificate_id', ae.agreement_certificate_id,
        'has_agreement_notification', EXISTS (
          SELECT 1 FROM public.notifications n
          WHERE n.recipient_id = m.id
            AND n.created_at >= COALESCE(ae.start_date::timestamptz, now() - interval '365 days')
            AND (
              lower(coalesce(n.type, '')) LIKE '%agreement%'
              OR lower(coalesce(n.type, '')) LIKE '%certificate%'
              OR lower(coalesce(n.title, '')) LIKE '%termo%'
              OR lower(coalesce(n.body, '')) LIKE '%termo%'
            )
        ),
        'next_action', CASE
          WHEN m.id IS NULL THEN 'investigate_missing_member'
          WHEN m.is_active IS NOT TRUE THEN 'reactivate_member_or_close_engagement'
          WHEN ae.kind = 'volunteer' THEN 'notify_member_to_sign_volunteer_term'
          WHEN ae.kind IN ('ambassador', 'study_group_owner', 'study_group_participant') THEN 'decide_template_for_kind_then_issue'
          ELSE 'review_special_kind_engagement'
        END
      ) ORDER BY ae.kind, ae.role, COALESCE(m.name, '')), '[]'::jsonb)
      FROM public.auth_engagements ae
      LEFT JOIN public.persons p ON p.id = ae.person_id
      LEFT JOIN public.members m ON m.person_id = p.id
      LEFT JOIN public.initiatives i ON i.id = ae.initiative_id
      WHERE ae.status = 'active'
        AND ae.requires_agreement IS TRUE
        AND ae.agreement_certificate_id IS NULL
    )
  );
END;
$function$;

COMMENT ON FUNCTION public.get_pending_agreement_engagements() IS
  'Issue #177: returns active engagements that require an agreement but lack a certificate. Visibility-only; does NOT issue or notify. Gated to manage_member. See P202_VOLUNTEER_LIFECYCLE_REMEDIATION_SPEC §2.';

GRANT EXECUTE ON FUNCTION public.get_pending_agreement_engagements() TO authenticated;

NOTIFY pgrst, 'reload schema';
