-- Track Q-A Batch D — orphan recovery: privacy gates / my-* (8 fns)
--
-- Captures live bodies as-of 2026-04-25 for LGPD-relevant self-service
-- surface: privacy consent gating, TCV readiness check, self-erasure (Art.
-- 18), PII access log readers (member + admin), data review heartbeat,
-- profile updater. Bodies preserved verbatim from `pg_get_functiondef`.
-- No behavior change.
--
-- Notes:
-- - delete_my_personal_data has explicit confirmation gate (string match
--   on 'DELETAR MEUS DADOS PESSOAIS') + dual-table audit (admin_audit_log +
--   member_role_changes). Erases phone/address/city/birth_date; preserves
--   name/email/pmi_id/state/country (attribution + TCV renewal carriers).
-- - get_pii_access_log_admin gated to is_superadmin OR
--   operational_role IN (manager, deputy_manager). Note: still uses legacy
--   role-list authority gate (not can_by_member); migrating to V4 is Phase B
--   drift cleanup, not Phase A capture.
-- - update_my_profile has whitelist v_allowed_fields (15 fields). New profile
--   fields require this list extending; backlog item.

CREATE OR REPLACE FUNCTION public.accept_privacy_consent(p_version text DEFAULT 'v1.0'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  UPDATE members SET
    privacy_consent_accepted_at = now(),
    privacy_consent_version = p_version,
    data_last_reviewed_at = now(),  -- reset review timer
    updated_at = now()
  WHERE id = v_caller_id;

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'privacy_consent_accepted', 'member', v_caller_id,
    jsonb_build_object('version', p_version, 'accepted_at', now()));

  RETURN jsonb_build_object('success', true, 'version', p_version, 'accepted_at', now());
END;
$function$;

CREATE OR REPLACE FUNCTION public.check_my_privacy_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record;
  v_needs_consent boolean;
  v_needs_revalidation boolean;
  v_current_version text := 'v1.0';
