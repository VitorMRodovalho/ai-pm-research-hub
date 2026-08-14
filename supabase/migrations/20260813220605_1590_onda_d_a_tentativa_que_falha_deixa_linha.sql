-- ============================================================================
-- #1590 onda D — a tentativa de agendamento que falha passa a deixar linha
-- ============================================================================
--
-- O item que nomeia a onda, do briefing de 12/08: "o candidato que abre a agenda e não encontra
-- horário é indistinguível de quem nunca clicou. Enquanto isso não mudar, qualquer métrica de
-- sucesso de agendamento diz 100% por construção."
--
-- Medido em 13/08/2026, ANTES desta migration, na janela de agosto (a única em que o token de
-- agendamento existe — os 17 tokens de escopo `interview_booking` foram TODOS emitidos em agosto):
--
--   12 candidaturas com despacho · 12 com token (100%) · 6 abriram a página · 5 com entrevista
--   → 2 ABRIRAM E NÃO RESERVARAM  ·  5 nunca abriram e não reservaram
--
-- O caso literal: uma candidatura voltou 7 vezes à página em 6 dias e não reservou. O registro
-- dela hoje é `interview_pending` / `interview_status = none` — byte por byte o mesmo das 5 que
-- nunca clicaram. As duas populações pedem ações OPOSTAS (agenda sem horário vs. e-mail que não
-- chegou), e a plataforma não sabe distingui-las.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- Decisão do PM (13/08): o DESPACHO vira a linha viva
-- ─────────────────────────────────────────────────────────────────────────────
--
-- `selection_dispatch_url_log` já grava uma linha por oferta de agenda (94 linhas, 55
-- candidaturas). Ela deixa de ser só log e passa a carregar o desfecho. As alternativas foram
-- recusadas com motivo:
--   - usar `onboarding_tokens.access_count` como denominador: só enxerga despacho COM token, e
--     não separa "não abriu" de "não recebeu";
--   - tabela nova de funil: duplicaria o que o log de despacho já é, criando uma segunda fonte
--     de verdade sobre o mesmo fato (a classe que fez a taxa de presença dizer 100% por meses).
--
-- ⚠️ `selection_booking_attempts` NÃO entra aqui. O nome engana: ela é escrita pelo webhook do
-- Google Calendar, uma linha por evento+convidado, e portanto só existe quando a reserva
-- ACONTECEU. Ela conta reservas que a plataforma não casou com candidatura — o oposto disto.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- Duas escolhas de forma, ambas contra armadilhas já pagas neste repositório
-- ─────────────────────────────────────────────────────────────────────────────
--
-- 1. TODA coluna nova é FATO OBSERVADO, nunca estado derivado. Não existe coluna `outcome`, e
--    portanto não existe cron para mantê-la nem deriva possível entre o que a coluna diz e o que
--    as linhas dizem. O desfecho é calculado na LEITURA, e a janela é a do próprio token (14
--    dias — medido idêntico nos 17), não um N inventado nesta migration.
--
-- 2. `instrumented boolean` separa "não abriu" de "não foi medido". As 94 linhas anteriores
--    nascem `false`: para elas a ausência de `booked_at` é ausência de INSTRUMENTAÇÃO, não
--    ausência de reserva, e a leitura devolve `pre_instrumentation` em vez de inventar uma falta.
--    Sem essa coluna, o primeiro relatório publicaria 94 agendamentos fracassados que nunca
--    fracassaram — a mesma classe do `ELSE 'absent'` que já rendeu issue neste repositório.
--
-- ⚠️ Guardamos o MD5 do token, nunca o token. `selection_dispatch_url_log` tem duas policies
-- PERMISSIVAS e a de escopo de organização vence a de negação, de modo que qualquer autenticado
-- da org LÊ a tabela inteira. O token é a credencial de acesso à página de agendamento do
-- candidato: gravá-lo em claro aqui entregaria a porta a todo mundo que já lê o log.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. As colunas de fato
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.selection_dispatch_url_log
  ADD COLUMN IF NOT EXISTS booking_token_md5   text,
  ADD COLUMN IF NOT EXISTS first_opened_at     timestamptz,
  ADD COLUMN IF NOT EXISTS last_opened_at      timestamptz,
  ADD COLUMN IF NOT EXISTS open_count          integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS booked_at           timestamptz,
  ADD COLUMN IF NOT EXISTS booked_interview_id uuid REFERENCES public.selection_interviews(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS superseded_at       timestamptz,
  -- As linhas que já existiam não foram medidas. Dizer o contrário produziria falta inventada.
  -- Os DOIS defaults são deliberados: `false` no ADD retro-preenche as 94 linhas antigas, e o
  -- `SET DEFAULT true` logo abaixo vale só para as próximas. Um `UPDATE ... SET false` no lugar
  -- disto seria correto hoje e marcaria linhas JÁ instrumentadas como não-medidas se a migration
  -- fosse reaplicada, porque o `ADD COLUMN IF NOT EXISTS` acima é idempotente e o UPDATE não.
  ADD COLUMN IF NOT EXISTS instrumented        boolean NOT NULL DEFAULT false;

ALTER TABLE public.selection_dispatch_url_log ALTER COLUMN instrumented SET DEFAULT true;

COMMENT ON COLUMN public.selection_dispatch_url_log.instrumented IS
  '#1590 onda D: false nas linhas anteriores à instrumentação. Para elas a ausência de booked_at é ausência de MEDIÇÃO, não ausência de reserva — a leitura devolve pre_instrumentation.';
COMMENT ON COLUMN public.selection_dispatch_url_log.booking_token_md5 IS
  '#1590 onda D: md5 do token despachado, para carimbar a abertura na linha EXATA. Hash e não o token porque a tabela é legível por qualquer autenticado da org (policy permissiva de escopo).';
COMMENT ON COLUMN public.selection_dispatch_url_log.superseded_at IS
  '#1590 onda D: um despacho posterior substituiu este. Sem isso, um reenvio faria a oferta anterior contar como agendamento fracassado.';

CREATE INDEX IF NOT EXISTS idx_dispatch_url_log_token_md5
  ON public.selection_dispatch_url_log (booking_token_md5) WHERE booking_token_md5 IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_dispatch_url_log_abertos
  ON public.selection_dispatch_url_log (application_id, dispatched_at DESC)
  WHERE booked_at IS NULL AND superseded_at IS NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Carimbo 1 — o despacho: guarda o token e aposenta a oferta anterior
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Corpo baseado no VIVO (pg_get_functiondef em 13/08), não numa migration anterior: esta função
-- foi tocada pelas ondas B e C e reconstruí-la de um arquivo antigo apagaria aquele trabalho.
-- O que muda em relação ao corpo vivo são exatamente dois blocos, ambos marcados `onda D`.

CREATE OR REPLACE FUNCTION public._dispatch_interview_booking_link(p_application_id uuid, p_caller_id uuid DEFAULT NULL::uuid, p_source text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_app record;
  v_url text;
  v_path text;
  v_evaluator uuid;
  v_token_result jsonb;
  v_hoje date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  v_capazes int;
  v_bloqueados int;
  v_token text;
BEGIN
  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  SELECT r.url, r.resolution_path, r.evaluator_id
  INTO v_url, v_path, v_evaluator
  FROM public.resolve_interview_booking_url(p_application_id) r;

  IF v_url IS NULL OR length(trim(v_url)) = 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'failure_code', 'NO_BOOKING_URL',
      'application_id', p_application_id,
      'dispatch_source', p_source,
      'message', 'no resolvable booking URL for this application'
    );
  END IF;

  v_token_result := public._issue_interview_booking_token_core(
    p_application_id, false, p_caller_id, false
  );

  IF COALESCE((v_token_result->>'success')::boolean, false) IS NOT TRUE THEN
    -- Recusa de gate: devolver como está, SEM levantar. A linha de auditoria já foi gravada pelo
    -- core e só sobrevive se ninguém abortar a transação daqui para cima.
    RETURN v_token_result || jsonb_build_object(
      'failure_code', 'GATE_REFUSED',
      'dispatch_source', p_source
    );
  END IF;

  v_token := v_token_result->>'token';

  -- #1590 onda D — aposentar a oferta anterior ANTES de inserir a nova.
  -- Um reenvio (remarcação, cutucão, resgate) não é o mesmo candidato falhando duas vezes: é a
  -- mesma pergunta feita de novo. Sem este bloco, cada reenvio deixaria para trás uma linha
  -- eternamente "ofertada e nunca reservada", e o funil contaria a mesma pessoa N vezes no
  -- numerador do fracasso. A ordem importa — superseder DEPOIS do INSERT apagaria a linha nova.
  UPDATE public.selection_dispatch_url_log
  SET superseded_at = now()
  WHERE application_id = p_application_id
    AND instrumented
    AND booked_at IS NULL
    AND superseded_at IS NULL;

  -- Linha de despacho: é ela que `validate_interview_booking_token` lê para montar a página, e é
  -- ela que alimenta o lookback do LRD. Sem esta linha o reagendamento continuaria fora do rodízio
  -- e fora do log, que é metade do achado da #1595.
  INSERT INTO public.selection_dispatch_url_log (
    application_id, cycle_id, track,
    resolved_url, resolution_path, resolved_evaluator_id, organization_id,
    booking_token_md5
  ) VALUES (
    p_application_id, v_app.cycle_id, v_app.role_applied,
    v_url, v_path, v_evaluator, v_app.organization_id,
    -- #1590 onda D: hash, nunca o token. Ver cabeçalho.
    CASE WHEN v_token IS NOT NULL THEN md5(v_token) ELSE NULL END
  );

  -- #1590 onda B: o desvio para a agenda institucional é EVENTO, não estado normal, na trilha
  -- researcher. Roda depois do log de despacho para registrar só o que de fato foi enviado.
  IF v_app.role_applied = 'researcher' AND v_path = 'cycle_fallback' THEN
    WITH capaz AS (
      SELECT sc.member_id
      FROM public.selection_committee sc
      JOIN public.members m ON m.id = sc.member_id
      WHERE sc.cycle_id = v_app.cycle_id
        AND sc.role IN ('evaluator', 'lead')
        AND sc.can_interview = true
        AND COALESCE(sc.interview_booking_url, m.interview_booking_url) IS NOT NULL
    )
    SELECT
      count(*),
      count(*) FILTER (WHERE EXISTS (
        SELECT 1
        FROM public.selection_interviewer_blackouts b
        WHERE b.cycle_id = v_app.cycle_id
          AND b.member_id = capaz.member_id
          AND v_hoje >= b.starts_on
          AND (b.ends_on IS NULL OR v_hoje <= b.ends_on)
      ))
    INTO v_capazes, v_bloqueados
    FROM capaz;

    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
    VALUES (
      p_caller_id,
      'selection.routing_fell_back_to_cycle',
      'selection_application',
      p_application_id,
      jsonb_build_object(
        'cycle_id', v_app.cycle_id,
        'dispatch_source', p_source,
        'committee_routable', v_capazes,
        'blocked_by_window', v_bloqueados,
        'local_date', v_hoje
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'application_id', p_application_id,
    'booking_url', v_token_result->>'booking_url',
    'token', v_token_result->>'token',
    'expires_at', v_token_result->>'expires_at',
    'resolved_url', v_url,
    'resolution_path', v_path,
    'resolved_evaluator_id', v_evaluator,
    'gate_mode', v_token_result->>'gate_mode',
    'prior_evidence', v_token_result->>'prior_evidence',
    'dispatch_source', p_source
  );
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Carimbo 2 — a abertura: o candidato chegou na porta
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Corpo VIVO acrescido de um bloco. A função já lia a linha de despacho para montar a URL — o
-- que faltava era ESCREVER de volta que a página foi aberta.
--
-- O carimbo vai na linha EXATA de onde o token saiu (por hash), com recuo para a mais recente
-- instrumentada. Sem o hash, um candidato que abre um link antigo carimbaria a oferta nova, e o
-- funil diria "abriu" para uma oferta que ele nunca viu.
--
-- ⚠️ A resolução da URL continua sendo a MAIS RECENTE, deliberadamente: é ela que carrega o
-- roteamento vigente. Ler o destino de uma linha e carimbar a abertura em outra é assimetria
-- intencional, não descuido — o destino é decisão de HOJE, a abertura é fato daquela oferta.

CREATE OR REPLACE FUNCTION public.validate_interview_booking_token(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_token_row record;
  v_app record;
  v_booking_url text;
  v_resolution_path text;
  v_stamped_id uuid;
BEGIN
  IF p_token IS NULL OR length(p_token) < 16 THEN
    RAISE EXCEPTION 'Invalid token format';
  END IF;

  SELECT * INTO v_token_row FROM public.onboarding_tokens WHERE token = p_token;
  IF v_token_row IS NULL THEN
    RAISE EXCEPTION 'Invalid or expired token';
  END IF;

  IF v_token_row.expires_at < now() THEN
    RAISE EXCEPTION 'Invalid or expired token';
  END IF;

  IF NOT (v_token_row.scopes @> ARRAY['interview_booking']::text[]) THEN
    RAISE EXCEPTION 'Token does not have interview_booking scope';
  END IF;

  -- Increment access tracking
  UPDATE public.onboarding_tokens
  SET access_count = COALESCE(access_count, 0) + 1,
      last_accessed_at = now()
  WHERE token = p_token;

  -- Lookup application (read-only fields safe for anon)
  SELECT id, applicant_name, first_name, email, status
  INTO v_app FROM public.selection_applications
  WHERE id = v_token_row.source_id;

  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  -- #1590 onda D — o carimbo de ABERTURA na linha de despacho.
  -- Preferência pela linha de onde ESTE token saiu; recuo para a mais recente instrumentada.
  -- Se não houver linha instrumentada nenhuma, não carimba: um token anterior à instrumentação
  -- não deve inventar medição numa linha que não foi medida.
  SELECT l.id INTO v_stamped_id
  FROM public.selection_dispatch_url_log l
  WHERE l.application_id = v_app.id
    AND l.instrumented
    AND l.booking_token_md5 = md5(p_token)
  ORDER BY l.dispatched_at DESC
  LIMIT 1;

  IF v_stamped_id IS NULL THEN
    SELECT l.id INTO v_stamped_id
    FROM public.selection_dispatch_url_log l
    WHERE l.application_id = v_app.id AND l.instrumented
    ORDER BY l.dispatched_at DESC
    LIMIT 1;
  END IF;

  IF v_stamped_id IS NOT NULL THEN
    UPDATE public.selection_dispatch_url_log
    SET open_count      = COALESCE(open_count, 0) + 1,
        first_opened_at = COALESCE(first_opened_at, now()),
        last_opened_at  = now()
    WHERE id = v_stamped_id;
  END IF;

  -- Destino do agendamento: o que foi efetivamente despachado para ESTA candidatura.
  SELECT l.resolved_url, l.resolution_path
  INTO v_booking_url, v_resolution_path
  FROM public.selection_dispatch_url_log l
  WHERE l.application_id = v_app.id
  ORDER BY l.dispatched_at DESC
  LIMIT 1;

  -- Fallback: token emitido fora do fluxo de despacho (sem linha de log).
  IF v_booking_url IS NULL THEN
    SELECT r.url, r.resolution_path
    INTO v_booking_url, v_resolution_path
    FROM public.resolve_interview_booking_url(v_app.id) r;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'application_id', v_app.id,
    'applicant_name', v_app.applicant_name,
    'first_name', COALESCE(NULLIF(trim(v_app.first_name), ''), split_part(v_app.applicant_name, ' ', 1)),
    'application_status', v_app.status,
    'expires_at', v_token_row.expires_at,
    'access_count', COALESCE(v_token_row.access_count, 0) + 1,
    'booking_url', v_booking_url,
    'resolution_path', v_resolution_path
  );
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Carimbo 3 — a reserva: fecha a oferta que estava aberta
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Dispara em TODO insert de entrevista, não só em `scheduled`/`rescheduled`: uma entrevista
-- lançada direto como `completed` (o caminho manual do operador) fechou a oferta do mesmo jeito,
-- e exigir status agendado deixaria esse caso contando como fracasso para sempre.

CREATE OR REPLACE FUNCTION public.trg_close_dispatch_on_interview()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_target uuid;
BEGIN
  SELECT l.id INTO v_target
  FROM public.selection_dispatch_url_log l
  WHERE l.application_id = NEW.application_id
    AND l.instrumented
    AND l.booked_at IS NULL
    AND l.superseded_at IS NULL
  ORDER BY l.dispatched_at DESC
  LIMIT 1;

  -- Nenhuma oferta aberta: entrevista criada sem despacho instrumentado (agendamento manual, ou
  -- despacho anterior à instrumentação). Não inventar vínculo — o silêncio aqui é a resposta certa.
  IF v_target IS NULL THEN
    RETURN NEW;
  END IF;

  UPDATE public.selection_dispatch_url_log
  SET booked_at = now(), booked_interview_id = NEW.id
  WHERE id = v_target;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_zz_close_dispatch_on_interview ON public.selection_interviews;
CREATE TRIGGER trg_zz_close_dispatch_on_interview
  AFTER INSERT ON public.selection_interviews
  FOR EACH ROW EXECUTE FUNCTION public.trg_close_dispatch_on_interview();

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. A leitura: desfecho DERIVADO, nunca coluna de estado
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Sete desfechos, cada um com uma ação operacional diferente. O que hoje é um único balde mudo
-- (`interview_pending` / `interview_status = none`) se abre em:
--
--   booked                 a oferta virou entrevista
--   superseded             um reenvio posterior substituiu esta oferta
--   opened_never_booked    ABRIU A AGENDA E NÃO RESERVOU, e a janela do token venceu  ← a onda
--   opened_waiting         abriu, ainda não reservou, dentro dos 14 dias
--   never_opened_expired   a janela venceu sem uma única abertura (e-mail não chegou / não foi lido)
--   never_opened_waiting   ainda dentro da janela, sem abertura
--   pre_instrumentation    linha anterior à onda D — não afirma nada sobre reserva
--
-- A janela é a do PRÓPRIO token (14 dias, medido idêntico nos 17 de agosto), lida de
-- `onboarding_tokens` quando o token existe e caindo para 14 dias quando não existe. Um N
-- inventado aqui divergiria da validade real do link no dia em que alguém mudasse o TTL.
--
-- Autoridade: o MESMO público declarado na tela pela onda C (comitê ∪ sponsor ∪ GP ∪ superadmin).
-- Espelhar o predicado de `get_selection_dashboard` abriria 6 `chapter_liaison` numa rota de PII
-- de candidato por uma porta que o menu nunca ofereceu — medido na onda A.

CREATE OR REPLACE FUNCTION public.get_interview_booking_funnel(p_cycle_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_cycle record;
  v_can_manage boolean;
  v_is_committee boolean;
  v_rows json;
BEGIN
  SELECT m.id, m.designations, m.is_superadmin INTO v_caller
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated');
  END IF;

  SELECT c.id, c.cycle_code, c.status INTO v_cycle
  FROM public.selection_cycles c WHERE c.id = p_cycle_id;
  IF v_cycle.id IS NULL THEN
    RETURN json_build_object('error', 'Cycle not found');
  END IF;

  v_is_committee := EXISTS (
    SELECT 1 FROM public.selection_committee sc
    WHERE sc.cycle_id = p_cycle_id AND sc.member_id = v_caller.id
  );
  v_can_manage := public.can_by_member(v_caller.id, 'manage_member');

  IF NOT (
    v_is_committee
    OR v_can_manage
    OR COALESCE(v_caller.is_superadmin, false)
    OR ('sponsor' = ANY(COALESCE(v_caller.designations, '{}'::text[])))
  ) THEN
    RETURN json_build_object('error', 'Unauthorized');
  END IF;

  SELECT COALESCE(json_agg(t.obj ORDER BY t.dispatched_at DESC), '[]'::json) INTO v_rows
  FROM (
    SELECT
      l.dispatched_at,
      json_build_object(
        'dispatch_id', l.id,
        'application_id', l.application_id,
        'applicant_name', a.applicant_name,
        'track', l.track,
        'resolution_path', l.resolution_path,
        'resolved_evaluator_id', l.resolved_evaluator_id,
        'dispatched_at', l.dispatched_at,
        'first_opened_at', l.first_opened_at,
        'last_opened_at', l.last_opened_at,
        'open_count', COALESCE(l.open_count, 0),
        'booked_at', l.booked_at,
        'superseded_at', l.superseded_at,
        'window_ends_at', w.window_ends_at,
        'outcome', CASE
          WHEN NOT l.instrumented              THEN 'pre_instrumentation'
          WHEN l.booked_at IS NOT NULL         THEN 'booked'
          WHEN l.superseded_at IS NOT NULL     THEN 'superseded'
          WHEN COALESCE(l.open_count, 0) > 0
               AND now() > w.window_ends_at    THEN 'opened_never_booked'
          WHEN COALESCE(l.open_count, 0) > 0   THEN 'opened_waiting'
          WHEN now() > w.window_ends_at        THEN 'never_opened_expired'
          ELSE                                      'never_opened_waiting'
        END
      ) AS obj
    FROM public.selection_dispatch_url_log l
    JOIN public.selection_applications a ON a.id = l.application_id
    CROSS JOIN LATERAL (
      -- A janela é a validade do PRÓPRIO token desta oferta. Sem o hash não há como saber qual
      -- token era, e recair sobre "o token mais recente da candidatura" daria a esta oferta a
      -- validade de outra — por isso o recuo é o prazo nominal, não o token do vizinho.
      SELECT COALESCE(
        CASE WHEN l.booking_token_md5 IS NOT NULL THEN (
          SELECT max(ot.expires_at) FROM public.onboarding_tokens ot
           WHERE ot.source_id = l.application_id
             AND ot.scopes @> ARRAY['interview_booking']::text[]
             AND md5(ot.token) = l.booking_token_md5
        ) END,
        l.dispatched_at + interval '14 days'
      ) AS window_ends_at
    ) w
    WHERE l.cycle_id = p_cycle_id
  ) t;

  RETURN json_build_object(
    'success', true,
    'cycle_id', p_cycle_id,
    'cycle_code', v_cycle.cycle_code,
    'dispatches', v_rows,
    -- Os totais saem do JSON JÁ MONTADO, não de um segundo predicado: duas implementações da
    -- mesma pergunta divergem, e foi assim que a taxa de presença passou meses dizendo 100%.
    'totals', COALESCE((
      SELECT json_object_agg(o, n) FROM (
        SELECT e->>'outcome' AS o, count(*) AS n
        FROM json_array_elements(v_rows) e GROUP BY 1
      ) z
    ), '{}'::json),
    'measured_at', now()
  );
END;
$function$;

-- `CREATE FUNCTION` concede EXECUTE a PUBLIC por padrão: toda RPC nova nasce alcançável por anon
-- (#1710, #1592). `validate_interview_booking_token` e `_dispatch_interview_booking_link` são
-- CREATE OR REPLACE e preservam os grants que já tinham — só a função nova é revogada aqui.
REVOKE EXECUTE ON FUNCTION public.get_interview_booking_funnel(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.trg_close_dispatch_on_interview() FROM PUBLIC, anon;

COMMENT ON FUNCTION public.get_interview_booking_funnel(uuid) IS
  '#1590 onda D: funil de agendamento por ciclo, com desfecho DERIVADO na leitura (nunca coluna de estado). Separa "abriu a agenda e não reservou" de "nunca abriu" — dois grupos que hoje têm registro idêntico e pedem ações opostas. Autoridade: comitê do ciclo, sponsor, manage_member ou superadmin.';
