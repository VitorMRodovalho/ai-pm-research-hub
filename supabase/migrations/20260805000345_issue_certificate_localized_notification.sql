-- issue_certificate: localize the recipient notification title + body by the certificate's
-- language instead of the hardcoded English "Certificate Issued: " / "You received a certificate: ".
-- The prefix leaked into the in-app notification AND (via TYPE_SUBJECTS[type] || notif.title
-- fallback in send-notification-email) into the email subject, forcing manual PT normalization on
-- every issuance. Body-only CREATE OR REPLACE — same signature, only the create_notification args
-- change; derives the locale from the cert's own language field (pt-BR default), no hardcoded lang.
-- Cross-ref: handoff 2026-07-05 cert follow-up; issue_certificate captured at p200 (20260519183819).

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

  -- Notify the recipient member (localized by the certificate's language — pt-BR default)
  PERFORM create_notification(
    v_member_id,
    'certificate_issued',
    CASE COALESCE(p_data->>'language','pt-BR')
      WHEN 'en-US' THEN 'Certificate Issued: '
      WHEN 'es-LATAM' THEN 'Certificado emitido: '
      ELSE 'Certificado emitido: '
    END || COALESCE(p_data->>'title', 'Certificate'),
    CASE COALESCE(p_data->>'language','pt-BR')
      WHEN 'en-US' THEN 'You received a certificate: '
      WHEN 'es-LATAM' THEN 'Recibiste un certificado: '
      ELSE 'Você recebeu um certificado: '
    END || COALESCE(p_data->>'title', ''),
    '/gamification',
    'certificate',
    v_cert_id
  );

  RETURN jsonb_build_object('success', true, 'certificate_id', v_cert_id, 'verification_code', v_code, 'member_name', v_member_name);
END; $function$;

NOTIFY pgrst, 'reload schema';
