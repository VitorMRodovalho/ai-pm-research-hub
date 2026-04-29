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

  // PMI returns coverLetterInfo as a STRING (the cover letter text) — not an object.
  // (Verified via HAR + script JSON inspection 2026-04-29.) The earlier assumption
  // of `{coverLetter, linkedinUrl}` from spec was wrong; spec was based on docs that
  // don't match runtime shape.
  const coverLetterText: string | null =
    typeof app.coverLetterInfo === 'string'
      ? app.coverLetterInfo
      : ((app.coverLetterInfo as any)?.coverLetter ?? null);

  return {
    cycle_id: cycleId,
    vep_application_id: String(app.applicationId),
    vep_opportunity_id: String(app._opportunityId),
    pmi_id: app.applicantId ? String(app.applicantId) : null,
    applicant_name: app.applicantName ?? '',
    email: app.applicantEmail ?? '',
    phone: null,  // PMI doesn't surface phone via /api/applications/{id}
    linkedin_url: extractLinkedinFromText(coverLetterText) ?? null,
    resume_url: app.resumeUrl ?? null,
    chapter: parseChapterFromAffiliation(
      responses.chapter_affiliation ?? '',
      app.applicantState ?? '',
      app.applicantCountry ?? ''
    ),
    membership_status: null,
    certifications: '',
    role_applied: opp.role_default,
    motivation_letter: responses.motivation_letter ?? coverLetterText,
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
      coverLetterText,
    application_date: applicationDate ? applicationDate.slice(0, 10) : null,
    status,
    imported_at: new Date().toISOString(),
    organization_id: orgId
  };
}

/**
 * Extract LinkedIn URL from free text (cover letter, etc).
 * Common forms: linkedin.com/in/<slug>, /pub/<slug>, /profile/<slug>, lnkd.in/...
 */
function extractLinkedinFromText(text: string | null): string | null {
  if (!text) return null;
  const m = text.match(/https?:\/\/(?:[a-z]{2,3}\.)?linkedin\.com\/[a-z]+\/[A-Za-z0-9_\-%]+/i)
        ?? text.match(/https?:\/\/lnkd\.in\/[A-Za-z0-9_\-%]+/i);
  return m ? m[0] : null;
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
 * 1. PMI-XX / PMI_XX / PMI/XX / PMI XX patterns
 * 2. Full state name (Goiás, Minas Gerais, ...)
 * 3. Standalone UF abbreviation (GO, MG, ...) with word boundary, but ONLY if
 *    affiliation doesn't start with "Não" / "ainda não" / "atualmente não"
 *    (ie, candidate explicitly says they aren't affiliated)
 * 4. Fallback to applicantState mapping
 *
 * Returns null when ambiguous ("MG e DF") or explicitly-not-affiliated.
 */
function parseChapterFromAffiliation(
  affiliation: string,
  state: string,
  _country: string
): string | null {
  const aff = (affiliation || '').trim();
  const affLower = aff.toLowerCase();

  // Strategy 1: explicit PMI-XX / PMI_XX / PMI/XX / PMI XX
  const pmiMatch = aff.match(/PMI[-\s_/]([A-Z]{2,3})\b/i);
  if (pmiMatch) return `PMI-${pmiMatch[1]!.toUpperCase()}`;

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
  const UF_TO_CHAPTER: Record<string, string> = {
    GO: 'PMI-GO', DF: 'PMI-DF', MG: 'PMI-MG', RS: 'PMI-RS',
    CE: 'PMI-CE', PE: 'PMI-PE', SP: 'PMI-SP', RJ: 'PMI-RJ',
    PR: 'PMI-PR', SC: 'PMI-SC', BA: 'PMI-BA', ES: 'PMI-ES'
  };
  // Detect "não" / "ainda não" / "atualmente não" prefix — candidate is NOT affiliated
  const NEGATIVE_PREFIX = /^(n[aã]o|atualmente n[aã]o|ainda n[aã]o|j[aá] fui)\b/i;
  const isNegative = NEGATIVE_PREFIX.test(affLower);

  if (!isNegative) {
    // Strategy 2: full state name in affiliation
    for (const [name, chap] of Object.entries(STATE_FULL_TO_CHAPTER)) {
      if (affLower.includes(name)) return chap;
    }

    // Strategy 3: standalone UF abbreviation with word boundary in affiliation.
    // Only apply if EXACTLY ONE UF found (avoid "MG e DF" ambiguity).
    const ufMatches = new Set<string>();
    const ufRegex = /\b(GO|DF|MG|RS|CE|PE|SP|RJ|PR|SC|BA|ES)\b/g;
    let m;
    while ((m = ufRegex.exec(aff)) !== null) {
      ufMatches.add(m[1]!.toUpperCase());
    }
    if (ufMatches.size === 1) {
      const onlyUf = [...ufMatches][0]!;
      return UF_TO_CHAPTER[onlyUf] ?? null;
    }
  }

  // Strategy 4: applicantState (rarely populated by PMI per HAR analysis)
  if (state) {
    const sl = state.trim().toLowerCase();
    if (STATE_FULL_TO_CHAPTER[sl]) return STATE_FULL_TO_CHAPTER[sl];
    const upper = state.trim().toUpperCase();
    if (UF_TO_CHAPTER[upper]) return UF_TO_CHAPTER[upper];
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
