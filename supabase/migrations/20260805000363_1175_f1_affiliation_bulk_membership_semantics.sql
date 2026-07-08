-- #1175 F1: verify_member_affiliations_bulk (vep_sync branch) conflated the VEP APPLICATION
-- status with the PMI MEMBERSHIP status: v_active := (vep_status_raw = 'Active') marks a member
-- "filiacao inativa" merely because their application sits in OfferExtended/OfferNotExtended
-- (same semantic class as #1130: VEP 'Active' = accepted offer, not membership). It also
-- persisted membership_expires_on = service_latest_end_date (end of VOLUNTEER SERVICE), not the
-- membership expiry. Measured impact (2026-07-08 live audit): 10 of 68 verified members marked
-- inactive by the 2026-07-07 batches; 7 of them have a provably current PMI membership.
--
-- Fix (vep_sync branch only; signature unchanged -> CREATE OR REPLACE preserves grants + SECDEF):
--   1. The best-match LATERAL row now also returns selection_applications.pmi_memberships
--      (enriched snapshot [{chapterName, expiryDate}] from the PMI community profile) — the
--      actual membership evidence, living on the SAME row the old code already read.
--   2. membership_active := (max parseable membership expiryDate >= CURRENT_DATE).
--   3. membership_expires_on := that max expiry (real membership expiry, renewal radar correct).
--   4. No membership evidence (no VEP row OR empty/unparseable pmi_memberships, e.g. private
--      community profile) -> member goes to the no_vep bucket for manual verification. NEVER
--      fabricate "inactive" from the application status.
-- sede_manual / self_attested branches keep the previous behavior byte-for-byte (their
-- semantics are a separate follow-up; see #1175 discussion).
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
  v_max_expiry          date;
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
    SELECT m.id, m.chapter, app.vep_status, app.service_end, app.memberships
    FROM public.members m
    LEFT JOIN LATERAL (
      -- Same best-match row as before (WHERE + ORDER BY + LIMIT 1 preserved); #1175 F1 adds
      -- the pmi_memberships snapshot — the actual membership evidence — to the projection.
      SELECT a.vep_status_raw AS vep_status, a.service_latest_end_date AS service_end,
             a.pmi_memberships AS memberships
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

    IF p_method = 'vep_sync' THEN
      -- #1175 F1: filiação = evidência de MEMBERSHIP (pmi_memberships expiryDate), nunca o
      -- status da CANDIDATURA (vep_status_raw — esse é o ciclo Submitted→OfferExtended→Active
      -- do engajamento, #1130). expiryDate chega como 'DD Mon YYYY' (ex.: '28 Feb 2027').
      SELECT max(to_date(x.elem->>'expiryDate', 'DD Mon YYYY'))
        INTO v_max_expiry
      FROM jsonb_array_elements(COALESCE(r.memberships, '[]'::jsonb)) AS x(elem)
      WHERE x.elem->>'expiryDate' ~ '^\d{1,2} [A-Za-z]{3} \d{4}$';

      IF v_max_expiry IS NULL THEN
        -- Snapshot ausente/vazio/inparseável (ex.: perfil community privado) = sem evidência
        -- de filiação → verificação manual. NÃO derivar do status da candidatura.
        v_no_vep := array_append(v_no_vep, r.id);
        CONTINUE;
      END IF;
      v_active := (v_max_expiry >= CURRENT_DATE);
    ELSE
      v_active := (r.vep_status = 'Active');
    END IF;

    INSERT INTO public.member_affiliation_verifications
      (member_id, verified_by_member_id, chapter_verified, membership_active,
       membership_expires_on, method, source_ref, verification_obs)
    VALUES
      (r.id, v_caller_id, r.chapter, v_active,
       -- #1175 F1: a expiry persistida é a da FILIAÇÃO (pmi_memberships), não a do fim do
       -- serviço voluntário (service_latest_end_date, erro do #999).
       CASE WHEN p_method = 'vep_sync' THEN v_max_expiry ELSE NULL END,
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
