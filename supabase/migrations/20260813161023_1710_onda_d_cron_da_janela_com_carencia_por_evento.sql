-- #1710 onda D — o selo passa a acontecer sozinho, com carencia por evento e piso na data do aviso.
--
-- Esta e a parte IRREVERSIVEL. As tres ondas anteriores deram ao ato escopo, reversao, tela e MCP;
-- esta e a que faz o ato ocorrer sem ninguem clicar.
--
-- Decisoes do PM, ja tomadas: selo AUTOMATICO com janela e aviso; carencia de 14 dias POR EVENTO;
-- piso em 24/08/2026 (os 14 dias prometidos no aviso do #1726, enviado em 10/08); exige dry-run e
-- reversao por evento — as duas ja entregues nas ondas anteriores.
--
-- 1. O NUCLEO COMPARTILHADO. `seal_event_attendance` resolve o chamador por `auth.uid()`; um cron
--    nao tem sessao. Duplicar o corpo para o cron seria duplicar exatamente a escrita em massa que
--    este item existe para domesticar. `_seal_event_attendance_apply` carrega tudo o que NAO depende
--    do chamador (tipo, status, fim, coorte, gravacao, carimbo, auditoria); os gates ficam com quem
--    chama, e a RPC do usuario passa a ser so os dois gates mais a delegacao.
--
-- 2. O ATOR DO SELO AUTOMATICO E NULO, e isso e a verdade: ninguem marcou aquela falta. Atribui-la
--    a um GP registraria uma falsidade. Como cron e suite de teste compartilham a digital de
--    `service_role` com ator nulo, o que separa os dois no log e o carimbo `metadata->>'source'`,
--    escrito pelo proprio ato.
--
-- 3. A JANELA VIVE EM DADO. `floor_date` e um FATO DE COMUNICACAO, nao uma constante: mudar a
--    carencia nao pode exigir DDL. E o corte do piso e por data LOCAL — `CURRENT_DATE` e UTC, e das
--    21h a meia-noite de Brasilia ele cruzaria a data prometida as pessoas horas antes. Mesma borda
--    que o #1727 ja pagou uma vez, no mesmo mecanismo.
--
-- Provado ao vivo em transacao abortada (13/08/2026), com o piso recuado so dentro dela:
--   ensaio -> events_due 31, events_would_seal 28, absences_would_write 51, events_skipped 3
--             e escreveu 0 carimbos e 0 linhas
--   ato    -> events_sealed 28, absences_written 51 (os MESMOS numeros)
--             28 linhas de auditoria com source=window_cron, 0 linhas do selo com ator nao nulo

CREATE OR REPLACE FUNCTION public._seal_event_attendance_apply(p_event_id uuid, p_actor_id uuid, p_dry_run boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
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

  -- A coorte e quantos dela ja tem registro saem da MESMA passagem: assim o numero que o ensaio
  -- publica e o numero que a gravacao produz, e nao duas contas que podem divergir.
  -- #1476 Onda 2: coorte operacional por engagement (junction), nao pelo cache operational_role.
  WITH coorte AS (
    SELECT m.id
    FROM public.members m
    WHERE m.is_active = true AND m.current_cycle_active = true
      AND EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
                  WHERE vt.member_id = m.id AND vt.operational_tier IN ('researcher','tribe_leader','manager'))
      AND EXISTS (
        SELECT 1 FROM public._attendance_eligible_events(m.id, NULL) ee WHERE ee.event_id = p_event_id
      )
  )
  SELECT count(*)::int, count(a.member_id)::int
    INTO v_eligible, v_recorded
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
      'would_write_absent_n', GREATEST(v_eligible - v_recorded, 0),
      'roster_sealed_at', v_sealed_at
    );
  END IF;

  INSERT INTO public.attendance (event_id, member_id, present, excused, organization_id, notes, registered_by, marked_by, checked_in_at)
  SELECT p_event_id, m.id, false, false, v_org,
         public._roster_seal_marker(), p_actor_id, p_actor_id, NULL
  FROM public.members m
  WHERE m.is_active = true AND m.current_cycle_active = true
    AND EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
                WHERE vt.member_id = m.id AND vt.operational_tier IN ('researcher','tribe_leader','manager'))
    AND EXISTS (
      SELECT 1 FROM public._attendance_eligible_events(m.id, NULL) ee WHERE ee.event_id = p_event_id
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
      'eligible_cohort_n', v_eligible, 'sealed_absent_count', v_sealed,
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
    'sealed_absent_count', v_sealed,
    'already_recorded_count', GREATEST(v_eligible - v_sealed, 0),
    'roster_sealed_at', v_sealed_at
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.seal_event_attendance(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.events e WHERE e.id = p_event_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Evento não encontrado', 'event_id', p_event_id);
  END IF;

  -- #1710: era `can_by_member(v_caller_id, 'manage_event')`, um gate SEM recurso. Medido em
  -- 13/08/2026: 622 pares (lider, evento) passavam por ele e nao pelo escopado, cada lider de tribo
  -- alcancando 49 a 55 eventos de OUTRAS tribos. Mesma classe do #1728.
  IF NOT public._can_manage_event(p_event_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Acesso negado: requer manage_event neste evento');
  END IF;

  RETURN public._seal_event_attendance_apply(p_event_id, v_caller_id, false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.seal_attendance_window_cron(p_dry_run boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_cfg        jsonb;
  v_grace      int;
  v_floor      date;
  v_hoje_local date;
  r            record;
  v_res        jsonb;
  v_eventos    int := 0;
  v_selados    int := 0;
  v_faltas     int := 0;
  v_pulados    int := 0;
  v_detalhe    jsonb := '[]'::jsonb;
BEGIN
  SELECT value INTO v_cfg FROM public.platform_settings WHERE key = 'attendance.seal_window';
  IF v_cfg IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'attendance.seal_window ausente em platform_settings');
  END IF;
  v_grace := COALESCE((v_cfg->>'grace_days')::int, 14);
  v_floor := (v_cfg->>'floor_date')::date;

  -- #1727 outra vez: `CURRENT_DATE` e UTC. Das 21h a meia-noite de Brasilia o banco ja virou o dia,
  -- e o piso da comunicacao seria cruzado algumas horas antes da data prometida as pessoas.
  v_hoje_local := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  IF v_floor IS NOT NULL AND v_hoje_local < v_floor THEN
    RETURN jsonb_build_object(
      'success', true, 'skipped', 'before_floor',
      'floor_date', v_floor, 'local_date', v_hoje_local, 'dry_run', p_dry_run);
  END IF;

  FOR r IN
    SELECT e.id
    FROM public.events e
    WHERE e.roster_sealed_at IS NULL
      AND e.status IS DISTINCT FROM 'cancelled'
      AND e.type IN ('geral','kickoff','tribo','lideranca')
      -- A MESMA fronteira que `_attendance_eligible_events` aplica. Sem ela o laco varreria os 313
      -- eventos passados todos os dias para pular ~250 por coorte vazia: caro, e um `events_due`
      -- inflado que nao descreve trabalho nenhum. O aviso do #1726 ja disse que o historico
      -- anterior ao ciclo nao sera fechado.
      AND e.date >= (SELECT c.cycle_start FROM public.cycles c WHERE c.is_current = true LIMIT 1)
      AND public._event_end_instant(e.date, e.time_start, e.duration_minutes, e.timezone)
          <= now() - (v_grace || ' days')::interval
    ORDER BY e.date
  LOOP
    v_eventos := v_eventos + 1;
    v_res := public._seal_event_attendance_apply(r.id, NULL, p_dry_run);
    IF (v_res->>'success')::boolean THEN
      v_selados := v_selados + 1;
      v_faltas := v_faltas + COALESCE((v_res->>'sealed_absent_count')::int,
                                      (v_res->>'would_write_absent_n')::int, 0);
      v_detalhe := v_detalhe || v_res;
    ELSE
      -- Coorte vazia e o desfecho ESPERADO para evento fora do ciclo de elegibilidade: nao e erro,
      -- e nao pode ser contado como selo. Registrar o motivo evita que "0 selados" pareca falha.
      v_pulados := v_pulados + 1;
      v_detalhe := v_detalhe || jsonb_build_object(
        'event_id', r.id, 'skipped', COALESCE(v_res->>'reason', v_res->>'error'));
    END IF;
  END LOOP;

  -- O ensaio NAO pode devolver as mesmas chaves do ato. `events_sealed: 12` num dry-run le como
  -- "12 eventos foram selados" para qualquer um que olhe o retorno sem reparar no `dry_run: true` —
  -- e um numero certo com significado errado, que e a familia de defeito que este item ja pagou 3x.
  RETURN jsonb_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'grace_days', v_grace,
    'floor_date', v_floor,
    'local_date', v_hoje_local,
    'events_due', v_eventos,
    'events_skipped', v_pulados,
    'detail', v_detalhe
  ) || CASE WHEN p_dry_run
         THEN jsonb_build_object('events_would_seal', v_selados, 'absences_would_write', v_faltas)
         ELSE jsonb_build_object('events_sealed', v_selados, 'absences_written', v_faltas)
       END;
END;
$function$;

COMMENT ON FUNCTION public._seal_event_attendance_apply(uuid, uuid, boolean) IS
  '#1710: nucleo do selo — tudo o que NAO depende do chamador. Os gates ficam em seal_event_attendance (usuario) e a ausencia deles no caminho do cron e deliberada; p_actor_id NULO carimba source=window_cron no audit log.';

COMMENT ON FUNCTION public.seal_attendance_window_cron(boolean) IS
  '#1710: sela todo evento que terminou ha mais de grace_days, nunca antes de floor_date (data local). p_dry_run=true faz o ensaio pela MESMA funcao que executa.';

-- A configuracao da janela: dado, nao literal.
INSERT INTO public.platform_settings (key, value, description, change_reason)
VALUES (
  'attendance.seal_window',
  '{"grace_days": 14, "floor_date": "2026-08-24"}'::jsonb,
  'Janela do selo automatico de presenca (#1710). grace_days: dias entre o FIM do evento e o selo, para o lider corrigir registro faltante. floor_date: nada sela antes desta data — sao os 14 dias prometidos no aviso do #1726, enviado em 10/08/2026.',
  '#1710 onda D — parametros da janela decididos pelo PM em 13/08/2026'
)
ON CONFLICT (key) DO NOTHING;

-- Nem o nucleo nem o cron sao superficie de usuario: os dois so existem para o caminho automatico
-- e para a RPC gateada. `CREATE FUNCTION` concede EXECUTE a PUBLIC por padrao (foi o que pegou as
-- funcoes da primeira onda), entao a revogacao vem junto e nao depois.
REVOKE EXECUTE ON FUNCTION public._seal_event_attendance_apply(uuid, uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.seal_attendance_window_cron(boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._seal_event_attendance_apply(uuid, uuid, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.seal_attendance_window_cron(boolean) TO service_role;

-- O agendamento. 11:40 UTC = 08:40 BRT; a faixa das 11h UTC estava vazia (conferido contra
-- `cron.job` em 13/08), entao o selo nao disputa janela com nenhum outro job.
--
-- O job entra ATIVO de proposito. Quem segura o gatilho e o `floor_date`, que e dado e pode ser
-- lido, medido e movido — e nao uma flag `enabled` que alguem precisaria lembrar de virar, sem tela
-- para faze-lo. Um mecanismo que depende de alguem lembrar e o defeito que esta issue existe para
-- consertar.
SELECT cron.unschedule('attendance-seal-window-daily')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'attendance-seal-window-daily');

SELECT cron.schedule(
  'attendance-seal-window-daily',
  '40 11 * * *',
  $cron$SELECT public.seal_attendance_window_cron();$cron$
);

NOTIFY pgrst, 'reload schema';
