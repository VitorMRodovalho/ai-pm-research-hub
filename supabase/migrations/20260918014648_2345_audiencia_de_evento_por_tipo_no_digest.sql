-- #2345: a audiencia de cada tipo de evento vira DADO, e os eventos institucionais param de ser
-- invisiveis.
--
-- MEDIDO em 17/09/2026. `events_upcoming` decidia por lista branca no corpo:
--
--   AND ( i.legacy_tribe_id = v_member_tribe_id
--         OR e.type IN ('plenaria','webinar','workshop_geral') )
--
-- Dois defeitos independentes nessa unica clausula:
--
--   1. **13 eventos futuros invisiveis.** `lideranca` (7) e `geral` (6) nao tem `initiative_id`
--      (sao institucionais), entao o primeiro ramo nunca casa; e nao estao na lista, entao o
--      segundo tambem nao. As reunioes de lideranca estao agendadas ate dezembro e o canal nunca
--      as mencionou. Mesma classe da #2286, na secao VIZINHA da mesma funcao.
--   2. **Dois tercos da lista branca sao FANTASMAS.** `plenaria` e `workshop_geral` tem ZERO
--      eventos na base (controle positivo: `webinar` tem 6, e existem 11 tipos vivos). O gate
--      citava nomes que nunca casam — a mesma classe do #2341, que procurava um cron removido.
--
-- ⚠️ POR QUE O DEFAULT AQUI E O INVERSO DO DA #2286. Lá o balde do `ELSE` fazia todo tipo novo
-- APARECER, e isso era seguro porque notificacao ja nasce endereçada a um destinatario. Aqui nao:
-- `entrevista` tem **151** eventos e `1on1` tem 22, ambos privados por natureza. Um default
-- "mostrar o que nao foi declarado" exporia entrevista de selecao no digest de 99 membros. Entao o
-- default e NAO mostrar (JOIN, nao LEFT JOIN), e quem impede o silencio de virar defeito e o
-- GUARD: todo `type` vivo em `events` precisa ter linha declarada aqui.
--
-- A audiencia fica em DADO para que mudar de ideia seja um UPDATE, nao uma migration.

CREATE TABLE IF NOT EXISTS public.event_type_digest_audience (
  event_type     text PRIMARY KEY,
  audience       text NOT NULL CHECK (audience IN ('all_members','leadership','initiative_members','suppressed')),
  rationale      text NOT NULL,
  retired_at     timestamptz,
  retired_reason text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT event_type_digest_audience_retired_needs_reason
    CHECK (retired_at IS NULL OR retired_reason IS NOT NULL)
);

ALTER TABLE public.event_type_digest_audience ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.event_type_digest_audience IS
  '#2345: quem ve cada tipo de evento no digest semanal. `events_upcoming` faz JOIN com esta '
  'tabela, entao tipo NAO declarado nao aparece — default seguro, porque `entrevista` e `1on1` '
  'sao privados. O guard do #2345 exige que todo type vivo em `events` tenha linha aqui, de modo '
  'que o silencio nao possa se instalar. Mudar audiencia e UPDATE, nao migration.';

