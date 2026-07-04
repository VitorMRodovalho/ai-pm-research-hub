-- #1098 — Event guest certificates (persons-anchored) — blocker do evento 16/07 (Aftershow)
--
-- certificates.member_id is NOT NULL by design (kept — ADR-0006: members is the engagement
-- bridge; persons models identity). External guests of the 2026-07-16 Aftershow get their own
-- table anchored on persons, with:
--   * verification by code through the SAME public surface (verify_certificate resolves both
--     paths; #991 status-oracle-free semantics preserved: any miss/non-issued state collapses
--     to one indistinguishable {valid:false}),
--   * own retention lane (ROPA G.1: 1 year post-event; explicitly OUTSIDE the members 5y
--     anonymization cron) via delete_expired_event_guest_certificates(),
--   * PDF autogen mirroring trg_certificate_pdf_autogen (same endpoint, same GUC secret;
--     the endpoint disambiguates by id lookup across both tables).
--
-- Issuance gate: can(caller_person,'manage_event'|'manage_platform','organization',org)
-- (V4 ADR-0007 — NOT a seed expansion; both actions already exist).
--
-- counter_signed_by is accepted AT issuance so the single autogen render is already
-- dual-signed (C3 lesson: post-hoc counter-sign forced 3 re-render waves).
--
-- Rollback:
--   DROP TRIGGER IF EXISTS trg_event_guest_cert_pdf_autogen ON public.event_guest_certificates;
--   DROP FUNCTION IF EXISTS public._trg_event_guest_cert_pdf_autogen();
--   DROP FUNCTION IF EXISTS public.issue_event_guest_certificate(jsonb);
--   DROP FUNCTION IF EXISTS public.delete_expired_event_guest_certificates(boolean);
--   (restore verify_certificate from 20260805000309_991_verify_certificate_no_pii_leak.sql)
--   DROP TABLE IF EXISTS public.event_guest_certificates;
--
-- Cross-refs: #1098 #1008 #1009 · docs/audit/LGPD_ROPA_PUBLIC_SURFACES.md §G.1 · ADR-0006/0007
-- · docs/council/decisions/2026-07-03-1008-aftershow-disclosure-gate.md

-- ────────────────────────────────────────────────────────────────────────────
-- 1. Table
-- ────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.event_guest_certificates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  person_id uuid NOT NULL REFERENCES public.persons(id) ON DELETE CASCADE,
  event_id uuid NOT NULL REFERENCES public.events(id) ON DELETE RESTRICT,
  type text NOT NULL DEFAULT 'event_participation' CHECK (type = 'event_participation'),
  title text NOT NULL,
  description text,
  verification_code text NOT NULL UNIQUE,
  language text NOT NULL DEFAULT 'pt-BR',
  status text NOT NULL DEFAULT 'issued' CHECK (status IN ('issued','revoked')),
  issued_at timestamptz NOT NULL DEFAULT now(),
  issued_by uuid REFERENCES public.members(id),
  counter_signed_by uuid REFERENCES public.members(id),
  counter_signed_at timestamptz,
  revoked_at timestamptz,
  revoked_by uuid REFERENCES public.members(id),
  revoked_reason text,
  pdf_url text,
  content_snapshot jsonb,
  retention_until date NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.event_guest_certificates IS
  '#1098: participation certificates for EXTERNAL event guests (persons-anchored; no members row). Retention: 1 year post-event (retention_until), deleted via delete_expired_event_guest_certificates() — NOT covered by the members 5y anonymization cron. ROPA G.1.';
COMMENT ON COLUMN public.event_guest_certificates.retention_until IS
  'ROPA G.1: event date + 1 year. Past this date the row (and its guest-only persons row + stored PDF) must be deleted via delete_expired_event_guest_certificates() + storage purge.';

CREATE UNIQUE INDEX IF NOT EXISTS event_guest_certs_one_issued_per_person_event
  ON public.event_guest_certificates (person_id, event_id) WHERE status = 'issued';
