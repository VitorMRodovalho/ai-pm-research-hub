-- Migration: 20260805000139_p569_s4c_export_my_data_pi_exclusion_audit_revoke
-- Issue: #569 Slice 4c (ADR-0101 deferred items, lines 57-58) + lifecycle completion
-- Refs: LGPD Art. 18 II (portabilidade); ADR-0101; #572 (retention program); doc7 Cl.4.1.
--       Bodies regenerated from LIVE prosrc (2026-06-10) — export_my_data has a documented
--       drift history (20260411230500 + Q-C batch3): NEVER edit from a stale file capture.
--
-- WHAT
--   1. export_my_data() — new 'pi_exclusion' section (declarant's declarations + Anexo I
--      assets: digest/status/anchor metadata + proof PRESENCE flag). The .ots bytea itself
--      is NOT inlined (binary; portability of the proof artifact = export_anexo_i's job);
--      the registry METADATA is the personal data Art. 18 II covers.
--   2. create_exclusion_declaration() — admin_audit_log row on create (ADR-0101 deferred
--      line 58: declaration lifecycle audit).
--   3. NEW revoke_exclusion_declaration(p_declaration_id) — the 'revoked' status was
--      UNREACHABLE (no RPC sets it; register guards against it; _ots_retention_pass purges
--      it — dead path until now). Owner-only (declarant), terminal (draft|active → revoked),
--      audited. Assets are KEPT (evidence retains probative value through the retention
--      window; _ots_retention_pass eliminates them 5y after revocation — mig 137). Pipeline
--      note: already-registered unstamped assets keep stamping after revoke — harmless
--      (digest-only, idempotent) and the proof still attests digest existence; revisit only
--      if calendar volume ever matters.
--
-- ROLLBACK
--   DROP FUNCTION public.revoke_exclusion_declaration(uuid);
--   -- restore export_my_data from its pre-139 live capture (this file's body minus the
--   --   'pi_exclusion' block) and create_exclusion_declaration from 20260805000135.
--
-- After apply: NOTIFY pgrst, 'reload schema'.

-- ============================================================================
-- 1. export_my_data — Art. 18 II portability gains the PI-exclusion registry
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
    -- #569 S4c (ADR-0101 deferred L57): the declarant's PI-exclusion registry — LGPD Art. 18 II
    -- portability. Digest/status/anchor METADATA only; the .ots bytea is not inlined (binary
    -- proof artifact — exported via export_anexo_i), its PRESENCE is flagged per asset.
    'pi_exclusion', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'declaration_id', d.id,
        'title', d.title,
        'status', d.status,
        'created_at', d.created_at,
        'updated_at', d.updated_at,
        'assets', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'seq', a.seq,
            'titulo', a.title,
            'natureza', a.nature,
            'autor_capitulo', a.author_label,
            'data_criacao', a.work_created_on,
            'caminho_url', a.source_ref,
            'sha256', a.sha256,
            'status', a.ots_status,
            'prova_ots', (a.ots_proof IS NOT NULL),
            'ancoragem', CASE WHEN a.ots_status = 'confirmed'
              THEN jsonb_build_object('bloco', a.bitcoin_block, 'utc', a.attested_at) ELSE NULL END
          ) ORDER BY a.seq)
          FROM public.pi_exclusion_assets a WHERE a.declaration_id = d.id
        ), '[]'::jsonb)
      ) ORDER BY d.created_at DESC)
      FROM public.pi_exclusion_declarations d WHERE d.declarant_member_id = v_member_id
    ), '[]'::jsonb),
    'exported_at', now()
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.export_my_data() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.export_my_data() TO authenticated;
GRANT EXECUTE ON FUNCTION public.export_my_data() TO service_role;

-- ============================================================================
-- 2. create_exclusion_declaration — lifecycle audit on create
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_exclusion_declaration(p_title text DEFAULT NULL::text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_org_id    uuid;
  v_id        uuid;
BEGIN
  SELECT id, organization_id INTO v_member_id, v_org_id FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  INSERT INTO public.pi_exclusion_declarations (organization_id, declarant_member_id, title, created_by)
  VALUES (v_org_id, v_member_id, p_title, auth.uid())
  RETURNING id INTO v_id;

  -- #569 S4c (ADR-0101 deferred L58): declaration lifecycle audit.
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (v_member_id, 'pi_exclusion.declaration_created', 'pi_exclusion_declaration', v_id,
          jsonb_build_object('title', p_title),
          jsonb_build_object('source', 'create_exclusion_declaration'));

  RETURN v_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_exclusion_declaration(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_exclusion_declaration(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_exclusion_declaration(text) TO service_role;

-- ============================================================================
-- 3. revoke_exclusion_declaration — completes the lifecycle (status was unreachable)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.revoke_exclusion_declaration(p_declaration_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_owner     uuid;
  v_status    text;
  v_assets    integer;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT declarant_member_id, status INTO v_owner, v_status
  FROM public.pi_exclusion_declarations WHERE id = p_declaration_id;
  IF v_owner IS NULL THEN RAISE EXCEPTION 'Declaration not found'; END IF;

  -- Owner-only v1: revocation is the DECLARANT's own act (the declaration is their unilateral
  -- statement). Fiscalization reads stay on export_anexo_i (view_pii + org fence); an admin
  -- revocation path, if ever needed, is a deliberate later decision — not the default here.
  IF v_owner <> v_member_id THEN
    RAISE EXCEPTION 'Access denied: only the declarant can revoke their declaration';
  END IF;

  IF v_status = 'revoked' THEN
    RETURN jsonb_build_object('success', true, 'already_revoked', true, 'declaration_id', p_declaration_id);
  END IF;

  UPDATE public.pi_exclusion_declarations
  SET status = 'revoked'
  WHERE id = p_declaration_id AND status IN ('draft', 'active');

  SELECT count(*) INTO v_assets FROM public.pi_exclusion_assets WHERE declaration_id = p_declaration_id;

  -- Assets are KEPT: the .ots proofs retain probative value (they attest digest existence at a
  -- date) through the retention window; _ots_retention_pass (mig 137) eliminates them 5y after
  -- revocation (anchored on updated_at — see the forward-guard there / #572).
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (v_member_id, 'pi_exclusion.declaration_revoked', 'pi_exclusion_declaration', p_declaration_id,
          jsonb_build_object('status', jsonb_build_object('from', v_status, 'to', 'revoked')),
          jsonb_build_object('source', 'revoke_exclusion_declaration', 'assets_kept', v_assets));

  RETURN jsonb_build_object(
    'success', true,
    'declaration_id', p_declaration_id,
    'previous_status', v_status,
    'assets_kept', v_assets,
    'retention_note', 'Assets e provas .ots permanecem pelo período de retenção (eliminação programada via ots-retention-monthly, 5 anos pós-revogação).'
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.revoke_exclusion_declaration(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revoke_exclusion_declaration(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_exclusion_declaration(uuid) TO service_role;

NOTIFY pgrst, 'reload schema';
