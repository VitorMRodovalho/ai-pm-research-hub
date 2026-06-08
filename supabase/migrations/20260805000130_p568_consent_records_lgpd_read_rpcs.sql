-- Migration: 20260805000130_p568_consent_records_lgpd_read_rpcs
-- Issue: #568 — LGPD Art. 18 (#564 council): expose consent_records in export_my_data +
--                add list_my_consents / admin read RPC
-- Refs: #564, PR #565, GC-162, LGPD Art. 18
--
-- Context (grounded LIVE 2026-06-08 against prod ldrfrvwhxsmgaabwmaik):
--   consent_records is correctly locked (PERMISSIVE rpc_only_deny_all USING(false) +
--   RESTRICTIVE org-scope; authenticated holds only a residual SELECT grant, anon nothing).
--   The read RPCs were deferred in the arming migration's comment ("list_my_consents — futuras")
--   and never created → two LGPD Art. 18 gaps:
--     1. export_my_data() omits consent history (Art. 18 II access / V confirmation).
--     2. No canonical superadmin/GP path to audit a member's consent records.
--
-- Changes (all SECURITY DEFINER; consent_records read only via these RPCs, never direct PostgREST):
--   1) list_my_consents() — the subject's OWN consent history (auth.uid() → members.id). Returns
--      the meaningful consent fields; omits the internal integrity hashes (email/ip/user_agent).
--   2) admin_list_member_consents(p_member_id) — gated on can_by_member(view_pii); logs the
--      PII-adjacent read to pii_access_log (parity with admin_get_member_details).
--   3) export_my_data() — add a 'consent_records' key (full rows, the subject's complete record);
--      ALSO fixes a pre-existing latent bug: the engagements subquery referenced i.name on
--      public.initiatives, which the V4 refactor renamed to `title` → export_my_data RAISED
--      "column i.name does not exist" for ANY member with engagements (LGPD Art. 18 export broken).
--      Corrected to i.title. Verified live: superadmin (12 engagements) export now succeeds.
--
-- Grant posture: new functions get a Supabase auto-grant to anon via PUBLIC → REVOKE FROM PUBLIC,
-- anon and GRANT authenticated, service_role (ADR-0038/0041 pattern). DB-only; no MCP/EF surface
-- change (MCP exposure, if wanted, is a separate follow-up).
--
-- Rollback:
--   DROP FUNCTION public.list_my_consents();
--   DROP FUNCTION public.admin_list_member_consents(uuid);
--   -- restore export_my_data() to the pre-#568 body (without the consent_records key).
--
-- After apply: NOTIFY pgrst, 'reload schema' (two new RPCs on the PostgREST surface).

-- ============================================================================
-- 1) list_my_consents() — subject self-read (LGPD Art. 18 II/V)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.list_my_consents()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_member_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', cr.id,
    'policy_type', cr.policy_type,
    'policy_version', cr.policy_version,
    'policy_document_id', cr.policy_document_id,
    'accepted_at', cr.accepted_at,
    'channel', cr.channel,
    'revoked_at', cr.revoked_at,
    'revocation_reason', cr.revocation_reason,
    'is_active', (cr.revoked_at IS NULL),
    'created_at', cr.created_at
  ) ORDER BY cr.accepted_at DESC), '[]'::jsonb)
  INTO v_result
  FROM public.consent_records cr
  WHERE cr.member_id = v_member_id;

  RETURN v_result;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.list_my_consents() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_my_consents() TO authenticated, service_role;

-- ============================================================================
-- 2) admin_list_member_consents(p_member_id) — view_pii-gated audit read + access log
-- ============================================================================
CREATE OR REPLACE FUNCTION public.admin_list_member_consents(p_member_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_org_id uuid;
  v_target_org_id uuid;
  v_result jsonb;
BEGIN
  SELECT m.id, m.organization_id INTO v_caller_id, v_caller_org_id
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'view_pii') THEN
    RAISE EXCEPTION 'Access denied: requires view_pii permission (LGPD-sensitive data)';
  END IF;

  -- Multi-tenant fence (CRITICAL): SECDEF bypasses the RESTRICTIVE org-scope RLS policy, and
  -- can_by_member('view_pii') is satisfied by the caller holding view_pii in ANY engagement —
  -- it does NOT bound the TARGET. Re-enforce org isolation here.
  SELECT m.organization_id INTO v_target_org_id FROM public.members m WHERE m.id = p_member_id;
  IF v_target_org_id IS NULL OR v_caller_org_id IS NULL OR v_target_org_id <> v_caller_org_id THEN
    RAISE EXCEPTION 'Access denied: target member not in caller organization';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', cr.id,
    'member_id', cr.member_id,
    'application_id', cr.application_id,
    'policy_type', cr.policy_type,
    'policy_version', cr.policy_version,
    'policy_document_id', cr.policy_document_id,
    'accepted_at', cr.accepted_at,
    'channel', cr.channel,
    -- capture-evidence hashes (pseudonymized) — relevant to a consent audit; view_pii-gated + logged.
    'email_hash', cr.email_hash,
    'ip_hash', cr.ip_hash,
    'user_agent_hash', cr.user_agent_hash,
    'revoked_at', cr.revoked_at,
    'revocation_reason', cr.revocation_reason,
    'is_active', (cr.revoked_at IS NULL),
    'created_at', cr.created_at
  ) ORDER BY cr.accepted_at DESC), '[]'::jsonb)
  INTO v_result
  FROM public.consent_records cr
  WHERE cr.member_id = p_member_id
    AND cr.organization_id = v_caller_org_id;

  -- Accountability (Art. 37): log EVERY admin read of consent history, incl. self-reads via this path.
  INSERT INTO public.pii_access_log (accessor_id, target_member_id, fields_accessed, context, reason, accessed_at)
  VALUES (v_caller_id, p_member_id, ARRAY['consent_history']::text[], 'admin_list_member_consents', 'consent audit', now());

  RETURN v_result;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.admin_list_member_consents(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_member_consents(uuid) TO authenticated, service_role;

-- ============================================================================
-- 3) export_my_data() — add consent_records to the LGPD Art. 18 export payload
-- (full body re-created with the new 'consent_records' key before 'exported_at')
-- ============================================================================
CREATE OR REPLACE FUNCTION public.export_my_data()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_member_email text;
  v_person_id uuid;
  v_result jsonb;
