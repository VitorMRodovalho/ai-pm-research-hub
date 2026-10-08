-- #2580 frente 2, regra 2 (decisao do GP de 08/10/2026, D3): um unico resumo semanal por pessoa, segunda-feira
-- 09h de Brasilia. A parte de lider entra no mesmo resumo e substitui o resumo de membro de sabado e o de lider
-- de segunda.
--
-- Como: o gerador do resumo de lider roda segunda 11:50 UTC e grava o resumo de cada lider como item
-- digest_weekly para quem esta na audiencia do resumo semanal (quem nao esta continua recebendo o e-mail
-- proprio). As 12:00 UTC o resumo de membro junta esse item na secao 'leadership' e o carimba como entregue
-- pelo mesmo conjunto que montou as secoes (#2286).

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
        -- #2580 regra 2: a parte de lider entra no mesmo resumo, sem janela (o gerador roda minutos antes).
        WHEN n.type = 'weekly_tribe_digest_leader' THEN 'leadership'
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

      -- #2580 regra 2: o resumo de lider (payload v2 do gerador) como item do resumo unico.
      'leadership', COALESCE(v_notif->'leadership', '[]'::jsonb),

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

CREATE OR REPLACE FUNCTION public.generate_weekly_member_digest_cron()
RETURNS TABLE(member_id uuid, notified boolean, reason text, batch_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_m record;
  v_digest jsonb;
  v_has_content boolean;
  v_consumed_ids jsonb;
  v_batch_id uuid := gen_random_uuid();
  v_consumed_id_array uuid[];
BEGIN
  FOR v_m IN
    SELECT id FROM public.members
    WHERE is_active = true
      AND notify_weekly_digest = true
      AND notify_delivery_mode_pref IN ('weekly_digest', 'custom_per_type')
  LOOP
    v_digest := public.get_weekly_member_digest(v_m.id);
    v_has_content :=
      jsonb_array_length(v_digest->'sections'->'cards'->'this_week_pending') > 0
      OR jsonb_array_length(v_digest->'sections'->'cards'->'next_week_due') > 0
      OR jsonb_array_length(v_digest->'sections'->'cards'->'overdue_7plus') > 0
      OR jsonb_array_length(v_digest->'sections'->'cards'->'new_assignments') > 0
      OR jsonb_array_length(v_digest->'sections'->'engagements_new') > 0
      OR jsonb_array_length(v_digest->'sections'->'attendance_reminders_pending') > 0
      OR jsonb_array_length(v_digest->'sections'->'other_notifications') > 0
      OR jsonb_array_length(v_digest->'sections'->'events_upcoming') > 0
      OR jsonb_array_length(v_digest->'sections'->'publications_new') > 0
      OR jsonb_array_length(v_digest->'sections'->'broadcasts') > 0
      OR jsonb_array_length(v_digest->'sections'->'governance_pending') > 0
      OR jsonb_array_length(v_digest->'sections'->'leadership') > 0
      OR jsonb_array_length(v_digest->'sections'->'achievements'->'certificates_issued') > 0
      OR (v_digest->'sections'->'achievements'->>'xp_delta')::int > 0;

    IF v_has_content THEN
      v_consumed_ids := v_digest->'consumed_notification_ids';

      INSERT INTO public.notifications (
        recipient_id, type, title, body, link, source_type, source_id,
        is_read, delivery_mode, digest_batch_id
      ) VALUES (
        v_m.id,
        'weekly_member_digest',
        'Seu resumo semanal — Núcleo IA',
        v_digest::text,
        '/digest/' || v_batch_id::text,
        'digest',
        v_batch_id,
        false,
        'transactional_immediate',
        v_batch_id
      );

      IF jsonb_array_length(v_consumed_ids) > 0 THEN
        SELECT array_agg((value::text)::uuid) INTO v_consumed_id_array
        FROM jsonb_array_elements_text(v_consumed_ids);

        UPDATE public.notifications
        SET digest_delivered_at = now(),
            digest_batch_id = v_batch_id
        WHERE id = ANY(v_consumed_id_array)
          AND digest_delivered_at IS NULL;
      END IF;

      member_id := v_m.id; notified := true; reason := 'sent'; batch_id := v_batch_id;
    ELSE
      member_id := v_m.id; notified := false; reason := 'no_content_skip'; batch_id := NULL;
    END IF;
    RETURN NEXT;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.generate_weekly_leader_digest_cron()
 RETURNS TABLE(initiative_id uuid, initiative_name text, leader_id uuid, notified boolean, reason text, batch_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_batch_id uuid := gen_random_uuid();
BEGIN
  RETURN QUERY
  WITH inits AS MATERIALIZED (
    SELECT i.initiative_id, i.name
    FROM public._v4_active_initiatives_with_leaders() i
  ),
  -- MATERIALIZED e obrigatorio: sem ele o planner pode reavaliar
  -- get_weekly_initiative_digest uma vez por PAR (40x) em vez de uma vez por
  -- iniciativa (~26x). O digest e caro (varias agregacoes por iniciativa).
  digests AS MATERIALIZED (
    SELECT i.initiative_id, i.name,
           public.get_weekly_initiative_digest(i.initiative_id) AS digest
    FROM inits i
  ),
  scored AS (
    SELECT d.initiative_id, d.name, d.digest,
           ( (d.digest->'aggregates'->>'cards_overdue_total')::int > 0
          OR (d.digest->'aggregates'->>'cards_due_next_7d')::int > 0
          OR (d.digest->'aggregates'->>'cards_without_assignee')::int > 0
          OR (d.digest->'aggregates'->>'cards_without_due_date')::int > 0
          OR (d.digest->'aggregates'->>'cards_completed_window')::int > 0
          OR (d.digest->'aggregates'->'ata_pending'->>'count_events')::int > 0
          OR (d.digest->'aggregates'->'attendance_pending'->>'count')::int > 0
          OR (d.digest->'aggregates'->'champion_pending'->>'count')::int > 0
           ) AS has_signal
    FROM digests d
  ),
  -- LEFT JOIN LATERAL preserva o caso "iniciativa ativa sem engagement de lider
  -- ativo": leader_id NULL vira uma linha de relatorio, como antes.
  pairs AS (
    SELECT s.initiative_id, s.name, s.digest, s.has_signal,
           l.lid AS leader_id,
           m.notify_delivery_mode_pref AS leader_pref
    FROM scored s
    LEFT JOIN LATERAL public._v4_leader_member_ids_by_initiative(s.initiative_id) l(lid) ON true
    LEFT JOIN public.members m ON m.id = l.lid
  ),
  classified AS (
    SELECT p.*,
           CASE
             WHEN p.leader_id IS NULL            THEN 'no_active_v4_leader_engagement'
             WHEN p.leader_pref = 'suppress_all' THEN 'leader_suppressed_all'
             WHEN NOT p.has_signal               THEN 'no_signal_skip'
             ELSE 'sent'
           END AS reason
    FROM pairs p
  ),
  to_send AS (
    SELECT c.leader_id,
           jsonb_agg(c.digest ORDER BY c.name) AS initiatives,
           count(*)::int AS n,
           min(c.name) AS first_name
    FROM classified c
    WHERE c.reason = 'sent'
    GROUP BY c.leader_id
  ),
  -- Data-modifying CTE: executa exatamente uma vez e por completo, sendo ou nao
  -- referenciada pela query principal (doc do Postgres, WITH).
  ins AS (
    INSERT INTO public.notifications (
      recipient_id, type, title, body, link, source_type, source_id,
      is_read, delivery_mode, digest_batch_id
    )
    SELECT
      t.leader_id,
      'weekly_tribe_digest_leader', -- type unchanged for email handler back-compat
      CASE WHEN t.n = 1
           THEN 'Resumo semanal: ' || t.first_name
           ELSE 'Resumo semanal: ' || t.n || ' iniciativas'
      END,
      jsonb_build_object(
        'version', 2,
        'leader_id', t.leader_id,
        'initiative_count', t.n,
        'generated_at', now(),
        'initiatives', t.initiatives
      )::text,
      '/admin/portfolio',
      'leader_digest',
      v_batch_id,
      false,
      -- #2580 regra 2: quem recebe o resumo semanal recebe a parte de lider dentro dele; quem nao recebe
      -- continua com o e-mail proprio. Mesmo predicado de audiencia de generate_weekly_member_digest_cron.
      CASE WHEN mm.is_active = true
                AND mm.notify_weekly_digest = true
                AND mm.notify_delivery_mode_pref IN ('weekly_digest', 'custom_per_type')
           THEN 'digest_weekly'
           ELSE 'transactional_immediate'
      END,
      v_batch_id
    FROM to_send t
    JOIN public.members mm ON mm.id = t.leader_id
    RETURNING recipient_id
  )
  SELECT c.initiative_id,
         c.name,
         c.leader_id,
         (c.reason = 'sent'),
         c.reason,
         CASE WHEN c.reason = 'sent' THEN v_batch_id ELSE NULL END
  FROM classified c
  ORDER BY c.name, c.leader_id;
END;
$function$;


-- Agenda: segunda 11:50 UTC (lider) e 12:00 UTC (membro, 09h de Brasilia). Resolvido por nome.
DO $$
DECLARE
  v_leader bigint;
  v_member bigint;
BEGIN
  SELECT jobid INTO v_leader FROM cron.job WHERE jobname = 'send-weekly-leader-digest';
  SELECT jobid INTO v_member FROM cron.job WHERE jobname = 'send-weekly-member-digest';
  IF v_leader IS NULL OR v_member IS NULL THEN
    RAISE EXCEPTION 'cron job do resumo semanal nao encontrado (lider=%, membro=%)', v_leader, v_member;
  END IF;
  PERFORM cron.alter_job(job_id := v_leader, schedule := '50 11 * * 1');
  PERFORM cron.alter_job(job_id := v_member, schedule := '0 12 * * 1');
END $$;

UPDATE public.digest_cron_expectations
   SET expected_schedule = '50 11 * * 1',
       description = 'gerador do resumo de lider (ADR-0022 W3): segunda 11:50 UTC, entra no resumo unico (#2580)'
 WHERE jobname = 'send-weekly-leader-digest';

UPDATE public.digest_cron_expectations
   SET expected_schedule = '0 12 * * 1',
       description = 'resumo semanal unico do membro (ADR-0022 W2): segunda 09h de Brasilia (#2580)'
 WHERE jobname = 'send-weekly-member-digest';
