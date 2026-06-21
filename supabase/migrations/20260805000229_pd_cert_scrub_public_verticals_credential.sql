CREATE OR REPLACE FUNCTION public.get_public_verticals()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- Cycle4 PD-CERT scrub: o payload publico NAO expoe mais anchor_credential/credential_body
  -- (credencial PMI implicita, sem MoU/co-branding), nem partner_org (claim de parceria sem
  -- instrumento assinado), nem description (embute "ancorada na credencial PMI-X"). A FE
  -- descreve a vertical por CONTEXTO de atuacao (i18n VERTICAL_DESC). So id/title/status saem.
  SELECT COALESCE(jsonb_agg(
           jsonb_build_object(
             'id', i.id,
             'title', i.title,
             'vertical_status', i.metadata->>'status'
           )
           ORDER BY
             CASE i.metadata->>'status'
               WHEN 'open' THEN 1 WHEN 'forming' THEN 2 WHEN 'paused' THEN 3 ELSE 4 END,
             i.title
         ), '[]'::jsonb)
  FROM public.initiatives i
  WHERE i.kind = 'community_vertical'
    AND i.status = 'active';
$function$;
