-- p200 (OPP-196.E, ADR-0087 §2 Batch B, 2026-05-19): V4 swap
-- `NOT ('curator' = ANY(designations))` → `NOT can_by_member('curate_content')`
-- in 3 cert fns. Pattern preserves logical inversion (curator is exception
-- to the manager-only gate).
--
-- Functions touched:
--   get_all_certificates — list + summary view (admin/PM/curator gated)
--   issue_certificate    — admin/PM/curator can issue
--   update_certificate   — admin/PM/curator can edit
--
-- All 3 use CREATE OR REPLACE FUNCTION (same signature; idempotent).

CREATE OR REPLACE FUNCTION public.get_all_certificates(p_status_filter text DEFAULT NULL::text, p_search text DEFAULT NULL::text, p_include_volunteer_agreements boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  -- p200 ADR-0087: curator V3 designation → V4 can_by_member('curate_content')
  IF NOT FOUND OR (
    v_caller.is_superadmin IS NOT TRUE
    AND v_caller.operational_role NOT IN ('manager', 'deputy_manager')
    AND NOT public.can_by_member(v_caller.id, 'curate_content')
  ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'total', count(*) FILTER (WHERE p_include_volunteer_agreements OR c.type != 'volunteer_agreement'),
      'issued', count(*) FILTER (WHERE c.status = 'issued' AND (p_include_volunteer_agreements OR c.type != 'volunteer_agreement')),
      'draft', count(*) FILTER (WHERE c.status = 'draft' AND (p_include_volunteer_agreements OR c.type != 'volunteer_agreement')),
      'revoked', count(*) FILTER (WHERE c.status = 'revoked' AND (p_include_volunteer_agreements OR c.type != 'volunteer_agreement')),
      'downloaded', count(*) FILTER (WHERE c.downloaded_at IS NOT NULL AND (p_include_volunteer_agreements OR c.type != 'volunteer_agreement'))
    ),
    'certificates', (
      SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.issued_at DESC), '[]'::jsonb)
      FROM (
        SELECT
          c2.id, c2.type, c2.title, c2.description,
          c2.cycle, c2.period_start, c2.period_end,
          c2.function_role, c2.language, c2.status,
          c2.verification_code, c2.pdf_url,
          c2.issued_at, c2.downloaded_at,
          c2.revoked_at, c2.revoked_reason,
          c2.updated_at,
          c2.issued_by,
          m.name AS member_name, m.photo_url AS member_photo,
          m.chapter AS member_chapter,
          ib.name AS issued_by_name
        FROM certificates c2
        JOIN members m ON m.id = c2.member_id
        LEFT JOIN members ib ON ib.id = c2.issued_by
        WHERE (p_status_filter IS NULL OR c2.status = p_status_filter)
          AND (p_include_volunteer_agreements OR c2.type != 'volunteer_agreement')
          AND (p_search IS NULL OR p_search = '' OR
            m.name ILIKE '%' || p_search || '%' OR
            c2.title ILIKE '%' || p_search || '%' OR
            c2.verification_code ILIKE '%' || p_search || '%'
          )
        ORDER BY c2.issued_at DESC
      ) t
    )
  ) INTO v_result
  FROM certificates c;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.issue_certificate(p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller record; v_cert_id uuid; v_code text; v_member_name text; v_member_id uuid;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  -- p200 ADR-0087: curator V3 designation → V4 can_by_member('curate_content')
  IF NOT FOUND OR (v_caller.is_superadmin IS NOT TRUE AND v_caller.operational_role NOT IN ('manager','deputy_manager') AND NOT public.can_by_member(v_caller.id, 'curate_content')) THEN
    RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  v_member_id := (p_data->>'member_id')::uuid;
  SELECT name INTO v_member_name FROM members WHERE id = v_member_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Member not found'); END IF;
  v_code := 'CERT-' || extract(year FROM now())::text || '-' || upper(substr(md5(random()::text), 1, 6));
  INSERT INTO certificates (member_id, type, title, description, cycle, period_start, period_end, function_role, language, issued_by, verification_code, issued_at)
  VALUES (v_member_id, COALESCE(p_data->>'type','participation'), p_data->>'title', p_data->>'description',
    COALESCE((p_data->>'cycle')::int, 3), p_data->>'period_start', p_data->>'period_end', p_data->>'function_role',
    COALESCE(p_data->>'language','pt-BR'), v_caller.id, v_code, now())
  RETURNING id INTO v_cert_id;

  -- Notify the recipient member
  PERFORM create_notification(
    v_member_id,
    'certificate_issued',
    'Certificate Issued: ' || COALESCE(p_data->>'title', 'Certificate'),
    'You received a certificate: ' || COALESCE(p_data->>'title', ''),
    '/gamification',
    'certificate',
    v_cert_id
  );

  RETURN jsonb_build_object('success', true, 'certificate_id', v_cert_id, 'verification_code', v_code, 'member_name', v_member_name);
END; $function$;

CREATE OR REPLACE FUNCTION public.update_certificate(p_cert_id uuid, p_updates jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  -- p200 ADR-0087: curator V3 designation → V4 can_by_member('curate_content')
  IF NOT FOUND OR (
    v_caller.is_superadmin IS NOT TRUE
    AND v_caller.operational_role NOT IN ('manager', 'deputy_manager')
    AND NOT public.can_by_member(v_caller.id, 'curate_content')
  ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  UPDATE certificates SET
    title = COALESCE(p_updates->>'title', title),
    description = COALESCE(p_updates->>'description', description),
    type = COALESCE(p_updates->>'type', type),
    period_start = COALESCE(p_updates->>'period_start', period_start),
    period_end = COALESCE(p_updates->>'period_end', period_end),
    function_role = COALESCE(p_updates->>'function_role', function_role),
    language = COALESCE(p_updates->>'language', language),
    cycle = COALESCE((p_updates->>'cycle')::int, cycle),
    updated_at = now()
  WHERE id = p_cert_id AND status != 'revoked';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Certificate not found or revoked');
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$function$;

NOTIFY pgrst, 'reload schema';
