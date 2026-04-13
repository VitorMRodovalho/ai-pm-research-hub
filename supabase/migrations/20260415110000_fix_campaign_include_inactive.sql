-- ============================================================================
-- Fix: admin_send_campaign() now respects include_inactive filter
-- Context: UI sends { include_inactive: true } but RPC hardcoded
--          WHERE is_active = true AND current_cycle_active = true.
--          Privacy policy changes (Sec. 12) must reach ALL data subjects,
--          including inactive members whose data is still retained.
-- Rollback: Restore from migration 20260319100034.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_send_campaign(
  p_template_id uuid,
  p_audience_filter jsonb DEFAULT '{}'::jsonb,
  p_scheduled_at timestamptz DEFAULT NULL,
  p_external_contacts jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_id uuid;
  v_send_id uuid;
  v_count int := 0;
  v_ext_count int := 0;
  v_sends_last_hour int;
  v_sends_last_day int;
  v_member record;
  v_tmpl record;
  v_roles text[];
  v_desigs text[];
  v_chapters text[];
  v_all boolean;
  v_include_inactive boolean;
  v_ext record;
BEGIN
  -- Auth check: GP/DM only
  SELECT id INTO v_caller_id
  FROM public.members
  WHERE auth_id = auth.uid()
    AND (is_superadmin
         OR operational_role IN ('manager','deputy_manager'));
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: only GP/DM can send campaigns';
  END IF;

  -- Rate limit: max 1 send per hour, max 3 per day
  SELECT COUNT(*) INTO v_sends_last_hour
  FROM public.campaign_sends
  WHERE sent_by = v_caller_id
    AND created_at > now() - interval '1 hour'
    AND status NOT IN ('draft','failed');
  IF v_sends_last_hour >= 1 THEN
    RAISE EXCEPTION 'Rate limit: max 1 campaign per hour';
  END IF;

  SELECT COUNT(*) INTO v_sends_last_day
  FROM public.campaign_sends
  WHERE sent_by = v_caller_id
    AND created_at > now() - interval '1 day'
    AND status NOT IN ('draft','failed');
  IF v_sends_last_day >= 3 THEN
    RAISE EXCEPTION 'Rate limit: max 3 campaigns per day';
  END IF;

  -- Validate template exists
  SELECT * INTO v_tmpl FROM public.campaign_templates WHERE id = p_template_id;
  IF v_tmpl IS NULL THEN
    RAISE EXCEPTION 'Template not found';
  END IF;

  -- Parse audience filter
  v_roles := ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_audience_filter->'roles', '[]'::jsonb)));
  v_desigs := ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_audience_filter->'designations', '[]'::jsonb)));
  v_chapters := ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_audience_filter->'chapters', '[]'::jsonb)));
  v_all := COALESCE((p_audience_filter->>'all')::boolean, false);
  v_include_inactive := COALESCE((p_audience_filter->>'include_inactive')::boolean, false);

  -- Create send record
  INSERT INTO public.campaign_sends (id, template_id, sent_by, audience_filter, status, scheduled_at)
  VALUES (gen_random_uuid(), p_template_id, v_caller_id, p_audience_filter,
          CASE WHEN p_scheduled_at IS NOT NULL THEN 'scheduled' ELSE 'pending_delivery' END,
          p_scheduled_at)
  RETURNING id INTO v_send_id;

  -- Resolve member recipients
  FOR v_member IN
    SELECT m.id, 'pt' AS lang
    FROM public.members m
    LEFT JOIN public.tribes t ON t.id = m.tribe_id
    WHERE m.email IS NOT NULL
      AND (
        (m.is_active = true AND m.current_cycle_active = true)
        OR (v_include_inactive AND (m.is_active = false OR m.current_cycle_active = false))
      )
      AND (
        v_all
        OR v_include_inactive
        OR (array_length(v_roles, 1) > 0 AND m.operational_role = ANY(v_roles))
        OR (array_length(v_desigs, 1) > 0 AND m.designations && v_desigs)
        OR (array_length(v_chapters, 1) > 0 AND t.chapter = ANY(v_chapters))
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.campaign_recipients cr2
        JOIN public.campaign_sends cs2 ON cs2.id = cr2.send_id
        WHERE cr2.member_id = m.id AND cr2.unsubscribed = true
      )
  LOOP
    INSERT INTO public.campaign_recipients (send_id, member_id, language)
    VALUES (v_send_id, v_member.id, v_member.lang);
    v_count := v_count + 1;
  END LOOP;

  -- Add external contacts
  FOR v_ext IN SELECT * FROM jsonb_array_elements(p_external_contacts)
  LOOP
    INSERT INTO public.campaign_recipients (send_id, external_email, external_name, language)
    VALUES (
      v_send_id,
      v_ext.value->>'email',
      v_ext.value->>'name',
      COALESCE(v_ext.value->>'language', 'en')
    );
    v_ext_count := v_ext_count + 1;
  END LOOP;

  -- Update recipient count
  UPDATE public.campaign_sends SET recipient_count = v_count + v_ext_count WHERE id = v_send_id;

  RETURN jsonb_build_object(
    'send_id', v_send_id,
    'member_recipients', v_count,
    'external_recipients', v_ext_count,
    'total_recipients', v_count + v_ext_count,
    'status', CASE WHEN p_scheduled_at IS NOT NULL THEN 'scheduled' ELSE 'pending_delivery' END
  );
END;
$$;

NOTIFY pgrst, 'reload schema';
