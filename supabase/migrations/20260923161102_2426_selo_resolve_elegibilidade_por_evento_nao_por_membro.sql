-- ============================================================================
-- #2426 — o ensaio do selo estourava o teto de 8s porque resolvia elegibilidade POR MEMBRO
-- ============================================================================
--
-- MEDIDO em 23/09/2026:
--   _seal_event_attendance_apply(um evento, dry_run) ......... 1009 ms
--     dos quais, as 76 chamadas de _attendance_eligible_events .. 981 ms  (97%)
--   laco de seal_attendance_window_cron: 9 eventos x 1009 ms ... ~9081 ms
--   teto de statement_timeout de authenticator/authenticated ... 8000 ms
--
-- POR QUE 9 AGORA: 5 eventos estavam elegiveis desde 28/07-24/08; QUATRO cruzaram a carencia de
-- 14 dias em 22 e 23/09. Ate 21/09 o laco custava ~5,0s e passava. Nao e flake: e degrau, e cada
-- evento novo do ciclo soma ~1s. Subir o teto so adiaria.
--
-- A CAUSA: para cada membro candidato, `_attendance_eligible_events(m.id, NULL)` computa a lista
-- INTEIRA de eventos elegiveis daquele membro — varrendo os 198 eventos da janela e avaliando
-- `_event_end_instant` em cada um — so para perguntar se ESTE evento esta nela.
-- 76 membros x 198 eventos = 15.048 avaliacoes por evento selado, 135.432 no laco de 9.
--
-- Mas as condicoes de JANELA, DATA, STATUS e TIPO dependem so do EVENTO, nao do membro. Elas
-- estavam dentro do laco sem precisar estar. Invertendo: resolve-se o evento UMA vez, e por membro
-- sobra apenas o ramo que de fato depende dele (tribo ou capacidade).
--
-- ⚠️ A GUARDA DE JANELA E OBRIGATORIA, E QUASE PASSOU DESPERCEBIDA.
-- `_attendance_eligible_events` filtra pela janela do ciclo; `_seal_event_attendance_apply` NAO.
-- A inversao ingenua, medida em 5 eventos ANTERIORES ao ciclo, inventaria **32 pares** onde o
-- caminho atual da 0 — ou seja, selar um evento antigo a mao passaria a gravar 32 faltas que hoje
-- nao existem. Por isso o `v_win_start/v_win_end` abaixo, e por isso o teste de equivalencia foi
-- refeito com eventos FORA da janela.
--
-- EQUIVALENCIA PROVADA por diferenca simetrica, nos dois sentidos:
--   amostra de 14 eventos (10 FORA da janela), 3 tipos: 180 pares dos dois lados, 0 e 0
--   amostra de 9 eventos dentro da janela, 3 tipos:     287 pares dos dois lados, 0 e 0
--   CONTROLE NEGATIVO (o instrumento sabe dizer nao):
--     mutacao que remove o ramo `tribo`  -> 23 so no velho
--     mutacao que afrouxa o ramo `tribo` -> 661 so no mutante
--   `kickoff` nao tem evento na janela: nao exercitado, e compartilha o ramo literal de `geral`.
--
-- OS DOIS CAMINHOS MUDAM JUNTOS, de proposito: o CTE `coorte` (ensaio) e o `INSERT ... SELECT`
-- (ato) usavam o MESMO EXISTS. Trocar so um faria ensaio e ato divergirem — exatamente o que o
-- teste `#1710-D C: o ensaio roda pela mesma funcao que executa` existe para impedir.
--
-- Cross-ref: #2426, #1710, #1727, #1729, #1948, #1476.
-- ============================================================================

