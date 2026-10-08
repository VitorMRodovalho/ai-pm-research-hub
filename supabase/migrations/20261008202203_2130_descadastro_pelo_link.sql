-- #2130 E-a: the campaign unsubscribe link works, and an unsubscribe holds per ADDRESS.
--
-- Every campaign email carries `/unsubscribe?token=<campaign_recipients.unsubscribe_token>` in the body and in the
-- List-Unsubscribe header, but no page or RPC consumed the token. Decisions of the GP (2026-10-08, E1 to E3):
--   * an unsubscribe blocks CAMPAIGNS only; one-off transactional sends (campaign_send_one_off) keep going;
--   * it is stored per address, because 689 of 1262 recipient rows are not members and have no member_id.
--
-- 1. email_unsubscribes: one row per address. Kept on purpose after member deletion: it is the record that
--    honours the opt-out, and without it the address would receive campaigns again.
CREATE TABLE IF NOT EXISTS public.email_unsubscribes (
  email text PRIMARY KEY CHECK (email = lower(btrim(email)) AND email <> ''),
  source text NOT NULL CHECK (source IN ('link', 'one_click')),
  campaign_recipient_id uuid REFERENCES public.campaign_recipients(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.email_unsubscribes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.email_unsubscribes FROM anon, authenticated;
COMMENT ON TABLE public.email_unsubscribes IS
  '#2130: campaign opt-out per address, written only by campaign_unsubscribe(). Retained to honour the opt-out.';

-- 2. The address is unsubscribed when it is in the table, or when any recipient row for it carries the flag
--    (the webhook sets the flag on a spam complaint). The member's CURRENT email is the address of a member row.
CREATE OR REPLACE FUNCTION public._campaign_email_unsubscribed(p_email text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT EXISTS (SELECT 1 FROM public.email_unsubscribes u WHERE u.email = lower(btrim(p_email)))
      OR EXISTS (
        SELECT 1 FROM public.campaign_recipients cr
        LEFT JOIN public.members m ON m.id = cr.member_id
        WHERE cr.unsubscribed = true
          AND lower(btrim(COALESCE(m.email, cr.external_email))) = lower(btrim(p_email))
      );
$function$;
REVOKE ALL ON FUNCTION public._campaign_email_unsubscribed(text) FROM PUBLIC, anon, authenticated;

-- 3. The page and the RFC 8058 one-click POST call this with the token from the link. The token (uuid v4, one per
--    recipient row) is the credential; an unknown token answers invalid_token and nothing else. No address is returned.
CREATE OR REPLACE FUNCTION public.campaign_unsubscribe(p_token uuid, p_one_click boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_id uuid;
  v_email text;
  v_new boolean;
BEGIN
  SELECT cr.id, lower(btrim(COALESCE(m.email, cr.external_email)))
    INTO v_id, v_email
  FROM public.campaign_recipients cr
  LEFT JOIN public.members m ON m.id = cr.member_id
  WHERE cr.unsubscribe_token = p_token;

  IF v_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'invalid_token'); END IF;
  IF v_email IS NULL OR v_email = '' THEN RETURN jsonb_build_object('ok', false, 'reason', 'no_address'); END IF;

  INSERT INTO public.email_unsubscribes (email, source, campaign_recipient_id)
  VALUES (v_email, CASE WHEN p_one_click THEN 'one_click' ELSE 'link' END, v_id)
  ON CONFLICT (email) DO NOTHING;
  v_new := FOUND;

  -- The row of the link, plus every campaign row of the same address not delivered yet: send-campaign skips a
  -- flagged row at send time, so a campaign deferred to the next day is not delivered after the opt-out.
  -- One-off transactional rows are left alone (E1).
  UPDATE public.campaign_recipients cr
  SET unsubscribed = true
  WHERE cr.unsubscribed IS DISTINCT FROM true
    AND (
      cr.id = v_id
      OR (
        cr.delivered IS DISTINCT FROM true
        AND EXISTS (
          SELECT 1 FROM public.campaign_sends cs
          WHERE cs.id = cr.send_id AND COALESCE(cs.audience_filter->>'one_off', 'false') <> 'true'
        )
        AND lower(btrim(COALESCE((SELECT m.email FROM public.members m WHERE m.id = cr.member_id), cr.external_email))) = v_email
      )
    );

  RETURN jsonb_build_object('ok', true, 'already', NOT v_new);
END;
$function$;
REVOKE ALL ON FUNCTION public.campaign_unsubscribe(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.campaign_unsubscribe(uuid, boolean) TO anon, authenticated, service_role;

-- 4. admin_send_campaign: the audience skips unsubscribed addresses, members AND external contacts.
--    Until now only members with a flagged row of their own were skipped; external contacts were never checked.
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
  v_skipped_unsubscribed int := 0;
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
    SELECT m.id, 'pt-BR' AS lang
    FROM public.members m
    WHERE m.email IS NOT NULL
      AND m.email !~* c_reserved_domain
      -- dimensão 1: atividade. include_inactive AMPLIA, nunca substitui a dimensão 2.
      AND (
        (m.is_active = true AND m.current_cycle_active = true)
        OR (v_include_inactive AND (m.is_active = false OR m.current_cycle_active = false))
      )
      -- dimensão 2: segmento. Sem `all` e sem lista alguma, ninguém é selecionado (decisão (a)).
      AND (
        v_all
        OR (array_length(v_roles, 1) > 0 AND m.operational_role = ANY(v_roles))
        OR (array_length(v_desigs, 1) > 0 AND m.designations && v_desigs)
        OR (array_length(v_chapters, 1) > 0 AND m.chapter = ANY(v_chapters))
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.campaign_recipients cr2
        JOIN public.campaign_sends cs2 ON cs2.id = cr2.send_id
        WHERE cr2.member_id = m.id AND cr2.unsubscribed = true
      )
      -- #2130: descadastro vale por endereço, inclusive o feito por um link enviado a outro cadastro.
      AND NOT public._campaign_email_unsubscribed(m.email)
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
    IF public._campaign_email_unsubscribed(v_ext_email) THEN
      v_skipped_unsubscribed := v_skipped_unsubscribed + 1;
      CONTINUE;
    END IF;
    INSERT INTO public.campaign_recipients (send_id, external_email, external_name, language)
    VALUES (v_send_id, v_ext_email, v_ext.value->>'name', public.normalize_platform_language(COALESCE(v_ext.value->>'language', 'en-US')));
    v_ext_count := v_ext_count + 1;
  END LOOP;

  UPDATE public.campaign_sends SET recipient_count = v_count + v_ext_count WHERE id = v_send_id;

  RETURN jsonb_build_object(
    'send_id', v_send_id, 'member_recipients', v_count, 'external_recipients', v_ext_count,
    'total_recipients', v_count + v_ext_count,
    'skipped_reserved_domain', v_skipped_reserved,
    'skipped_unsubscribed', v_skipped_unsubscribed,
    'status', CASE WHEN p_scheduled_at IS NOT NULL THEN 'scheduled' ELSE 'pending_delivery' END
  );
END;
$function$;
