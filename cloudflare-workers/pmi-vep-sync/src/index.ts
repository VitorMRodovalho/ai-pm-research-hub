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
  getRecentCycles,
  pickCycleForApplicationDate,
  getCycleAppIdStats,
  pickCycleByAppIdSequence,
  getActiveOpportunities,
  upsertSelectionApplication,
  findPersonIdByEmail,
  upsertPmiChapterMemberships,
  insertServiceHistory,
  setEngagementEndDateSource
} from './db';
import { issueOnboardingToken } from './onboarding-token';
import { dispatchWelcome } from './welcome';
import {
  mapScriptToNucleo,
  mapPmiChapterMemberships,
  mapServiceHistory
} from './script-mapper';
import { syncResumesParallel, type ResumeSyncResult } from './resume-sync';

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

  // p195 BUG-195.B fix: pre-fetch recent cycles (open + closed) for per-app
  // cycle redirection based on application_date. When an application's
  // submitted date falls within a CLOSED cycle's [open, close] window, the
  // app should be assigned to that semantic-correct cycle instead of the
  // currently-open one. Fixes the misassignment pattern surfaced in p195:
  // 5 apps applied during c3 were imported into b2 because b2 was open at
  // import time. Now logged via summary.applications_cycle_redirected.
  const recentCycles = await getRecentCycles(db);

  // p195 OPP-196.A heuristic: per-cycle app_id stats fallback for apps
  // without application_date (VEP "Active" status / historical legacy
  // import). Use case: PM importing cycle 2 candidates whose VEP status
  // is now Active (no submittedDate exposed) — app_id sequence places them
  // in the correct historical cycle once at least 1 cycle 2 app exists.
  const cycleAppIdStats = await getCycleAppIdStats(db);

  const ttlDays = parseInt(env.ONBOARDING_TOKEN_TTL_DAYS, 10) || 7;

  const summary: IngestSummary = {
    cycle_id: cycle.id,
    cycle_code: cycle.cycle_code,
    applications_received: body.applications.length,
    applications_processed: 0,
    applications_new: 0,
    applications_updated: 0,
    applications_skipped: 0,
    applications_skipped_prior_cycle: 0, // p153 hotfix7 — kept at 0 for dashboard backward-compat; cross-cycle apps now partial-refresh
    applications_cross_cycle_refreshed: 0,
    welcome_dispatched: 0,
    welcomes_skipped_non_submitted: 0,
    errors: [],
    // p126 E2 Phase B metrics
    phase_b_processed: 0,
    phase_b_skipped_private: 0,
    pmi_chapter_memberships_upserted: 0,
    service_history_inserted: 0,
    // p195 Opção B+: resume binary mirror to Supabase Storage
    resumes_synced: 0,
    resumes_skipped_no_url: 0,
    resumes_failed: 0,
    // p195 BUG-195.B: per-app cycle redirect counter
    applications_cycle_redirected: 0
  };

  const allQRs = body.questionResponses ?? [];
  const allHistory = body.serviceHistory ?? [];  // p126 E2 — 1:N service history rows

  // p195 Opção B+: pre-flight resume mirror to Supabase Storage.
  // Done BEFORE the per-app upsert loop because (a) Azure SAS URL is what we
  // received in the JSON and we want to act on it while still fresh (PM may
  // wait minutes between JSON download and Apply click), (b) parallelism (5
  // concurrent downloads) compresses 33 candidate CVs to ~10-15s total.
  // Skip apps without resumeUrl (qualified bucket — VEP doesn't expose
  // resume_url after candidate enters onboarding stage). dry_run mode skips
  // the entire sync to keep preview cheap.
  const resumeSyncResults = new Map<string, ResumeSyncResult>();
  if (body.dry_run !== true) {
    const appsWithResume = body.applications.filter(a => a.resumeUrl && a.applicantId);
    if (appsWithResume.length > 0) {
      const startedAt = Date.now();
      const syncMap = await syncResumesParallel(
        env.SUPABASE_URL,
        env.SUPABASE_SERVICE_ROLE_KEY,
        appsWithResume,
        cycle.cycle_code
      );
      for (const [app, result] of syncMap.entries()) {
        // Index by applicationId so per-app loop downstream can lookup quickly
        resumeSyncResults.set(String(app.applicationId), result);
        if (result.storage_path) {
          summary.resumes_synced = (summary.resumes_synced ?? 0) + 1;
        } else {
          summary.resumes_failed = (summary.resumes_failed ?? 0) + 1;
          summary.errors.push({
            scope: 'resume_sync_failed',
            ref: String(app.applicationId),
            error: result.error ?? 'unknown',
          });
        }
      }
      summary.resumes_skipped_no_url = body.applications.length - appsWithResume.length;
      const elapsed = Date.now() - startedAt;
      console.log(`[resume-sync] ${syncMap.size} apps, ${summary.resumes_synced} ok, ${summary.resumes_failed} failed, ${elapsed}ms`);
    } else {
      summary.resumes_skipped_no_url = body.applications.length;
    }
  }

  // p151 C: dry-run preview mode — compute diff WITHOUT DML.
  // Returns IngestDryRunSummary with will_insert/will_update/will_skip arrays.
  // Used by /api/admin/import-pmi-vep-json Astro endpoint for admin UI preview
  // before the PM hits the Apply button.
  if (body.dry_run === true) {
    const dryDiff: any = {
      dry_run: true,
      cycle_id: cycle.id,
      cycle_code: cycle.cycle_code,
      applications_received: body.applications.length,
      will_insert: [],
      will_update: [],
      will_cross_cycle_refresh: [], // p153 hotfix7 — split out from will_update
      will_skip: [],
      errors: []
    };

    for (const app of body.applications) {
      const oppId = String(app._opportunityId);
      const opp = oppLookup[oppId];
      if (!opp) {
        dryDiff.will_skip.push({ ref: String(app.applicationId), reason: 'opportunity_not_active' });
        continue;
      }
      if (!opp.essay_mapping || Object.keys(opp.essay_mapping).length === 0) {
        dryDiff.will_skip.push({ ref: String(app.applicationId), reason: 'essay_mapping_missing' });
        continue;
      }
      const mapped = mapScriptToNucleo(app, opp, allQRs, cycle.id, cycle.cycle_code, env.ORG_ID);
      if (!mapped.email || !mapped.applicant_name) {
        dryDiff.will_skip.push({ ref: String(app.applicationId), reason: 'missing_required (applicant_name or email)' });
        continue;
      }

      // Lookup existing by compound key (vep_application_id, vep_opportunity_id).
      // Canonical logic per feedback_pmi_vep_ingest_logic_canonical.md (p150 PM diretiva).
      const { data: existing } = await db
        .from('selection_applications')
        .select('id, applicant_name, status, cycle_id, role_applied, chapter')
        .eq('vep_application_id', mapped.vep_application_id)
        .eq('vep_opportunity_id', mapped.vep_opportunity_id)
        .maybeSingle();

      if (existing) {
        const bucket = (existing.cycle_id !== mapped.cycle_id)
          ? dryDiff.will_cross_cycle_refresh   // p153 hotfix7 — partial refresh path
          : dryDiff.will_update;
        bucket.push({
          application_id: existing.id,
          applicant_name: mapped.applicant_name,
          existing_cycle_id: existing.cycle_id,
          existing_status: existing.status,
          existing_role: existing.role_applied
        });
      } else {
        dryDiff.will_insert.push({
          applicant_name: mapped.applicant_name,
          email: mapped.email,
          opportunity_id: oppId,
          chapter: opp.chapter_posted,
          role_applied: opp.role_default
        });
      }
    }

    if (runId) {
      await logRunComplete(db, runId, 'success', {
        trigger_reason: 'http_ingest_dry_run',
        applications_received: body.applications.length,
        will_insert: dryDiff.will_insert.length,
        will_update: dryDiff.will_update.length,
        will_cross_cycle_refresh: dryDiff.will_cross_cycle_refresh.length,
        will_skip: dryDiff.will_skip.length
      } as any, dryDiff.errors);
    }

    // #224 — surface correlation id + Phase A source-export warning so the
    // admin UI can deep-link and disambiguate the uploaded ingestResult.error
    // (Phase A) from this dry-run's status (Phase B).
    dryDiff.run_id = runId;
    dryDiff.ingest_result_warning = body.ingestResult ?? null;

    return jsonResponse(dryDiff, 200);
  }

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

      const mapped = mapScriptToNucleo(app, opp, allQRs, cycle.id, cycle.cycle_code, env.ORG_ID);

      // p195 BUG-195.B fix: redirect to semantically-correct cycle when
      // application_date falls in a different cycle's window. Mapper already
      // computed application_date (from submittedDate or fallback). If a
      // closed-cycle match exists, override the cycle_id stamped by mapper.
      const dateMatched = pickCycleForApplicationDate(mapped.application_date, recentCycles);
      if (dateMatched && dateMatched.id !== cycle.id) {
        // Track the redirect for observability + audit
        summary.applications_cycle_redirected = (summary.applications_cycle_redirected ?? 0) + 1;
        console.log(`[cycle-redirect:date] app=${app.applicationId} date=${mapped.application_date} ` +
          `default=${cycle.cycle_code} → matched=${dateMatched.cycle_code}`);
        mapped.cycle_id = dateMatched.id;
      } else if (!mapped.application_date) {
        // p195 OPP-196.A fallback: application_date is null (VEP Active /
        // historical legacy). Try app_id sequence heuristic to infer the
        // semantically-correct cycle before defaulting to current open.
        const appIdNum = Number(app.applicationId);
        const seqMatched = Number.isFinite(appIdNum)
          ? pickCycleByAppIdSequence(appIdNum, cycleAppIdStats)
          : null;
        if (seqMatched && seqMatched.cycle_id !== cycle.id) {
          summary.applications_cycle_redirected = (summary.applications_cycle_redirected ?? 0) + 1;
          console.log(`[cycle-redirect:seq] app=${app.applicationId} (no date) ` +
            `default=${cycle.cycle_code} → matched=${seqMatched.cycle_code} ` +
            `(in range ${seqMatched.min_app_id}-${seqMatched.max_app_id})`);
          mapped.cycle_id = seqMatched.cycle_id;
        }
      }

      // p195 Opção B+: stamp storage mirror result if pre-flight sync succeeded.
      // Mapper defaults both fields to null, so this is purely additive.
      const resumeResult = resumeSyncResults.get(String(app.applicationId));
      if (resumeResult?.storage_path) {
        mapped.resume_storage_path = resumeResult.storage_path;
        mapped.resume_synced_at = resumeResult.synced_at;
      }

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

      // ─── p126 E2: Phase B canonical UPSERT + service history INSERT ────────
      // p153 hotfix7: Phase B canonical runs for ALL rows (incl. cross-cycle partial
      // refresh) so chapter memberships + service history stay current for past
      // candidates too. Only private profiles skip canonical UPSERT.
      {
        // Wave 3 synth (D-CONV-3): track Phase B participation by ANY non-null Phase B
        // signal, not just pmi_data_fetched_at presence. Older script versions might
        // not emit pmiDataFetchedAt but still have Phase B fields populated.
        if (mapped.community_profile_private === true) {
          summary.phase_b_skipped_private = (summary.phase_b_skipped_private ?? 0) + 1;
        } else if (
          mapped.pmi_data_fetched_at ||
          (mapped.pmi_memberships && Array.isArray(mapped.pmi_memberships) && mapped.pmi_memberships.length > 0) ||
          mapped.profile_location ||
          mapped.profile_about_me ||
          mapped.service_history_count !== null
        ) {
          summary.phase_b_processed = (summary.phase_b_processed ?? 0) + 1;
        }

        // Resolve person_id via email (Strategy 1+2 in db.ts findPersonIdByEmail)
        // Ghost member case (person_id NULL): canonical UPSERT skipped per security-engineer Wave 2 B1.
        try {
          const personId = await findPersonIdByEmail(db, mapped.email);

          // pmi_chapter_memberships UPSERT (canonical multi-chapter — Decision 2 hybrid)
          if (personId) {
            const memberships = mapPmiChapterMemberships(app, personId);
            if (memberships.length > 0) {
              const upserted = await upsertPmiChapterMemberships(db, memberships);
              summary.pmi_chapter_memberships_upserted =
                (summary.pmi_chapter_memberships_upserted ?? 0) + upserted;
            }

            // Decision 8 — engagement end_date_source 'pmi_vep' fallback
            // Only set if VEP serviceEndDateUTC present AND source not already 'agreement'
            if (app.serviceEndDateUTC) {
              try {
                const endDate = app.serviceEndDateUTC.slice(0, 10);
                await setEngagementEndDateSource(db, personId, 'pmi_vep', endDate);
              } catch (e: any) {
                summary.errors.push({
                  scope: 'engagement_end_date_source',
                  ref: String(app.applicationId),
                  error: e.message
                });
              }
            }
          } else if (mapped.pmi_memberships && Array.isArray(mapped.pmi_memberships) && mapped.pmi_memberships.length > 0) {
            // Wave 3 synth (D-CONV-2): observable logging instead of silent no-op.
            // No person_id resolved (ghost or new applicant not yet member) — snapshot
            // already in selection_applications.pmi_memberships JSONB; no canonical UPSERT.
            // I_PMI_CHAPTER_MEMBERSHIPS_ORPHANS invariant detects post-hoc if needed.
            console.warn(`[${WORKER_NAME}] Phase B membership snapshot persisted without canonical UPSERT (no person_id resolved for email): app=${app.applicationId}, memberships=${mapped.pmi_memberships.length}`);
          }

          // service_history INSERT (1:N append-only — applies regardless of person_id)
          // Uses dbApplicationId from upsert result, not personId.
          const historyRows = mapServiceHistory(app, result.id, allHistory);
          if (historyRows.length > 0) {
            const inserted = await insertServiceHistory(db, historyRows);
            summary.service_history_inserted =
              (summary.service_history_inserted ?? 0) + inserted;
          }
        } catch (e: any) {
          summary.errors.push({
            scope: 'phase_b_canonical',
            ref: String(app.applicationId),
            error: e.message
          });
        }
      }

      if (result.cross_cycle_refresh) {
        // p153 hotfix7 — row from prior cycle received PARTIAL refresh
        // (resume_url SAS rotation, profile_*, vep_status_raw, etc.) but no
        // welcome dispatch (not a new candidate; decision history preserved).
        summary.applications_cross_cycle_refreshed++;
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

  // #224 — surface correlation id + Phase A source-export warning so the
  // admin UI can deep-link to cron_run_log and disambiguate the uploaded
  // ingestResult.error (Phase A export-side) from this Apply call's status.
  summary.run_id = runId;
  summary.ingest_result_warning = body.ingestResult ?? null;

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
