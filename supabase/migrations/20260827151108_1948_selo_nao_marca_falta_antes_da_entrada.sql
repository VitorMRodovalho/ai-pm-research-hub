-- #1948 — o selo para de gravar falta em reuniao ANTERIOR a entrada da pessoa.
--
-- DECISAO DO PM (27/08/2026): o corte e a ENTRADA NA TRIBO. Este arquivo implementa essa decisao
-- na forma generalizada que ela exige, pelos motivos medidos abaixo.
--
-- ── Por que "entrada na tribo" virou "primeiro engajamento" ───────────────────────────────────
-- A reuniao GERAL tem na coorte gente sem engajamento de tribo: medido em 27/08, 2 das 72 pessoas
-- da coorte operacional nao tem NENHUM engajamento de tribo (entram por manager/deputy). Um
-- predicado que olhasse so a tribo devolveria NULL para essas duas e as tiraria do selo inteiro —
-- trocaria este defeito por outro, pior, porque silencioso. O predicado e o PRIMEIRO ENGAJAMENTO
-- da pessoa, que para quem entra por tribo E a entrada na tribo (as duas definicoes concordam nas
-- 17 linhas de hoje) e que existe para as 72.
--
-- `min(granted_at)` NAO filtra `revoked_at IS NULL`, de proposito: um engajamento desde entao
-- revogado ainda PROVA que a pessoa estava na organizacao naquela data. Filtrar revogados faz a
-- pessoa parecer ter entrado depois do que entrou — foi o que inflou a primeira medicao de 17
-- para 18.
--
-- ── Por que gravar linha JUSTIFICADA em vez de tirar da coorte ────────────────────────────────
-- O selo carrega uma invariante declarada no proprio corpo (#1729/#1657): "materializa a linha de
-- no-show, entao selado + sem linha nao ocorre; o ELSE cobre so o residuo". As TRES grades
-- (`get_attendance_grid`, `get_tribe_attendance_grid`, `get_initiative_attendance_grid`) dependem
-- disso: nelas, `roster_sealed_at IS NOT NULL` + linha ausente = 'absent'.
--
-- Tirar a pessoa da coorte quebraria essa invariante e moveria o defeito para a leitura — o mesmo
-- numero de faltas falsas, agora sem nenhuma linha para auditar. A saida e manter a coorte e
-- gravar `excused = true` com motivo: a linha existe (invariante preservada), diz o fato certo, e
-- `excused` ja e EXCLUIDO do denominador em toda a cadeia de leitura (medido em 27/08:
-- `get_attendance_rate` divide por `count(*) FILTER (WHERE a.excused IS NOT TRUE)`, e as tres
-- grades contam a taxa sobre ('present','absent','unrecorded')). A pessoa nao e punida e nao vira
-- oportunidade perdida.
--
-- ── Medido antes de aplicar (27/08/2026) ─────────────────────────────────────────────────────
--   faltas em evento selado ................................ 554
--   ANTES da entrada da pessoa .............................. 17  (4 pessoas, 8 eventos)
--   evento mais antigo ...................................... 2026-07-09
--   CONTROLE, presencas registradas antes da entrada ........ 0   <- se nao fosse 0, o predicado
--                                                                   estaria mentindo
--   coorte operacional ...................................... 72  (0 sem engajamento nenhum)

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 1. SSOT: uma definicao de "desde quando esta pessoa podia ser esperada numa reuniao".
-- ─────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._member_operational_since(p_member_id uuid)
RETURNS date
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT COALESCE(
    (SELECT min(en.granted_at)::date
       FROM public.engagements en
       JOIN public.members m ON m.id = p_member_id
      WHERE en.person_id = m.person_id),
    (SELECT m.created_at::date FROM public.members m WHERE m.id = p_member_id)
  );
$function$;

COMMENT ON FUNCTION public._member_operational_since(uuid) IS
  '#1948 — data do PRIMEIRO engajamento da pessoa (revogados incluem-se: revogado ainda prova '
  'presenca na data). Fallback para members.created_at. SSOT do corte "esta pessoa era esperada '
  'nesta reuniao?" — usada pelo selo e por qualquer guard que precise da mesma pergunta.';

-- `CREATE FUNCTION` nasce com EXECUTE para PUBLIC (e portanto para anon).
REVOKE ALL ON FUNCTION public._member_operational_since(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._member_operational_since(uuid) TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 2. ESCRITA: o selo continua materializando a linha para TODA a coorte (invariante do #1729),
--    mas quem entrou depois do evento recebe linha JUSTIFICADA em vez de falta.
--    Corpo derivado do vivo (md5 conferido em 27/08); as mudancas sao a contagem `v_pre_entry`,
--    o LATERAL com o corte, as duas colunas novas no INSERT e as chaves novas nos payloads.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
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
  v_pre_entry int := 0;
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
  -- #1948: a coorte NAO muda — quem entrou depois do evento continua nela, e a distincao vai na
  -- COLUNA da linha, nao na presenca dela. Tirar da coorte quebraria "selado => linha existe".
  WITH coorte AS (
    SELECT m.id, (v_date < public._member_operational_since(m.id)) AS pre_entry
    FROM public.members m
    WHERE m.is_active = true AND m.current_cycle_active = true
      AND EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
                  WHERE vt.member_id = m.id AND vt.operational_tier IN ('researcher','tribe_leader','manager'))
      AND EXISTS (
        SELECT 1 FROM public._attendance_eligible_events(m.id, NULL) ee WHERE ee.event_id = p_event_id
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

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 3. CORRECAO das linhas ja gravadas.
--    Escrito pela REGRA, nao por lista de ids: uma lista fixa envelhece e nao cobre o que o selo
--    gravou entre a medicao e o apply. A regra e a mesma que a escrita passa a usar, entao as duas
--    pontas nao podem divergir.
--    Nao toca em linha `present` — o controle mediu 0 presencas antes da entrada, e se um dia
--    houver uma, ela e um fato a investigar, nao a sobrescrever.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
UPDATE public.attendance a
   SET excused       = true,
       excuse_reason = COALESCE(a.excuse_reason, 'Ingresso posterior ao evento (#1948)'),
       updated_at    = now()
  FROM public.events e
 WHERE e.id = a.event_id
   AND e.roster_sealed_at IS NOT NULL
   AND a.present = false
   AND a.excused IS NOT TRUE
   AND e.date < public._member_operational_since(a.member_id);

-- Confirmar o EFEITO, nao a ausencia de erro. Se sobrar qualquer falta anterior a entrada, o apply
-- FALHA alto em vez de deixar a migration passar por cima do defeito que veio consertar.
DO $do$
DECLARE
  v_left    int;
  v_present int;
BEGIN
  SELECT count(*) FILTER (WHERE a.present = false AND a.excused IS NOT TRUE),
         count(*) FILTER (WHERE a.present = true)
    INTO v_left, v_present
  FROM public.attendance a
  JOIN public.events e ON e.id = a.event_id
  WHERE e.roster_sealed_at IS NOT NULL
    AND e.date < public._member_operational_since(a.member_id);

  IF v_left <> 0 THEN
    RAISE EXCEPTION '#1948: sobraram % faltas anteriores a entrada depois da correcao', v_left;
  END IF;
  -- Controle POSITIVO na mesma transacao: se ninguem NUNCA aparece como presente antes da propria
  -- entrada, o predicado pode estar certo — ou pode nao estar casando linha nenhuma. Este numero
  -- distingue os dois casos e vai para o log do apply.
  RAISE NOTICE '#1948: presencas registradas antes da entrada (controle, esperado 0): %', v_present;
END $do$;

NOTIFY pgrst, 'reload schema';
