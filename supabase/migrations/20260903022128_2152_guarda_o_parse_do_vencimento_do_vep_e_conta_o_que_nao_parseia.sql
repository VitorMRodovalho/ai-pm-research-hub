-- WHAT: a leitura do vencimento do VEP dentro do radar diario passa a ser GUARDADA por formato, e
--       o que nao parseia passa a ser CONTADO em vez de silencioso.
--
-- POR QUE ISTO E CORRECAO DE FRAGILIDADE QUE EU MESMO INTRODUZI, uma migration antes: a faixa (C)
--       da 20260903015844 chama `to_date(pmi_memberships->0->>'expiryDate','DD Mon YYYY')` cru,
--       dentro do LOOP do cron das 09:00 UTC. Medido em 03/09/2026:
--
--         SELECT to_date('No Memberships','DD Mon YYYY')
--           -> ERROR 22007: invalid value "No" for "DD"
--
--       Uma unica string malformada vinda do VEP nao derrubaria so a faixa nova: derrubaria a
--       FUNCAO INTEIRA, e com ela o D-7 urgente, o D-30 e o aviso de vencida, que nada tem a ver
--       com o VEP. O radar de filiacao ficaria mudo por causa de um campo de terceiro.
--
--       Hoje o acervo esta limpo: das 121 candidaturas com membership, 0 sem expiryDate e 0 fora
--       do formato 'DD Mon YYYY'. Ou seja, isto NAO conserta um defeito ativo — remove um modo de
--       falha que depende de dado que a plataforma nao controla. A #2134 ja registra que o VEP
--       produz valor estranho ("No Memberships" virando NULL no nosso campo), entao a hipotese
--       nao e teorica.
--
-- POR QUE CONTAR, e nao so guardar: um CASE que devolve NULL troca "estoura" por "fica quieto", e
--       ficar quieto e o formato de defeito que este projeto mais paga caro. `expiry_unparseable`
--       entra no retorno para que a queda vire numero. Zero hoje; se subir, alguem ve.
--
-- CONTROLE DE NAO-REGRESSAO: o formato ISO ('2027-08-31') tambem cai no ELSE e vira NULL. Isso e
--       deliberado — se o VEP mudar de formato, a faixa emudece em vez de mentir uma data — e e
--       exatamente o caso que o contador torna visivel.
--
-- ROLLBACK: reaplicar o corpo da 20260903015844.
--
-- CROSS-REF: #2152, #2134

