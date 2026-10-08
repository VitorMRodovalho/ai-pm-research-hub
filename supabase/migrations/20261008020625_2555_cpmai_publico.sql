-- #2555: a vitrine do grupo de estudos CPMAI tem uma leitura publica.
--
-- /cpmai esta no menu Explorar do visitante, mas a pagina lia so get_cpmai_course_dashboard(), que devolve
-- {"error":"Not authenticated"} a quem nao e membro, porque mistura o curso com a inscricao, o progresso e as notas
-- da propria pessoa. Esta funcao devolve so o curso: titulo, descricao, status e os dominios com nome e peso. Nada
-- de metadata solta (o metadata do grupo tem o link do grupo de WhatsApp) e nada da pessoa. A RLS das tabelas nao
-- muda (decisao de arquitetura 6). Decisao do GP de 08/10/2026.

CREATE OR REPLACE FUNCTION public.get_public_cpmai_course()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $function$
  SELECT jsonb_build_object(
    'course', jsonb_build_object('id', i.id, 'title', i.title, 'description', i.description, 'status', i.status),
    'domains', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', d->>'id',
        'domain_number', (d->>'domain_number')::int,
        'weight_pct', (d->>'weight_pct')::numeric,
        'name_pt', d->>'name_pt',
        'name_en', d->>'name_en',
        'name_es', d->>'name_es'
      ) ORDER BY (d->>'sort_order')::int)
      FROM jsonb_array_elements(COALESCE(i.metadata->'domains', '[]'::jsonb)) d
    ), '[]'::jsonb)
  )
  FROM public.initiatives i
  WHERE i.kind = 'study_group' AND i.status <> 'archived'
    AND NOT public.is_confidential_initiative(i.id)
  ORDER BY i.created_at DESC
  LIMIT 1;
$function$;

REVOKE ALL ON FUNCTION public.get_public_cpmai_course() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_cpmai_course() TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
