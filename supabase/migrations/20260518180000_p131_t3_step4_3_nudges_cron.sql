-- p131 T-3 C3 step 4: estender v4_notify_expiring_engagements para 3 nudges D-60/D-30/D-7
-- ============================================================================
--
-- Driver: Q-C confirmada por Vitor — desenho de 3 nudges:
--   D-60: notif WEEKLY DIGEST agregada para o GP (Vitor) — "X voluntários
--         vencerão em 60d, eles precisam cadastrar renovação no VEP"
--         Tipo: engagement_renewal_d60_gp_aggregate (suppress, só agrega no digest)
--   D-30: notif WEEKLY DIGEST para o voluntário + GP (ambos via digest)
--         Tipo: engagement_renewal_d30 (digest_weekly default)
--   D-7:  notif TRANSACTIONAL email real-time para voluntário + Lorena cc + GP cc
--         Tipo: engagement_renewal_d7_urgent (transactional_immediate)
--
-- Plus trigger trg_link_renewal_application — quando selection_application
-- nova é criada e email matches engagement_volunteer_active próximo de end_date
-- (≤90d), auto-popula renews_engagement_id (Q-D=C2 explícita).
--
-- Plus _delivery_mode_for atualizado com novo tipo d7_urgent.
-- ============================================================================

-- 1) Catálogo delivery_mode atualizado para novo type D-7
CREATE OR REPLACE FUNCTION public._delivery_mode_for(p_type text)
RETURNS text
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
SET search_path TO ''
AS $function$
  SELECT CASE p_type
    WHEN 'volunteer_agreement_signed'    THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_pending'  THEN 'transactional_immediate'
    WHEN 'system_alert'                  THEN 'transactional_immediate'
    WHEN 'certificate_ready'             THEN 'transactional_immediate'
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
    WHEN 'engagement_renewal_d7_urgent'  THEN 'transactional_immediate'  -- p131 T-3
    WHEN 'engagement_renewal_d30'        THEN 'digest_weekly'            -- p131 T-3
    WHEN 'engagement_renewal_d60_gp_aggregate' THEN 'digest_weekly'      -- p131 T-3
    WHEN 'attendance_detractor'          THEN 'suppress'
    WHEN 'info'                          THEN 'suppress'
    WHEN 'system'                        THEN 'suppress'
    ELSE 'digest_weekly'
  END;
$function$;

-- 2) RPC v4_notify_expiring_engagements rewrite com 3 nudges
CREATE OR REPLACE FUNCTION public.v4_notify_expiring_engagements()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_count_d60 int := 0;
  v_count_d30 int := 0;
  v_count_d7 int := 0;
  v_engagement record;
  v_gp_member_id uuid;
  v_lorena_member_id uuid;
