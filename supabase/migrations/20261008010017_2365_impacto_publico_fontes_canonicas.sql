-- #2365: get_public_impact_data passa a ler as fontes canonicas que a home ja usa.
--
-- O /about le esta RPC, e quatro numeros divergiam da home na mesma visita:
--   chapters        signed (assinados)            -> engaged (assinados + em negociacao), decisao do GP de 03/10/2026;
--                   o valor anterior continua em chapters_signed.
--   active_members  members ativos no ciclo        -> v_operational_members (ADR-0126), a mesma da home.
--   tribes          todas as tribos                -> so as ativas; tribes_summary segue o mesmo filtro.
--   impact_hours    soma propria (duracao planejada, sem excluir ausencia justificada)
--                   -> get_impact_hours_canonical acumulado (ADR-0100 2C, nenhuma re-implementacao inline),
--                   decisao do GP de 08/10/2026; impact_hours_since devolve o ano do primeiro registro contado.
--   timeline        ganha timeline_is_narrative: o texto e registro historico, nao dado corrente.
-- Assinatura, SECURITY DEFINER, search_path e EXECUTE para anon nao mudam (pos-condicao no fim).

CREATE OR REPLACE FUNCTION public.get_public_impact_data()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result jsonb;
  v_chapters jsonb := public.get_chapter_metrics();
BEGIN
  SELECT jsonb_build_object(
    'chapters', (v_chapters->>'engaged')::int,
    'chapters_engaged', (v_chapters->>'engaged')::int,
    'chapters_signed', (v_chapters->>'signed')::int,
    'active_members', (SELECT COUNT(*) FROM public.v_operational_members),
    'tribes', (SELECT COUNT(*) FROM tribes WHERE is_active),
    'articles_published', (SELECT COUNT(*) FROM public_publications WHERE is_published = true),
    'articles_approved', (
      SELECT COUNT(*) FROM board_lifecycle_events WHERE action = 'curation_review' AND new_status = 'approved'
    ),
    'total_events', (SELECT COUNT(*) FROM events e WHERE e.date >= '2026-03-01' AND NOT EXISTS (SELECT 1 FROM initiatives ci WHERE ci.id = e.initiative_id AND ci.visibility = 'confidential')),
    'total_attendance_hours', (
      SELECT COALESCE(SUM(e.duration_minutes / 60.0), 0)
      FROM attendance a JOIN events e ON e.id = a.event_id
      WHERE e.date >= '2026-03-01' AND a.present AND NOT EXISTS (SELECT 1 FROM initiatives ci WHERE ci.id = e.initiative_id AND ci.visibility = 'confidential')
    ),
    'impact_hours', public.get_impact_hours_canonical('2000-01-01'::date, CURRENT_DATE),
    'impact_hours_since', (
      SELECT EXTRACT(year FROM min(e.date))::int
      FROM attendance a JOIN events e ON e.id = a.event_id
      WHERE a.present AND a.excused IS NOT TRUE AND e.date <= CURRENT_DATE
        AND NOT EXISTS (SELECT 1 FROM initiatives ci WHERE ci.id = e.initiative_id AND ci.visibility = 'confidential')
    ),
    'webinars', public.get_webinars_count(NULL, NULL, 'realized'),
    'ia_pilots', (SELECT COUNT(*) FROM ia_pilots WHERE status IN ('active','completed')),
    'partner_count', (SELECT COUNT(*) FROM partner_entities WHERE status = 'active'),
    'courses_count', (SELECT COUNT(*) FROM courses),
    'recent_publications', COALESCE((
      SELECT jsonb_agg(sub ORDER BY sub.publication_date DESC NULLS LAST)
      FROM (SELECT title, authors, external_platform AS platform, publication_date, external_url
            FROM public_publications WHERE is_published = true
            ORDER BY publication_date DESC NULLS LAST LIMIT 5) sub
    ), '[]'::jsonb),
    'tribes_summary', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', t.name, 'quadrant_name', t.quadrant_name,
        'member_count', (SELECT COUNT(*) FROM members m WHERE m.tribe_id = t.id AND m.is_active),
        'leader_name', (SELECT m.name FROM members m WHERE m.id = t.leader_member_id AND m.is_active AND m.current_cycle_active AND m.member_status = 'active' AND t.is_active)
      ) ORDER BY t.id)
      FROM tribes t
      WHERE t.is_active
    ), '[]'::jsonb),
    'chapters_summary', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'chapter', pe.name,
          'member_count', (SELECT COUNT(*) FROM members m WHERE m.chapter = pe.name AND m.is_active),
          'sponsor', (SELECT ms.name FROM members ms WHERE ms.chapter = pe.name AND 'sponsor' = ANY(ms.designations) AND ms.is_active LIMIT 1)
        )
        ORDER BY (SELECT COUNT(*) FROM members m WHERE m.chapter = pe.name AND m.is_active) DESC, pe.name
      )
      FROM partner_entities pe
      WHERE pe.entity_type = 'pmi_chapter' AND pe.status = 'active' AND NOT COALESCE(pe.is_international, false)
    ), '[]'::jsonb),
    'partners', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('name', name, 'type', entity_type, 'status', status))
      FROM partner_entities WHERE status = 'active'
    ), '[]'::jsonb),
    'recognitions', jsonb_build_array(
      jsonb_build_object(
        'title', 'Finalista — Prêmio "Carlos Novello" Voluntário do Ano',
        'organization', 'PMI LATAM Excellence Awards 2025',
        'recipient', 'Vitor Maia Rodovalho (GP)',
        'date', '2026-02-26',
        'category', 'Volunteer of the Year — LATAM Brasil',
        'description', 'Nomeado pelo PMI Goiás pelo trabalho à frente do Núcleo de IA & GP'
      )
    ),
    'timeline_is_narrative', true,
    'timeline', jsonb_build_array(
      jsonb_build_object('year', '2024', 'title', 'Fase Piloto', 'description', 'Concepção pelo PMI-GO. Patrocínio Ivan Lourenço. Experimentação e lições aprendidas.'),
      jsonb_build_object('year', '2025.1', 'title', 'Oficialização', 'description', 'Parceria PMI-GO + PMI-CE. 7 artigos submetidos ao ProjectManagement.com. 1º Webinar.'),
      jsonb_build_object('year', '2025.2', 'title', 'Amadurecimento', 'description', 'Manual de Governança R2. 13 pesquisadores selecionados. Expansão para PMI-DF, PMI-MG, PMI-RS.'),
      jsonb_build_object('year', '2026', 'title', 'Escala', 'description', '44+ colaboradores, 8 tribos, 5 capítulos PMI. Plataforma digital própria. Processo seletivo estruturado.')
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc
                 WHERE oid = 'public.get_public_impact_data()'::regprocedure
                   AND prosecdef
                   AND proconfig @> ARRAY['search_path=public, pg_temp'])
     OR NOT has_function_privilege('anon', 'public.get_public_impact_data()', 'EXECUTE')
  THEN
    RAISE EXCEPTION 'get_public_impact_data: pos-condicao violada (assinatura ou EXECUTE)';
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
