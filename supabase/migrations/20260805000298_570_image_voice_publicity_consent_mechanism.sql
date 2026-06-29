-- #570 — Autonomous image/voice publicity consent: opt-in / revoke MECHANISM (build-ahead).
--
-- Origin: Parecer 01/2026 rec (e); Adendo Retificativo (doc5) "Art. 8-A" [net-new clause, gated];
--         Termo (doc2) Cláusula 11 + Parágrafo único (current image-consent basis + revocation rule).
--
-- Model shift: the image/voice publicity consent moves from "implicit on Term adhesion (Cláusula 11)"
-- to an AUTONOMOUS, dissociated, revocable-anytime opt-in recorded in the immutable consent_records
-- ledger. This migration is the FIRST writer to consent_records (read RPCs landed in #568; the table
-- was armed RPC-only in p107 `20260516780000`).
--
-- SCOPE HERE = MECHANISM ONLY. The public clause text (Adendo "Art. 8-A") and the member-facing UI are
-- the GO-LIVE, gated on legal G12 (LGPD Art. 11 sign-off) per council decision 2026-06-08 (legalops
-- triage). The RPCs ship dormant (no caller wires them yet) → behavior-neutral until go-live.
--
-- Retrofit (issue AC): existing volunteers are NOT backfilled. A Term/Cláusula-11 signature does NOT
-- presume this consent — it requires a new express opt-in. (No INSERT/backfill anywhere below.)

-- ── 1) Admit the new autonomous policy_type into the consent_records CHECK (sole definition: p107) ──
ALTER TABLE public.consent_records DROP CONSTRAINT consent_records_policy_type_check;
ALTER TABLE public.consent_records ADD CONSTRAINT consent_records_policy_type_check
  CHECK (policy_type = ANY (ARRAY[
    'privacy_policy'::text,
    'volunteer_term'::text,
    'ai_analysis'::text,
    'communication_preferences'::text,
    'cookies'::text,
    'image_voice_publicity'::text,   -- #570: autonomous image/voice publicity opt-in (Parecer 01/2026 rec e)
    'other'::text
  ]));

-- ── 2) grant_image_voice_consent — member self-service active opt-in (FIRST consent_records writer) ──
CREATE OR REPLACE FUNCTION public.grant_image_voice_consent(p_evidence jsonb DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_org_id uuid;
  v_doc_id uuid;
  v_doc_version text;
  v_version text;
  v_active public.consent_records%ROWTYPE;
  v_new_id uuid;
BEGIN
  -- Autonomous: resolve the authenticated member directly; NOT predicated on Term adhesion.
  SELECT id, organization_id INTO v_member_id, v_org_id
  FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Provenance: current Adendo Retificativo (carries Art. 8-A) — best-effort, nullable FK.
  SELECT id, version INTO v_doc_id, v_doc_version
  FROM public.governance_documents
  WHERE doc_type = 'volunteer_addendum'
  ORDER BY effective_from DESC NULLS LAST, created_at DESC
  LIMIT 1;

  -- policy_version is NOT NULL: prefer the exact clause version the member was shown (evidence),
  -- else the resolved Adendo version, else a sentinel.
  v_version := COALESCE(NULLIF(p_evidence ->> 'displayed_version', ''), v_doc_version, 'unversioned');

  -- Idempotent active opt-in: an existing ACTIVE consent is returned as-is (never duplicated).
  SELECT * INTO v_active
  FROM public.consent_records
  WHERE member_id = v_member_id
    AND policy_type = 'image_voice_publicity'
    AND revoked_at IS NULL
  ORDER BY accepted_at DESC
  LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'success', true, 'already_active', true,
      'consent_id', v_active.id, 'policy_type', 'image_voice_publicity',
      'policy_version', v_active.policy_version, 'accepted_at', v_active.accepted_at,
      'is_active', true);
  END IF;

  -- New acceptance row (immutable ledger; a re-consent after a revoke is a NEW row, not an un-revoke).
  INSERT INTO public.consent_records (
    member_id, policy_type, policy_version, policy_document_id,
    accepted_at, channel, ip_hash, user_agent_hash, organization_id
  ) VALUES (
    v_member_id, 'image_voice_publicity', v_version, v_doc_id,
    now(), 'platform_action',
    NULLIF(p_evidence ->> 'ip_hash', ''),
    NULLIF(p_evidence ->> 'user_agent_hash', ''),
    v_org_id
  ) RETURNING id INTO v_new_id;

  -- Accountability (LGPD Art. 37): mirror accept_privacy_consent's audit trail.
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member_id, 'image_voice_consent_granted', 'member', v_member_id,
    jsonb_build_object('consent_id', v_new_id, 'policy_type', 'image_voice_publicity',
                       'policy_version', v_version, 'policy_document_id', v_doc_id, 'accepted_at', now()));

  RETURN jsonb_build_object(
    'success', true, 'already_active', false,
    'consent_id', v_new_id, 'policy_type', 'image_voice_publicity',
    'policy_version', v_version, 'accepted_at', now(), 'is_active', true);
END;
$function$;

-- ── 3) revoke_image_voice_consent — member self-service revoke (NO retroactive effect) ──
--    Mirrors Termo Cláusula 11 Parágrafo único: ceases NEW uses; preserves already-published material
--    (LGPD Art. 8º §5º). Revocation is recorded on the active row; the row is never deleted.
CREATE OR REPLACE FUNCTION public.revoke_image_voice_consent(p_reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_revoked_id uuid;
  v_revoked_at timestamptz;
  v_reason text;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_reason := COALESCE(NULLIF(p_reason, ''), 'member self-service revocation');

  UPDATE public.consent_records
     SET revoked_at = now(),
         revocation_reason = v_reason
   WHERE member_id = v_member_id
     AND policy_type = 'image_voice_publicity'
     AND revoked_at IS NULL
  RETURNING id, revoked_at INTO v_revoked_id, v_revoked_at;

  IF v_revoked_id IS NULL THEN
    RETURN jsonb_build_object('success', true, 'no_active_consent', true, 'is_active', false);
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member_id, 'image_voice_consent_revoked', 'member', v_member_id,
    jsonb_build_object('consent_id', v_revoked_id, 'policy_type', 'image_voice_publicity',
                       'revoked_at', v_revoked_at, 'revocation_reason', v_reason));

  RETURN jsonb_build_object(
    'success', true, 'no_active_consent', false,
    'consent_id', v_revoked_id, 'revoked_at', v_revoked_at, 'is_active', false);
END;
$function$;

-- ── 4) Grants: member-facing, authenticated only (anti-open-relay posture, cf. #568 / #963) ──
REVOKE ALL ON FUNCTION public.grant_image_voice_consent(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.grant_image_voice_consent(jsonb) FROM anon;
REVOKE ALL ON FUNCTION public.revoke_image_voice_consent(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.revoke_image_voice_consent(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.grant_image_voice_consent(jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.revoke_image_voice_consent(text) TO authenticated, service_role;

COMMENT ON FUNCTION public.grant_image_voice_consent(jsonb) IS
  '#570 autonomous image/voice publicity opt-in (Parecer 01/2026 rec e; Adendo Art. 8-A). Dissociated from Term adhesion; idempotent; FIRST consent_records writer. NO backfill of existing signers. Go-live (clause text + UI) gated on legal G12 (LGPD Art. 11).';
COMMENT ON FUNCTION public.revoke_image_voice_consent(text) IS
  '#570 image/voice publicity consent revocation — no retroactive effect (ceases NEW uses, preserves published material; mirrors Termo Cláusula 11 Parágrafo único / LGPD Art. 8º §5º).';
