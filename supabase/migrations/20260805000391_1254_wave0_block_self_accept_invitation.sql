-- Wave 0 (#1254) — fechar auto-aprovacao em respond_to_initiative_invitation.
-- Um pedido self-service (invitee == inviter, criado por request_tribe_assignment) NAO pode ser
-- auto-aceito: a aprovacao e do revisor (review_tribe_request / review_initiative_request). Aceitar
-- o proprio pedido criaria o engagement pulando a revisao do lider -- fura o modelo hibrido
-- "lider confirma". 'decline' segue permitido (e o requester cancelando o proprio pedido pendente).
-- Convites reais (invitee != inviter, lider->pesquisador) permanecem inalterados.
--
-- Corpo baseado no VIVO (pg_get_functiondef, 2026-07-10); unica mudanca = o guard adicionado.
-- ROLLBACK: re-aplicar o corpo de 20260514330000 (respond_to_initiative_invitation).

CREATE OR REPLACE FUNCTION public.respond_to_initiative_invitation(p_invitation_id uuid, p_response text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_caller_person_id uuid;
  v_invitation record;
  v_engagement_id uuid;
  v_org_id uuid := '2b4f58ab-7c45-4170-8718-b77ee69ff906';
BEGIN
  -- Validate caller
  SELECT m.id, m.person_id INTO v_caller_member_id, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Validate response value
  IF p_response NOT IN ('accept', 'decline') THEN
    RAISE EXCEPTION 'Response must be "accept" or "decline" (got: %)', p_response
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Validate invitation
  SELECT * INTO v_invitation FROM public.initiative_invitations WHERE id = p_invitation_id;
  IF v_invitation.id IS NULL THEN
    RAISE EXCEPTION 'Invitation not found' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_invitation.invitee_member_id <> v_caller_member_id THEN
    RAISE EXCEPTION 'Unauthorized: caller is not the invitee' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_invitation.status <> 'pending' THEN
    RAISE EXCEPTION 'Invitation is not pending (current status: %)', v_invitation.status
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_invitation.expires_at < now() THEN
    -- Auto-expire on read
    UPDATE public.initiative_invitations SET status = 'expired' WHERE id = p_invitation_id;
    RAISE EXCEPTION 'Invitation has expired' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Wave 0 (#1254): a self-service request (invitee == inviter) must be approved by a reviewer, never
  -- self-accepted -- self-accept would create the engagement bypassing leader review (the hybrid
  -- model's core). decline stays allowed as the requester's own cancel path.
  IF p_response = 'accept' AND v_invitation.invitee_member_id = v_invitation.inviter_member_id THEN
    RAISE EXCEPTION 'Pedido self-service nao pode ser auto-aceito; a aprovacao e do revisor (lider/GP). Para cancelar, use decline.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Update invitation
  UPDATE public.initiative_invitations
  SET status = CASE WHEN p_response = 'accept' THEN 'accepted' ELSE 'declined' END,
      responded_at = now(),
      responded_note = p_note
  WHERE id = p_invitation_id;

  -- If accepted: create engagement
  IF p_response = 'accept' THEN
    INSERT INTO public.engagements
      (person_id, initiative_id, kind, role, status, legal_basis, granted_by, metadata, organization_id)
    VALUES (
      v_caller_person_id,
      v_invitation.initiative_id,
      v_invitation.kind_scope,
      'participant',  -- default role; kind_scope determines actual capabilities
      'active',
      'consent',
      v_invitation.inviter_member_id,
      jsonb_build_object(
        'source', 'invitation_accept',
        'invitation_id', p_invitation_id,
        'invited_by', v_invitation.inviter_member_id,
        'invited_at', v_invitation.created_at
      ),
      v_org_id
    )
    RETURNING id INTO v_engagement_id;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'invitation_id', p_invitation_id,
    'response', p_response,
    'engagement_id', v_engagement_id,
    'responded_at', now()
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