CREATE OR REPLACE FUNCTION public.v4_notify_expiring_affiliations(p_dry_run boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_count_d30  int := 0;
  v_count_d7   int := 0;
  v_count_stale int := 0;
  v_count_expired int := 0;
  v_count_vep_divergent int := 0;
  v_count_expiry_unparseable int := 0;
  v_sent       int := 0;
  v_filiacao_member_id uuid;
  r            record;
BEGIN
  -- Diretora de Filiação (sede) — destinatária de awareness quando não-dry-run.
  SELECT m.id INTO v_filiacao_member_id
  FROM public.members m
  WHERE m.is_active = true AND 'filiacao_director' = ANY(m.designations)
  LIMIT 1;

  -- Última verificação por membro (a trilha é append-only).
  -- #2152: o LATERAL traz o que o VEP informa para a MESMA pessoa. É LEFT porque nem todo membro
  -- tem candidatura espelhada; sem VEP, a faixa (C) simplesmente não avalia (r.vep_expira IS NULL).
  FOR r IN
    SELECT DISTINCT ON (mav.member_id)
      mav.member_id, mav.membership_active, mav.membership_expires_on, mav.created_at,
      m.name AS member_name, m.is_active,
      (mav.membership_expires_on - CURRENT_DATE) AS days_until_expiry,
      (CURRENT_DATE - mav.created_at::date) AS days_since_verification,
      vep.vep_expira, vep.vep_expira_bruto, vep.vep_visto
    FROM public.member_affiliation_verifications mav
    JOIN public.members m ON m.id = mav.member_id
    LEFT JOIN LATERAL (
      SELECT CASE WHEN sa.pmi_memberships->0->>'expiryDate' ~ '^\d{1,2} [A-Za-z]{3} \d{4}$'
                  THEN to_date(sa.pmi_memberships->0->>'expiryDate','DD Mon YYYY')
                  ELSE NULL END AS vep_expira,
             sa.pmi_memberships->0->>'expiryDate' AS vep_expira_bruto,
             sa.vep_last_seen_at::date AS vep_visto
      FROM public.selection_applications sa
      WHERE lower(sa.email) = lower(m.email)
        AND sa.pmi_memberships IS NOT NULL
        AND jsonb_array_length(sa.pmi_memberships) > 0
      ORDER BY sa.created_at DESC
      LIMIT 1
    ) vep ON true
    WHERE m.is_active = true
    ORDER BY mav.member_id, mav.created_at DESC
  LOOP
    -- (A) Expiração D-30
    IF r.membership_active AND r.membership_expires_on IS NOT NULL
       AND r.days_until_expiry BETWEEN 8 AND 30 THEN
      v_count_d30 := v_count_d30 + 1;
      IF NOT p_dry_run AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = r.member_id AND n.type = 'affiliation_renewal_d30'
          AND n.source_id = r.member_id AND n.created_at > (now() - interval '7 days')
      ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
        VALUES (r.member_id, 'affiliation_renewal_d30',
          'Sua filiação PMI vence em 30 dias',
          'PMI Goiás (Programa Núcleo IA): sua filiação ao PMI vence em ' || r.membership_expires_on ||
          '. O Termo de Voluntariado exige filiação PMI ativa — renove em pmi.org. '
          'Para parar estes lembretes, ajuste em /profile (não afeta seu voluntariado).',
          '/profile', 'affiliation', r.member_id,
          public._delivery_mode_for('affiliation_renewal_d30'));
        v_sent := v_sent + 1;
      END IF;
    END IF;

    -- (A) Expiração D-7 URGENTE
    IF r.membership_active AND r.membership_expires_on IS NOT NULL
       AND r.days_until_expiry BETWEEN 0 AND 7 THEN
      v_count_d7 := v_count_d7 + 1;
      IF NOT p_dry_run AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = r.member_id AND n.type = 'affiliation_renewal_d7_urgent'
          AND n.source_id = r.member_id AND n.created_at > (now() - interval '7 days')
      ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
        VALUES (r.member_id, 'affiliation_renewal_d7_urgent',
          'URGENTE: sua filiação PMI vence em 7 dias',
          'PMI Goiás (Programa Núcleo IA): sua filiação ao PMI vence em ' || r.membership_expires_on ||
          '. Renove imediatamente em pmi.org para manter seu Termo de Voluntariado vigente. '
          'Para ajustar lembretes, acesse /profile (não afeta seu voluntariado).',
          '/profile', 'affiliation', r.member_id,
          public._delivery_mode_for('affiliation_renewal_d7_urgent'));
        v_sent := v_sent + 1;
      END IF;
    END IF;

    -- (A) VENCIDA (#1855). O radar avisava D-30 e D-7 e nunca depois: quem ja tinha vencido
    -- nao casava em faixa nenhuma, porque days_until_expiry negativo falha nos dois BETWEEN.
    -- Mesmo tom dos anteriores, so lembrete, sem consequencia declarada (decisao do PM, 18/08).
    -- Dedupe de 30 dias, e nao de 7 como as faixas irmas: a faixa de vencidas e ilimitada no
    -- tempo, entao uma janela de 7 dias viraria cobranca semanal para sempre.
    IF r.membership_active AND r.membership_expires_on IS NOT NULL
       AND r.days_until_expiry < 0 THEN
      v_count_expired := v_count_expired + 1;
      IF NOT p_dry_run AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = r.member_id AND n.type = 'affiliation_renewal_expired'
          AND n.source_id = r.member_id AND n.created_at > (now() - interval '30 days')
      ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
        VALUES (r.member_id, 'affiliation_renewal_expired',
          'Sua filiação PMI venceu',
          'PMI Goiás (Programa Núcleo IA): sua filiação ao PMI venceu em ' || r.membership_expires_on ||
          '. O Termo de Voluntariado exige filiação PMI ativa. Renove em pmi.org. '
          'Para parar estes lembretes, ajuste em /profile (não afeta seu voluntariado).',
          '/profile', 'affiliation', r.member_id,
          public._delivery_mode_for('affiliation_renewal_expired'));
        v_sent := v_sent + 1;
      END IF;
    END IF;

    -- (B) Verificação obsoleta > 11 meses (cobre a varredura anual no mesmo radar).
    IF r.days_since_verification > 330 THEN
      v_count_stale := v_count_stale + 1;
      IF NOT p_dry_run AND v_filiacao_member_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = v_filiacao_member_id AND n.type = 'affiliation_verification_stale'
          AND n.source_id = r.member_id AND n.created_at > (now() - interval '30 days')
      ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
        VALUES (v_filiacao_member_id, 'affiliation_verification_stale',
          'Re-verificar filiação: ' || r.member_name,
          r.member_name || ' não tem verificação de filiação há ' || r.days_since_verification ||
          ' dias. Re-verifique na fila de /admin/members.',
          '/admin/members?filter=affiliation', 'affiliation', r.member_id,
          public._delivery_mode_for('affiliation_verification_stale'));
        v_sent := v_sent + 1;
      END IF;
    END IF;

    -- #2152/#2134: o VEP informou algo que não é uma data no formato esperado. Contado e não
    -- ignorado: sem este número, trocar "estoura" por "fica quieto" seria um upgrade ruim — a
    -- faixa (C) emudeceria e nada diria por quê.
    IF r.vep_expira IS NULL AND r.vep_expira_bruto IS NOT NULL THEN
      v_count_expiry_unparseable := v_count_expiry_unparseable + 1;
    END IF;

    -- (C) #2152: a verificação ficou ATRÁS do VEP. Distinta da faixa (B): lá o critério é IDADE da
    -- verificação, aqui é CONTRADIÇÃO entre duas fontes vivas. Uma verificação de 40 dias pode já
    -- estar errada, e uma de 300 dias pode estar certa; (B) não pega a primeira e pega a segunda.
    --
    -- O limiar de 30 dias existe para a faixa não virar ruído: divergência com meio ano de folga
    -- não produz selo vermelho nem cobrança indevida. O que se quer alcançar é a janela em que a
    -- verificação atrasada está prestes a fazer a tela dizer "vencida" para quem renovou.
    IF r.vep_expira IS NOT NULL
       AND r.membership_expires_on IS NOT NULL
       AND r.vep_expira > r.membership_expires_on
       AND r.membership_expires_on < (CURRENT_DATE + 30) THEN
      v_count_vep_divergent := v_count_vep_divergent + 1;
      IF NOT p_dry_run AND v_filiacao_member_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = v_filiacao_member_id AND n.type = 'affiliation_vep_divergence'
          AND n.source_id = r.member_id AND n.created_at > (now() - interval '30 days')
      ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
        VALUES (v_filiacao_member_id, 'affiliation_vep_divergence',
          'Filiação divergente do VEP: ' || r.member_name,
          'A verificação de ' || r.member_name || ' diz que a filiação vence em ' ||
          r.membership_expires_on || ', e o VEP (lido em ' || COALESCE(r.vep_visto::text, 'data não registrada') ||
          ') diz ' || r.vep_expira || '. A tela vai marcar filiação vencida para quem já renovou. '
          'Re-verifique em /admin/members para a verificação alcançar o VEP.',
          '/admin/members?filter=affiliation', 'affiliation', r.member_id,
          public._delivery_mode_for('affiliation_vep_divergence'));
        v_sent := v_sent + 1;
      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'dry_run', p_dry_run,
    'candidates_d30', v_count_d30,
    'candidates_d7', v_count_d7,
    'candidates_expired', v_count_expired,
    'candidates_stale', v_count_stale,
    'candidates_vep_divergent', v_count_vep_divergent,
    'expiry_unparseable', v_count_expiry_unparseable,
    'notifications_sent', v_sent,
    'run_at', now());
END;
$function$;

-- POS-CONDICOES.
DO $$
DECLARE
  v_ensaio      jsonb;
  v_da_funcao   int;
  v_da_consulta int;
  v_guardado    date;
  v_estourou    boolean := false;
BEGIN
  -- 1. A EXPRESSAO GUARDADA NAO ESTOURA onde a crua estourava. Sem este par, "a funcao roda" nao
  --    distingue "o guard funciona" de "o acervo esta limpo hoje" — e ele ESTA limpo (0 de 121
  --    fora do formato), entao um ensaio contra os dados reais passaria dos dois jeitos.
  BEGIN
    SELECT to_date('No Memberships', 'DD Mon YYYY') INTO v_guardado;
  EXCEPTION WHEN others THEN
    v_estourou := true;
  END;
  IF NOT v_estourou THEN
    RAISE EXCEPTION 'PREMISSA FALSA: to_date cru NAO estourou, entao este guard nao protege de nada';
  END IF;

  SELECT CASE WHEN x ~ '^\d{1,2} [A-Za-z]{3} \d{4}$' THEN to_date(x,'DD Mon YYYY') ELSE NULL END
    INTO v_guardado FROM (VALUES ('No Memberships')) t(x);
  IF v_guardado IS NOT NULL THEN
    RAISE EXCEPTION 'POS-CONDICAO: a expressao guardada devolveu % para lixo, esperava NULL', v_guardado;
  END IF;

  -- CONTROLE POSITIVO: o guard nao pode ter emudecido o caso BOM.
  SELECT CASE WHEN x ~ '^\d{1,2} [A-Za-z]{3} \d{4}$' THEN to_date(x,'DD Mon YYYY') ELSE NULL END
    INTO v_guardado FROM (VALUES ('31 Aug 2027')) t(x);
  IF v_guardado IS DISTINCT FROM DATE '2027-08-31' THEN
    RAISE EXCEPTION 'CONTROLE: o guard quebrou o caminho valido, devolveu %', v_guardado;
  END IF;

  -- 2. O radar responde e traz a chave nova.
  v_ensaio := public.v4_notify_expiring_affiliations(p_dry_run := true);
  IF NOT (v_ensaio ? 'expiry_unparseable') THEN
    RAISE EXCEPTION 'POS-CONDICAO: o ensaio nao devolveu expiry_unparseable';
  END IF;
  IF v_ensaio->>'notifications_sent' <> '0' THEN
    RAISE EXCEPTION 'CONTROLE: o ensaio com dry_run gravou % notificacao(oes)', v_ensaio->>'notifications_sent';
  END IF;

  -- 3. A faixa (C) continua concordando com uma consulta independente que reproduz o predicado,
  --    agora com a MESMA guarda. Se o guard tivesse mudado quem entra na faixa, os lados divergem.
  v_da_funcao := (v_ensaio->>'candidates_vep_divergent')::int;
  SELECT count(*) INTO v_da_consulta
  FROM (
    SELECT DISTINCT ON (mav.member_id) mav.membership_expires_on, vep.vep_expira
    FROM public.member_affiliation_verifications mav
    JOIN public.members m ON m.id = mav.member_id
    LEFT JOIN LATERAL (
      SELECT CASE WHEN sa.pmi_memberships->0->>'expiryDate' ~ '^\d{1,2} [A-Za-z]{3} \d{4}$'
                  THEN to_date(sa.pmi_memberships->0->>'expiryDate','DD Mon YYYY')
                  ELSE NULL END AS vep_expira
      FROM public.selection_applications sa
      WHERE lower(sa.email) = lower(m.email)
        AND sa.pmi_memberships IS NOT NULL
        AND jsonb_array_length(sa.pmi_memberships) > 0
      ORDER BY sa.created_at DESC LIMIT 1
    ) vep ON true
    WHERE m.is_active = true
    ORDER BY mav.member_id, mav.created_at DESC
  ) ult
  WHERE ult.vep_expira IS NOT NULL
    AND ult.membership_expires_on IS NOT NULL
    AND ult.vep_expira > ult.membership_expires_on
    AND ult.membership_expires_on < (CURRENT_DATE + 30);

  IF v_da_funcao <> v_da_consulta THEN
    RAISE EXCEPTION 'POS-CONDICAO: a faixa contou %, a consulta independente contou %', v_da_funcao, v_da_consulta;
  END IF;

  RAISE NOTICE '#2152 guard ok: divergentes=%, expiry_unparseable=%', v_da_funcao, v_ensaio->>'expiry_unparseable';
END $$;
