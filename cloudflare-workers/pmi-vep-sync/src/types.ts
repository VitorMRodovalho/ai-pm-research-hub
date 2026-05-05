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
  INGEST_SHARED_SECRET: string;

  // KV namespaces
  PMI_OAUTH_KV: KVNamespace;

  // Queue producers (opcionais em S0)
  QUEUE_AI_OBJECTIVE_DRAFTER?: Queue<{ application_id: string }>;
  QUEUE_WELCOME_DISPATCHER?: Queue<{ application_id: string; token: string }>;
}

// =====================================================================
// PMI OAuth — access_token cached em KV (Plano B-revised per HAR analysis)
//
// IMPORTANT: PMI vep_ui app NÃO emite refresh_token (escopo `openid profile`
// only — sem `offline_access`). Worker opera em access-only mode: lê
// access_token do KV, alerta proativamente quando expires_at < now + 6h,
// falha clean quando token expira. PM precisa re-seedar a cada ~24h.
//
// Long-term fix: PM contata PMI IT para adicionar offline_access scope ao
// vep_ui app, OU registra app dedicado nucleo_pmi_sync com offline_access.
// =====================================================================

export interface PmiOAuthTokens {
  access_token: string;
  refresh_token?: string;    // OPCIONAL — só presente se PMI conceder offline_access (futuro)
  expires_at: number;        // ms epoch
  refreshed_at: number;      // ms epoch — when seed/refresh aconteceu
  initialized_by?: string;   // e.g., 'manual_seed_2026_04_29_vitor' para audit trail
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

// =====================================================================
// Ingest endpoint — JSON output do extract_pmi_volunteer.js (browser script)
// =====================================================================

export interface ScriptApplication {
  _opportunityId: number | string;
  _bucket: 'submitted' | 'qualified' | 'rejected';
  applicationId: number | string;
  applicantId: number | string;
  applicantName: string;
  applicantEmail: string;
  status?: string;
  statusId?: number;
  applicantCity?: string;
  applicantState?: string;
  applicantCountry?: string;
  submittedDateUtc?: string;
  expiryDateUtc?: string;
  resumeUrl?: string;
  profileUrl?: string;
  label?: string;
  // From detail call:
  coverLetterInfo?: { coverLetter?: string; linkedinUrl?: string };
  nonPMIExperience?: string;
  // Lifecycle timestamps (rejected bucket):
  declinedByRecruiterDateUtc?: string;
  declinedByVolunteerDateUtc?: string;
  applicationWithdrawnDateUtc?: string;
  roleRemovedDateUtc?: string;
  offerExpiredDateUtc?: string;
  applicationExpiredDateUtc?: string;
  // Other detail fields
  formsSentDateUTC?: string;
  formsSignedDateUTC?: string;
  acceptanceDateUTC?: string;
  declinedDateUTC?: string;
  declinedBy?: string;
  withdrawnDateUTC?: string;
  removedDateUTC?: string;
  onboardingDateUTC?: string;
  activeDateUTC?: string;
  serviceStartDateUTC?: string;
  serviceEndDateUTC?: string;
  specialInterest?: string;
  // Allow other fields from script
  [key: string]: any;
}

export interface ScriptQuestionResponse {
  applicationId: number | string;
  applicantId?: number | string;
  applicantEmail?: string;
  opportunityId?: number | string;
  responseId?: number | string;
  questionId: number | string;
  question?: string;
  response?: string;
}

export interface ScriptOpportunity {
  opportunityId: number | string;
  name?: string;
  chapterName?: string;
  status?: string;
  classification?: string;
  numberOfApplications?: number;
}

export interface ScriptIngestPayload {
  meta?: { extractedAt?: string; recruiter?: any; opportunityIds?: any };
  opportunities?: ScriptOpportunity[];
  applications: ScriptApplication[];
  questionResponses?: ScriptQuestionResponse[];
}

export interface IngestSummary {
  cycle_id: string;
  cycle_code: string;
  applications_received: number;
  applications_processed: number;
  applications_new: number;
  applications_updated: number;
  applications_skipped: number;
  applications_skipped_prior_cycle: number;  // existing in different (closed) cycle
  welcome_dispatched: number;
  welcomes_skipped_non_submitted: number;    // _bucket != 'submitted' OR statusId != 2 (qualified leaders + rejected)
  errors: Array<{ scope: string; ref?: string; error: string }>;
  pmi_token_expiring_soon?: boolean;
}
