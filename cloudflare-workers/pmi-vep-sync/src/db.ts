/**
 * Supabase client for the worker (service_role key, bypasses RLS).
 * SECURITY: Never expose this client outside the worker. service_role has full DB access.
 */

import { createClient, SupabaseClient } from '@supabase/supabase-js';
import type { Env, CronRunMetrics } from './types';
import { parseBrChapterCode } from './mapper';

export function createDbClient(env: Env): SupabaseClient {
  return createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { 'x-worker': 'pmi-vep-sync' } }
  });
}

// =====================================================================
// Cron run logging helpers
// =====================================================================

export async function logRunStart(
  db: SupabaseClient,
  workerName: string,
  scheduledFor: Date,
  triggerReason: string
): Promise<string> {
  const { data, error } = await db.rpc('log_cron_run_start', {
    p_worker_name: workerName,
    p_scheduled_for: scheduledFor.toISOString(),
    p_metrics: { trigger_reason: triggerReason }
  });
  if (error) throw new Error(`logRunStart failed: ${error.message}`);
  return data as string;
}

export async function logRunComplete(
  db: SupabaseClient,
  runId: string,
  status: 'success' | 'failed' | 'skipped',
  metrics: Partial<CronRunMetrics>,
  errors: any[] = []
): Promise<void> {
  const { error } = await db.rpc('log_cron_run_complete', {
    p_run_id: runId,
    p_status: status,
    p_metrics: metrics as any,
    p_errors: errors
  });
  if (error) {
    console.error('logRunComplete failed:', error.message);
  }
}

// =====================================================================
// Selection cycle helpers
// =====================================================================

export async function getOpenSelectionCycle(db: SupabaseClient): Promise<{ id: string; cycle_code: string } | null> {
  const { data, error } = await db
    .from('selection_cycles')
    .select('id, cycle_code')
    .eq('status', 'open')
    .order('open_date', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) {
    console.error('getOpenSelectionCycle:', error.message);
    return null;
  }
  return data;
}

// p195 BUG-195.B fix: per-app cycle assignment based on application_date.
//
// Returns recent selection_cycles (open + closed) ordered by open_date desc.
// Used by pickCycleForApplicationDate() to redirect mis-assigned apps to
// their semantic-correct cycle when application_date falls in a closed cycle.
export interface CycleWindow {
  id: string;
  cycle_code: string;
  status: string;
  open_date: string | null;     // ISO YYYY-MM-DD
  close_date: string | null;    // ISO YYYY-MM-DD
}

export async function getRecentCycles(db: SupabaseClient): Promise<CycleWindow[]> {
  // Pull all cycles with non-null open_date (sentinel rows like "draft" without
  // dates are excluded). Going back 18 months gives plenty of overlap window
  // for late VEP imports without bloating the response.
  const cutoff = new Date(Date.now() - 18 * 30 * 86400000).toISOString().slice(0, 10);
  const { data, error } = await db
    .from('selection_cycles')
    .select('id, cycle_code, status, open_date, close_date')
    .gte('open_date', cutoff)
    .order('open_date', { ascending: false });

  if (error) {
    console.error('getRecentCycles:', error.message);
    return [];
  }
  return (data ?? []) as CycleWindow[];
}

// Pure function — picks the cycle whose [open_date, close_date] range contains
// applicationDate. If multiple cycles match (overlapping ranges), prefers the
// one with the latest open_date (most-recent applicable). If applicationDate
// is null or no cycle matches, returns null (caller falls back to "open cycle"
// default behavior — matches pre-p195 semantics).
//
// Date semantics: applicationDate is the candidate's VEP submittedDate.
// Cycle windows use [open_date, close_date] INCLUSIVE on both ends. A cycle
// without close_date matches anything >= open_date (still-open cycle).
export function pickCycleForApplicationDate(
  applicationDate: string | null | undefined,
  cycles: CycleWindow[]
): CycleWindow | null {
  if (!applicationDate || cycles.length === 0) return null;
  // Normalize to date-only string for comparison (ISO is sortable).
  const appDate = applicationDate.length >= 10 ? applicationDate.slice(0, 10) : applicationDate;

  // First pass: cycles whose range includes appDate.
  const matches = cycles.filter(c => {
    if (!c.open_date) return false;
    if (appDate < c.open_date) return false;
    if (c.close_date && appDate > c.close_date) return false;
    return true;
  });
  if (matches.length === 0) return null;

  // Multiple matches → prefer latest open_date (most-recent applicable).
  // This handles cycle overlap (e.g., b2 ending while next cycle opening).
  matches.sort((a, b) => (a.open_date! < b.open_date! ? 1 : -1));
  return matches[0];
}

