-- #2556: o consentimento de localizacao precisa no mapa publico ganha prova e um lugar para ser pedido.
--
-- Medido em 08/10/2026: o consentimento era so members.allow_precise_location_in_public_map (booleano), sem data
-- nem texto exibido, e so podia ser dado numa caixa do /profile. Na equipe de pesquisa (v_operational_members),
-- 25 de 80 nao tinham nenhum consentimento de mapa e 4 so o antigo (agregado, k>=3).
-- Decisao do GP de 08/10/2026 (opcao C): o pedido vira um cartao na home do membro, o "agora nao" fica no banco
-- e cada autorizacao e revogacao entra no ledger consent_records (LGPD art. 8, par. 2: o onus da prova do
-- consentimento e do controlador). O texto exibido e o rotulo ja aprovado (parecer legal-counsel 25/06/2026),
-- sem mudanca. As RPCs seguem o desenho de grant/revoke_image_voice_consent (#570).
-- Os consentimentos dados antes desta migration NAO ganham linha retroativa: nao ha evidencia de quando nem de
-- qual texto foi exibido, e uma linha inventada seria dado sintetico.

-- 1) "agora nao": data em que o membro dispensou o pedido
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS public_map_prompt_dismissed_at timestamptz;

-- 2) tipo de consentimento novo no ledger (mantem todos os anteriores)
ALTER TABLE public.consent_records DROP CONSTRAINT consent_records_policy_type_check;
ALTER TABLE public.consent_records ADD CONSTRAINT consent_records_policy_type_check
  CHECK (policy_type = ANY (ARRAY[
    'privacy_policy'::text,
    'volunteer_term'::text,
    'ai_analysis'::text,
    'communication_preferences'::text,
    'cookies'::text,
    'image_voice_publicity'::text,
    'public_map_location'::text,
    'other'::text
  ]));

-- 3) o cartao aparece? So para quem esta na equipe de pesquisa, sem consentimento preciso e sem ter dispensado.
CREATE OR REPLACE FUNCTION public.get_my_public_map_prompt()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_m public.members%ROWTYPE;
BEGIN
  SELECT * INTO v_m FROM public.members WHERE auth_id = auth.uid();
  IF v_m.id IS NULL THEN
    RETURN jsonb_build_object('show', false);
  END IF;
  RETURN jsonb_build_object(
    'show', EXISTS (SELECT 1 FROM public.v_operational_members o WHERE o.id = v_m.id)
            AND NOT COALESCE(v_m.allow_precise_location_in_public_map, false)
            AND v_m.public_map_prompt_dismissed_at IS NULL,
    'legacy_only', COALESCE(v_m.allow_state_in_public_map, false)
                   AND NOT COALESCE(v_m.allow_precise_location_in_public_map, false)
  );
END;
$function$;

-- 4) autorizar: liga a flag e grava a prova (idempotente: um consentimento ativo nao e duplicado)
CREATE OR REPLACE FUNCTION public.grant_public_map_consent(p_evidence jsonb DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_org_id uuid;
  v_version constant text := 'pd-map-precise-2026-06-25';
  v_evidence jsonb;
  v_active_id uuid;
  v_new_id uuid;
BEGIN
  SELECT id, organization_id INTO v_member_id, v_org_id
  FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE public.members SET allow_precise_location_in_public_map = true WHERE id = v_member_id;

  SELECT id INTO v_active_id
  FROM public.consent_records
  WHERE member_id = v_member_id AND policy_type = 'public_map_location' AND revoked_at IS NULL
  ORDER BY accepted_at DESC
  LIMIT 1;
  IF v_active_id IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'already_active', true, 'consent_id', v_active_id, 'is_active', true);
  END IF;

  -- So as chaves que descrevem onde e como o texto foi exibido; nada livre vindo do cliente.
  v_evidence := jsonb_strip_nulls(jsonb_build_object(
    'surface', NULLIF(p_evidence ->> 'surface', ''),
    'lang', NULLIF(p_evidence ->> 'lang', ''),
    'label_key', 'profile.allowPreciseLocationMapLabel'
  ));

  INSERT INTO public.consent_records (
    member_id, policy_type, policy_version, accepted_at, channel, evidence, organization_id
  ) VALUES (
    v_member_id, 'public_map_location', v_version, now(), 'platform_action', v_evidence, v_org_id
  ) RETURNING id INTO v_new_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member_id, 'public_map_consent_granted', 'member', v_member_id,
    jsonb_build_object('consent_id', v_new_id, 'policy_type', 'public_map_location', 'policy_version', v_version));

  RETURN jsonb_build_object('success', true, 'already_active', false, 'consent_id', v_new_id, 'is_active', true);
