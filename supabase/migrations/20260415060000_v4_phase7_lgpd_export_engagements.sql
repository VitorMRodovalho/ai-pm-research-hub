-- ============================================================================
-- V4 Phase 7b — LGPD Export: add persons + engagements to export_my_data
-- ADR: ADR-0006 (Person + Engagement Identity Model)
-- LGPD: Art. 18, V (portabilidade de dados)
-- Rollback: Re-apply previous version from 20260411230500
-- ============================================================================

CREATE OR REPLACE FUNCTION public.export_my_data()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
DECLARE
  v_member_id uuid;
  v_member_email text;
  v_person_id uuid;
  v_result jsonb;
BEGIN
  SELECT id, email INTO v_member_id, v_member_email
  FROM public.members WHERE auth_id = auth.uid();

  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Resolve V4 person
  SELECT id INTO v_person_id FROM public.persons WHERE legacy_member_id = v_member_id;

  SELECT jsonb_build_object(
    -- Legacy profile (members table)
    'profile', (SELECT row_to_json(m)::jsonb FROM public.members m WHERE m.id = v_member_id),

    -- V4: Person record
    'person', CASE WHEN v_person_id IS NOT NULL THEN
      (SELECT row_to_json(p)::jsonb FROM public.persons p WHERE p.id = v_person_id)
    ELSE NULL END,

    -- V4: Engagements (all statuses — active, expired, revoked)
    'engagements', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', e.id,
        'kind', e.kind,
        'role', e.role,
        'status', e.status,
        'initiative_name', i.name,
        'start_date', e.start_date,
        'end_date', e.end_date,
        'legal_basis', e.legal_basis,
        'has_agreement', (e.agreement_certificate_id IS NOT NULL),
        'granted_at', e.granted_at,
        'revoked_at', e.revoked_at,
        'revoke_reason', e.revoke_reason
      ) ORDER BY e.start_date DESC)
      FROM public.engagements e
      LEFT JOIN public.initiatives i ON i.id = e.initiative_id
      WHERE e.person_id = v_person_id
    ), '[]'::jsonb),

    -- Existing exports
    'attendance', COALESCE((SELECT jsonb_agg(row_to_json(a)::jsonb) FROM public.attendance a WHERE a.member_id = v_member_id), '[]'::jsonb),
    'gamification', COALESCE((SELECT jsonb_agg(row_to_json(g)::jsonb) FROM public.gamification_points g WHERE g.member_id = v_member_id), '[]'::jsonb),
    'notifications', COALESCE((SELECT jsonb_agg(row_to_json(n)::jsonb) FROM public.notifications n WHERE n.recipient_id = v_member_id), '[]'::jsonb),
    'board_assignments', COALESCE((SELECT jsonb_agg(row_to_json(ba)::jsonb) FROM public.board_item_assignments ba WHERE ba.member_id = v_member_id), '[]'::jsonb),
    'cycle_history', COALESCE((SELECT jsonb_agg(row_to_json(mch)::jsonb) FROM public.member_cycle_history mch WHERE mch.member_id = v_member_id), '[]'::jsonb),
    'certificates', COALESCE((SELECT jsonb_agg(row_to_json(c)::jsonb) FROM public.certificates c WHERE c.member_id = v_member_id), '[]'::jsonb),
    'selection_applications', COALESCE((SELECT jsonb_agg(row_to_json(sa)::jsonb) FROM public.selection_applications sa WHERE sa.email = v_member_email), '[]'::jsonb),
    'onboarding', COALESCE((SELECT jsonb_agg(row_to_json(op)::jsonb) FROM public.onboarding_progress op WHERE op.member_id = v_member_id), '[]'::jsonb),
    'exported_at', now()
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.export_my_data() IS
  'LGPD Art. 18, V: Export all personal data. V4: includes persons + engagements + certificates.';

NOTIFY pgrst, 'reload schema';