// p195 OPP-196.A heuristic: per-cycle app_id sequence stats for fallback
// cycle assignment when application_date is null (VEP "Active" / legacy
// historical imports).
//
// Returns each cycle's existing applicationId stats:
//   { cycle_id, min_app_id, max_app_id, sample_count }
// Only cycles with ≥1 numeric vep_application_id are returned (bootstrap
// cycles with 0 apps fall back to default open-cycle behavior).
export interface CycleAppIdStats {
  cycle_id: string;
  cycle_code: string;
  min_app_id: number;
  max_app_id: number;
  sample_count: number;
}

export async function getCycleAppIdStats(db: SupabaseClient): Promise<CycleAppIdStats[]> {
  // Aggregate via SQL — single query, indexed (selection_applications.cycle_id
  // has an index). vep_application_id is text but always numeric in practice;
  // filter via regex to skip any non-numeric defensively.
  const { data, error } = await db.rpc('_pmi_vep_sync_cycle_app_id_stats');
  if (error) {
    // Fallback to client-side aggregation if helper RPC not yet deployed.
    console.warn('getCycleAppIdStats RPC unavailable, falling back to client agg:', error.message);
    const { data: rows, error: rowsErr } = await db
      .from('selection_applications')
      .select('cycle_id, vep_application_id')
      .not('vep_application_id', 'is', null);
    if (rowsErr) {
      console.error('getCycleAppIdStats fallback failed:', rowsErr.message);
      return [];
    }
    const cycleMap = new Map<string, { min: number; max: number; count: number }>();
    for (const row of (rows ?? []) as Array<{ cycle_id: string; vep_application_id: string }>) {
      const appId = parseInt(row.vep_application_id, 10);
      if (!Number.isFinite(appId)) continue;
      const cur = cycleMap.get(row.cycle_id);
      if (!cur) cycleMap.set(row.cycle_id, { min: appId, max: appId, count: 1 });
      else { cur.min = Math.min(cur.min, appId); cur.max = Math.max(cur.max, appId); cur.count++; }
    }
    // Need cycle_code — fetch separately
    const cycleIds = [...cycleMap.keys()];
    if (cycleIds.length === 0) return [];
    const { data: cycles } = await db
      .from('selection_cycles')
      .select('id, cycle_code')
      .in('id', cycleIds);
    const codeMap = new Map((cycles ?? []).map((c: any) => [c.id, c.cycle_code as string]));
    return cycleIds.map(id => ({
      cycle_id: id,
      cycle_code: codeMap.get(id) ?? '',
      min_app_id: cycleMap.get(id)!.min,
      max_app_id: cycleMap.get(id)!.max,
      sample_count: cycleMap.get(id)!.count,
    }));
  }
  return (data ?? []) as CycleAppIdStats[];
}

