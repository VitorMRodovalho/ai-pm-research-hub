-- #2553 D7, pacote DB-4: get_public_impact_data deixa de devolver nome de pessoa.
--
-- Decisões do GP em 24/10/2026, repassadas pela orquestradora: (4a) o /about mostra pessoas só em número, sem nome;
-- (5) o prêmio individual sai da RPC e da página. A função é lida por anon (o /about, o MCP do Núcleo e consumidores
-- externos), então o nome sai da resposta, não só da tela. Saem:
--   - tribes_summary[].leader_name (nome de quem lidera cada linha);
--   - chapters_summary[].sponsor (nome de quem preside cada capítulo);
--   - recent_publications[].authors (nomes de autoria);
--   - partners (a lista de nomes de parceiros: um dos cadastros ativos é uma pessoa, e não há campo que a separe das
--     organizações; partner_count continua);
--   - recognitions (o prêmio individual, que nomeia uma pessoa);
--   - na timeline, a frase da entrada 2024 que nomeia o patrocinador (o resto da entrada fica).
-- Nenhum outro campo muda: contadores, filtros de tribo ativa e de iniciativa confidencial, horas, webinars, a ordem
-- dos capítulos e as outras entradas da timeline são os do corpo de 20261008013231, letra por letra.
--
-- (1) pré-condição: o corpo vivo é o de 20261008013231 (md5 do corpo com espaço normalizado, a mesma conta do gate de
--     deriva). Outro corpo no banco para a migration em vez de sobrescrever o que não foi medido.
-- (2) a função nova (CREATE OR REPLACE mantém assinatura, dono e grants).
-- (3) pós-condição: SECURITY DEFINER, search_path fixo, EXECUTE de anon, e a resposta sem nenhuma das chaves que saíram.
--
-- Rollback: reaplicar a função de 20261008013231_2365_linha_do_tempo_ciclos.sql.

-- ── (1) o banco é o medido ──────────────────────────────────────────────────────────────────────────────────────
DO $do$
DECLARE
  v_md5 text;
BEGIN
  SELECT md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')) INTO v_md5
  FROM pg_proc p
  WHERE p.oid = 'public.get_public_impact_data()'::regprocedure;
  IF v_md5 IS DISTINCT FROM '4b0b384a650ba2335bec21031faa5ccb' THEN
    RAISE EXCEPTION '#2553 DB-4: get_public_impact_data no banco não é a de 20261008013231 (md5 %)', v_md5;
  END IF;
END;
$do$;

-- ── (2) a leitura pública sem nome de pessoa ────────────────────────────────────────────────────────────────────
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
      FROM (SELECT title, external_platform AS platform, publication_date, external_url
            FROM public_publications WHERE is_published = true
            ORDER BY publication_date DESC NULLS LAST LIMIT 5) sub
    ), '[]'::jsonb),
    'tribes_summary', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', t.name, 'quadrant_name', t.quadrant_name,
        'member_count', (SELECT COUNT(*) FROM members m WHERE m.tribe_id = t.id AND m.is_active)
      ) ORDER BY t.id)
      FROM tribes t
      WHERE t.is_active
    ), '[]'::jsonb),
    'chapters_summary', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'chapter', pe.name,
          'member_count', (SELECT COUNT(*) FROM members m WHERE m.chapter = pe.name AND m.is_active)
        )
        ORDER BY (SELECT COUNT(*) FROM members m WHERE m.chapter = pe.name AND m.is_active) DESC, pe.name
      )
      FROM partner_entities pe
      WHERE pe.entity_type = 'pmi_chapter' AND pe.status = 'active' AND NOT COALESCE(pe.is_international, false)
    ), '[]'::jsonb),
    'timeline_is_narrative', true,
    'timeline', jsonb_build_array(
      jsonb_build_object('year', '2024', 'title', 'Fase Piloto', 'description', 'Concepção pelo PMI-GO. Experimentação e lições aprendidas.'),
      jsonb_build_object('year', '2025.1', 'title', 'Oficialização', 'description', 'Parceria PMI-GO + PMI-CE. 7 artigos submetidos ao ProjectManagement.com. 1º Webinar.'),
      jsonb_build_object('year', '2025.2', 'title', 'Amadurecimento', 'description', 'Manual de Governança R2. 13 pesquisadores selecionados. Expansão para PMI-DF, PMI-MG, PMI-RS.'),
      jsonb_build_object('year', '2026.1', 'title', 'Escala', 'description', 'Início do ciclo 3: 44+ colaboradores, 8 tribos, 5 capítulos PMI. Plataforma digital própria. Processo seletivo estruturado. Abertura de negociação com novos capítulos.'),
      jsonb_build_object('year', '2026.2', 'title', 'Expansão', 'description', 'Ciclo 4: novas tribos de pesquisa e vitrine pública do Núcleo, com podcast, webinars gravados e indicadores atualizados em tempo real.')
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- ── (3) pós-condição ────────────────────────────────────────────────────────────────────────────────────────────
DO $do$
DECLARE
  v jsonb := public.get_public_impact_data();
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc
                 WHERE oid = 'public.get_public_impact_data()'::regprocedure
                   AND prosecdef
                   AND proconfig @> ARRAY['search_path=public, pg_temp'])
     OR NOT has_function_privilege('anon', 'public.get_public_impact_data()', 'EXECUTE')
  THEN
    RAISE EXCEPTION '#2553 DB-4: pós-condição violada (assinatura ou EXECUTE)';
  END IF;
  IF v ? 'recognitions' OR v ? 'partners'
     OR jsonb_path_exists(v, '$.tribes_summary[*].leader_name')
     OR jsonb_path_exists(v, '$.chapters_summary[*].sponsor')
     OR jsonb_path_exists(v, '$.recent_publications[*].authors')
  THEN
    RAISE EXCEPTION '#2553 DB-4: a resposta ainda leva uma chave com nome de pessoa';
  END IF;
  IF jsonb_array_length(v->'tribes_summary') = 0 OR NOT (v ? 'partner_count') THEN
    RAISE EXCEPTION '#2553 DB-4: controle positivo falhou (tribes_summary vazio ou partner_count ausente)';
  END IF;
END;
$do$;

NOTIFY pgrst, 'reload schema';
