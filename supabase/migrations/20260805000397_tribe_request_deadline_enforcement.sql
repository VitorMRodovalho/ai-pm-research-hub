-- Tribe request deadline enforcement (WS-A "prazo 16/07").
--
-- The tribe-choice deadline (16/07 23:59 BRT = 17/07 02:59 UTC) was communicated to volunteers via
-- WhatsApp, but nothing in code stopped new self-service requests after it. This migration makes the
-- deadline real, server-side:
--   1. SSOT setting `tribe_request_deadline` in platform_settings (ISO-8601 UTC; absent/null = open).
--   2. request_tribe_assignment: hard gate — rejects NEW requests once now() > deadline. This is the
--      actual enforcement (the FE picker hiding is cosmetic; the RPC is callable directly).
--   3. get_my_tribe_request_context: mirrors the gate as ineligible_reason='window_closed' and returns
--      the deadline so the FE can show it in the open picker and render a closed empty-state.
-- Switching tribes after the deadline is intentionally also closed (switch = leave + re-request; the
-- re-request hits this gate) -> post-deadline moves route through coordination.

-- 1. SSOT setting. ON CONFLICT so re-runs / deadline edits are idempotent.
INSERT INTO public.platform_settings (key, value, description, change_reason)
VALUES (
  'tribe_request_deadline',
  '"2026-07-17T02:59:00Z"'::jsonb,
  'Prazo final para pesquisadores pedirem entrada em tribo (self-service). ISO-8601 UTC. Ausente/null = janela aberta.',
  'enforcement do prazo 16/07 23h59 BRT comunicado aos voluntarios (WhatsApp)'
)
ON CONFLICT (key) DO UPDATE
  SET value = EXCLUDED.value,
      description = EXCLUDED.description,
      change_reason = EXCLUDED.change_reason,
      changed_at = now();

-- 2. request_tribe_assignment + deadline gate (v_deadline read once from the SSOT setting).
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

-- 3. get_my_tribe_request_context + window_closed reason + deadline in payload.
CREATE OR REPLACE FUNCTION public.get_my_tribe_request_context()
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
  v_tribe_id integer;
  v_has_tribe_engagement boolean;
  v_eligible boolean;
  v_reason text;
  v_current_tribe_title text;
  v_current_tribe_id integer;
  v_current_tribe_initiative_id uuid;
  v_pending jsonb;
  v_tribes jsonb;
  v_deadline timestamptz;
  v_window_closed boolean;
