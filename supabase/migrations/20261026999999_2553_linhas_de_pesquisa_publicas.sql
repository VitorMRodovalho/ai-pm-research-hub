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
-- (1) name_i18n das linhas 9 a 15. Medido pela orquestradora em 22/10/2026: as 7 estão com tribes.name_i18n nulo, e
--     os nomes em en e es moravam só nos dicionários (data.tribeN.name). Os textos abaixo são os dos 3 dicionários
--     nessa data, os mesmos que a home mostra hoje. Aborta se não forem exatamente 7 linhas nulas; a auditoria guarda
--     o tribes.name de cada uma, para comparar com o pt.
-- (2) get_public_research_lines().
--
-- Rollback: DROP FUNCTION public.get_public_research_lines(); name_i18n = NULL nas linhas da auditoria
--   tribes.name_i18n_filled.

-- ── (1) nome nos 3 idiomas ────────────────────────────────────────────────────────────────────────────────────
DO $do$
DECLARE
  v_rows    integer;
  v_before  jsonb;
BEGIN
  SELECT jsonb_object_agg(t.id, t.name) INTO v_before
  FROM public.tribes t WHERE t.id BETWEEN 9 AND 15 AND t.name_i18n IS NULL;

  UPDATE public.tribes t SET name_i18n = jsonb_build_object('pt', n.pt, 'en', n.en, 'es', n.es)
  FROM (VALUES
      (9, 'IA em Projetos & Indústria da Construção', 'AI in Projects & the Construction Industry', 'IA en Proyectos & Industria de la Construcción'),
      (10, 'Governança Assistida', 'Assisted Governance', 'Gobernanza Asistida'),
      (11, 'PMO Inteligente', 'Intelligent PMO', 'PMO Inteligente'),
      (12, 'Produtividade Aumentada', 'Augmented Productivity', 'Productividad Aumentada'),
      (13, 'Dados em Projetos de IA', 'Data in AI Projects', 'Datos en Proyectos de IA'),
      (14, 'Fluência em IA', 'AI Literacy', 'Fluidez en IA'),
      (15, 'Segundo Cérebro & Comunicação de Times', 'Second Brain & Team Communication', 'Segundo Cerebro & Comunicación de Equipos')
  ) AS n(id, pt, en, es)
  WHERE t.id = n.id AND t.name_i18n IS NULL;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 7 THEN
    RAISE EXCEPTION '#2553 linhas: esperava 7 linhas (9 a 15) com name_i18n nulo, achei %', v_rows;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, changes, metadata)
  VALUES (NULL, 'tribes.name_i18n_filled', 'tribes',
          jsonb_build_object('tribe_ids', jsonb_build_array(9, 10, 11, 12, 13, 14, 15), 'name_before', v_before),
          jsonb_build_object('issue', '#2553', 'source', 'migration',
                             'decision', 'GP 20/10/2026 (D5): a home lê o nome da linha do banco, nos 3 idiomas'));
END;
$do$;

-- ── (2) a leitura pública ─────────────────────────────────────────────────────────────────────────────────────

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
