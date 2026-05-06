-- ARM-1 auto-promote cron (p108 cont.): polish ADR-0072 Lead Capture Funnel.
--
-- Pré-fix: leads em status='new' precisavam admin clicar manualmente promote_lead_to_application.
-- Pós: cron daily 09 UTC promove leads com auto_promote_eligible=true para ciclos open.
--
-- Schema:
--   visitor_leads.auto_promote_eligible boolean DEFAULT true (opt-out, não opt-in — captura
--     LGPD consent já cobre escopo "comunicações sobre voluntariado")
--   selection_cycles.leads_auto_promoted_at timestamptz (idempotency: cron só processa cada
--     ciclo uma vez por janela de auto-promote)
--
-- Cron: daily 09 UTC. Processa ciclos com status='open' AND leads_auto_promoted_at IS NULL.
-- Para cada ciclo: itera leads em status='new' AND auto_promote_eligible=true, promove via
-- INSERT em selection_applications + UPDATE lead status='promoted' (mesma lógica do RPC manual
-- mas com promoted_via='cron' tracking). Marca cycle.leads_auto_promoted_at = now() ao final.
--
-- LGPD note: lead.lgpd_consent (capture-time) é prerequisito para insert. auto_promote_eligible
-- é opt-out adicional caso lead queira só receber news mas não ser promovido. Future UI pode
-- expor checkbox "Sim, quero ser convidado para próximo ciclo" — defer até primeira coorte.
--
-- Rollback:
--   ALTER TABLE visitor_leads DROP COLUMN auto_promote_eligible;
--   ALTER TABLE selection_cycles DROP COLUMN leads_auto_promoted_at;
--   DROP FUNCTION auto_promote_eligible_leads_for_cycle(uuid);
--   DROP FUNCTION auto_promote_eligible_leads_daily();
--   SELECT cron.unschedule('auto-promote-eligible-leads-daily');

-- 1. Schema additions
ALTER TABLE public.visitor_leads
  ADD COLUMN IF NOT EXISTS auto_promote_eligible boolean DEFAULT true;

ALTER TABLE public.selection_cycles
  ADD COLUMN IF NOT EXISTS leads_auto_promoted_at timestamptz;

COMMENT ON COLUMN public.visitor_leads.auto_promote_eligible IS
  'p108 ARM-1 cron: opt-out flag para auto-promoção quando ciclo abre. Default true. UI checkbox futuro pode permitir lead optar por só newsletter sem promoção.';
COMMENT ON COLUMN public.selection_cycles.leads_auto_promoted_at IS
  'p108 ARM-1 cron: timestamp da auto-promoção. NULL = ainda não processado. Idempotency flag para auto_promote_eligible_leads_daily() não reprocessar.';

