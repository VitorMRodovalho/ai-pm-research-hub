-- #1855 — o radar de filiacao passa a enxergar quem JA venceu, e sai do dry-run.
--
-- Tres mudancas, nenhuma delas estrutural:
--
-- 1. Faixa nova de VENCIDAS. As faixas existentes sao BETWEEN 8 AND 30 e BETWEEN 1 AND 7 sobre
--    days_until_expiry, entao um valor NEGATIVO nao casa em nenhuma: quem ja venceu nunca recebeu
--    nada. Medido em 18/08/2026 22:37 UTC: 2 pessoas nessa condicao, vencidas em 31/07.
--    Tom decidido pelo PM em 18/08: so lembrete, sem consequencia declarada. O texto cita o Termo,
--    pmi.org e o opt-out, igual as faixas irmas.
--
-- 2. Buraco do dia 0. A faixa urgente comecava em 1, entao o PROPRIO dia do vencimento nao casava
--    em faixa nenhuma: o D-7 ja tinha passado e a faixa de vencidas ainda nao valia. Hoje isso
--    atinge 0 pessoas, mas o buraco e estrutural e some com BETWEEN 0 AND 7.
--
-- 3. O freio sai. O cron v4-affiliation-expiry-notify roda desde 11/06 com p_dry_run := true,
--    ou seja, conta e nao envia. Passa a false.
--
-- Dedupe: a faixa de vencidas usa 30 dias, e nao os 7 das irmas, porque ela e ilimitada no tempo.
-- A 7 dias, quem nao renovar recebe cobranca semanal para sempre.
--
-- LIMITE CONHECIDO, e ele nao e coberto aqui: o laco le de member_affiliation_verifications, entao
-- so alcanca quem a Diretoria de Filiacao ja verificou. Medido em 18/08/2026: 94 membros ativos,
-- 62 com verificacao, 32 sem nenhuma linha. Esses 32 sao invisiveis ao radar, e a lacuna e nossa,
-- nao deles: o caminho e a fila da Diretoria, nao e-mail.
--
-- Bases conferidas por md5 normalizado contra o vivo imediatamente antes de aplicar, drift zero:
--   v4_notify_expiring_affiliations = b20e8d2eb738e70fb8cb03b4bcd6793a (4584 chars)
--   _delivery_mode_for              = df676b810655287c7f65dd191fa0686f (4233 chars)

CREATE OR REPLACE FUNCTION public.v4_notify_expiring_affiliations(p_dry_run boolean DEFAULT true)
RETURNS jsonb
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_count_d30  int := 0;
  v_count_d7   int := 0;
  v_count_stale int := 0;
  v_count_expired int := 0;
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
  FOR r IN
    SELECT DISTINCT ON (mav.member_id)
      mav.member_id, mav.membership_active, mav.membership_expires_on, mav.created_at,
      m.name AS member_name, m.is_active,
      (mav.membership_expires_on - CURRENT_DATE) AS days_until_expiry,
      (CURRENT_DATE - mav.created_at::date) AS days_since_verification
    FROM public.member_affiliation_verifications mav
    JOIN public.members m ON m.id = mav.member_id
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
  END LOOP;

  RETURN jsonb_build_object(
    'dry_run', p_dry_run,
    'candidates_d30', v_count_d30,
    'candidates_d7', v_count_d7,
    'candidates_expired', v_count_expired,
    'candidates_stale', v_count_stale,
    'notifications_sent', v_sent,
    'run_at', now());
END;
$function$;

-- Cataloga o tipo novo no despachante de entrega.
CREATE OR REPLACE FUNCTION public._delivery_mode_for(p_type text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO ''
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

-- O freio sai. Sem hardcode do jobid: o nome e a chave estavel.
SELECT cron.alter_job(
  job_id  := (SELECT jobid FROM cron.job WHERE jobname = 'v4-affiliation-expiry-notify'),
  command := 'SELECT public.v4_notify_expiring_affiliations(p_dry_run := false)'
);
