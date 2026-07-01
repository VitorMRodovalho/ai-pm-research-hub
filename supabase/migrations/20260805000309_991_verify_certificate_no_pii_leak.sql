-- #991 — verify_certificate: stop leaking issuer/counter-signer member NAMES and
-- collapse the status oracle on the anonymous /verify surface.
--
-- Live body (pre-fix) resolved cert.issued_by and cert.counter_signed_by to real
-- member names (typically GP / Presidência) and returned them as `issued_by` /
-- `counter_signed_by`, plus `revoked_reason` and a full status discriminant
-- (valid / revoked / rejected / superseded / not_found), to any anonymous caller
-- holding a code. That is third-party PII on a public surface (LGPD Art. 6 III
-- minimization) and contradicts the ADR-0098 "metadata-only, soft-private /verify"
-- intent.
--
-- Fix (PM decision 2026-07-01 — full collapse):
--   * Issuer / counter-signer NAMES removed; attributed to the org via a fixed
--     `authorized_by` string. Expose only `has_counter_signature` + `counter_signed_at`.
--   * Holder `member_name` KEPT — it is the cert subject, and proving the cert belongs
--     to X is the point of verification (issue #991 #2). The type-aware holder-name
--     omit for the new curation cert types is deferred to #308-B (SPEC §11 F-H5 /
--     invariant CUR_006); this migration is the base that #308-B's type-aware
--     projection builds on (one RPC, one route — SPEC §11 F-H4).
--   * Any code that is NOT a currently-issued cert (not found, revoked, rejected,
--     superseded) returns an INDISTINGUISHABLE {valid:false} — no discriminant,
--     no revoked_reason. Members still see revocation/rejection reasons on the
--     authenticated /certificates page.
--
-- Signature is unchanged (p_code text -> jsonb), so CREATE OR REPLACE preserves the
-- existing anon/authenticated/service_role EXECUTE grants (the /verify surface stays
-- anon by design). Anon-executable on the /verify PostgREST surface: NOTIFY pgrst after.
-- Ref: SPEC_308 §0.2 / §11 F-M-names, F-H5; ADR-0098; ADR-0119 Q3.

CREATE OR REPLACE FUNCTION public.verify_certificate(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  cert record;
  v_member_name text;
BEGIN
  SELECT c.* INTO cert
  FROM certificates c
  WHERE c.verification_code = p_code;

  -- Status-oracle-free: a missing code AND any non-issued status collapse to the
  -- same indistinguishable response, so the anon surface cannot be used to probe
  -- a certificate's governance state (#991 / SPEC §11 F-H5).
  -- IS DISTINCT FROM (not COALESCE(status,'issued')<>'issued') so a schema-permitted
  -- NULL status fails CLOSED (NULL IS DISTINCT FROM 'issued' = TRUE) rather than being
  -- coalesced into a false 'valid' — the CHECK constraint allows status IS NULL.
  IF cert IS NULL OR cert.status IS DISTINCT FROM 'issued' THEN
    RETURN jsonb_build_object('valid', false);
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

NOTIFY pgrst, 'reload schema';