// Pure function — picks the cycle whose existing app_id range [min, max]
// contains the new appId. Falls back to nearest range (smallest delta) if
// no exact containment. Returns null if no cycles have any apps yet
// (bootstrap edge — caller falls back to open-cycle default).
//
// Use case (PM p195 follow-up): importing historical cycle 2 candidates
// who are now Active in VEP (no application_date) — app_ids predate
// cycle 3 (268xxx-277xxx) so heuristic assigns them to cycle 2 once
// at least 1 cycle 2 app has been imported.
//
// Tolerance: ±5000 buffer expands "contains" range to handle near-edge
// app_ids (PMI app_ids increase ~3000-5000 between cycle waves; the buffer
// captures border-case applications).
export function pickCycleByAppIdSequence(
  appId: number | null | undefined,
  stats: CycleAppIdStats[]
): CycleAppIdStats | null {
  if (appId == null || !Number.isFinite(appId) || stats.length === 0) return null;
  const BUFFER = 5000;

  // First pass: exact containment (within [min-BUFFER, max+BUFFER]).
  const contained = stats.filter(s =>
    appId >= s.min_app_id - BUFFER && appId <= s.max_app_id + BUFFER
  );
  if (contained.length === 1) return contained[0];
  if (contained.length > 1) {
    // Multiple matches (cycles with overlapping ranges) → prefer cycle with
    // strictest containment (smallest range that still includes appId).
    contained.sort((a, b) => (a.max_app_id - a.min_app_id) - (b.max_app_id - b.min_app_id));
    return contained[0];
  }

  // No containment → return cycle whose range edge is closest to appId.
  // Computes min distance to either edge of each cycle's range.
  const ranked = stats.map(s => ({
    stats: s,
    delta: Math.min(
      Math.abs(appId - s.min_app_id),
      Math.abs(appId - s.max_app_id)
    ),
  }));
  ranked.sort((a, b) => a.delta - b.delta);
  // Reject if best match is too far (> 20k delta is likely a totally
  // different era — better to fall back to open cycle than misassign).
  if (ranked[0].delta > 20000) return null;
  return ranked[0].stats;
}

// =====================================================================
// VEP opportunity helpers
// =====================================================================

import type { VepOpportunityRow } from './types';

export async function getActiveOpportunities(db: SupabaseClient): Promise<VepOpportunityRow[]> {
  const { data, error } = await db
    .from('vep_opportunities')
    .select('opportunity_id, title, chapter_posted, role_default, essay_mapping, vep_url, is_active')
    .eq('is_active', true);

  if (error) throw new Error(`getActiveOpportunities: ${error.message}`);
  return (data ?? []) as VepOpportunityRow[];
}

// =====================================================================
// Application upsert
// =====================================================================

import type {
  SelectionApplicationUpsert,
  ServiceHistoryInsert
} from './types';

export interface UpsertResult {
  id: string;
  was_new: boolean;
  consent_active: boolean;
  /** p153 hotfix7 — true when existing row belonged to a PRIOR cycle and
   *  received a PARTIAL refresh (external PMI data only). False otherwise.
   *  Replaces the legacy `skipped_prior_cycle` flag (which fully skipped). */
  cross_cycle_refresh?: boolean;
  prior_cycle_id?: string;
}

// =====================================================================
// #472 correction #2 — re-import status freeze (B2 root cause)
// =====================================================================

/**
 * Canonical selection-pipeline ladder + terminal set.
 *
 * Kept byte-aligned with `recompute_application_status` (migration
 * 20260805000090): the worker writes status on same-cycle re-import and the
 * daily heal-cron recomputes it from facts — if their status models diverged
 * they would fight (worker clobbers → cron heals → worker clobbers …). The
 * parity contract test (`p472-vep-reimport-status-freeze`) asserts these two
 * literals equal the migration's `v_ladder` + terminal `NOT IN (...)` list.
 */
const SELECTION_STATUS_LADDER = [
  'submitted', 'screening', 'objective_eval', 'objective_cutoff',
  'interview_pending', 'interview_scheduled', 'interview_done', 'final_eval',
];
const SELECTION_TERMINAL_STATUSES = new Set([
  'approved', 'rejected', 'converted', 'withdrawn', 'cancelled', 'waitlist', 'interview_noshow',
]);

/**
 * VEP raw statuses (`vep_status_raw`, written verbatim from the extract script's
 * `app.status`) that represent a HARD, per-application terminal decision: the
 * recruiter declined to extend an offer, the volunteer withdrew, or the
 * application/offer expired or was removed. These all surface via the extract
 * script's `rejected` bucket → `mapBucketAndStatusToNucleo` already maps them to
 * a terminal platform status ('rejected' / 'withdrawn').
 *
 * #693 defect 1 — distinct from the blind 'Submitted' bucket: VEP emits
 * 'Submitted' for EVERY in-flight app (it cannot see the platform pipeline), and
 * the #472 freeze deliberately ignores that so a re-sync never knocks an advanced
 * candidate back. But a HARD terminal decision is authoritative and must pull the
 * candidate OUT of the active funnel even mid-pipeline — otherwise a VEP-declined
 * application lingers at e.g. 'screening' and the candidate surfaces under the
 * wrong, dead application (live case: Ana Sofia leader app OfferNotExtended stuck
 * at 'screening'). Matched case-insensitively. Kept in sync with the DB-side
 * heal `reconcile_vep_terminal_status` (migration 20260805000171).
 */
