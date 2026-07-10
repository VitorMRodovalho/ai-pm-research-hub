-- #1257 (Wave 3) — Leader-review hardening for the hybrid tribe-entry flow.
-- Gap F3 / decision D2 + the #1263 systemic fix. See
-- docs/specs/SPEC_TRIBE_SWITCH_AND_LEADER_REVIEW.md §Wave 3.
--
-- Four coordinated changes (all DDL bodies based on the LIVE function via pg_get_functiondef,
-- per docs/reference — do NOT reconstruct from an older migration):
--   1. request_tribe_assignment: TTL 7d EXPLICIT on the INSERT (tribe requests only). The table
--      default (initiative_invitations.expires_at DEFAULT now()+72h) is LEFT UNTOUCHED so legitimate
--      leader->researcher invites keep their 72h window.
--   2. review_tribe_request: #1263 atomic tribe switch — on approve, demote any OTHER active tribe
--      engagement the researcher holds so admission is a clean switch (keeps AH single-active + AG
--      tribe_id at baseline 0). Priscila Oliveira was the live evidence (two active tribe engagements
--      after a stale pending request was approved into a second tribe).
--   3. initiative_invitations.metadata (new jsonb column) + process_tribe_request_nudges(): a D-2
--      leader nudge (dedup once per request via metadata->>'leader_nudged_at') and a GP fallback on
--      expiry (dedup via metadata->>'gp_fallback_at').
--   4. cron 'tribe-request-nudge-hourly' (15 * * * *) drives (3).

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. request_tribe_assignment — TTL 7d explicit (tribe path only)
-- ─────────────────────────────────────────────────────────────────────────────
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

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. review_tribe_request — #1263 atomic tribe switch on approval
-- ─────────────────────────────────────────────────────────────────────────────
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
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Nudge D-2 + GP fallback on expiry
-- ─────────────────────────────────────────────────────────────────────────────

