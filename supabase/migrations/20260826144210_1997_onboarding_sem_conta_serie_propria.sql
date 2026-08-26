-- #1997 -- quem nao tem conta na plataforma para de ser cobrado por uma jornada que
-- nao tem como abrir, e o admin passa a enxergar essa diferenca.
--
-- CASO QUE EXPOE. Farhad Abdollahyan, aprovado como LIDER em 14/08 (cycle4-2026), engajamento
-- volunteer/leader ativo, 16 passos de onboarding atribuidos, 0 concluidos, members.auth_id NULL.
-- Tres passos dele ja estao 'overdue' -- e um deles se chama literalmente `platform_access`,
-- com SLA vencido em 21/08. O detector marcou atraso no passo "conseguir acesso a plataforma"
-- e cobrou a pessoa por isso via notificacao in-app, que exige exatamente o acesso que falta.
--
-- NAO E CASO ISOLADO, E TEM RELOGIO. Medido 26/08: 4 pessoas sem auth_id carregam jornada ativa
-- (Farhad 16 passos, Thiago Sousa 12, Rafael dos Santos 12, Hector Rigon 7; 0 concluidos nas
-- quatro). Dessas, 3 tem 12 passos com SLA armado:
--     28/08 21:15 UTC  2 passos  Farhad            (kick_off, profile_complete)
--     29/08 01:35 UTC  2 passos  Rafael + Thiago   (join_whatsapp)
--     02/09 01:35 UTC  4 passos  Rafael + Thiago   (accept_terms, platform_access)
--     09/09 01:35 UTC  4 passos  Rafael + Thiago   (kick_off, profile_complete)
-- O cron `detect-onboarding-overdue-daily` (jobid 39, `0 13 * * *`) roda todo dia as 13:00 UTC,
-- entao a primeira leva reproduz o defeito em 29/08 as 10:00 BRT. Estoque atual de 'overdue':
-- 107 passos, 3 deles de quem nao tem conta (as 3 do Farhad).
--
-- O QUE E, E O QUE NAO E. A notificacao `selection_onboarding_overdue` cai no ELSE de
-- `_delivery_mode_for` e sai como 'digest_weekly'. Ela NAO some por falta de conta: o digest
-- semanal (`generate_weekly_member_digest_cron`) nao filtra por auth_id, e gente sem conta
-- recebe o e-mail do digest -- medido, 15 envios a 8 pessoas sem auth_id. O que a falta de
-- conta impede e o DESTINO: o link e `/workspace`, que 302 vem de `/onboarding` (o endereco
-- que TODOS os e-mails de aprovacao mandam abrir) e exige sessao. As 3 do Farhad, alias,
-- seguem com digest_delivered_at NULL desde 18/08 -- mas isso vale para 3 pessoas COM conta
-- na mesma leva, porque o gate `v_has_content` do digest nao olha notificacoes pendentes.
-- Esse segundo defeito e de outra caixa e fica fora daqui, registrado no handoff.
--
-- Por isso a correcao NAO suprime a notificacao. Suprimir criaria ausencia indistinguivel de
-- "ninguem estava atrasado" -- a armadilha de sempre. Ela troca o TEXTO e o DESTINO por algo
-- acionavel sem sessao, e contabiliza o caso em serie propria.
--
-- TRES MUDANCAS
--
--  1. `detect_onboarding_overdue` passa a olhar `members.auth_id`. O passo continua sendo
--     marcado 'overdue' (a verdade do SLA nao muda), mas quem nao tem conta recebe uma
--     notificacao que aponta para `/guia-pre-onboarding` -- pagina PUBLICA, feita para anon,
--     cujo passo 2 e exatamente "entre na plataforma com o MESMO e-mail do PMI". A RPC passa a
--     devolver `blocked_no_account_steps` e `blocked_no_account_people` como serie propria,
--     ao lado de `notifications_sent`.
--
--  2. `get_application_onboarding_pct` para de filtrar por `metadata->>'phase'='pre_onboarding'`.
--     Medido: das 899 linhas de `onboarding_progress`, ZERO carregam a chave `phase`. O filtro
--     seleciona conjunto vazio, a RPC devolve -1 para as 71 candidaturas com jornada, e a coluna
--     "Onboarding" de /admin/selection mostra "--" para todo mundo, sempre. Quem escreveria essa
--     chave e `seed_pre_onboarding_steps`, que NAO tem chamador em lugar nenhum (nem SQL, nem
--     frontend, nem edge function) -- ligar aquele seeder e decisao de produto e fica de fora;
--     aqui so se conserta o leitor para medir a jornada que a candidatura REALMENTE tem.
--
--  3. `get_onboarding_blocked_cohort()` (nova, SECDEF, manage_platform): a lista que o admin
--     precisa para agir -- quem tem jornada e nao tem conta, com contagem de passos, proximo
--     SLA e se ainda existe token vivo de `profile_completion` (hoje: nenhum dos 4 tem; todos
--     venceram entre 19/05 e 07/08).
--
-- GC-097: nenhuma FK nova, nenhuma coluna nova. members usa `name` e `auth_id`; a juncao
-- op.member_id -> members.id ja existia no laco. `search_path` e GRANTs preservados iguais aos
-- corpos vivos (authenticated + service_role, nunca anon).