const VEP_HARD_TERMINAL_STATUSES = new Set([
  'offernotextended', 'declined', 'withdrawn', 'expired', 'offerexpired', 'removed',
]);

/**
 * Decide the selection_applications.status to persist on a SAME-CYCLE VEP
 * re-import (#472 correction #2, B2 root cause).
 *
 * VEP only knows its own buckets (→ submitted | approved | rejected | cancelled,
 * defaulting to 'submitted'); it is blind to the platform-internal pipeline
 * (screening … final_eval). A naive `status = payload.status` therefore knocks an
 * advanced candidate back to 'submitted' on every re-sync — they vanish from the
 * final ranking (live evidence: all 37 in-flight apps carry vep_status_raw=
 * 'Submitted', the bucket the mapper emits as 'submitted').
 *
 * Rule — forward-only + terminal-safe (symmetric with the heal-cron):
 *   • existing terminal  → freeze (never re-open a decided app via re-import).
 *   • incoming is a HARD terminal VEP decision (vep_status_raw ∈
 *     VEP_HARD_TERMINAL_STATUSES → mapper emits a terminal status) → propagate
 *     even mid-pipeline (#693 defect 1: an explicit recruiter/volunteer terminal
 *     decision is authoritative; it must remove the candidate from the active funnel).
 *   • incoming is a VEP soft exit (not on the in-flight ladder, NOT a hard
 *     terminal) → accept only from the pristine 'submitted' intake; otherwise
 *     freeze (a PMI opportunity-posting expiry / blind bucket must not reject a
 *     candidate already mid-pipeline — the platform owns exits past intake).
 *   • both in-flight → forward-only: write incoming only if it ranks strictly
 *     ahead of existing, else freeze. (VEP can't emit a forward in-flight stage,
 *     so in practice every advanced app is frozen — exactly the B2 fix.)
 */
export function resolveReimportStatus(
  existing: string | null | undefined,
  incoming: string,
  vepStatusRaw?: string | null
): string {
  if (!existing) return incoming;                                  // defensive (status is NOT NULL on update)
  if (SELECTION_TERMINAL_STATUSES.has(existing)) return existing;  // terminal-safe (platform decision stands)

  // #693 defect 1 — a HARD terminal VEP decision (recruiter declined / volunteer
  // withdrew / application or offer expired) overrides the #472 mid-pipeline
  // freeze. The freeze exists because VEP is blind to the internal pipeline for
  // IN-FLIGHT apps (every one carries vep_status_raw='Submitted'); it must NOT
  // also swallow an explicit terminal decision. Guarded twice: (a) the raw VEP
  // status must be in the hard-terminal set, and (b) the mapper must have already
  // resolved `incoming` to a terminal platform status — so a mis-typed or
  // unexpected raw value can never silently terminalize an in-flight candidate.
  if (
    vepStatusRaw &&
    VEP_HARD_TERMINAL_STATUSES.has(vepStatusRaw.toLowerCase()) &&
    SELECTION_TERMINAL_STATUSES.has(incoming)
  ) {
    return incoming;
  }

  const exRank = SELECTION_STATUS_LADDER.indexOf(existing);
  if (exRank === -1) return existing;                              // unknown/non-domain existing → freeze
  const inRank = SELECTION_STATUS_LADDER.indexOf(incoming);
  if (inRank === -1) return existing === 'submitted' ? incoming : existing;  // VEP exit only from intake
  return inRank > exRank ? incoming : existing;                              // forward-only
}

