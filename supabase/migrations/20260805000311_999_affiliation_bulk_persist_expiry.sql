-- #999: verify_member_affiliations_bulk (vep_sync branch) discarded the enriched membership
-- expiry, so the renewal radar (D-30 / D-7 farol in /admin/filiacao) never fired — every
-- bulk-confirmed member got membership_expires_on = NULL.
--
-- The date IS available and reliable: selection_applications.service_latest_end_date is the
-- same "Até" shown in the selection PMI tab (live 2026-07-01: populated 90/136; of 57
-- VEP-Active apps, 50 have the date and ALL 50 are in the future — 0 past → no false "expired").
-- The old FOR loop pulled only vep_status_raw via a scalar subquery and hard-coded
-- membership_expires_on = NULL.
--
-- Fix (behavior-additive, signature unchanged → CREATE OR REPLACE preserves grants + SECDEF):
--   1. LEFT JOIN LATERAL fetches vep_status_raw AND service_latest_end_date from the SAME
--      best-match application row (identical WHERE + ORDER BY + LIMIT 1 as the old scalar
--      subquery → vep_status matching is byte-for-byte preserved).
--   2. INSERT persists the date into membership_expires_on ONLY for p_method='vep_sync'
--      (the VEP-derived branch). sede_manual / self_attested keep NULL (unchanged) — the
--      VEP date is not their source of truth.
-- Consistency guard (unchanged): active/inactive is still driven by vep_status_raw='Active'
-- (authoritative); the date only feeds "vence em breve / vencida". NULL date → radar simply
-- stays dark for that member, VEP-active status intact.
CREATE OR REPLACE FUNCTION public.verify_member_affiliations_bulk(p_member_ids uuid[], p_method text DEFAULT 'vep_sync'::text, p_obs text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id           uuid;
  v_caller_designations text[];
  v_batch_ref           text;
  v_count               int := 0;
  v_ids                 uuid[] := '{}';
  v_no_vep              uuid[] := '{}';
  v_not_found           uuid[] := '{}';
  v_active              boolean;
  r                     record;
BEGIN
  SELECT m.id, m.designations INTO v_caller_id, v_caller_designations
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  IF NOT ('filiacao_director' = ANY(COALESCE(v_caller_designations, '{}'::text[])))
     AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Forbidden: requires filiacao_director designation or platform manager authority';
  END IF;

  IF p_method NOT IN ('vep_sync','sede_manual','self_attested') THEN
    RAISE EXCEPTION 'Invalid method: %', p_method;
  END IF;
  IF p_member_ids IS NULL OR cardinality(p_member_ids) = 0 THEN
    RAISE EXCEPTION 'No members supplied';
  END IF;
  IF p_obs IS NOT NULL AND char_length(p_obs) > 500 THEN
    RAISE EXCEPTION 'verification_obs exceeds 500 chars';
  END IF;

  -- Vedação de uso próprio (spec §6.2.3): o verificador não pode estar no próprio lote
  -- (auto-atribuição de pmi_id_verified). Exceção: manage_member (PM/superadmin).
  IF v_caller_id = ANY(p_member_ids) AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Forbidden: self-verification not permitted (remova seu próprio id do lote)';
  END IF;

  v_batch_ref := 'bulk:' || gen_random_uuid()::text;

  FOR r IN
    SELECT m.id, m.chapter, app.vep_status, app.service_end
    FROM public.members m
    LEFT JOIN LATERAL (
      -- Same best-match row as the previous scalar subquery (WHERE + ORDER BY + LIMIT 1
      -- preserved), now returning the enriched expiry alongside the VEP status. #999.
      SELECT a.vep_status_raw AS vep_status, a.service_latest_end_date AS service_end
      FROM public.selection_applications a
      WHERE lower(a.email) = lower(m.email) AND a.vep_status_raw IS NOT NULL
      ORDER BY a.vep_last_seen_at DESC NULLS LAST
      LIMIT 1
    ) app ON true
    WHERE m.id = ANY(p_member_ids)
  LOOP
    -- vep_sync deriva a filiação do VEP; sem registro VEP NÃO fabricamos "inativo" —
    -- reporta em no_vep_ids para verificação manual (council LOW).
    IF p_method = 'vep_sync' AND r.vep_status IS NULL THEN
      v_no_vep := array_append(v_no_vep, r.id);
      CONTINUE;
    END IF;
    v_active := (r.vep_status = 'Active');
    INSERT INTO public.member_affiliation_verifications
      (member_id, verified_by_member_id, chapter_verified, membership_active,
       membership_expires_on, method, source_ref, verification_obs)
    VALUES
      (r.id, v_caller_id, r.chapter, v_active,
       -- #999: persist the VEP-enriched expiry for the vep_sync branch so the renewal
       -- radar can fire; other methods keep NULL (the VEP date is not their source).
       CASE WHEN p_method = 'vep_sync' THEN r.service_end ELSE NULL END,
       p_method, v_batch_ref, p_obs);

    -- pmi_id_verified tracks the active/inactive status (VEP-authoritative), independent of
    -- the expiry date; the expiry only feeds the "vence em breve / vencida" radar. #999.
    UPDATE public.members
    SET pmi_id_verified = v_active, updated_at = now()
    WHERE id = r.id;

    v_count := v_count + 1;
    v_ids := array_append(v_ids, r.id);
  END LOOP;

  -- ids fornecidos que não existem como membro (council LOW: não silenciar typo de UUID)
  v_not_found := ARRAY(
    SELECT x FROM unnest(p_member_ids) x
    EXCEPT
    SELECT y FROM unnest(array_cat(v_ids, v_no_vep)) y);

  -- Trilha de leitura nominal (Art. 37) — só dos membros que existiram e tiveram PII lida
  -- (NIT: logar após o loop com ids reais, não os de entrada que podem incluir UUIDs inválidos).
  PERFORM public.log_pii_access_batch(
    array_cat(v_ids, v_no_vep),
    ARRAY['pmi_id','chapter','membership_status'],
    'affiliation_verification_bulk',
    'Diretoria de Filiação (sede) — verificação de filiação PMI em massa via VEP');

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'affiliation.verified_bulk', 'member', NULL,
    jsonb_build_object(
      'batch_ref', v_batch_ref,
      'method', p_method,
      'count', v_count,
      'member_ids', to_jsonb(v_ids),
      'no_vep_ids', to_jsonb(v_no_vep),
      'not_found_ids', to_jsonb(v_not_found)));

  RETURN jsonb_build_object(
    'ok', true,
    'count', v_count,
    'batch_ref', v_batch_ref,
    'member_ids', to_jsonb(v_ids),
    'no_vep_ids', to_jsonb(v_no_vep),
    'not_found_ids', to_jsonb(v_not_found));
END;
$function$;

NOTIFY pgrst, 'reload schema';