BEGIN
  SELECT id, email INTO v_member_id, v_member_email
  FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT id INTO v_person_id FROM public.persons WHERE legacy_member_id = v_member_id;

  SELECT jsonb_build_object(
    'profile', (SELECT row_to_json(m)::jsonb FROM public.members m WHERE m.id = v_member_id),
    'person', CASE WHEN v_person_id IS NOT NULL THEN
      (SELECT row_to_json(p)::jsonb FROM public.persons p WHERE p.id = v_person_id)
    ELSE NULL END,
    'engagements', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', e.id, 'kind', e.kind, 'role', e.role, 'status', e.status,
        'initiative_name', i.title, 'start_date', e.start_date, 'end_date', e.end_date,
        'legal_basis', e.legal_basis, 'has_agreement', (e.agreement_certificate_id IS NOT NULL),
        'granted_at', e.granted_at, 'revoked_at', e.revoked_at, 'revoke_reason', e.revoke_reason
      ) ORDER BY e.start_date DESC)
      FROM public.engagements e LEFT JOIN public.initiatives i ON i.id = e.initiative_id
      WHERE e.person_id = v_person_id
    ), '[]'::jsonb),
    'attendance', COALESCE((SELECT jsonb_agg(row_to_json(a)::jsonb) FROM public.attendance a WHERE a.member_id = v_member_id), '[]'::jsonb),
    'gamification', COALESCE((SELECT jsonb_agg(row_to_json(g)::jsonb) FROM public.gamification_points g WHERE g.member_id = v_member_id), '[]'::jsonb),
    'notifications', COALESCE((SELECT jsonb_agg(row_to_json(n)::jsonb) FROM public.notifications n WHERE n.recipient_id = v_member_id), '[]'::jsonb),
    'board_assignments', COALESCE((SELECT jsonb_agg(row_to_json(ba)::jsonb) FROM public.board_item_assignments ba WHERE ba.member_id = v_member_id), '[]'::jsonb),
    'cycle_history', COALESCE((SELECT jsonb_agg(row_to_json(mch)::jsonb) FROM public.member_cycle_history mch WHERE mch.member_id = v_member_id), '[]'::jsonb),
    'certificates', COALESCE((SELECT jsonb_agg(row_to_json(c)::jsonb) FROM public.certificates c WHERE c.member_id = v_member_id), '[]'::jsonb),
    'selection_applications', COALESCE((
      SELECT jsonb_agg(row_to_json(sa)::jsonb)
      FROM public.selection_applications sa
      WHERE lower(trim(sa.email)) IN (
        SELECT lower(trim(m.email::text))  FROM public.members m        WHERE m.id = v_member_id         AND m.email IS NOT NULL
        UNION
        SELECT lower(trim(me.email::text)) FROM public.member_emails me WHERE me.member_id = v_member_id AND me.email IS NOT NULL
      )
    ), '[]'::jsonb),
    'onboarding', COALESCE((SELECT jsonb_agg(row_to_json(op)::jsonb) FROM public.onboarding_progress op WHERE op.member_id = v_member_id), '[]'::jsonb),
    'consent_records', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', cr.id,
        'policy_type', cr.policy_type,
        'policy_version', cr.policy_version,
        'policy_document_id', cr.policy_document_id,
        'accepted_at', cr.accepted_at,
        'channel', cr.channel,
        'email_hash', cr.email_hash,
        'ip_hash', cr.ip_hash,
        'user_agent_hash', cr.user_agent_hash,
        'revoked_at', cr.revoked_at,
        'revocation_reason', cr.revocation_reason,
        'is_active', (cr.revoked_at IS NULL),
        'created_at', cr.created_at
      ) ORDER BY cr.accepted_at DESC)
      FROM public.consent_records cr WHERE cr.member_id = v_member_id
    ), '[]'::jsonb),
    'exported_at', now()
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

-- export_my_data is CREATE OR REPLACE: re-assert the intended ACL explicitly (do not rely on
-- ACL preservation — on a fresh DB the auto PUBLIC/anon grant would otherwise leak the export).
REVOKE EXECUTE ON FUNCTION public.export_my_data() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.export_my_data() TO authenticated, service_role;
