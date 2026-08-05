-- ============================================================================
-- #1609 + #1611 — A PORTA DE ENTRADA DO AGENDAMENTO
-- ----------------------------------------------------------------------------
-- Contexto (medido em 2026-08-05, produção):
--
--   admin_audit_log, ação `calendar_booking_unmatched`, histórico completo:
--     16.486 linhas  /  18 e-mails  /  30 eventos   → "não existe candidatura"
--        143 linhas  /   3 e-mails  /   4 eventos   → resolve, mas CICLO FECHADO
--         89 linhas  /   1 e-mail   /   1 evento    → resolve, mas STATUS decidido
--
--   Assimetria que enquadra o #1609: `calendar_booking_synced` gravou 9 linhas
--   para 6 eventos (~1,5 linhas/evento); `calendar_booking_unmatched` gravou
--   ~1.093 linhas por evento. Sucesso é silencioso, falha é tempestade.
--
--   Causa-raiz na ORIGEM (fora deste repositório): o Apps Script
--   `nucleoia-calendar-sync` varre 90 dias à frente a cada 5 min e, no branch
--   404, DELIBERADAMENTE não marca o evento como processado ("se a candidatura
--   for movida para a fase certa depois, a próxima varredura reenvia e casa").
--   A intenção é auto-cura; o defeito é não ter limite. Um evento que não casa
--   é reenviado a cada 5 min até a sua data passar. O script é corrigido em
--   separado; ESTA migration é a defesa do lado da plataforma, que precisa
--   valer mesmo que a origem volte a errar.
--
-- O que muda:
--
--   1. #1611 — `match_booking_application` passa a devolver o MOTIVO. Hoje ela
--      faz RETURN QUERY e devolve conjunto VAZIO nos três casos (não achei /
--      status fora da allow-list / ciclo fechado), e o chamador não tem como
--      distinguir — não há informação para distinguir. Passa a devolver SEMPRE
--      exatamente UMA linha, com `match_outcome` ∈ {matched, no_application,
--      status_not_allowed, cycle_closed}. Mudança de FORMA de retorno → DROP +
--      CREATE. Consumidor inventariado ANTES: `src/pages/api/calendar-webhook.ts`
--      é o ÚNICO (zero funções SQL chamam a RPC, zero ferramentas MCP).
--
--   2. #1609 — `selection_booking_attempts`: UMA linha por (evento, convidado),
--      com contador, em vez de N linhas de log. `record_booking_attempt` decide
--      se aquela tentativa merece uma linha de auditoria; depois do corte
--      (10 tentativas) só um desfecho `matched` volta a auditar.
--
--   3. R4.2/R4.3 — `get_booking_exception_queue` torna a fila visível ao GP sem
--      varrer `admin_audit_log`.
--
--   4. O consumidor contaminado: `selection_consistency_report` contava LINHAS
--      de log na classe (e). Medido em 05/08, antes desta migration, o relatório
--      dizia `integrity_anomaly_total` = 3.278 — e os 3.278 eram da classe (e),
--      com `affected_applications_distinct` = 0. Passa a contar pares
--      (evento, convidado) NÃO resolvidos e SÓ o desfecho acionável.
--
-- ROLLBACK:
--   DROP FUNCTION public.get_booking_exception_queue(boolean);
--   DROP FUNCTION public.record_booking_attempt(text, text, text, timestamptz);
--   DROP TABLE public.selection_booking_attempts;
--   -- e re-aplicar 20260805000096 (matcher sem motivo) + 20260805000097
--   -- (classe (e) lendo admin_audit_log). Nenhum dado de candidatura é tocado.
-- ============================================================================

-- ── 1. contador por (evento, convidado) ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.selection_booking_attempts (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  calendar_event_id  text        NOT NULL,
  guest_email        text        NOT NULL,   -- normalizado LOWER(TRIM) na escrita
  attempts           integer     NOT NULL DEFAULT 0,
  first_seen_at      timestamptz NOT NULL DEFAULT now(),
  last_seen_at       timestamptz NOT NULL DEFAULT now(),
  last_outcome       text        NOT NULL,
  outcome_changed_at timestamptz NOT NULL DEFAULT now(),
  last_scheduled_at  timestamptz,
  suppressed_at      timestamptz,            -- corte: parou de gerar auditoria
  resolved_at        timestamptz,            -- casou com uma candidatura
  CONSTRAINT selection_booking_attempts_pair_uniq
    UNIQUE (calendar_event_id, guest_email),
  CONSTRAINT selection_booking_attempts_outcome_chk
    CHECK (last_outcome IN ('matched','no_application','status_not_allowed','cycle_closed'))
);

CREATE INDEX IF NOT EXISTS selection_booking_attempts_queue_idx
  ON public.selection_booking_attempts (last_outcome, resolved_at, last_seen_at DESC);

ALTER TABLE public.selection_booking_attempts ENABLE ROW LEVEL SECURITY;

-- Sem POLICY por desenho: a tabela guarda e-mail de candidato (PII). O acesso é
-- exclusivamente por `record_booking_attempt` (escrita, service_role) e
-- `get_booking_exception_queue` (leitura, gate de autoridade no corpo). anon e
-- authenticated não alcançam a tabela diretamente — RLS habilitada sem policy
-- nega tudo, e service_role a ignora por ser BYPASSRLS.

COMMENT ON TABLE public.selection_booking_attempts IS
  '#1609: uma linha por (calendar_event_id, guest_email) com contador de tentativas, '
  'no lugar de uma linha de admin_audit_log por tentativa. Antes disto, 11 reservas '
  'produziram 16.486 linhas de auditoria (~1.093 por evento) porque o Apps Script de '
  'origem reenvia o mesmo evento a cada 5 min enquanto ele não casar. É também a fila '
  'de exceção do GP (R4.2) e a superfície de observabilidade que dispensa varrer '
  'admin_audit_log (R4.3).';

COMMENT ON COLUMN public.selection_booking_attempts.suppressed_at IS
  'Quando o corte disparou (10 tentativas). Depois disto a tentativa continua a ser '
  'CONTADA, mas deixa de gerar linha de auditoria — só um desfecho `matched` volta a '
  'auditar (e zera a supressão).';

COMMENT ON COLUMN public.selection_booking_attempts.last_outcome IS
  '#1611: o motivo devolvido por match_booking_application. `no_application` é o único '
  'desfecho ACIONÁVEL (a plataforma tem um buraco); `status_not_allowed` e `cycle_closed` '
  'são a plataforma FUNCIONANDO — a recusa está correta por desenho.';

-- ── 2. #1611 — o matcher passa a devolver o MOTIVO ───────────────────────────
-- Muda a FORMA do retorno (coluna nova + sempre uma linha) → DROP + CREATE.
DROP FUNCTION IF EXISTS public.match_booking_application(text);

CREATE OR REPLACE FUNCTION public.match_booking_application(p_guest_email text)
RETURNS TABLE (
  application_id   uuid,
  applicant_name   text,
  app_status       text,
  interview_status text,
  cycle_id         uuid,
  matched_by       text,
  match_outcome    text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_guest text;
  v_guest_member_id uuid;
  v_allow text[] := ARRAY['submitted', 'screening', 'objective_eval', 'objective_cutoff',
                          'interview_pending', 'interview_scheduled'];
  v_row record;
BEGIN
  v_guest := NULLIF(LOWER(TRIM(p_guest_email)), '');
  IF v_guest IS NULL THEN
    -- #1611: nunca mais conjunto vazio. Sem e-mail não há como resolver nada,
    -- e isso é indistinguível de "não existe candidatura" para o chamador.
    RETURN QUERY SELECT NULL::uuid, NULL::text, NULL::text, NULL::text, NULL::uuid,
                        NULL::text, 'no_application'::text;
    RETURN;
  END IF;

  -- alternate-email bridge: resolve the guest email to a member (if any). Um
  -- candidato PODE já ser membro — medido em 2026-08-05, 51 de 81 candidaturas
  -- do ciclo aberto (63%) já têm o e-mail em member_emails —, então esta ponte
  -- não é o caso raro que o comentário anterior supunha. O que ela exige é o
  -- MESMO member_id nos dois lados, o que zera o risco de casar candidatos
  -- diferentes.
  SELECT me.member_id INTO v_guest_member_id
  FROM public.member_emails me
  WHERE me.email = v_guest::citext
  LIMIT 1;

  -- UMA varredura sobre todas as candidaturas que o e-mail resolve (primária ou
  -- alternada do mesmo membro), classificando cada uma e escolhendo a melhor.
  -- A ordenação põe TODAS as candidaturas elegíveis (ciclo aberto/ativo + status
  -- na allow-list) à frente, e só então aplica o desempate herdado da corr-1
  -- (primária > ciclo aberto mais recente > candidatura mais nova) — de modo que
  -- a linha escolhida no caso `matched` é a MESMA que a versão anterior escolhia.
  SELECT a.id,
         a.applicant_name,
         a.status,
         a.interview_status,
         a.cycle_id,
         (CASE WHEN LOWER(TRIM(a.email)) = v_guest THEN 'primary' ELSE 'alternate' END)::text AS matched_by,
         (CASE
            WHEN c.status IN ('open', 'active') AND a.status = ANY (v_allow) THEN 'matched'
            WHEN c.status IN ('open', 'active')                              THEN 'status_not_allowed'
            ELSE                                                                  'cycle_closed'
          END)::text AS match_outcome
  INTO v_row
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE (
      LOWER(TRIM(a.email)) = v_guest
      OR (
        v_guest_member_id IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM public.member_emails me2
          WHERE me2.member_id = v_guest_member_id
            AND me2.email = LOWER(TRIM(a.email))::citext
        )
      )
    )
  ORDER BY (CASE
              WHEN c.status IN ('open', 'active') AND a.status = ANY (v_allow) THEN 0
              WHEN c.status IN ('open', 'active')                              THEN 1
              ELSE                                                                  2
            END),
           (LOWER(TRIM(a.email)) = v_guest) DESC,
           c.open_date DESC NULLS LAST,
           a.created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN QUERY SELECT NULL::uuid, NULL::text, NULL::text, NULL::text, NULL::uuid,
                        NULL::text, 'no_application'::text;
    RETURN;
  END IF;

  -- Nos desfechos de recusa a identidade da candidatura VAI JUNTO de propósito:
  -- é o que permite ao GP ver, na fila de exceção, que a reserva foi recusada
  -- CORRETAMENTE (candidatura já decidida) em vez de perdida. O chamador é
  -- service_role apenas, e o gate de promoção continua sendo `match_outcome`.
  RETURN QUERY SELECT v_row.id, v_row.applicant_name, v_row.status, v_row.interview_status,
                      v_row.cycle_id, v_row.matched_by, v_row.match_outcome;
END;
$function$;

COMMENT ON FUNCTION public.match_booking_application(text) IS
  '#1611: devolve SEMPRE uma linha, com `match_outcome` ∈ (matched, no_application, '
  'status_not_allowed, cycle_closed). Antes devolvia conjunto vazio nos três casos de '
  'recusa, e o webhook gravava os três sob a mesma ação `calendar_booking_unmatched` — '
  'misturando "a plataforma tem um buraco" com "a plataforma funcionou". Só `matched` '
  'autoriza promover a candidatura.';

-- ── 3. #1609 — contabiliza a tentativa e decide se ela merece auditoria ──────
CREATE OR REPLACE FUNCTION public.record_booking_attempt(
  p_calendar_event_id text,
  p_guest_email       text,
  p_outcome           text,
  p_scheduled_at      timestamptz DEFAULT NULL
)
RETURNS TABLE (
  attempts         integer,
  should_audit     boolean,
  suppressed       boolean,
  outcome_changed  boolean,
  first_seen_at    timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  -- Corte: a partir daqui a tentativa é contada mas não auditada. 10 é o mesmo
  -- teto do Apps Script corrigido, para que os dois lados desistam juntos.
  c_audit_cut constant integer := 10;
  v_event text;
  v_guest text;
  v_prev  public.selection_booking_attempts%ROWTYPE;
  v_row   public.selection_booking_attempts%ROWTYPE;
  v_changed boolean;
  v_just_suppressed boolean;
BEGIN
  v_event := NULLIF(TRIM(p_calendar_event_id), '');
  v_guest := NULLIF(LOWER(TRIM(p_guest_email)), '');
  IF v_event IS NULL OR v_guest IS NULL THEN
    RAISE EXCEPTION 'record_booking_attempt: calendar_event_id e guest_email são obrigatórios';
  END IF;
  IF p_outcome IS NULL OR p_outcome NOT IN ('matched','no_application','status_not_allowed','cycle_closed') THEN
    RAISE EXCEPTION 'record_booking_attempt: outcome inválido: %', COALESCE(p_outcome, '<null>');
  END IF;

  SELECT * INTO v_prev
  FROM public.selection_booking_attempts
  WHERE calendar_event_id = v_event AND guest_email = v_guest;

  INSERT INTO public.selection_booking_attempts AS ba (
    calendar_event_id, guest_email, attempts, first_seen_at, last_seen_at,
    last_outcome, outcome_changed_at, last_scheduled_at, resolved_at, suppressed_at
  )
  VALUES (
    v_event, v_guest, 1, now(), now(),
    p_outcome, now(), p_scheduled_at,
    CASE WHEN p_outcome = 'matched' THEN now() ELSE NULL END,
    NULL
  )
  ON CONFLICT (calendar_event_id, guest_email) DO UPDATE SET
    attempts     = ba.attempts + 1,
    last_seen_at = now(),
    last_outcome = EXCLUDED.last_outcome,
    outcome_changed_at = CASE WHEN ba.last_outcome IS DISTINCT FROM EXCLUDED.last_outcome
                              THEN now() ELSE ba.outcome_changed_at END,
    last_scheduled_at  = COALESCE(EXCLUDED.last_scheduled_at, ba.last_scheduled_at),
    resolved_at = CASE WHEN EXCLUDED.last_outcome = 'matched'
                       THEN COALESCE(ba.resolved_at, now()) ELSE ba.resolved_at END,
    -- `matched` ZERA a supressão: se o par voltar a falhar depois de ter casado,
    -- isso é fato novo e merece uma primeira linha de novo.
    suppressed_at = CASE
                      WHEN EXCLUDED.last_outcome = 'matched'    THEN NULL
                      WHEN ba.suppressed_at IS NOT NULL         THEN ba.suppressed_at
                      WHEN ba.attempts + 1 >= c_audit_cut       THEN now()
                      ELSE NULL
                    END
  RETURNING * INTO v_row;

  v_changed := (v_prev.calendar_event_id IS NULL)
               OR (v_prev.last_outcome IS DISTINCT FROM p_outcome);
  v_just_suppressed := (v_prev.suppressed_at IS NULL) AND (v_row.suppressed_at IS NOT NULL);

  -- Política de auditoria — o teto por par é ~5 linhas, contra as ~1.093 de antes:
  --   • a PRIMEIRA aparição do par sempre entra (é o fato "houve uma reserva órfã");
  --   • uma MUDANÇA de desfecho entra enquanto o par não estiver suprimido;
  --   • o disparo do corte entra UMA vez (é o fato "desisti de logar isto");
  --   • depois do corte, só `matched` volta a entrar — que é a resolução.
  should_audit := (v_row.attempts = 1)
                  OR v_just_suppressed
                  OR (v_changed AND (v_prev.suppressed_at IS NULL OR p_outcome = 'matched'));

  attempts        := v_row.attempts;
  suppressed      := v_row.suppressed_at IS NOT NULL;
  outcome_changed := v_changed;
  first_seen_at   := v_row.first_seen_at;
  RETURN NEXT;
END;
$function$;

COMMENT ON FUNCTION public.record_booking_attempt(text, text, text, timestamptz) IS
  '#1609: conta a tentativa por (evento, convidado) e devolve should_audit — o webhook '
  'só grava em admin_audit_log quando esta função autoriza. Sem isto, o Apps Script de '
  'origem (5 em 5 min, horizonte de 90 dias) grava uma linha por varredura enquanto a '
  'reserva não casar: 5.693 linhas para UM evento foi o pior caso medido.';

-- ── 4. R4.2/R4.3 — a fila de exceção, sem varrer admin_audit_log ─────────────
CREATE OR REPLACE FUNCTION public.get_booking_exception_queue(
  p_include_resolved boolean DEFAULT false
)
RETURNS TABLE (
  calendar_event_id text,
  guest_email       text,
  attempts          integer,
  first_seen_at     timestamptz,
  last_seen_at      timestamptz,
  last_outcome      text,
  actionable        boolean,
  suppressed        boolean,
  resolved_at       timestamptz,
  last_scheduled_at timestamptz,
  application_id    uuid,
  applicant_name    text,
  app_status        text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
BEGIN
  -- Gate: a fila expõe e-mail de candidato (PII). Mesma escada de
  -- get_application_gate_attempts, sem o escopo por candidatura (a fila é
  -- global): comissão de QUALQUER ciclo, ou autoridade de plataforma/membro.
  -- Contexto sem JWT (pg_cron / service_role) é o caminho auto-executável.
  IF auth.uid() IS NOT NULL THEN
    SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
    IF v_caller IS NULL THEN
      RAISE EXCEPTION 'Unauthorized: member not found';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.selection_committee sc WHERE sc.member_id = v_caller.id)
       AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text)
       AND NOT public.can_by_member(v_caller.id, 'manage_member'::text)
       AND NOT public.can_by_member(v_caller.id, 'view_internal_analytics'::text)
    THEN
      RAISE EXCEPTION 'Unauthorized: must be selection committee or have manage_platform/manage_member/view_internal_analytics';
    END IF;
  END IF;

  RETURN QUERY
  SELECT ba.calendar_event_id,
         ba.guest_email,
         ba.attempts,
         ba.first_seen_at,
         ba.last_seen_at,
         ba.last_outcome,
         -- #1611: só `no_application` é buraco da plataforma. Os outros dois
         -- desfechos são recusa CORRETA e entram na fila apenas como contexto.
         (ba.last_outcome = 'no_application' AND ba.resolved_at IS NULL) AS actionable,
         (ba.suppressed_at IS NOT NULL) AS suppressed,
         ba.resolved_at,
         ba.last_scheduled_at,
         m.application_id,
         m.applicant_name,
         m.app_status
  FROM public.selection_booking_attempts ba
  LEFT JOIN LATERAL public.match_booking_application(ba.guest_email) m ON true
  WHERE (p_include_resolved OR ba.resolved_at IS NULL)
  ORDER BY (ba.last_outcome = 'no_application' AND ba.resolved_at IS NULL) DESC,
           ba.last_seen_at DESC;
END;
$function$;

COMMENT ON FUNCTION public.get_booking_exception_queue(boolean) IS
  'R4.2/R4.3 (#1609): fila de reservas de entrevista que não viraram entrevista, legível '
  'sem varrer admin_audit_log. `actionable` separa o buraco real (nenhuma candidatura '
  'resolve o e-mail) da recusa correta por status/ciclo (#1611).';

-- ── 5. o consumidor contaminado: classe (e) do relatório de consistência ────
-- Inventariar os consumidores É parte da mudança (#1594, depois #1598 — a lição
-- que já mordeu duas vezes neste arco). O único consumidor SQL do balde é este.
CREATE OR REPLACE FUNCTION public.selection_consistency_report(p_cycle_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_pre_interview text[] := ARRAY['submitted','screening','objective_eval','objective_cutoff'];
  v_decided text[] := ARRAY['final_eval','interview_done','approved','rejected','converted',
                            'withdrawn','cancelled','waitlist','interview_noshow'];
  v_a jsonb; v_b jsonb; v_c jsonb; v_d jsonb; v_e jsonb; v_disp jsonb;
  v_a_n int; v_b_n int; v_c_n int; v_d_n int; v_e_n int; v_disp_n int;
  v_distinct_apps int;  -- DISTINCT applications across A/B/C/D (B ⊆ D → a plain sum double-counts)
BEGIN
  -- Auth: authenticated callers need manage_platform; a no-JWT context
  -- (pg_cron / service_role) is the self-running path and is allowed.
  IF auth.uid() IS NOT NULL THEN
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'Unauthorized: manage_platform required';
    END IF;
  END IF;

  -- open/active cycles only (or the one requested), so we never alarm on closed cycles.
  -- a. scored but not advanced past a final/decided stage
  WITH oa AS (
    SELECT a.* FROM public.selection_applications a
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE c.status IN ('open','active')
      AND (p_cycle_id IS NULL OR a.cycle_id = p_cycle_id)
  ),
  rows_a AS (
    SELECT a.id, a.applicant_name, a.status, a.interview_score
    FROM oa a
    WHERE a.interview_score IS NOT NULL
      AND a.status <> ALL (v_decided)
  )
  SELECT count(*), COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.applicant_name) FILTER (WHERE r.rn <= 10), '[]'::jsonb)
  INTO v_a_n, v_a
  FROM (SELECT *, row_number() OVER (ORDER BY applicant_name) AS rn FROM rows_a) r;

  -- b. completed/conducted interview row but app still pre-interview
  WITH rows_b AS (
    SELECT DISTINCT a.id, a.applicant_name, a.status
    FROM public.selection_interviews si
    JOIN public.selection_applications a ON a.id = si.application_id
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE c.status IN ('open','active')
      AND (p_cycle_id IS NULL OR a.cycle_id = p_cycle_id)
      AND (si.status = 'completed' OR si.conducted_at IS NOT NULL)
      AND a.status = ANY (v_pre_interview)
  )
  SELECT count(*), COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.applicant_name) FILTER (WHERE r.rn <= 10), '[]'::jsonb)
  INTO v_b_n, v_b
  FROM (SELECT *, row_number() OVER (ORDER BY applicant_name) AS rn FROM rows_b) r;

  -- c. status interview_scheduled/interview_done but NO interview row
  --    (final_eval excluded — manual off-platform final is legitimate)
  WITH rows_c AS (
    SELECT a.id, a.applicant_name, a.status
    FROM public.selection_applications a
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE c.status IN ('open','active')
      AND (p_cycle_id IS NULL OR a.cycle_id = p_cycle_id)
      AND a.status IN ('interview_scheduled','interview_done')
      AND NOT EXISTS (SELECT 1 FROM public.selection_interviews si WHERE si.application_id = a.id)
  )
  SELECT count(*), COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.applicant_name) FILTER (WHERE r.rn <= 10), '[]'::jsonb)
  INTO v_c_n, v_c
  FROM (SELECT *, row_number() OVER (ORDER BY applicant_name) AS rn FROM rows_c) r;

  -- d. live interview row but app still pre-interview (orphan)
  WITH rows_d AS (
    SELECT DISTINCT a.id, a.applicant_name, a.status
    FROM public.selection_interviews si
    JOIN public.selection_applications a ON a.id = si.application_id
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE c.status IN ('open','active')
      AND (p_cycle_id IS NULL OR a.cycle_id = p_cycle_id)
      AND si.status NOT IN ('cancelled','noshow')
      AND a.status = ANY (v_pre_interview)
  )
  SELECT count(*), COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.applicant_name) FILTER (WHERE r.rn <= 10), '[]'::jsonb)
  INTO v_d_n, v_d
  FROM (SELECT *, row_number() OVER (ORDER BY applicant_name) AS rn FROM rows_d) r;

  -- e. calendar bookings that matched NO application in the last 7 days.
  --    #1611: isto contava LINHAS de admin_audit_log, e o webhook gravava uma
  --    linha por retentativa do Apps Script (5 em 5 min) — de modo que UMA
  --    reserva órfã inflava a manchete em milhares. Medido em 2026-08-05, antes
  --    da correção: integrity_anomaly_total = 3.278, com
  --    affected_applications_distinct = 0. A anomalia inteira era ruído de log.
  --    Passa a ler o contador por (evento, convidado) do #1609, e SÓ o desfecho
  --    acionável: `no_application`. Uma reserva recusada porque a candidatura já
  --    foi decidida (status_not_allowed) ou porque o ciclo fechou (cycle_closed)
  --    é a plataforma FUNCIONANDO — não é anomalia e não entra aqui.
  WITH rows_e AS (
    SELECT ba.calendar_event_id,
           ba.guest_email,
           ba.attempts,
           ba.first_seen_at,
           ba.last_seen_at AS created_at
    FROM public.selection_booking_attempts ba
    WHERE ba.last_outcome = 'no_application'
      AND ba.resolved_at IS NULL
      AND ba.last_seen_at >= now() - interval '7 days'
  )
  SELECT count(*), COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.created_at DESC) FILTER (WHERE r.rn <= 10), '[]'::jsonb)
  INTO v_e_n, v_e
  FROM (SELECT *, row_number() OVER (ORDER BY created_at DESC) AS rn FROM rows_e) r;

  -- DISTINCT affected applications across A/B/C/D — the human-facing "how many
  -- candidates are broken". The per-class counts above overlap (B ⊆ D: every
  -- completed/conducted row is also a live row), so summing them would double-count
  -- a single broken application. This recomputes the same predicates as a set.
  WITH oa AS (
    SELECT a.id, a.status, a.interview_score
    FROM public.selection_applications a
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE c.status IN ('open','active')
      AND (p_cycle_id IS NULL OR a.cycle_id = p_cycle_id)
  ),
  iv AS (
    SELECT si.application_id,
           bool_or(si.status = 'completed' OR si.conducted_at IS NOT NULL) AS has_done,
           bool_or(si.status NOT IN ('cancelled','noshow'))                AS has_live
    FROM public.selection_interviews si
    GROUP BY si.application_id
  )
  SELECT count(DISTINCT o.id) INTO v_distinct_apps
  FROM oa o
  LEFT JOIN iv ON iv.application_id = o.id
  WHERE (o.interview_score IS NOT NULL AND o.status <> ALL (v_decided))                          -- A
     OR (COALESCE(iv.has_done, false) AND o.status = ANY (v_pre_interview))                       -- B
     OR (o.status IN ('interview_scheduled','interview_done') AND iv.application_id IS NULL)      -- C
     OR (COALESCE(iv.has_live, false) AND o.status = ANY (v_pre_interview));                      -- D

  -- dispatch gap — INFORMATIONAL ONLY (the campaign path bypasses dispatch_url_log).
  -- Scoped to interview_pending/interview_scheduled — the statuses where the link is
  -- still operationally needed; interview_done/final_eval are excluded because the
  -- interview already occurred so a missing dispatch row there is stale history.
  SELECT count(*) INTO v_disp_n
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE c.status IN ('open','active')
    AND (p_cycle_id IS NULL OR a.cycle_id = p_cycle_id)
    AND a.status IN ('interview_pending','interview_scheduled')
    AND NOT EXISTS (SELECT 1 FROM public.selection_dispatch_url_log d WHERE d.application_id = a.id);
  v_disp := jsonb_build_object(
    'count', v_disp_n,
    'note', 'INFORMATIONAL — interview links may have gone out via the email campaign '
            || '(campaign_recipients/Resend), which does not write selection_dispatch_url_log. '
            || 'Not an alert; cross-check campaign delivery before acting.'
  );

  RETURN jsonb_build_object(
    'success', true,
    'scope', COALESCE(p_cycle_id::text, 'all open/active cycles'),
    'integrity_anomalies', jsonb_build_object(
      'scored_not_advanced',            jsonb_build_object('count', v_a_n, 'samples', v_a),
      'interview_completed_app_behind', jsonb_build_object('count', v_b_n, 'samples', v_b),
      'interview_phase_no_row',         jsonb_build_object('count', v_c_n, 'samples', v_c),
      'orphan_interview_row',           jsonb_build_object('count', v_d_n, 'samples', v_d),
      'unmatched_calendar_bookings_7d', jsonb_build_object('count', v_e_n, 'samples', v_e)
    ),
    'dispatch_gap_informational', jsonb_build_object('qualified_no_dispatch_log', v_disp),
    -- total = DISTINCT broken applications (A/B/C/D, deduplicated — B ⊆ D) + unmatched
    -- bookings (E, which are bookings, not applications, so additive). The per-class
    -- counts above are an overlapping breakdown; this is the non-double-counted headline.
    'affected_applications_distinct', v_distinct_apps,
    'integrity_anomaly_total', (v_distinct_apps + v_e_n),
    'has_integrity_anomaly', (v_distinct_apps + v_e_n) > 0
  );
