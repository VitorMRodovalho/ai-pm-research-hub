-- #2286: o carimbo do digest passa a DERIVAR do que foi renderizado.
--
-- Medido em 17/09/2026, na fonte viva:
--   31 tipos vivos com delivery_mode='digest_weekly'
--   4.388 linhas carimbadas, sendo 2.661 pelo PROPRIO digest e 1.727 pelo purgador de
--   30 dias (`purge_stale_digest_notifications_cron`, que carimba por idade de proposito
--   e fica FORA desta mudanca; atribuicao feita cruzando digest_batch_id com o audit log)
--   Das 2.661 carimbadas pelo digest, ZERO eram de um tipo que o e-mail desenha.
--
-- A perda acontecia em TRES camadas, e a issue registrava so a primeira:
--   1. 27 tipos nao tinham secao nenhuma nesta RPC            -> 1.277 carimbadas
--   2. 2 tipos tinham secao aqui e NENHUM bloco no renderizador
--      da EF send-notification-email (`new_assignments` e
--      `attendance_reminders_pending`, criadas em p95 #99 1A/1B,
--      com ZERO ocorrencia no repositorio inteiro)            -> 3.006 carimbadas
--   3. `consumed_notification_ids` era um SELECT PARALELO sobre
--      notifications, independente das secoes: por construcao
--      ele podia afirmar entrega do que ninguem montou.
--
-- O conserto ataca a classe, nao os casos: UMA classificacao decide ao mesmo tempo
-- em que secao a notificacao aparece e se o id entra no carimbo. O `ELSE` recolhe
-- tudo o que nao casou com lista branca nenhuma, entao um tipo novo passa a aparecer
-- por DEFAULT em vez de sumir por omissao, e carimbar vira consequencia de renderizar.
--
-- A janela: as listas brancas mantem os pisos que ja tinham (7 dias, 14 para os dois
-- tipos de janela estendida). A sobra NAO tem piso de data de proposito — medido, 24
-- das 82 pendentes ja tinham envelhecido para fora da janela movel e nunca mais
-- entrariam em digest nenhum. Quem impede repeticao e o carimbo, nao a janela.
--
-- Atributos preservados deliberadamente (medidos antes: STABLE, SECURITY DEFINER,
-- search_path='', owner postgres). CREATE OR REPLACE preserva os GRANTs.

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
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  v_is_self := (v_caller_id = p_member_id);

  IF NOT v_is_self AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: can only read own digest or requires manage_member permission';
  END IF;

  SELECT tribe_id INTO v_member_tribe_id FROM public.members WHERE id = p_member_id;

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

      'events_upcoming', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', e.id, 'title', e.title, 'date', e.date,
          'type', e.type, 'initiative_id', e.initiative_id,
          'initiative_title', i.title
        ) ORDER BY e.date ASC)
        FROM public.events e
        LEFT JOIN public.initiatives i ON i.id = e.initiative_id
        WHERE e.date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '7 days'
          AND (
            i.legacy_tribe_id = v_member_tribe_id
            OR e.type IN ('plenaria', 'webinar', 'workshop_geral')
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

-- #2286: o orquestrador precisa CONTAR as tres secoes novas. Sem isto, um membro cujo
-- unico conteudo fosse `other_notifications` (ou os lembretes de presenca) continuaria
-- em `no_content_skip` — o digest nao sairia e o conserto ficaria invisivel justamente
-- para quem ele existe para atender.
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

-- A assinatura nao mudou, mas o corpo sim: recarrega o cache da PostgREST por higiene.
NOTIFY pgrst, 'reload schema';
