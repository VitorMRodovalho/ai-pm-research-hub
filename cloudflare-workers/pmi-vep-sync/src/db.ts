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

import type { SelectionApplicationUpsert } from './types';

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
        status: payload.status,
        imported_at: payload.imported_at,
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