END;
$function$;

-- ── 6. compactação do histórico para dentro do contador ─────────────────────
-- As 16.486 linhas históricas de `calendar_booking_unmatched` viram 30 linhas de
-- contador (uma por par evento/convidado), com o desfecho RECLASSIFICADO agora
-- pelo matcher novo — de modo que a fila de exceção já nasce dizendo a verdade
-- sobre cada reserva, em vez de começar vazia e mentir por omissão.
--
-- `suppressed_at` = última aparição: são pares que já estouraram qualquer corte,
-- e o que ainda estiver disparando (havia 1 evento ativo em 05/08 16:46 UTC) para
-- de gerar linha nova imediatamente.
--
-- As linhas de admin_audit_log NÃO são apagadas aqui. Expurgo é decisão do PM
-- (aceite do #1609 diz "decisão à parte") e é destrutivo; o contador já entrega
-- a compactação sem perder nada.
INSERT INTO public.selection_booking_attempts (
  calendar_event_id, guest_email, attempts, first_seen_at, last_seen_at,
  last_outcome, outcome_changed_at, suppressed_at
)
SELECT h.calendar_event_id,
       h.guest_email,
       h.n,
       h.first_seen,
       h.last_seen,
       COALESCE((SELECT m.match_outcome
                 FROM public.match_booking_application(h.guest_email) m), 'no_application'),
       h.last_seen,
       h.last_seen
FROM (
  SELECT NULLIF(TRIM(l.metadata->>'calendar_event_id'), '')       AS calendar_event_id,
         NULLIF(LOWER(TRIM(l.changes->>'guest_email')), '')       AS guest_email,
         count(*)                                                 AS n,
         min(l.created_at)                                        AS first_seen,
         max(l.created_at)                                        AS last_seen
  FROM public.admin_audit_log l
  WHERE l.action IN ('calendar_booking_unmatched', 'arm116.calendar_booking_unmatched')
  GROUP BY 1, 2
) h
WHERE h.calendar_event_id IS NOT NULL
  AND h.guest_email IS NOT NULL
ON CONFLICT (calendar_event_id, guest_email) DO NOTHING;

-- ── 7. escadas de grant ─────────────────────────────────────────────────────
-- O Supabase concede EXECUTE a anon/authenticated EXPLICITAMENTE via ALTER
-- DEFAULT PRIVILEGES, então REVOKE de PUBLIC sozinho não fecha nada.
REVOKE ALL ON FUNCTION public.match_booking_application(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.match_booking_application(text) TO service_role;

REVOKE ALL ON FUNCTION public.record_booking_attempt(text, text, text, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_booking_attempt(text, text, text, timestamptz) TO service_role;

-- Leitura com gate de autoridade no corpo → alcança o admin logado.
REVOKE ALL ON FUNCTION public.get_booking_exception_queue(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_booking_exception_queue(boolean) TO authenticated, service_role;

REVOKE ALL ON TABLE public.selection_booking_attempts FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
