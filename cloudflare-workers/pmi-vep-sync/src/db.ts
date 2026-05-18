/**
 * Supabase client for the worker (service_role key, bypasses RLS).
 * SECURITY: Never expose this client outside the worker. service_role has full DB access.
 */

import { createClient, SupabaseClient } from '@supabase/supabase-js';
import type { Env, CronRunMetrics } from './types';

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
  PmiChapterMembershipUpsert,
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
    .select('id, cycle_id, consent_ai_analysis_at, consent_ai_analysis_revoked_at')
    .eq('vep_application_id', payload.vep_application_id)
    .eq('vep_opportunity_id', payload.vep_opportunity_id)
    .maybeSingle();

  if (existing) {
    // External-PMI-data refresh — fields that legitimately change post-cycle
    // (resume_url SAS rotation, profile data, certifications, chapter, VEP bucket).
    const commonRefresh = {
      pmi_id: payload.pmi_id,
      applicant_name: payload.applicant_name,
      email: payload.email,
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
        status: payload.status,
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
 * data (pmi_chapter_memberships) to identity model. Returns NULL if no person
 * found (= ghost case; mapper skips canonical UPSERT to preserve invariant
 * I_PMI_CHAPTER_MEMBERSHIPS_ORPHANS).
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
 * UPSERT pmi_chapter_memberships rows for a person. Per migration 2:
 * UNIQUE (person_id, chapter_name) + ON CONFLICT updates expiry_date + captured_at.
 *
 * Returns count of rows touched (UPSERT inserted + updated combined).
 */
export async function upsertPmiChapterMemberships(
  db: SupabaseClient,
  rows: PmiChapterMembershipUpsert[]
): Promise<number> {
  if (rows.length === 0) return 0;

  const { error, count } = await db
    .from('pmi_chapter_memberships')
    .upsert(rows, {
      onConflict: 'person_id,chapter_name',
      count: 'exact'
    });

  if (error) {
    throw new Error(`upsertPmiChapterMemberships: ${error.message}`);
  }
  return count ?? rows.length;
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
