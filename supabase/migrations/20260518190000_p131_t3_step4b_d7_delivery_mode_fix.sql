-- p131 T-3 C3 step 4b: fix D-7 delivery_mode
-- ============================================================================
-- Hotfix v4_notify_expiring_engagements: adiciona delivery_mode explícito
-- via _delivery_mode_for() em todos INSERTs. Default da coluna era
-- 'digest_weekly' — D-7 que precisa 'transactional_immediate' ficaria errado
-- sem este fix.
-- ============================================================================

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
  SELECT m.id INTO v_gp_member_id
  FROM public.members m
  WHERE m.is_active=true AND m.operational_role='manager'
  LIMIT 1;

  SELECT m.id INTO v_lorena_member_id
  FROM public.members m
  WHERE m.is_active=true
    AND 'voluntariado_director' = ANY(m.designations)
  LIMIT 1;

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
      AND e.kind = 'volunteer'
      AND e.end_date IS NOT NULL
      AND e.end_date BETWEEN CURRENT_DATE AND (CURRENT_DATE + interval '60 days')
  LOOP
    IF v_engagement.days_until_expiry BETWEEN 53 AND 60
       AND v_gp_member_id IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM public.notifications n
         WHERE n.recipient_id = v_gp_member_id
           AND n.type = 'engagement_renewal_d60_gp_aggregate'
           AND n.source_id = v_engagement.engagement_id
           AND n.created_at > (now() - interval '7 days')
       ) THEN
      INSERT INTO public.notifications (recipient_id, type, title, body, source_type, source_id, delivery_mode)
      VALUES (
        v_gp_member_id, 'engagement_renewal_d60_gp_aggregate',
        'Voluntário vencerá em 60d: ' || v_engagement.person_name,
        v_engagement.person_name || ' (' || v_engagement.role || COALESCE(' · ' || v_engagement.initiative_title, '') ||
        ') tem vínculo expirando em ' || v_engagement.end_date || '. Nudge ao voluntário só dispara em D-30.',
        'engagement', v_engagement.engagement_id,
        public._delivery_mode_for('engagement_renewal_d60_gp_aggregate')
      );
      v_count_d60 := v_count_d60 + 1;
    END IF;

    IF v_engagement.days_until_expiry BETWEEN 23 AND 30 THEN
      IF v_engagement.legacy_member_id IS NOT NULL
         AND NOT EXISTS (
           SELECT 1 FROM public.notifications n
           WHERE n.recipient_id = v_engagement.legacy_member_id
             AND n.type = 'engagement_renewal_d30'
             AND n.source_id = v_engagement.engagement_id
             AND n.created_at > (now() - interval '7 days')
         ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, source_type, source_id, delivery_mode)
        VALUES (
          v_engagement.legacy_member_id, 'engagement_renewal_d30',
          'Sua vaga vence em 30 dias',
          'Sua vaga como ' || v_engagement.kind_name ||
          COALESCE(' na ' || v_engagement.initiative_title, '') ||
          ' expira em ' || v_engagement.end_date || '. Para renovar, cadastre-se na vaga atual no PMI VEP.',
          'engagement', v_engagement.engagement_id,
          public._delivery_mode_for('engagement_renewal_d30')
        );
        v_count_d30 := v_count_d30 + 1;
      END IF;
      IF v_gp_member_id IS NOT NULL
         AND NOT EXISTS (
           SELECT 1 FROM public.notifications n
           WHERE n.recipient_id = v_gp_member_id
             AND n.type = 'engagement_renewal_d30'
             AND n.source_id = v_engagement.engagement_id
             AND n.created_at > (now() - interval '7 days')
         ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, source_type, source_id, delivery_mode)
        VALUES (
          v_gp_member_id, 'engagement_renewal_d30',
          'Voluntário ' || v_engagement.person_name || ' vence em 30d',
          v_engagement.person_name || ' precisa renovar VEP. Se renovação detected, ball-in-court transfere para você.',
          'engagement', v_engagement.engagement_id,
          public._delivery_mode_for('engagement_renewal_d30')
        );
        v_count_d30 := v_count_d30 + 1;
      END IF;
    END IF;

    IF v_engagement.days_until_expiry BETWEEN 1 AND 7 THEN
      IF v_engagement.legacy_member_id IS NOT NULL
         AND NOT EXISTS (
           SELECT 1 FROM public.notifications n
           WHERE n.recipient_id = v_engagement.legacy_member_id
             AND n.type = 'engagement_renewal_d7_urgent'
             AND n.source_id = v_engagement.engagement_id
             AND n.created_at > (now() - interval '7 days')
         ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, source_type, source_id, delivery_mode)
        VALUES (
          v_engagement.legacy_member_id, 'engagement_renewal_d7_urgent',
          'URGENTE: vaga vence em 7 dias',
          'Sua vaga como ' || v_engagement.kind_name ||
          COALESCE(' na ' || v_engagement.initiative_title, '') ||
          ' expira em ' || v_engagement.end_date || '. URGENTE: cadastre renovação no PMI VEP imediatamente.',
          'engagement', v_engagement.engagement_id,
          public._delivery_mode_for('engagement_renewal_d7_urgent')
        );
        v_count_d7 := v_count_d7 + 1;
      END IF;
      IF v_gp_member_id IS NOT NULL
         AND NOT EXISTS (
           SELECT 1 FROM public.notifications n
           WHERE n.recipient_id = v_gp_member_id
             AND n.type = 'engagement_renewal_d7_urgent'
             AND n.source_id = v_engagement.engagement_id
             AND n.created_at > (now() - interval '7 days')
         ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, source_type, source_id, delivery_mode)
        VALUES (
          v_gp_member_id, 'engagement_renewal_d7_urgent',
          'D-7: ' || v_engagement.person_name || ' vence em 7d',
          v_engagement.person_name || ' (' || v_engagement.role || ') vence ' || v_engagement.end_date || '. Verificar status renovação VEP.',
          'engagement', v_engagement.engagement_id,
          public._delivery_mode_for('engagement_renewal_d7_urgent')
        );
        v_count_d7 := v_count_d7 + 1;
      END IF;
      IF v_lorena_member_id IS NOT NULL
         AND v_lorena_member_id <> v_gp_member_id
         AND NOT EXISTS (
           SELECT 1 FROM public.notifications n
           WHERE n.recipient_id = v_lorena_member_id
             AND n.type = 'engagement_renewal_d7_urgent'
             AND n.source_id = v_engagement.engagement_id
             AND n.created_at > (now() - interval '7 days')
         ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, source_type, source_id, delivery_mode)
        VALUES (
          v_lorena_member_id, 'engagement_renewal_d7_urgent',
          'PMI-GO Voluntariado D-7: ' || v_engagement.person_name,
          v_engagement.person_name || ' (' || v_engagement.role || ') vence ' || v_engagement.end_date || '. cc Diretoria de Voluntariado PMI-GO para awareness.',
          'engagement', v_engagement.engagement_id,
          public._delivery_mode_for('engagement_renewal_d7_urgent')
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

NOTIFY pgrst, 'reload schema';
