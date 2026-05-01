-- p86 #5: visibility de comunicações enviadas a um candidato (selection_application).
-- Match by external_email — cobre PMI welcomes, interview reschedule, e futuras comms.
-- V4: committee lead OR member, OR manage_member.

DROP FUNCTION IF EXISTS public.get_application_communications(uuid);
CREATE FUNCTION public.get_application_communications(p_application_id uuid)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_committee record;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  SELECT * INTO v_committee
  FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id
    AND member_id = v_caller.id
    AND role IN ('lead','member');

  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_member'::text) THEN
    RAISE EXCEPTION 'Unauthorized: must be committee member or have manage_member';
  END IF;

  SELECT jsonb_agg(
    jsonb_build_object(
      'send_id', cs.id,
      'template_name', ct.name,
      'template_slug', ct.slug,
      'template_category', ct.category,
      'send_status', cs.status,
      'send_created_at', cs.created_at,
      'send_sent_at', cs.sent_at,
      'send_error_log', cs.error_log,
      'audience_source', cs.audience_filter->>'source',
      'recipient_id', cr.id,
      'recipient_email', cr.external_email,
      'recipient_delivered', cr.delivered,
      'recipient_delivered_at', cr.delivered_at,
      'recipient_error_message', cr.error_message,
      'recipient_bounce_type', cr.bounce_type,
      'recipient_bounced_at', cr.bounced_at,
      'recipient_opened_at', cr.first_opened_at,
      'recipient_open_count', cr.open_count,
      'recipient_clicked_at', cr.clicked_at,
      'recipient_click_count', cr.click_count,
      'recipient_complained_at', cr.complained_at,
      'recipient_bot_suspected', cr.bot_suspected
    )
    ORDER BY cs.created_at DESC
  ) INTO v_result
  FROM public.campaign_recipients cr
  JOIN public.campaign_sends cs ON cs.id = cr.send_id
  JOIN public.campaign_templates ct ON ct.id = cs.template_id
  WHERE lower(cr.external_email) = lower(v_app.email);

  RETURN jsonb_build_object(
    'application_id', p_application_id,
    'applicant_email', v_app.email,
    'communications', COALESCE(v_result, '[]'::jsonb)
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_application_communications(uuid) TO authenticated;

COMMENT ON FUNCTION public.get_application_communications(uuid) IS
  'p86 #5: returns timeline of all campaign emails sent to applicant.email. V4 manage_member or committee member (lead OR member). Powers Comunicação tab in admin/selection modal.';

NOTIFY pgrst, 'reload schema';
