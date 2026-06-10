-- Migration: 20260805000140_p569_s4_council_folds_revoked_at
-- Issue: #569 Slice 4 — council folds on draft review (wf_6c6d28d8: 3/3 GO_W_FIXES, 0 blocker)
-- Predecessor: 20260805000139. Refs: ADR-0101; LGPD Art. 6º III / 7º IX / 18 II e VI; #572; mig 137.
--
-- WHAT (council folds)
--   1. revoked_at COLUMN (legal-counsel MEDIUM, LGPD Art. 6º III): the retention window was
--      anchored on updated_at (proxy) — any future admin UPDATE on a revoked declaration would
--      silently EXTEND the 5y retention of the titular's data. revoked_at is the immutable
--      anchor; _ots_retention_pass now uses COALESCE(revoked_at, updated_at) (conservative for
--      any pre-column rows; live count at ship: 0 declarations).
--   2. revoke fn: SELECT ... FOR UPDATE (security LOW — concurrent dual-revoke produced a
--      phantom audit row: both sessions read 'draft', loser's UPDATE hit 0 rows but still
--      audited); sets revoked_at; retention_note now states the LEGAL BASIS (Art. 7º IX
--      legítimo interesse probatório como exceção ao Art. 18 VI) + DPO contact (Art. 9º).
--   3. create fn: audit 'title' falls back to '[sem título]' (auditoria humana sem correlação
--      extra por UUID — legal NIT).
--   4. export_my_data: dead v_member_email dropped (security LOW); each pi_exclusion
--      declaration gains total_assets / confirmed_assets / eficacia_plena (doc7 Cl.4.1 — the
--      titular sees at once whether the declaration reached full probative efficacy, instead
--      of mis-reading per-asset 'pending' as efficacious; legal LOW). Two-step portability
--      (metadados aqui; artefato .ots via export_anexo_i) documented in-body.
--
-- ROLLBACK
--   Restore the 4 bodies from 20260805000139 (export/create/revoke) + 20260805000137
--   (_ots_retention_pass); ALTER TABLE public.pi_exclusion_declarations DROP COLUMN revoked_at;
--
-- After apply: NOTIFY pgrst, 'reload schema'.

-- ============================================================================
-- 1. revoked_at — immutable retention anchor
-- ============================================================================

ALTER TABLE public.pi_exclusion_declarations
  ADD COLUMN IF NOT EXISTS revoked_at timestamptz;

COMMENT ON COLUMN public.pi_exclusion_declarations.revoked_at IS
  '#569 S4 (LGPD Art. 6º III): immutable anchor of the 5y post-revocation retention window (mig 137 retention pass). Set ONCE by revoke_exclusion_declaration; never updated. NULL = not revoked.';

