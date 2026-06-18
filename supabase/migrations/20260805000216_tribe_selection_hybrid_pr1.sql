-- Tribe Selection Híbrida — PR1 (DB core). See docs/specs/SPEC_TRIBE_SELECTION_HYBRID.md.
-- Council: data-architect (GO on SPEC) + security-engineer + code-reviewer (this PR).
--
-- PROBLEM (grounded live 2026-06-18): tribe selection was a one-shot batch event (deadline
-- home_schedule.selection_deadline_at=2026-03-09, closed 101 days). select_tribe blocks all
-- post-deadline selection except manage_platform. Live cohort needing a tribe ≈ 0 today
-- (25/26 active researchers already have one), but the STRUCTURAL gap is the CONTINUOUS flow:
-- when the 27 guests are promoted to researcher and sign the volunteer term (#625/Épico D),
-- they have NO self-service path into a tribe. This PR builds that path on the V4-native
-- initiative/engagement axis (the 8 tribes ARE initiatives kind='research_tribe'; ADR-0005),
-- reusing the request_to_join_initiative / review_initiative_request pattern.
--
-- DECISIONS (PM, this session): hybrid — researcher requests -> tribe leader confirms (GP override).
--
-- THREE GAPS CLOSED:
--   (1) tribes are join_policy='invite_only' -> request_to_join_initiative refuses them. Dedicated
--       RPC request_tribe_assignment operates directly on initiative_invitations (NOT changing
--       join_policy — that would open the legacy batch flow too).
--   (2) leader authority: tribe leader is engagement volunteer/leader; role='leader' is NOT in
--       review_initiative_request's owner/coordinator gate, and volunteer/leader has no
--       manage_member (GP-only, LGPD Art.18 — seeding it is forbidden). Caminho-3 INLINE-scope in a
--       dedicated wrapper review_tribe_request (can_by_member_for_initiative does not exist;
--       confirmed live). The shared review_initiative_request gate is NOT touched (blast radius:
--       workgroup/committee/study_group). No seed in engagement_kind_permissions.
--   (3) engagement->members.tribe_id bridge does not exist (sync_tribe_from_initiative keys on
--       members.initiative_id, not engagements). New AFTER trigger on engagements (4.1) with a
--       mandatory demotion branch.
--
-- count_tribe_slots ALREADY reads members.tribe_id (verified live) -> the bridge trigger keeps the
-- slot count correct with no extra work; the SPEC's "migrate count_tribe_slots" item was dropped.
--
-- INVARIANTS (baseline measured live 2026-06-18, both 0):
--   AG_tribe_engagement_has_tribe_id   : every active volunteer engagement in a research_tribe must
--                                        have member.tribe_id = initiative.legacy_tribe_id (bridge correctness).
--   AH_research_tribe_single_active_engagement : a person has at most one active volunteer engagement
--                                        across research_tribe initiatives (the bridge's single-tribe_id
--                                        assumption + the demotion branch depend on this).
--   NOTE (deviation from SPEC §4.4, surfaced to council): the SPEC's second invariant
--   I_research_tribe_no_dual_pending (pending invitation vs divergent tribe_selections) was REPLACED
--   by AH. Reasons, both grounded live: (a) the pending-vs-tribe_selections formulation FALSE-POSITIVES
--   on a legitimate tribe-move (a researcher with an old batch tribe_selections row requesting a
--   different tribe is in-flight state, not drift); (b) the committed-divergence variant (active eng vs
--   tribe_selections pointing elsewhere) is already NON-zero today (1 pre-existing legacy
--   tribe_selections staleness, BELOW the bridge since AG=0 — consistent with this PR freezing
--   tribe_selections rather than reconciling it). AH is 0-clean today and directly protects the
--   trigger's core assumption, which AG alone does not.
--
-- ROLLBACK:
--   DROP TRIGGER IF EXISTS trg_sync_tribe_id_from_engagement ON public.engagements;
--   DROP FUNCTION IF EXISTS public._sync_tribe_id_from_engagement();
--   DROP FUNCTION IF EXISTS public.request_tribe_assignment(integer, text);
--   DROP FUNCTION IF EXISTS public.review_tribe_request(uuid, text, text);
--   COMMENT ON TABLE public.tribe_selections IS NULL;  -- (or the prior comment, if any)
--   -- re-apply 20260805000210's check_schema_invariants() body (without AG/AH).
--   NOTIFY pgrst, 'reload schema';

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Bridge trigger: engagements -> members.tribe_id (admission + demotion).
--    search_path='' (public.-qualified). No inline comment in the body (Phase C captures
--    prosrc verbatim — #766/D4-D5 sediment). Does NOT write engagements/tribe_selections (no loop).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._sync_tribe_id_from_engagement()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE
  v_legacy_tribe_id integer;
  v_member_id uuid;
BEGIN
  SELECT i.legacy_tribe_id INTO v_legacy_tribe_id
  FROM public.initiatives i
  WHERE i.id = NEW.initiative_id AND i.kind = 'research_tribe';

  IF v_legacy_tribe_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT m.id INTO v_member_id
  FROM public.members m
  WHERE m.person_id = NEW.person_id;

  IF v_member_id IS NULL THEN
    RETURN NULL;
  END IF;

  IF NEW.status = 'active' THEN
    UPDATE public.members
       SET tribe_id = v_legacy_tribe_id
     WHERE id = v_member_id
       AND tribe_id IS DISTINCT FROM v_legacy_tribe_id;
    RETURN NULL;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.status = 'active' AND NEW.status <> 'active' THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.engagements e2
      JOIN public.initiatives i2 ON i2.id = e2.initiative_id AND i2.kind = 'research_tribe'
      WHERE e2.person_id = NEW.person_id
        AND e2.kind = 'volunteer'
        AND e2.status = 'active'
        AND e2.id <> NEW.id
    ) THEN
      UPDATE public.members
         SET tribe_id = NULL
       WHERE id = v_member_id
         AND tribe_id IS NOT NULL;
    END IF;
  END IF;

  RETURN NULL;
END; $fn$;
REVOKE ALL ON FUNCTION public._sync_tribe_id_from_engagement() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_sync_tribe_id_from_engagement ON public.engagements;
CREATE TRIGGER trg_sync_tribe_id_from_engagement
  AFTER INSERT OR UPDATE OF status, kind ON public.engagements
  FOR EACH ROW
  WHEN (NEW.kind = 'volunteer')
  EXECUTE FUNCTION public._sync_tribe_id_from_engagement();

COMMENT ON FUNCTION public._sync_tribe_id_from_engagement() IS
  'Tribe Selection Híbrida PR1: bridges an active volunteer engagement in a research_tribe initiative to members.tribe_id (admission), and zeroes members.tribe_id on demotion (active -> non-active) ONLY when no other active research_tribe volunteer engagement remains for the person. AFTER INSERT OR UPDATE OF status,kind on engagements; WHEN (NEW.kind=volunteer). count_tribe_slots reads members.tribe_id, so the slot count follows automatically. See mig 20260805000216 / SPEC_TRIBE_SELECTION_HYBRID.md.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. request_tribe_assignment — researcher self-requests a tribe (continuous flow).
--    Volunteer-term gate identical to select_tribe (member_is_pre_onboarding, fail-closed on
--    NULL person). Inserts a self-invitation (invitee==inviter) on initiative_invitations and
--    notifies the tribe leader(s).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.request_tribe_assignment(p_tribe_id integer, p_message text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
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

  INSERT INTO public.initiative_invitations
    (initiative_id, invitee_member_id, inviter_member_id, kind_scope, message)
  VALUES
    (v_initiative.id, v_member_id, v_member_id, 'volunteer', p_message)
  RETURNING id INTO v_invitation_id;

  -- notify the tribe leader(s) — no PII in the body (LGPD minimisation)
  INSERT INTO public.notifications
    (recipient_id, type, title, body, link, source_type, source_id, actor_id, delivery_mode)
  SELECT m2.id, 'tribe_request',
         'Novo pedido de entrada na tribo',
         'Um pesquisador pediu para entrar na tribo ' || v_initiative.title || '. Revise em /tribe/' || p_tribe_id::text || '.',
         '/tribe/' || p_tribe_id::text,
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
    'expires_at', (now() + interval '72 hours'),
    'note', 'O líder da tribo vai revisar seu pedido. Acompanhe por list_my_initiative_invitations.'
  );
END;
$function$;
-- Grant hygiene: authenticated-only. The body is fail-closed on auth.uid() regardless, but this
-- closes the anon surface. NOTE: Supabase's ALTER DEFAULT PRIVILEGES grants EXECUTE to anon
-- EXPLICITLY (not via PUBLIC), so an explicit REVOKE FROM anon is required — REVOKE FROM PUBLIC
-- alone leaves anon reachable (verified live; that is why select_tribe et al stay anon-reachable).
REVOKE ALL ON FUNCTION public.request_tribe_assignment(integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_tribe_assignment(integer, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. review_tribe_request — tribe leader (or GP) approves/declines a tribe request.
--    Authority (Caminho-3 inline-scope): can_by_member(manage_member) OR active volunteer/leader
--    engagement in THIS tribe's initiative. Restricted to research_tribe invitations. On approve,
--    inserts an engagement (which fires the bridge trigger -> sets members.tribe_id).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.review_tribe_request(p_invitation_id uuid, p_decision text, p_note text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
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
$function$;
REVOKE ALL ON FUNCTION public.review_tribe_request(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.review_tribe_request(uuid, text, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Legacy marker — tribe_selections is frozen (deadline closed). Formal deprecation = future ADR.
-- ─────────────────────────────────────────────────────────────────────────────
COMMENT ON TABLE public.tribe_selections IS
  'LEGACY (frozen): one-shot batch tribe selection (deadline home_schedule.selection_deadline_at=2026-03-09, closed). The continuous post-promotion flow lives on the initiative/engagement axis (request_tribe_assignment / review_tribe_request -> engagements -> members.tribe_id via trg_sync_tribe_id_from_engagement; mig 20260805000216). Still a write path for members.tribe_id via the legacy select_tribe/sync trigger; do NOT drop without a deprecation ADR. See SPEC_TRIBE_SELECTION_HYBRID.md.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. check_schema_invariants() with AG + AH appended (33 -> 35). Body below is reproduced verbatim
--    from 20260805000210 (33 invariants, byte-equal) with the two RETURN QUERY blocks added before
--    END. The whole CREATE OR REPLACE is applied to live so file body == live prosrc (Phase C gate).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.check_schema_invariants()
 RETURNS TABLE(invariant_name text, description text, severity text, violation_count integer, sample_ids uuid[])
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NULL
     AND current_setting('role', true) NOT IN ('service_role', 'postgres')
     AND current_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Unauthorized: check_schema_invariants requires authentication';
  END IF;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status = 'alumni' AND operational_role IS DISTINCT FROM 'alumni'
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'A1_alumni_role_consistency'::text,
         'member_status=alumni must coerce operational_role=alumni (B7 trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status = 'observer' AND operational_role NOT IN ('observer','guest','none')
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'A2_observer_role_consistency'::text,
         'member_status=observer must coerce operational_role IN (observer,guest,none) (B7 trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH computed AS (
    SELECT m.id AS member_id,
      CASE
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'manager')        THEN 'manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'co_gp')          THEN 'manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'deputy_manager') THEN 'deputy_manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role IN ('leader','comms_leader')) THEN 'tribe_leader'
        WHEN bool_or(
          (ae.kind = 'volunteer' AND ae.role IN ('researcher','facilitator','communicator','curator'))
          OR (ae.kind IN ('committee_member','workgroup_member','study_group_owner')
              AND ae.role IN ('leader','co_leader','owner','coordinator','researcher','contributor','member','participant'))
          OR (ae.kind IN ('committee_coordinator','workgroup_coordinator')
              AND ae.role IN ('leader','co_leader','owner','coordinator'))
        ) THEN 'researcher'
        WHEN bool_or(ae.kind = 'external_signer') THEN 'external_signer'
        WHEN bool_or(ae.kind = 'observer') THEN 'observer'
        WHEN bool_or(ae.kind = 'alumni') THEN 'alumni'
        WHEN bool_or(ae.kind = 'sponsor') THEN 'sponsor'
        WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
        WHEN bool_or(ae.kind = 'candidate') THEN 'candidate'
        ELSE 'guest'
      END AS expected_role
    FROM public.members m
    LEFT JOIN public.auth_engagements ae ON ae.person_id = m.person_id AND ae.is_authoritative = true
    WHERE m.member_status='active' AND m.name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND m.name NOT LIKE '%_synthetic%'
    GROUP BY m.id
  ),
  drift AS (
    SELECT c.member_id FROM computed c
    JOIN public.members m ON m.id = c.member_id
    WHERE m.operational_role IS DISTINCT FROM c.expected_role
  )
  SELECT 'A3_active_role_engagement_derivation'::text,
         'active member operational_role must equal priority-ladder derivation from active engagements (cache trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE ((member_status='active' AND is_active=false) OR (member_status IN ('observer','alumni','inactive') AND is_active=true))
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'B_is_active_status_mismatch'::text,
         'members.is_active must match member_status mapping (active=true, terminal=false)'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive') AND designations IS NOT NULL AND array_length(designations,1)>0
  )
  SELECT 'C_designations_in_terminal_status'::text,
         'members.designations must be empty when member_status is observer/alumni/inactive'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    JOIN public.persons p ON p.id = m.person_id
    WHERE m.auth_id IS NOT NULL AND p.auth_id IS NOT NULL AND m.auth_id IS DISTINCT FROM p.auth_id
  )
  SELECT 'D_auth_id_mismatch_person_member'::text,
         'persons.auth_id and members.auth_id must agree when both are set (ghost resolution sync)'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT ae.engagement_id AS e_id FROM public.auth_engagements ae
    JOIN public.members m ON m.person_id = ae.person_id
    WHERE ae.status='active' AND m.member_status IN ('observer','alumni','inactive')
      AND ae.kind NOT IN ('observer','alumni','external_signer','sponsor','chapter_board','partner_contact')
  )
  SELECT 'E_engagement_active_with_terminal_member'::text,
         'engagement.status=active is inconsistent with member.member_status in (observer/alumni/inactive) unless kind matches'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(e_id ORDER BY e_id) FROM (SELECT e_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT i.id AS initiative_id FROM public.initiatives i
    WHERE i.legacy_tribe_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.tribes t WHERE t.id = i.legacy_tribe_id)
  )
  SELECT 'F_initiative_legacy_tribe_orphan'::text,
         'initiatives.legacy_tribe_id must point to an existing tribe (bridge integrity)'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(initiative_id ORDER BY initiative_id) FROM (SELECT initiative_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    LEFT JOIN public.document_versions dv ON dv.id = gd.current_version_id
    WHERE gd.current_version_id IS NOT NULL
      AND (dv.id IS NULL OR dv.locked_at IS NULL)
      AND NOT EXISTS (
        SELECT 1 FROM public.approval_chains ac
        WHERE ac.document_id = gd.id
          AND ac.status IN ('review','approved','activated')
          AND ac.closed_at IS NULL
      )
  )
  SELECT 'J_current_version_published'::text,
         'governance_documents.current_version_id must point to a document_versions row with locked_at IS NOT NULL — unless an open approval_chain (review/approved/activated, closed_at NULL) is in flight that will lock the version on close (Phase IP-1, chain-aware).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    WHERE m.operational_role='external_signer'
      AND NOT EXISTS (
        SELECT 1 FROM public.auth_engagements ae
        WHERE ae.person_id=m.person_id AND ae.kind='external_signer' AND ae.status='active' AND ae.is_authoritative=true
      )
  )
  SELECT 'K_external_signer_integrity'::text,
         'members.operational_role=external_signer must have an active auth_engagements row with kind=external_signer (Phase IP-1).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    WHERE m.member_status IN ('alumni','observer','inactive') AND m.anonymized_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM public.member_offboarding_records r WHERE r.member_id=m.id)
  )
  SELECT 'L_offboarding_record_present'::text,
         'members in alumni/observer/inactive (not anonymized) must have a member_offboarding_records row (#91 G3 trigger).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH expected AS (
    SELECT a.id AS application_id, a.research_score AS cached,
      CASE
        WHEN e.obj_avg IS NOT NULL AND e.int_avg IS NOT NULL THEN round(e.obj_avg + e.int_avg, 2)
        WHEN e.obj_avg IS NOT NULL THEN round(e.obj_avg, 2)
        ELSE NULL
      END AS expected
    FROM public.selection_applications a
    CROSS JOIN LATERAL (
      SELECT AVG(weighted_subtotal) FILTER (WHERE evaluation_type='objective' AND submitted_at IS NOT NULL) AS obj_avg,
        AVG(weighted_subtotal) FILTER (WHERE evaluation_type='interview' AND submitted_at IS NOT NULL) AS int_avg
      FROM public.selection_evaluations WHERE application_id=a.id
    ) e
  ),
  drift AS (
    SELECT application_id FROM expected
    WHERE (cached IS NULL) IS DISTINCT FROM (expected IS NULL)
       OR (cached IS NOT NULL AND expected IS NOT NULL AND ABS(cached - expected) > 0.01)
  )
  SELECT 'M_application_score_consistency'::text,
         'selection_applications.research_score must equal compute_application_scores(application_id) derivation (sync trigger trg_recompute_application_scores).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(application_id ORDER BY application_id) FROM (SELECT application_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive')
      AND offboarded_at IS NULL AND anonymized_at IS NULL
      AND name <> 'VP Desenvolvimento Profissional (PMI-GO)'
  )
  SELECT 'N_terminal_status_offboarded_at_present'::text,
         'members in alumni/observer/inactive (not anonymized) must have offboarded_at NOT NULL (ARM-9 G6 defense-in-depth complement to L).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT ma.id AS artifact_id FROM public.meeting_artifacts ma
    WHERE ma.event_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.events e WHERE e.id = ma.event_id)
  )
  SELECT 'O_meeting_artifact_event_orphan'::text,
         'meeting_artifacts.event_id must point to an existing event when not NULL (FK defense).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(artifact_id ORDER BY artifact_id) FROM (SELECT artifact_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  SELECT 'P_tribe_initiative_bridge_complete'::text,
         'tribes.is_active=true must have at least one initiative.legacy_tribe_id pointing to it (V3-V4 bridge; cron leader digest depends).'::text,
         'medium'::text,
         (SELECT COUNT(*)::integer FROM public.tribes t
          WHERE t.is_active = true
            AND NOT EXISTS (SELECT 1 FROM public.initiatives i WHERE i.legacy_tribe_id = t.id)),
         NULL::uuid[];

  RETURN QUERY
  WITH drift AS (
    SELECT id AS engagement_id FROM public.engagements
    WHERE status = 'expired' AND end_date > CURRENT_DATE
  )
  SELECT 'Q_expired_engagement_end_date'::text,
         'engagements.status=expired requires end_date <= CURRENT_DATE (impossible to be expired in the future; VEP service_latest_end_date is source of truth).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(engagement_id ORDER BY engagement_id) FROM (SELECT engagement_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT a.id AS application_id
    FROM public.selection_applications a
    WHERE a.status = 'approved'
      AND a.email IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.members m WHERE lower(m.email) = lower(a.email)
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.member_emails me WHERE lower(me.email) = lower(a.email)
      )
  )
  SELECT 'R_approved_application_has_member'::text,
         'selection_applications.status=approved must have a matching members row by lower(email). Bypass of approve_selection_application() canonical RPC creates this drift (Issue #180).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(application_id ORDER BY application_id) FROM (SELECT application_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT DISTINCT m.id AS member_id
    FROM public.selection_applications a
    JOIN public.members m ON lower(m.email) = lower(a.email)
    WHERE a.status = 'approved' AND m.person_id IS NULL
  )
  SELECT 'S_approved_member_has_person_id'::text,
         'members tied to an approved selection_applications row must have person_id NOT NULL (V4 graph anchor for engagements). Issue #180.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH primary_email_counts AS (
    SELECT m.id AS member_id,
           COUNT(me.id) FILTER (WHERE me.is_primary = true) AS primary_count
    FROM public.members m
    LEFT JOIN public.member_emails me ON me.member_id = m.id
    WHERE m.name NOT LIKE '%_synthetic%'
    GROUP BY m.id
  ),
  drift AS (
    SELECT member_id FROM primary_email_counts
    WHERE primary_count <> 1
  )
  SELECT 'T_member_has_exactly_one_primary_email'::text,
         'Every member must have exactly one primary email in member_emails (Issue #205).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    WHERE gd.status = 'pending_proposer_consent'
      AND EXISTS (
        SELECT 1 FROM public.approval_chains ac
        WHERE ac.document_id = gd.id
          AND ac.status NOT IN ('withdrawn','superseded')
      )
  )
  SELECT 'V_prime_pending_proposer_consent_no_open_chain'::text,
         'status=pending_proposer_consent must not have non-cancelled approval_chains rows (#315 P0-Q7 + Amendment A2 — pending_proposer_consent precedes any chain).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    WHERE gd.status IN ('approved','active')
      AND gd.current_ratified_chain_id IS NULL
  )
  SELECT 'V_status_chain_coherence'::text,
         'governance_documents with status approved/active must have current_ratified_chain_id NOT NULL (#315 P0-Q6 + #367 Wave 1b first leaf). NO carve-out: 7 legacy pre-chain docs backfilled with PM-designated synthetic chains via migration 20260805000038 (acknowledge signoffs, metadata.legacy_migration=true, role=migration_attestation).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT cp.id AS product_id
    FROM public.content_products cp
    WHERE
      CASE cp.source_kind
        WHEN 'governance_document_version' THEN
          NOT (cp.source_document_version_id IS NOT NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_publication_idea_id IS NULL
               AND cp.source_external_uri IS NULL)
        WHEN 'board_item' THEN
          NOT (cp.source_board_item_id IS NOT NULL
               AND cp.source_document_version_id IS NULL
               AND cp.source_publication_idea_id IS NULL
               AND cp.source_external_uri IS NULL)
        WHEN 'publication_idea' THEN
          NOT (cp.source_publication_idea_id IS NOT NULL
               AND cp.source_document_version_id IS NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_external_uri IS NULL)
        WHEN 'external' THEN
          NOT (cp.source_external_uri IS NOT NULL
               AND cp.source_document_version_id IS NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_publication_idea_id IS NULL)
        WHEN 'none' THEN
          NOT (cp.source_document_version_id IS NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_publication_idea_id IS NULL
               AND cp.source_external_uri IS NULL)
        ELSE TRUE
      END
  )
  SELECT 'W_content_product_source_integrity'::text,
         'content_products row must satisfy chk_content_products_source_integrity CHECK semantics (exactly one source FK populated per source_kind; ADR-0099 §2.2 + §6 step 9). Defense-in-depth complement to the CHECK constraint; mirrors V/V''/T pattern.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(product_id ORDER BY product_id) FROM (SELECT product_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT p.id AS parecer_id
    FROM public.blind_review_pareceres p
    WHERE NOT EXISTS (
      SELECT 1 FROM public.blind_review_assignments a
      WHERE a.session_id = p.session_id
        AND a.reviewer_member_id = p.reviewer_member_id
        AND a.status = 'active'
    )
  )
  SELECT 'X_blind_review_pareceres_session_product_match'::text,
         'blind_review_pareceres.reviewer_member_id must have an active blind_review_assignments row in the same session (assignment-parecer integrity; ADR-0099 §2.7 + §7 step 11). Defense-in-depth complement to FK constraints; catches drift if assignment is withdrawn while parecer remains. #382 PR-B.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(parecer_id ORDER BY parecer_id) FROM (SELECT parecer_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH pe AS (
    SELECT name AS k FROM public.partner_entities
    WHERE entity_type = 'pmi_chapter' AND status = 'active' AND NOT COALESCE(is_international, false)
  ),
  ch AS (
    SELECT 'PMI-' || code AS k FROM public.chapters WHERE status = 'active'
  ),
  drift AS (
    SELECT k FROM pe WHERE k NOT IN (SELECT k FROM ch)
    UNION ALL
    SELECT k FROM ch WHERE k NOT IN (SELECT k FROM pe)
  )
  SELECT 'Y_chapter_pipeline_parity'::text,
         'every active domestic pmi_chapter in partner_entities must have a matching active chapters row (by name = ''PMI-'' || chapters.code) and vice-versa — MEMBERSHIP parity (not just count), so it catches single-table inserts/archives even when row counts coincide. Drift = get_chapter_metrics()->>signed forks from the V4 chapters table (#481).'::text,
         'medium'::text,
         (SELECT COUNT(*)::integer FROM drift),
         NULL::uuid[];

  RETURN QUERY
  WITH drift AS (
    SELECT id AS webinar_id FROM public.webinars
    WHERE status IS NULL OR status NOT IN ('planned','confirmed','completed','cancelled')
  )
  SELECT 'Z_webinar_status_domain'::text,
         'webinars.status must be within planned|confirmed|completed|cancelled (the realized=completed canonical definition depends on it; defense-in-depth complement to webinars_status_check — #479/#481).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(webinar_id ORDER BY webinar_id) FROM (SELECT webinar_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive') AND current_cycle_active = true
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'B2_current_cycle_active_terminal_status'::text,
         'members in observer/alumni/inactive must have current_cycle_active=false (#483 sync_member_status_consistency B-trigger; CCA gates the get_gamification_leaderboard/get_public_leaderboard cohort).'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- U (ADR-0104 Wave 3b-ii): members.chapter is now derived as
  -- COALESCE('PMI-'||entry_chapter_code, 'PMI-'||primary affiliation code, legacy chapter).
  -- For the derivation to be deterministic for registry-chaptered active members, each must have
  -- exactly one is_primary=true affiliation. The partial unique index enforces AT MOST one; this
  -- enforces EXACTLY one. Non-registry chapters (Outro/Externo) are excluded — legitimately
  -- unaffiliated, derivation falls through to the legacy value.
  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id
    FROM public.members m
    WHERE m.member_status = 'active'
      AND m.person_id IS NOT NULL
      AND m.name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND m.name NOT LIKE '%_synthetic%'
      AND replace(m.chapter, 'PMI-', '') IN (SELECT chapter_code FROM public.chapter_registry)
      AND NOT (m.operational_role = 'guest' AND m.entry_chapter_code IS NULL)
      AND (SELECT COUNT(*) FROM public.member_chapter_affiliations a
            WHERE a.person_id = m.person_id AND a.is_primary) <> 1
  )
  SELECT 'U_active_person_has_primary_chapter_affiliation'::text,
         'every active registry-chaptered member''s person_id must have exactly one is_primary=true member_chapter_affiliations row, else the members.chapter COALESCE(entry, primary, legacy) derivation breaks silently (ADR-0104 Wave 3b-ii). Excluded: operational_role=''guest'' AND entry_chapter_code IS NULL (pre-onboarding, entry-chapter choice not yet made — affiliation is seeded by set_my_entry_chapter, Wave 3b-i; until then the COALESCE falls through to the legacy default). Non-registry chapters (Outro/Externo) excluded — legitimately unaffiliated.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- AA (#766; the discovery dubbed this "invariant T", but T and U are already taken):
  -- the cert-side AFTER trigger (_trg_complete_volunteer_term_on_cert on certificates) and the
  -- seed-side BEFORE guard (_trg_complete_volunteer_term_on_seed on onboarding_progress) together
  -- guarantee that a member holding an issued volunteer_agreement certificate has their
  -- 'volunteer_term' onboarding step marked completed. This invariant codifies that guarantee.
  -- Directional: no volunteer_term row, or a completed step without an issued cert (all certs
  -- rejected/superseded), is NOT a violation.
  RETURN QUERY
  WITH drift AS (
    SELECT op.member_id
    FROM public.onboarding_progress op
    WHERE op.step_key = 'volunteer_term'
      AND op.status <> 'completed'
      AND op.member_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.certificates c
        WHERE c.member_id = op.member_id
          AND c.type = 'volunteer_agreement'
          AND c.status = 'issued'
      )
  )
  SELECT 'AA_volunteer_term_complete_when_cert_issued'::text,
         'a member holding an issued volunteer_agreement certificate must have their volunteer_term onboarding_progress step at status=completed. Guaranteed by the cert-side AFTER trigger (_trg_complete_volunteer_term_on_cert on certificates) plus the seed-side BEFORE guard (_trg_complete_volunteer_term_on_seed on onboarding_progress), p233 / issue #766. A non-completed step alongside an issued cert means a trigger was bypassed (service_role direct INSERT, or a cert backfill that did not fire the AFTER trigger). Directional: a member with no volunteer_term row, or a completed step without an issued cert (all certs rejected or superseded), is NOT a violation.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;
  -- AB (#766 PR2): a term_signed milestone must have a volunteer_agreement certificate
  -- of ANY status (issued/rejected/superseded) for the same member. Wave-3c-safe: the
  -- milestone persists after a cert is rejected or superseded because the member did
  -- sign once; only a milestone with NO cert ancestry at all is a violation (fabrication
  -- or a bad backfill via service_role direct INSERT). Directional complement to AA.
  RETURN QUERY
  WITH drift AS (
    SELECT mm.member_id
    FROM public.member_milestones mm
    WHERE mm.milestone_key = 'term_signed'
      AND NOT EXISTS (
        SELECT 1 FROM public.certificates c
        WHERE c.member_id = mm.member_id
          AND c.type = 'volunteer_agreement'
      )
  )
  SELECT 'AB_term_signed_milestone_has_cert_ancestry'::text,
         'a term_signed member_milestone must have at least one volunteer_agreement certificate of any status (issued/rejected/superseded) for the same member. Wave 3c reject/reissue is valid ancestry — the milestone persists after a cert is rejected or superseded because the member did sign once. A milestone with NO cert in any state indicates fabrication or a bad backfill (service_role direct INSERT into member_milestones; source_id is informational-only without FK). #766 PR2, mig 20260805000202. Directional complement to AA.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- AC (#766 PR3): a first_attendance milestone must have at least one present=true
  -- attendance row for the member. source_id is informational-only (no FK), so a milestone
  -- with no present attendance indicates fabrication or a bad backfill (service_role direct
  -- INSERT into member_milestones). Directional, mirrors AA/AB.
  RETURN QUERY
  WITH drift AS (
    SELECT mm.member_id
    FROM public.member_milestones mm
    WHERE mm.milestone_key = 'first_attendance'
      AND NOT EXISTS (
        SELECT 1 FROM public.attendance a
        WHERE a.member_id = mm.member_id
          AND a.present = true
      )
  )
  SELECT 'AC_first_attendance_milestone_has_attendance'::text,
         'a first_attendance member_milestone must have at least one present=true attendance row for the same member. source_id is informational-only (no FK), so a milestone with no present attendance indicates fabrication or a bad backfill (service_role direct INSERT into member_milestones). #766 PR3, mig 20260805000203. Directional, mirrors AA/AB.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- AD (#766 PR3): a first_deliverable milestone must have at least one tribe_deliverable
  -- with status='completed' assigned to the member. Keyed on status='completed' (the same
  -- signal the trigger fires on, and the XP sibling trg_tribe_deliverable_completed_xp), NOT
  -- completed_at (a derived audit column). Catches a status reverted via service_role after
  -- the milestone fired, a fabricated milestone, or a bad backfill. Directional.
  RETURN QUERY
  WITH drift AS (
    SELECT mm.member_id
    FROM public.member_milestones mm
    WHERE mm.milestone_key = 'first_deliverable'
      AND NOT EXISTS (
        SELECT 1 FROM public.tribe_deliverables td
        WHERE td.assigned_member_id = mm.member_id
          AND td.status = 'completed'
      )
  )
  SELECT 'AD_first_deliverable_milestone_has_completed_deliverable'::text,
         'a first_deliverable member_milestone must have at least one tribe_deliverable with status=''completed'' assigned to the same member. Keyed on status=''completed'' (same signal as the trigger and the XP sibling trg_tribe_deliverable_completed_xp; NOT completed_at, a derived audit column). A milestone with no completed deliverable indicates fabrication, a bad backfill, or a status reverted via service_role after the milestone fired. #766 PR3, mig 20260805000203. Directional, mirrors AA/AB.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- AE (#766 PR5): a profile_complete milestone must have members.profile_completed_at set.
  -- profile_completed_at is monotonic — only update_my_profile writes it (NULL -> now() once,
  -- via CASE WHEN profile_completed_at IS NULL THEN now() ELSE profile_completed_at END) and no
  -- function ever clears it — so this directional check is false-positive-free, unlike promotion
  -- (PR4 added no invariant: operational_role is a mutable cache with routine demotion). Catches
  -- a fabricated milestone, a bad backfill, or the column cleared via a manual UPDATE after the
  -- milestone fired. Directional, mirrors AA/AB/AC/AD.
  RETURN QUERY
  WITH drift AS (
    SELECT mm.member_id
    FROM public.member_milestones mm
    WHERE mm.milestone_key = 'profile_complete'
      AND NOT EXISTS (
        SELECT 1 FROM public.members m
        WHERE m.id = mm.member_id
          AND m.profile_completed_at IS NOT NULL
      )
  )
  SELECT 'AE_profile_complete_milestone_has_profile_completed_at'::text,
         'a profile_complete member_milestone must have members.profile_completed_at set. The column is monotonic — only update_my_profile writes it (NULL -> now() once, never cleared) — so this directional check is false-positive-free, unlike promotion whose mutable operational_role cache demotes routinely (hence PR4 added no invariant). A milestone with a NULL profile_completed_at indicates fabrication, a bad backfill (service_role direct INSERT into member_milestones; source_id is informational-only without FK), or the column cleared via a manual UPDATE after the milestone fired. #766 PR5, mig 20260805000205. Directional, mirrors AA/AB/AC/AD.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  -- AF (D4/D5, mig 20260805000210): a selection_interviews row in an OPEN status (scheduled/rescheduled)
  -- must be the most-recently-created interview row for its application. An open row OLDER than another
  -- interview row of the same application means a reschedule/re-booking created a new row without closing
  -- the prior open one. Guaranteed forward by the AFTER INSERT trigger trg_supersede_prior_open_interviews
  -- (cancels older open siblings on a new open insert — the live root cause:
  -- sync_calendar_booking_to_interview / schedule_interview). KNOWN directional gap (defense-in-depth):
  -- a TERMINAL row inserted newer than an open row (only import_historical_interviews) is not superseded
  -- and would surface here; in production 'completed' is reached by UPDATE in-place
  -- (mark_interview_status/submit_interview_scores), so the live path is covered.
  RETURN QUERY
  WITH drift AS (
    SELECT si.id AS interview_id
    FROM public.selection_interviews si
    WHERE si.status IN ('scheduled','rescheduled')
      AND EXISTS (
        SELECT 1 FROM public.selection_interviews si2
        WHERE si2.application_id = si.application_id
          AND si2.created_at > si.created_at
      )
  )
  SELECT 'AF_open_interview_is_newest_row'::text,
         'a selection_interviews row in an open status (scheduled/rescheduled) must be the most-recently-created interview row for its application. An open row older than another interview row of the same application indicates a reschedule/re-booking that did not close the prior open row (bypass of the AFTER INSERT trigger trg_supersede_prior_open_interviews, or pre-fix legacy drift). Root cause: sync_calendar_booking_to_interview / schedule_interview INSERTing a new scheduled row without superseding the prior open one (D4/D5, mig 20260805000210). KNOWN directional gap (defense-in-depth): a TERMINAL row inserted newer than an open row (only import_historical_interviews) is not superseded by the trigger and would surface here; the live path reaches completed via UPDATE in-place, so it is covered.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(interview_id ORDER BY interview_id) FROM (SELECT interview_id FROM drift LIMIT 10) s)
  FROM drift;

  -- AG (Tribe Selection Híbrida PR1, mig 20260805000216): every active volunteer engagement in a
  -- research_tribe initiative must have member.tribe_id = initiative.legacy_tribe_id. This is the
  -- correctness contract of the bridge trigger trg_sync_tribe_id_from_engagement: admission sets
  -- members.tribe_id from the engagement, and count_tribe_slots reads members.tribe_id, so a divergence
  -- means the bridge was bypassed (service_role direct INSERT into engagements) or a stale tribe_id
  -- from the legacy select_tribe path conflicts with the engagement. Baseline 0 (31 active engagements).
  RETURN QUERY
  WITH drift AS (
    SELECT e.id AS engagement_id
    FROM public.engagements e
    JOIN public.initiatives i ON i.id = e.initiative_id AND i.kind = 'research_tribe'
    JOIN public.members m ON m.person_id = e.person_id
    WHERE e.kind = 'volunteer' AND e.status = 'active'
      AND m.tribe_id IS DISTINCT FROM i.legacy_tribe_id
  )
  SELECT 'AG_tribe_engagement_has_tribe_id'::text,
         'every active volunteer engagement in a research_tribe initiative must have member.tribe_id = initiative.legacy_tribe_id (the correctness contract of the bridge trigger trg_sync_tribe_id_from_engagement; count_tribe_slots reads members.tribe_id, so a divergence corrupts the slot count). A violation means the bridge was bypassed (service_role direct INSERT into engagements) or a stale legacy tribe_id conflicts with the engagement. Tribe Selection Híbrida PR1, mig 20260805000216. Baseline 0.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(engagement_id ORDER BY engagement_id) FROM (SELECT engagement_id FROM drift LIMIT 10) s)
  FROM drift;

  -- AH (Tribe Selection Híbrida PR1, mig 20260805000216): a person has at most one active volunteer
  -- engagement across research_tribe initiatives. members.tribe_id is a single scalar and the bridge
  -- trigger's demotion branch ("zero tribe_id only if no other active research_tribe engagement remains")
  -- both assume a single active tribe engagement; two would make tribe_id ambiguous and could leave a
  -- stale tribe_id after one is demoted. Supersedes the SPEC's I_research_tribe_no_dual_pending (which
  -- false-positives on a legitimate tribe-move and whose committed-divergence sibling is already
  -- non-zero from frozen legacy tribe_selections staleness). Baseline 0.
  RETURN QUERY
  WITH drift AS (
    SELECT e.person_id
    FROM public.engagements e
    JOIN public.initiatives i ON i.id = e.initiative_id AND i.kind = 'research_tribe'
    WHERE e.kind = 'volunteer' AND e.status = 'active'
    GROUP BY e.person_id
    HAVING COUNT(*) > 1
  )
  SELECT 'AH_research_tribe_single_active_engagement'::text,
         'a person must have at most one active volunteer engagement across research_tribe initiatives. members.tribe_id is a single scalar and the bridge trigger trg_sync_tribe_id_from_engagement (admission + demotion branch) assumes a single active tribe engagement; two make tribe_id ambiguous and can leave a stale tribe_id after one is demoted. Supersedes the SPEC''s I_research_tribe_no_dual_pending (which false-positives on a legitimate tribe-move and whose committed-divergence sibling is already non-zero from frozen legacy tribe_selections staleness, below the bridge since AG=0). Tribe Selection Híbrida PR1, mig 20260805000216. Baseline 0.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(person_id ORDER BY person_id) FROM (SELECT person_id FROM drift LIMIT 10) s)
  FROM drift;

END;
$function$;

NOTIFY pgrst, 'reload schema';
