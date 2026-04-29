/**
 * Mapper para output do extract_pmi_volunteer.js (browser script).
 *
 * O script roda no browser do PM logado no PMI VEP recruiter dashboard. Browser
 * session passa pelo Cloudflare Bot Management; cookies + UA real chegam ao
 * backend PMI. Saída: JSON estruturado com applications + questionResponses.
 *
 * Worker /ingest endpoint chama esse mapper para converter cada application
 * em SelectionApplicationUpsert.
 *
 * Difference vs spec mapper.ts (deprecated, originalmente para API server-to-server):
 * - questionResponses vem como GLOBAL array, filtramos por applicationId
 * - Field names diferentes (questionId/question/response vs questionNumber/...)
 * - Lifecycle timestamps mais ricos (15 fields vs ~8)
 * - applicantCity/State/Country disponíveis
 * - bucket discriminator '_bucket' indica funil PMI (submitted/qualified/rejected)
 */

import type {
  ScriptApplication,
  ScriptQuestionResponse,
  VepOpportunityRow,
  SelectionApplicationUpsert
} from './types';

const ORG_ID_DEFAULT = '2b4f58ab-7c45-4170-8718-b77ee69ff906';

export function mapScriptToNucleo(
  app: ScriptApplication,
  opp: VepOpportunityRow,
  allQuestionResponses: ScriptQuestionResponse[],
  cycleId: string,
  orgId: string = ORG_ID_DEFAULT
): SelectionApplicationUpsert {
  const myResponses = allQuestionResponses.filter(qr =>
    String(qr.applicationId) === String(app.applicationId)
  );

  const responses = extractResponsesFromScript(myResponses, opp);
  const status = mapBucketAndStatusToNucleo(app._bucket, app.status);
  const applicationDate =
    app.submittedDateUtc ??
    app.applicationExpiredDateUtc ??
    app.applicationWithdrawnDateUtc ??
    null;

  return {
    cycle_id: cycleId,
    vep_application_id: String(app.applicationId),
    vep_opportunity_id: String(app._opportunityId),
    pmi_id: app.applicantId ? String(app.applicantId) : null,
    applicant_name: app.applicantName ?? '',
    email: app.applicantEmail ?? '',
    phone: null,  // PMI script doesn't capture phone in current shape
    linkedin_url: app.coverLetterInfo?.linkedinUrl ?? null,
    resume_url: app.resumeUrl ?? null,
    chapter: parseChapterFromAffiliation(
      responses.chapter_affiliation ?? '',
      app.applicantState ?? '',
      app.applicantCountry ?? ''
    ),
    membership_status: null,
    certifications: '',  // not in script output (only in detail.certifications which we'd add to script if needed)
    role_applied: opp.role_default,
    motivation_letter: responses.motivation_letter
      ?? app.coverLetterInfo?.coverLetter
      ?? null,
    proposed_theme: responses.proposed_theme ?? null,
    areas_of_interest: responses.areas_of_interest ?? null,
    availability_declared: responses.availability_declared ?? null,
    leadership_experience: responses.leadership_experience ?? null,
    academic_background: responses.academic_background ?? null,
    chapter_affiliation: responses.chapter_affiliation ?? null,
    non_pmi_experience: app.nonPMIExperience ?? null,
    reason_for_applying:
      responses.motivation_letter ??
      responses.reason_for_applying ??
      app.coverLetterInfo?.coverLetter ??
      null,
    application_date: applicationDate ? applicationDate.slice(0, 10) : null,
    status,
    imported_at: new Date().toISOString(),
    organization_id: orgId
  };
}

/**
 * Extrai responses por essay_mapping field.
 * Strategy: try questionId match first, fall back to ordinal index, fall back to
 * question text substring match. Most resilient is ordinal (PMI returns
 * responses in question order).
 */
function extractResponsesFromScript(
  myResponses: ScriptQuestionResponse[],
  opp: VepOpportunityRow
): Record<string, string | null> {
  const mapping = (opp.essay_mapping ?? {}) as Record<string, { field: string; question: string }>;
  const out: Record<string, string | null> = {};

  // Sort essay_mapping keys numerically (1, 2, 3, 4...) to preserve PM intent
  const sortedKeys = Object.keys(mapping).sort((a, b) => {
    const ai = parseInt(a, 10);
    const bi = parseInt(b, 10);
    if (isNaN(ai) || isNaN(bi)) return a.localeCompare(b);
    return ai - bi;
  });

  for (let i = 0; i < sortedKeys.length; i++) {
    const key = sortedKeys[i]!;
    const m = mapping[key];
    if (!m) continue;

    let resp: ScriptQuestionResponse | undefined;

    // Strategy 1: exact match by questionId
    resp = myResponses.find(r => String(r.questionId) === key);

    // Strategy 2: ordinal index (questionResponses[i])
    if (!resp && i < myResponses.length) {
      resp = myResponses[i];
    }

    // Strategy 3: question text substring match (resilient if order changes)
    if (!resp && m.question) {
      const needle = m.question.substring(0, 40).toLowerCase();
      resp = myResponses.find(r => (r.question ?? '').toLowerCase().includes(needle));
    }

    out[m.field] = (resp?.response ?? null);
  }

  return out;
}