-- ============================================================================
-- 2. revoke — FOR UPDATE + revoked_at + legal-basis retention note
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

  -- FOR UPDATE (council security fold): a concurrent dual-revoke must serialize here so the
  -- loser re-reads 'revoked' and takes the idempotent path — without it both sessions read the
  -- pre-revoke status and the loser wrote a PHANTOM audit row for an UPDATE that hit 0 rows.
  SELECT declarant_member_id, status INTO v_owner, v_status
  FROM public.pi_exclusion_declarations WHERE id = p_declaration_id
  FOR UPDATE;
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
  SET status = 'revoked', revoked_at = now()
  WHERE id = p_declaration_id AND status IN ('draft', 'active');

  SELECT count(*) INTO v_assets FROM public.pi_exclusion_assets WHERE declaration_id = p_declaration_id;

  -- Assets are KEPT: the .ots proofs retain probative value (they attest digest existence at a
  -- date) through the retention window; _ots_retention_pass eliminates them 5y after revoked_at.
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (v_member_id, 'pi_exclusion.declaration_revoked', 'pi_exclusion_declaration', p_declaration_id,
          jsonb_build_object('status', jsonb_build_object('from', v_status, 'to', 'revoked')),
          jsonb_build_object('source', 'revoke_exclusion_declaration', 'assets_kept', v_assets));

  RETURN jsonb_build_object(
    'success', true,
    'declaration_id', p_declaration_id,
    'previous_status', v_status,
    'assets_kept', v_assets,
    'retention_note', 'Assets e provas .ots são mantidos por 5 anos pós-revogação com fundamento no Art. 7º, IX da LGPD (legítimo interesse probatório), como exceção ao direito de eliminação imediata do Art. 18, VI; a eliminação ocorre programaticamente ao fim do período (cron ots-retention-monthly) e esta revogação fica auditada. Dúvidas sobre o tratamento: dpo@pmigo.org.br.'
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.revoke_exclusion_declaration(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revoke_exclusion_declaration(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_exclusion_declaration(uuid) TO service_role;

-- ============================================================================
-- 3. create — audit title placeholder (human-auditable trail)
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

  -- #569 S4c (ADR-0101 deferred L58): declaration lifecycle audit. Placeholder title keeps the
  -- human audit trail readable when the declarant skipped the optional title (legal fold).
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (v_member_id, 'pi_exclusion.declaration_created', 'pi_exclusion_declaration', v_id,
          jsonb_build_object('title', COALESCE(p_title, '[sem título]')),
          jsonb_build_object('source', 'create_exclusion_declaration'));

  RETURN v_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_exclusion_declaration(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_exclusion_declaration(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_exclusion_declaration(text) TO service_role;

-- ============================================================================
-- 4. export_my_data — dead var dropped + per-declaration eficácia summary
-- ============================================================================

CREATE OR REPLACE FUNCTION public.export_my_data()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_person_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id
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
    -- proof artifact — export it via export_anexo_i por declaration_id), its PRESENCE is
    -- flagged per asset. eficacia_plena (doc7 Cl.4.1) = ALL assets confirmed — surfaced per
    -- declaration so the titular never mis-reads 'pending' as already-efficacious (legal fold).
    'pi_exclusion', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'declaration_id', d.id,
        'title', d.title,
        'status', d.status,
        'created_at', d.created_at,
        'updated_at', d.updated_at,
        'revoked_at', d.revoked_at,
        'total_assets', (SELECT count(*) FROM public.pi_exclusion_assets a WHERE a.declaration_id = d.id),
        'confirmed_assets', (SELECT count(*) FROM public.pi_exclusion_assets a WHERE a.declaration_id = d.id AND a.ots_status = 'confirmed'),
        'eficacia_plena', COALESCE((
          SELECT bool_and(a.ots_status = 'confirmed') AND count(*) > 0
          FROM public.pi_exclusion_assets a WHERE a.declaration_id = d.id
        ), false),
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
-- 5. retention pass — anchor on revoked_at (immutable), conservative fallback
-- ============================================================================

CREATE OR REPLACE FUNCTION public._ots_retention_pass(p_retention interval DEFAULT interval '5 years')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_assets_deleted integer := 0;
  v_decls_deleted  integer := 0;
BEGIN
  -- Floor the window at 1 year: a fat-fingered manual call ('1 day') must not mass-purge
  -- evidence. doc1 2.5.6 institutional windows are >= vínculo+5y; 5y is the default.
  IF p_retention < interval '1 year' THEN
    RAISE EXCEPTION '_ots_retention_pass: retention window % is below the 1-year safety floor', p_retention;
  END IF;

  -- 2a. Assets (digest + .ots bytea) of declarations revoked longer than the window.
  --     Window anchored on revoked_at (mig 140 — immutable, LGPD Art. 6º III: a later admin
  --     UPDATE can no longer silently extend the titular's retention). COALESCE(updated_at)
  --     keeps the pre-column era conservative (0 revoked declarations existed at ship time).
  WITH gone AS (
    DELETE FROM public.pi_exclusion_assets a
    USING public.pi_exclusion_declarations d
    WHERE a.declaration_id = d.id
      AND d.status = 'revoked'
      AND COALESCE(d.revoked_at, d.updated_at) < now() - p_retention
    RETURNING a.id
  )
  SELECT count(*) INTO v_assets_deleted FROM gone;

  -- 2b. The now asset-free revoked declarations themselves (eliminação irreversível).
  WITH gone AS (
    DELETE FROM public.pi_exclusion_declarations d
    WHERE d.status = 'revoked'
      AND COALESCE(d.revoked_at, d.updated_at) < now() - p_retention
      AND NOT EXISTS (SELECT 1 FROM public.pi_exclusion_assets a WHERE a.declaration_id = d.id)
    RETURNING d.id
  )
  SELECT count(*) INTO v_decls_deleted FROM gone;

  -- NOTE: 'error' assets of draft/active declarations are intentionally NOT touched — they are
  -- declarant-entered Anexo I rows (export_anexo_i surfaces them); deleting them here would be
  -- silent data loss. They leave via declarant re-registration or declaration revocation + window.

  -- Durable audit trail (council security MEDIUM): the JSON return below dies with the cron
  -- response TTL; irreversible elimination of evidence artifacts must leave a permanent row.
  -- actor_id NULL = system/cron actor. No-op passes do not log.
  IF v_assets_deleted > 0 OR v_decls_deleted > 0 THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      NULL,
      'ots.retention_pass',
      'pi_exclusion_registry',
      NULL,
      jsonb_build_object(
        'assets_deleted', v_assets_deleted,
        'declarations_deleted', v_decls_deleted
      ),
      jsonb_build_object(
        'source', '_ots_retention_pass',
        'retention_window', p_retention::text,
        'ran_at', now()
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'retention_window', p_retention::text,
    'assets_deleted', v_assets_deleted,
    'declarations_deleted', v_decls_deleted,
    'ran_at', now()
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public._ots_retention_pass(interval) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._ots_retention_pass(interval) TO service_role;

NOTIFY pgrst, 'reload schema';
