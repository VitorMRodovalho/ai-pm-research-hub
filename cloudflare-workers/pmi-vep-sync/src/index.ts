/**
 * pmi-vep-sync — main entry point.
 *
 * Triggered by Cloudflare Cron (daily 04:00 UTC). Self-healing logic decides
 * if it actually executes (cadence 72h, tolerance 12h). On failure, retries
 * are intrinsic — next daily trigger checks if catch-up is needed.
 *
 * Pipeline:
 *   1. shouldRun() — consulta v_cron_last_success
 *   2. log_cron_run_start RPC → run_id
 *   3. getOpenSelectionCycle()
 *   4. getActiveOpportunities()
 *   5. Para cada opportunity:
 *      - listAllApplicationsForOpp() (3 buckets PMI)
 *      - Para cada application:
 *        - getApplicationDetail()
 *        - mapPmiToNucleo()
 *        - upsertSelectionApplication() (compound key per B2)
 *        - Se nova:
 *          - issueOnboardingToken(scopes: profile_completion + video_screening + consent_giving)
 *          - dispatchWelcome() via campaign_send_one_off (per B3)
 *   6. log_cron_run_complete RPC
 *   7. checkConsecutiveFailures() → alertConsecutiveFailures() se >= 3
 */

import type { Env, CronRunMetrics } from './types';
import {
  createDbClient,
  logRunStart,
  logRunComplete,
  getOpenSelectionCycle,
  getActiveOpportunities,
  upsertSelectionApplication
} from './db';
import {
  decideRun,
  checkConsecutiveFailures,
  alertConsecutiveFailures
} from './scheduler';
import {
  listAllApplicationsForOpp,
  getApplicationDetail
} from './pmi-vep-client';
import { mapPmiToNucleo } from './mapper';
import { issueOnboardingToken } from './onboarding-token';
import { dispatchWelcome } from './welcome';

const WORKER_NAME = 'pmi-vep-sync';

export default {
  async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
    const db = createDbClient(env);

    const decision = await decideRun(db, env, WORKER_NAME);
    if (!decision.run) {
      console.log(`[${WORKER_NAME}] skipping: ${decision.reason}`);
      return;
    }
    console.log(`[${WORKER_NAME}] running: ${decision.reason}`);

    let runId: string;
    try {
      runId = await logRunStart(db, WORKER_NAME, new Date(event.scheduledTime), decision.reason);
    } catch (e: any) {
      console.error(`[${WORKER_NAME}] logRunStart failed:`, e.message);
      return;
    }

    const metrics: CronRunMetrics = {
      trigger_reason: decision.reason,
      opportunities_processed: 0,
      applications_new: 0,
      applications_updated: 0,
      applications_skipped_not_partner: 0,
      welcome_messages_dispatched: 0,
      drafts_dispatched: 0,
      errors: []
    };

    try {
      const cycle = await getOpenSelectionCycle(db);
      if (!cycle) {
        await logRunComplete(db, runId, 'skipped', metrics, [{ scope: 'cycle', error: 'no open selection cycle' }]);
        return;
      }
      console.log(`[${WORKER_NAME}] open cycle: ${cycle.cycle_code} (${cycle.id})`);

      const opps = await getActiveOpportunities(db);
      console.log(`[${WORKER_NAME}] ${opps.length} active opportunities`);

      for (const opp of opps) {
        try {
          await processOpportunity(opp, cycle.id, db, env, metrics);
          metrics.opportunities_processed++;
        } catch (e: any) {
          metrics.errors.push({
            scope: 'opportunity',
            ref: opp.opportunity_id,
            error: e.message
          });
          console.error(`[${WORKER_NAME}] opp ${opp.opportunity_id} failed:`, e);
        }
      }

      const finalStatus = metrics.errors.length > 0 ? 'failed' : 'success';
      await logRunComplete(db, runId, finalStatus, metrics, metrics.errors);
      console.log(`[${WORKER_NAME}] done: ${finalStatus}`, metrics);

      if (finalStatus === 'failed') {
        const threshold = parseInt(env.CONSECUTIVE_FAILURE_ALERT_THRESHOLD, 10);
        const consecutive = await checkConsecutiveFailures(db, WORKER_NAME, threshold);
        if (consecutive >= threshold) {
          ctx.waitUntil(alertConsecutiveFailures(db, env, WORKER_NAME, consecutive));
        }
      }

    } catch (e: any) {
      console.error(`[${WORKER_NAME}] FATAL:`, e);
      await logRunComplete(db, runId, 'failed', metrics, [
        { scope: 'fatal', error: e.message, stack: e.stack }
      ]);
      throw e;
    }
  }
};

async function processOpportunity(
  opp: import('./types').VepOpportunityRow,
  cycleId: string,
  db: ReturnType<typeof createDbClient>,
  env: Env,
  metrics: CronRunMetrics
): Promise<void> {
  if (!opp.essay_mapping || Object.keys(opp.essay_mapping).length === 0) {
    metrics.errors.push({
      scope: 'opportunity_skipped',
      ref: opp.opportunity_id,
      error: 'essay_mapping vazio — popular antes de ativar'
    });
    return;
  }

  const apps = await listAllApplicationsForOpp(env, opp.opportunity_id);
  console.log(`[${WORKER_NAME}] opp ${opp.opportunity_id}: ${apps.length} applications listed`);

  const ttlDays = parseInt(env.ONBOARDING_TOKEN_TTL_DAYS, 10) || 7;

  for (const item of apps) {
    try {
      const detail = await getApplicationDetail(env, item.applicationId);
      const mapped = mapPmiToNucleo(detail, opp, cycleId, env.ORG_ID);

      const result = await upsertSelectionApplication(db, mapped);

      if (result.was_new) {
        metrics.applications_new++;

        const token = await issueOnboardingToken(db, {
          source_type: 'pmi_application',
          source_id: result.id,
          scopes: ['profile_completion', 'video_screening', 'consent_giving'],
          ttl_days: ttlDays,
          issued_by_worker: WORKER_NAME
        });

        const welcomeResult = await dispatchWelcome(db, env, {
          application_id: result.id,
          applicant_name: mapped.applicant_name,
          email: mapped.email,
          role_applied: mapped.role_applied,
          chapter: mapped.chapter,
          token
        });

        if (welcomeResult.success) {
          metrics.welcome_messages_dispatched++;
        } else {
          metrics.errors.push({
            scope: 'welcome',
            ref: result.id,
            error: welcomeResult.reason ?? 'unknown'
          });
        }
      } else {
        metrics.applications_updated++;
      }

    } catch (e: any) {
      metrics.errors.push({
        scope: 'application',
        ref: String(item.applicationId),
        error: e.message
      });
      console.error(`[${WORKER_NAME}] app ${item.applicationId} failed:`, e);
    }
  }
}