BEGIN
  SELECT id, privacy_consent_accepted_at, privacy_consent_version, data_last_reviewed_at
  INTO v_member
  FROM members WHERE auth_id = auth.uid();
  IF v_member.id IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  -- Needs consent if: never accepted OR version outdated (and not the implicit backfill)
  v_needs_consent := (v_member.privacy_consent_accepted_at IS NULL)
    OR (v_member.privacy_consent_version != v_current_version AND v_member.privacy_consent_version != 'v1.0-implicit-tcv');

  -- Needs revalidation if: last review > 365 days ago
  v_needs_revalidation := v_member.data_last_reviewed_at IS NULL
    OR v_member.data_last_reviewed_at < (now() - interval '365 days');

  RETURN jsonb_build_object(
    'current_version', v_current_version,
    'accepted_version', v_member.privacy_consent_version,
    'accepted_at', v_member.privacy_consent_accepted_at,
    'last_reviewed_at', v_member.data_last_reviewed_at,
    'needs_consent', v_needs_consent,
    'needs_revalidation', v_needs_revalidation
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.check_my_tcv_readiness()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record;
  v_missing text[] := '{}';
  v_has_signed boolean;
  v_cycle int;
BEGIN
  v_cycle := EXTRACT(YEAR FROM now())::int;
  SELECT id, name, operational_role, pmi_id, phone, address, city, state, country, birth_date
  INTO v_member
  FROM members WHERE auth_id = auth.uid();
  IF v_member.id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Skip check for roles that don't require TCV (sponsors, observers, liaisons)
  IF v_member.operational_role IN ('sponsor', 'chapter_liaison', 'observer', 'candidate', 'visitor') THEN
    RETURN jsonb_build_object('applicable', false, 'reason', 'role_exempt');
  END IF;

  -- Already signed?
  SELECT EXISTS (
    SELECT 1 FROM certificates
    WHERE member_id = v_member.id AND type = 'volunteer_agreement'
      AND cycle = v_cycle AND status = 'issued'
  ) INTO v_has_signed;

  IF v_has_signed THEN
    RETURN jsonb_build_object('applicable', true, 'signed', true, 'missing_fields', '[]'::jsonb);
  END IF;

  -- Check required fields
  IF v_member.pmi_id IS NULL OR length(trim(v_member.pmi_id)) = 0 THEN
    v_missing := array_append(v_missing, 'pmi_id');
  END IF;
  IF v_member.phone IS NULL OR length(trim(v_member.phone)) = 0 THEN
    v_missing := array_append(v_missing, 'phone');
  END IF;
  IF v_member.address IS NULL OR length(trim(v_member.address)) = 0 THEN
    v_missing := array_append(v_missing, 'address');
  END IF;
  IF v_member.city IS NULL OR length(trim(v_member.city)) = 0 THEN
    v_missing := array_append(v_missing, 'city');
  END IF;
  IF v_member.state IS NULL OR length(trim(v_member.state)) = 0 THEN
    v_missing := array_append(v_missing, 'state');
  END IF;
  IF v_member.country IS NULL OR length(trim(v_member.country)) = 0 THEN
    v_missing := array_append(v_missing, 'country');
  END IF;
  IF v_member.birth_date IS NULL THEN
    v_missing := array_append(v_missing, 'birth_date');
  END IF;

  RETURN jsonb_build_object(
    'applicable', true,
    'signed', false,
    'ready_to_sign', array_length(v_missing, 1) IS NULL,
    'missing_fields', to_jsonb(coalesce(v_missing, '{}'::text[])),
    'missing_count', coalesce(array_length(v_missing, 1), 0)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_my_personal_data(p_confirm_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_cleared text[];
BEGIN
  SELECT id, name, email, phone, address, city, state, country, birth_date
  INTO v_caller
  FROM members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Safety: require explicit confirmation text to prevent accidents
  IF p_confirm_text IS NULL OR upper(trim(p_confirm_text)) != 'DELETAR MEUS DADOS PESSOAIS' THEN
    RETURN jsonb_build_object(
      'error', 'confirmation_required',
      'message', 'Confirme enviando o parâmetro p_confirm_text com o texto: DELETAR MEUS DADOS PESSOAIS',
      'warning', 'Esta ação é IRREVERSÍVEL. Limpa endereço, cidade, telefone, aniversário. Preserva nome, email, contribuições, certificados emitidos.'
    );
  END IF;

  -- Track what was cleared
  v_cleared := '{}';
  IF v_caller.phone IS NOT NULL THEN v_cleared := array_append(v_cleared, 'phone'); END IF;
  IF v_caller.address IS NOT NULL THEN v_cleared := array_append(v_cleared, 'address'); END IF;
  IF v_caller.city IS NOT NULL THEN v_cleared := array_append(v_cleared, 'city'); END IF;
  IF v_caller.birth_date IS NOT NULL THEN v_cleared := array_append(v_cleared, 'birth_date'); END IF;

  -- Clear PII (keep name, email, state, country — these are needed for attribution + TCV renewal)
  -- Keep: name, email, pmi_id, state, country, photo_url, linkedin_url, credly_url
  -- Clear: phone, address, city, birth_date
  UPDATE members SET
    phone = NULL,
    address = NULL,
    city = NULL,
    birth_date = NULL,
    updated_at = now()
  WHERE id = v_caller.id;

  -- Audit trail (mandatory for LGPD compliance)
  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller.id, 'lgpd_self_erasure', 'member', v_caller.id,
    jsonb_build_object(
      'cleared_fields', to_jsonb(v_cleared),
      'cleared_at', now(),
      'legal_basis', 'LGPD Lei 13.709/2018 Art. 18 — Direito ao esquecimento',
      'preserved', 'name, email, pmi_id, state, country, historical contributions'
    ));

  -- Audit in member_role_changes for additional trail
  INSERT INTO member_role_changes (
    member_id, change_type, field_name,
    old_value, new_value,
    effective_date, reason,
    authorized_by, executed_by
  )
  SELECT v_caller.id, 'pii_erasure', unnest(v_cleared),
    to_jsonb('[REDACTED]'::text), to_jsonb(NULL::text),
    current_date, 'LGPD self-erasure request',
    v_caller.id, v_caller.id
  WHERE array_length(v_cleared, 1) > 0;

  RETURN jsonb_build_object(
    'success', true,
    'cleared_fields', to_jsonb(v_cleared),
    'preserved', jsonb_build_array('name', 'email', 'pmi_id', 'state', 'country', 'photo_url', 'linkedin_url', 'credly_url'),
    'message', 'Dados pessoais limpos. Histórico de contribuições e certificados preservados. Para excluir completamente sua conta, contate o gestor do projeto.',
    'legal_basis', 'LGPD Lei 13.709/2018 Art. 18'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_pii_access_log(p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller_id uuid; v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'accessor_name', m.name,
    'accessor_role', m.operational_role,
    'fields_accessed', pl.fields_accessed,
    'context', pl.context,
    'reason', pl.reason,
    'accessed_at', pl.accessed_at
  ) ORDER BY pl.accessed_at DESC), '[]'::jsonb)
  INTO v_result
  FROM pii_access_log pl
  JOIN members m ON m.id = pl.accessor_id
  WHERE pl.target_member_id = v_caller_id
  LIMIT p_limit;

  RETURN jsonb_build_object('accesses', v_result, 'total_shown', jsonb_array_length(v_result));
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_pii_access_log_admin(p_target_member_id uuid DEFAULT NULL::uuid, p_accessor_id uuid DEFAULT NULL::uuid, p_days integer DEFAULT 30, p_limit integer DEFAULT 500)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller record; v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND OR (v_caller.is_superadmin IS NOT TRUE AND v_caller.operational_role NOT IN ('manager','deputy_manager')) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: admin only');
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', pl.id,
    'accessor', jsonb_build_object('id', a.id, 'name', a.name, 'role', a.operational_role),
    'target', jsonb_build_object('id', t.id, 'name', t.name, 'chapter', t.chapter),
    'fields_accessed', pl.fields_accessed,
    'context', pl.context,
    'reason', pl.reason,
    'accessed_at', pl.accessed_at
  ) ORDER BY pl.accessed_at DESC), '[]'::jsonb)
  INTO v_result
  FROM pii_access_log pl
  JOIN members a ON a.id = pl.accessor_id
  JOIN members t ON t.id = pl.target_member_id
  WHERE pl.accessed_at >= now() - (p_days || ' days')::interval
    AND (p_target_member_id IS NULL OR pl.target_member_id = p_target_member_id)
    AND (p_accessor_id IS NULL OR pl.accessor_id = p_accessor_id)
  LIMIT p_limit;

  RETURN jsonb_build_object('log', v_result, 'filters', jsonb_build_object('days', p_days, 'target', p_target_member_id, 'accessor', p_accessor_id));
