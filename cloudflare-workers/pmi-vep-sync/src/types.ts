/**
 * Shared types for pmi-vep-sync worker.
 */

// =====================================================================
// Cloudflare Worker bindings (env)
// =====================================================================

export interface Env {
  // Vars
  CRON_CADENCE_HOURS: string;
  CRON_TOLERANCE_HOURS: string;
  CONSECUTIVE_FAILURE_ALERT_THRESHOLD: string;
  ORG_ID: string;
  ONBOARDING_TOKEN_TTL_DAYS: string;

  // Secrets
  SUPABASE_URL: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
  PMI_VEP_BASE_URL: string;
  PMI_VEP_OAUTH_TOKEN_URL: string;
  PMI_VEP_OAUTH_CLIENT_ID: string;
  PMI_VEP_OAUTH_CLIENT_SECRET: string;
  GP_NOTIFICATION_EMAIL: string;
  ONBOARDING_BASE_URL: string;

  // KV namespaces
  PMI_OAUTH_KV: KVNamespace;

  // Queue producers (opcionais em S0)
  QUEUE_AI_OBJECTIVE_DRAFTER?: Queue<{ application_id: string }>;
  QUEUE_WELCOME_DISPATCHER?: Queue<{ application_id: string; token: string }>;
}

// =====================================================================
// PMI OAuth — refresh_token cached em KV (Plano B per p81 review)
// =====================================================================

export interface PmiOAuthTokens {
  access_token: string;
  refresh_token: string;
  expires_at: number;        // ms epoch
  refreshed_at: number;      // ms epoch — when we last called /token
  initialized_by?: string;   // e.g., 'manual_seed_2026_04_29' for audit
}

// =====================================================================
// Domain — PMI VEP API responses (subset relevante)
// =====================================================================

export interface VepOpportunityRow {
  opportunity_id: string;
  title: string;
  chapter_posted: string | null;
  role_default: 'leader' | 'researcher' | 'manager' | string;
  essay_mapping: Record<string, { field: string; question: string }> | null;
  vep_url: string | null;
  is_active: boolean;
}

export interface VepApplicationListItem {
  applicationId: number | string;
  applicantId: number | string;
  applicantEmail: string;
  applicantName: string;
  status?: string;
}

export interface VepApplicationDetail {
  applicationId: number | string;
  applicantId: number | string;
  applicantEmail: string;
  applicantName: string;
  status: string;
  applicationDate?: string;
  resumeUrl?: string;
  linkedinUrl?: string;
  phone?: string;
  certifications?: string[];
  membershipStatus?: string;
  nonPMIExperience?: string;
  questionResponses?: VepQuestionResponse[];
  coverLetterInfo?: {
    coverLetter?: string;
    linkedinUrl?: string;
  };
  declinedByRecruiterDateUtc?: string;
  declinedByVolunteerDateUtc?: string;
  applicationWithdrawnDateUtc?: string;
  roleRemovedDateUtc?: string;
  offerExpiredDateUtc?: string;
  applicationExpiredDateUtc?: string;
}

export interface VepQuestionResponse {
  questionNumber?: number;
  questionIndex?: number;
  questionText?: string;
  responseText?: string;
  answer?: string;
}

// =====================================================================
// Domain — Núcleo selection_applications shape (subset usado pelo mapper)
// =====================================================================

export interface SelectionApplicationUpsert {
  cycle_id: string;
  vep_application_id: string;
  vep_opportunity_id: string;
  pmi_id: string | null;
  applicant_name: string;
  email: string;
  phone: string | null;
  linkedin_url: string | null;
  resume_url: string | null;
  chapter: string | null;
  membership_status: string | null;
  certifications: string | null;
  role_applied: string;
  motivation_letter: string | null;
  proposed_theme: string | null;
  areas_of_interest: string | null;
  availability_declared: string | null;
  leadership_experience: string | null;
  academic_background: string | null;
  chapter_affiliation: string | null;
  non_pmi_experience: string | null;
  reason_for_applying: string | null;
  application_date: string | null;
  status: string;
  imported_at: string;
  organization_id: string;
}

// =====================================================================
// Cron run logging
// =====================================================================

export interface CronRunMetrics {
  trigger_reason?: string;
  opportunities_processed: number;
  applications_new: number;
  applications_updated: number;
  applications_skipped_not_partner: number;
  welcome_messages_dispatched: number;
  drafts_dispatched: number;
  errors: Array<{ scope: string; ref?: string; error: string }>;
}

export interface SchedulerDecision {
  run: boolean;
  reason: string;
  hours_since_last_success: number | null;
}
