-- ============================================================================
-- p205 / Issue #169 — fix manage_initiative_engagement RPC
-- ============================================================================
--
-- Two bugs found at p205 close (PM testing change-função flow):
--
-- 1. Kind validation ran upfront before action branching, so action='remove'
--    failed with empty p_kind even though remove doesn't need kind. Frontend
--    workaround was to pass currentKind on remove (commit 0ca7910a), but
--    the real fix is RPC-side. Move kind validation inside `IF p_action='add'`.
--
-- 2. Remove branch set status='revoked' but engagements_status_check constraint
--    only allows: pending/active/suspended/expired/offboarded/anonymized.
--    'revoked' is NOT in the allowed enum despite revoked_at/revoked_by/
--    revoke_reason columns existing on the table. Drift between original design
--    intent (revoke semantics) and current constraint. Use 'expired' instead
--    (engagement reached its end) while keeping revoke_* columns for audit.
--
--    Cleaner long-term fix would be either (a) add 'revoked' to the constraint
--    enum, or (b) drop revoke_* columns and use expiry-only semantics. That
--    decision is deferred — backlogged as a separate item. This hotfix
--    unblocks PM #169 ramp at T-11d.
--
-- DROP + CREATE used because parameters carried defaults that CREATE OR REPLACE
-- couldn't preserve cleanly.
-- ============================================================================

DROP FUNCTION IF EXISTS public.manage_initiative_engagement(uuid, uuid, text, text, text);

CREATE OR REPLACE FUNCTION public.manage_initiative_engagement(
  p_initiative_id uuid, p_person_id uuid, p_kind text, p_role text, p_action text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_caller_person_id uuid; v_initiative record; v_engagement record;
  v_org_id uuid := '2b4f58ab-7c45-4170-8718-b77ee69ff906';
  v_is_admin boolean; v_is_owner_of_initiative boolean; v_kind_allows_owner boolean;
BEGIN
  SELECT p.id INTO v_caller_person_id FROM persons p WHERE p.auth_id = auth.uid();
  IF v_caller_person_id IS NULL THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  v_is_admin := can(v_caller_person_id, 'manage_member', 'initiative', p_initiative_id);
  IF NOT v_is_admin THEN
    v_is_owner_of_initiative := EXISTS (SELECT 1 FROM engagements e WHERE e.person_id = v_caller_person_id AND e.initiative_id = p_initiative_id AND e.status = 'active' AND (e.kind LIKE '%_owner' OR e.kind LIKE '%_coordinator' OR e.role IN ('owner','coordinator','lead')));
    v_kind_allows_owner := EXISTS (SELECT 1 FROM engagement_kinds ek WHERE ek.slug = p_kind AND ('owner' = ANY(ek.created_by_role) OR 'coordinator' = ANY(ek.created_by_role)));
    IF NOT (v_is_owner_of_initiative AND v_kind_allows_owner) THEN
      RETURN jsonb_build_object('error', 'Unauthorized', 'hint', CASE WHEN NOT v_is_owner_of_initiative THEN 'Caller is not active owner/coordinator of initiative' ELSE 'Engagement kind does not allow owner as creator' END);
    END IF;
  END IF;
  SELECT i.id, i.kind, i.status INTO v_initiative FROM initiatives i WHERE i.id = p_initiative_id;
  IF v_initiative IS NULL THEN RETURN jsonb_build_object('error', 'Initiative not found'); END IF;
  IF v_initiative.status NOT IN ('active', 'draft') THEN RETURN jsonb_build_object('error', 'Initiative is not active'); END IF;

  IF p_action = 'add' THEN
    -- Kind validation only required for add (remove/update_role reference existing engagement)
    IF NOT EXISTS (SELECT 1 FROM engagement_kinds ek WHERE ek.slug = p_kind AND v_initiative.kind = ANY(ek.initiative_kinds_allowed)) THEN
      RETURN jsonb_build_object('error', format('Engagement kind "%s" not allowed for initiative kind "%s"', p_kind, v_initiative.kind));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM persons WHERE id = p_person_id) THEN RETURN jsonb_build_object('error', 'Person not found'); END IF;
    IF EXISTS (SELECT 1 FROM engagements e WHERE e.person_id = p_person_id AND e.initiative_id = p_initiative_id AND e.status = 'active') THEN
      RETURN jsonb_build_object('error', 'Person already has active engagement in this initiative');
    END IF;
    INSERT INTO engagements (person_id, initiative_id, kind, role, status, legal_basis, granted_by, metadata, organization_id)
    VALUES (p_person_id, p_initiative_id, p_kind, p_role, 'active', 'consent', v_caller_person_id,
      jsonb_build_object('source', 'manage_initiative_engagement', 'added_by', v_caller_person_id::text, 'invoked_as', CASE WHEN v_is_admin THEN 'admin' ELSE 'initiative_owner' END), v_org_id)
    RETURNING * INTO v_engagement;
    RETURN jsonb_build_object('ok', true, 'action', 'added', 'engagement_id', v_engagement.id, 'authorized_as', CASE WHEN v_is_admin THEN 'admin' ELSE 'initiative_owner' END);
  ELSIF p_action = 'remove' THEN
    -- Use 'expired' (valid in engagements_status_check). revoke_* columns preserved for audit.
    UPDATE engagements SET status = 'expired', revoked_at = now(), revoked_by = v_caller_person_id, revoke_reason = 'Removed via manage_initiative_engagement', updated_at = now()
    WHERE person_id = p_person_id AND initiative_id = p_initiative_id AND status = 'active' RETURNING * INTO v_engagement;
    IF v_engagement IS NULL THEN RETURN jsonb_build_object('error', 'No active engagement found for this person'); END IF;
    RETURN jsonb_build_object('ok', true, 'action', 'removed', 'engagement_id', v_engagement.id);
  ELSIF p_action = 'update_role' THEN
    UPDATE engagements SET role = p_role, updated_at = now()
    WHERE person_id = p_person_id AND initiative_id = p_initiative_id AND status = 'active' RETURNING * INTO v_engagement;
    IF v_engagement IS NULL THEN RETURN jsonb_build_object('error', 'No active engagement found for this person'); END IF;
    RETURN jsonb_build_object('ok', true, 'action', 'role_updated', 'engagement_id', v_engagement.id, 'new_role', p_role);
  ELSE RETURN jsonb_build_object('error', format('Unknown action: %s', p_action));
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.manage_initiative_engagement(uuid, uuid, text, text, text) TO authenticated;
NOTIFY pgrst, 'reload schema';
