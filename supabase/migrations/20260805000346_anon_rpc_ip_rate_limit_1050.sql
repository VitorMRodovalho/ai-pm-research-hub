-- #1050: in-RPC per-IP rate limiting for anon-executable RPCs called browser→Supabase
-- direct (they bypass the Cloudflare Worker edge, so Worker/zone rules cannot cover them).
-- Mechanism verified live: an anon PostgREST RPC can read cf-connecting-ip from
-- current_setting('request.headers'). Fail-OPEN everywhere: a missing IP signal or any
-- storage error must never block a legitimate caller (authority stays in the RPC logic).

-- ── counter store: unlogged (perf; survivable loss — it's throwaway throttle state) ──
CREATE UNLOGGED TABLE IF NOT EXISTS public.anon_rate_counters (
  bucket_key text PRIMARY KEY,          -- '{action}:{ip}:{minute_bucket}'
  hits       int NOT NULL DEFAULT 0,
  expires_at timestamptz NOT NULL
);
-- Deny-all: only the SECURITY DEFINER helper (running as owner) touches this table.
ALTER TABLE public.anon_rate_counters ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.anon_rate_counters FROM anon, authenticated;

-- ── helper: atomic bump + threshold check, keyed by client IP + action + time bucket ──
CREATE OR REPLACE FUNCTION public.rl_check_and_bump(
  p_action text, p_limit int, p_window_s int DEFAULT 60
) RETURNS boolean               -- true = allowed, false = throttled
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_ip     text;
  v_bucket bigint;
  v_key    text;
  v_hits   int;
BEGIN
  -- Resolve client IP from the PostgREST request headers. Fail-OPEN if unavailable
  -- (service-role / server-side calls have no request.headers).
  BEGIN
    v_ip := current_setting('request.headers', true)::jsonb->>'cf-connecting-ip';
  EXCEPTION WHEN others THEN
    v_ip := NULL;
  END;
  IF v_ip IS NULL OR v_ip = '' THEN
    RETURN true;
  END IF;

  v_bucket := floor(extract(epoch FROM now()) / p_window_s);
  v_key := p_action || ':' || v_ip || ':' || v_bucket::text;

  INSERT INTO public.anon_rate_counters (bucket_key, hits, expires_at)
  VALUES (v_key, 1, now() + make_interval(secs => p_window_s + 10))
  ON CONFLICT (bucket_key)
  DO UPDATE SET hits = public.anon_rate_counters.hits + 1
  RETURNING hits INTO v_hits;

  -- Opportunistic GC (~2% of calls) so the unlogged table stays small without a cron.
  IF random() < 0.02 THEN
    DELETE FROM public.anon_rate_counters WHERE expires_at < now();
  END IF;

  RETURN v_hits <= p_limit;
EXCEPTION WHEN others THEN
  RETURN true;  -- fail-open on any storage error
END;
$function$;
-- NOT granted to anon/authenticated: internal helper, must not be PostgREST-callable.
REVOKE ALL ON FUNCTION public.rl_check_and_bump(text, int, int) FROM public, anon, authenticated;

-- ── verify_certificate: +30/min/IP throttle (kills scripted code enumeration) ──
CREATE OR REPLACE FUNCTION public.verify_certificate(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  cert record;
  v_member_name text;
  guest record;
BEGIN
  -- #991 oracle-free contract: a throttled caller must be INDISTINGUISHABLE from a
  -- not-found result (no status/discriminant key at all). Collapse to valid=false.
  IF NOT public.rl_check_and_bump('verify_certificate', 30, 60) THEN
    RETURN jsonb_build_object('valid', false);
  END IF;

  SELECT c.* INTO cert
  FROM certificates c
  WHERE c.verification_code = p_code;

  IF cert IS NULL OR cert.status IS DISTINCT FROM 'issued' THEN
    SELECT g.id, g.type, g.title, g.issued_at, g.counter_signed_by, g.counter_signed_at,
           g.language, g.verification_code, g.status,
           p.name AS guest_name, e.title AS event_title, e.date AS event_date
    INTO guest
    FROM event_guest_certificates g
    JOIN persons p ON p.id = g.person_id
    JOIN events e ON e.id = g.event_id
    WHERE g.verification_code = p_code;

    IF guest.id IS NULL OR guest.status IS DISTINCT FROM 'issued' THEN
      RETURN jsonb_build_object('valid', false);
    END IF;

    RETURN jsonb_build_object(
      'valid', true,
      'type', guest.type,
      'title', guest.title,
      'member_name', guest.guest_name,
      'issued_at', guest.issued_at,
      'authorized_by', 'Presidência, Núcleo IA e GP',
      'has_counter_signature', guest.counter_signed_by IS NOT NULL,
      'counter_signed_at', guest.counter_signed_at,
      'cycle', NULL,
      'period_start', guest.event_date::text,
      'period_end', guest.event_date::text,
      'function_role', NULL,
      'language', guest.language,
      'verification_code', guest.verification_code,
      'audience', 'event_guest',
      'event_title', guest.event_title
    );
  END IF;

  SELECT name INTO v_member_name FROM members WHERE id = cert.member_id;

  RETURN jsonb_build_object(
    'valid', true,
    'type', cert.type,
    'title', cert.title,
    'member_name', v_member_name,
    'issued_at', cert.issued_at,
    'authorized_by', 'Presidência, Núcleo IA e GP',
    'has_counter_signature', cert.counter_signed_by IS NOT NULL,
    'counter_signed_at', cert.counter_signed_at,
    'cycle', cert.cycle,
    'period_start', cert.period_start,
    'period_end', cert.period_end,
    'function_role', cert.function_role,
    'language', cert.language,
    'verification_code', cert.verification_code
  );
END;
$function$;

-- ── capture_visitor_lead: +10/min/IP throttle + close the idempotent enumeration oracle ──
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
  IF NOT public.rl_check_and_bump('capture_visitor_lead', 10, 60) THEN
    RETURN jsonb_build_object('error','rate_limited');
  END IF;

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
    -- #1050: return the SAME shape as the insert path (no 'idempotent' flag) so an anon
    -- caller cannot use the response to test whether an email is already a lead.
    RETURN jsonb_build_object('success', true, 'lead_id', v_existing_id);
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
