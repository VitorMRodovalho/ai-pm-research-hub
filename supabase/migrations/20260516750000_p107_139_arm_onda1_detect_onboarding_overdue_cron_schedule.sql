-- ARM Onda 1 #139: agendar cron detect_onboarding_overdue
--
-- Estado pré:
--   - Função detect_onboarding_overdue() existe, SECDEF, mas usa auth.uid() + can_by_member
--     ('manage_platform') — falha em contexto cron (sem JWT)
--   - Nenhum cron agendado → SLA invisível operacionalmente
--
-- Mudanças:
--   1) Refatorar detect_onboarding_overdue com cron-context bypass (pattern ADR-0028
--      p89, mesmo de process_pending_reschedule_nudges): se chamado sem JWT (cron),
--      bypassa auth check; chamadas humanas via MCP/admin continuam exigindo manage_platform
--   2) cron.schedule 'detect-onboarding-overdue-daily' às 13 UTC (10 BRT) — antes do
--      digest (14 UTC = 11 BRT) para que admin veja overdue marcados quando rever digest
--
-- Rollback:
--   SELECT cron.unschedule('detect-onboarding-overdue-daily');
--   CREATE OR REPLACE FUNCTION public.detect_onboarding_overdue() ... (versão original com auth strict)

-- 1) Refatorar a função
CREATE OR REPLACE FUNCTION public.detect_onboarding_overdue()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $func$
DECLARE
  v_caller_id uuid;
  v_overdue record;
  v_notified int := 0;
  v_updated int := 0;
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
      sa.chapter
    FROM public.onboarding_progress op
    JOIN public.selection_applications sa ON sa.id = op.application_id
    WHERE op.status IN ('pending', 'in_progress')
      AND op.sla_deadline < now()
  LOOP
    UPDATE public.onboarding_progress
    SET status = 'overdue'
    WHERE id = v_overdue.progress_id AND status != 'overdue';

    IF FOUND THEN
      v_updated := v_updated + 1;
    END IF;

    IF v_overdue.member_id IS NOT NULL THEN
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
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'steps_marked_overdue', v_updated,
    'notifications_sent', v_notified,
    'context', CASE WHEN auth.uid() IS NULL THEN 'cron' ELSE 'admin' END
  );
END;
$func$;

-- 2) Schedule cron
SELECT cron.unschedule('detect-onboarding-overdue-daily')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'detect-onboarding-overdue-daily');

SELECT cron.schedule(
  'detect-onboarding-overdue-daily',
  '0 13 * * *',
  $$SELECT public.detect_onboarding_overdue()$$
);

NOTIFY pgrst, 'reload schema';
