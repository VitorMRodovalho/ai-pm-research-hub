-- ARM-1 Captação: enrichment + RPCs + funnel stats
-- Substrate: visitor_leads table existed empty + RLS anon insert + form em /about (ImpactPageIsland).
-- Gap: no UTM, no promote path, no admin visibility, no funnel stats.
-- Scope: ALTER table for UTM/referrer + 5 RPCs (capture/list/promote/dismiss/funnel_stats) + status CHECK.

-- ============================================================
-- Step 1: Enrichment columns (mirror selection_applications Onda 2.1)
-- ============================================================
ALTER TABLE public.visitor_leads
  ADD COLUMN IF NOT EXISTS utm_data jsonb,
  ADD COLUMN IF NOT EXISTS referrer_member_id uuid REFERENCES public.members(id),
  ADD COLUMN IF NOT EXISTS promoted_to_application_id uuid REFERENCES public.selection_applications(id),
  ADD COLUMN IF NOT EXISTS promoted_at timestamptz,
  ADD COLUMN IF NOT EXISTS promoted_by uuid REFERENCES public.members(id),
  ADD COLUMN IF NOT EXISTS dismissed_at timestamptz,
  ADD COLUMN IF NOT EXISTS dismissed_by uuid REFERENCES public.members(id),
  ADD COLUMN IF NOT EXISTS dismissal_reason text,
  ADD COLUMN IF NOT EXISTS dedupe_email_normalized text GENERATED ALWAYS AS (LOWER(TRIM(email))) STORED;

CREATE INDEX IF NOT EXISTS idx_visitor_leads_status ON public.visitor_leads(status);
CREATE INDEX IF NOT EXISTS idx_visitor_leads_chapter ON public.visitor_leads(chapter_interest);
CREATE INDEX IF NOT EXISTS idx_visitor_leads_email_norm ON public.visitor_leads(dedupe_email_normalized);
CREATE INDEX IF NOT EXISTS idx_visitor_leads_referrer ON public.visitor_leads(referrer_member_id);

