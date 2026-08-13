-- ============================================================================
-- #1590 onda B — elegibilidade de roteamento vira dimensão PRÓPRIA, com janela
-- ============================================================================
--
-- O pedido do PM, nas palavras dele: se o entrevistador bloqueia a agenda nas próximas semanas
-- mas continua sendo a pessoa roteada, o candidato recebe a agenda dele, VAZIA, e fica sem
-- conseguir agendar. A recusa acontece na frente do candidato.
--
-- São duas dimensões independentes:
--
--   dimensão                       responde                              quem sente
--   disponibilidade de calendário  "que horários esta pessoa tem?"       quem já foi roteado
--   elegibilidade de roteamento    "esta pessoa pode ser escolhida?"     o candidato, ANTES
--
-- Hoje elas estão conflatadas numa coluna só: a única forma de sair do rodízio é APAGAR
-- `interview_booking_url`, o que destrói a configuração, não tem data e não se reverte sozinho.
--
-- Medido em 12/08/2026, ciclo cycle4-2026 aberto:
--   - 3 avaliadores roteáveis (todos por `committee_override`), 4 observadores fora do rodízio
--   - 94 despachos no total: researcher 57 `member_global` + 30 `committee_override`,
--     leader 7 `cycle_fallback`
--   - nenhum registro do candidato que abriu a agenda e não encontrou horário
--
-- O que esta migration NÃO faz: não há tela nem RPC de escrita ainda (onda C). A tabela é
-- populada por SQL do GP até lá. Ficou explícito para não parecer entrega pela metade.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. A dimensão temporal
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Tabela de PERÍODOS, não flag booleana: permite janela futura ("vou estar fora de 20 a 30/08"),
-- guarda histórico de quem bloqueou e por quê, e não perde a configuração de calendário.
-- `ends_on` nulo = bloqueio aberto, encerrado por escrita explícita.

