-- WHAT: o radar diario de filiacao (`v4_notify_expiring_affiliations`, cron 09:00 UTC) ganha uma
--       faixa que compara a ULTIMA verificacao com o que o VEP informa e avisa a diretoria de
--       filiacao quando a verificacao ficou para tras. Nao escreve verificacao nenhuma.
--
-- POR QUE AVISO E NAO ESCRITA (decisao do dono, 03/09/2026): as RPCs que gravam verificacao exigem
--       `filiacao_director` / `manage_member` e vedam auto-verificacao. Um cron gravando
--       verificacao produziria verificacao SEM VERIFICADOR, que e mudanca de politica e nao
--       conserto. O radar aponta; quem tem autoridade verifica.
--
-- ESTADO MEDIDO EM 03/09/2026, antes de escrever (e o motivo de isto ser tripwire, nao remendo):
--
--         pares com as duas fontes .......... 69
--         falso "vencida" hoje ..............  0   <- a #2152 corrigiu as nove em 02/09
--         falso "em dia" hoje ...............  0
--         verificacoes atras do VEP .........  0
--         que virariam falso-vencida em 90d .  0
--         ensaio do cron hoje ............... 3 D-30, 0 D-7, 0 vencidas, 0 obsoletas
--
--       Ou seja: esta faixa dispara em ZERO hoje, de proposito. Ela existe para pegar a proxima
--       leva de renovacoes antes de virar selo vermelho na tela, porque o defeito reaparece
--       sozinho: toda verificacao envelhece um ano e nada a reescreve. Cobertura e integral, os
--       67 membros ativos com verificacao tem todos espelho no VEP.
--
-- LIMIAR DA FAIXA: so avisa quando a verificacao atrasada esta a menos de 30 dias de vencer (ou ja
--       venceu) E o VEP diz data maior. Divergencia com oito meses de folga e ruido: nao produz
--       selo errado nem cobranca indevida, e avisar dela treinaria a diretoria a ignorar o aviso.
--
-- POR QUE `_delivery_mode_for` ENTRA JUNTO: o CASE tem `ELSE 'digest_weekly'`, e os comentarios
--       de #625 (bloco 5b) e #1855 registram que tipo novo deve ser CATALOGADO em vez de cair no
--       ELSE, porque o ELSE e default de conveniencia e um dia muda. Sem esta metade, o tipo novo
--       funcionaria hoje e mudaria de comportamento sem ninguem tocar nele.
--
-- SOBRE A TRANSCRICAO DO CASE: o corpo de `_delivery_mode_for` e longo e foi reescrito inteiro
--       aqui. Transcrever corpo de funcao a mao inventa funcao, entao a pos-condicao NAO confia na
--       copia: ela extrai do corpo VIVO (antes) todos os tipos catalogados, avalia cada um, e
--       depois exige diferenca simetrica zero contra a avaliacao nova, mais exatamente um tipo a
--       mais. Erro de transcricao em qualquer WHEN reprova.
--
-- O QUE ESTA MIGRATION NAO FAZ, e fica registrado como pendencia: as faixas D-30 / D-7 / vencida
--       continuam avisando o MEMBRO com base na verificacao. Se a verificacao estiver atrasada, o
--       membro recebe cobranca de renovacao estando regular. Hoje isso nao acontece (divergencia
--       = 0, e os 3 candidatos D-30 batem com o VEP), e suprimir o aviso ao membro muda QUEM e
--       notificado, que nao foi o que se decidiu. Fica para decisao propria.
--
-- ROLLBACK: reaplicar os corpos anteriores das duas funcoes.
--
-- CROSS-REF: #2152, #625, #1855

-- 0. CAPTURA O ANTES, direto do corpo vivo. Nao ha lista transcrita aqui de proposito: o regex le
--    os WHEN que o Postgres esta executando agora.
CREATE TABLE public._tmp_2152_delivery_before AS
SELECT m[1] AS tipo, public._delivery_mode_for(m[1]) AS modo
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace,
LATERAL regexp_matches(p.prosrc, 'WHEN ''([a-z0-9_]+)''', 'g') m
WHERE n.nspname = 'public' AND p.proname = '_delivery_mode_for';