-- Additive: per-invitation nudge bookkeeping. No metadata column existed on initiative_invitations;
-- the D-2 leader nudge and the GP fallback each dedup once via a timestamp flag stored here.
ALTER TABLE public.initiative_invitations
  ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE OR REPLACE FUNCTION public.process_tribe_request_nudges(p_dry_run boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_run_at timestamptz := now();
  v_leader_due int := 0;
  v_gp_due int := 0;
  v_leader_notifs int := 0;
  v_gp_notifs int := 0;
BEGIN
  -- ── Part 1: D-2 leader nudge ──
  -- Due cohort: pending research_tribe self-requests within 2 days of expiry, not yet nudged.
  SELECT count(*) INTO v_leader_due
  FROM public.initiative_invitations ii
  JOIN public.initiatives i ON i.id = ii.initiative_id AND i.kind = 'research_tribe'
  WHERE ii.status = 'pending'
    AND (ii.metadata->>'leader_nudged_at') IS NULL
    AND ii.expires_at > v_run_at
    AND ii.expires_at <= v_run_at + interval '2 days';

  IF NOT p_dry_run AND v_leader_due > 0 THEN
    WITH due AS (
      SELECT ii.id AS invitation_id, ii.initiative_id, i.legacy_tribe_id, i.title
      FROM public.initiative_invitations ii
      JOIN public.initiatives i ON i.id = ii.initiative_id AND i.kind = 'research_tribe'
      WHERE ii.status = 'pending'
        AND (ii.metadata->>'leader_nudged_at') IS NULL
        AND ii.expires_at > v_run_at
        AND ii.expires_at <= v_run_at + interval '2 days'
    ), ins AS (
      INSERT INTO public.notifications
        (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
      SELECT m2.id, 'tribe_request_nudge',
             'Pedido de entrada na tribo perto de expirar',
             'Um pedido de entrada na tribo ' || d.title || ' aguarda sua revisão e expira em breve. Aprove ou recuse em /tribe/' || d.legacy_tribe_id::text || '?tab=members.',
             '/tribe/' || d.legacy_tribe_id::text || '?tab=members',
             'initiative_invitation', d.invitation_id, 'transactional_immediate'
      FROM due d
      JOIN public.engagements e ON e.initiative_id = d.initiative_id
        AND e.kind = 'volunteer' AND e.role = 'leader' AND e.status = 'active'
      JOIN public.members m2 ON m2.person_id = e.person_id
      RETURNING 1
    )
    SELECT count(*) INTO v_leader_notifs FROM ins;

    -- Mark ALL due (even leaderless tribes) so we nudge at most once; the GP fallback catches a
    -- leaderless tribe at expiry.
    UPDATE public.initiative_invitations ii
       SET metadata = ii.metadata || jsonb_build_object('leader_nudged_at', v_run_at)
    FROM public.initiatives i
    WHERE ii.initiative_id = i.id AND i.kind = 'research_tribe'
      AND ii.status = 'pending'
      AND (ii.metadata->>'leader_nudged_at') IS NULL
      AND ii.expires_at > v_run_at
      AND ii.expires_at <= v_run_at + interval '2 days';
  END IF;

  -- ── Part 2: GP fallback on expiry ──
  -- Recently-expired (last 3 days) research_tribe requests with no GP fallback yet. The 3-day bound
  -- prevents a backfill blast on ship; the metadata flag prevents repeats.
  SELECT count(*) INTO v_gp_due
  FROM public.initiative_invitations ii
  JOIN public.initiatives i ON i.id = ii.initiative_id AND i.kind = 'research_tribe'
  WHERE ii.status = 'expired'
    AND (ii.metadata->>'gp_fallback_at') IS NULL
    AND ii.expires_at > v_run_at - interval '3 days';

  IF NOT p_dry_run AND v_gp_due > 0 THEN
    WITH due AS (
      SELECT ii.id AS invitation_id, i.legacy_tribe_id, i.title
      FROM public.initiative_invitations ii
      JOIN public.initiatives i ON i.id = ii.initiative_id AND i.kind = 'research_tribe'
      WHERE ii.status = 'expired'
        AND (ii.metadata->>'gp_fallback_at') IS NULL
        AND ii.expires_at > v_run_at - interval '3 days'
    ), ins AS (
      INSERT INTO public.notifications
        (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
      SELECT m.id, 'tribe_request_expired_gp',
             'Pedido de tribo expirou sem revisão',
             'Um pedido de entrada na tribo ' || d.title || ' expirou sem o líder revisar. Faça a triagem em /tribe/' || d.legacy_tribe_id::text || '?tab=members.',
             '/tribe/' || d.legacy_tribe_id::text || '?tab=members',
             'initiative_invitation', d.invitation_id, 'transactional_immediate'
      FROM due d
      -- Fan-out: 1 fallback por GP (manager). Espelha detect_stuck_selection_funnel (ADR-0011 Amd A).
      CROSS JOIN public.members m
      WHERE m.operational_role = 'manager' AND m.member_status = 'active'
      RETURNING 1
    )
    SELECT count(*) INTO v_gp_notifs FROM ins;

    UPDATE public.initiative_invitations ii
       SET metadata = ii.metadata || jsonb_build_object('gp_fallback_at', v_run_at)
    FROM public.initiatives i
    WHERE ii.initiative_id = i.id AND i.kind = 'research_tribe'
      AND ii.status = 'expired'
      AND (ii.metadata->>'gp_fallback_at') IS NULL
      AND ii.expires_at > v_run_at - interval '3 days';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'leader_nudge_due', v_leader_due,
    'leader_notifs_inserted', v_leader_notifs,
    'gp_fallback_due', v_gp_due,
    'gp_notifs_inserted', v_gp_notifs,
    'run_at', v_run_at
  );
END;
$function$;

-- Cron-only detector: revoke the implicit PUBLIC EXECUTE bit (runs as the cron owner).
REVOKE ALL ON FUNCTION public.process_tribe_request_nudges(boolean) FROM PUBLIC;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Schedule the nudge cron (15 min after the hourly expire cron at :00, so a request that expires
--    this hour is picked up for the GP fallback in the same hour).
-- ─────────────────────────────────────────────────────────────────────────────
DO $cron$
BEGIN
  PERFORM cron.unschedule('tribe-request-nudge-hourly');
EXCEPTION WHEN OTHERS THEN
  NULL;  -- job did not exist yet
END $cron$;

SELECT cron.schedule('tribe-request-nudge-hourly', '15 * * * *', 'SELECT public.process_tribe_request_nudges();');
