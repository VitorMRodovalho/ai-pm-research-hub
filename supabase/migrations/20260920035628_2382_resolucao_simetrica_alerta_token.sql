-- #2382: resolucao automatica SIMETRICA de alerta de token.
--
-- O scan ja encerrava sozinho o alerta 'unknown' quando a sonda descobria um prazo: a causa do alerta
-- deixava de existir, entao o alerta tambem. Faltava a direcao inversa, e ela aconteceu de verdade:
-- a #2378 tornou o token do Instagram perpetuo (token_expires_at e data_access_expires_at foram os dois
-- para NULL) e os dois 'warning' de 18 e 19/09 que diziam "expira em 7 dias" e "expira em 6 dias"
-- ficaram orfaos no painel, apontando para um prazo que nao existe mais.
--
-- Alerta que sobrevive a propria causa treina as pessoas a ignorar alerta, que e exatamente o motivo
-- pelo qual a resolucao automatica do 'unknown' foi escrita. A regra e a mesma nos dois sentidos:
-- quando a PREMISSA do alerta desaparece, quem criou o alerta o encerra.
--
-- `acknowledged_by` continua NULL de proposito, e continua sendo o marcador de "foi a maquina":
-- comms_acknowledge_alert() sempre grava o auth.uid() de quem dispensou. O guard do #1543 deixa de
-- exigir que todo resolvido-pela-maquina seja 'unknown' e passa a exigir a condicao que torna a
-- resolucao legitima: 'warning'/'urgent' so podem estar assim se o canal NAO tiver prazo nenhum hoje.
CREATE OR REPLACE FUNCTION public._comms_token_expiry_scan()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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
      -- #2382: o canal deixou de ter prazo, logo todo alerta que FALAVA de um prazo perdeu a premissa.
      -- Simétrico ao encerramento do 'unknown' logo abaixo, e pela mesma razão.
      UPDATE public.comms_token_alerts
      SET acknowledged = true
      WHERE channel = v_channel.channel
        AND alert_type IN ('warning', 'urgent')
        AND acknowledged = false;

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
$$;
