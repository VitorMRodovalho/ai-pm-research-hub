-- #1139 — Tribe-journey UX hardening (pre-kickoff, DIA 9 2026-07-09).
-- The hybrid tribe flow (request_tribe_assignment / review_tribe_request, mig 20260805000216)
-- works end-to-end; the UX around it does not. Two DB-side gaps this migration closes:
--
--   Item 1 (HIGH): get_my_tribe_request_context() folds every ineligibility cause into ONE
--     `eligible` boolean, so the FE (TribeRequestBlock) can only `return null` → a BLANK block.
--     At the C4 kickoff, ~37 researchers without a signed volunteer term hit exactly this blank
--     ("parece quebrado"). We surface `ineligible_reason` (+ `current_tribe_title` for the has_tribe
--     case) so the FE can render an explicit empty-state with the reason + next step. Purely additive:
--     existing keys (eligible/pending/tribes) are unchanged, so current callers are unaffected.
--
--   Item 2 (MEDIUM): request_tribe_assignment() notifies the tribe leader with a bare `/tribe/N`
--     link, which lands on the default General tab — the pending-request queue only renders on the
--     Membros tab, so the leader "doesn't see it". Deep-link the notification to `/tribe/N?tab=members`
--     (the tab router already reads ?tab=). Body text (human-readable) left as `/tribe/N`.
--
-- Both functions are CREATE OR REPLACE (same signatures). Live prosrc verified byte-identical to the
-- 20260805000216/217 capture before reproduction (no drift). Reason order mirrors
-- request_tribe_assignment's own guard sequence (inactive → has-tribe → term) for parity.
--
-- ROLLBACK: re-apply the bodies from 20260805000216 (request_tribe_assignment) and
--           20260805000217 (get_my_tribe_request_context); NOTIFY pgrst, 'reload schema';

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. get_my_tribe_request_context — now reports WHY when ineligible (Item 1).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_my_tribe_request_context()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
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
  v_pending jsonb;
  v_tribes jsonb;
BEGIN
  SELECT m.id, m.person_id, m.member_status, m.is_active, m.tribe_id
    INTO v_member_id, v_person_id, v_member_status, v_is_active, v_tribe_id
    FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_member_id IS NULL THEN
    RETURN jsonb_build_object('eligible', false, 'ineligible_reason', 'no_member', 'current_tribe_title', NULL, 'pending', NULL, 'tribes', '[]'::jsonb);
  END IF;

  -- caller's pending research_tribe self-request (invitee == me), if any
  SELECT to_jsonb(p) INTO v_pending FROM (
    SELECT i.legacy_tribe_id AS tribe_id, i.title, ii.message, ii.created_at, ii.expires_at
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
  IF v_eligible THEN
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

  -- the current tribe title (only meaningful for the has_tribe empty-state)
  IF v_reason = 'has_tribe' THEN
    SELECT i.title INTO v_current_tribe_title
    FROM public.initiatives i
    WHERE i.kind = 'research_tribe'
      AND (
        i.legacy_tribe_id = v_tribe_id
        OR EXISTS (
          SELECT 1 FROM public.engagements e
          WHERE e.initiative_id = i.id AND e.person_id = v_person_id
            AND e.kind = 'volunteer' AND e.status = 'active'
        )
      )
    ORDER BY (i.legacy_tribe_id = v_tribe_id) DESC NULLS LAST
    LIMIT 1;
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
    'pending', v_pending,
    'tribes', v_tribes
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_my_tribe_request_context() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_tribe_request_context() TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. request_tribe_assignment — leader notification deep-links to the Membros tab (Item 2).
--    Body reproduced verbatim from 20260805000216 (live prosrc byte-verified); ONLY the notification
--    `link` column changes: '/tribe/N' → '/tribe/N?tab=members'.
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
    'expires_at', (now() + interval '72 hours'),
    'note', 'O líder da tribo vai revisar seu pedido. Acompanhe por list_my_initiative_invitations.'
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.request_tribe_assignment(integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_tribe_assignment(integer, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