CREATE INDEX IF NOT EXISTS event_guest_certs_event_idx ON public.event_guest_certificates (event_id);
CREATE INDEX IF NOT EXISTS event_guest_certs_person_idx ON public.event_guest_certificates (person_id);
CREATE INDEX IF NOT EXISTS event_guest_certs_retention_idx ON public.event_guest_certificates (retention_until);

DROP TRIGGER IF EXISTS trg_event_guest_certificates_updated_at ON public.event_guest_certificates;
CREATE TRIGGER trg_event_guest_certificates_updated_at
  BEFORE UPDATE ON public.event_guest_certificates
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at_v4();

-- ────────────────────────────────────────────────────────────────────────────
-- 2. RLS — anon gets NOTHING (public verification only via SECURITY DEFINER RPC).
--    Admin (manage_platform) full; event managers + own-row (guest with auth) read.
-- ────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.event_guest_certificates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS egc_admin_all ON public.event_guest_certificates;
CREATE POLICY egc_admin_all ON public.event_guest_certificates
  FOR ALL TO authenticated
  USING (public.rls_can('manage_platform'))
  WITH CHECK (public.rls_can('manage_platform'));

-- manage_event read is deliberately ORG-WIDE (single-org MVP): any manage_event
-- holder can already ISSUE guest certs at organization scope, so reading them is
-- the same trust boundary. Scope to per-event management before a second org or
-- externally-delegated event managers exist (review finding, logged P3).
DROP POLICY IF EXISTS egc_read ON public.event_guest_certificates;
CREATE POLICY egc_read ON public.event_guest_certificates
  FOR SELECT TO authenticated
  USING (
    public.rls_can('manage_platform')
    OR public.rls_can('manage_event')
    OR EXISTS (
      SELECT 1 FROM public.persons p
      WHERE p.id = event_guest_certificates.person_id AND p.auth_id = auth.uid()
    )
  );

GRANT SELECT, UPDATE ON public.event_guest_certificates TO authenticated;
REVOKE ALL ON public.event_guest_certificates FROM anon;

-- ────────────────────────────────────────────────────────────────────────────
-- 3. PDF autogen trigger — mirrors trg_certificate_pdf_autogen (p225 #281):
--    fire-and-forget pg_net POST to the shared render endpoint; same GUC secret;
--    best-effort (failures leave pdf_url NULL, recoverable via backfill script).
--    No inline -- comments inside the body (Phase C body-hash parity).
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public._trg_event_guest_cert_pdf_autogen()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_secret text;
  v_url text;
BEGIN
  IF NEW.pdf_url IS NOT NULL THEN
    RETURN NEW;
  END IF;

  v_secret := COALESCE(current_setting('app.cert_pdf_internal_secret', true), '');
  IF v_secret = '' THEN
    RAISE WARNING 'event_guest_cert_pdf_autogen: app.cert_pdf_internal_secret not configured; skipping PDF gen for guest cert % (verification_code=%)', NEW.id, NEW.verification_code;
    RETURN NEW;
  END IF;

  v_url := 'https://nucleoia.vitormr.dev/api/internal/cert-pdf-render/' || NEW.id::text;

  PERFORM net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_secret,
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('cert_id', NEW.id, 'verification_code', NEW.verification_code, 'kind', 'event_guest'),
    timeout_milliseconds := 30000
  );

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'event_guest_cert_pdf_autogen exception for guest cert % (verification_code=%): % (continuing, best-effort)',
      NEW.id, NEW.verification_code, SQLERRM;
    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public._trg_event_guest_cert_pdf_autogen() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._trg_event_guest_cert_pdf_autogen() TO postgres;

COMMENT ON FUNCTION public._trg_event_guest_cert_pdf_autogen() IS
  '#1098: AFTER INSERT trigger fn on event_guest_certificates — fire-and-forget pg_net POST to /api/internal/cert-pdf-render/<id> (endpoint resolves guest certs by id fallback). Mirrors _trg_certificate_pdf_autogen; same app.cert_pdf_internal_secret GUC; best-effort.';