-- Seed dos 11 tipos VIVOS medidos em 17/09, mais os 2 fantasmas que a lista branca citava.
-- `suppressed` e decisao de privacidade, nao esquecimento: esta escrito por que.
INSERT INTO public.event_type_digest_audience (event_type, audience, rationale, retired_at, retired_reason)
VALUES
  ('tribo',          'initiative_members', 'evento de tribo: audiencia e quem participa dela (435 eventos, todos com initiative_id)', NULL, NULL),
  ('comms',          'initiative_members', 'pauta de comunicacao da iniciativa (37 eventos, todos com initiative_id)', NULL, NULL),
  ('iniciativa',     'initiative_members', 'evento da propria iniciativa', NULL, NULL),
  ('webinar',        'all_members',        'aberto ao nucleo — era o unico tipo da lista branca antiga que existia de fato', NULL, NULL),
  ('geral',          'all_members',        '#2345: institucional e aberto. Era INVISIVEL: 6 eventos futuros sem chegar a ninguem', NULL, NULL),
  ('kickoff',        'all_members',        'abertura de ciclo, institucional', NULL, NULL),
  ('evento_externo', 'all_members',        'representacao do nucleo fora: informativo para todos', NULL, NULL),
  ('lideranca',      'leadership',         '#2345: era INVISIVEL (7 eventos futuros). Audiencia por PAPEL, nao lista: 25 pessoas com papel de lideranca ativo contra 99 membros ativos — lista branca global exporia a reuniao de lideranca a todos', NULL, NULL),
  ('parceria',       'leadership',         'negociacao com terceiro: conservador ate decisao em contrario', NULL, NULL),
  ('entrevista',     'suppressed',         'PRIVACIDADE: 151 eventos de entrevista de selecao. Nunca vai ao digest coletivo', NULL, NULL),
  ('1on1',           'suppressed',         'PRIVACIDADE: conversa individual, privada por natureza', NULL, NULL),
  ('plenaria',       'all_members',        'estava na lista branca antiga', '2026-09-17 00:00:00+00', '#2345: ZERO eventos na base — nome fantasma que a lista branca citava e que nunca casou'),
  ('workshop_geral', 'all_members',        'estava na lista branca antiga', '2026-09-17 00:00:00+00', '#2345: ZERO eventos na base — nome fantasma que a lista branca citava e que nunca casou')
ON CONFLICT (event_type) DO NOTHING;