-- 2. Per-cycle helper (extracts existing promote_lead_to_application logic, callable from cron)
CREATE OR REPLACE FUNCTION public.auto_promote_eligible_leads_for_cycle(p_cycle_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $func$
DECLARE
  v_cycle record;
  v_lead record;
  v_app_id uuid;
  v_first text;
  v_last text;
  v_count integer := 0;
  v_skipped integer := 0;
  v_dedup_skipped integer := 0;
  v_caller_id uuid;
  v_cron_context boolean;
BEGIN
  v_cron_context := (current_setting('role', true) IN ('service_role','postgres')
                     OR current_user IN ('postgres','supabase_admin'));

  IF NOT v_cron_context THEN
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL THEN
      RAISE EXCEPTION 'Unauthorized: not authenticated';
    END IF;
    IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
      RAISE EXCEPTION 'Unauthorized: requires manage_member';
    END IF;
  END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = p_cycle_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Cycle not found');
  END IF;
  IF v_cycle.status <> 'open' THEN
    RETURN jsonb_build_object('error', 'Cycle is not open: ' || v_cycle.status);
  END IF;

  FOR v_lead IN
    SELECT vl.*
    FROM public.visitor_leads vl
    WHERE vl.status = 'new'
      AND vl.auto_promote_eligible = true
      AND vl.lgpd_consent = true
      AND NOT EXISTS (
        SELECT 1 FROM public.selection_applications sa
        WHERE sa.cycle_id = p_cycle_id
          AND LOWER(TRIM(sa.email)) = vl.dedupe_email_normalized
      )
    ORDER BY vl.created_at ASC
  LOOP
    BEGIN
      v_first := SPLIT_PART(v_lead.name, ' ', 1);
      v_last := NULLIF(TRIM(SUBSTRING(v_lead.name FROM POSITION(' ' IN v_lead.name) + 1)), '');

      INSERT INTO public.selection_applications (
        cycle_id, applicant_name, first_name, last_name, email, phone, chapter,
        referral_source, referrer_member_id, utm_data, status, created_at, application_date
      ) VALUES (
        p_cycle_id, v_lead.name, v_first, v_last, v_lead.email, v_lead.phone,
        v_lead.chapter_interest,
        COALESCE(v_lead.source, 'lead_promote_cron'),
        v_lead.referrer_member_id,
        v_lead.utm_data,
        'submitted', now(), CURRENT_DATE
      )
      RETURNING id INTO v_app_id;

      UPDATE public.visitor_leads SET
        status = 'promoted', promoted_at = now(), promoted_by = NULL,
        promoted_to_application_id = v_app_id
      WHERE id = v_lead.id;

      INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
      VALUES (
        v_caller_id, 'visitor_lead.auto_promoted', 'visitor_lead', v_lead.id,
        jsonb_build_object('application_id', v_app_id, 'cycle_id', p_cycle_id, 'via', 'cron'),
        jsonb_strip_nulls(jsonb_build_object('lead_email', v_lead.email))
      );

      v_count := v_count + 1;
    EXCEPTION
      WHEN unique_violation THEN
        v_dedup_skipped := v_dedup_skipped + 1;
      WHEN OTHERS THEN
        v_skipped := v_skipped + 1;
        INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
        VALUES (
          v_caller_id, 'visitor_lead.auto_promote_failed', 'visitor_lead', v_lead.id,
          jsonb_build_object('error', SQLERRM),
          jsonb_build_object('lead_email', v_lead.email, 'cycle_id', p_cycle_id)
        );
    END;
  END LOOP;

  UPDATE public.selection_cycles SET leads_auto_promoted_at = now() WHERE id = p_cycle_id;

  RETURN jsonb_build_object(
    'cycle_id', p_cycle_id,
    'cycle_code', v_cycle.cycle_code,
    'promoted', v_count,
    'dedup_skipped', v_dedup_skipped,
    'errors', v_skipped,
    'completed_at', now()
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.auto_promote_eligible_leads_for_cycle(uuid) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.auto_promote_eligible_leads_for_cycle(uuid) TO authenticated;

COMMENT ON FUNCTION public.auto_promote_eligible_leads_for_cycle(uuid) IS
  'p108 ARM-1 cron helper: promove leads em status=new + auto_promote_eligible=true para selection_applications no ciclo. Idempotente via dedup email vs existing apps. Auth: cron-context (service_role/postgres) OR manage_member.';

-- 3. Cron handler — itera ciclos abertos não processados
CREATE OR REPLACE FUNCTION public.auto_promote_eligible_leads_daily()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $func$
DECLARE
  v_cycle record;
  v_result jsonb;
  v_results jsonb := '[]'::jsonb;
  v_total_promoted integer := 0;
  v_total_cycles integer := 0;
  v_cron_context boolean;
BEGIN
  v_cron_context := (current_setting('role', true) IN ('service_role','postgres')
                     OR current_user IN ('postgres','supabase_admin'));

  IF NOT v_cron_context THEN
    RAISE EXCEPTION 'Unauthorized: cron-only (called by pg_cron)';
  END IF;

  FOR v_cycle IN
    SELECT id, cycle_code FROM public.selection_cycles
    WHERE status = 'open' AND leads_auto_promoted_at IS NULL
    ORDER BY open_date ASC NULLS LAST
  LOOP
    v_result := public.auto_promote_eligible_leads_for_cycle(v_cycle.id);
    v_results := v_results || jsonb_build_array(v_result);
    v_total_cycles := v_total_cycles + 1;
    v_total_promoted := v_total_promoted + COALESCE((v_result->>'promoted')::int, 0);
  END LOOP;

  RETURN jsonb_build_object(
    'cycles_processed', v_total_cycles,
    'total_promoted', v_total_promoted,
    'per_cycle', v_results,
    'ran_at', now()
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.auto_promote_eligible_leads_daily() FROM public, anon, authenticated;

COMMENT ON FUNCTION public.auto_promote_eligible_leads_daily() IS
  'p108 ARM-1 cron: daily 09 UTC. Itera selection_cycles status=open + leads_auto_promoted_at IS NULL, processa via auto_promote_eligible_leads_for_cycle. Idempotente — só roda uma vez por ciclo aberto.';

-- 4. Schedule cron (idempotent — pg_cron ON CONFLICT no jobname)
SELECT cron.schedule(
  'auto-promote-eligible-leads-daily',
  '0 9 * * *',
  'SELECT public.auto_promote_eligible_leads_daily();'
);

NOTIFY pgrst, 'reload schema';
