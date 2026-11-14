-- get_public_impact_data.total_events conta encontros da comunidade realizados (decisão do GP, 13/11/2026).
--
-- Antes: contava toda linha de events desde 2026-03-01, inclusive eventos futuros, cancelados e as entrevistas
-- individuais do processo seletivo. O /about exibia esse total como "eventos".
-- Agora: só eventos com data até hoje, não cancelados (status 'cancelled' ou cancelled_at preenchido) e que não são
-- entrevista de seleção. Reunião sem chamada de presença continua contando, porque o encontro aconteceu.
-- O resto da função é o corpo de 20261025160648, letra por letra.
--
-- (1) pré-condição: o corpo vivo é o de 20261025160648 (md5 do corpo com espaço normalizado, a conta do gate de
--     deriva). Outro corpo no banco para a migration.
-- (2) a função (CREATE OR REPLACE mantém assinatura, dono e grants).
-- (3) pós-condição, só leitura: total_events é igual à contagem pela definição nova.
--
-- Rollback: reaplicar get_public_impact_data de 20261025160648.

-- ── (1) o banco é o medido ──────────────────────────────────────────────────────────────────────────────────────
DO $precondition$
BEGIN
  IF (SELECT md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')) FROM pg_proc p
      WHERE p.oid = 'public.get_public_impact_data()'::regprocedure)
     IS DISTINCT FROM '928c89bbb476f55c729670add099b57d' THEN
    RAISE EXCEPTION 'total_events: get_public_impact_data no banco não é a da captura medida';
  END IF;
END;
$precondition$;

-- ── (2) a função ────────────────────────────────────────────────────────────────────────────────────────────────
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
    -- Encontros da comunidade realizados (GP 13/11/2026): só o que já aconteceu, sem cancelados e sem entrevista de
    -- seleção, que é operação do processo seletivo e não encontro. Reunião sem chamada de presença continua contando.
    'total_events', (
      SELECT COUNT(*) FROM events e
      WHERE e.date >= '2026-03-01' AND e.date <= CURRENT_DATE
        AND e.status IS DISTINCT FROM 'cancelled' AND e.cancelled_at IS NULL
        AND e.type IS DISTINCT FROM 'entrevista'
        AND NOT EXISTS (SELECT 1 FROM initiatives ci WHERE ci.id = e.initiative_id AND ci.visibility = 'confidential')
    ),
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
    -- PR3 A1 (GP 25/10/2026): os capítulos engajados (assinados e em negociação, sem dizer qual é qual), contando
    -- pessoas na base do cabeçalho (v_operational_members). O número só aparece com 3 pessoas ou mais, o mesmo k do
    -- mapa da home (get_public_country_reach: n >= 3); abaixo disso o card mostra só o capítulo. O membro guarda
    -- 'PMI-' || código do capítulo, e há capítulo cujo nome no CRM é outro: casa pelo nome ou pelo código.
    'chapters_summary', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object('chapter', c.chapter, 'member_count', c.member_count)
        ORDER BY c.member_count DESC NULLS LAST, c.chapter
      )
      FROM (
        SELECT pe.name AS chapter,
               CASE WHEN n.people >= 3 THEN n.people END AS member_count
        FROM partner_entities pe
        CROSS JOIN LATERAL (
          SELECT COUNT(*) AS people FROM public.v_operational_members om
          WHERE om.chapter = pe.name OR om.chapter = 'PMI-' || pe.chapter
        ) n
        WHERE pe.entity_type = 'pmi_chapter' AND pe.status IN ('active', 'negotiation')
          AND NOT COALESCE(pe.is_international, false)
      ) c
    ), '[]'::jsonb),
    'timeline_is_narrative', true,
    'timeline', jsonb_build_array(
      jsonb_build_object('year', '2024', 'title', 'Fase Piloto', 'description', 'Concepção pelo PMI-GO. Experimentação e lições aprendidas.'),
      jsonb_build_object('year', '2025.1', 'title', 'Oficialização', 'description', 'Parceria PMI-GO + PMI-CE. 7 artigos submetidos ao ProjectManagement.com. 1º Webinar.'),
      jsonb_build_object('year', '2025.2', 'title', 'Amadurecimento', 'description', 'Manual de Governança R2. 13 pesquisadores selecionados. Expansão para PMI-DF, PMI-MG, PMI-RS.'),
      jsonb_build_object('year', '2026.1', 'title', 'Escala', 'description', 'Início do ciclo 3: 44+ colaboradores, 8 tribos, 5 capítulos PMI. Plataforma digital própria. Processo seletivo estruturado. Abertura de negociação com novos capítulos.'),
      jsonb_build_object('year', '2026.2', 'title', 'Expansão', 'description', 'Ciclo 4: novas tribos de pesquisa e vitrine pública do Núcleo, com podcast, webinars gravados e indicadores atualizados em tempo real.'),
      jsonb_build_object('year', 'Out 2026', 'title', 'PMI Global Summit 2026', 'description', 'Apresentação do Núcleo no Volunteer Live! (Detroit, EUA, 21/10/2026).')
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- ── (3) pós-condição ────────────────────────────────────────────────────────────────────────────────────────────
DO $postcondition$
DECLARE
  v_rpc bigint := (public.get_public_impact_data()->>'total_events')::bigint;
  v_def bigint;
BEGIN
  SELECT COUNT(*) INTO v_def FROM events e
  WHERE e.date >= '2026-03-01' AND e.date <= CURRENT_DATE
    AND e.status IS DISTINCT FROM 'cancelled' AND e.cancelled_at IS NULL
    AND e.type IS DISTINCT FROM 'entrevista'
    AND NOT EXISTS (SELECT 1 FROM initiatives ci WHERE ci.id = e.initiative_id AND ci.visibility = 'confidential');
  IF v_rpc IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION 'total_events: RPC devolve %, a definição conta %', v_rpc, v_def;
  END IF;
END;
$postcondition$;
