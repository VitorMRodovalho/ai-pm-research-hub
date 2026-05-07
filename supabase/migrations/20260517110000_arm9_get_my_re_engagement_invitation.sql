-- p118 ARM-9 Frontend: get_my_re_engagement_invitation read RPC
-- Allows the invited alumni member to read their own pipeline entry to display
-- cycle/message/state on /me/re-engagement/[id] before responding via respond_re_engagement.
-- Authorization: caller's member.id must equal pipeline.member_id (no manage_member required).
-- Rollback: DROP FUNCTION public.get_my_re_engagement_invitation(uuid);

CREATE OR REPLACE FUNCTION public.get_my_re_engagement_invitation(p_pipeline_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller record;
  v_pipeline record;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error','Not authenticated');
  END IF;

  SELECT * INTO v_pipeline FROM public.re_engagement_pipeline WHERE id = p_pipeline_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error','Pipeline entry not found');
  END IF;

  IF v_pipeline.member_id <> v_caller.id THEN
    RETURN jsonb_build_object('error','Unauthorized: this invitation is not for you');
  END IF;

  RETURN jsonb_build_object(
    'pipeline_id', v_pipeline.id,
    'member_id', v_pipeline.member_id,
    'member_name', v_caller.name,
    'cycle_code', v_pipeline.cycle_code,
    'state', v_pipeline.state::text,
    'staged_at', v_pipeline.staged_at,
    'invited_at', v_pipeline.invited_at,
    'invitation_message', v_pipeline.invitation_message,
    'responded_at', v_pipeline.responded_at,
    'response', v_pipeline.response,
    'response_note', v_pipeline.response_note,
    'cancelled_at', v_pipeline.cancelled_at,
    'cancellation_reason', v_pipeline.cancellation_reason,
    'reason_category_snapshot', v_pipeline.reason_category_snapshot
  );
END $$;

REVOKE ALL ON FUNCTION public.get_my_re_engagement_invitation(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_re_engagement_invitation(uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.get_my_re_engagement_invitation(uuid) IS
'ARM-9 Frontend (p118). Read-only RPC for the invited alumni to fetch their own pipeline entry. Used by /me/re-engagement/[id] page to display cycle, invitation message, and current state before calling respond_re_engagement. Auth: caller.member_id must match pipeline.member_id.';

NOTIFY pgrst, 'reload schema';