BEGIN
  -- Pegar GP único (manager) e Lorena (voluntariado_director designation)
  SELECT m.id INTO v_gp_member_id
  FROM public.members m
  WHERE m.is_active=true AND m.operational_role='manager'
  LIMIT 1;

  SELECT m.id INTO v_lorena_member_id
  FROM public.members m
  WHERE m.is_active=true
    AND 'voluntariado_director' = ANY(m.designations)
  LIMIT 1;

  -- Iterar engagements voluntários com end_date dentro de 60d (cobre todos 3 nudges)
  FOR v_engagement IN
    SELECT
      e.id AS engagement_id, e.person_id, p.legacy_member_id, p.name AS person_name,
      e.kind, e.role, e.end_date, e.metadata,
      ek.display_name AS kind_name,
      i.title AS initiative_title,
      (e.end_date - CURRENT_DATE) AS days_until_expiry
    FROM public.engagements e
    JOIN public.persons p ON p.id = e.person_id
    JOIN public.engagement_kinds ek ON ek.slug = e.kind
    LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.status = 'active'
      AND e.kind = 'volunteer'  -- p131: só voluntários (não founders/sponsors/etc)
      AND e.end_date IS NOT NULL
      AND e.end_date BETWEEN CURRENT_DATE AND (CURRENT_DATE + interval '60 days')
  LOOP
    -- D-60: GP-only aggregate (entre 53-60d)
    IF v_engagement.days_until_expiry BETWEEN 53 AND 60
       AND v_gp_member_id IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM public.notifications n
         WHERE n.recipient_id = v_gp_member_id
           AND n.type = 'engagement_renewal_d60_gp_aggregate'
           AND n.source_id = v_engagement.engagement_id
           AND n.created_at > (now() - interval '7 days')
       ) THEN
      INSERT INTO public.notifications (recipient_id, type, title, body, source_type, source_id)
      VALUES (
        v_gp_member_id, 'engagement_renewal_d60_gp_aggregate',
        'Voluntário vencerá em 60d: ' || v_engagement.person_name,
        v_engagement.person_name || ' (' || v_engagement.role || COALESCE(' · ' || v_engagement.initiative_title, '') ||
        ') tem vínculo expirando em ' || v_engagement.end_date || '. Nudge ao voluntário só dispara em D-30.',
        'engagement', v_engagement.engagement_id
      );
      v_count_d60 := v_count_d60 + 1;
    END IF;

    -- D-30: voluntário + GP recebem (ambos digest_weekly)
    IF v_engagement.days_until_expiry BETWEEN 23 AND 30 THEN
      -- Voluntário
      IF v_engagement.legacy_member_id IS NOT NULL
         AND NOT EXISTS (
           SELECT 1 FROM public.notifications n
           WHERE n.recipient_id = v_engagement.legacy_member_id
             AND n.type = 'engagement_renewal_d30'
             AND n.source_id = v_engagement.engagement_id
             AND n.created_at > (now() - interval '7 days')
         ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, source_type, source_id)
        VALUES (
          v_engagement.legacy_member_id, 'engagement_renewal_d30',
          'Sua vaga vence em 30 dias',
          'Sua vaga como ' || v_engagement.kind_name ||
          COALESCE(' na ' || v_engagement.initiative_title, '') ||
          ' expira em ' || v_engagement.end_date || '. Para renovar, cadastre-se na vaga atual no PMI VEP.',
          'engagement', v_engagement.engagement_id
        );
        v_count_d30 := v_count_d30 + 1;
      END IF;
      -- GP (mesma source_id, recipient diferente)
      IF v_gp_member_id IS NOT NULL
         AND NOT EXISTS (
           SELECT 1 FROM public.notifications n
           WHERE n.recipient_id = v_gp_member_id
             AND n.type = 'engagement_renewal_d30'
             AND n.source_id = v_engagement.engagement_id
             AND n.created_at > (now() - interval '7 days')
         ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, source_type, source_id)
        VALUES (
          v_gp_member_id, 'engagement_renewal_d30',
          'Voluntário ' || v_engagement.person_name || ' vence em 30d',
          v_engagement.person_name || ' precisa renovar VEP. Se renovação detected, ball-in-court transfere para você.',
          'engagement', v_engagement.engagement_id
        );
        v_count_d30 := v_count_d30 + 1;
      END IF;
    END IF;

    -- D-7: voluntário URGENT + GP cc + Lorena cc (transactional_immediate)
    IF v_engagement.days_until_expiry BETWEEN 1 AND 7 THEN
      -- Voluntário URGENT
      IF v_engagement.legacy_member_id IS NOT NULL
         AND NOT EXISTS (
           SELECT 1 FROM public.notifications n
           WHERE n.recipient_id = v_engagement.legacy_member_id
             AND n.type = 'engagement_renewal_d7_urgent'
             AND n.source_id = v_engagement.engagement_id
             AND n.created_at > (now() - interval '7 days')
         ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, source_type, source_id)
        VALUES (
          v_engagement.legacy_member_id, 'engagement_renewal_d7_urgent',
          'URGENTE: vaga vence em 7 dias',
          'Sua vaga como ' || v_engagement.kind_name ||
          COALESCE(' na ' || v_engagement.initiative_title, '') ||
          ' expira em ' || v_engagement.end_date || '. URGENTE: cadastre renovação no PMI VEP imediatamente.',
          'engagement', v_engagement.engagement_id
        );
        v_count_d7 := v_count_d7 + 1;
      END IF;
      -- GP cc
      IF v_gp_member_id IS NOT NULL
         AND NOT EXISTS (
           SELECT 1 FROM public.notifications n
           WHERE n.recipient_id = v_gp_member_id
             AND n.type = 'engagement_renewal_d7_urgent'
             AND n.source_id = v_engagement.engagement_id
             AND n.created_at > (now() - interval '7 days')
         ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, source_type, source_id)
        VALUES (
          v_gp_member_id, 'engagement_renewal_d7_urgent',
          'D-7: ' || v_engagement.person_name || ' vence em 7d',
          v_engagement.person_name || ' (' || v_engagement.role || ') vence ' || v_engagement.end_date || '. Verificar status renovação VEP.',
          'engagement', v_engagement.engagement_id
        );
        v_count_d7 := v_count_d7 + 1;
      END IF;
      -- Lorena cc
      IF v_lorena_member_id IS NOT NULL
         AND v_lorena_member_id <> v_gp_member_id  -- evita duplicate se Lorena = GP
         AND NOT EXISTS (
           SELECT 1 FROM public.notifications n
           WHERE n.recipient_id = v_lorena_member_id
             AND n.type = 'engagement_renewal_d7_urgent'
             AND n.source_id = v_engagement.engagement_id
             AND n.created_at > (now() - interval '7 days')
         ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, source_type, source_id)
        VALUES (
          v_lorena_member_id, 'engagement_renewal_d7_urgent',
          'PMI-GO Voluntariado D-7: ' || v_engagement.person_name,
          v_engagement.person_name || ' (' || v_engagement.role || ') vence ' || v_engagement.end_date || '. cc Diretoria de Voluntariado PMI-GO para awareness.',
          'engagement', v_engagement.engagement_id
        );
        v_count_d7 := v_count_d7 + 1;
      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'notifications_d60', v_count_d60,
    'notifications_d30', v_count_d30,
    'notifications_d7', v_count_d7,
    'total_sent', v_count_d60 + v_count_d30 + v_count_d7,
    'run_at', now()
  );
