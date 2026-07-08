-- #1175 F4: update_my_profile wrote ONLY members; the persons row (the V4 identity
-- primitive, ADR-0006) stayed stale — index case audited live 2026-07-08: members
-- updated 2026-07-07 23:21 (address/phone/birth_date) while persons.phone/address/
-- city/state were still NULL with updated_at = created_at (2026-07-05). Any surface
-- reading persons sees outdated PII, violating the single-source + read-through rule
-- (#1032) and the ADR-0006 bridge model (members is the bridge, persons the primitive).
--
-- Fix:
--   1. update_my_profile now DUAL-WRITES the shared PII fields to persons (via
--      members.person_id) with the same field-presence CASE semantics. Fields that do
--      not exist on persons (signature_url, allow_*_map flags) stay members-only.
--   2. One-time gap backfill persons ← members for the shared columns, NULL-fill only
--      (never overwrites a non-NULL persons value). Grounded 2026-07-08 pre-apply
--      (118 member↔person pairs): phone 35, address 43, city 44, state 38,
--      birth_date 44, linkedin_url 38, photo_url 31, credly_url 35 gaps
--      (country/pmi_id 0). Audited in admin_audit_log.

CREATE OR REPLACE FUNCTION public.update_my_profile(p_fields jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_allowed_fields text[] := ARRAY['name','phone','linkedin_url','credly_url','share_whatsapp','pmi_id','state','country','photo_url','signature_url','address','city','birth_date','share_address','share_birth_date','allow_state_in_public_map','allow_precise_location_in_public_map'];
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
    allow_precise_location_in_public_map = CASE WHEN p_fields ? 'allow_precise_location_in_public_map' THEN (p_fields->>'allow_precise_location_in_public_map')::boolean ELSE allow_precise_location_in_public_map END,
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

-- One-time gap backfill persons ← members (NULL-fill only; persons non-NULL wins —
-- forward writes now keep both in sync, this only repairs the historical drift).
DO $$
DECLARE
  v_rows int;
BEGIN
  UPDATE persons p SET
    phone        = coalesce(p.phone, m.phone),
    linkedin_url = coalesce(p.linkedin_url, m.linkedin_url),
    credly_url   = coalesce(p.credly_url, m.credly_url),
    state        = coalesce(p.state, m.state),
    country      = coalesce(p.country, m.country),
    photo_url    = coalesce(p.photo_url, m.photo_url),
    address      = coalesce(p.address, m.address),
    city         = coalesce(p.city, m.city),
    birth_date   = coalesce(p.birth_date, m.birth_date),
    updated_at   = now()
  FROM members m
  WHERE m.person_id = p.id
    AND (
      (p.phone IS NULL AND m.phone IS NOT NULL) OR
      (p.linkedin_url IS NULL AND m.linkedin_url IS NOT NULL) OR
      (p.credly_url IS NULL AND m.credly_url IS NOT NULL) OR
      (p.state IS NULL AND m.state IS NOT NULL) OR
      (p.country IS NULL AND m.country IS NOT NULL) OR
      (p.photo_url IS NULL AND m.photo_url IS NOT NULL) OR
      (p.address IS NULL AND m.address IS NOT NULL) OR
      (p.city IS NULL AND m.city IS NOT NULL) OR
      (p.birth_date IS NULL AND m.birth_date IS NOT NULL)
    );
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    (SELECT id FROM public.members WHERE email = 'vitor.rodovalho@outlook.com'),
    'persons.backfill_from_members_gap_fill', 'persons', NULL,
    jsonb_build_object(
      'issue', '#1175 F4',
      'persons_gap_filled', v_rows,
      'policy', 'NULL-fill only; persons non-NULL preserved'));
END $$;

NOTIFY pgrst, 'reload schema';
