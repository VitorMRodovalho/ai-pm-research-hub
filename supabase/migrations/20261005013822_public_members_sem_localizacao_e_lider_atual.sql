-- public_members sem localização, e get_public_impact_data nomeia só o líder atual.
--
-- (1) public_members continua SECURITY DEFINER e legível por anon (diretório público, ADR-0024),
--     mas state e country saem da view. No site público, localização sai só pelas RPCs do mapa
--     (get_public_state_reach_v3 e afins), conforme /privacy. Nenhum leitor seleciona essas duas
--     colunas da view: conferido em 04/10/2026 no front, nas Edge Functions e nos corpos de função
--     do banco.
--     Tirar coluna muda a assinatura da view, então é DROP + CREATE (sem dependentes em pg_depend).
--     O DROP leva grants e comentário; os dois são refeitos abaixo, com o mesmo ACL de antes
--     (anon e authenticated só SELECT; service_role fica com o default do schema).
--
-- (2) get_public_impact_data.tribes_summary[].leader_name devolvia o nome referenciado em
--     tribes.leader_member_id mesmo depois de a pessoa sair e de a tribo fechar. Passa a devolver
--     só com a tribo ativa e a pessoa ativa no ciclo corrente (D1 da #2553, emenda 1: só o líder
--     atual). O resto do corpo é o vivo de 04/10/2026, idêntico à captura 20260805000320.
--
-- (3) Pós-condição no fim: se o ACL da view, as colunas ou a assinatura da função saírem errados,
--     a migration aborta inteira.

DROP VIEW IF EXISTS public.public_members;

CREATE VIEW public.public_members AS
  SELECT id,
    name,
    photo_url,
    chapter,
    operational_role,
    designations,
    tribe_id,
    initiative_id,
    current_cycle_active,
    is_active,
    linkedin_url,
    credly_badges,
    credly_url,
    credly_verified_at,
    cpmai_certified,
    cpmai_certified_at,
    cycles,
    created_at,
    share_whatsapp,
    member_status,
    is_founder
   FROM public.members;

REVOKE ALL ON public.public_members FROM anon, authenticated;
GRANT SELECT ON public.public_members TO anon, authenticated, service_role;

COMMENT ON VIEW public.public_members IS
  'Diretório público de membros, legível por anon (SECURITY DEFINER aceito na ADR-0024). Sem localização: ela sai só pelas RPCs do mapa, conforme /privacy. Coluna acrescentada aqui fica visível para anon.';

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
    'chapters', (v_chapters->>'signed')::int,
    'chapters_engaged', (v_chapters->>'engaged')::int,
    'active_members', (SELECT COUNT(*) FROM members WHERE is_active = true AND current_cycle_active = true),
    'tribes', (SELECT COUNT(*) FROM tribes),
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
    'impact_hours', (
      SELECT COALESCE(SUM(e.duration_minutes / 60.0), 0)
      FROM attendance a JOIN events e ON e.id = a.event_id
      WHERE a.present AND NOT EXISTS (SELECT 1 FROM initiatives ci WHERE ci.id = e.initiative_id AND ci.visibility = 'confidential')
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
  IF has_table_privilege('anon', 'public.public_members', 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     OR has_table_privilege('authenticated', 'public.public_members', 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     OR NOT has_table_privilege('anon', 'public.public_members', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.public_members', 'SELECT')
     OR EXISTS (SELECT 1 FROM pg_attribute
                WHERE attrelid = 'public.public_members'::regclass
                  AND attname IN ('state', 'country') AND NOT attisdropped)
  THEN
    RAISE EXCEPTION 'public_members: pos-condicao violada (ACL ou colunas)';
  END IF;

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
