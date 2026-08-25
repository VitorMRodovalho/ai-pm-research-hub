-- ============================================================================
-- #1925 saida 2 - a escada de prioridade vira SSOT, e ganha reconciliacao agendada
-- ----------------------------------------------------------------------------
-- O DEFEITO (medido e diagnosticado na #1925): `A3_active_role_engagement_derivation`
-- deriva de `public.auth_engagements`, e a view usa `CURRENT_DATE`
-- (`pg_get_viewdef('public.auth_engagements') ~ 'CURRENT_DATE'` = true). A virada de data
-- muda a DERIVACAO sem que ninguem escreva em `auth_engagements`, e o cache
-- `members.operational_role` so e reescrito pelo trigger, que so dispara em ESCRITA.
-- Resultado: A3 fica vermelha sozinha, e como ela estava no portao required, a PR de
-- qualquer pessoa ficava vermelha sem ninguem tocar em dado. (A saida 1 - tirar o teste
-- do relatorio do required - entrou na #1981.)
--
-- MEDIDO EM 25/08/2026, e cada numero muda uma decisao:
--
--   14 funcoes escrevem `members.operational_role`, TODAS por evento. Nenhuma e lote
--   agendavel: e a familia "detector sem agendamento". Dai o worker novo.
--
--   A escada de prioridade ja existe inline em DUAS copias - o trigger
--   `sync_operational_role_cache` e a CTE `computed` da A3 dentro de
--   `check_schema_invariants`. Elas sao BYTE-IDENTICAS hoje (md5 f7d75a5c..., 1197 chars
--   apos colapsar espaco e tirar comentario), com o mesmo filtro `is_authoritative = true`.
--   Um cron com a escada COPIADA seria a TERCEIRA copia, e a primeira divergencia entre
--   elas sairia calada. Por isso a escada vira `_derive_operational_role()` ANTES do cron.
--
--   Populacao: 94 membros ativos, 1 deles excluido pela A3 (o pseudo-membro compartilhado).
--   Entre os ativos, ZERO divergem hoje - este reconciliador e PREVENCAO, nao reparo, e o
--   "antes" honesto e 0 linhas corrigidas.
--
--   ⚠️ Entre os NAO-ativos ha 32 divergencias. Elas NAO entram: papel de quem saiu e
--   congelado por `admin_offboard_member` e afins, e reconciliar ali seria mutacao em massa
--   de 32 linhas que ninguem pediu. O escopo e o mesmo eixo da A3: `member_status='active'`.
--
-- JANELA QUE ISTO FECHA: `CURRENT_DATE` vira 00:00 UTC e o primeiro job que mexe em
-- engajamento e `v4_engagement_expiration`, as 03:05 UTC. Entre os dois ha ~3h em que a
-- derivacao ja mudou e nenhuma escrita corrigiu o cache. O cron roda 00:04 UTC, dentro dessa
-- janela e logo apos a virada. Minuto deslocado de proposito (#1844): 00:00 em ponto
-- concentraria com qualquer job de hora cheia, e o pool e compartilhado com trafego real.
--
-- O QUE ESTA MIGRATION NAO FAZ, de proposito:
--   - NAO faz a A3 chamar `_derive_operational_role`. Se derivacao e verificacao
--     compartilharem a funcao, o invariante deixa de ser independente da implementacao: um
--     erro na escada passaria a ser invisivel para o proprio guard que existe para pega-lo.
--     E troca real, nao limpeza, e merece PR propria com a decisao escrita.
--   - NAO reconcilia nao-ativos (as 32 acima).
--   - NAO cria wrapper publico gateado: ninguem pediu superficie manual, e cada RPC publica
--     nova e um portao a mais para testar.
--
-- ⚠️ DUPLICACAO QUE SOBRA, declarada: o ESCOPO da A3 (`member_status='active'` mais as duas
-- exclusoes de nome) fica copiado aqui. E predicado curto, nao a escada de 1197 chars, e some
-- na PR que converter a A3. Registrar e melhor do que fingir que nao existe.
--
-- ROLLBACK:
--   SELECT cron.unschedule('operational-role-reconcile-daily');
--   DROP FUNCTION public._operational_role_reconcile_cron();
--   DROP FUNCTION public._reconcile_operational_role_cache(boolean);
--   -- e recriar sync_operational_role_cache a partir da captura de 20260822033913,
--   -- ANTES de DROP FUNCTION public._derive_operational_role(uuid).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- (1) A escada, agora com um dono so.
--
-- O corpo do CASE e a CAPTURA VERBATIM da que estava inline em
-- `sync_operational_role_cache` (20260822033913), comentarios inclusive: mudar qualquer
-- degrau aqui seria mudar autoridade de gente, e isto e extracao, nao redesenho.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._derive_operational_role(p_person_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT COALESCE(
    (
      SELECT CASE
          WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'manager')        THEN 'manager'
          WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'co_gp')          THEN 'deputy_manager'
          WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'deputy_manager') THEN 'deputy_manager'
          WHEN bool_or(ae.kind = 'volunteer' AND ae.role IN ('leader','comms_leader')) THEN 'tribe_leader'
          -- Wave 1 fix: sponsor outranks researcher (committee/workgroup) so a sponsor who also sits on a
          -- committee (e.g. the governance committee) shows as a sponsor, not a researcher.
          WHEN bool_or(ae.kind = 'sponsor') THEN 'sponsor'
          -- Wave 2 WS-1 (PM 2026-06-28 'governança vence'): chapter_board (chapter director) outranks
          -- researcher/observer so a chapter director who also sits on a committee or observes a
          -- tribe still shows as 'Ponto Focal do Capítulo' (chapter_liaison). Stays BELOW sponsor
          -- and operational leaders (manager/deputy/tribe_leader) — those who lead operationally keep that role.
          WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
          WHEN bool_or(
            (ae.kind = 'volunteer' AND ae.role IN ('researcher','facilitator','communicator','curator'))
            OR (ae.kind IN ('committee_member','workgroup_member','study_group_owner')
                AND ae.role IN ('leader','co_leader','owner','coordinator','researcher','contributor','member','participant'))
            OR (ae.kind IN ('committee_coordinator','workgroup_coordinator')
                AND ae.role IN ('leader','co_leader','owner','coordinator'))
          ) THEN 'researcher'
          WHEN bool_or(ae.kind = 'external_signer') THEN 'external_signer'
          WHEN bool_or(ae.kind = 'institutional_auditor') THEN 'institutional_auditor'
          WHEN bool_or(ae.kind = 'observer') THEN 'observer'
          WHEN bool_or(ae.kind = 'alumni') THEN 'alumni'
          WHEN bool_or(ae.kind = 'candidate') THEN 'candidate'
          ELSE 'guest'
        END
      FROM public.auth_engagements ae
      WHERE ae.person_id = p_person_id AND ae.is_authoritative = true
    ),
    'guest'
  );
$function$;

COMMENT ON FUNCTION public._derive_operational_role(uuid) IS
  '#1925 - SSOT da escada de prioridade de `members.operational_role`. Era inline em duas '
  'copias byte-identicas (o trigger `sync_operational_role_cache` e a CTE `computed` da A3 em '
  '`check_schema_invariants`); um cron com a escada copiada seria a terceira. Nunca devolve '
  'NULL: pessoa sem engajamento autoritativo resolve para `guest`, igual ao ELSE do CASE.';

-- `CREATE FUNCTION` concede EXECUTE a PUBLIC, e esta funcao le engajamento de pessoa.
-- As chamadoras sao SECURITY DEFINER de `postgres`, e numa chamada SECDEF->SECDEF o EXECUTE
-- e verificado como o DONO, entao revogar de `authenticated` nao as alcanca (#1631/#1551).
REVOKE ALL ON FUNCTION public._derive_operational_role(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._derive_operational_role(uuid) TO service_role;

-- ----------------------------------------------------------------------------
-- (2) O trigger passa a CHAMAR a escada em vez de carregar a sua copia.
-- Captura de 20260822033913 com a UNICA mudanca sendo a troca do CASE pela chamada.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_operational_role_cache()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_new_role text;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE person_id = COALESCE(NEW.person_id, OLD.person_id);
  IF v_member_id IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;

  -- #1925: a escada de prioridade saiu daqui e virou uma funcao propria. Ela existia inline
  -- em DUAS copias (aqui e na CTE `computed` da A3 em check_schema_invariants),
  -- byte-identicas em 25/08 (md5 f7d75a5c...). Um cron de reconciliacao com a escada
  -- copiada seria a TERCEIRA, e a primeira divergencia sairia calada.
  v_new_role := public._derive_operational_role(COALESCE(NEW.person_id, OLD.person_id));

  UPDATE public.members SET operational_role = COALESCE(v_new_role, 'guest'), updated_at = now()
    WHERE id = v_member_id AND operational_role IS DISTINCT FROM COALESCE(v_new_role, 'guest');

  RETURN COALESCE(NEW, OLD);
END;
$function$;

-- ----------------------------------------------------------------------------
-- (3) O worker em lote: o que o trigger nao consegue ser.
--
-- O trigger so dispara em escrita, e a virada de `CURRENT_DATE` nao e escrita. Este worker
-- e a unica coisa no sistema que reconcilia sem que ninguem tenha mexido em nada.
--
-- Escreve so quando ha diferenca (`IS DISTINCT FROM`), e cada membro roda no seu proprio
-- bloco de excecao: um dado ruim numa linha nao pode silenciar as outras (classe do #1829).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._reconcile_operational_role_cache(p_dry_run boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_m record;
  v_esperado text;
  v_mudancas jsonb := '[]'::jsonb;
  v_erros jsonb := '[]'::jsonb;
  v_examinados int := 0;
BEGIN
  FOR v_m IN
    -- Mesmo eixo de populacao da A3. Nao-ativos ficam de fora de proposito: papel de quem
    -- saiu e congelado por `admin_offboard_member` e afins, e em 25/08 havia 32 divergencias
    -- ali que reconciliar seria mutacao em massa que ninguem pediu.
    SELECT m.id, m.person_id, m.operational_role
    FROM public.members m
    WHERE m.member_status = 'active'
      AND m.person_id IS NOT NULL
      AND m.name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND m.name NOT LIKE '%_synthetic%'
    ORDER BY m.id
  LOOP
    v_examinados := v_examinados + 1;
    BEGIN
      v_esperado := public._derive_operational_role(v_m.person_id);

      IF v_m.operational_role IS DISTINCT FROM v_esperado THEN
        IF NOT p_dry_run THEN
          UPDATE public.members
          SET operational_role = v_esperado, updated_at = now()
          WHERE id = v_m.id AND operational_role IS DISTINCT FROM v_esperado;
        END IF;

        v_mudancas := v_mudancas || jsonb_build_object(
          'member_id', v_m.id, 'de', v_m.operational_role, 'para', v_esperado
        );
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_erros := v_erros || jsonb_build_object('member_id', v_m.id, 'erro', SQLERRM);
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'examined', v_examinados,
    'changed', jsonb_array_length(v_mudancas),
    'errors', jsonb_array_length(v_erros),
    'dry_run', p_dry_run,
    'changes', v_mudancas,
    'error_details', v_erros
  );
END;
$function$;

COMMENT ON FUNCTION public._reconcile_operational_role_cache(boolean) IS
  '#1925 - reconcilia `members.operational_role` com `_derive_operational_role()` para membros '
  'ATIVOS. Existe porque as 14 funcoes que escrevem esse campo sao todas por evento, e a virada '
  'de CURRENT_DATE em `auth_engagements` muda a derivacao sem que ninguem escreva. Nao toca '
  'nao-ativos (papel congelado no offboarding). Escreve so quando ha diferenca.';

REVOKE ALL ON FUNCTION public._reconcile_operational_role_cache(boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._reconcile_operational_role_cache(boolean) TO service_role;

-- ----------------------------------------------------------------------------
-- (4) A entrada do cron. `pg_cron` nao tem sessao, entao `auth.uid()` e nulo: quem entra por
-- aqui nao passa por portao, e o registro sai com `actor_id NULL`.
--
-- So loga quando houve mudanca ou erro. Uma linha por dia dizendo "nada a fazer" enterraria
-- justamente o dia em que algo aconteceu (#1906).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._operational_role_reconcile_cron()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  v_result := public._reconcile_operational_role_cache(false);

  IF COALESCE((v_result->>'changed')::int, 0) > 0
     OR COALESCE((v_result->>'errors')::int, 0) > 0 THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      NULL, 'members.operational_role_reconciled', 'members', NULL,
      v_result - 'error_details',
      jsonb_build_object('issue', 1925, 'via', '_operational_role_reconcile_cron',
                         'errors', v_result->'error_details')
    );
  END IF;

  RETURN v_result;
END;
$function$;

COMMENT ON FUNCTION public._operational_role_reconcile_cron() IS
  '#1925 - entrada de cron da reconciliacao de `members.operational_role`. Agendada 00:04 UTC, '
  'logo apos a virada de CURRENT_DATE que muda `auth_engagements` sem escrita nenhuma, e antes '
  'de `v4_engagement_expiration` (03:05 UTC). So grava em admin_audit_log quando houve mudanca '
  'ou erro.';

REVOKE ALL ON FUNCTION public._operational_role_reconcile_cron() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._operational_role_reconcile_cron() TO service_role;

-- ----------------------------------------------------------------------------
-- (5) O agendamento. `cron.schedule` faz upsert por NOME, entao reaplicar e idempotente.
-- 00:04 UTC = 21:04 em Sao Paulo. Minuto deslocado de proposito (#1844): hora cheia
-- concentra jobs, e o pool e compartilhado com trafego real.
-- ----------------------------------------------------------------------------
SELECT cron.schedule(
  'operational-role-reconcile-daily',
  '4 0 * * *',
  $cron$SELECT public._operational_role_reconcile_cron();$cron$
);

NOTIFY pgrst, 'reload schema';
