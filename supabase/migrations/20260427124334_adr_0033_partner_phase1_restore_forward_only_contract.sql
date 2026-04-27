-- ADR-0033 Phase 1 amendment (p66): restore forward-only transition contract
-- Test failure: tests/contracts/novello-partner-pipeline.test.mjs expects
-- backward_transition_blocked logic that was inadvertently dropped during
-- p66 V4 conversion (sourced from drifted live body, not from W122/W123 migration).
--
-- Root cause: live body had drift from migration 20260319100031 — the
-- captured pre-conversion body was the drift state, not the contract state.
-- Track Q-style drift surfaced via contract test guard.

CREATE OR REPLACE FUNCTION public.admin_update_partner_status(
  p_partner_id uuid,
  p_new_status text,
  p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_current_status text;
  v_current_notes text;
  v_status_order jsonb := '{"prospect":1,"contact":2,"negotiation":3,"active":4,"inactive":5,"churned":6}'::jsonb;
  v_current_rank int;
  v_new_rank int;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Auth required';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_partner') THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT status, notes INTO v_current_status, v_current_notes FROM public.partner_entities WHERE id = p_partner_id;
  IF v_current_status IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'partner_not_found');
  END IF;

  IF p_new_status NOT IN ('prospect','contact','negotiation','active','inactive','churned') THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_status');
  END IF;

  -- Forward-only check (W122/W123 contract): any status can go to inactive/churned
  -- but cannot move backward in the funnel.
  v_current_rank := (v_status_order->>v_current_status)::int;
  v_new_rank := (v_status_order->>p_new_status)::int;

  IF p_new_status NOT IN ('inactive', 'churned') AND v_new_rank <= v_current_rank THEN
    RETURN jsonb_build_object('success', false, 'error', 'backward_transition_blocked',
      'detail', 'Cannot move from ' || v_current_status || ' to ' || p_new_status);
  END IF;

  UPDATE public.partner_entities SET
    status = p_new_status,
    notes = CASE
      WHEN p_notes IS NOT NULL THEN
        COALESCE(v_current_notes || E'\n', '') || to_char(now(), 'YYYY-MM-DD') || ': [' || v_current_status || ' -> ' || p_new_status || '] ' || p_notes
      ELSE
        COALESCE(v_current_notes || E'\n', '') || to_char(now(), 'YYYY-MM-DD') || ': Status alterado de ' || v_current_status || ' para ' || p_new_status
    END,
    updated_at = now(),
    partnership_date = CASE
      WHEN p_new_status = 'active' AND partnership_date IS NULL THEN CURRENT_DATE
      ELSE partnership_date
    END
  WHERE id = p_partner_id;

  INSERT INTO public.partner_interactions (partner_id, interaction_type, summary, actor_member_id)
  VALUES (p_partner_id, 'status_change', v_current_status || ' -> ' || p_new_status, v_caller_id);

  UPDATE public.partner_entities SET last_interaction_at = now() WHERE id = p_partner_id;

  RETURN jsonb_build_object('success', true, 'old_status', v_current_status, 'new_status', p_new_status);
END;
$$;
COMMENT ON FUNCTION public.admin_update_partner_status(uuid, text, text) IS
  'Phase B'' V4 conversion (ADR-0033 Phase 1, p66): manage_partner via can_by_member + W122/W123 forward-only transition contract restored (contract drift caught by tests/contracts/novello-partner-pipeline.test.mjs). Was V3 (SA OR manager/deputy OR designations sponsor/chapter_liaison).';

NOTIFY pgrst, 'reload schema';