END;
$function$;

CREATE OR REPLACE FUNCTION public.mark_my_data_reviewed()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  UPDATE members SET data_last_reviewed_at = now(), updated_at = now() WHERE id = v_caller_id;

  RETURN jsonb_build_object('success', true, 'reviewed_at', now());
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_my_profile(p_fields jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_allowed_fields text[] := ARRAY['name','phone','linkedin_url','credly_url','share_whatsapp','pmi_id','state','country','photo_url','signature_url','address','city','birth_date','share_address','share_birth_date'];
  v_field text;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;

  FOR v_field IN SELECT jsonb_object_keys(p_fields) LOOP
    IF NOT (v_field = ANY(v_allowed_fields)) THEN
      RETURN jsonb_build_object('error', 'Field not allowed: ' || v_field);
    END IF;
  END LOOP;

  UPDATE members SET
    name = CASE WHEN p_fields ? 'name' AND length(p_fields->>'name') >= 2 THEN p_fields->>'name' ELSE name END,
    phone = CASE WHEN p_fields ? 'phone' THEN p_fields->>'phone' ELSE phone END,
    linkedin_url = CASE WHEN p_fields ? 'linkedin_url' THEN p_fields->>'linkedin_url' ELSE linkedin_url END,
    credly_url = CASE WHEN p_fields ? 'credly_url' THEN p_fields->>'credly_url' ELSE credly_url END,
    share_whatsapp = CASE WHEN p_fields ? 'share_whatsapp' THEN (p_fields->>'share_whatsapp')::boolean ELSE share_whatsapp END,
    share_address = CASE WHEN p_fields ? 'share_address' THEN (p_fields->>'share_address')::boolean ELSE share_address END,
    share_birth_date = CASE WHEN p_fields ? 'share_birth_date' THEN (p_fields->>'share_birth_date')::boolean ELSE share_birth_date END,
    pmi_id = CASE WHEN p_fields ? 'pmi_id' THEN p_fields->>'pmi_id' ELSE pmi_id END,
    state = CASE WHEN p_fields ? 'state' THEN p_fields->>'state' ELSE state END,
    country = CASE WHEN p_fields ? 'country' THEN p_fields->>'country' ELSE country END,
    photo_url = CASE WHEN p_fields ? 'photo_url' THEN p_fields->>'photo_url' ELSE photo_url END,
    signature_url = CASE WHEN p_fields ? 'signature_url' THEN p_fields->>'signature_url' ELSE signature_url END,
    address = CASE WHEN p_fields ? 'address' THEN p_fields->>'address' ELSE address END,
    city = CASE WHEN p_fields ? 'city' THEN p_fields->>'city' ELSE city END,
    birth_date = CASE WHEN p_fields ? 'birth_date' THEN (p_fields->>'birth_date')::date ELSE birth_date END,
    profile_completed_at = CASE WHEN profile_completed_at IS NULL THEN now() ELSE profile_completed_at END,
    -- Any profile update counts as a data review
    data_last_reviewed_at = CASE WHEN array_length(ARRAY(SELECT jsonb_object_keys(p_fields)), 1) > 0 THEN now() ELSE data_last_reviewed_at END,
    updated_at = now()
  WHERE id = v_caller.id;

  RETURN jsonb_build_object('ok', true, 'updated_fields', (SELECT array_agg(k) FROM jsonb_object_keys(p_fields) k));
END;
$function$;
