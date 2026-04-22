-- ============================================================================
-- Issue #88 Wave 1 — Owner pode convocar membros para sua initiative
--
-- Contexto: schema `engagement_kinds.created_by_role` permite `owner` convocar
-- (ex.: study_group_participant para Preparatório CPMAI, workgroup_member
-- para Hub de Comunicação). MAS o RPC `manage_initiative_engagement`
-- exigia `can(..., 'manage_member', 'initiative', id)` que é admin-only.
--
-- Discrepância: schema modela self-service, RPC bloqueia. Owner de study_group
-- ou workgroup coordinator não conseguia adicionar participantes — sempre
-- precisava escalar para GP/manager.
--
-- Fix: se caller NÃO tem `manage_member`, verifica se é owner da initiative
-- (engagement kind terminando em '_owner' OR '_coordinator' ativo na
-- initiative em questão) AND se o kind pedido permite owner como creator.
--
-- Preserva: admin/manager/deputy_manager continuam podendo convocar qualquer
-- kind em qualquer initiative via canV4('manage_member'). Fix é aditivo,
-- não-destrutivo para o flow atual.
--
-- Ref:
-- - ADR-0006 (engagement model), ADR-0008 (per-kind lifecycle), ADR-0009
-- - engagement_kinds.created_by_role já contempla 'owner'/'manager'/etc
-- - Issue #88 para contexto completo + 3 personas (CPMAI prep, CPMAI study,
--   Hub Comunicação)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.manage_initiative_engagement(
  p_initiative_id uuid,
  p_person_id uuid,
  p_kind text,
  p_role text DEFAULT 'participant'::text,
  p_action text DEFAULT 'add'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_person_id uuid;
  v_initiative record;
  v_engagement record;
  v_org_id uuid := '2b4f58ab-7c45-4170-8718-b77ee69ff906';
  v_is_admin boolean;
  v_is_owner_of_initiative boolean;
  v_kind_allows_owner boolean;
BEGIN
  SELECT p.id INTO v_caller_person_id
  FROM persons p WHERE p.auth_id = auth.uid();

  IF v_caller_person_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- Admin-class check (primary path, preserved)
  v_is_admin := can(v_caller_person_id, 'manage_member', 'initiative', p_initiative_id);

  -- If not admin, check owner self-service path (Wave 1 new)
  IF NOT v_is_admin THEN
    v_is_owner_of_initiative := EXISTS (
      SELECT 1 FROM engagements e
      WHERE e.person_id = v_caller_person_id
        AND e.initiative_id = p_initiative_id
        AND e.status = 'active'
        AND (
          e.kind LIKE '%_owner'
          OR e.kind LIKE '%_coordinator'
          OR e.role IN ('owner','coordinator','lead')
        )
    );

    v_kind_allows_owner := EXISTS (
      SELECT 1 FROM engagement_kinds ek
      WHERE ek.slug = p_kind
        AND (
          'owner' = ANY(ek.created_by_role)
          OR 'coordinator' = ANY(ek.created_by_role)
        )
    );

    IF NOT (v_is_owner_of_initiative AND v_kind_allows_owner) THEN
      RETURN jsonb_build_object(
        'error', 'Unauthorized: requires manage_member permission OR owner/coordinator of this initiative with kind that allows owner creation',
        'hint', CASE
          WHEN NOT v_is_owner_of_initiative THEN 'Caller is not active owner/coordinator of initiative ' || p_initiative_id::text
          ELSE 'Engagement kind "' || p_kind || '" does not allow owner as creator (check engagement_kinds.created_by_role)'
        END
      );
    END IF;
  END IF;

  SELECT i.id, i.kind, i.status INTO v_initiative
  FROM initiatives i WHERE i.id = p_initiative_id;

  IF v_initiative IS NULL THEN
    RETURN jsonb_build_object('error', 'Initiative not found');
  END IF;

  IF v_initiative.status NOT IN ('active', 'draft') THEN
    RETURN jsonb_build_object('error', 'Initiative is not active');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM engagement_kinds ek
    WHERE ek.slug = p_kind
      AND v_initiative.kind = ANY(ek.initiative_kinds_allowed)
  ) THEN
    RETURN jsonb_build_object('error',
      format('Engagement kind "%s" not allowed for initiative kind "%s"', p_kind, v_initiative.kind));
  END IF;

  IF p_action = 'add' THEN
    IF NOT EXISTS (SELECT 1 FROM persons WHERE id = p_person_id) THEN
      RETURN jsonb_build_object('error', 'Person not found');
    END IF;

    IF EXISTS (
      SELECT 1 FROM engagements e
      WHERE e.person_id = p_person_id AND e.initiative_id = p_initiative_id AND e.status = 'active'
    ) THEN
      RETURN jsonb_build_object('error', 'Person already has active engagement in this initiative');
    END IF;

    INSERT INTO engagements (person_id, initiative_id, kind, role, status, legal_basis, granted_by, metadata, organization_id)
    VALUES (p_person_id, p_initiative_id, p_kind, p_role, 'active', 'consent',
            v_caller_person_id,
            jsonb_build_object(
              'source', 'manage_initiative_engagement',
              'added_by', v_caller_person_id::text,
              'invoked_as', CASE WHEN v_is_admin THEN 'admin' ELSE 'initiative_owner' END
            ),
            v_org_id)
    RETURNING * INTO v_engagement;

    RETURN jsonb_build_object('ok', true, 'action', 'added', 'engagement_id', v_engagement.id, 'authorized_as', CASE WHEN v_is_admin THEN 'admin' ELSE 'initiative_owner' END);

  ELSIF p_action = 'remove' THEN
    UPDATE engagements SET
      status = 'revoked',
      revoked_at = now(),
      revoked_by = v_caller_person_id,
      revoke_reason = 'Removed via manage_initiative_engagement',
      updated_at = now()
    WHERE person_id = p_person_id
      AND initiative_id = p_initiative_id
      AND status = 'active'
    RETURNING * INTO v_engagement;

    IF v_engagement IS NULL THEN
      RETURN jsonb_build_object('error', 'No active engagement found for this person');
    END IF;

    RETURN jsonb_build_object('ok', true, 'action', 'removed', 'engagement_id', v_engagement.id);

  ELSIF p_action = 'update_role' THEN
    UPDATE engagements SET
      role = p_role,
      updated_at = now()
    WHERE person_id = p_person_id
      AND initiative_id = p_initiative_id
      AND status = 'active'
    RETURNING * INTO v_engagement;

    IF v_engagement IS NULL THEN
      RETURN jsonb_build_object('error', 'No active engagement found for this person');
    END IF;

    RETURN jsonb_build_object('ok', true, 'action', 'role_updated', 'engagement_id', v_engagement.id, 'new_role', p_role);

  ELSE
    RETURN jsonb_build_object('error', format('Unknown action: %s', p_action));
  END IF;
END;
$function$;
