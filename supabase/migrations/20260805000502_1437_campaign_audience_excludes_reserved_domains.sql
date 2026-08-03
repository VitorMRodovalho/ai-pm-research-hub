-- #1437 — test data must never become a real campaign recipient.
--
-- On 2026-08-02 the member campaign for the 04/08 webinar selected 89 recipients, one of which
-- was `test-sync-updated-…@example.com`: a row left behind by tests/contracts/member_emails.test.mjs
-- that kept is_active = true. The audience predicate below (is_active AND current_cycle_active)
-- cannot tell a synthetic row from a member, so it was selected like anyone else. Delivery failed
-- only because Resend refuses example.com.
--
-- The test-side cleanup is fixed in the same PR, but cleanup is best-effort by nature: it depends
-- on a process reaching its end, and a cancelled CI run kills it. This is the send-side floor —
-- addresses in domains RFC 2606 / RFC 6761 reserve for documentation and testing can never reach
-- a person, so they are excluded from BOTH the member loop and the external-contact loop, and
-- excluded rows are not counted in recipient_count.
--
-- Body based on the LIVE definition of admin_send_campaign (pg_get_functiondef, 2026-08-02), not
-- on the last migration that touched it.

CREATE OR REPLACE FUNCTION public.admin_send_campaign(p_template_id uuid, p_audience_filter jsonb DEFAULT '{}'::jsonb, p_scheduled_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_external_contacts jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_send_id uuid;
  v_count int := 0;
  v_ext_count int := 0;
  v_skipped_reserved int := 0;
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
  v_ext_email text;
  -- RFC 2606 / RFC 6761 reserved domains: mail here can never reach a person.
  c_reserved_domain constant text := '@([^@]*\.)?(example\.(com|org|net)|test|invalid|localhost)$';
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Forbidden: only GP/DM can send campaigns';
  END IF;

  SELECT COUNT(*) INTO v_sends_last_hour FROM public.campaign_sends
  WHERE sent_by = v_caller_id AND created_at > now() - interval '1 hour' AND status NOT IN ('draft','failed');
  IF v_sends_last_hour >= 1 THEN RAISE EXCEPTION 'Rate limit: max 1 campaign per hour'; END IF;

  SELECT COUNT(*) INTO v_sends_last_day FROM public.campaign_sends
  WHERE sent_by = v_caller_id AND created_at > now() - interval '1 day' AND status NOT IN ('draft','failed');
  IF v_sends_last_day >= 3 THEN RAISE EXCEPTION 'Rate limit: max 3 campaigns per day'; END IF;

  SELECT * INTO v_tmpl FROM public.campaign_templates WHERE id = p_template_id;
  IF v_tmpl IS NULL THEN RAISE EXCEPTION 'Template not found'; END IF;

  v_roles := ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_audience_filter->'roles', '[]'::jsonb)));
  v_desigs := ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_audience_filter->'designations', '[]'::jsonb)));
  v_chapters := ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_audience_filter->'chapters', '[]'::jsonb)));
  v_all := COALESCE((p_audience_filter->>'all')::boolean, false);
  v_include_inactive := COALESCE((p_audience_filter->>'include_inactive')::boolean, false);

  INSERT INTO public.campaign_sends (id, template_id, sent_by, audience_filter, status, scheduled_at)
  VALUES (gen_random_uuid(), p_template_id, v_caller_id, p_audience_filter,
          CASE WHEN p_scheduled_at IS NOT NULL THEN 'scheduled' ELSE 'pending_delivery' END, p_scheduled_at)
  RETURNING id INTO v_send_id;

  FOR v_member IN
    SELECT m.id, 'pt' AS lang
    FROM public.members m
    WHERE m.email IS NOT NULL
      AND m.email !~* c_reserved_domain
      AND (
        (m.is_active = true AND m.current_cycle_active = true)
        OR (v_include_inactive AND (m.is_active = false OR m.current_cycle_active = false))
      )
      AND (
        v_all OR v_include_inactive
        OR (array_length(v_roles, 1) > 0 AND m.operational_role = ANY(v_roles))
        OR (array_length(v_desigs, 1) > 0 AND m.designations && v_desigs)
        OR (array_length(v_chapters, 1) > 0 AND m.chapter = ANY(v_chapters))
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

  FOR v_ext IN SELECT * FROM jsonb_array_elements(p_external_contacts)
  LOOP
    v_ext_email := v_ext.value->>'email';
    IF v_ext_email IS NULL OR v_ext_email ~* c_reserved_domain THEN
      v_skipped_reserved := v_skipped_reserved + 1;
      CONTINUE;
    END IF;
    INSERT INTO public.campaign_recipients (send_id, external_email, external_name, language)
    VALUES (v_send_id, v_ext_email, v_ext.value->>'name', COALESCE(v_ext.value->>'language', 'en'));
    v_ext_count := v_ext_count + 1;
  END LOOP;

  UPDATE public.campaign_sends SET recipient_count = v_count + v_ext_count WHERE id = v_send_id;

  RETURN jsonb_build_object(
    'send_id', v_send_id, 'member_recipients', v_count, 'external_recipients', v_ext_count,
    'total_recipients', v_count + v_ext_count,
    'skipped_reserved_domain', v_skipped_reserved,
    'status', CASE WHEN p_scheduled_at IS NOT NULL THEN 'scheduled' ELSE 'pending_delivery' END
  );
END;
$function$;

COMMENT ON FUNCTION public.admin_send_campaign(uuid, jsonb, timestamp with time zone, jsonb) IS
  'Sends a campaign to a member audience and/or explicit external contacts. Gated by auth.uid() + can_by_member(manage_platform). Excludes RFC 2606/6761 reserved e-mail domains from both loops (#1437).';
