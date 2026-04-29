-- Phase B'' batch 16.1: validate_privacy_policy_consistency V3 sa-only → V4 can_by_member('manage_platform')
-- V3 gate: members.is_superadmin = true
-- V4 mapping: manage_platform covers volunteer manager/deputy_manager/co_gp + sa
-- Impact: V3=2, V4=2 (clean match in current state; +manager/deputy_manager/co_gp parity is admin-tier consistent)
CREATE OR REPLACE FUNCTION public.validate_privacy_policy_consistency()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_issues jsonb := '[]'::jsonb;
  v_current_version text;
  v_kind record;
BEGIN
  SELECT id INTO v_caller_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_member_id IS NULL OR NOT public.can_by_member(v_caller_member_id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Superadmin only';
  END IF;

  SELECT version INTO v_current_version
  FROM privacy_policy_versions
  ORDER BY effective_at DESC LIMIT 1;

  FOR v_kind IN
    SELECT slug, display_name, legal_basis, retention_days_after_end,
           anonymization_policy, requires_agreement
    FROM engagement_kinds
    ORDER BY slug
  LOOP
    IF v_kind.retention_days_after_end > 1825 THEN
      v_issues := v_issues || jsonb_build_array(jsonb_build_object(
        'kind', v_kind.slug,
        'severity', 'warning',
        'issue', 'Retention exceeds 5 years (' || v_kind.retention_days_after_end || ' days). Verify legal justification.'
      ));
    END IF;

    IF v_kind.legal_basis = 'consent' AND NOT v_kind.requires_agreement THEN
      v_issues := v_issues || jsonb_build_array(jsonb_build_object(
        'kind', v_kind.slug,
        'severity', 'error',
        'issue', 'Consent-based kind does not require agreement. LGPD Art. 8 requires explicit consent documentation.'
      ));
    END IF;

    IF v_kind.retention_days_after_end IS NULL OR v_kind.retention_days_after_end = 0 THEN
      v_issues := v_issues || jsonb_build_array(jsonb_build_object(
        'kind', v_kind.slug,
        'severity', 'error',
        'issue', 'No retention period configured. Must be documented per LGPD Art. 15.'
      ));
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'current_policy_version', v_current_version,
    'total_engagement_kinds', (SELECT count(*) FROM engagement_kinds),
    'issues_found', jsonb_array_length(v_issues),
    'issues', v_issues,
    'unnotified_versions', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', id, 'version', version, 'effective_at', effective_at
      )), '[]'::jsonb)
      FROM privacy_policy_versions
      WHERE notification_campaign_id IS NULL
    )
  );
END;
$function$;
