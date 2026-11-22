-- #3169: captura em migration o corpo vivo de classify_entry_chapter.
-- O corpo no ar divergia da ultima captura (20260805000386). Esta migration grava o corpo
-- vivo byte a byte, sem mudar o comportamento. ACL e comentario ficam como estao.
CREATE OR REPLACE FUNCTION public.classify_entry_chapter(p_pmi_memberships jsonb, p_community_profile_private boolean, p_pmi_data_fetched_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_codes text[];
BEGIN
  SELECT array_agg(DISTINCT code ORDER BY code) INTO v_codes
  FROM (
    SELECT public.resolve_br_chapter_code(m->>'chapterName') AS code,
           m->>'expiryDate' AS exp
    FROM jsonb_array_elements(COALESCE(p_pmi_memberships, '[]'::jsonb)) AS m
  ) x
  WHERE code IS NOT NULL
    AND (
      exp IS NULL
      OR exp !~ '^\s*\d{1,2}\s+[A-Za-z]{3,}\s+\d{4}\s*$'
      OR to_date(exp, 'DD Mon YYYY') >= CURRENT_DATE
    );

  IF v_codes IS NOT NULL AND array_length(v_codes, 1) >= 1 THEN
    RETURN jsonb_build_object(
      'bucket', CASE WHEN array_length(v_codes, 1) > 1 THEN 'ambiguous' ELSE 'resolved' END,
      'active_br_codes', to_jsonb(v_codes)
    );
  END IF;

  RETURN jsonb_build_object(
    'bucket', CASE
      WHEN COALESCE(p_community_profile_private, false) THEN 'profile_private'
      WHEN p_pmi_data_fetched_at IS NULL              THEN 'no_fetch'
      ELSE 'not_affiliated'
    END,
    'active_br_codes', '[]'::jsonb
  );
END;
$function$;
