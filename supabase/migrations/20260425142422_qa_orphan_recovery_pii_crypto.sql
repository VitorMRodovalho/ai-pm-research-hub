-- Track Q-A Batch C — orphan recovery: PII crypto helpers (3 fns)
--
-- LGPD-relevant: these wrap pgp_sym_encrypt/decrypt for PII at-rest
-- protection AND record per-row access in pii_access_log. Capturing the live
-- bodies as-of 2026-04-25 unblocks reproducibility for fresh-project deploys
-- (previously these were defined out-of-band and would not exist after a
-- clean `db reset --linked`).
--
-- Bodies preserved verbatim from `pg_get_functiondef`. No behavior change.
--
-- LGPD audit trail: log_pii_access deliberately skips self-access logging
-- (caller == target == no-op). encrypt_sensitive/decrypt_sensitive use the
-- `app.encryption_key` GUC; the key itself is set at session/role level and
-- never materialized in source. SECURITY DEFINER + auth.uid() gating in
-- log_pii_access ensures anon never writes audit rows.

CREATE OR REPLACE FUNCTION public.encrypt_sensitive(val text)
 RETURNS bytea
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN pgp_sym_encrypt(val, current_setting('app.encryption_key', true));
END;
$function$;

CREATE OR REPLACE FUNCTION public.decrypt_sensitive(val bytea)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN pgp_sym_decrypt(val, current_setting('app.encryption_key', true));
END;
$function$;

CREATE OR REPLACE FUNCTION public.log_pii_access(p_target_member_id uuid, p_fields text[], p_context text, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_accessor_id uuid;
BEGIN
  SELECT id INTO v_accessor_id FROM members WHERE auth_id = auth.uid();
  -- Don't log self-access
  IF v_accessor_id IS NULL OR v_accessor_id = p_target_member_id THEN RETURN; END IF;

  INSERT INTO pii_access_log (accessor_id, target_member_id, fields_accessed, context, reason)
  VALUES (v_accessor_id, p_target_member_id, p_fields, p_context, p_reason);
END;
$function$;