-- 1. O catalogo de entrega, com o tipo novo somado ao fim do bloco de filiacao.
CREATE OR REPLACE FUNCTION public._delivery_mode_for(p_type text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $function$
  SELECT CASE p_type
    -- PR-2 (email audit): the per-signing leadership alert is now in-app only; the daily
    -- digest (volunteer_term_signed_digest) carries the single aggregated email.
    WHEN 'volunteer_agreement_signed'    THEN 'suppress'
    WHEN 'volunteer_term_signed_digest'  THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_pending'  THEN 'transactional_immediate'
    WHEN 'system_alert'                  THEN 'transactional_immediate'
    -- #1169: ready is redundant with issued at the email layer (issued carries the single email);
    -- kept in-app only. Every ready-cert already fired an issued email (0 ready-without-issued/60d).
    WHEN 'certificate_ready'             THEN 'suppress'
    WHEN 'certificate_issued'            THEN 'transactional_immediate'
    WHEN 'member_offboarded'             THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_advanced'    THEN 'transactional_immediate'
    WHEN 'ip_ratification_chain_approved'   THEN 'transactional_immediate'
    WHEN 'ip_ratification_awaiting_members' THEN 'transactional_immediate'
    WHEN 'webinar_status_confirmed'      THEN 'transactional_immediate'
    WHEN 'webinar_status_completed'      THEN 'transactional_immediate'
    WHEN 'webinar_status_cancelled'      THEN 'transactional_immediate'
    WHEN 'weekly_card_digest_member'     THEN 'transactional_immediate'
    WHEN 'governance_cr_new'             THEN 'transactional_immediate'
    WHEN 'governance_cr_vote'            THEN 'transactional_immediate'
    WHEN 'governance_cr_approved'        THEN 'transactional_immediate'
    WHEN 'sponsor_finance_entry_logged'  THEN 'transactional_immediate'
    WHEN 'governance_manual_proposed'    THEN 'transactional_immediate'
    WHEN 'engagement_renewal_d7_urgent'  THEN 'transactional_immediate'
    -- p153 OPP-153.1: project_charter (TAP) notifications
    WHEN 'project_charter_invite'        THEN 'transactional_immediate'
    WHEN 'project_charter_approved'      THEN 'transactional_immediate'
    -- p159 S#1 T1 (2026-05-14): selection_termo_due é o "email principal" pós-VEP-Active
    WHEN 'selection_termo_due'           THEN 'transactional_immediate'
    -- p228 #260 W2 Leaf 1 (2026-05-23): Selection funnel Policy Matrix
    WHEN 'selection_approved'            THEN 'transactional_immediate'
    WHEN 'selection_interview_scheduled' THEN 'transactional_immediate'
    WHEN 'peer_review_requested'         THEN 'transactional_immediate'
    WHEN 'selection_evaluation_complete' THEN 'suppress'
    WHEN 'selection_interview_noshow'    THEN 'digest_weekly'
    -- p228 #260 W2 Leaf 2 (2026-05-23): admin reminder for overdue interviews
    WHEN 'selection_interview_overdue'   THEN 'digest_weekly'
    -- p228 #260 W2 Leaf 4 (2026-05-23): candidate invite to book interview after
    -- objective evaluations cleared + research_score >= cycle cutoff.
    WHEN 'selection_cutoff_approved'     THEN 'transactional_immediate'
    -- (end p228)
    -- #2013 (2026-08-26): o teto de lembretes de reagendamento foi atingido e o caso vira
    -- trabalho de gente. Imediato de proposito: e o unico aviso, e o digest semanal so
    -- entrega a quem tem OUTRO conteudo na semana (#2010).
    WHEN 'selection_reschedule_escalated' THEN 'transactional_immediate'
    -- #186 (2026-06-05): curation committee broadcast when an item enters curation_pending
    WHEN 'curation_item_submitted'       THEN 'transactional_immediate'
    WHEN 'engagement_renewal_d30'        THEN 'digest_weekly'
    WHEN 'engagement_renewal_d60_gp_aggregate' THEN 'digest_weekly'
    -- #625 F3 (2026-06-11): radar de renovação de filiação
    WHEN 'affiliation_renewal_d7_urgent'  THEN 'transactional_immediate'
    WHEN 'affiliation_renewal_d30'        THEN 'digest_weekly'
    WHEN 'affiliation_verification_stale' THEN 'digest_weekly'
    -- #1855 (2026-08-18): faixa de filiacao ja VENCIDA. Catalogado de proposito, e nao deixado
    -- cair no ELSE, pelo mesmo motivo registrado no bloco 5b da #625: o ELSE e um default de
    -- conveniencia e um dia muda. digest_weekly porque o PM decidiu 'so lembrete, mesmo tom'.
    WHEN 'affiliation_renewal_expired'    THEN 'digest_weekly'
    -- #2152 (2026-09-03): a verificacao ficou atras do VEP. Vai para a diretoria, nao para o
    -- membro, e no mesmo modo da faixa irma de verificacao obsoleta: e trabalho de fila, nao
    -- urgencia. Catalogado em vez de cair no ELSE, pelo motivo registrado acima.
    WHEN 'affiliation_vep_divergence'     THEN 'digest_weekly'
    -- #1224 PR2 (2026-07-09): one-time onboarding nudge when the PMI enrichment cannot resolve
    -- an entry chapter (profile_private / no_fetch / not_affiliated / ambiguous-no-choice).
    WHEN 'entry_chapter_action_needed'    THEN 'transactional_immediate'
    -- #740 Wave 3c-i (B8): agreement rejected / reissued — member must re-sign, deliver immediately
    WHEN 'volunteer_agreement_rejected'  THEN 'transactional_immediate'
    WHEN 'volunteer_agreement_reissued'  THEN 'transactional_immediate'
    WHEN 'attendance_detractor'          THEN 'suppress'
    WHEN 'info'                          THEN 'suppress'
    WHEN 'system'                        THEN 'suppress'
    ELSE 'digest_weekly'
  END;
$function$;

-- 2. O radar, com a faixa (C) nova. As faixas A e B ficam identicas ao que estavam.
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
      vep.vep_expira, vep.vep_visto
    FROM public.member_affiliation_verifications mav
    JOIN public.members m ON m.id = mav.member_id
    LEFT JOIN LATERAL (
      SELECT to_date(sa.pmi_memberships->0->>'expiryDate','DD Mon YYYY') AS vep_expira,
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
    'notifications_sent', v_sent,
    'run_at', now());
END;
$function$;

-- 3. POS-CONDICOES.
DO $$
DECLARE
  v_modo_mudou   int;
  v_sumiram      int;
  v_surgiram     text[];
  v_modo_novo    text;
  v_ensaio       jsonb;
  v_da_funcao    int;
  v_da_consulta  int;
BEGIN
  -- 3a. PROVA DA TRANSCRICAO, lado dos MODOS: todo tipo que ja existia tem de continuar entregando
  --     no mesmo modo.
  SELECT count(*) INTO v_modo_mudou
    FROM public._tmp_2152_delivery_before b
   WHERE public._delivery_mode_for(b.tipo) IS DISTINCT FROM b.modo;
  IF v_modo_mudou <> 0 THEN
    RAISE EXCEPTION 'TRANSCRICAO: % tipo(s) mudaram de modo de entrega', v_modo_mudou;
  END IF;

  -- 3b. PROVA DA TRANSCRICAO, lado dos NOMES, nos dois sentidos. So 3a nao basta: um WHEN apagado
  --     cujo modo era 'digest_weekly' cairia no ELSE 'digest_weekly' e passaria em 3a sem que nada
  --     acusasse. Aqui a comparacao e entre os CONJUNTOS de tipos catalogados no corpo, extraidos
  --     do prosrc vivo dos dois lados, e nao entre resultados.
  WITH depois AS (
    SELECT m[1] AS tipo
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
         LATERAL regexp_matches(p.prosrc, 'WHEN ''([a-z0-9_]+)''', 'g') m
    WHERE n.nspname = 'public' AND p.proname = '_delivery_mode_for'
  )
  SELECT (SELECT count(*) FROM public._tmp_2152_delivery_before b
           WHERE NOT EXISTS (SELECT 1 FROM depois d WHERE d.tipo = b.tipo)),
         (SELECT array_agg(d.tipo ORDER BY d.tipo) FROM depois d
           WHERE NOT EXISTS (SELECT 1 FROM public._tmp_2152_delivery_before b WHERE b.tipo = d.tipo))
    INTO v_sumiram, v_surgiram;

  IF v_sumiram <> 0 THEN
    RAISE EXCEPTION 'TRANSCRICAO: % tipo(s) sumiram do catalogo', v_sumiram;
  END IF;
  IF v_surgiram IS DISTINCT FROM ARRAY['affiliation_vep_divergence'] THEN
    RAISE EXCEPTION 'TRANSCRICAO: os tipos novos foram %, esperava exatamente {affiliation_vep_divergence}', v_surgiram;
  END IF;

  -- 3c. O tipo novo esta catalogado de verdade, e nao apenas caindo no ELSE. Como o ELSE devolve
  --     'digest_weekly' e o modo escolhido TAMBEM e 'digest_weekly', perguntar o modo nao
  --     distingue as duas situacoes: quem distingue e 3b, que le o corpo. Aqui so se afirma o
  --     valor entregue.
  v_modo_novo := public._delivery_mode_for('affiliation_vep_divergence');
  IF v_modo_novo <> 'digest_weekly' THEN
    RAISE EXCEPTION 'POS-CONDICAO: modo do tipo novo e %, esperava digest_weekly', v_modo_novo;
  END IF;

  -- 3d. O radar responde, e traz a chave nova.
  v_ensaio := public.v4_notify_expiring_affiliations(p_dry_run := true);
  IF NOT (v_ensaio ? 'candidates_vep_divergent') THEN
    RAISE EXCEPTION 'POS-CONDICAO: o ensaio nao devolveu candidates_vep_divergent';
  END IF;
  IF v_ensaio->>'notifications_sent' <> '0' THEN
    RAISE EXCEPTION 'CONTROLE: o ensaio com dry_run gravou % notificacao(oes)', v_ensaio->>'notifications_sent';
  END IF;

  -- 3e. A FAIXA FAZ O QUE O COMENTARIO DIZ. Nao se afirma um numero fixo aqui, porque o numero
  --     depende do dia: afirma-se que a contagem da funcao bate com uma consulta independente que
  --     reproduz o predicado. Se a faixa filtrar por outra coisa, os dois lados divergem.
  v_da_funcao := (v_ensaio->>'candidates_vep_divergent')::int;

  SELECT count(*) INTO v_da_consulta
  FROM (
    SELECT DISTINCT ON (mav.member_id)
           mav.membership_expires_on, vep.vep_expira
    FROM public.member_affiliation_verifications mav
    JOIN public.members m ON m.id = mav.member_id
    LEFT JOIN LATERAL (
      SELECT to_date(sa.pmi_memberships->0->>'expiryDate','DD Mon YYYY') AS vep_expira
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
    RAISE EXCEPTION 'POS-CONDICAO: a faixa contou %, a consulta independente contou %',
                    v_da_funcao, v_da_consulta;
  END IF;

  RAISE NOTICE '#2152 ok: catalogo intacto, faixa (C) concorda com a consulta independente em % caso(s)', v_da_funcao;
END $$;

DROP TABLE public._tmp_2152_delivery_before;