BEGIN
  SELECT m.id, m.person_id, m.member_status, m.is_active, m.tribe_id
    INTO v_member_id, v_person_id, v_member_status, v_is_active, v_tribe_id
    FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_member_id IS NULL THEN
    RETURN jsonb_build_object('eligible', false, 'ineligible_reason', 'no_member', 'current_tribe_title', NULL, 'current_tribe_id', NULL, 'current_tribe_initiative_id', NULL, 'pending', NULL, 'tribes', '[]'::jsonb, 'deadline', NULL);
  END IF;

  -- Deadline SSOT (absent/null = open window). Surfaced in the payload + drives the window_closed reason.
  v_deadline := (SELECT (value #>> '{}')::timestamptz FROM public.platform_settings WHERE key = 'tribe_request_deadline');
  v_window_closed := v_deadline IS NOT NULL AND now() > v_deadline;

  -- caller's pending research_tribe self-request (invitee == me), if any.
  -- #1255: invitation_id added so the FE can cancel this exact pending request.
  SELECT to_jsonb(p) INTO v_pending FROM (
    SELECT ii.id AS invitation_id, i.legacy_tribe_id AS tribe_id, i.title, ii.message, ii.created_at, ii.expires_at
    FROM public.initiative_invitations ii
    JOIN public.initiatives i ON i.id = ii.initiative_id AND i.kind = 'research_tribe'
    WHERE ii.invitee_member_id = v_member_id AND ii.status = 'pending'
    ORDER BY ii.created_at DESC
    LIMIT 1
  ) p;

  -- already in a tribe via an active engagement?
  v_has_tribe_engagement := EXISTS (
    SELECT 1 FROM public.engagements e
    JOIN public.initiatives i ON i.id = e.initiative_id AND i.kind = 'research_tribe'
    WHERE e.person_id = v_person_id AND e.kind = 'volunteer' AND e.status = 'active'
  );

  -- eligible to self-request: active, termed (not pre-onboarding), no tribe yet (mirrors request_tribe_assignment)
  v_eligible := v_is_active IS TRUE
    AND v_tribe_id IS NULL
    AND NOT v_has_tribe_engagement
    AND v_person_id IS NOT NULL
    AND NOT public.member_is_pre_onboarding(v_person_id, v_member_status);

  -- #1139 Item 1: surface WHY when ineligible so the FE renders an explicit empty-state instead of a
  -- blank block. Priority mirrors request_tribe_assignment's guard sequence: inactive → has-tribe → term.
  -- Deadline enforcement: if the window is closed and the caller has no tribe (so they would want to
  -- request), window_closed outranks the term/eligible states — after the deadline there is nothing to
  -- request. has_tribe callers keep their own state (the deadline is about joining, not their membership).
  IF v_window_closed AND v_tribe_id IS NULL AND NOT v_has_tribe_engagement THEN
    v_eligible := false;
    v_reason := 'window_closed';
  ELSIF v_eligible THEN
    v_reason := NULL;
  ELSIF v_person_id IS NULL THEN
    v_reason := 'no_member';
  ELSIF v_is_active IS DISTINCT FROM true THEN
    v_reason := 'inactive';
  ELSIF v_tribe_id IS NOT NULL OR v_has_tribe_engagement THEN
    v_reason := 'has_tribe';
  ELSIF public.member_is_pre_onboarding(v_person_id, v_member_status) THEN
    v_reason := 'pending_term';
  ELSE
    v_reason := 'ineligible';
  END IF;

  -- #1256: for the has_tribe empty-state, prefer the initiative where the caller holds the ACTIVE
  -- volunteer engagement — withdraw_from_initiative requires an active engagement on that initiative,
  -- so the FE's "leave tribe" action targets it. Returns tribe_id + initiative_id + title together.
  IF v_reason = 'has_tribe' THEN
    SELECT i.id, i.legacy_tribe_id, i.title
      INTO v_current_tribe_initiative_id, v_current_tribe_id, v_current_tribe_title
    FROM public.initiatives i
    JOIN public.engagements e ON e.initiative_id = i.id
      AND e.person_id = v_person_id AND e.kind = 'volunteer' AND e.status = 'active'
    WHERE i.kind = 'research_tribe'
    ORDER BY (i.legacy_tribe_id = v_tribe_id) DESC NULLS LAST, e.start_date DESC, e.created_at DESC
    LIMIT 1;

    -- legacy-only fallback: tribe_id set but no active engagement (liaison / stale bridge). Keep the
    -- title for the empty-state; leave initiative_id NULL so the FE hides the self-service leave action.
    IF v_current_tribe_title IS NULL THEN
      SELECT i.title, i.legacy_tribe_id INTO v_current_tribe_title, v_current_tribe_id
      FROM public.initiatives i
      WHERE i.kind = 'research_tribe' AND i.legacy_tribe_id = v_tribe_id
      ORDER BY i.legacy_tribe_id
      LIMIT 1;
    END IF;
  END IF;

  -- selectable active research_tribe tribes (single source of truth = initiatives, not static data)
  SELECT coalesce(
    jsonb_agg(jsonb_build_object('tribe_id', i.legacy_tribe_id, 'title', i.title) ORDER BY i.legacy_tribe_id),
    '[]'::jsonb
  ) INTO v_tribes
  FROM public.initiatives i
  WHERE i.kind = 'research_tribe' AND i.status = 'active' AND i.legacy_tribe_id IS NOT NULL;

  RETURN jsonb_build_object(
    'eligible', v_eligible,
    'ineligible_reason', v_reason,
    'current_tribe_title', v_current_tribe_title,
    'current_tribe_id', v_current_tribe_id,
    'current_tribe_initiative_id', v_current_tribe_initiative_id,
    'pending', v_pending,
    'tribes', v_tribes,
    'deadline', v_deadline
  );
END;
$function$;
