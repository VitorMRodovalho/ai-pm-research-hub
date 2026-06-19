-- Cycle 4 Fatia B1 — public data layer for the verticals landing.
-- (1) get_public_verticals(): anon-safe list of community_vertical initiatives for the
--     hub-and-spoke (bloco 3) + CTA "Seja protagonista" (bloco 6). NEVER leaks
--     metadata.intended_lead (person name/id = LGPD PII) — only config keys selected.
-- (2) capture_visitor_lead: persist target_vertical (founder interest per vertical, bloco 6).
-- (3) get_public_platform_stats: add total_verticals (bloco 2 counter).
-- Ref: ADR-0103, docs/strategy/cycle4_landing_value_prop.md (§5a, §4, §3)

-- (2a) founder-interest dimension on the lead funnel. uuid + FK so it can only ever
-- point at a real initiative (data-architect C1; security MEDIUM anti-pollution).
ALTER TABLE public.visitor_leads
  ADD COLUMN IF NOT EXISTS target_vertical uuid
    REFERENCES public.initiatives(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.visitor_leads.target_vertical IS
  'UUID da initiative (kind=community_vertical) de interesse do fundador. Nullable. Capturado via bloco 6 CTA da landing (ADR-0103, Ciclo 4).';

CREATE INDEX IF NOT EXISTS idx_visitor_leads_target_vertical
  ON public.visitor_leads(target_vertical) WHERE target_vertical IS NOT NULL;

-- (1) public verticals RPC — anon-safe; surfaces ONLY non-PII config keys.
CREATE OR REPLACE FUNCTION public.get_public_verticals()
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT COALESCE(jsonb_agg(
           jsonb_build_object(
             'id', i.id,
             'title', i.title,
             'description', i.description,
             'vertical_status', i.metadata->>'status',
             'anchor_credential', i.metadata->>'anchor_credential',
             'credential_body', i.metadata->>'credential_body',
             'partner_org', i.metadata->>'partner_org'
           )
           ORDER BY
             CASE i.metadata->>'status'
               WHEN 'open' THEN 1 WHEN 'forming' THEN 2 WHEN 'paused' THEN 3 ELSE 4 END,
             i.title
         ), '[]'::jsonb)
  FROM public.initiatives i
  WHERE i.kind = 'community_vertical'
    AND i.status = 'active';
$function$;

REVOKE ALL ON FUNCTION public.get_public_verticals() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_verticals() TO anon, authenticated, service_role;

-- (2b) capture_visitor_lead — persist target_vertical (founder CTA, bloco 6).
CREATE OR REPLACE FUNCTION public.capture_visitor_lead(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_lead_id uuid;
  v_email text;
  v_name text;
  v_consent boolean;
  v_referrer_id uuid;
  v_existing_id uuid;
  v_target_vertical uuid;
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

  -- Soft email format check
  IF v_email !~ '^[^@]+@[^@]+\.[^@]+$' THEN
    RETURN jsonb_build_object('error','invalid email format');
  END IF;

  -- Optional referrer (member_id from URL query ?ref=xxx)
  IF p_payload ? 'referrer_member_id' AND (p_payload->>'referrer_member_id') ~ '^[0-9a-f-]{36}$' THEN
    v_referrer_id := (p_payload->>'referrer_member_id')::uuid;
    -- Verify exists
    PERFORM 1 FROM public.members WHERE id = v_referrer_id;
    IF NOT FOUND THEN v_referrer_id := NULL; END IF;
  END IF;

  -- Optional founder-interest vertical (bloco 6 CTA). Resolve defensively: keep only
  -- when it points at a real community_vertical; else drop to NULL (analytics field,
  -- never blocks lead capture). Mirrors referrer_member_id (data-architect/security review).
  IF p_payload ? 'target_vertical' AND (p_payload->>'target_vertical') ~ '^[0-9a-f-]{36}$' THEN
    v_target_vertical := (p_payload->>'target_vertical')::uuid;
    PERFORM 1 FROM public.initiatives WHERE id = v_target_vertical AND kind = 'community_vertical';
    IF NOT FOUND THEN v_target_vertical := NULL; END IF;
  END IF;

  -- Idempotent: if same email already exists with status='new', return existing
  SELECT id INTO v_existing_id
  FROM public.visitor_leads
  WHERE LOWER(TRIM(email)) = v_email AND status = 'new'
  LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    -- Update with new payload (last-wins on optional fields)
    UPDATE public.visitor_leads SET
      phone = COALESCE(NULLIF(TRIM(p_payload->>'phone'),''), phone),
      chapter_interest = COALESCE(NULLIF(TRIM(p_payload->>'chapter_interest'),''), chapter_interest),
      role_interest = COALESCE(NULLIF(TRIM(p_payload->>'role_interest'),''), role_interest),
      message = COALESCE(NULLIF(TRIM(p_payload->>'message'),''), message),
      target_vertical = COALESCE(v_target_vertical, target_vertical),
      utm_data = COALESCE(p_payload->'utm_data', utm_data),
      referrer_member_id = COALESCE(v_referrer_id, referrer_member_id),
      source = COALESCE(NULLIF(TRIM(p_payload->>'source'),''), source)
    WHERE id = v_existing_id;
    RETURN jsonb_build_object('success', true, 'lead_id', v_existing_id, 'idempotent', true);
  END IF;

  INSERT INTO public.visitor_leads (
    name, email, phone, chapter_interest, role_interest, message,
    lgpd_consent, source, status, utm_data, referrer_member_id, target_vertical
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
    v_referrer_id,
    v_target_vertical
  )
  RETURNING id INTO v_lead_id;

  RETURN jsonb_build_object('success', true, 'lead_id', v_lead_id);
END $function$;

-- (3) get_public_platform_stats — add total_verticals (bloco 2 counter).
CREATE OR REPLACE FUNCTION public.get_public_platform_stats()
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT json_build_object(
    -- #625 C1 (homepage instance): pre-onboarding cohort excluded -- "Pesquisadores ativos"
    -- counts only members OPERATING in the current cycle.
    'active_members', (
      SELECT COUNT(*) FROM public.members m
      WHERE m.is_active AND m.current_cycle_active
        AND NOT public.member_is_pre_onboarding(m.person_id, m.member_status)
    ),
    'total_tribes', (SELECT COUNT(*) FROM public.tribes WHERE is_active),
    'total_initiatives', (
      SELECT count(*) FROM public.initiatives
      WHERE status = 'active' AND legacy_tribe_id IS NULL
    ),
    -- Cycle 4: community verticals (ADR-0103) surfaced as a live counter.
    'total_verticals', (
      SELECT count(*) FROM public.initiatives
      WHERE kind = 'community_vertical' AND status = 'active'
    ),
    -- #481: canonical signed-chapter count.
    'total_chapters', (public.get_chapter_metrics()->>'signed')::int,
    'total_events', (SELECT COUNT(*) FROM public.events WHERE date >= '2026-01-01'),
    'total_resources', (SELECT COUNT(*) FROM public.hub_resources WHERE is_active),
    'retention_rate', (
      SELECT ROUND(
        COUNT(*) FILTER (WHERE m.current_cycle_active)::numeric /
        NULLIF(COUNT(*) FILTER (WHERE m.is_active OR m.member_status = 'alumni'), 0) * 100, 1
      )
      FROM public.members m
      WHERE m.member_status IN ('active','alumni','observer')
        AND NOT public.member_is_pre_onboarding(m.person_id, m.member_status)
    )
  );
$function$;

NOTIFY pgrst, 'reload schema';
