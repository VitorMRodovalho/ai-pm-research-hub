/**
 * Self-healing scheduler logic.
 *
 * Cron roda diariamente (Cloudflare-side) mas o worker decide se executa baseado em:
 *  - Houve run com sucesso? (consulta v_cron_last_success)
 *  - Quantas horas desde o último?
 *  - Está dentro da cadência normal (~72h) ou em atraso?
 *
 * Filosofia: não pular janela. Se 3 dias passaram sem sucesso, força run.
 */

import type { SupabaseClient } from '@supabase/supabase-js';
import type { Env, SchedulerDecision } from './types';

export async function decideRun(
  db: SupabaseClient,
  env: Env,
  workerName: string
): Promise<SchedulerDecision> {
  const cadence = parseFloat(env.CRON_CADENCE_HOURS);
  const tolerance = parseFloat(env.CRON_TOLERANCE_HOURS);

  const { data: lastSuccess, error } = await db
    .from('v_cron_last_success')
    .select('completed_at, scheduled_for')
    .eq('worker_name', workerName)
    .maybeSingle();

  if (error) {
    console.error('decideRun: query failed, defaulting to run:', error.message);
    return { run: true, reason: 'fallback_on_query_error', hours_since_last_success: null };
  }

  if (!lastSuccess) {
    return { run: true, reason: 'first_run', hours_since_last_success: null };
  }

  const hoursSince = (Date.now() - new Date(lastSuccess.completed_at).getTime()) / 3_600_000;

  if (hoursSince >= cadence + tolerance) {
    return {
      run: true,
      reason: `overdue_${hoursSince.toFixed(1)}h_since_last_success`,
      hours_since_last_success: hoursSince
    };
  }

  if (hoursSince >= cadence) {
    return {
      run: true,
      reason: 'normal_window',
      hours_since_last_success: hoursSince
    };
  }

  return {
    run: false,
    reason: `last_success_${hoursSince.toFixed(1)}h_ago_next_in_${(cadence - hoursSince).toFixed(1)}h`,
    hours_since_last_success: hoursSince
  };
}

/**
 * Verifica se deve disparar alerta de falhas consecutivas.
 */
export async function checkConsecutiveFailures(
  db: SupabaseClient,
  workerName: string,
  threshold: number
): Promise<number> {
  const { data, error } = await db
    .from('cron_run_log')
    .select('status, started_at')
    .eq('worker_name', workerName)
    .in('status', ['success', 'failed'])
    .order('started_at', { ascending: false })
    .limit(threshold);

  if (error || !data) return 0;

  const allFailed = data.length >= threshold && data.every(r => r.status === 'failed');
  return allFailed ? data.length : 0;
}

/**
 * Disparar email de alerta para o GP via campaign_send_one_off.
 *
 * Wrapper RPC criado em migration 20260516200000 B3 — looks up template
 * by slug and delegates to admin_send_campaign with external_contacts.
 *
 * PRE-DEPLOY: PM precisa seedar campaign_templates com slug =
 * 'cron_failure_alert' antes do worker entrar em produção.
 */
export async function alertConsecutiveFailures(
  db: SupabaseClient,
  env: Env,
  workerName: string,
  failureCount: number
): Promise<void> {
  console.error(JSON.stringify({
    severity: 'CRITICAL',
    alert: 'cron_consecutive_failures',
    worker: workerName,
    failure_count: failureCount,
    notify_email: env.GP_NOTIFICATION_EMAIL
  }));

  try {
    const { error } = await db.rpc('campaign_send_one_off', {
      p_template_slug: 'cron_failure_alert',
      p_to_email: env.GP_NOTIFICATION_EMAIL,
      p_variables: { worker: workerName, failure_count: failureCount },
      p_metadata: { source: 'pmi-vep-sync', alert_type: 'consecutive_failures' }
    });
    if (error) {
      console.error('alertConsecutiveFailures: campaign_send_one_off failed:', error.message);
    }
  } catch (e: any) {
    console.error('alertConsecutiveFailures: exception during dispatch:', e?.message ?? e);
  }
}
