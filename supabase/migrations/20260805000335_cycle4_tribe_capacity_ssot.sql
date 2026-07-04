-- Virada C3→C4 — capacidade de tribo vira SSOT em platform_settings (decisão owner 04/07).
--
-- Antes: select_tribe e admin_force_tribe_selection hardcodavam v_max_slots := 6 (migs
-- 20260805000185 / 20260425143237), enquanto platform_settings.max_researchers_per_tribe
-- já existia com valor 10 e NADA o lia; e o fluxo híbrido novo (review_tribe_request,
-- mig 20260805000216) não checava capacidade NENHUMA (deferido na SPEC §4.5). Três
-- superfícies, três respostas diferentes para "tribo cheia".
--
-- Agora: helper tribe_capacity_limit() lê platform_settings (fallback = 10, o valor
-- vivo) e as três superfícies consomem o helper (Pattern 47 — um SSOT, zero literais).
-- Ajustar a capacidade do C4 = editar a setting, sem migration.
--
-- Semântica da contagem no fluxo híbrido: espelha count_tribe_slots() (membros ativos
-- na tribo excluindo sponsor/chapter_liaison/guest/none — ou seja, líderes CONTAM vaga,
-- como no dashboard admin). Os fluxos legados continuam contando tribe_selections
-- (self-select), inalterados na semântica — só o teto muda de literal para SSOT.

begin;

-- 1) o SSOT
create or replace function public.tribe_capacity_limit()
returns integer
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
AS $$
  select coalesce(
    (select (value #>> '{}')::int from public.platform_settings where key = 'max_researchers_per_tribe'),
    10
  );
$$;

revoke all on function public.tribe_capacity_limit() from public, anon;
grant execute on function public.tribe_capacity_limit() to authenticated;

comment on function public.tribe_capacity_limit() is
  'SSOT do teto de membros por tribo: platform_settings.max_researchers_per_tribe (fallback 10). Consumido por select_tribe / admin_force_tribe_selection / review_tribe_request.';

-- 2) select_tribe: v_max_slots := 6 → tribe_capacity_limit() (resto do corpo intacto, mig 185)
create or replace function public.select_tribe(p_tribe_id integer)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
AS $$
DECLARE
  v_uid           uuid;
  v_member_id     uuid;
  v_is_active     boolean;
  v_op_role       text;
  v_member_status text;
  v_person_id     uuid;
  v_deadline      timestamptz;
  v_slot_count    integer;
  v_max_slots     integer := public.tribe_capacity_limit();
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Não autenticado');
  END IF;

  SELECT id, is_active, operational_role, member_status
    INTO v_member_id, v_is_active, v_op_role, v_member_status
    FROM members
   WHERE auth_id = v_uid;

  IF v_member_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Membro não encontrado');
  END IF;

  IF v_is_active IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('success', false, 'error', 'Membro inativo');
  END IF;

  -- WS-A3: tribe selection requires the signed volunteer term (not pre-onboarding).
  SELECT id INTO v_person_id FROM public.persons WHERE legacy_member_id = v_member_id;
  -- Fail closed if no person row: member_is_pre_onboarding(NULL,...) would return
  -- false and silently skip the gate (mirrors the get_tribe_group_link guard).
  IF v_person_id IS NULL
     OR public.member_is_pre_onboarding(v_person_id, v_member_status) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Assine o termo de voluntário antes de escolher uma tribo');
  END IF;

  IF v_op_role = 'tribe_leader' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Líderes de tribo são alocados diretamente');
  END IF;

  SELECT selection_deadline_at::timestamptz
    INTO v_deadline
    FROM home_schedule
   LIMIT 1;

  -- R3 V4: bypass deadline for manage_platform holders (was: superadmin/manager/deputy_manager)
  IF v_deadline IS NOT NULL AND now() > v_deadline THEN
    IF NOT public.can_by_member(v_member_id, 'manage_platform'::text) THEN
      RETURN jsonb_build_object('success', false, 'error', 'Seleção encerrada');
    END IF;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM tribes WHERE id = p_tribe_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Tribo não encontrada');
  END IF;

  SELECT count(*)
    INTO v_slot_count
    FROM tribe_selections
   WHERE tribe_id = p_tribe_id
     AND member_id IS DISTINCT FROM v_member_id;

  IF v_slot_count >= v_max_slots THEN
    RETURN jsonb_build_object('success', false, 'error', 'Tribo lotada');
  END IF;

  INSERT INTO tribe_selections (member_id, tribe_id, selected_at)
  VALUES (v_member_id, p_tribe_id, now())
  ON CONFLICT (member_id)
  DO UPDATE SET tribe_id    = EXCLUDED.tribe_id,
                selected_at = EXCLUDED.selected_at;

  RETURN jsonb_build_object('success', true, 'tribe_id', p_tribe_id);
END;
$$;

-- 3) admin_force_tribe_selection: idem (corpo da mig 20260425143237 intacto no resto)
create or replace function public.admin_force_tribe_selection(p_member_id uuid, p_tribe_id integer)
returns json
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_current_count INTEGER;
  v_max_slots INTEGER := public.tribe_capacity_limit();
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RETURN json_build_object('error', 'Unauthorized: requires manage_member permission');
  END IF;

  -- Check slot availability
  SELECT COUNT(*) INTO v_current_count
  FROM public.tribe_selections WHERE tribe_id = p_tribe_id;

  IF v_current_count >= v_max_slots THEN
    RETURN json_build_object('error', 'Tribo lotada (' || v_current_count || '/' || v_max_slots || ')');
  END IF;

  -- Remove existing selection if any
  DELETE FROM public.tribe_selections WHERE member_id = p_member_id;

  -- Insert new selection
  INSERT INTO public.tribe_selections (member_id, tribe_id, selected_at)
  VALUES (p_member_id, p_tribe_id, now());

  RETURN json_build_object('success', true, 'tribe_id', p_tribe_id);
END;
$$;

-- 4) review_tribe_request: ganha o cap que a SPEC §4.5 tinha deferido — checado só no
--    approve, ANTES do write, contando como count_tribe_slots() (members ativos na tribo,
--    excluindo sponsor/chapter_liaison/guest/none). Resto do corpo (mig 216) intacto.
create or replace function public.review_tribe_request(p_invitation_id uuid, p_decision text, p_note text DEFAULT NULL::text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
AS $$
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
    RAISE EXCEPTION 'Decisão deve ser "approve" ou "decline" (recebido: %)', p_decision
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
$$;

commit;
