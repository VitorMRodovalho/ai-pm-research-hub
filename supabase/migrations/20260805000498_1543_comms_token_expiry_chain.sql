-- #1543 — a cadeia de alerta de token de comms tinha TRÊS quebras independentes, e só uma era sobre o
-- Instagram. Tudo medido em produção em 30/07/2026.
--
--   QUEBRA 1 — `comms_check_token_expiry()`, o ÚNICO escritor de `comms_token_alerts`, tem
--     `IF v_channel.token_expires_at IS NULL THEN CONTINUE`. O Instagram tem esse campo NULL, então era
--     pulado inteiro. `comms_token_alerts` vazia lia-se como "tokens saudáveis"; significava "o alerta não
--     tem como disparar".
--
--   QUEBRA 2 — o prazo real do Instagram NÃO é `expires_at`. O `debug_token` da Graph API devolve, para o
--     token armazenado: `is_valid: true`, `expires_at: 0` (não expira) e `data_access_expires_at` =
--     25/09/2026. Existe um prazo verdadeiro e a plataforma não tinha onde guardá-lo. A coluna que faltava
--     não era de "expiração de token", era de "expiração de acesso a dados".
--
--   QUEBRA 3 — e esta vale para TODOS os canais: não havia cron. Conferido contra os 64 jobs ativos; o
--     único que toca comms é `sync-comms-metrics-daily` (jobid 21), que chama a Edge Function, não esta
--     RPC. `comms_check_token_expiry()` só rodava a partir de `loadTokenAlerts()` em
--     `src/pages/admin/comms.astro`, ou seja, quando um humano abria `/admin/comms`. A mensagem que ela
--     produz é "Renove em Admin → Comunicação" — e só aparecia para quem já estava em Admin → Comunicação.
--     Mesma família do helper sem consumidor do #1495: o mecanismo existia e não alcançava ninguém.
--
-- ⚠️ A ARMADILHA DE CONSERTAR A QUEBRA 3 DO JEITO ÓBVIO, e a razão do desenho abaixo: agendar
-- `comms_check_token_expiry()` direto NÃO funcionaria e PARECERIA funcionar. Ela abre com
-- `IF NOT public.can_view_comms_analytics() THEN RETURN` zero-shape, e esse gate resolve
-- `members WHERE auth_id = auth.uid()`. Sob pg_cron não há JWT, `auth.uid()` é NULL, o gate nega, e o job
-- devolveria sucesso todo dia sem escrever nada — verde por vácuo, registrado como saudável em
-- `cron.job_run_details`. Por isso a função `_cron` separada, no mesmo molde de
-- `ratification_window_close_cron`: SECDEF, sem gate de usuário, alcançável só por postgres/service_role.
--
-- A lógica fica em UM worker (`_comms_token_expiry_scan`) que as duas portas chamam, para que a versão da
-- UI e a versão do cron não possam divergir com o tempo.

-- ── Colunas: o prazo que EXISTE, e a distinção entre "sem prazo" e "nunca sondado" ──────────────────
ALTER TABLE public.comms_channel_config
  ADD COLUMN IF NOT EXISTS data_access_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS token_checked_at timestamptz;

COMMENT ON COLUMN public.comms_channel_config.data_access_expires_at IS
  'Prazo de acesso a dados devolvido pelo debug_token da Graph API (#1543). Para o Instagram este é o '
  'prazo que EXISTE; token_expires_at pode ser NULL porque o token não expira (expires_at = 0).';
COMMENT ON COLUMN public.comms_channel_config.token_checked_at IS
  'Quando a validade foi confirmada na API do provedor pela última vez (#1543). NULL = nunca sondado, que '
  'é DESCONHECIDO e não "válido" — a distinção que faltava e deixava o canal sem vigilância.';

-- 'unknown' entra no vocabulário em vez de reusar 'warning': "expira em 5 dias" e "não sei se expira" são
-- afirmações diferentes e pedem ações diferentes. Empilhar as duas no mesmo tipo é o vício que o #1537
-- passou esta mesma sessão desmontando em outra tabela.
ALTER TABLE public.comms_token_alerts DROP CONSTRAINT IF EXISTS comms_token_alerts_alert_type_check;
ALTER TABLE public.comms_token_alerts ADD CONSTRAINT comms_token_alerts_alert_type_check
  CHECK (alert_type = ANY (ARRAY['warning'::text, 'urgent'::text, 'resolved'::text, 'unknown'::text]));