DROP TRIGGER IF EXISTS trg_event_guest_cert_pdf_autogen ON public.event_guest_certificates;
CREATE TRIGGER trg_event_guest_cert_pdf_autogen
  AFTER INSERT ON public.event_guest_certificates
  FOR EACH ROW WHEN (NEW.pdf_url IS NULL)
  EXECUTE FUNCTION public._trg_event_guest_cert_pdf_autogen();

-- ────────────────────────────────────────────────────────────────────────────
-- 4. Issuance RPC — creates/reuses the persons row by lower(email) inside the org
--    (persons has NO unique on email; dedup is deliberate + ordered: rows with
--    auth_id first, then oldest). Gate: manage_event OR manage_platform.
--    consent_version is REQUIRED when a NEW person is created (LGPD Art. 7 I/8:
--    the RPC records WHICH consent instrument was captured at registration —
--    e.g. event-guest-aftershow-2026-airmeet-form — it never fabricates consent
--    silently). The event-guest prefix is enforced because the retention lane's
--    orphan-person guard keys on it.
--    The partial unique index below closes the concurrent-create race for
--    guest-created persons without touching the broader persons model.
-- ────────────────────────────────────────────────────────────────────────────

CREATE UNIQUE INDEX IF NOT EXISTS persons_event_guest_email_unique
  ON public.persons (organization_id, lower(email))
  WHERE consent_version LIKE 'event-guest%';