CREATE OR REPLACE FUNCTION public._seal_event_attendance_apply(
  p_event_id uuid, p_actor_id uuid, p_dry_run boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_type      text;
  v_status    text;
  v_date      date;
  v_title     text;
  v_org       uuid;
  v_sealed_at timestamptz;
  v_end       timestamptz;
  v_eligible  int := 0;
  v_recorded  int := 0;
  v_sealed    int := 0;
  v_pre_entry int := 0;
  -- #2426: a janela do ciclo, resolvida UMA vez. Era avaliada por membro, dentro de
  -- `_attendance_eligible_events`, e e a guarda que impede o selo manual de um evento
  -- anterior ao ciclo gravar faltas que hoje nao existem.
  v_win_start date;
  v_win_end   date;
  v_tribe_id  int;
BEGIN
  SELECT e.type, e.status, e.date, e.title, e.organization_id, e.roster_sealed_at,
         public._event_end_instant(e.date, e.time_start, e.duration_minutes, e.timezone)
    INTO v_type, v_status, v_date, v_title, v_org, v_sealed_at, v_end
  FROM public.events e WHERE e.id = p_event_id;

  IF v_type IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Evento não encontrado', 'event_id', p_event_id);
  END IF;
  IF v_type NOT IN ('geral','kickoff','tribo','lideranca') THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Tipo de evento não elegível para presença (' || v_type || ')', 'event_id', p_event_id);
  END IF;
  IF v_status = 'cancelled' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Evento cancelado não pode ser selado', 'event_id', p_event_id);
  END IF;
  -- #1727: comparar DATA em UTC deixava passar a reuniao de hoje a noite, marcando falta de quem
  -- ainda ia comparecer. O corte e por INSTANTE, pela funcao compartilhada.
  IF v_end > now() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Evento ainda não terminou',
      'event_id', p_event_id, 'ends_at', v_end);
  END IF;

  -- #2426: janela do ciclo + tribo do evento, resolvidas uma vez fora de qualquer laco.
  SELECT c.cycle_start, LEAST(COALESCE(c.cycle_end, CURRENT_DATE), CURRENT_DATE)
    INTO v_win_start, v_win_end
  FROM public.cycles c WHERE c.is_current = true LIMIT 1;

  SELECT i.legacy_tribe_id INTO v_tribe_id
  FROM public.initiatives i WHERE i.id = (SELECT e2.initiative_id FROM public.events e2 WHERE e2.id = p_event_id);

  -- Fora da janela do ciclo a coorte e vazia, exatamente como antes (o filtro morava dentro de
  -- `_attendance_eligible_events`). Cai no mesmo desfecho de coorte vazia, logo abaixo.
  IF v_win_start IS NULL OR v_date < v_win_start OR v_date > v_win_end THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Coorte elegível vazia: evento não selado',
      'reason', 'skipped_empty_cohort',
      'event_id', p_event_id, 'event_title', v_title, 'event_date', v_date,
      'eligible_cohort_n', 0, 'roster_sealed_at', v_sealed_at);
  END IF;

  -- A coorte e quantos dela ja tem registro saem da MESMA passagem: assim o numero que o ensaio
  -- publica e o numero que a gravacao produz, e nao duas contas que podem divergir.
  -- #1476 Onda 2: coorte operacional por engagement (junction), nao pelo cache operational_role.
  -- #1948: a coorte NAO muda — quem entrou depois do evento continua nela, e a distincao vai na
  -- COLUNA da linha, nao na presenca dela. Tirar da coorte quebraria "selado => linha existe".
  WITH coorte AS (
    SELECT m.id, (v_date < public._member_operational_since(m.id)) AS pre_entry
    FROM public.members m
    WHERE m.is_active = true AND m.current_cycle_active = true
      AND EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
                  WHERE vt.member_id = m.id AND vt.operational_tier IN ('researcher','tribe_leader','manager'))
      -- #2426: so o ramo que depende do MEMBRO. O resto ja foi resolvido acima.
      AND (
        v_type IN ('geral','kickoff')
        OR (v_type = 'tribo' AND v_tribe_id IS NOT NULL AND public.get_member_tribe(m.id) = v_tribe_id)
        OR (v_type = 'lideranca' AND public.can_by_member(m.id, 'manage_event'))
      )
  )
  SELECT count(*)::int, count(a.member_id)::int,
         count(*) FILTER (WHERE c.pre_entry AND a.member_id IS NULL)::int
    INTO v_eligible, v_recorded, v_pre_entry
  FROM coorte c
  LEFT JOIN public.attendance a ON a.event_id = p_event_id AND a.member_id = c.id;

  -- #1729: coorte vazia NAO e evento a selar. Carimbar aqui marcaria "lista fechada" num evento que
  -- nunca teve lista, e a partir do carimbo a grade passa a ler ausencia de linha como falta.
  IF v_eligible = 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Coorte elegível vazia: evento não selado',
      'reason', 'skipped_empty_cohort',
      'event_id', p_event_id,
      'event_title', v_title,
      'event_date', v_date,
      'eligible_cohort_n', 0,
      'roster_sealed_at', v_sealed_at
    );
  END IF;

  IF p_dry_run THEN
    RETURN jsonb_build_object(
      'success', true,
      'dry_run', true,
      'event_id', p_event_id,
      'event_title', v_title,
      'event_type', v_type,
      'event_date', v_date,
      'eligible_cohort_n', v_eligible,
      'already_recorded_count', v_recorded,
      'would_write_absent_n', GREATEST(v_eligible - v_recorded - v_pre_entry, 0),
      -- #1948: o ensaio separa as duas naturezas. Sem isto o PM le "N faltas" e algumas nao sao.
      'would_write_excused_pre_entry_n', v_pre_entry,
      'roster_sealed_at', v_sealed_at
    );
  END IF;

  INSERT INTO public.attendance (event_id, member_id, present, excused, excuse_reason, organization_id, notes, registered_by, marked_by, checked_in_at)
  SELECT p_event_id, m.id, false,
         s.pre_entry,
         CASE WHEN s.pre_entry THEN 'Ingresso posterior ao evento (#1948)' END,
         v_org, public._roster_seal_marker(), p_actor_id, p_actor_id, NULL
  FROM public.members m
  CROSS JOIN LATERAL (SELECT (v_date < public._member_operational_since(m.id)) AS pre_entry) s
  WHERE m.is_active = true AND m.current_cycle_active = true
    AND EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
                WHERE vt.member_id = m.id AND vt.operational_tier IN ('researcher','tribe_leader','manager'))
    -- #2426: MESMA condicao do CTE acima. Os dois caminhos mudam juntos, senao ensaio e ato divergem.
    AND (
      v_type IN ('geral','kickoff')
      OR (v_type = 'tribo' AND v_tribe_id IS NOT NULL AND public.get_member_tribe(m.id) = v_tribe_id)
      OR (v_type = 'lideranca' AND public.can_by_member(m.id, 'manage_event'))
    )
  ON CONFLICT (event_id, member_id) DO NOTHING;
  GET DIAGNOSTICS v_sealed = ROW_COUNT;

  UPDATE public.events SET roster_sealed_at = COALESCE(roster_sealed_at, now())
  WHERE id = p_event_id
  RETURNING roster_sealed_at INTO v_sealed_at;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
  VALUES (p_actor_id, 'attendance.roster_sealed', 'event', p_event_id,
    jsonb_build_object(
      'event_title', v_title, 'event_date', v_date, 'event_type', v_type,
      'eligible_cohort_n', v_eligible, 'sealed_absent_count', GREATEST(v_sealed - v_pre_entry, 0),
      'sealed_excused_pre_entry_count', v_pre_entry,
      'roster_sealed_at', v_sealed_at,
      -- Cron e suite de teste tem a MESMA digital (`service_role`, ator nulo). O carimbo e o unico
      -- jeito de o log distinguir um selo automatico de um selo escrito por um teste.
      'source', CASE WHEN p_actor_id IS NULL THEN 'window_cron' ELSE 'manual' END));

  RETURN jsonb_build_object(
    'success', true,
    'event_id', p_event_id,
    'event_title', v_title,
    'event_type', v_type,
    'event_date', v_date,
    'eligible_cohort_n', v_eligible,
    'sealed_absent_count', GREATEST(v_sealed - v_pre_entry, 0),
    'sealed_excused_pre_entry_count', v_pre_entry,
    'already_recorded_count', GREATEST(v_eligible - v_sealed, 0),
    'roster_sealed_at', v_sealed_at
  );
END;
$function$;