-- ── Worker único ────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._comms_token_expiry_scan()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_channel record;
  v_deadline timestamptz;
  v_days int;
  v_alerts_created int := 0;
  v_alerts jsonb := '[]'::jsonb;
BEGIN
  FOR v_channel IN
    SELECT channel, token_expires_at, data_access_expires_at, token_checked_at,
           sync_status, oauth_token, api_key
    FROM public.comms_channel_config
  LOOP
    -- YouTube usa api_key, que não expira — segue sendo exceção legítima e declarada.
    IF v_channel.channel = 'youtube' THEN
      CONTINUE;
    END IF;

    -- Sem token OAuth configurado não há o que vigiar.
    IF v_channel.oauth_token IS NULL THEN
      CONTINUE;
    END IF;

    -- O prazo que vale é o MAIS PRÓXIMO entre expiração do token e expiração do acesso a dados. Antes
    -- desta migration só o primeiro era considerado, e para o Instagram só o segundo existe.
    v_deadline := LEAST(
      COALESCE(v_channel.token_expires_at, 'infinity'::timestamptz),
      COALESCE(v_channel.data_access_expires_at, 'infinity'::timestamptz)
    );
    IF v_deadline = 'infinity'::timestamptz THEN
      v_deadline := NULL;
    END IF;

    IF v_deadline IS NULL THEN
      -- Nenhum prazo conhecido. Isso NÃO é "válido": é desconhecido, e a diferença entre as duas coisas é
      -- o buraco que deixou o Instagram sem vigilância. Só vira alerta quando a sonda também está
      -- ausente ou velha — um token confirmado na API há pouco e sem prazo é legitimamente perpétuo.
      IF v_channel.token_checked_at IS NULL
         OR v_channel.token_checked_at < now() - interval '7 days' THEN
        IF NOT EXISTS (
          SELECT 1 FROM public.comms_token_alerts
          WHERE channel = v_channel.channel
            AND alert_type = 'unknown'
            AND created_at > now() - interval '1 day'
        ) THEN
          INSERT INTO public.comms_token_alerts (channel, alert_type, message, days_until_expiry)
          VALUES (
            v_channel.channel,
            'unknown',
            format(
              'Validade do token do %s é DESCONHECIDA: sem prazo registrado e sem confirmação na API %s. '
              'Nada está vigiando este canal.',
              v_channel.channel,
              CASE WHEN v_channel.token_checked_at IS NULL
                   THEN 'em momento nenhum'
                   ELSE format('desde %s', to_char(v_channel.token_checked_at, 'DD/MM/YYYY')) END
            ),
            NULL
          );
          v_alerts_created := v_alerts_created + 1;
        END IF;
      END IF;
      CONTINUE;
    END IF;

    -- Chegou aqui: o prazo é conhecido. Se havia alerta 'unknown' aberto para este canal, ele acabou de
    -- perder a causa — a sonda descobriu o prazo. Alerta que sobrevive à própria causa treina as pessoas a
    -- ignorar alerta, então ele é encerrado aqui.
    --
    -- `acknowledged_by` fica NULL de propósito, e isso NÃO é descuido: `comms_acknowledge_alert()` sempre
    -- grava o `auth.uid()` de quem dispensou, então `acknowledged = true AND acknowledged_by IS NULL` é o
    -- marcador inequívoco de "resolvido pela máquina". Escrever um uuid qualquer aqui faria a coluna
    -- mentir sobre um ato humano que não houve.
    UPDATE public.comms_token_alerts
    SET acknowledged = true
    WHERE channel = v_channel.channel
      AND alert_type = 'unknown'
      AND acknowledged = false;

    v_days := EXTRACT(day FROM v_deadline - now())::int;

    IF v_days < 0 THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.comms_token_alerts
        WHERE channel = v_channel.channel
          AND alert_type = 'urgent'
          AND created_at > now() - interval '1 day'
      ) THEN
        INSERT INTO public.comms_token_alerts (channel, alert_type, message, days_until_expiry)
        VALUES (
          v_channel.channel,
          'urgent',
          format('Token do %s expirou. Métricas não estão sendo atualizadas.', v_channel.channel),
          v_days
        );
        v_alerts_created := v_alerts_created + 1;
      END IF;

      UPDATE public.comms_channel_config
      SET sync_status = 'token_expired'
      WHERE channel = v_channel.channel AND sync_status != 'token_expired';

    ELSIF v_days <= 7 THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.comms_token_alerts
        WHERE channel = v_channel.channel
          AND alert_type = 'warning'
          AND created_at > now() - interval '1 day'
      ) THEN
        INSERT INTO public.comms_token_alerts (channel, alert_type, message, days_until_expiry)
        VALUES (
          v_channel.channel,
          'warning',
          format('Token do %s expira em %s dias. Renove em Admin → Comunicação.', v_channel.channel, v_days),
          v_days
        );
        v_alerts_created := v_alerts_created + 1;
      END IF;
    END IF;
  END LOOP;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', a.id,
    'channel', a.channel,
    'alert_type', a.alert_type,
    'message', a.message,
    'days_until_expiry', a.days_until_expiry,
    'created_at', a.created_at
  ) ORDER BY
    CASE a.alert_type WHEN 'urgent' THEN 0 WHEN 'warning' THEN 1 WHEN 'unknown' THEN 2 ELSE 3 END,
    a.created_at DESC
  ), '[]'::jsonb)
  INTO v_alerts
  FROM public.comms_token_alerts a
  WHERE a.acknowledged = false;

  RETURN jsonb_build_object('alerts_created', v_alerts_created, 'active_alerts', v_alerts);
