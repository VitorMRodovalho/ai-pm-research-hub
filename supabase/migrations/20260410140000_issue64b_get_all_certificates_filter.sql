-- ============================================================
-- Issue #64 (follow-up): get_all_certificates was not filtering
-- volunteer_agreement → admin page at /gamification ("Gerenciar")
-- still showed all 5 TERM entries mixed with certificates.
--
-- Fix: add optional p_include_volunteer_agreements param (default false).
-- Existing frontend callers don't pass it → termos are excluded.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_all_certificates(
  p_status_filter text DEFAULT NULL,
  p_search text DEFAULT NULL,
  p_include_volunteer_agreements boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller record;
  v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND OR (
    v_caller.is_superadmin IS NOT TRUE
    AND v_caller.operational_role NOT IN ('manager', 'deputy_manager')
    AND NOT ('curator' = ANY(v_caller.designations))
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
$$;

GRANT EXECUTE ON FUNCTION public.get_all_certificates(text, text, boolean) TO authenticated;

NOTIFY pgrst, 'reload schema';