/**
 * Determine chapter slug. Priority:
 * 1. Parse from chapter_affiliation response (PMI-XX format expected)
 * 2. Fallback to applicantState mapping
 * 3. Fallback to country (BR detection)
 */
function parseChapterFromAffiliation(
  affiliation: string,
  state: string,
  _country: string
): string | null {
  // Parse "PMI-GO" / "PMI GO" / "Goiás Chapter" patterns from response
  const pmiMatch = affiliation.match(/PMI[-\s]([A-Z]{2,3})\b/i);
  if (pmiMatch) return `PMI-${pmiMatch[1]!.toUpperCase()}`;

  // Brazilian state full-name to PMI-XX mapping
  const STATE_FULL_TO_CHAPTER: Record<string, string> = {
    'goiás': 'PMI-GO', 'goias': 'PMI-GO',
    'distrito federal': 'PMI-DF',
    'minas gerais': 'PMI-MG',
    'rio grande do sul': 'PMI-RS',
    'ceará': 'PMI-CE', 'ceara': 'PMI-CE',
    'pernambuco': 'PMI-PE',
    'são paulo': 'PMI-SP', 'sao paulo': 'PMI-SP',
    'rio de janeiro': 'PMI-RJ',
    'paraná': 'PMI-PR', 'parana': 'PMI-PR',
    'santa catarina': 'PMI-SC',
    'bahia': 'PMI-BA',
    'espírito santo': 'PMI-ES', 'espirito santo': 'PMI-ES'
  };
  const STATE_ABBREV: Record<string, string> = {
    GO: 'PMI-GO', DF: 'PMI-DF', MG: 'PMI-MG', RS: 'PMI-RS',
    CE: 'PMI-CE', PE: 'PMI-PE', SP: 'PMI-SP', RJ: 'PMI-RJ',
    PR: 'PMI-PR', SC: 'PMI-SC', BA: 'PMI-BA', ES: 'PMI-ES'
  };

  if (state) {
    const sl = state.trim().toLowerCase();
    if (STATE_FULL_TO_CHAPTER[sl]) return STATE_FULL_TO_CHAPTER[sl];
    const upper = state.trim().toUpperCase();
    if (STATE_ABBREV[upper]) return STATE_ABBREV[upper];
    // Search affiliation for any state name
    for (const [name, chap] of Object.entries(STATE_FULL_TO_CHAPTER)) {
      if (sl.includes(name)) return chap;
    }
  }

  // Search affiliation text for state names too
  const aff = affiliation.toLowerCase();
  for (const [name, chap] of Object.entries(STATE_FULL_TO_CHAPTER)) {
    if (aff.includes(name)) return chap;
  }

  return null;
}

/**
 * Map (bucket, status) → selection_applications.status (CHECK constraint domain).
 *
 * DB CHECK: submitted | screening | objective_eval | objective_cutoff |
 *   interview_pending | interview_scheduled | interview_done | interview_noshow |
 *   final_eval | approved | rejected | waitlist | converted | withdrawn | cancelled
 */
function mapBucketAndStatusToNucleo(
  bucket: 'submitted' | 'qualified' | 'rejected' | string,
  status?: string
): string {
  const s = (status ?? '').toLowerCase();

  if (bucket === 'rejected') {
    if (s.includes('withdrawn') || s.includes('removed')) return 'withdrawn';
    return 'rejected';
  }
  if (bucket === 'qualified') {
    // Already-approved candidates from prior cycles or recruiter-qualified
    if (s.includes('approved') || s.includes('active') || s.includes('completed')) {
      return 'approved';
    }
    return 'approved';  // qualified bucket implies approved by recruiter
  }
  // Default: submitted bucket
  if (s.includes('submitted')) return 'submitted';
  if (s.includes('screen')) return 'screening';
  return 'submitted';
}