-- ---------------------------------------------------------------------------
-- 1. detect_onboarding_overdue
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.detect_onboarding_overdue()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id uuid;
  v_overdue record;
  v_notified int := 0;
  v_updated int := 0;
  v_blocked_steps int := 0;
  v_blocked_people uuid[] := ARRAY[]::uuid[];
BEGIN
  -- Cron-context auth bypass (no JWT). ADR-0028 p89 pattern.
  -- Human callers via MCP/admin must have manage_platform; cron context (auth.uid IS NULL)
  -- bypasses since pg_cron is trusted scheduler.
  IF auth.role() IS NOT NULL AND auth.role() NOT IN ('service_role') AND auth.uid() IS NOT NULL THEN
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: member not found'; END IF;
    IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'Unauthorized: admin only';
    END IF;
  END IF;

  FOR v_overdue IN
    SELECT
      op.id AS progress_id,
      op.application_id,
      op.step_key,
      op.member_id,
      op.sla_deadline,
      sa.applicant_name,
      sa.chapter,
      -- #1997: LEFT JOIN de proposito. member_id e nullable em onboarding_progress, e uma
      -- linha orfa nao pode virar "tem conta" por acidente de juncao.
      (m.auth_id IS NOT NULL) AS has_platform_account
    FROM public.onboarding_progress op
    JOIN public.selection_applications sa ON sa.id = op.application_id
    LEFT JOIN public.members m ON m.id = op.member_id
    WHERE op.status IN ('pending', 'in_progress')
      AND op.sla_deadline < now()
  LOOP
    UPDATE public.onboarding_progress
    SET status = 'overdue'
    WHERE id = v_overdue.progress_id AND status != 'overdue';

    IF FOUND THEN
      v_updated := v_updated + 1;
    END IF;

    IF v_overdue.member_id IS NULL THEN
      CONTINUE;
    END IF;

    IF v_overdue.has_platform_account THEN
      PERFORM public.create_notification(
        v_overdue.member_id,
        'selection_onboarding_overdue',
        'Etapa de Onboarding Atrasada',
        'A etapa "' || v_overdue.step_key || '" está atrasada. Por favor, complete-a o mais breve possível.',
        '/workspace',
        'onboarding_progress',
        v_overdue.progress_id
      );
      v_notified := v_notified + 1;
    ELSE
      -- #1997: sem auth_id o destino padrao (/workspace, para onde /onboarding redireciona)
      -- exige sessao, e a pessoa nao tem nenhuma. Cobrar a etapa nesse endereco pede que ela
      -- atravesse a porta que esta trancada. O texto e o link mudam para o unico passo que ela
      -- PODE dar: /guia-pre-onboarding e publico e explica como criar o acesso.
      --
      -- E UMA notificacao por PESSOA, nao por passo: para quem esta estruturalmente impedido a
      -- mensagem e sempre a mesma, e repeti-la por etapa vencida so empilha ruido identico (o
      -- Farhad ja acumulou 3 assim). O nome cru do passo (`platform_access`, `join_whatsapp`)
      -- tambem sai do texto: nenhum deles e acionavel antes do acesso existir.
      IF NOT (v_overdue.member_id = ANY(v_blocked_people)) THEN
        PERFORM public.create_notification(
          v_overdue.member_id,
          'selection_onboarding_overdue',
          'Crie seu acesso para destravar o onboarding',
          'Sua jornada de onboarding tem etapas vencidas, mas elas só podem ser concluídas '
            || 'dentro da plataforma e ainda não há acesso vinculado ao seu cadastro. Entre '
            || 'usando o MESMO e-mail que você cadastrou no PMI. O guia público explica o '
            || 'passo a passo.',
          '/guia-pre-onboarding',
          'onboarding_progress',
          v_overdue.progress_id
        );
        v_notified := v_notified + 1;
      END IF;
      v_blocked_steps := v_blocked_steps + 1;
      v_blocked_people := v_blocked_people || v_overdue.member_id;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'steps_marked_overdue', v_updated,
    'notifications_sent', v_notified,
    -- #1997: serie propria. "atrasado" e "impedido" nao podem somar no mesmo balde: sem essa
    -- separacao o painel mistura quem NAO FEZ com quem NAO PODE FAZER.
    'blocked_no_account_steps', v_blocked_steps,
    'blocked_no_account_people', (SELECT count(DISTINCT x) FROM unnest(v_blocked_people) AS x),
    'context', CASE WHEN auth.uid() IS NULL THEN 'cron' ELSE 'admin' END
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.detect_onboarding_overdue() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.detect_onboarding_overdue() TO authenticated, service_role;

