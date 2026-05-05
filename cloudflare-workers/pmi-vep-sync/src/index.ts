/**
 * pmi-vep-sync — entry point.
 *
 * MODES:
 *   1. HTTP `/ingest` (primary) — recebe JSON do extract_pmi_volunteer.js
 *      (browser script) e processa applications. Auth via header
 *      `x-ingest-secret` (shared secret). Browser passa Cloudflare Bot Mgmt
 *      do PMI naturalmente; nosso worker só recebe.
 *
 *   2. `scheduled` (cron 04 UTC, watchdog only) — checa expiry do PMI access
 *      token cached em KV (futuro: re-issue automatic se houver refresh_token).
 *      Por ora apenas log + alerta GP via campaign_send_one_off se token
 *      expirar em < 12h (PM precisa re-seedar).
 *      Cron NÃO mais polleia PMI VEP API (Cloudflare Bot Management bloqueia
 *      datacenter IPs — descoberto durante p81 sessão de smoke).
 *
 * Pipeline /ingest:
 *   1. Validate x-ingest-secret header
 *   2. Validate JSON shape (applications array required)
 *   3. Lookup open selection_cycle
 *   4. Build vep_opportunities lookup
 *   5. Per application:
 *      a. mapScriptToNucleo (essay_mapping resolution)
 *      b. upsertSelectionApplication (compound key vep_app+vep_opp)
 *      c. If new: issueOnboardingToken + dispatchWelcome
 *   6. Return summary
 */

import type {
  Env,
  CronRunMetrics,
  ScriptIngestPayload,
  IngestSummary,
  VepOpportunityRow
} from './types';
import {
  createDbClient,
  logRunStart,
  logRunComplete,
  getOpenSelectionCycle,
  getActiveOpportunities,
  upsertSelectionApplication
} from './db';
import { issueOnboardingToken } from './onboarding-token';
import { dispatchWelcome } from './welcome';
import { mapScriptToNucleo } from './script-mapper';

const WORKER_NAME = 'pmi-vep-sync';
const ALLOWED_ORIGIN = 'https://volunteer.pmi.org';
const KV_KEY = 'pmi_oauth:tokens';

