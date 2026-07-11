-- #1280 fix(tribe): review_tribe_request — approve idempotente contra engagement ativa pré-existente
--
-- O approve demovia volunteer ativo em OUTRAS research_tribes (tribe switch, initiative_id <> alvo)
-- mas INSERIA incondicionalmente na tribo alvo. Se o convidado já tinha uma engagement volunteer
-- ativa na MESMA initiative alvo (ex.: stub retroativo do backfill #1247, incidente David Gentil),
-- o approve criava uma SEGUNDA row ativa → violava AH_research_tribe_single_active_engagement
-- (a invariante só DETECTAVA pós-fato; o write-path não IMPEDIA).
--
-- Fix: antes do INSERT, checar se já existe engagement do mesmo kind_scope ativa nesta MESMA
-- initiative; se sim, reusar (no-op idempotente) em vez de inserir outra. Classe dual-write (#1217/#1270).
--
-- Base: corpo VIVO (pg_get_functiondef), não a migration original (evita drift).
CREATE OR REPLACE FUNCTION public.review_tribe_request(p_invitation_id uuid, p_decision text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_caller_person_id uuid;
  v_is_admin boolean;
  v_is_leader boolean;
  v_invitation record;
  v_initiative record;
  v_invitee_person_id uuid;
  v_engagement_id uuid;
  v_org_id uuid := '2b4f58ab-7c45-4170-8718-b77ee69ff906';
  v_slot_count integer;
  v_max_slots integer := public.tribe_capacity_limit();
BEGIN
  SELECT m.id, m.person_id INTO v_caller_member_id, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_decision NOT IN ('approve', 'decline') THEN
    RAISE EXCEPTION 'Decisão deve ser \"approve\" ou \"decline\" (recebido: %)', p_decision
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- cap the note (it lands verbatim in the requester's notification body)
  IF length(coalesce(p_note, '')) > 500 THEN
    RAISE EXCEPTION 'Nota muito longa (máx 500 caracteres)' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT * INTO v_invitation FROM public.initiative_invitations WHERE id = p_invitation_id;
  IF v_invitation.id IS NULL THEN
    RAISE EXCEPTION 'Pedido não encontrado' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT * INTO v_initiative FROM public.initiatives WHERE id = v_invitation.initiative_id;
  IF v_initiative.kind <> 'research_tribe' THEN
    RAISE EXCEPTION 'review_tribe_request só revisa pedidos de tribo (use review_initiative_request)'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF v_invitation.status <> 'pending' THEN
    RAISE EXCEPTION 'Pedido não está pendente (status=%)', v_invitation.status
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_invitation.expires_at < now() THEN
    -- do NOT UPDATE here: a RAISE rolls back the same statement, so the write is a no-op.
    -- The cron expire_stale_initiative_invitations commits the 'expired' state.
    RAISE EXCEPTION 'Pedido expirou' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- self-service request invariant (invitee == inviter)
  IF v_invitation.invitee_member_id <> v_invitation.inviter_member_id THEN
    RAISE EXCEPTION 'Não é um pedido self-service — o convidado deve responder via respond_to_initiative_invitation'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Authority: GP (manage_member) OR leader of THIS tribe (Caminho-3 inline-scope, no shared gate)
  v_is_admin := public.can_by_member(v_caller_member_id, 'manage_member');
  IF NOT v_is_admin THEN
    v_is_leader := EXISTS (
      SELECT 1 FROM public.engagements e
      WHERE e.person_id = v_caller_person_id
        AND e.initiative_id = v_invitation.initiative_id
        AND e.kind = 'volunteer'
        AND e.role = 'leader'
        AND e.status = 'active'
    );
    IF NOT v_is_leader THEN
      RAISE EXCEPTION 'Não autorizado: apenas o líder desta tribo ou o GP podem revisar'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- Capacidade (SSOT tribe_capacity_limit): só bloqueia o approve — decline sempre passa.
  -- Conta como count_tribe_slots(): membros ativos já na tribo, excluindo papéis sem vaga.
  IF p_decision = 'approve' THEN
    SELECT count(*) INTO v_slot_count
    FROM public.members m
    WHERE m.tribe_id = v_initiative.legacy_tribe_id
      AND m.member_status = 'active'
      AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'guest', 'none');
    IF v_slot_count >= v_max_slots THEN
      RAISE EXCEPTION 'Tribo lotada (%/%): peça ao GP para ajustar a capacidade ou escolha outra tribo', v_slot_count, v_max_slots
        USING ERRCODE = 'invalid_parameter_value';
    END IF;
  END IF;

  UPDATE public.initiative_invitations
  SET status = CASE WHEN p_decision = 'approve' THEN 'accepted' ELSE 'declined' END,
      reviewed_by = v_caller_member_id,
      reviewed_at = now(),
      reviewed_note = p_note,
      responded_at = now()
  WHERE id = p_invitation_id;

  IF p_decision = 'approve' THEN
    SELECT m.person_id INTO v_invitee_person_id
    FROM public.members m WHERE m.id = v_invitation.invitee_member_id;

    -- #1263 (Wave 3): atomic tribe switch. request_tribe_assignment blocks a member who already has
    -- a tribe, so this only bites the edge where a pending request predated a tribe join (or a GP
    -- force-move): the researcher holds an ACTIVE volunteer engagement in ANOTHER research_tribe.
    -- Demote it here — BEFORE inserting the new one — so the bridge trigger
    -- trg_sync_tribe_id_from_engagement never sees two active tribe engagements for this person, and
    -- AH (single active tribe engagement) + AG (members.tribe_id matches) stay at baseline 0.
    -- Use 'offboarded' (valid engagements_status_check value) — NEVER 'revoked' (not in the CHECK).
    UPDATE public.engagements e
       SET status = 'offboarded',
           revoked_at = now(),
           revoked_by = v_caller_person_id,   -- engagements.revoked_by FK -> persons(id), NOT members(id)
           revoke_reason = 'tribe_switch_on_approval',
           metadata = e.metadata || jsonb_build_object(
             'offboarded_via', 'tribe_switch_on_approval',
             'superseding_invitation_id', p_invitation_id,
             'reviewed_by_member_id', v_caller_member_id
           ),
           updated_at = now()
      FROM public.initiatives i
     WHERE e.initiative_id = i.id
       AND i.kind = 'research_tribe'
       AND e.person_id = v_invitee_person_id
       AND e.kind = 'volunteer'
       AND e.status = 'active'
       AND e.initiative_id <> v_invitation.initiative_id;

    -- #1280 idempotência: se já existe engagement do mesmo kind ativa nesta MESMA tribo, reusar
    -- (no-op) em vez de inserir uma segunda — que violaria AH_research_tribe_single_active_engagement.
    -- Bite: um pedido pendente materializado após um stub retroativo (backfill #1247) para a mesma tribo.
    SELECT e.id INTO v_engagement_id
    FROM public.engagements e
    WHERE e.person_id = v_invitee_person_id
      AND e.initiative_id = v_invitation.initiative_id
      AND e.kind = v_invitation.kind_scope
      AND e.status = 'active'
    ORDER BY e.created_at
    LIMIT 1;

    IF v_engagement_id IS NULL THEN
      INSERT INTO public.engagements
        (person_id, initiative_id, kind, role, status, legal_basis, granted_by, metadata, organization_id)
      VALUES (
        v_invitee_person_id,
        v_invitation.initiative_id,
        v_invitation.kind_scope,
        'participant',
        'active',
        'consent',
        v_caller_person_id,  -- engagements.granted_by FK -> persons(id), NOT members(id)
        jsonb_build_object(
          'source', 'tribe_request_approved',
          'invitation_id', p_invitation_id,
          'reviewed_by', v_caller_member_id,
          'review_authority', CASE WHEN v_is_admin THEN 'admin' ELSE 'tribe_leader' END,
          'requested_at', v_invitation.created_at
        ),
        v_org_id
      )
      RETURNING id INTO v_engagement_id;
    END IF;
  END IF;

  -- notify the requester of the outcome
  INSERT INTO public.notifications
    (recipient_id, type, title, body, link, source_type, source_id, actor_id, delivery_mode)
  VALUES (
    v_invitation.invitee_member_id,
    'tribe_request_reviewed',
    CASE WHEN p_decision = 'approve' THEN 'Pedido de tribo aprovado' ELSE 'Pedido de tribo recusado' END,
    CASE WHEN p_decision = 'approve'
         THEN 'Seu pedido para entrar na tribo ' || v_initiative.title || ' foi aprovado.'
         ELSE 'Seu pedido para entrar na tribo ' || v_initiative.title || ' foi recusado.' || coalesce(' Nota: ' || p_note, '')
    END,
    '/tribe/' || v_initiative.legacy_tribe_id::text,
    'initiative_invitation', p_invitation_id, v_caller_member_id, 'transactional_immediate'
  );

  RETURN jsonb_build_object(
    'ok', true,
    'invitation_id', p_invitation_id,
    'decision', p_decision,
    'engagement_id', v_engagement_id,
    'review_authority', CASE WHEN v_is_admin THEN 'admin' ELSE 'tribe_leader' END,
    'reviewed_at', now()
  );
END;
$function$
;
