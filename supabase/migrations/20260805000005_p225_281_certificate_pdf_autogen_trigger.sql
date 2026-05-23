-- p225 #281 — Forward auto-gen of certificate PDFs via DB trigger + CF Browser Rendering
--
-- Architecture: AFTER INSERT trigger on public.certificates fires fire-and-forget
-- net.http_post to Astro endpoint /api/internal/cert-pdf-render/<id>, which uses
-- Cloudflare Browser Rendering binding to render the same HTML template as the
-- backfill script (scripts/backfill-cert-pdfs.ts, p221 #267 alpha) → zero visual
-- drift between stored and member-print PDFs.
--
-- Hook strategy: trigger gates on WHEN(NEW.pdf_url IS NULL), so manual UPDATE
-- of pdf_url (e.g. after admin upload via dashboard or backfill script) silently
-- skips. Idempotent by design — re-running the backfill script after this lands
-- is also a no-op.
--
-- Shared secret: app.cert_pdf_internal_secret GUC must be set via
-- `ALTER DATABASE postgres SET app.cert_pdf_internal_secret = '<value>'`
-- before this trigger can issue HTTP calls. Same value must be set as
-- CERT_PDF_INTERNAL_SECRET via `npx wrangler secret put`. Missing/empty secret
-- = trigger logs WARNING and returns NEW (insert succeeds, no PDF generated).
-- This separation lets ops rotate secrets safely (set DB GUC first → set Worker
-- secret next → roll DB GUC to new value).
--
-- Best-effort semantics: any exception in net.http_post is caught and logged
-- as WARNING; INSERT is never rolled back due to PDF gen failure. Failed cases
-- can be recovered by re-running scripts/backfill-cert-pdfs.ts.
--
-- Cross-ref: ADR-0098, P162 #189 (RESOLVED-281), p221 PR #282 (backfill alpha),
-- p221 migration 20260805000000 (bucket creation), src/lib/certificates/pdf.ts,
-- src/pages/api/internal/cert-pdf-render/[id].ts.
--
-- Rollback (if needed):
--   DROP TRIGGER IF EXISTS trg_certificate_pdf_autogen ON public.certificates;
--   DROP FUNCTION IF EXISTS public._trg_certificate_pdf_autogen();
--   ALTER DATABASE postgres RESET app.cert_pdf_internal_secret;
--
-- After apply: NOTIFY pgrst, 'reload schema' is NOT required (no PostgREST surface change).

CREATE OR REPLACE FUNCTION public._trg_certificate_pdf_autogen()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
-- Function body design notes (kept outside body to preserve Phase C body-hash parity;
-- Postgres strips inline `--` comments from prosrc, so any `--` inside the body would
-- cause md5(prosrc) ≠ md5(file body) drift — see sediment p225 below):
--   * Defense in depth: trigger WHEN clause already gates pdf_url IS NULL; we still
--     check here in case the trigger is re-fired (e.g. via UPDATE) in a future iteration.
--   * Shared secret read from DB-level GUC `app.cert_pdf_internal_secret` (set via
--     ALTER DATABASE SET). Empty/unset → log WARNING + skip; insert still succeeds.
--   * net.http_post is fire-and-forget; pg_net background worker processes async.
--     If endpoint returns 200 it UPDATEs certificates.pdf_url on its own; otherwise
--     cert stays pdf_url=NULL and can be re-generated via scripts/backfill-cert-pdfs.ts.

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
    RAISE WARNING 'cert_pdf_autogen: app.cert_pdf_internal_secret not configured; skipping PDF gen for cert % (verification_code=%)', NEW.id, NEW.verification_code;
    RETURN NEW;
  END IF;

  v_url := 'https://nucleoia.vitormr.dev/api/internal/cert-pdf-render/' || NEW.id::text;

  PERFORM net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_secret,
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('cert_id', NEW.id, 'verification_code', NEW.verification_code),
    timeout_milliseconds := 30000
  );

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'cert_pdf_autogen exception for cert % (verification_code=%): % (continuing — best-effort)',
      NEW.id, NEW.verification_code, SQLERRM;
    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public._trg_certificate_pdf_autogen() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._trg_certificate_pdf_autogen() TO postgres;

COMMENT ON FUNCTION public._trg_certificate_pdf_autogen() IS
  'p225 #281: AFTER INSERT trigger fn on public.certificates — fires fire-and-forget pg_net POST to /api/internal/cert-pdf-render/<id> for forward auto-gen of stored PDF via CF Browser Rendering. Shared secret via current_setting(app.cert_pdf_internal_secret). Best-effort: exceptions logged as WARNING, never block insert. See ADR-0098.';

DROP TRIGGER IF EXISTS trg_certificate_pdf_autogen ON public.certificates;
CREATE TRIGGER trg_certificate_pdf_autogen
  AFTER INSERT ON public.certificates
  FOR EACH ROW WHEN (NEW.pdf_url IS NULL)
  EXECUTE FUNCTION public._trg_certificate_pdf_autogen();

COMMENT ON TRIGGER trg_certificate_pdf_autogen ON public.certificates IS
  'p225 #281: forward auto-gen of stored PDF on cert insert. Gated by WHEN(NEW.pdf_url IS NULL) for idempotency — bulk_issue/admin paths that set pdf_url explicitly are skipped.';

-- Sanity check: trigger registered + function exists
DO $$
DECLARE
  v_trigger_count int;
  v_fn_count int;
BEGIN
  SELECT count(*) INTO v_trigger_count
  FROM pg_trigger
  WHERE tgname = 'trg_certificate_pdf_autogen' AND NOT tgisinternal;
  IF v_trigger_count <> 1 THEN
    RAISE EXCEPTION 'p225 #281 sanity: trg_certificate_pdf_autogen not registered (count=%)', v_trigger_count;
  END IF;

  SELECT count(*) INTO v_fn_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = '_trg_certificate_pdf_autogen';
  IF v_fn_count <> 1 THEN
    RAISE EXCEPTION 'p225 #281 sanity: _trg_certificate_pdf_autogen function missing (count=%)', v_fn_count;
  END IF;
END $$;