/**
 * Upsert selection_applications by COMPOUND KEY (vep_application_id, vep_opportunity_id).
 *
 * Per migration 20260516200000 B2 fix: PARTIAL COMPOUND UNIQUE on
 * (vep_application_id, vep_opportunity_id) WHERE both NOT NULL.
 *
 * Compound key preserves the dual-track triaged_to_leader pattern where
 * the same PMI applicationId can appear linked to two opportunities
 * (e.g., 64966 leader + 64967 researcher).
 *
 * CYCLE-AWARE BEHAVIOR (p153 hotfix7, replaces post-2026-04-29 full skip):
 * If existing.cycle_id != payload.cycle_id (row belongs to a PRIOR cycle),
 * the upsert performs a PARTIAL refresh:
 *   - PRESERVES decision-history fields: cycle_id, status, role_applied,
 *     motivation_letter, proposed_theme, areas_of_interest, availability_declared,
 *     leadership_experience, academic_background, non_pmi_experience,
 *     reason_for_applying, application_date, imported_at.
 *   - REFRESHES external PMI data: resume_url (Azure SAS ~1-48h TTL),
 *     linkedin_url, phone, email, chapter, profile_*, pmi_memberships,
 *     service_*, vep_status_raw, vep_last_seen_at, pmi_data_fetched_at.
 * Aligns with PM canonical directive p150 (sediment
 * `feedback_pmi_vep_ingest_logic_canonical.md`): "Anti-pattern: diff filtrado
 * por cycle único." Pre-hotfix, prior-cycle rows kept stale resume_url
 * indefinitely, breaking CV access for past candidates.
 *
 * Same-cycle updates proceed with full field update as before.
 */