export default {
  async fetch(req: Request, env: Env, _ctx: ExecutionContext): Promise<Response> {
    const url = new URL(req.url);

    // CORS preflight
    if (req.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: corsHeaders()
      });
    }

    // Health endpoint (public, no auth)
    if (req.method === 'GET' && url.pathname === '/health') {
      return jsonResponse({ status: 'ok', worker: WORKER_NAME, mode: 'ingest+watchdog' }, 200);
    }

    // Ingest endpoint (POST + auth)
    if (req.method === 'POST' && url.pathname === '/ingest') {
      return handleIngest(req, env);
    }

    return jsonResponse({ error: 'not_found', message: `${req.method} ${url.pathname} not handled` }, 404);
  },

  /**
   * Cron handler — watchdog mode only.
   * Token expiry check + alert. NO PMI API polling (CF blocks).
   */
  async scheduled(event: ScheduledEvent, env: Env, _ctx: ExecutionContext): Promise<void> {
    const db = createDbClient(env);

    let runId: string;
    try {
      runId = await logRunStart(db, WORKER_NAME, new Date(event.scheduledTime), 'watchdog_check');
    } catch (e: any) {
      console.error(`[${WORKER_NAME}] logRunStart failed:`, e.message);
      return;
    }

    const metrics: CronRunMetrics = {
      trigger_reason: 'watchdog_check',
      opportunities_processed: 0,
      applications_new: 0,
      applications_updated: 0,
      applications_skipped_not_partner: 0,
      welcome_messages_dispatched: 0,
      drafts_dispatched: 0,
      errors: []
    };

    try {
      const tokens = await env.PMI_OAUTH_KV.get(KV_KEY, 'json') as { expires_at?: number } | null;

      if (!tokens || !tokens.expires_at) {
        (metrics as any).pmi_token_status = 'not_initialized';
        (metrics as any).note = 'KV pmi_oauth:tokens empty. Worker is HTTP-driven /ingest only; this is fine if no PMI API access planned.';
        await logRunComplete(db, runId, 'success', metrics, []);
        return;
      }

      const remainingMs = tokens.expires_at - Date.now();
      const remainingHours = remainingMs / 3600000;

      (metrics as any).pmi_token_remaining_hours = Number(remainingHours.toFixed(2));
      (metrics as any).pmi_token_expires_at = new Date(tokens.expires_at).toISOString();

      // Alert if expired or about to expire (< 12h)
      if (remainingMs < 12 * 3600 * 1000) {
        (metrics as any).pmi_token_expiring_soon = true;
        try {
          await db.rpc('campaign_send_one_off', {
            p_template_slug: 'cron_failure_alert',
            p_to_email: env.GP_NOTIFICATION_EMAIL,
            p_variables: {
              worker: WORKER_NAME,
              failure_count: 0,
              note: `PMI access_token expires in ${remainingHours.toFixed(1)}h — re-seed via wrangler kv key put`
            },
            p_metadata: { source: WORKER_NAME, alert_type: 'pmi_token_expiring' }
          });
          (metrics as any).alert_dispatched = true;
        } catch (e: any) {
          metrics.errors.push({ scope: 'alert', error: e.message });
        }
      }

      await logRunComplete(db, runId, 'success', metrics, metrics.errors);
    } catch (e: any) {
      console.error(`[${WORKER_NAME}] watchdog FATAL:`, e);
      await logRunComplete(db, runId, 'failed', metrics, [
        { scope: 'fatal', error: e.message, stack: e.stack }
      ]);
    }
  }
};

/**
 * /ingest — recebe JSON do browser script extract_pmi_volunteer.js
 */
