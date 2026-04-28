-- ADR-0061 W6: Cross-initiative engagement audit RPC
-- Closes #88 backlog: PMI-Latam admin needs org-wide visibility of engagements
-- by kind ("all study_group_owner across org", "all evaluators in committees").
-- Authority: view_internal_analytics (V4 audit-scope action).
-- LGPD: logs PII access per distinct target member when names returned.
-- Rollback: DROP FUNCTION public.list_initiative_engagements_by_kind(text, text, text, integer);

CREATE OR REPLACE FUNCTION public.list_initiative_engagements_by_kind(
  p_engagement_kind text DEFAULT NULL,
  p_initiative_kind text DEFAULT NULL,
  p_status_filter text DEFAULT 'active',
  p_limit integer DEFAULT 100
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_member_id uuid;
  v_clamped_limit integer;
  v_engagements jsonb;
  v_total integer;
  v_member_ids uuid[];
BEGIN
  -- Identify caller from auth_id -> members
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();

  IF v_caller_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- Org-wide audit gate
  IF NOT public.can_by_member(v_caller_member_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Not authorized: requires view_internal_analytics');
  END IF;

  -- At least one filter required (avoid unbounded org-wide scan)
  IF p_engagement_kind IS NULL AND p_initiative_kind IS NULL THEN
    RETURN jsonb_build_object(
      'error', 'At least one of p_engagement_kind or p_initiative_kind is required',
      'hint', 'Use p_engagement_kind=''study_group_owner'' or p_initiative_kind=''workgroup'' to scope the audit.'
    );
  END IF;

  IF p_status_filter NOT IN ('active', 'all', 'revoked', 'onboarding') THEN
    RETURN jsonb_build_object('error', format('Invalid p_status_filter: %s. Use active|all|revoked|onboarding', p_status_filter));
  END IF;

  v_clamped_limit := greatest(1, least(500, coalesce(p_limit, 100)));

  WITH base AS (
    SELECT
      e.id AS engagement_id,
      e.kind,
      e.role,
      e.status,
      e.start_date,
      e.end_date,
      e.granted_at,
      e.revoked_at,
      e.metadata,
      e.person_id,
      p.name AS person_name,
      mb.id AS member_id,
      i.id AS initiative_id,
      i.title AS initiative_title,
      i.kind AS initiative_kind,
      i.status AS initiative_status,
      ek.display_name AS kind_display
    FROM public.engagements e
    JOIN public.persons p ON p.id = e.person_id
    LEFT JOIN public.members mb ON mb.id = p.legacy_member_id
    JOIN public.initiatives i ON i.id = e.initiative_id
    LEFT JOIN public.engagement_kinds ek ON ek.slug = e.kind
    WHERE (p_engagement_kind IS NULL OR e.kind = p_engagement_kind)
      AND (p_initiative_kind IS NULL OR i.kind = p_initiative_kind)
      AND (
        (p_status_filter = 'active' AND e.status = 'active')
        OR (p_status_filter = 'all')
        OR (p_status_filter = 'revoked' AND e.status = 'revoked')
        OR (p_status_filter = 'onboarding' AND e.status = 'onboarding')
      )
    ORDER BY i.title, e.role, p.name
    LIMIT v_clamped_limit
  ),
  agg AS (
    SELECT
      coalesce(jsonb_agg(jsonb_build_object(
        'engagement_id', engagement_id,
        'kind', kind,
        'kind_display', kind_display,
        'role', role,
        'status', status,
        'start_date', start_date,
        'end_date', end_date,
        'granted_at', granted_at,
        'revoked_at', revoked_at,
        'person_id', person_id,
        'person_name', person_name,
        'member_id', member_id,
        'initiative_id', initiative_id,
        'initiative_title', initiative_title,
        'initiative_kind', initiative_kind,
        'initiative_status', initiative_status,
        'metadata_source', metadata->>'source'
      )), '[]'::jsonb) AS engagements,
      count(*)::integer AS total,
      array_remove(array_agg(DISTINCT member_id), NULL) AS member_ids
    FROM base
  )
  SELECT engagements, total, member_ids
  INTO v_engagements, v_total, v_member_ids
  FROM agg;

  -- LGPD: log PII access (name field) per distinct target member
  IF v_total > 0 AND v_member_ids IS NOT NULL AND array_length(v_member_ids, 1) > 0 THEN
    INSERT INTO public.pii_access_log (accessor_id, target_member_id, fields_accessed, context, reason)
    SELECT
      v_caller_member_id,
      unnest(v_member_ids),
      ARRAY['name']::text[],
      'list_initiative_engagements_by_kind',
      format('engagement_kind=%s initiative_kind=%s status=%s',
        coalesce(p_engagement_kind, '*'),
        coalesce(p_initiative_kind, '*'),
        p_status_filter
      );
  END IF;

  RETURN jsonb_build_object(
    'filters', jsonb_build_object(
      'engagement_kind', p_engagement_kind,
      'initiative_kind', p_initiative_kind,
      'status_filter', p_status_filter,
      'limit', v_clamped_limit
    ),
    'total_count', v_total,
    'truncated', v_total >= v_clamped_limit,
    'engagements', v_engagements
  );
END;
$$;

REVOKE ALL ON FUNCTION public.list_initiative_engagements_by_kind(text, text, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_initiative_engagements_by_kind(text, text, text, integer) TO authenticated;

COMMENT ON FUNCTION public.list_initiative_engagements_by_kind(text, text, text, integer) IS
'ADR-0061 W6: Cross-initiative audit RPC. Returns engagements org-wide filtered by engagement kind (e.g., study_group_owner) and/or initiative kind (e.g., workgroup). Authority: view_internal_analytics. LGPD: logs PII access per target member. Status filter: active|all|revoked|onboarding. Limit clamped to [1,500].';

NOTIFY pgrst, 'reload schema';
