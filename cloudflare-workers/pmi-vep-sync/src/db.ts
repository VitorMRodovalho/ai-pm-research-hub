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
  skipped_prior_cycle?: boolean;
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
 * CYCLE-AWARE BEHAVIOR (post incident 2026-04-29):
 * If existing.cycle_id != payload.cycle_id (i.e., row belongs to a PRIOR
 * closed cycle), the upsert is SKIPPED entirely to preserve historical
 * cycle outcome. PMI's bucket may have moved the app to "rejected" after
 * closing, but we don't want to overwrite our own status/role_applied/
 * cycle_id that captured the actual cycle decision (approved/converted/
 * triaged_to_leader). Same-cycle updates proceed normally.
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
    if (existing.cycle_id !== payload.cycle_id) {
      // Prior cycle: skip update to preserve history
      return {
        id: existing.id,
        was_new: false,
        consent_active: !!existing.consent_ai_analysis_at && !existing.consent_ai_analysis_revoked_at,
        skipped_prior_cycle: true,
        prior_cycle_id: existing.cycle_id
      };
    }

    const { error } = await db
      .from('selection_applications')
      .update({
        // cycle_id intentionally NOT updated (preserves history per cycle-aware behavior above)
        pmi_id: payload.pmi_id,
        applicant_name: payload.applicant_name,
        email: payload.email,
        phone: payload.phone,
        linkedin_url: payload.linkedin_url,
        resume_url: payload.resume_url,
        chapter: payload.chapter,
        membership_status: payload.membership_status,
        certifications: payload.certifications,
        role_applied: payload.role_applied,
        motivation_letter: payload.motivation_letter,
        proposed_theme: payload.proposed_theme,
        areas_of_interest: payload.areas_of_interest,
        availability_declared: payload.availability_declared,
        leadership_experience: payload.leadership_experience,
        academic_background: payload.academic_background,
        chapter_affiliation: payload.chapter_affiliation,
        non_pmi_experience: payload.non_pmi_experience,
        reason_for_applying: payload.reason_for_applying,
        // Wave 3 synth (S-DA-1): application_date refreshed on re-import
        // (PMI may move app across lifecycle timestamps — submitted/expired/withdrawn)
        application_date: payload.application_date,
        status: payload.status,
        imported_at: payload.imported_at,
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
        updated_at: new Date().toISOString()
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