async function handleIngest(req: Request, env: Env): Promise<Response> {
  // Auth
  const secret = req.headers.get('x-ingest-secret');
  if (!secret || secret !== env.INGEST_SHARED_SECRET) {
    return jsonResponse({ error: 'unauthorized' }, 401);
  }

  // Parse
  let body: ScriptIngestPayload;
  try {
    body = await req.json() as ScriptIngestPayload;
  } catch (e: any) {
    return jsonResponse({ error: 'invalid_json', message: e.message }, 400);
  }

  if (!body.applications || !Array.isArray(body.applications)) {
    return jsonResponse({ error: 'missing_applications', message: 'body.applications array required' }, 400);
  }

  const db = createDbClient(env);

  // Log this ingest run for observability (cron_run_log)
  let runId: string | null = null;
  try {
    runId = await logRunStart(db, WORKER_NAME + '-ingest', new Date(), 'http_ingest');
  } catch (e: any) {
    console.error('logRunStart failed:', e.message);
  }

  const cycle = await getOpenSelectionCycle(db);
  if (!cycle) {
    if (runId) {
      await logRunComplete(db, runId, 'skipped', { trigger_reason: 'http_ingest', applications_received: body.applications.length } as any, [
        { scope: 'cycle', error: 'no open selection cycle' }
      ]);
    }
    return jsonResponse({ error: 'no_open_cycle', message: 'No selection_cycles row with status=open' }, 412);
  }

  const opps = await getActiveOpportunities(db);
  const oppLookup: Record<string, VepOpportunityRow> = {};
  for (const o of opps) oppLookup[String(o.opportunity_id)] = o;

  const ttlDays = parseInt(env.ONBOARDING_TOKEN_TTL_DAYS, 10) || 7;

  const summary: IngestSummary = {
    cycle_id: cycle.id,
    cycle_code: cycle.cycle_code,
    applications_received: body.applications.length,
    applications_processed: 0,
    applications_new: 0,
    applications_updated: 0,
    applications_skipped: 0,
    applications_skipped_prior_cycle: 0,
    welcome_dispatched: 0,
    welcomes_skipped_non_submitted: 0,
    errors: []
  };

  const allQRs = body.questionResponses ?? [];

  for (const app of body.applications) {
    try {
      const oppId = String(app._opportunityId);
      const opp = oppLookup[oppId];

      if (!opp) {
        summary.applications_skipped++;
        summary.errors.push({
          scope: 'opportunity_not_active',
          ref: String(app.applicationId),
          error: `vep_opportunities row for opp ${oppId} not found or not is_active=true`
        });
        continue;
      }

      if (!opp.essay_mapping || Object.keys(opp.essay_mapping).length === 0) {
        summary.applications_skipped++;
        summary.errors.push({
          scope: 'essay_mapping_missing',
          ref: String(app.applicationId),
          error: `essay_mapping vazio para opp ${oppId}; popular antes de ativar`
        });
        continue;
      }

      const mapped = mapScriptToNucleo(app, opp, allQRs, cycle.id, env.ORG_ID);

      if (!mapped.email || !mapped.applicant_name) {
        summary.applications_skipped++;
        summary.errors.push({
          scope: 'missing_required',
          ref: String(app.applicationId),
          error: 'applicant_name or email missing'
        });
        continue;
      }

      const result = await upsertSelectionApplication(db, mapped);
      summary.applications_processed++;

      if (result.skipped_prior_cycle) {
        summary.applications_skipped_prior_cycle++;
        continue;
      }

      if (result.was_new) {
        summary.applications_new++;

        // Bug #2 fix (p91 audit, p92 Phase A): only dispatch welcome+token to
        // pending applicants from the submitted bucket. Qualified bucket =
        // already-active leaders from prior cycles; rejected bucket = declined
        // or withdrawn. Both are tracked in selection_applications for archive
        // (rich lifecycle data) but must NOT trigger onboarding email — that
        // sent welcomes to 4 unintended recipients on 2026-04-29
        // (Hayala/AnaCarla/Marcos already PMI leaders; Adalberto declined).
        const isPendingApplicant = app._bucket === 'submitted' && app.statusId === 2;
        if (!isPendingApplicant) {
          summary.welcomes_skipped_non_submitted++;
        } else {
          try {
            const token = await issueOnboardingToken(db, {
              source_type: 'pmi_application',
              source_id: result.id,
              scopes: ['profile_completion', 'video_screening', 'consent_giving'],
              ttl_days: ttlDays,
              issued_by_worker: WORKER_NAME + '-ingest'
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
              summary.welcome_dispatched++;
            } else {
              summary.errors.push({
                scope: 'welcome',
                ref: result.id,
                error: welcomeResult.reason ?? 'dispatch failed'
              });
            }
          } catch (e: any) {
            summary.errors.push({
              scope: 'token_or_welcome',
              ref: result.id,
              error: e.message
            });
          }
        }
      } else {
        summary.applications_updated++;
      }
    } catch (e: any) {
      summary.errors.push({
        scope: 'application',
        ref: String(app.applicationId),
        error: e.message
      });
      console.error(`[${WORKER_NAME}] app ${app.applicationId} failed:`, e);
    }
  }

  // Finalize run log
  if (runId) {
    const finalStatus = summary.errors.length > 0 && summary.applications_processed === 0
      ? 'failed'
      : 'success';
    await logRunComplete(db, runId, finalStatus, summary as any, summary.errors);
  }

  return jsonResponse(summary, 200);
}

function corsHeaders(): HeadersInit {
  return {
    'access-control-allow-origin': ALLOWED_ORIGIN,
    'access-control-allow-methods': 'POST, GET, OPTIONS',
    'access-control-allow-headers': 'content-type, x-ingest-secret',
    'access-control-max-age': '86400'
  };
}

function jsonResponse(body: any, status: number): Response {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: {
      'content-type': 'application/json',
      ...corsHeaders()
    }
  });
}