CREATE TABLE IF NOT EXISTS public.selection_interviewer_blackouts (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id        uuid NOT NULL REFERENCES public.selection_cycles(id) ON DELETE CASCADE,
  member_id       uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  starts_on       date NOT NULL,
  ends_on         date,
  reason          text,
  created_by      uuid REFERENCES public.members(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  organization_id uuid,
  CONSTRAINT selection_interviewer_blackouts_window_ck
    CHECK (ends_on IS NULL OR ends_on >= starts_on)
);

COMMENT ON TABLE public.selection_interviewer_blackouts IS
  'Elegibilidade de ROTEAMENTO por período (#1590 onda B). Não é disponibilidade de calendário: '
  'quem está aqui não entra no rodízio de `resolve_interview_booking_url`, e o candidato nunca vê '
  'aquela porta. A URL de agendamento continua significando só CAPACIDADE (tem calendário), e '
  '`selection_committee.can_interview` continua significando o desligamento PERMANENTE. Três eixos '
  'separados de propósito: apagar a URL para tirar alguém do rodízio destrói configuração.';

COMMENT ON COLUMN public.selection_interviewer_blackouts.ends_on IS
  'Nulo = bloqueio aberto (sem data de volta). Encerrar exige escrita explícita.';

-- O índice serve o NOT EXISTS do picker, que filtra por (cycle_id, member_id) e compara a janela.
CREATE INDEX IF NOT EXISTS selection_interviewer_blackouts_lookup_idx
  ON public.selection_interviewer_blackouts (cycle_id, member_id, starts_on, ends_on);

ALTER TABLE public.selection_interviewer_blackouts ENABLE ROW LEVEL SECURITY;

-- Mesmo par de policies de `selection_committee`, que é o irmão direto (registro de comitê):
-- ninguém alcança a tabela direto; a fronteira são as SECURITY DEFINER.
DROP POLICY IF EXISTS rpc_only_deny_all ON public.selection_interviewer_blackouts;
CREATE POLICY rpc_only_deny_all ON public.selection_interviewer_blackouts
  FOR ALL USING (false);

DROP POLICY IF EXISTS selection_interviewer_blackouts_v4_org_scope ON public.selection_interviewer_blackouts;
CREATE POLICY selection_interviewer_blackouts_v4_org_scope ON public.selection_interviewer_blackouts
  AS RESTRICTIVE FOR ALL
  USING (organization_id = public.auth_org() OR organization_id IS NULL);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. O picker passa a ler os TRÊS eixos separados
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Base: corpo VIVO de 12/08/2026 (`pg_get_functiondef`), não a migration de origem — as duas já
-- divergiram antes neste repositório e reescrever por cima do arquivo antigo apaga trabalho.
--
-- Delta único: o `NOT EXISTS` do bloqueio. Ordenação, precedência e fallback ficam intactos.
--
-- ⚠️ A BORDA DE DATA É O RISCO CONHECIDO. `CURRENT_DATE` é UTC: das 21h à meia-noite em Brasília
-- o servidor já virou o dia, e um bloqueio que termina "hoje" deixaria de valer três horas antes
-- do fim do dia local (a mesma classe do #1727). Por isso a comparação é sobre
-- `(now() AT TIME ZONE 'America/Sao_Paulo')::date`.

CREATE OR REPLACE FUNCTION public.resolve_interview_booking_url(p_application_id uuid)
 RETURNS TABLE(url text, resolution_path text, evaluator_id uuid)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_app record;
  v_cycle record;
  v_url text;
  v_path text;
  v_evaluator uuid;
  v_hoje date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  IF v_app.role_applied = 'researcher' THEN
    -- LRD: avaliador com o despacho mais antigo primeiro (NULLS FIRST = nunca usado fura a fila).
    -- Desempate por member_id para ordem estável.
    SELECT
      sc.member_id,
      COALESCE(sc.interview_booking_url, m.interview_booking_url),
      CASE
        WHEN sc.interview_booking_url IS NOT NULL THEN 'committee_override'
        ELSE 'member_global'
      END
    INTO v_evaluator, v_url, v_path
    FROM public.selection_committee sc
    JOIN public.members m ON m.id = sc.member_id
    LEFT JOIN LATERAL (
      SELECT MAX(l.dispatched_at) AS last_dispatched
      FROM public.selection_dispatch_url_log l
      WHERE l.cycle_id = v_cycle.id
        AND l.track = 'researcher'
        AND l.resolved_evaluator_id = sc.member_id
    ) lrd ON true
    WHERE sc.cycle_id = v_cycle.id
      AND sc.role IN ('evaluator', 'lead')
      AND sc.can_interview = true
      AND COALESCE(sc.interview_booking_url, m.interview_booking_url) IS NOT NULL
      -- #1590 onda B: elegibilidade de roteamento, dimensão separada da capacidade acima.
      AND NOT EXISTS (
        SELECT 1
        FROM public.selection_interviewer_blackouts b
        WHERE b.cycle_id = v_cycle.id
          AND b.member_id = sc.member_id
          AND v_hoje >= b.starts_on
          AND (b.ends_on IS NULL OR v_hoje <= b.ends_on)
      )
    ORDER BY lrd.last_dispatched NULLS FIRST, sc.member_id
    LIMIT 1;
  END IF;

  -- Fallback único: leader, role desconhecido, ou researcher sem avaliador resolvível.
  IF v_url IS NULL OR length(trim(v_url)) = 0 THEN
    v_url := v_cycle.interview_booking_url;
    v_path := 'cycle_fallback';
    v_evaluator := NULL;
  END IF;

  -- Sem URL em lugar nenhum devolve NULL, não exceção: quem despacha decide se isso é erro
  -- (notify levanta P0020) ou estado de erro de tela (a página do token).
  IF v_url IS NULL OR length(trim(v_url)) = 0 THEN
    v_url := NULL;
    v_path := NULL;
    v_evaluator := NULL;
  END IF;

  RETURN QUERY SELECT v_url, v_path, v_evaluator;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. A queda para a agenda do Núcleo deixa de ser SILENCIOSA
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Decisão do PM (12/08): quando ninguém está elegível, o candidato CAI na agenda do Núcleo. O
-- comportamento fica; o silêncio não. Hoje `cycle_fallback` é indistinguível na trilha researcher
-- entre "o rodízio funcionou" e "o rodízio ficou vazio".
--
-- O registro sai AQUI, no chamador, e não no picker: o picker é STABLE e não pode escrever. Os 5
-- caminhos de despacho (notify_selection_cutoff_approved, request_interview_reschedule,
-- request_interview_booking_link_via_token, mark_interview_status, process_pending_reschedule_nudges)
-- passam todos por esta função, então um gancho cobre todos.
--
-- A metadata separa as duas causas, que pedem ações opostas:
--   committee_routable = 0            → ninguém configurado (falta cadastrar URL)
--   blocked_by_window = routable > 0  → todo mundo bloqueado no período (falta gente, ou janela larga demais)
--
-- Só a trilha RESEARCHER é auditada: em `leader` o `cycle_fallback` é o caminho normal e projetado
-- (entrevista em grupo), então registrá-lo produziria ruído diário que se aprende a ignorar.

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

  -- Linha de despacho: é ela que `validate_interview_booking_token` lê para montar a página, e é
  -- ela que alimenta o lookback do LRD. Sem esta linha o reagendamento continuaria fora do rodízio
  -- e fora do log, que é metade do achado da #1595.
  INSERT INTO public.selection_dispatch_url_log (
    application_id, cycle_id, track,
    resolved_url, resolution_path, resolved_evaluator_id, organization_id
  ) VALUES (
    p_application_id, v_app.cycle_id, v_app.role_applied,
    v_url, v_path, v_evaluator, v_app.organization_id
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

COMMENT ON FUNCTION public.resolve_interview_booking_url(uuid) IS
  'Rodízio LRD do roteamento de entrevista. Lê TRÊS eixos separados (#1590 onda B): papel no comitê '
  'mais `can_interview` (desligamento permanente), URL de agendamento (capacidade) e '
  '`selection_interviewer_blackouts` (elegibilidade por período). A janela compara contra a data '
  'LOCAL de São Paulo, não `CURRENT_DATE` — em UTC a noite de Brasília já virou o dia (#1727).';