export async function upsertSelectionApplication(
  db: SupabaseClient,
  payload: SelectionApplicationUpsert
): Promise<UpsertResult> {
  const { data: existing } = await db
    .from('selection_applications')
    // email + vep_reconciled_at → #444 reconciled-email freeze;
    // status → #472 corr.#2 re-import status freeze (both applied below).
    .select('id, cycle_id, email, status, vep_reconciled_at, consent_ai_analysis_at, consent_ai_analysis_revoked_at')
    .eq('vep_application_id', payload.vep_application_id)
    .eq('vep_opportunity_id', payload.vep_opportunity_id)
    .maybeSingle();

  if (existing) {
    // External-PMI-data refresh — fields that legitimately change post-cycle
    // (resume_url SAS rotation, profile data, certifications, chapter, VEP bucket).
    const commonRefresh = {
      pmi_id: payload.pmi_id,
      applicant_name: payload.applicant_name,
      // #444: freeze the email once an admin has manually reconciled this app to a
      // member (vep_reconciled_at set). The worker matches by COMPOUND KEY
      // (vep_application_id, vep_opportunity_id), NOT by email, so a PMI re-sync
      // would otherwise overwrite a reconciled email↔member link back to the raw
      // PMI email — silently breaking invariant R_approved_application_has_member
      // and red-lighting CI for unrelated PRs on every cycle import (live case:
      // Paulo Alves, app 6259ced2, clobbered pejota81 over the reconciled
      // paulo-junior on the 2026-05-30 sync). Writing back the existing value is a
      // deliberate no-op that preserves the reconciliation across every future sync;
      // non-reconciled rows refresh email from PMI exactly as before.
      email: existing.vep_reconciled_at ? existing.email : payload.email,
      phone: payload.phone,
      linkedin_url: payload.linkedin_url,
      resume_url: payload.resume_url,
      // p195 Opção B+: include storage mirror path + sync timestamp in commonRefresh
      // so cross-cycle partial refresh also updates these (each new SAS rotation may
      // bring a fresh storage upload if Worker download succeeded).
      resume_storage_path: payload.resume_storage_path ?? null,
      resume_synced_at: payload.resume_synced_at ?? null,
      chapter: payload.chapter,
      membership_status: payload.membership_status,
      certifications: payload.certifications,
      chapter_affiliation: payload.chapter_affiliation,
      // p126 E2 Phase B fields (per ADR-0076 Princípio 1 + Migration 1)
      applicant_city: payload.applicant_city,
      profile_location: payload.profile_location,
      profile_state: payload.profile_state,
      profile_city: payload.profile_city,
      profile_country: payload.profile_country,
      pmi_memberships: payload.pmi_memberships,
      profile_industry: payload.profile_industry,
      profile_company: payload.profile_company,
      profile_designation: payload.profile_designation,
      profile_certifications: payload.profile_certifications,
      profile_volunteer_interest: payload.profile_volunteer_interest,
      profile_specialties: payload.profile_specialties,
      profile_linkedin_url: payload.profile_linkedin_url,
      profile_about_me: payload.profile_about_me,
      service_history_count: payload.service_history_count,
      service_history_chapters: payload.service_history_chapters,
      service_first_start_date: payload.service_first_start_date,
      service_latest_end_date: payload.service_latest_end_date,
      is_open_to_volunteer: payload.is_open_to_volunteer,
      community_profile_private: payload.community_profile_private,
      pmi_data_fetched_at: payload.pmi_data_fetched_at,
      consent_version: payload.consent_version,
      // p152 W1.2 hotfix6: vep_status_raw + vep_last_seen_at added to mapper p151
      // but never reached UPDATE SET clause — silently dropped on every ingest.
      // Worker reported success but vep_status_raw stayed NULL in all 97 apps.
      vep_status_raw: payload.vep_status_raw,
      vep_last_seen_at: payload.vep_last_seen_at,
      updated_at: new Date().toISOString()
    };

    if (existing.cycle_id !== payload.cycle_id) {
      // p153 hotfix7 — cross-cycle PARTIAL refresh. See function-level comment.
      // #693 note: cross-cycle refresh updates vep_status_raw but deliberately
      // does NOT touch `status` (decision history of a prior cycle is preserved).
      // A hard-terminal VEP decision arriving cross-cycle is therefore healed by
      // reconcile_vep_terminal_status (migration 20260805000171), not here.
      const { error } = await db
        .from('selection_applications')
        .update(commonRefresh)
        .eq('id', existing.id);

      if (error) throw new Error(`cross-cycle partial refresh selection_applications: ${error.message}`);

      return {
        id: existing.id,
        was_new: false,
        consent_active: !!existing.consent_ai_analysis_at && !existing.consent_ai_analysis_revoked_at,
        cross_cycle_refresh: true,
        prior_cycle_id: existing.cycle_id
      };
    }

    // Same-cycle full update — decision-history fields also overwritten.
    const { error } = await db
      .from('selection_applications')
      .update({
        ...commonRefresh,
        // cycle_id intentionally NOT updated (set on insert; preserved on every update)
        role_applied: payload.role_applied,
        motivation_letter: payload.motivation_letter,
        proposed_theme: payload.proposed_theme,
        areas_of_interest: payload.areas_of_interest,
        availability_declared: payload.availability_declared,
        leadership_experience: payload.leadership_experience,
        academic_background: payload.academic_background,
        non_pmi_experience: payload.non_pmi_experience,
        reason_for_applying: payload.reason_for_applying,
        // Wave 3 synth (S-DA-1): application_date refreshed on re-import
        // (PMI may move app across lifecycle timestamps — submitted/expired/withdrawn)
        application_date: payload.application_date,
        // #472 corr.#2 — freeze status (forward-only + terminal-safe): a blind
        // same-cycle re-sync must not regress an advanced candidate back to
        // 'submitted'. VEP is blind to the internal pipeline (every in-flight app
        // carries vep_status_raw='Submitted' → mapper emits 'submitted'), so the
        // pre-fix `status: payload.status` erased scored candidates from the final
        // ranking. Symmetric with recompute_application_status (mig 20260805000090)
        // so the worker and the daily heal-cron never fight.
        // #693 defect 1 — pass vep_status_raw so a HARD terminal VEP decision
        // (OfferNotExtended/Withdrawn/Expired/OfferExpired) terminalizes an
        // in-flight candidate instead of being frozen by the #472 mid-pipeline rule.
        status: resolveReimportStatus(existing.status, payload.status, payload.vep_status_raw),
        imported_at: payload.imported_at,
      })
      .eq('id', existing.id);

    if (error) throw new Error(`update selection_applications: ${error.message}`);

    return {
      id: existing.id,
      was_new: false,
      consent_active: !!existing.consent_ai_analysis_at && !existing.consent_ai_analysis_revoked_at
    };
  } else {
    const { data: inserted, error } = await db
      .from('selection_applications')
      .insert(payload)
      .select('id')
      .single();

    if (error) throw new Error(`insert selection_applications: ${error.message}`);

    return {
      id: inserted.id,
      was_new: true,
      consent_active: false
    };
  }
}

