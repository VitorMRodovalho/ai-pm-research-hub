-- ARM-9 Features G2: re-engagement pipeline (staged → invited → declined/accepted)
-- Auto-stages alumni com return_interest=true quando new cycle vira is_current=true
-- Admin curates list + sends invite. Alumni responds. Admin can cancel.

-- ============================================================
-- Step 1: ENUM type for state machine
-- ============================================================
DO $$ BEGIN
  CREATE TYPE public.re_engagement_state AS ENUM ('staged','invited','declined','accepted','cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- Step 2: Pipeline table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.re_engagement_pipeline (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  cycle_code text NOT NULL REFERENCES public.cycles(cycle_code),
  state public.re_engagement_state NOT NULL DEFAULT 'staged',

  staged_at timestamptz NOT NULL DEFAULT now(),
  staged_by uuid REFERENCES public.members(id),
  staged_source text NOT NULL CHECK (staged_source IN ('cron_new_cycle','manual_admin')),
  return_interest_snapshot boolean,
  reason_category_snapshot text,

  invited_at timestamptz,
  invited_by uuid REFERENCES public.members(id),
  invitation_message text,

  responded_at timestamptz,
  response text CHECK (response IN ('accepted','declined') OR response IS NULL),
  response_note text,

  cancelled_at timestamptz,
  cancelled_by uuid REFERENCES public.members(id),
  cancellation_reason text,

  metadata jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT re_engagement_state_consistency CHECK (
    (state = 'staged'    AND invited_at IS NULL     AND responded_at IS NULL  AND cancelled_at IS NULL) OR
    (state = 'invited'   AND invited_at IS NOT NULL AND responded_at IS NULL  AND cancelled_at IS NULL) OR
    (state = 'accepted'  AND invited_at IS NOT NULL AND responded_at IS NOT NULL AND response = 'accepted'  AND cancelled_at IS NULL) OR
    (state = 'declined'  AND invited_at IS NOT NULL AND responded_at IS NOT NULL AND response = 'declined'  AND cancelled_at IS NULL) OR
    (state = 'cancelled' AND cancelled_at IS NOT NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_re_engagement_active_per_member_cycle
  ON public.re_engagement_pipeline (member_id, cycle_code)
  WHERE state IN ('staged','invited','accepted');

CREATE INDEX IF NOT EXISTS idx_re_engagement_state ON public.re_engagement_pipeline(state);
CREATE INDEX IF NOT EXISTS idx_re_engagement_member ON public.re_engagement_pipeline(member_id);
CREATE INDEX IF NOT EXISTS idx_re_engagement_cycle ON public.re_engagement_pipeline(cycle_code);

CREATE OR REPLACE FUNCTION public._re_engagement_set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS trg_re_engagement_set_updated_at ON public.re_engagement_pipeline;
CREATE TRIGGER trg_re_engagement_set_updated_at
  BEFORE UPDATE ON public.re_engagement_pipeline
  FOR EACH ROW EXECUTE FUNCTION public._re_engagement_set_updated_at();

ALTER TABLE public.re_engagement_pipeline ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rpc_only_deny_all ON public.re_engagement_pipeline;
CREATE POLICY rpc_only_deny_all ON public.re_engagement_pipeline
  AS RESTRICTIVE FOR ALL TO public USING (false) WITH CHECK (false);

REVOKE ALL ON public.re_engagement_pipeline FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.re_engagement_pipeline TO service_role;

COMMENT ON TABLE public.re_engagement_pipeline IS
'ARM-9 Features G2. Staged pipeline para re-convidar alumni com return_interest=true em ciclo novo. RPC-only (RLS deny all). State machine: staged → invited → accepted|declined; admin pode cancelar em qualquer ponto pré-resposta.';

-- ============================================================
-- Step 3-7: RPCs (stage, list, invite, respond, cancel)
-- ============================================================
CREATE OR REPLACE FUNCTION public.stage_alumni_for_re_engagement(
  p_member_id uuid, p_cycle_code text, p_source text DEFAULT 'manual_admin'
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE
  v_caller record; v_member record; v_record record; v_pipeline_id uuid;
BEGIN
  IF p_source NOT IN ('cron_new_cycle','manual_admin') THEN
    RETURN jsonb_build_object('error','Invalid source: ' || p_source);
  END IF;
  IF p_source <> 'cron_new_cycle' THEN
    SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
    IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
    IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
      RETURN jsonb_build_object('error','Unauthorized: requires manage_member permission');
    END IF;
  END IF;
  SELECT * INTO v_member FROM public.members WHERE id = p_member_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Member not found'); END IF;
  IF v_member.member_status <> 'alumni' THEN
    RETURN jsonb_build_object('error','Member is not alumni (status: ' || COALESCE(v_member.member_status,'NULL') || ')');
  END IF;
  IF v_member.anonymized_at IS NOT NULL THEN
    RETURN jsonb_build_object('error','Cannot stage anonymized member (LGPD Art. 16 II)');
  END IF;
  SELECT return_interest, reason_category_code INTO v_record
  FROM public.member_offboarding_records WHERE member_id = p_member_id
  ORDER BY offboarded_at DESC LIMIT 1;
  SELECT id INTO v_pipeline_id
  FROM public.re_engagement_pipeline
  WHERE member_id = p_member_id AND cycle_code = p_cycle_code AND state IN ('staged','invited','accepted')
  LIMIT 1;
  IF v_pipeline_id IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'pipeline_id', v_pipeline_id, 'idempotent', true);
  END IF;
  INSERT INTO public.re_engagement_pipeline (
    member_id, cycle_code, state, staged_by, staged_source,
    return_interest_snapshot, reason_category_snapshot
  ) VALUES (
    p_member_id, p_cycle_code, 'staged',
    CASE WHEN p_source = 'cron_new_cycle' THEN NULL ELSE v_caller.id END,
    p_source, v_record.return_interest, v_record.reason_category_code
  ) RETURNING id INTO v_pipeline_id;
  RETURN jsonb_build_object(
    'success', true, 'pipeline_id', v_pipeline_id, 'member_name', v_member.name,
    'return_interest', v_record.return_interest, 'reason_category', v_record.reason_category_code
  );
END $$;
REVOKE ALL ON FUNCTION public.stage_alumni_for_re_engagement(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.stage_alumni_for_re_engagement(uuid, text, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.list_re_engagement_pipeline(
  p_state text DEFAULT NULL, p_cycle_code text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE v_caller record; v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
    RETURN jsonb_build_object('error','Unauthorized: requires manage_member permission');
  END IF;
  SELECT jsonb_agg(jsonb_build_object(
    'pipeline_id', p.id, 'member_id', p.member_id, 'member_name', m.name,
    'member_email', m.email, 'chapter', m.chapter, 'cycle_code', p.cycle_code,
    'state', p.state, 'staged_at', p.staged_at, 'staged_source', p.staged_source,
    'staged_by_name', sb.name, 'return_interest_snapshot', p.return_interest_snapshot,
    'reason_category_snapshot', p.reason_category_snapshot, 'invited_at', p.invited_at,
    'invited_by_name', ib.name, 'invitation_message', p.invitation_message,
    'responded_at', p.responded_at, 'response', p.response, 'response_note', p.response_note,
    'cancelled_at', p.cancelled_at, 'cancelled_by_name', cb.name,
    'cancellation_reason', p.cancellation_reason
  ) ORDER BY p.staged_at DESC) INTO v_result
  FROM public.re_engagement_pipeline p
  JOIN public.members m ON m.id = p.member_id
  LEFT JOIN public.members sb ON sb.id = p.staged_by
  LEFT JOIN public.members ib ON ib.id = p.invited_by
  LEFT JOIN public.members cb ON cb.id = p.cancelled_by
  WHERE (p_state IS NULL OR p.state::text = p_state)
    AND (p_cycle_code IS NULL OR p.cycle_code = p_cycle_code);
  RETURN jsonb_build_object('items', COALESCE(v_result, '[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.list_re_engagement_pipeline(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_re_engagement_pipeline(text, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.invite_alumni_to_re_engage(
  p_pipeline_id uuid, p_message text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE v_caller record; v_pipeline record; v_member record;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
    RETURN jsonb_build_object('error','Unauthorized: requires manage_member permission');
  END IF;
  SELECT * INTO v_pipeline FROM public.re_engagement_pipeline WHERE id = p_pipeline_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Pipeline entry not found'); END IF;
  IF v_pipeline.state <> 'staged' THEN
    RETURN jsonb_build_object('error','Cannot invite from state: ' || v_pipeline.state::text);
  END IF;
  SELECT * INTO v_member FROM public.members WHERE id = v_pipeline.member_id;
  IF v_member.anonymized_at IS NOT NULL THEN
    RETURN jsonb_build_object('error','Member was anonymized — cannot invite');
  END IF;
  UPDATE public.re_engagement_pipeline SET
    state = 'invited', invited_at = now(), invited_by = v_caller.id, invitation_message = p_message
  WHERE id = p_pipeline_id;
  PERFORM public.create_notification(
    v_member.id, 're_engagement_invitation',
    'Convite para retornar ao Núcleo IA',
    COALESCE(p_message, 'Você foi convidado(a) para retornar ao Núcleo IA no ciclo ' || v_pipeline.cycle_code || '.'),
    '/me/re-engagement/' || p_pipeline_id::text,
    're_engagement_pipeline', p_pipeline_id
  );
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (v_caller.id, 're_engagement.invited', 're_engagement_pipeline', p_pipeline_id,
    jsonb_build_object('member_id', v_pipeline.member_id, 'cycle_code', v_pipeline.cycle_code),
    jsonb_strip_nulls(jsonb_build_object('message_excerpt', LEFT(p_message, 200))));
  RETURN jsonb_build_object('success', true, 'pipeline_id', p_pipeline_id, 'invited_at', now());
END $$;
REVOKE ALL ON FUNCTION public.invite_alumni_to_re_engage(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.invite_alumni_to_re_engage(uuid, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.respond_re_engagement(
  p_pipeline_id uuid, p_response text, p_note text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE v_caller record; v_pipeline record;
BEGIN
  IF p_response NOT IN ('accepted','declined') THEN
    RETURN jsonb_build_object('error','Invalid response: must be accepted or declined');
  END IF;
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  SELECT * INTO v_pipeline FROM public.re_engagement_pipeline WHERE id = p_pipeline_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Pipeline entry not found'); END IF;
  IF v_pipeline.member_id <> v_caller.id THEN
    RETURN jsonb_build_object('error','Unauthorized: only the invited member can respond');
  END IF;
  IF v_pipeline.state <> 'invited' THEN
    RETURN jsonb_build_object('error','Cannot respond from state: ' || v_pipeline.state::text);
  END IF;
  UPDATE public.re_engagement_pipeline SET
    state = p_response::public.re_engagement_state, responded_at = now(),
    response = p_response, response_note = p_note
  WHERE id = p_pipeline_id;
  INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id)
  SELECT mgr.id,
         CASE WHEN p_response = 'accepted' THEN 're_engagement_accepted' ELSE 're_engagement_declined' END,
         COALESCE(v_caller.name,'Alumni') || ' ' ||
           CASE WHEN p_response = 'accepted' THEN 'aceitou o convite de retorno' ELSE 'declinou o convite de retorno' END,
         COALESCE(p_note, NULL), '/admin/members/re-engagement',
         're_engagement_pipeline', p_pipeline_id
  FROM public.members mgr
  WHERE mgr.is_active = true AND mgr.operational_role IN ('manager','deputy_manager');
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (v_caller.id, 're_engagement.' || p_response, 're_engagement_pipeline', p_pipeline_id,
    jsonb_build_object('response', p_response, 'cycle_code', v_pipeline.cycle_code),
    jsonb_strip_nulls(jsonb_build_object('note_excerpt', LEFT(p_note, 200))));
  RETURN jsonb_build_object('success', true, 'pipeline_id', p_pipeline_id, 'response', p_response);
END $$;
REVOKE ALL ON FUNCTION public.respond_re_engagement(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.respond_re_engagement(uuid, text, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.cancel_re_engagement(
  p_pipeline_id uuid, p_reason text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE v_caller record; v_pipeline record;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
    RETURN jsonb_build_object('error','Unauthorized: requires manage_member permission');
  END IF;
  SELECT * INTO v_pipeline FROM public.re_engagement_pipeline WHERE id = p_pipeline_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Pipeline entry not found'); END IF;
  IF v_pipeline.state IN ('cancelled','accepted','declined') THEN
    RETURN jsonb_build_object('error','Cannot cancel from state: ' || v_pipeline.state::text);
  END IF;
  UPDATE public.re_engagement_pipeline SET
    state = 'cancelled', cancelled_at = now(), cancelled_by = v_caller.id, cancellation_reason = p_reason
  WHERE id = p_pipeline_id;
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (v_caller.id, 're_engagement.cancelled', 're_engagement_pipeline', p_pipeline_id,
    jsonb_build_object('member_id', v_pipeline.member_id, 'previous_state', v_pipeline.state::text),
    jsonb_strip_nulls(jsonb_build_object('reason', p_reason)));
  RETURN jsonb_build_object('success', true, 'pipeline_id', p_pipeline_id);
END $$;
REVOKE ALL ON FUNCTION public.cancel_re_engagement(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_re_engagement(uuid, text) TO authenticated, service_role;

-- ============================================================
-- Step 8: Trigger AFTER UPDATE em cycles when is_current flips false→true
-- ============================================================
CREATE OR REPLACE FUNCTION public._auto_stage_alumni_on_cycle_open()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE v_alumni record; v_count integer := 0;
BEGIN
  IF (OLD.is_current IS DISTINCT FROM NEW.is_current) AND NEW.is_current = true THEN
    FOR v_alumni IN
      SELECT DISTINCT m.id AS member_id
      FROM public.members m
      JOIN public.member_offboarding_records r ON r.member_id = m.id
      WHERE m.member_status = 'alumni' AND m.anonymized_at IS NULL AND r.return_interest = true
        AND NOT EXISTS (
          SELECT 1 FROM public.re_engagement_pipeline p
          WHERE p.member_id = m.id AND p.cycle_code = NEW.cycle_code
            AND p.state IN ('staged','invited','accepted')
        )
    LOOP
      PERFORM public.stage_alumni_for_re_engagement(v_alumni.member_id, NEW.cycle_code, 'cron_new_cycle');
      v_count := v_count + 1;
    END LOOP;
    IF v_count > 0 THEN
      INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
      VALUES (NULL, 're_engagement.auto_staged_on_cycle_open', 'cycle', NULL,
        jsonb_build_object('cycle_code', NEW.cycle_code, 'staged_count', v_count),
        jsonb_build_object('source', 'trg_auto_stage_alumni_on_cycle_open'));
    END IF;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_auto_stage_alumni_on_cycle_open ON public.cycles;
CREATE TRIGGER trg_auto_stage_alumni_on_cycle_open
  AFTER UPDATE ON public.cycles
  FOR EACH ROW EXECUTE FUNCTION public._auto_stage_alumni_on_cycle_open();

NOTIFY pgrst, 'reload schema';