CREATE OR REPLACE FUNCTION public.issue_event_guest_certificate(p_data jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_person uuid;
  v_caller_member uuid;
  v_org uuid := COALESCE(NULLIF(p_data->>'organization_id','')::uuid, '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid);
  v_event record;
  v_email text;
  v_name text;
  v_person uuid;
  v_created_person boolean := false;
  v_counter uuid;
  v_counter_name text;
  v_issuer_name text;
  v_code text;
  v_cert_id uuid;
  v_title text;
  v_lang text;
  v_existing_code text;
  v_retention date;
  v_consent_version text;
BEGIN
  SELECT p.id INTO v_caller_person FROM public.persons p WHERE p.auth_id = auth.uid();
  IF v_caller_person IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF NOT (
    public.can(v_caller_person, 'manage_event', 'organization', v_org)
    OR public.can(v_caller_person, 'manage_platform', 'organization', v_org)
  ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_event or manage_platform at organization scope');
  END IF;

  SELECT m.id, m.name INTO v_caller_member, v_issuer_name FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_member IS NULL THEN
    RETURN jsonb_build_object('error', 'Caller has no members row; issued_by must be a member (renders the issuer signature)');
  END IF;

  v_email := lower(trim(p_data->>'guest_email'));
  v_name := trim(p_data->>'guest_name');
  IF v_email IS NULL OR v_email = '' OR position('@' IN v_email) = 0 THEN
    RETURN jsonb_build_object('error', 'guest_email is required (valid email)');
  END IF;
  IF v_name IS NULL OR v_name = '' THEN
    RETURN jsonb_build_object('error', 'guest_name is required');
  END IF;

  SELECT e.id, e.title, e.date INTO v_event FROM public.events e WHERE e.id = NULLIF(p_data->>'event_id','')::uuid;
  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('error', 'event not found', 'event_id', p_data->>'event_id');
  END IF;

  v_lang := COALESCE(NULLIF(p_data->>'language',''), 'pt-BR');
  v_title := COALESCE(NULLIF(trim(p_data->>'title'),''), v_event.title);
  v_retention := (v_event.date + interval '1 year')::date;

  v_counter := NULLIF(p_data->>'counter_signed_by','')::uuid;
  IF v_counter IS NOT NULL THEN
    SELECT m.name INTO v_counter_name FROM public.members m WHERE m.id = v_counter;
    IF v_counter_name IS NULL THEN
      RETURN jsonb_build_object('error', 'counter_signed_by member not found', 'counter_signed_by', v_counter);
    END IF;
  END IF;

  SELECT p.id INTO v_person
  FROM public.persons p
  WHERE p.organization_id = v_org
    AND p.anonymized_at IS NULL
    AND (
      lower(p.email) = v_email
      OR EXISTS (SELECT 1 FROM unnest(p.secondary_emails) se WHERE lower(se) = v_email)
    )
  ORDER BY (p.auth_id IS NOT NULL) DESC, p.created_at ASC
  LIMIT 1;

  IF v_person IS NULL THEN
    v_consent_version := NULLIF(trim(p_data->>'consent_version'), '');
    IF v_consent_version IS NULL OR v_consent_version NOT LIKE 'event-guest%' THEN
      RETURN jsonb_build_object(
        'error', 'consent_version is required when creating a guest person and must start with event-guest',
        'hint', 'name the consent instrument captured at registration, e.g. event-guest-aftershow-2026-airmeet-form'
      );
    END IF;
    BEGIN
      INSERT INTO public.persons (organization_id, name, email, consent_status, consent_accepted_at, consent_version)
      VALUES (v_org, v_name, v_email, 'accepted', now(), v_consent_version)
      RETURNING id INTO v_person;
      v_created_person := true;
    EXCEPTION WHEN unique_violation THEN
      SELECT p.id INTO v_person
      FROM public.persons p
      WHERE p.organization_id = v_org AND lower(p.email) = v_email
      ORDER BY p.created_at ASC
      LIMIT 1;
    END;
  END IF;

  SELECT g.verification_code INTO v_existing_code
  FROM public.event_guest_certificates g
  WHERE g.person_id = v_person AND g.event_id = v_event.id AND g.status = 'issued';
  IF v_existing_code IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'already_issued', 'verification_code', v_existing_code, 'person_id', v_person);
  END IF;

  LOOP
    v_code := 'CERT-EVT-' || to_char(now(), 'YYYY') || '-' || upper(substr(md5(random()::text), 1, 6));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.event_guest_certificates WHERE verification_code = v_code)
      AND NOT EXISTS (SELECT 1 FROM public.certificates WHERE verification_code = v_code);
  END LOOP;

  INSERT INTO public.event_guest_certificates (
    organization_id, person_id, event_id, title, description, verification_code, language,
    issued_by, counter_signed_by, counter_signed_at, content_snapshot, retention_until
  )
  VALUES (
    v_org, v_person, v_event.id, v_title, NULLIF(trim(p_data->>'description'),''), v_code, v_lang,
    v_caller_member, v_counter, CASE WHEN v_counter IS NOT NULL THEN now() END,
    jsonb_build_object(
      'guest_name', v_name,
      'event_title', v_event.title,
      'event_date', v_event.date,
      'body_copy', '1008_option_a_no_pdu',
      'issued_by_name', v_issuer_name,
      'counter_signed_by_name', v_counter_name
    ),
    v_retention
  )
  RETURNING id INTO v_cert_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
  VALUES (
    v_caller_member, 'issue_event_guest_certificate', 'event_guest_certificate', v_cert_id,
    jsonb_build_object(
      'event_id', v_event.id,
      'person_id', v_person,
      'verification_code', v_code,
      'created_person', v_created_person,
      'retention_until', v_retention
    )
  );

  RETURN jsonb_build_object(
    'ok', true,
    'certificate_id', v_cert_id,
    'verification_code', v_code,
    'person_id', v_person,
    'created_person', v_created_person,
    'retention_until', v_retention
  );
END;
$$;

REVOKE ALL ON FUNCTION public.issue_event_guest_certificate(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.issue_event_guest_certificate(jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.issue_event_guest_certificate(jsonb) TO authenticated, service_role;

COMMENT ON FUNCTION public.issue_event_guest_certificate(jsonb) IS
  '#1098: issues a participation certificate to an EXTERNAL event guest (persons-anchored; creates/reuses persons by lower(email) in org). Gate: can(manage_event|manage_platform, organization). Accepts counter_signed_by at issuance so the autogen PDF renders dual-signed in one pass. consent_version is REQUIRED (prefix event-guest) whenever a NEW person is created — it names the consent instrument captured at registration (LGPD Art. 7 I); the RPC never defaults it. p_data: {event_id, guest_name, guest_email, consent_version (required on first issuance for an email), language?, title?, description?, counter_signed_by?, organization_id?}.';

-- ────────────────────────────────────────────────────────────────────────────
-- 5. verify_certificate — SAME signature (p_code text), now resolves BOTH paths.
--    #991 invariants preserved: any miss or non-issued state (either table)
--    collapses to the same {valid:false}; no issuer/counter-signer names; anon
--    grant carried over by CREATE OR REPLACE.
--    (COMMENT precedes the CREATE so the 991 contract test's lastIndexOf header
--    scan lands on the CREATE and sees SECURITY DEFINER; the function exists
--    since migration 20260805000309, so the COMMENT is valid at this point.)
-- ────────────────────────────────────────────────────────────────────────────

COMMENT ON FUNCTION public.verify_certificate(p_code text) IS
  '#991 + #1098: public certificate verification by code across BOTH paths (member certificates + event_guest_certificates). Status-oracle-free: missing code and any non-issued status in either table return the same {valid:false}. Never returns issuer/counter-signer names (third-party PII); guest payload adds audience=event_guest + event_title.';

CREATE OR REPLACE FUNCTION public.verify_certificate(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  cert record;
  v_member_name text;
  guest record;
BEGIN
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
$$;

-- ────────────────────────────────────────────────────────────────────────────
-- 6. Retention deletion RPC (ROPA G.1) — dedicated lane, NOT the members 5y cron.
--    Dry-run by default. Real run deletes expired certs, then guest-only orphan
--    persons (auth_id IS NULL, no legacy link, event-guest consent marker, no
--    engagements, no remaining guest certs; per-row FK-violation safe), and logs
--    to admin_audit_log. Stored PDFs (certificates bucket, guests/ prefix) are
--    returned as storage_paths_to_purge for the documented DPO storage purge.
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.delete_expired_event_guest_certificates(p_dry_run boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role text := COALESCE(auth.jwt()->>'role', '');
  v_caller_person uuid;
  v_caller_member uuid;
  v_org uuid := '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid;
  v_candidates jsonb;
  v_deleted_certs jsonb := '[]'::jsonb;
  v_deleted_persons jsonb := '[]'::jsonb;
  v_skipped_persons jsonb := '[]'::jsonb;
  v_paths jsonb;
  r record;
BEGIN
  IF v_role <> 'service_role' THEN
    SELECT p.id INTO v_caller_person FROM public.persons p WHERE p.auth_id = auth.uid();
    IF v_caller_person IS NULL OR NOT public.can(v_caller_person, 'manage_platform', 'organization', v_org) THEN
      RETURN jsonb_build_object('error', 'Unauthorized: requires manage_platform or service_role');
    END IF;
    SELECT m.id INTO v_caller_member FROM public.members m WHERE m.auth_id = auth.uid();
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', g.id,
    'verification_code', g.verification_code,
    'event_id', g.event_id,
    'person_id', g.person_id,
    'retention_until', g.retention_until,
    'pdf_url', g.pdf_url
  )), '[]'::jsonb)
  INTO v_candidates
  FROM public.event_guest_certificates g
  WHERE g.retention_until < current_date;

  IF p_dry_run THEN
    RETURN jsonb_build_object('ok', true, 'dry_run', true, 'count', jsonb_array_length(v_candidates), 'candidates', v_candidates);
  END IF;

  WITH del AS (
    DELETE FROM public.event_guest_certificates g
    WHERE g.retention_until < current_date
    RETURNING g.id, g.verification_code, g.pdf_url, g.person_id
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', del.id, 'verification_code', del.verification_code, 'pdf_url', del.pdf_url, 'person_id', del.person_id
  )), '[]'::jsonb)
  INTO v_deleted_certs
  FROM del;

  FOR r IN
    SELECT DISTINCT p.id
    FROM public.persons p
    WHERE p.id IN (SELECT (elem->>'person_id')::uuid FROM jsonb_array_elements(v_deleted_certs) elem)
      AND p.auth_id IS NULL
      AND p.legacy_member_id IS NULL
      AND p.consent_version LIKE 'event-guest%'
      AND NOT EXISTS (SELECT 1 FROM public.engagements en WHERE en.person_id = p.id)
      AND NOT EXISTS (SELECT 1 FROM public.event_guest_certificates g2 WHERE g2.person_id = p.id)
  LOOP
    BEGIN
      DELETE FROM public.persons WHERE id = r.id;
      v_deleted_persons := v_deleted_persons || to_jsonb(r.id);
    EXCEPTION WHEN foreign_key_violation THEN
      v_skipped_persons := v_skipped_persons || to_jsonb(r.id);
    END;
  END LOOP;

  SELECT COALESCE(jsonb_agg(elem->>'pdf_url'), '[]'::jsonb)
  INTO v_paths
  FROM jsonb_array_elements(v_deleted_certs) elem
  WHERE elem->>'pdf_url' IS NOT NULL;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, metadata)
  VALUES (
    v_caller_member, 'lgpd_event_guest_cert_retention_deletion', 'event_guest_certificate',
    jsonb_build_object(
      'deleted_certificates', v_deleted_certs,
      'deleted_person_ids', v_deleted_persons,
      'skipped_person_ids_fk', v_skipped_persons,
      'storage_paths_to_purge', v_paths,
      'ropa_ref', 'LGPD_ROPA_PUBLIC_SURFACES.md G.1'
    )
  );

  RETURN jsonb_build_object(
    'ok', true,
    'dry_run', false,
    'deleted_count', jsonb_array_length(v_deleted_certs),
    'deleted_certificates', v_deleted_certs,
    'deleted_person_ids', v_deleted_persons,
    'skipped_person_ids_fk', v_skipped_persons,
    'storage_paths_to_purge', v_paths
  );
