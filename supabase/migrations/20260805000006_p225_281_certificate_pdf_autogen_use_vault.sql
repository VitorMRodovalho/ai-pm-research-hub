-- p225 #281 follow-up — Refactor _trg_certificate_pdf_autogen to read shared secret
-- from Supabase Vault (vault.decrypted_secrets) instead of GUC.
--
-- Why this migration exists:
--   Original migration 20260805000005 used `current_setting('app.cert_pdf_internal_secret', true)`
--   to read the trigger-Worker shared secret. In Supabase managed Postgres, custom
--   GUCs under the `app.*` namespace require allowlist enrollment to be ALTER'able
--   via `ALTER DATABASE postgres SET`. Attempting that command returns:
--     ERROR: 42501: permission denied to set parameter "app.cert_pdf_internal_secret"
--
--   Path forward: Supabase Vault (extension `supabase_vault` v0.3.1, installed by
--   default on all Supabase projects). Provides `vault.create_secret(value, name, desc)`
--   to insert encrypted secrets, and `vault.decrypted_secrets` view for SECDEF
--   readers to retrieve the cleartext. Encryption at rest is automatic.
--
-- Sediment SEDIMENT-225.B (carry to P162 close):
--   In Supabase managed PG, `ALTER DATABASE ... SET app.*` is blocked for non-allowlisted
--   params. Use `vault.create_secret(...)` for any cross-session/cross-process secret
--   that needs to persist (pg_net background workers cannot read session-level GUCs).
--   Do NOT design trigger fns around `current_setting('app.*')` for managed PG without
--   verifying the param is on the Supabase allowlist (e.g., `pgrst.*`, `pgsodium.*`).
--
-- Operator setup (post-merge of this migration):
--   1. Generate secret value:  openssl rand -base64 32
--   2. Set in Worker:          npx wrangler secret put CERT_PDF_INTERNAL_SECRET
--   3. Set in Vault (Studio):  SELECT vault.create_secret('<same_value>', 'cert_pdf_internal_secret', 'p225 #281 ADR-0098: shared secret for AFTER INSERT trigger → /api/internal/cert-pdf-render');
--   4. Confirm:                SELECT name, length(decrypted_secret) FROM vault.decrypted_secrets WHERE name = 'cert_pdf_internal_secret';
--
-- Rotation (future):
--   1. Update wrangler secret to new value (Worker)
--   2. UPDATE vault.secrets SET secret = vault.encrypt('<new_value>', key_id) WHERE name = 'cert_pdf_internal_secret';
--   (or DELETE + vault.create_secret in same tx for atomicity)
--
-- Rollback (if needed):
--   To revert: ship a new CREATE-OR-REPLACE-FUNCTION migration restoring the prior
--   body (note: example code intentionally avoided here to prevent the body-drift
--   parser from matching this comment as a second function definition — sediment
--   SEDIMENT-225.C: parser regex matches CREATE FUNCTION inside SQL comments).
--   Or to disable trigger entirely:
--     DROP TRIGGER IF EXISTS trg_certificate_pdf_autogen ON public.certificates;
--
-- Cross-ref: ADR-0098, migration 20260805000005 (initial trigger ship), p225 #281,
--   sediment SEDIMENT-225.A (Postgres -- strip from prosrc).

CREATE OR REPLACE FUNCTION public._trg_certificate_pdf_autogen()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, vault
AS $$
DECLARE
  v_secret text;
  v_url text;
BEGIN
  IF NEW.pdf_url IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets
  WHERE name = 'cert_pdf_internal_secret'
  LIMIT 1;

  IF v_secret IS NULL OR v_secret = '' THEN
    RAISE WARNING 'cert_pdf_autogen: vault secret "cert_pdf_internal_secret" not configured; skipping PDF gen for cert % (verification_code=%)', NEW.id, NEW.verification_code;
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

COMMENT ON FUNCTION public._trg_certificate_pdf_autogen() IS
  'p225 #281 (vault refactor 20260805000006): AFTER INSERT trigger fn on public.certificates — fires fire-and-forget pg_net POST to /api/internal/cert-pdf-render/<id>. Reads shared secret from vault.decrypted_secrets (name=cert_pdf_internal_secret) — Supabase managed PG blocks ALTER DATABASE SET app.* per SEDIMENT-225.B. Best-effort: exceptions logged as WARNING, never block insert. See ADR-0098.';

-- Sanity check: trigger still references the updated fn body via the same name
DO $$
DECLARE
  v_fn_count int;
  v_body_uses_vault boolean;
BEGIN
  SELECT count(*) INTO v_fn_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = '_trg_certificate_pdf_autogen';
  IF v_fn_count <> 1 THEN
    RAISE EXCEPTION 'p225 #281 vault refactor: _trg_certificate_pdf_autogen function missing (count=%)', v_fn_count;
  END IF;

  SELECT (p.prosrc ILIKE '%vault.decrypted_secrets%') INTO v_body_uses_vault
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = '_trg_certificate_pdf_autogen';
  IF NOT v_body_uses_vault THEN
    RAISE EXCEPTION 'p225 #281 vault refactor: fn body does not reference vault.decrypted_secrets (likely the new CREATE OR REPLACE did not stick)';
  END IF;
END $$;