COMMENT ON FUNCTION public.detect_onboarding_overdue() IS
  '#1997: marca passos vencidos e notifica. Quem nao tem members.auth_id recebe texto e link '
  'publicos (/guia-pre-onboarding) em vez de /workspace, e entra em serie propria '
  '(blocked_no_account_steps / blocked_no_account_people).';

-- ---------------------------------------------------------------------------
-- 2. get_application_onboarding_pct -- o filtro de phase selecionava conjunto vazio
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_application_onboarding_pct(p_application_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id uuid;
  v_result integer;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  -- #1838: manage_platform e administracao da plataforma, e esta RPC devolve UM INTEIRO de
  -- progresso de onboarding de uma candidatura. A exigencia era desproporcional ao que ela
  -- entrega. E LEITURA, entao qualquer papel do comite do ciclo DESTA candidatura passa, com
  -- view_pii. O EXISTS falha fechado se a candidatura nao existir.
  IF v_caller_id IS NULL OR NOT (
       public.can_by_member(v_caller_id, 'manage_platform')
    OR (EXISTS (SELECT 1 FROM public.selection_applications sa
                 WHERE sa.id = p_application_id
                   AND public.is_selection_committee_member(v_caller_id, sa.cycle_id))
        AND public.can_by_member(v_caller_id, 'view_pii'))
  ) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform, or selection committee membership with view_pii';
  END IF;

  -- #1997: antes havia aqui `AND metadata->>'phase' = 'pre_onboarding'`. Nenhuma das 899 linhas
  -- de onboarding_progress carrega a chave `phase` (quem a escreveria, seed_pre_onboarding_steps,
  -- nao tem chamador), entao o filtro devolvia -1 para as 71 candidaturas com jornada e a coluna
  -- "Onboarding" do /admin/selection ficava "--" para todas. A porcentagem passa a medir a
  -- jornada que a candidatura REALMENTE tem. 'skipped' conta como resolvido, igual ao
  -- update_pmi_onboarding_step, senao um passo dispensado derruba a barra para sempre.
  SELECT CASE
    WHEN count(*) = 0 THEN -1
    ELSE round(100.0 * count(*) FILTER (WHERE status IN ('completed', 'skipped')) / count(*))::int
  END INTO v_result
  FROM public.onboarding_progress
  WHERE application_id = p_application_id;

  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_application_onboarding_pct(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_application_onboarding_pct(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. get_onboarding_blocked_cohort -- a lista acionavel
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_onboarding_blocked_cohort()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id uuid;
  v_people jsonb;
BEGIN
  -- Devolve PII (nome + e-mail) de varios ciclos ao mesmo tempo, entao o portao e
  -- manage_platform inteiro -- diferente da #1838, onde o que saia era um inteiro.
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform';
  END IF;

  SELECT COALESCE(jsonb_agg(t ORDER BY t.next_sla NULLS LAST, t.name), '[]'::jsonb)
  INTO v_people
  FROM (
    SELECT
      m.id                AS member_id,
      m.name              AS name,
      m.email             AS email,
      m.is_active         AS is_active,
      m.operational_role  AS operational_role,
      op.application_id   AS application_id,
      sa.status           AS application_status,
      sa.role_applied     AS role_applied,
      sc.cycle_code       AS cycle_code,
      count(*)                                                        AS steps_total,
      count(*) FILTER (WHERE op.status IN ('completed', 'skipped'))    AS steps_done,
      count(*) FILTER (WHERE op.status = 'overdue')                    AS steps_overdue,
      count(*) FILTER (WHERE op.status IN ('pending', 'in_progress'))  AS steps_pending,
      min(op.sla_deadline) FILTER (WHERE op.status IN ('pending', 'in_progress'))
                                                                       AS next_sla,
      -- O outro caminho sem sessao: o portal /pmi-onboarding/<token>. update_pmi_onboarding_step
      -- exige escopo profile_completion e token nao vencido, entao um token vivo significa que a
      -- pessoa AINDA consegue mexer nos passos sem conta.
      EXISTS (
        SELECT 1 FROM public.onboarding_tokens tk
         WHERE tk.source_id = op.application_id
           AND tk.expires_at > now()
           AND 'profile_completion' = ANY(tk.scopes)
      ) AS has_live_profile_token
    FROM public.onboarding_progress op
    JOIN public.members m ON m.id = op.member_id
    LEFT JOIN public.selection_applications sa ON sa.id = op.application_id
    LEFT JOIN public.selection_cycles sc ON sc.id = sa.cycle_id
    WHERE m.auth_id IS NULL
    GROUP BY m.id, m.name, m.email, m.is_active, m.operational_role,
             op.application_id, sa.status, sa.role_applied, sc.cycle_code
    -- Quem ja concluiu tudo o que tinha nao esta bloqueado por nada.
    HAVING count(*) FILTER (WHERE op.status NOT IN ('completed', 'skipped')) > 0
  ) t;

  RETURN jsonb_build_object(
    'measured_at', now(),
    'people', v_people,
    'summary', jsonb_build_object(
      'people', jsonb_array_length(v_people),
      'steps_blocked', COALESCE((SELECT sum((x->>'steps_pending')::int + (x->>'steps_overdue')::int)
                                   FROM jsonb_array_elements(v_people) x), 0),
      'steps_overdue', COALESCE((SELECT sum((x->>'steps_overdue')::int)
                                   FROM jsonb_array_elements(v_people) x), 0)
    )
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_onboarding_blocked_cohort() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_onboarding_blocked_cohort() TO authenticated, service_role;

COMMENT ON FUNCTION public.get_onboarding_blocked_cohort() IS
  '#1997: quem tem jornada de onboarding atribuida e nao tem members.auth_id. Separa "nao fez" '
  'de "nao pode fazer" para o painel. Gate manage_platform (devolve PII de varios ciclos).';
