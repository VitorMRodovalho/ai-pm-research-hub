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
// p126 E2: extended com 22 Phase B fields per ADR-0076 Princípio 1 + Migration 1
// (20260518000000_p125_e1_selection_applications_pmi_3d_columns.sql)
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
  // p195 Opção B+: sustainable resume extraction (PDF mirrored to Supabase Storage).
  // resume_storage_path = "cycle-{cycle_code}/{applicantId}.pdf" when Worker
  // successfully downloaded from Azure SAS + uploaded to selection-resumes bucket.
  // NULL when download failed/skipped → frontend falls back to resume_url Azure link.
  resume_storage_path?: string | null;
  resume_synced_at?: string | null;
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

  // ─── p126 E2 Phase B fields (ADR-0076 Princípio 1) ─────────────────────────
  // Geographic (Phase B Community)
  applicant_city?: string | null;
  profile_location?: string | null;     // raw "Cidade, Estado, País"
  profile_state?: string | null;
  profile_city?: string | null;
  profile_country?: string | null;

  // Multi-chapter snapshot (Decision 2 hybrid)
  pmi_memberships?: Array<{ chapterName: string; expiryDate: string }> | null;

  // Phase B professional fields
  profile_industry?: string | null;
  profile_company?: string | null;
  profile_designation?: string | null;
  profile_certifications?: string[] | null;

  // p150 P0 (2026-05-12) — VEP raw status capture for reconciliation report.
  vep_status_raw?: string | null;
  vep_last_seen_at?: string | null;
  profile_volunteer_interest?: string | null;
  profile_specialties?: string | null;
  profile_linkedin_url?: string | null;

  // Phase B free-text bio (Decision 3 — store only, NOT in LLM Cycle 3)
  profile_about_me?: string | null;

  // Service history denormalized (snapshot-only, NOT cache — Decision S5)
  service_history_count?: number | null;
  service_history_chapters?: string | null;
  service_first_start_date?: string | null;
  service_latest_end_date?: string | null;

  // Ternary: true=open / false=not / NULL=unknown (Decision P3 — NUNCA em LLM)
  is_open_to_volunteer?: boolean | null;

  // Decision 5 — VEP-only treatment for profilePrivate users
  community_profile_private?: boolean;

  // Snapshot semantics
  pmi_data_fetched_at?: string | null;

  // Consent audit trail (Decision 4 — Cycle 3 freeze)
  consent_version?: string | null;
}

// =====================================================================
// p126 E2 — pmi_chapter_memberships (canonical 1:N) shape per ADR-0076
// (Migration 2: 20260518010000_p125_e1_pmi_chapter_memberships.sql)
// Source of truth for E3 cron compliance D-60/D-30/D-7 queries.
// =====================================================================

export interface PmiChapterMembershipUpsert {
  person_id: string;             // FK to persons.id
  chapter_name: string;          // NOT normalized to chapter_registry FK (per data-architect)
  chapter_id_pmi?: number | null; // optional PMI numeric ID
  expiry_date: string;           // YYYY-MM-DD; required
  source: 'pmi_community' | 'pmi_vep' | 'manual';
  captured_at: string;           // ISO timestamp
}

// =====================================================================
// p126 E2 — selection_application_service_history (1:N HISTÓRICA) shape
// (Migration 3: 20260518020000_p125_e1_service_history_table.sql)
// Append-only at submission. AI triage signal V2 Cycle 4+.
// =====================================================================

export interface ServiceHistoryInsert {
  application_id: string;
  chapter_name: string;
  role_name?: string | null;
  start_date?: string | null;
  end_date?: string | null;
  source: 'pmi_community' | 'pmi_vep' | 'manual';
  captured_at: string;
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

  // ─── p126 E2 Phase B fields (PMI Community profile scrape) ────────────────
  // All optional. profilePrivate=true → all profile* fields NULL/absent (Decision 5).
  // Camelcase here matches script output; mapper converts to snake_case for DB.
  profileLocation?: string | null;       // raw "Cidade, Estado, País"
  profileState?: string | null;
  profileCity?: string | null;
  profileCountry?: string | null;
  profileMembershipChapters?: Array<{ chapterName: string; expiryDate: string }> | null;
  profileIndustry?: string | null;
  profileCompany?: string | null;
  profileDesignation?: string | null;
  profileCertifications?: string | null;
  profileVolunteerInterest?: string | null;
  profileSpecialties?: string | null;
  profileLinkedinUrl?: string | null;
  profileAboutMe?: string | null;        // free-text bio — Decision 3: store but EXCLUDED from LLM
  serviceHistoryCount?: number | null;
  serviceHistoryChapters?: string | null;
  serviceFirstStartDate?: string | null;
  serviceLatestEndDate?: string | null;
  isOpenToVolunteer?: boolean | null;    // ternary — security-engineer R7
  profilePrivate?: boolean;              // true if HTTP 400 from Community API (Decision 5)
  pmiDataFetchedAt?: string | null;      // ISO timestamp Phase B fetch
  // Wave 3 synth fix (3-agent convergent): allow script to override consent_version
  // for Cycle 4+ payloads (`termo-v3-${cycle_code}`). Mapper falls back to default if absent.
  consentVersion?: string | null;

