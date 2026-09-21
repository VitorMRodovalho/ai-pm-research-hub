-- #2407: o helper de teste deixa de apagar alerta de producao, ficando hermetico de verdade.
--
-- O QUE ELE FAZIA, e o dano medido em 21/09/2026:
--   O bloco abaixo apagava TODO `arm9_inactivity_alert` dos ultimos 6 dias, de TODOS os
--   destinatarios, para que a dedup da #1170 nao derrotasse a assercao `managers_notified > 0`.
--   O probe que deveria guarda-lo roda com o override de limiar JA aplicado, e no teste hermetico
--   o limiar e 0, que por construcao produz candidatos (99 medidos). Entao o DELETE sempre
--   disparava nesse caminho.
--   Efeito: o cron `detect-inactive-members-weekly` (`0 12 * * 1`) notificou 2 gestores as
--   12:00:00 de 21/09, o CI rodou as 13:15, e o total de `arm9_inactivity_alert` na base ficou em
--   ZERO. O alerta semanal de inatividade nascia toda segunda e era apagado pelo primeiro CI do
--   dia, portanto nunca chegava a ser lido.
--
-- A DECISAO, ratificada pelo dono em 21/09 (kit `decision-records-kit`, §5: a ratificacao do
-- humano E o artefato):
--   "Escopar o DELETE ao que o teste cria", e na bifurcacao de implementacao,
--   "Subtransacao que desfaz tudo".
--
-- POR QUE A SUBTRANSACAO, e nao um DELETE mais estreito:
--   Nao existe DELETE estreito que resolva. As linhas que SUPRIMEM sao justamente as de producao,
--   entao qualquer recorte que preserve a assercao `managers_notified > 0` teria de remove-las.
--   A saida honesta e nao COMMITAR nada: o bloco apaga, roda, captura o resultado e ABORTA a
--   subtransacao. O PL/pgSQL desfaz toda escrita feita dentro do frame e PRESERVA as variaveis
--   locais, que e exatamente a assimetria de que este helper precisa.
--
--   Exercitado antes de escrever esta migration, em tabela temporaria, sem tocar producao:
--     * `WHEN SQLSTATE 'ND407'` pega a sentinela .......... SIM
--     * linhas sobreviventes ao aborto .................... 0
--     * variavel com o resultado ......................... sobreviveu intacta
--
-- EFEITO COLATERAL BOM, e medido: o helper tambem para de despejar ruido em producao.
--   `admin_audit_log` tem 4014 linhas de `arm9.inactivity_detection_run` desde 18/05, das quais
--   3684 sao deste helper (limiar 0). A partir daqui, zero.
--
-- O QUE ISTO CUSTA, declarado:
--   O caminho INSERT continua sendo EXERCIDO (as constraints sao checadas no INSERT, nao no
--   commit), mas deixa de ser COMMITADO. Um defeito que so aparecesse no commit escaparia. Nao ha
--   defeito conhecido dessa classe aqui, e o preco alternativo era continuar apagando dado alheio.
--
-- ⚠️ E isto torna VAZIA a assercao de residuo do teste (`residue === 0`), que passa a ser
--   verdadeira por construcao. O guard ganha no lugar uma assercao que PODE falhar: a contagem de
--   linhas de audit com `threshold_days = 0` antes e depois da chamada tem de ser IGUAL.
--
-- Cross-ref: #2407, #1170 (a dedup e o vazamento de 4216 linhas), #231, #2405.

CREATE OR REPLACE FUNCTION public._test_detect_inactive_with_threshold(p_threshold integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_old_value jsonb;
  v_result jsonb;
BEGIN
  -- Defense: service_role only (matches detect_inactive_members cron-bypass check).
  -- Phrasing aligned with ADR-0011 canonical hasAuthGate set (p187 MED-186.F).
  IF current_setting('role', true) NOT IN ('service_role', 'postgres')
     AND current_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Unauthorized: _test_detect_inactive_with_threshold requires service_role';
  END IF;

  IF p_threshold < 0 THEN
    RAISE EXCEPTION 'p_threshold must be >= 0 (got %)', p_threshold;
  END IF;

  -- Snapshot current site_config value
  SELECT value INTO v_old_value
    FROM public.site_config
   WHERE key = 'inactivity_threshold_days';

  -- Override. FICA FORA do frame que aborta, de proposito: o `detect_inactive_members` de dentro
  -- precisa enxergar o limiar sobrescrito, e a restauracao defensiva abaixo e quem o desfaz.
  UPDATE public.site_config
     SET value = to_jsonb(p_threshold)
   WHERE key = 'inactivity_threshold_days';

  -- #2407: o frame agora tem DUAS funcoes: restaurar `site_config` em caso de erro (como antes)
  -- e, no caminho feliz, DESFAZER tudo o que foi escrito aqui dentro.
  BEGIN
    -- #1170: a dedup de 6 dias derrotaria `managers_notified > 0`. Limpar a janela continua sendo
    -- o unico jeito de exercitar o caminho INSERT, e agora essa limpeza NAO SOBREVIVE ao bloco.
    IF (public.detect_inactive_members(p_dry_run := true)->>'candidates_count')::int > 0 THEN
      DELETE FROM public.notifications
       WHERE type = 'arm9_inactivity_alert'
         AND created_at > (now() - interval '6 days');
    END IF;

    v_result := public.detect_inactive_members(p_dry_run := false);

    -- #2407: a sentinela. Abortar o frame desfaz o DELETE acima E os INSERTs que
    -- `detect_inactive_members` acabou de fazer em `notifications` e `admin_audit_log`.
    -- `v_result` sobrevive porque variavel de PL/pgSQL nao e transacional, e e sobre ela que o
    -- teste afirma. SQLSTATE proprio para nao confundir a sentinela com erro de verdade: um
    -- `WHEN OTHERS` sozinho aqui engoliria o defeito que este mesmo repo passou o dia caçando.
    RAISE EXCEPTION USING ERRCODE = 'ND407', MESSAGE = '#2407 sentinela hermetica: desfaz as escritas do teste';
  EXCEPTION
    WHEN SQLSTATE 'ND407' THEN
      -- Caminho esperado: o frame ja foi desfeito. Nada a fazer.
      NULL;
    WHEN OTHERS THEN
      UPDATE public.site_config
         SET value = v_old_value
       WHERE key = 'inactivity_threshold_days';
      RAISE;
  END;

  -- Defensive restore (belt+suspenders for cases where caller forgot tx=rollback)
  UPDATE public.site_config
     SET value = v_old_value
   WHERE key = 'inactivity_threshold_days';

  RETURN v_result;
END;
$function$;