DO $$
BEGIN
  ALTER TABLE public.visitor_leads
    ADD CONSTRAINT visitor_leads_status_check
    CHECK (status IS NULL OR status IN ('new','contacted','promoted','dismissed'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN check_violation THEN
    UPDATE public.visitor_leads SET status = 'new' WHERE status IS NOT NULL AND status NOT IN ('new','contacted','promoted','dismissed');
    ALTER TABLE public.visitor_leads
      ADD CONSTRAINT visitor_leads_status_check
      CHECK (status IS NULL OR status IN ('new','contacted','promoted','dismissed'));
END $$;

-- ============================================================
-- Step 2: capture_visitor_lead — public RPC, anon-callable
-- ============================================================
CREATE OR REPLACE FUNCTION public.capture_visitor_lead(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_lead_id uuid;
  v_email text;
  v_name text;
  v_consent boolean;
  v_referrer_id uuid;
  v_existing_id uuid;
BEGIN
  v_email := NULLIF(TRIM(LOWER(p_payload->>'email')), '');
  v_name := NULLIF(TRIM(p_payload->>'name'), '');
  v_consent := COALESCE((p_payload->>'lgpd_consent')::boolean, false);

  IF v_email IS NULL OR v_name IS NULL THEN
    RETURN jsonb_build_object('error','name and email are required');
  END IF;

  IF NOT v_consent THEN
    RETURN jsonb_build_object('error','LGPD consent is required');
  END IF;

  IF v_email !~ '^[^@]+@[^@]+\.[^@]+$' THEN
    RETURN jsonb_build_object('error','invalid email format');
  END IF;

  IF p_payload ? 'referrer_member_id' AND (p_payload->>'referrer_member_id') ~ '^[0-9a-f-]{36}$' THEN
    v_referrer_id := (p_payload->>'referrer_member_id')::uuid;
    PERFORM 1 FROM public.members WHERE id = v_referrer_id;
    IF NOT FOUND THEN v_referrer_id := NULL; END IF;
  END IF;

  SELECT id INTO v_existing_id
  FROM public.visitor_leads
  WHERE LOWER(TRIM(email)) = v_email AND status = 'new'
  LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    UPDATE public.visitor_leads SET
      phone = COALESCE(NULLIF(TRIM(p_payload->>'phone'),''), phone),
      chapter_interest = COALESCE(NULLIF(TRIM(p_payload->>'chapter_interest'),''), chapter_interest),
      role_interest = COALESCE(NULLIF(TRIM(p_payload->>'role_interest'),''), role_interest),
      message = COALESCE(NULLIF(TRIM(p_payload->>'message'),''), message),
      utm_data = COALESCE(p_payload->'utm_data', utm_data),
      referrer_member_id = COALESCE(v_referrer_id, referrer_member_id),
      source = COALESCE(NULLIF(TRIM(p_payload->>'source'),''), source)
    WHERE id = v_existing_id;
    RETURN jsonb_build_object('success', true, 'lead_id', v_existing_id, 'idempotent', true);
  END IF;

  INSERT INTO public.visitor_leads (
    name, email, phone, chapter_interest, role_interest, message,
    lgpd_consent, source, status, utm_data, referrer_member_id
  ) VALUES (
    v_name, v_email,
    NULLIF(TRIM(p_payload->>'phone'), ''),
    NULLIF(TRIM(p_payload->>'chapter_interest'), ''),
    NULLIF(TRIM(p_payload->>'role_interest'), ''),
    NULLIF(TRIM(p_payload->>'message'), ''),
    true,
    COALESCE(NULLIF(TRIM(p_payload->>'source'), ''), 'website'),
    'new',
    p_payload->'utm_data',
    v_referrer_id
  )
  RETURNING id INTO v_lead_id;

  RETURN jsonb_build_object('success', true, 'lead_id', v_lead_id);
END $$;

REVOKE ALL ON FUNCTION public.capture_visitor_lead(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.capture_visitor_lead(jsonb) TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.capture_visitor_lead(jsonb) IS
'ARM-1 Captação. Public anon-callable lead capture. Idempotent (same email + status=new updates last-wins). LGPD: rejects payload without lgpd_consent=true. Normalizes email to lowercase trimmed.';

-- ============================================================
-- Step 3: list_visitor_leads — admin view
-- ============================================================
CREATE OR REPLACE FUNCTION public.list_visitor_leads(
  p_status text DEFAULT NULL,
  p_chapter text DEFAULT NULL,
  p_limit int DEFAULT 200
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller record;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
    RETURN jsonb_build_object('error','Unauthorized: requires manage_member permission');
  END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'lead_id', l.id, 'name', l.name, 'email', l.email, 'phone', l.phone,
    'chapter_interest', l.chapter_interest, 'role_interest', l.role_interest, 'message', l.message,
    'source', l.source, 'status', l.status, 'utm_data', l.utm_data,
    'referrer_member_id', l.referrer_member_id, 'referrer_name', rm.name,
    'created_at', l.created_at, 'contacted_at', l.contacted_at, 'contacted_by_name', cb.name,
    'promoted_at', l.promoted_at, 'promoted_to_application_id', l.promoted_to_application_id,
    'promoted_by_name', pb.name, 'dismissed_at', l.dismissed_at, 'dismissed_by_name', db.name,
    'dismissal_reason', l.dismissal_reason
  ) ORDER BY l.created_at DESC) INTO v_result
  FROM (
    SELECT * FROM public.visitor_leads
    WHERE (p_status IS NULL OR status = p_status)
      AND (p_chapter IS NULL OR chapter_interest = p_chapter)
    ORDER BY created_at DESC LIMIT p_limit
  ) l
  LEFT JOIN public.members rm ON rm.id = l.referrer_member_id
  LEFT JOIN public.members cb ON cb.id = l.contacted_by
  LEFT JOIN public.members pb ON pb.id = l.promoted_by
  LEFT JOIN public.members db ON db.id = l.dismissed_by;

  RETURN jsonb_build_object('items', COALESCE(v_result, '[]'::jsonb));
END $$;

REVOKE ALL ON FUNCTION public.list_visitor_leads(text, text, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_visitor_leads(text, text, int) TO authenticated, service_role;

-- ============================================================
-- Step 4: promote_lead_to_application — admin manual curation
-- ============================================================
CREATE OR REPLACE FUNCTION public.promote_lead_to_application(
  p_lead_id uuid, p_cycle_id uuid, p_pmi_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller record; v_lead record; v_cycle record;
  v_app_id uuid; v_first text; v_last text;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
    RETURN jsonb_build_object('error','Unauthorized: requires manage_member permission');
  END IF;

  SELECT * INTO v_lead FROM public.visitor_leads WHERE id = p_lead_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Lead not found'); END IF;

  IF v_lead.status = 'promoted' THEN
    RETURN jsonb_build_object('error','Lead already promoted', 'application_id', v_lead.promoted_to_application_id);
  END IF;
  IF v_lead.status = 'dismissed' THEN
    RETURN jsonb_build_object('error','Lead was dismissed; cannot promote');
  END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = p_cycle_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Cycle not found'); END IF;
  IF v_cycle.status <> 'open' THEN
    RETURN jsonb_build_object('error','Cycle is not open: ' || v_cycle.status);
  END IF;

  v_first := SPLIT_PART(v_lead.name, ' ', 1);
  v_last := NULLIF(TRIM(SUBSTRING(v_lead.name FROM POSITION(' ' IN v_lead.name) + 1)), '');

  INSERT INTO public.selection_applications (
    cycle_id, applicant_name, first_name, last_name, email, phone, pmi_id, chapter,
    referral_source, referrer_member_id, utm_data, status, created_at, application_date
  ) VALUES (
    p_cycle_id, v_lead.name, v_first, v_last, v_lead.email, v_lead.phone, p_pmi_id,
    v_lead.chapter_interest, COALESCE(v_lead.source, 'lead_promote'),
    v_lead.referrer_member_id, v_lead.utm_data, 'submitted', now(), CURRENT_DATE
  ) RETURNING id INTO v_app_id;

  UPDATE public.visitor_leads SET
    status = 'promoted', promoted_at = now(),
    promoted_by = v_caller.id, promoted_to_application_id = v_app_id
  WHERE id = p_lead_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (v_caller.id, 'visitor_lead.promoted', 'visitor_lead', p_lead_id,
    jsonb_build_object('application_id', v_app_id, 'cycle_id', p_cycle_id),
    jsonb_strip_nulls(jsonb_build_object('lead_email', v_lead.email, 'pmi_id', p_pmi_id)));

  RETURN jsonb_build_object('success', true, 'lead_id', p_lead_id, 'application_id', v_app_id);
END $$;

REVOKE ALL ON FUNCTION public.promote_lead_to_application(uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.promote_lead_to_application(uuid, uuid, text) TO authenticated, service_role;

-- ============================================================
-- Step 5: dismiss_visitor_lead — admin discard
-- ============================================================
CREATE OR REPLACE FUNCTION public.dismiss_visitor_lead(
  p_lead_id uuid, p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_caller record; v_lead record;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
    RETURN jsonb_build_object('error','Unauthorized: requires manage_member permission');
  END IF;

  SELECT * INTO v_lead FROM public.visitor_leads WHERE id = p_lead_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Lead not found'); END IF;

  IF v_lead.status IN ('promoted','dismissed') THEN
    RETURN jsonb_build_object('error','Cannot dismiss from state: ' || v_lead.status);
  END IF;

  UPDATE public.visitor_leads SET
    status = 'dismissed', dismissed_at = now(),
    dismissed_by = v_caller.id, dismissal_reason = p_reason
  WHERE id = p_lead_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (v_caller.id, 'visitor_lead.dismissed', 'visitor_lead', p_lead_id,
    jsonb_build_object('previous_status', v_lead.status),
    jsonb_strip_nulls(jsonb_build_object('reason', p_reason, 'lead_email', v_lead.email)));

  RETURN jsonb_build_object('success', true, 'lead_id', p_lead_id);
END $$;

REVOKE ALL ON FUNCTION public.dismiss_visitor_lead(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dismiss_visitor_lead(uuid, text) TO authenticated, service_role;

-- ============================================================
-- Step 6: get_volunteer_funnel_stats — funnel breakdown
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_volunteer_funnel_stats(p_cycle_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller record;
  v_lead_stats jsonb; v_app_stats jsonb;
  v_by_source jsonb; v_by_chapter jsonb;
  v_target_cycle uuid;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
    RETURN jsonb_build_object('error','Unauthorized: requires manage_member permission');
  END IF;

  IF p_cycle_id IS NULL THEN
    SELECT id INTO v_target_cycle FROM public.selection_cycles WHERE status='open' ORDER BY open_date DESC LIMIT 1;
  ELSE
    v_target_cycle := p_cycle_id;
  END IF;

  SELECT jsonb_build_object(
    'total', COUNT(*),
    'new', COUNT(*) FILTER (WHERE status = 'new'),
    'contacted', COUNT(*) FILTER (WHERE status = 'contacted'),
    'promoted', COUNT(*) FILTER (WHERE status = 'promoted'),
    'dismissed', COUNT(*) FILTER (WHERE status = 'dismissed')
  ) INTO v_lead_stats FROM public.visitor_leads;

  SELECT jsonb_build_object(
    'total', COUNT(*),
    'submitted', COUNT(*) FILTER (WHERE status = 'submitted'),
    'in_review', COUNT(*) FILTER (WHERE status = 'in_review'),
    'accepted', COUNT(*) FILTER (WHERE status = 'accepted'),
    'rejected', COUNT(*) FILTER (WHERE status = 'rejected'),
    'from_promoted_leads', COUNT(*) FILTER (WHERE referral_source = 'lead_promote')
  ) INTO v_app_stats FROM public.selection_applications
  WHERE v_target_cycle IS NULL OR cycle_id = v_target_cycle;

  WITH src AS (
    SELECT COALESCE(NULLIF(utm_data->>'utm_source',''), source, 'unknown') AS src_key,
      COUNT(*) AS cnt, COUNT(*) FILTER (WHERE status = 'promoted') AS promoted_cnt
    FROM public.visitor_leads GROUP BY src_key
  )
  SELECT jsonb_agg(jsonb_build_object('source', src_key, 'leads', cnt, 'promoted', promoted_cnt) ORDER BY cnt DESC)
  INTO v_by_source FROM src;

  WITH ch AS (
    SELECT COALESCE(chapter_interest, 'unspecified') AS chapter, COUNT(*) AS cnt
    FROM public.visitor_leads GROUP BY chapter
  )
  SELECT jsonb_agg(jsonb_build_object('chapter', chapter, 'leads', cnt) ORDER BY cnt DESC)
  INTO v_by_chapter FROM ch;

  RETURN jsonb_build_object(
    'cycle_id', v_target_cycle,
    'leads', v_lead_stats, 'applications', v_app_stats,
    'by_source', COALESCE(v_by_source, '[]'::jsonb),
    'by_chapter', COALESCE(v_by_chapter, '[]'::jsonb)
  );
END $$;

REVOKE ALL ON FUNCTION public.get_volunteer_funnel_stats(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_volunteer_funnel_stats(uuid) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