END;
$function$;

-- 5) revogar: desliga a flag e marca a linha ativa como revogada (nunca apaga; a revogacao vale dali em diante)
CREATE OR REPLACE FUNCTION public.revoke_public_map_consent(p_reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_revoked_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE public.members SET allow_precise_location_in_public_map = false WHERE id = v_member_id;

  UPDATE public.consent_records
     SET revoked_at = now(),
         revocation_reason = COALESCE(NULLIF(p_reason, ''), 'member self-service revocation')
   WHERE member_id = v_member_id AND policy_type = 'public_map_location' AND revoked_at IS NULL
  RETURNING id INTO v_revoked_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member_id, 'public_map_consent_revoked', 'member', v_member_id,
    jsonb_build_object('consent_id', v_revoked_id, 'policy_type', 'public_map_location'));

  RETURN jsonb_build_object('success', true, 'revoked_consent_id', v_revoked_id, 'is_active', false);
END;
$function$;

-- 6) "agora nao"
CREATE OR REPLACE FUNCTION public.dismiss_public_map_prompt()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.members SET public_map_prompt_dismissed_at = now() WHERE id = v_member_id;
  RETURN jsonb_build_object('success', true);
END;
$function$;

-- 7) update_my_profile deixa de aceitar allow_precise_location_in_public_map: o consentimento preciso passa so
--    por grant/revoke_public_map_consent, que gravam a prova. Corpo identico ao vivo, menos o campo.
CREATE OR REPLACE FUNCTION public.update_my_profile(p_fields jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_allowed_fields text[] := ARRAY['name','phone','linkedin_url','credly_url','share_whatsapp','pmi_id','state','country','photo_url','signature_url','address','city','birth_date','share_address','share_birth_date','allow_state_in_public_map'];
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
    allow_state_in_public_map = CASE WHEN p_fields ? 'allow_state_in_public_map' THEN (p_fields->>'allow_state_in_public_map')::boolean ELSE allow_state_in_public_map END,
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

  -- #1175 F4 (ADR-0006): dual-write the shared PII fields to the persons primitive so
  -- identity surfaces never read stale data. Same presence semantics as the members
  -- UPDATE above; persons-absent fields (signature_url, allow_*_map) are members-only.
  IF v_caller.person_id IS NOT NULL THEN
    UPDATE persons SET
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
      address = CASE WHEN p_fields ? 'address' THEN p_fields->>'address' ELSE address END,
      city = CASE WHEN p_fields ? 'city' THEN p_fields->>'city' ELSE city END,
      birth_date = CASE WHEN p_fields ? 'birth_date' THEN (p_fields->>'birth_date')::date ELSE birth_date END,
      updated_at = now()
    WHERE id = v_caller.person_id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'updated_fields', (SELECT array_agg(k) FROM jsonb_object_keys(p_fields) k));
END;
$function$;

REVOKE ALL ON FUNCTION public.get_my_public_map_prompt() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.grant_public_map_consent(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.revoke_public_map_consent(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.dismiss_public_map_prompt() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_public_map_prompt() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.grant_public_map_consent(jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.revoke_public_map_consent(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.dismiss_public_map_prompt() TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