// =====================================================================
// p126 E2 — Phase B helpers: persons lookup + chapter_memberships UPSERT
// + service_history INSERT
// (ADR-0076 Princípio 1 + Decisions 2 + S5 + Risk 2 mitigation)
// =====================================================================

/**
 * Resolve persons.id from email match. Used to link PMI Community canonical
 * data (service_history + engagement end_date) to the identity model. Returns
 * NULL if no person found (= ghost case; callers skip the canonical write to
 * preserve the orphan invariant). (#441: pmi_chapter_memberships path retired.)
 *
 * Lookup priority:
 *   1. members.email exact match → members.person_id
 *   2. members.secondary_emails @> [email] → members.person_id
 *
 * Per security-engineer Wave 2 B1: ghost-member path (members.person_id NULL)
 * returns NULL here; canonical UPSERT skipped intentionally. Snapshot in
 * selection_applications.pmi_memberships JSONB still persists.
 */
export async function findPersonIdByEmail(
  db: SupabaseClient,
  email: string
): Promise<string | null> {
  if (!email) return null;
  const lowerEmail = email.toLowerCase().trim();

  // Strategy 1: primary email
  const { data: byPrimary } = await db
    .from('members')
    .select('person_id')
    .eq('email', lowerEmail)
    .not('person_id', 'is', null)
    .limit(1)
    .maybeSingle();

  if (byPrimary?.person_id) return byPrimary.person_id as string;

  // Strategy 2: secondary_emails (text[] array contains)
  const { data: bySecondary } = await db
    .from('members')
    .select('person_id')
    .contains('secondary_emails', [lowerEmail])
    .not('person_id', 'is', null)
    .limit(1)
    .maybeSingle();

  return (bySecondary?.person_id as string) ?? null;
}

/**
 * Wave 3a-iii (#740 / ADR-0104) — populate member_chapter_affiliations from the
 * reliable pmi_memberships snapshot for a resolved person.
 *
 * For each BR ("<State>, Brazil Chapter") membership we resolve the chapter_registry
 * code and call the SECURITY DEFINER RPC upsert_chapter_affiliation with
 * is_primary=false: the worker asserts which chapters a person belongs to (FACT), it
 * never decides the headline. The RPC owns the one-primary invariant (it preserves the
 * legacy backfill / the future entry_chapter choice, and only promotes a provisional
 * primary when the person has none). Non-BR entries ("PMI Global", "Washington, DC
 * Chapter", "Angola Chapter") are skipped — chapter_registry is BR-only.
 *
 * Idempotent (ON CONFLICT upsert in the RPC). Tolerates both the runtime shape (an
 * array of plain name strings, as actually stored in selection_applications.pmi_memberships)
 * and the declared { chapterName } object shape. Returns the count of affiliations upserted.
 */
export async function upsertChapterAffiliations(
  db: SupabaseClient,
  personId: string,
  memberships: unknown
): Promise<number> {
  if (!Array.isArray(memberships) || memberships.length === 0) return 0;

  const codes = new Set<string>();
  for (const m of memberships) {
    const name =
      typeof m === 'string'
        ? m
        : (m && typeof m === 'object' ? ((m as any).chapterName ?? null) : null);
    const code = parseBrChapterCode(name);
    if (code) codes.add(code);
  }
  if (codes.size === 0) return 0;

  let upserted = 0;
  for (const code of codes) {
    const { error } = await db.rpc('upsert_chapter_affiliation', {
      p_person_id: personId,
      p_chapter_code: code,
      p_source: 'pmi_vep',
      p_is_primary: false
    });
    if (error) {
      throw new Error(`upsertChapterAffiliations(${code}): ${error.message}`);
    }
    upserted++;
  }
  return upserted;
}

