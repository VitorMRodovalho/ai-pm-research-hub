-- #1024: admin write-pair for #729. The read-branch (get_member_comms_card →
-- image_consent_revoked, #729/mig 314) honors an image_voice_publicity revocation, but
-- under the current Cláusula-11 regime there was NO write path to RECORD an externally
-- communicated revocation (self-service revoke_image_voice_consent only updates an active
-- opt-in row, and nobody has opted in). LGPD Art. 18 VI ("facilitated revocation") was met
-- in text, not operationally. This RPC lets GP/DPO record a communicated revocation so the
-- read-branch is reachable and the honoring is demonstrable to the ANPD.
--
-- Security review (security-engineer, APPROVE_WITH_CONDITIONS) applied: F1 cross-org IDOR
-- guard, F2 revoked_at carries the member's communicated date (p_effective_at) — NOT
-- accepted_at (which becomes a nominal sentinel; the issue's original accepted_at=p_effective_at
-- produced accepted==revoked==now() and left the legally-relevant date off the ledger),
-- F4 future-date guard, F5 free-text bound, F6 member_not_found raises, F7 COMMENT.
--
-- ⚠️ Legal: the Cláusula-11 implicit-authorization representation (and the revised date
-- semantics) is legal-vetted in shape (#1024) but a licensed lawyer must confirm before the
-- RPC is wired into the UI / ratified. This migration ships the mechanism; the legal sign-off
-- is a human gate. Race hardening (unique partial index / dedup) tracked as a follow-up.
CREATE OR REPLACE FUNCTION public.gp_record_image_consent_revocation(
  p_member_id uuid,
  p_reason text DEFAULT NULL::text,
  p_source text DEFAULT NULL::text,
  p_effective_at timestamptz DEFAULT now()
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller      uuid;
  v_caller_org  uuid;
  v_org         uuid;
  v_reason      text;
  v_effective   timestamptz;
  v_consent_id  uuid;
  v_revoked_at  timestamptz;
  v_was_insert  boolean := false;
  v_doc_id      uuid;
  v_doc_version text;
  v_version     text;
BEGIN
  -- Gate: GP/DPO (manage_member) — the SECDEF boundary. anon/PUBLIC is REVOKED below.
  SELECT id, organization_id INTO v_caller, v_caller_org
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_caller, 'manage_member') THEN
    RAISE EXCEPTION 'access_denied: manage_member required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- F4: a communicated revocation cannot take effect in the future (1h skew tolerance).
  -- A future revoked_at would masquerade as active to `revoked_at IS NULL` checks.
  v_effective := COALESCE(p_effective_at, now());
  IF v_effective > now() + interval '1 hour' THEN
    RAISE EXCEPTION 'p_effective_at cannot be in the future' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- F5: bound free-text (COMMENT warns callers not to embed PII in p_reason/p_source).
  IF char_length(COALESCE(p_reason, '')) > 500 OR char_length(COALESCE(p_source, '')) > 255 THEN
    RAISE EXCEPTION 'p_reason/p_source too long' USING ERRCODE = 'string_data_right_truncation';
  END IF;

  -- F1: target must belong to the caller's org (no cross-org IDOR); F6: absent → raise.
  SELECT organization_id INTO v_org FROM public.members WHERE id = p_member_id;
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'member_not_found' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_org IS DISTINCT FROM v_caller_org THEN
    RAISE EXCEPTION 'access_denied: target member outside caller org' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_reason := COALESCE(NULLIF(p_reason, ''), 'GP-recorded externally-communicated revocation (Termo Cláusula 11)');

  -- Idempotency (mirror revoke_image_voice_consent): if an active opt-in exists, revoke THAT
  -- row at the communicated effective date; otherwise insert a row born revoked.
  UPDATE public.consent_records
     SET revoked_at = v_effective,
         revocation_reason = v_reason
   WHERE member_id = p_member_id
     AND policy_type = 'image_voice_publicity'
     AND revoked_at IS NULL
  RETURNING id, revoked_at INTO v_consent_id, v_revoked_at;

  IF v_consent_id IS NULL THEN
    -- Provenance: current Adendo Retificativo (Art. 8-A image/voice basis), mirroring
    -- grant_image_voice_consent's version resolution. policy_version is NOT NULL.
    SELECT id, version INTO v_doc_id, v_doc_version
    FROM public.governance_documents
    WHERE doc_type = 'volunteer_addendum'
    ORDER BY effective_from DESC NULLS LAST, created_at DESC
    LIMIT 1;
    v_version := COALESCE(v_doc_version, 'unversioned');

    -- F2: accepted_at is a nominal sentinel (no per-member opt-in timestamp exists under the
    -- implicit Cláusula-11 basis; provenance lives in the audit log). revoked_at carries the
    -- legally-relevant communicated date. channel='admin_attestation' (the only admin-recorded
    -- channel allowed by consent_records_channel_check).
    INSERT INTO public.consent_records (
      member_id, policy_type, policy_version, policy_document_id, channel,
      accepted_at, revoked_at, revocation_reason, organization_id
    ) VALUES (
      p_member_id, 'image_voice_publicity', v_version, v_doc_id, 'admin_attestation',
      now(), v_effective, v_reason, v_org
    )
    RETURNING id, revoked_at INTO v_consent_id, v_revoked_at;
    v_was_insert := true;
  END IF;

  -- Demonstrability trail (LGPD Art. 18 VI): source + effective_at + who + when.
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller, 'image_voice_consent_revoked_by_admin', 'member', p_member_id,
    jsonb_build_object(
      'consent_id', v_consent_id, 'policy_type', 'image_voice_publicity',
      'revoked_at', v_revoked_at, 'revocation_reason', v_reason,
      'source', p_source, 'effective_at', v_effective,
      'was_insert', v_was_insert));

  RETURN jsonb_build_object(
    'success', true, 'consent_id', v_consent_id, 'revoked_at', v_revoked_at,
    'was_insert', v_was_insert, 'is_active', false);
END;
$function$;

COMMENT ON FUNCTION public.gp_record_image_consent_revocation(uuid, text, text, timestamptz) IS
  '#1024 write-pair for #729. GP/DPO (manage_member) records an externally-communicated image_voice_publicity revocation for LGPD Art. 18 VI demonstrability. revoked_at carries p_effective_at (the member''s communicated date); accepted_at is a nominal sentinel. p_source/p_reason MUST NOT contain PII (emails, names) — use opaque channel ids (email/whatsapp/written_request). Legal: the Clausula-11 implicit-authorization representation needs licensed-lawyer sign-off before UI wiring / ratification.';

-- #965 drift avoidance: never anon-reachable; authority is the can_by_member gate inside.
REVOKE ALL ON FUNCTION public.gp_record_image_consent_revocation(uuid, text, text, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gp_record_image_consent_revocation(uuid, text, text, timestamptz) TO authenticated, service_role;
