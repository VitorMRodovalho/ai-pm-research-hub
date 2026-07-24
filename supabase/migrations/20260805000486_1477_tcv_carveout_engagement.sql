-- =====================================================================================
-- #1477: check_my_tcv_readiness — carve-out cirúrgico (rota A, ratificada owner 2026-07-24).
--
-- Problem: the TCV exemption keyed off operational_role (a single-valued DISPLAY cache
-- that collapses multi-hat members — the #1476 anti-pattern). Two chapter_liaison members
-- who ALSO hold an active operational tier via engagement were exempted from the volunteer
-- agreement but must sign it.
--
-- Route A (carve-out): a label only exempts when the member has NO operational engagement
-- (v_member_operational_tiers, the #1476 Onda 2 canonical junction). Fixes the 2 dual-hat
-- members with ZERO ripple — the 45 alumni/guest/null members (no label, no engagement)
-- stay non-exempt exactly as today. Chosen over pure-engagement (route B) because the TCV
-- is a PMI-GO contractual gate: over-inclusive is safe, under-inclusive would be a
-- compliance gap if the junction ever omitted a real operational volunteer.
--
-- Base: live body (pg_get_functiondef), only the exemption predicate changes.
-- =====================================================================================

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

  -- Skip check for roles that don't require TCV (sponsors, observers, liaisons),
  -- but ONLY when the member has no operational engagement. A dual-hat member whose
  -- display cache collapsed to an exempt label (e.g. chapter_liaison) yet holds an
  -- active operational tier via engagement must still sign (#1477, carve-out route A).
  IF v_member.operational_role IN ('sponsor', 'chapter_liaison', 'observer', 'candidate', 'visitor')
     AND NOT EXISTS (
       SELECT 1 FROM public.v_member_operational_tiers t WHERE t.member_id = v_member.id
     ) THEN
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

NOTIFY pgrst, 'reload schema';