/**
 * UPSERT service_history rows with idempotency guard.
 * Wave 3 synth Wave 2 BLOCKER fix (3-agent convergent):
 *   - Migration 7 (20260518070000) added UNIQUE INDEX on
 *     (application_id, chapter_name, COALESCE(start_date, '1900-01-01'))
 *   - Re-ingest produces no duplicates: ON CONFLICT IGNORE
 * Append-only semantic preserved (no field updates), but row creation is idempotent.
 */
export async function insertServiceHistory(
  db: SupabaseClient,
  rows: ServiceHistoryInsert[]
): Promise<number> {
  if (rows.length === 0) return 0;

  const { error, count } = await db
    .from('selection_application_service_history')
    .upsert(rows, {
      onConflict: 'application_id,chapter_name,start_date',
      ignoreDuplicates: true,
      count: 'exact'
    });

  if (error) {
    throw new Error(`insertServiceHistory: ${error.message}`);
  }
  return count ?? rows.length;
}

/**
 * Set engagements.metadata.end_date_source flag for a person's active engagements.
 * Used by E2 worker for Decision 8 (Issue D fallback strategy):
 *   - 'agreement' if agreement_certificate_id present (handled by Hotfix Wave 0)
 *   - 'pmi_vep' if PMI VEP serviceEndDateUTC available
 *   - 'estimated' last resort with current_date + 6 months
 *
 * Returns count of rows updated. Idempotent — only updates if source not already set.
 */
export async function setEngagementEndDateSource(
  db: SupabaseClient,
  personId: string,
  source: 'agreement' | 'pmi_vep' | 'estimated' | 'manual',
  endDate?: string | null
): Promise<number> {
  const { data: rows, error: queryErr } = await db
    .from('engagements')
    .select('id, metadata, end_date')
    .eq('person_id', personId)
    .eq('status', 'active');

  if (queryErr) {
    throw new Error(`setEngagementEndDateSource query: ${queryErr.message}`);
  }
  if (!rows || rows.length === 0) return 0;

  let updated = 0;
  for (const row of rows) {
    const meta = (row.metadata ?? {}) as Record<string, any>;
    // p131 T-3 C3 step 3: refinar guard. Era "skip se source='agreement'" mas
    // Hotfix Wave 0 marcou agreement source SEM popular end_date — gap inicial.
    // p131 backfill (C3 step 2) populou end_date com placeholder agreement_issued_at+365d.
    // Permitimos PMI VEP sobrescrever quando:
    //   (a) end_date IS NULL (Hotfix incompleto, ou nunca rodou)
    //   (b) metadata.end_date_placeholder=true (placeholder C3 step 2 — VEP é mais preciso)
    // Skip apenas quando há end_date REAL agreement-confirmed (não placeholder).
    if (meta.end_date_source === 'agreement'
        && row.end_date !== null
        && meta.end_date_placeholder !== true) continue;
    // Wave 3 synth (D-CONV-1): skip only if same source AND same endDate already stored
    // (avoids redundant DB writes on re-import). Prior `!endDate` check was too narrow.
    if (meta.end_date_source === source && row.end_date === endDate) continue;

    const newMeta = {
      ...meta,
      end_date_source: source,
      end_date_source_set_at: new Date().toISOString(),
      end_date_source_set_by: 'pmi-vep-sync-e2'
    };
    if (meta.end_date_pending) delete (newMeta as any).end_date_pending;
    // p131 T-3 C3 step 3: ao receber dado real (pmi_vep), remover flag placeholder
    if (source === 'pmi_vep' && meta.end_date_placeholder) {
      delete (newMeta as any).end_date_placeholder;
      delete (newMeta as any).end_date_placeholder_set_at;
      delete (newMeta as any).end_date_placeholder_source;
      delete (newMeta as any).end_date_placeholder_basis_cert_id;
    }

    const updatePayload: Record<string, any> = { metadata: newMeta };
    if (endDate && source === 'pmi_vep') {
      updatePayload.end_date = endDate;
    }

    const { error: updErr } = await db
      .from('engagements')
      .update(updatePayload)
      .eq('id', row.id);

    if (updErr) {
      console.error(`setEngagementEndDateSource update failed for ${row.id}:`, updErr.message);
      continue;
    }
    updated++;
  }
  return updated;
}