END;
$function$;

COMMENT ON FUNCTION public._comms_token_expiry_scan() IS
  'Worker único da varredura de expiração de token (#1543). Não tem gate de usuário porque não é porta: as '
  'portas são comms_check_token_expiry() (gateada, para a UI) e comms_check_token_expiry_cron() (para o '
  'pg_cron). Manter a lógica aqui impede que as duas divirjam.';

REVOKE ALL ON FUNCTION public._comms_token_expiry_scan() FROM PUBLIC, anon, authenticated;

-- ── Porta 1: a UI, com o gate original preservado ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.comms_check_token_expiry()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- #963: alertas de expiração são dado de comms-ops e esta chamada escreve. Restrito ao tier de
  -- comms-analytics, igual às RPCs irmãs. Negado → zero-shape (sem escrita, sem leitura); a página
  -- /admin/comms esconde a seção de alertas quando active_alerts vem vazio.
  IF NOT public.can_view_comms_analytics() THEN
    RETURN jsonb_build_object('alerts_created', 0, 'active_alerts', '[]'::jsonb);
  END IF;

  RETURN public._comms_token_expiry_scan();
END;
$function$;

REVOKE ALL ON FUNCTION public.comms_check_token_expiry() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.comms_check_token_expiry() TO authenticated, service_role;

-- ── Porta 2: o pg_cron, sem gate de usuário ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.comms_check_token_expiry_cron()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- SEM can_view_comms_analytics() de propósito: esse gate resolve auth.uid(), que é NULL sob pg_cron, e
  -- faria o job devolver zero-shape todo dia sem escrever nada. A proteção aqui é o ACL (REVOKE de
  -- PUBLIC/anon/authenticated logo abaixo), não um gate que a própria chamada não consegue satisfazer.
  RETURN public._comms_token_expiry_scan();
END;
$function$;

COMMENT ON FUNCTION public.comms_check_token_expiry_cron() IS
  'Porta do pg_cron para a varredura de token (#1543). Sem gate de usuário por construção — ver o corpo. '
  'Alcançável apenas por postgres e service_role.';

REVOKE ALL ON FUNCTION public.comms_check_token_expiry_cron() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.comms_check_token_expiry_cron() TO service_role;

-- ── O cron que faltava ──────────────────────────────────────────────────────────────────────────────
-- 09:20 UTC = 06:20 BRT, fora dos horários já ocupados (0 9 é do auto-promote-eligible-leads-daily).
SELECT cron.unschedule('comms-token-expiry-daily')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'comms-token-expiry-daily');

SELECT cron.schedule(
  'comms-token-expiry-daily',
  '20 9 * * *',
  $cron$SELECT public.comms_check_token_expiry_cron();$cron$
);
