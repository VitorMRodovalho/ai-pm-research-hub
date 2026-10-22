-- #2553 PR 2 (home v2), pacote DB-3: as linhas de pesquisa da home numa leitura pública só.
--
-- D5 (GP 20/10/2026): o detalhe de cada linha abre na própria home, enquanto a camada pública de /tribe/[id] não
-- existe. Nome e quadrante de cada linha vinham de src/data/tribes.ts, e uma linha nova só aparecia com mudança de
-- código. Agora vêm de tribes (name_i18n, quadrant, quadrant_name_i18n); o texto, as entregas e o horário saem da mesma
-- fonte de get_tribe_public_profiles (#2609), e as vagas ocupadas da mesma contagem de count_tribe_slots, com a
-- capacidade de tribe_capacity_limit. Sem nome de liderança (D3: lideranças só em contagem). Só iniciativa visível
-- (rls_can_see_initiative, ADR-0105).
--
-- Lida pela PR-6 (a virada da home). Nada a lê quando a migration entra.
--
-- Rollback: DROP FUNCTION public.get_public_research_lines();

CREATE OR REPLACE FUNCTION public.get_public_research_lines()
 RETURNS TABLE(tribe_id integer, name_i18n jsonb, quadrant text, quadrant_name_i18n jsonb,
               description_i18n jsonb, deliverables_i18n jsonb, slots jsonb, members integer, capacity integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH seats AS (SELECT public.count_tribe_slots()::jsonb AS j),
       cap AS (SELECT public.tribe_capacity_limit() AS n)
  SELECT DISTINCT ON (t.id)
         t.id,
         coalesce(t.name_i18n, jsonb_build_object('pt', t.name)),
         t.quadrant,
         t.quadrant_name_i18n,
         i.description_i18n,
         i.deliverables_i18n,
         coalesce((
           SELECT jsonb_agg(jsonb_build_object('day_of_week', s.day_of_week,
                                               'time_start', s.time_start, 'time_end', s.time_end)
                            ORDER BY s.day_of_week, s.time_start)
           FROM public.tribe_meeting_slots s
           WHERE s.tribe_id = t.id AND s.is_active = true
         ), '[]'::jsonb),
         coalesce((seats.j->>t.id::text)::integer, 0),
         cap.n
  FROM public.tribes t
  JOIN public.initiatives i ON i.legacy_tribe_id = t.id AND i.kind = 'research_tribe'
  CROSS JOIN seats
  CROSS JOIN cap
  WHERE t.is_active = true
    AND coalesce(i.visibility, 'standard') <> 'confidential'
    AND public.rls_can_see_initiative(i.id)
  ORDER BY t.id, (i.status = 'active') DESC, i.updated_at DESC;
$function$;
COMMENT ON FUNCTION public.get_public_research_lines() IS
  '#2553 D5 (GP 20/10/2026): as linhas de pesquisa ativas para a home pública: nome, quadrante, texto, entregas, horário semanal e vagas ocupadas, sem nome de pessoa.';
REVOKE ALL ON FUNCTION public.get_public_research_lines() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_research_lines() TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