  // Allow other fields from script
  [key: string]: any;
}

// =====================================================================
// p126 E2 — Service history row from script payload
// One row per historical PMI volunteer role. Sent by extract_pmi_volunteer.js
// in the new payload.serviceHistory[] array.
// =====================================================================

export interface ScriptServiceHistoryRow {
  applicationId: number | string;        // FK to current application
  applicantId?: number | string;
  chapterName: string;
  roleName?: string | null;
  startDate?: string | null;             // YYYY-MM-DD
  endDate?: string | null;
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
  // p126 E2: serviceHistory rows (1:N, separated for clarity)
  serviceHistory?: ScriptServiceHistoryRow[];
  // p151 C: dry-run preview support (early exit with diff, no DML).
  // When true, /ingest returns IngestDryRunSummary instead of applying changes.
  dry_run?: boolean;
}

// p151 C: shape returned when /ingest is called with dry_run=true.
export interface IngestDryRunSummary {
  dry_run: true;
  cycle_id: string;
  cycle_code: string;
  applications_received: number;
  will_insert: Array<{
    applicant_name: string;
    email: string;
    opportunity_id: string;
    chapter: string | null;
    role_applied: string;
  }>;
  will_update: Array<{
    application_id: string;
    applicant_name: string;
    existing_cycle_id: string;
    existing_status: string;
    existing_role: string;
  }>;
  /** p153 hotfix7 — rows where existing.cycle_id != incoming.cycle_id; will
   *  receive a PARTIAL refresh (external PMI data only, decision history
   *  preserved). Separate from will_update so the admin preview UI can show
   *  the split before Apply. */
  will_cross_cycle_refresh: Array<{
    application_id: string;
    applicant_name: string;
    existing_cycle_id: string;
    existing_status: string;
    existing_role: string;
  }>;
  will_skip: Array<{ ref: string; reason: string }>;
  errors: Array<{ scope: string; ref?: string; error: string }>;
}

export interface IngestSummary {
  cycle_id: string;
  cycle_code: string;
  applications_received: number;
  applications_processed: number;
  applications_new: number;
  applications_updated: number;
  applications_skipped: number;
  /** p153 hotfix7 — kept for dashboard backward-compat. Always 0 going forward
   *  because cross-cycle apps now get partial refresh instead of full skip.
   *  See applications_cross_cycle_refreshed. */
  applications_skipped_prior_cycle: number;
  /** p153 hotfix7 — count of cross-cycle rows that received partial refresh
   *  (resume_url/SAS, profile_*, vep_status_raw, pmi_*, service_history_count)
   *  while preserving decision-history fields (cycle_id/status/role_applied/
   *  motivation_letter/application_date/imported_at). */
  applications_cross_cycle_refreshed: number;
  welcome_dispatched: number;
  welcomes_skipped_non_submitted: number;    // _bucket != 'submitted' OR statusId != 2 (qualified leaders + rejected)
  errors: Array<{ scope: string; ref?: string; error: string }>;
  pmi_token_expiring_soon?: boolean;

  // p126 E2 Phase B metrics
  phase_b_processed?: number;                // applications with Phase B data
  phase_b_skipped_private?: number;          // Decision 5 — profilePrivate=true
  pmi_chapter_memberships_upserted?: number;
  service_history_inserted?: number;

  // p195 Opção B+: resume binary mirror to Supabase Storage
  resumes_synced?: number;                   // PDFs downloaded from Azure + uploaded to bucket
  resumes_skipped_no_url?: number;           // applications with null resumeUrl (qualified bucket)
  resumes_failed?: number;                   // download or upload error — see errors[].scope='resume_sync_failed'

  // p195 BUG-195.B fix: count of applications redirected to a different cycle
  // based on application_date falling in a closed cycle's [open, close] window.
  // Closes the misassignment pattern where late-imported apps landed in current
  // open cycle when they semantically belonged to a prior closed cycle.
  applications_cycle_redirected?: number;
}