END;
$$;

REVOKE ALL ON FUNCTION public.delete_expired_event_guest_certificates(boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_expired_event_guest_certificates(boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.delete_expired_event_guest_certificates(boolean) TO authenticated, service_role;

COMMENT ON FUNCTION public.delete_expired_event_guest_certificates(boolean) IS
  '#1098 ROPA G.1: dedicated retention lane for event guest certificates (1 year post-event). Dry-run by default; real run deletes expired certs + guest-only orphan persons, logs to admin_audit_log, and returns storage_paths_to_purge (certificates bucket) for the documented DPO purge step. Gate: manage_platform or service_role. Deliberately OUTSIDE anonymize_inactive_members (members 5y cron).';

-- ────────────────────────────────────────────────────────────────────────────
-- 7. Sanity checks
-- ────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
  v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'event_guest_certificates' AND c.relrowsecurity;
  IF v_count <> 1 THEN
    RAISE EXCEPTION '#1098 sanity: event_guest_certificates missing or RLS not enabled (count=%)', v_count;
  END IF;

  SELECT count(*) INTO v_count FROM pg_trigger
  WHERE tgname = 'trg_event_guest_cert_pdf_autogen' AND NOT tgisinternal;
  IF v_count <> 1 THEN
    RAISE EXCEPTION '#1098 sanity: trg_event_guest_cert_pdf_autogen not registered (count=%)', v_count;
  END IF;

  SELECT count(*) INTO v_count FROM pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace
    AND p.proname IN ('issue_event_guest_certificate', 'delete_expired_event_guest_certificates');
  IF v_count <> 2 THEN
    RAISE EXCEPTION '#1098 sanity: expected 2 new RPCs, found %', v_count;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.role_table_grants
    WHERE table_schema = 'public' AND table_name = 'event_guest_certificates' AND grantee = 'anon'
  ) THEN
    RAISE EXCEPTION '#1098 sanity: anon must have NO grants on event_guest_certificates';
  END IF;
END $$;