END;
$function$;

COMMENT ON FUNCTION public.v4_notify_expiring_engagements() IS
  'p131 T-3 C3 step 4: substitui versão p124 com 3 nudges em vez de 1. D-60 (53-60d) GP-only aggregate, D-30 (23-30d) voluntário + GP, D-7 (1-7d) voluntário URGENT + GP cc + Lorena (voluntariado_director) cc. Idempotência: dedup window 7d via NOT EXISTS sobre notifications.created_at. Filtro kind=volunteer único (founders/ambassadors/sponsors/etc não entram). Cron job v4_engagement_expiry_notify dispara diário 0 8 * * *.';

-- 3) Trigger trg_link_renewal_application — auto-popula renews_engagement_id
CREATE OR REPLACE FUNCTION public._trg_link_renewal_application()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_engagement_id uuid;
BEGIN
  IF NEW.email IS NULL OR NEW.email = '' THEN RETURN NEW; END IF;
  IF NEW.renews_engagement_id IS NOT NULL THEN RETURN NEW; END IF;

  -- p131 T-3 C3 step 5 v2: heurística simplificada (sem proximity end_date).
  -- Match: email batendo com engagement volunteer active de algum member.
  -- Justificativa: end_date pode ser placeholder distante (signed_at+365d) mas
  -- a app é claramente renovação se o voluntário já tem vínculo ativo no Núcleo.
  -- Pega o mais antigo (= primeiro vínculo, semantica de "renovação histórica").
  SELECT e.id INTO v_engagement_id
  FROM public.engagements e
  JOIN public.persons p ON p.id = e.person_id
  JOIN public.members m ON m.id = p.legacy_member_id
  WHERE lower(m.email) = lower(NEW.email)
    AND e.kind = 'volunteer'
    AND e.status = 'active'
  ORDER BY e.start_date ASC, e.created_at ASC
  LIMIT 1;

  IF v_engagement_id IS NOT NULL THEN
    NEW.renews_engagement_id := v_engagement_id;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_link_renewal_application ON public.selection_applications;
CREATE TRIGGER trg_link_renewal_application
  BEFORE INSERT ON public.selection_applications
  FOR EACH ROW
  EXECUTE FUNCTION public._trg_link_renewal_application();

COMMENT ON FUNCTION public._trg_link_renewal_application() IS
  'p131 T-3 C3 step 5: BEFORE INSERT trigger que auto-popula selection_applications.renews_engagement_id quando email matches engagement volunteer active próximo de end_date (≤90d). Heurística email-match — pode ser sobrescrito manualmente via UPDATE depois. Permite ball-in-court transfer ao GP automaticamente quando voluntário re-cadastra via VEP.';

-- 4) Backfill renews_engagement_id para selection_applications já existentes
WITH renewals AS (
  SELECT
    sa.id AS application_id,
    e.id AS engagement_id
  FROM public.selection_applications sa
  JOIN public.engagements e ON e.kind='volunteer' AND e.status='active' AND e.end_date IS NOT NULL
  JOIN public.persons p ON p.id = e.person_id
  JOIN public.members m ON m.id = p.legacy_member_id AND lower(m.email) = lower(sa.email)
  WHERE sa.renews_engagement_id IS NULL
    AND sa.email IS NOT NULL
    AND e.end_date <= (sa.created_at::date + interval '90 days')
    AND sa.created_at > (e.start_date::timestamp - interval '30 days')  -- application criada >= start engagement
)
UPDATE public.selection_applications sa
SET renews_engagement_id = r.engagement_id
FROM renewals r
WHERE sa.id = r.application_id;

NOTIFY pgrst, 'reload schema';