-- Auditoria para o CI: a RPC do digest e self-gated por auth.uid(), e o guard precisa medir a
-- cobertura por um caminho que ele possa chamar. Devolve fatos crus, sem veredito.
CREATE OR REPLACE FUNCTION public._audit_event_type_digest_coverage()
RETURNS TABLE(event_type text, eventos_na_base bigint, declarado boolean,
              audiencia text, aposentado boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE(t.type, a.event_type)            AS event_type,
         COALESCE(t.n, 0)                          AS eventos_na_base,
         (a.event_type IS NOT NULL)                AS declarado,
         a.audience                                AS audiencia,
         (a.retired_at IS NOT NULL)                AS aposentado
  FROM (SELECT type, count(*) AS n FROM public.events GROUP BY type) t
  FULL OUTER JOIN public.event_type_digest_audience a ON a.event_type = t.type
  ORDER BY 2 DESC, 1;
$$;

REVOKE ALL ON FUNCTION public._audit_event_type_digest_coverage() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._audit_event_type_digest_coverage() TO service_role;

-- A funcao. Atributos preservados (STABLE, SECURITY DEFINER, search_path=''), e tudo o que a
-- #2286 garantiu segue intacto: o ELSE do CASE, a UNICA leitura de notifications, o carimbo
-- derivado e o xp_delta por occurred_at (#1470).
CREATE OR REPLACE FUNCTION public.get_weekly_member_digest(p_member_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_is_self boolean;
  v_member_tribe_id integer;
  v_window_start timestamptz := date_trunc('day', now()) - interval '7 days';
  v_extended_window timestamptz := date_trunc('day', now()) - interval '14 days';
  v_notif jsonb;
  v_consumed jsonb;
  v_is_leadership boolean;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  v_is_self := (v_caller_id = p_member_id);

  IF NOT v_is_self AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: can only read own digest or requires manage_member permission';
  END IF;

  SELECT tribe_id INTO v_member_tribe_id FROM public.members WHERE id = p_member_id;

  -- #2345: audiencia de `lideranca` e por PAPEL, derivada de engagements — nao lista branca.
  -- Medido em 17/09: 25 pessoas com papel de lideranca ativo contra 99 membros ativos. Jogar
  -- `lideranca` na lista global faria a reuniao de lideranca aparecer no digest de todos os 99.
  -- Derivar de engagements tambem faz a audiencia acompanhar entrada e desligamento sozinha.
  SELECT EXISTS (
    SELECT 1
    FROM public.engagements en
    JOIN public.members m2 ON m2.person_id = en.person_id
    WHERE m2.id = p_member_id
      AND en.status = 'active'
      AND (en.role IN ('leader', 'coordinator') OR en.kind LIKE '%coordinator%')
  ) INTO v_is_leadership;

  -- #2286: a UNICA leitura de notifications desta funcao. `secao` decide onde o item
  -- aparece; `v_consumed` sai do MESMO conjunto, entao o carimbo nao tem como divergir
  -- do que foi montado. Nao acrescente um segundo SELECT sobre public.notifications
  -- aqui: era exatamente isso que fazia o carimbo mentir.
  WITH pend AS (
    SELECT n.id, n.type, n.title, n.body, n.created_at, n.link, n.source_type, n.source_id,
      CASE
        WHEN n.type = 'assignment_new'      AND n.created_at >= v_extended_window THEN 'new_assignments'
        WHEN n.type = 'attendance_reminder' AND n.created_at >= v_extended_window THEN 'attendance_reminders_pending'
        WHEN n.type IN ('engagement_welcome', 'engagement_added', 'volunteer_agreement_signed')
             AND n.created_at >= v_window_start THEN 'engagements_new'
        WHEN n.type = 'tribe_broadcast'     AND n.created_at >= v_window_start THEN 'broadcasts'
        WHEN n.type IN ('governance_vote_reminder', 'ip_ratification_gate_pending', 'change_request_pending')
             AND n.created_at >= v_window_start THEN 'governance_pending'
        ELSE 'other_notifications'
      END AS secao
    FROM public.notifications n
    WHERE n.recipient_id = p_member_id
      AND n.delivery_mode = 'digest_weekly'
      AND n.digest_delivered_at IS NULL
  ), agg AS (
    SELECT p.secao,
           jsonb_agg(jsonb_build_object(
             'id', p.id, 'type', p.type, 'title', p.title, 'body', p.body,
             'created_at', p.created_at, 'link', p.link,
             'source_type', p.source_type, 'source_id', p.source_id
           ) ORDER BY p.created_at DESC) AS itens
    FROM pend p GROUP BY p.secao
  )
  SELECT COALESCE((SELECT jsonb_object_agg(a.secao, a.itens) FROM agg a), '{}'::jsonb),
         COALESCE((SELECT jsonb_agg(p.id ORDER BY p.created_at DESC) FROM pend p), '[]'::jsonb)
    INTO v_notif, v_consumed;

  SELECT jsonb_build_object(
    'member_id', p_member_id,
    'generated_at', now(),
    'window_start', v_window_start,
    'sections', jsonb_build_object(
      'cards', jsonb_build_object(
        'this_week_pending', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', bi.id, 'title', bi.title, 'status', bi.status,
            'due_date', bi.due_date, 'board_name', pb.board_name,
            'initiative_title', i.title,
            'days_overdue', GREATEST(0, CURRENT_DATE - bi.due_date)
          ) ORDER BY bi.due_date ASC)
          FROM public.board_items bi
          LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
          LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
          WHERE bi.assignee_id = p_member_id
            AND bi.status NOT IN ('done', 'archived')
            AND bi.due_date BETWEEN CURRENT_DATE - INTERVAL '7 days' AND CURRENT_DATE
        ), '[]'::jsonb),
        'next_week_due', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', bi.id, 'title', bi.title, 'status', bi.status,
            'due_date', bi.due_date, 'board_name', pb.board_name,
            'initiative_title', i.title
          ) ORDER BY bi.due_date ASC)
          FROM public.board_items bi
          LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
          LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
          WHERE bi.assignee_id = p_member_id
            AND bi.status NOT IN ('done', 'archived')
            AND bi.due_date > CURRENT_DATE
            AND bi.due_date <= CURRENT_DATE + INTERVAL '7 days'
        ), '[]'::jsonb),
        'overdue_7plus', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', bi.id, 'title', bi.title, 'status', bi.status,
            'due_date', bi.due_date, 'board_name', pb.board_name,
            'initiative_title', i.title,
            'days_overdue', CURRENT_DATE - bi.due_date
          ) ORDER BY bi.due_date ASC)
          FROM public.board_items bi
          LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
          LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
          WHERE bi.assignee_id = p_member_id
            AND bi.status NOT IN ('done', 'archived')
            AND bi.due_date < CURRENT_DATE - INTERVAL '7 days'
        ), '[]'::jsonb),
        -- p95 #99 1B: notificacoes de atribuicao nova. #2286: vem do conjunto unico.
        'new_assignments', COALESCE(v_notif->'new_assignments', '[]'::jsonb)
      ),

      'engagements_new', COALESCE(v_notif->'engagements_new', '[]'::jsonb),

      -- #2345: a audiencia vem da TABELA, nao de lista branca no corpo. Antes, `lideranca` (7
      -- eventos futuros) e `geral` (6) eram INVISIVEIS: nao tem initiative_id, entao o ramo da
      -- tribo nunca casava, e nao estavam na lista. E dois tercos da lista antiga eram FANTASMAS
      -- (`plenaria` e `workshop_geral` tem ZERO eventos na base).
      --
      -- JOIN, nao LEFT JOIN, de proposito: tipo NAO declarado nao aparece. E o inverso do default
      -- da #2286, e a razao e privacidade — `entrevista` tem 151 eventos e `1on1` tem 22, ambos
      -- privados. Mostrar o nao-declarado exporia entrevista de selecao a 99 membros. Quem impede
      -- o silencio de virar defeito e o guard: todo type vivo tem de ter linha declarada.
      'events_upcoming', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', e.id, 'title', e.title, 'date', e.date,
          'type', e.type, 'initiative_id', e.initiative_id,
          'initiative_title', i.title,
          'audience', a.audience
        ) ORDER BY e.date ASC)
        FROM public.events e
        JOIN public.event_type_digest_audience a ON a.event_type = e.type
        LEFT JOIN public.initiatives i ON i.id = e.initiative_id
        WHERE e.date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '7 days'
          AND a.retired_at IS NULL
          AND a.audience <> 'suppressed'
          AND (
            (a.audience = 'initiative_members' AND i.legacy_tribe_id = v_member_tribe_id)
            OR a.audience = 'all_members'
            OR (a.audience = 'leadership' AND v_is_leadership)
          )
      ), '[]'::jsonb),

      -- p95 #99 1A: lembretes de presenca. #2286: vem do conjunto unico.
      'attendance_reminders_pending', COALESCE(v_notif->'attendance_reminders_pending', '[]'::jsonb),

      'publications_new', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', ps.id, 'title', ps.title,
          'submission_date', ps.submission_date,
          'primary_author_id', ps.primary_author_id
        ) ORDER BY ps.submission_date DESC)
        FROM public.publication_submissions ps
        WHERE ps.status = 'published'::public.submission_status
          AND ps.submission_date >= v_window_start::date
      ), '[]'::jsonb),

      'broadcasts', COALESCE(v_notif->'broadcasts', '[]'::jsonb),

      'governance_pending', COALESCE(v_notif->'governance_pending', '[]'::jsonb),

      -- #2286: o balde do ELSE. Enquanto existir, nenhum tipo `digest_weekly` some
      -- por omissao: o default vira MOSTRAR, e suprimir passa a exigir decisao
      -- registrada no catalogo do ADR-0022 (delivery_mode='suppress').
      'other_notifications', COALESCE(v_notif->'other_notifications', '[]'::jsonb),

      'achievements', jsonb_build_object(
        'certificates_issued', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', c.id, 'title', c.title, 'type', c.type,
            'issued_at', c.issued_at
          ) ORDER BY c.issued_at DESC)
          FROM public.certificates c
          WHERE c.member_id = p_member_id
            AND c.issued_at >= v_window_start
        ), '[]'::jsonb),
        -- #1470: XP da janela movel por data do FATO (occurred_at), nao data de lancamento
        -- (created_at) — o backfill historico nao infla mais o "XP desta semana".
        'xp_delta', COALESCE((
          SELECT sum(gp.points)::int
          FROM public.gamification_points gp
          WHERE gp.member_id = p_member_id
            AND COALESCE(gp.occurred_at, gp.created_at) >= v_window_start
        ), 0)
      )
    ),
    -- #2286: exatamente os ids que entraram nas secoes acima. Nao ha SELECT proprio.
    'consumed_notification_ids', v_consumed
  ) INTO v_result;

  RETURN v_result;
END;
$$;


NOTIFY pgrst, 'reload schema';
