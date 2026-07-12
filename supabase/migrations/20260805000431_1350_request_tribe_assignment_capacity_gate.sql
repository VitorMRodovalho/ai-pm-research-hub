-- #1350 — request_tribe_assignment must block (with a clear message) when the tribe is at cap.
--
-- Before: the capacity gate lived ONLY in the approve path (review_tribe_request) and legacy
-- select_tribe. request_tribe_assignment had NO capacity check, so a researcher could file a
-- request against a full tribe; it entered as `pending` but was un-approvable (the leader's
-- approve then raised "Tribo lotada (8/8)" -> HTTP 400). Anchor incident: Guilherme Matricarde
-- -> Tribo 6 (ROI & Portfólio), pending since 2026-07-09, stuck because the tribe is 8/8.
--
-- After (PM decision 2026-07-12): block the request itself, with the same clear message and the
-- SAME slot formula as review_tribe_request (active members on the tribe whose operational_role
-- is not sponsor/chapter_liaison/guest/none — the leader counts; cap SSOT = tribe_capacity_limit()
-- = platform_settings.max_researchers_per_tribe, default 7, live 8 = leader + 7). No waitlist
-- exists, so a pending on a full tribe is fragile; failing closed at request time is the fix.
--
-- Only re-captures request_tribe_assignment. review_tribe_request already gates + messages; the
-- FE surfacing of that message (the 400 the leader saw) is handled client-side.

CREATE OR REPLACE FUNCTION public.request_tribe_assignment(p_tribe_id integer, p_message text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_person_id uuid;
  v_member_status text;
  v_is_active boolean;
  v_initiative record;
  v_invitation_id uuid;
  v_deadline timestamptz;
  v_slot_count integer;
  v_max_slots integer := public.tribe_capacity_limit();
BEGIN
  SELECT m.id, m.person_id, m.member_status, m.is_active
    INTO v_member_id, v_person_id, v_member_status, v_is_active
    FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_is_active IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Membro inativo' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Deadline gate: block NEW tribe requests once the configured deadline has passed. SSOT setting;
  -- absent/null = open window (no enforcement). This is the real gate (the FE hides the picker too).
  v_deadline := (SELECT (value #>> '{}')::timestamptz FROM public.platform_settings WHERE key = 'tribe_request_deadline');
  IF v_deadline IS NOT NULL AND now() > v_deadline THEN
    RAISE EXCEPTION 'O prazo para pedir uma tribo encerrou. Fale com a coordenacao do Nucleo para entrar ou trocar de tribo.'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF length(coalesce(p_message, '')) < 50 THEN
    RAISE EXCEPTION 'A mensagem deve ter ao menos 50 caracteres descrevendo sua motivação (atual: %)', length(coalesce(p_message, ''))
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- WS-A3 parity with select_tribe: tribe entry requires the signed volunteer term.
  -- Fail closed if no person row (member_is_pre_onboarding(NULL,...) would return false).
  IF v_person_id IS NULL OR public.member_is_pre_onboarding(v_person_id, v_member_status) THEN
    RAISE EXCEPTION 'Assine o termo de voluntário antes de pedir uma tribo'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_initiative
  FROM public.initiatives
  WHERE legacy_tribe_id = p_tribe_id AND kind = 'research_tribe';

  IF v_initiative.id IS NULL THEN
    RAISE EXCEPTION 'Tribo não encontrada' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_initiative.status <> 'active' THEN
    RAISE EXCEPTION 'Esta tribo não está ativa' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- block if already in ANY tribe (self-service is "join your first tribe"; moves are GP-mediated
  -- via admin force-move). This keeps the AH single-active-engagement invariant intact on approval.
  IF EXISTS (
    SELECT 1 FROM public.engagements e
    JOIN public.initiatives i3 ON i3.id = e.initiative_id AND i3.kind = 'research_tribe'
    WHERE e.person_id = v_person_id
      AND e.kind = 'volunteer'
      AND e.status = 'active'
  ) THEN
    RAISE EXCEPTION 'Você já participa de uma tribo' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- one pending tribe request at a time (across all research_tribe initiatives)
  IF EXISTS (
    SELECT 1
    FROM public.initiative_invitations ii
    JOIN public.initiatives i2 ON i2.id = ii.initiative_id AND i2.kind = 'research_tribe'
    WHERE ii.invitee_member_id = v_member_id
      AND ii.status = 'pending'
  ) THEN
    RAISE EXCEPTION 'Você já tem um pedido de tribo pendente' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- #1350: capacity gate at REQUEST time (was only on approve/select_tribe). Same slot formula as
  -- review_tribe_request (p_tribe_id IS the legacy_tribe_id = members.tribe_id). Blocking here means
  -- no un-approvable pending is ever created against a full tribe. Cap SSOT = tribe_capacity_limit().
  SELECT count(*) INTO v_slot_count
  FROM public.members m
  WHERE m.tribe_id = p_tribe_id
    AND m.member_status = 'active'
    AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'guest', 'none');
  IF v_slot_count >= v_max_slots THEN
    RAISE EXCEPTION 'Tribo lotada (%/%): escolha outra tribo', v_slot_count, v_max_slots
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- #1257 (Wave 3, D2): TTL 7 dias EXPLÍCITO — revisão feita por líder voluntário precisa de mais
  -- folga que as 72h do default da tabela. Só o caminho de tribo seta 7d; o default (now()+72h)
  -- permanece para convites líder→pesquisador legítimos.
  INSERT INTO public.initiative_invitations
    (initiative_id, invitee_member_id, inviter_member_id, kind_scope, message, expires_at)
  VALUES
    (v_initiative.id, v_member_id, v_member_id, 'volunteer', p_message, now() + interval '7 days')
  RETURNING id INTO v_invitation_id;

  -- notify the tribe leader(s) — no PII in the body (LGPD minimisation).
  -- #1139 Item 2: link deep-links to the Membros tab (where the approval queue renders).
  INSERT INTO public.notifications
    (recipient_id, type, title, body, link, source_type, source_id, actor_id, delivery_mode)
  SELECT m2.id, 'tribe_request',
         'Novo pedido de entrada na tribo',
         'Um pesquisador pediu para entrar na tribo ' || v_initiative.title || '. Revise em /tribe/' || p_tribe_id::text || '.',
         '/tribe/' || p_tribe_id::text || '?tab=members',
         'initiative_invitation', v_invitation_id, v_member_id, 'transactional_immediate'
  FROM public.engagements e
  JOIN public.members m2 ON m2.person_id = e.person_id
  WHERE e.initiative_id = v_initiative.id
    AND e.kind = 'volunteer' AND e.role = 'leader' AND e.status = 'active';

  RETURN jsonb_build_object(
    'ok', true,
    'invitation_id', v_invitation_id,
    'tribe_id', p_tribe_id,
    'initiative_id', v_initiative.id,
    'expires_at', (now() + interval '7 days'),
    'note', 'O líder da tribo vai revisar seu pedido. Acompanhe por list_my_initiative_invitations.'
  );
END;
$function$;
