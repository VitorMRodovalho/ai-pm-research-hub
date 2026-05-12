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
  ScriptServiceHistoryRow,
  VepOpportunityRow,
  SelectionApplicationUpsert,
  PmiChapterMembershipUpsert,
  ServiceHistoryInsert
} from './types';

// ORG_ID_DEFAULT is a fallback used ONLY when caller omits orgId argument
// (test scenarios without env binding). Production caller (index.ts handleIngest)
// always passes env.ORG_ID. Never edit this UUID without updating wrangler config.
const ORG_ID_DEFAULT = '2b4f58ab-7c45-4170-8718-b77ee69ff906';

export function mapScriptToNucleo(
  app: ScriptApplication,
  opp: VepOpportunityRow,
  allQuestionResponses: ScriptQuestionResponse[],
  cycleId: string,
  cycleCode: string = '',
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

  // ─── p126 E2: Phase B field handling per ADR-0076 + Decision 5 ────────────
  const isPhaseBPrivate = app.profilePrivate === true;

  // Decision 5 enforcement (defense-in-depth): if profilePrivate=true, NULL all profile_* fields
  // RPC import_vep_applications also re-clears (atomicity Princípio 11), but mapper does it first.
  const phaseBLocation = isPhaseBPrivate ? null : (app.profileLocation ?? null);
  const phaseBState = isPhaseBPrivate ? null : (app.profileState ?? null);
  const phaseBCity = isPhaseBPrivate ? null : (app.profileCity ?? null);
  const phaseBCountry = isPhaseBPrivate ? null : (app.profileCountry ?? null);
  // p150 worker patch — PMI Community API often returns profileMembershipChapters
  // as a double-encoded JSON STRING (e.g. "[\"PMI Global\",\"Ceará, Brazil Chapter\"]")
  // instead of a real array. Sediment: feedback_pmi_community_double_encoded_json.md (p125).
  // Prior code did `?? null` only — when value was a string, it landed in jsonb
  // as a JSON string scalar (jsonb_typeof='string'), not an array. The DB ended up
  // with NULL/string but never the array, so pmi_canonical chapter derivation failed.
  // Now we parse: array → use as-is; string → JSON.parse; anything else → null.
  const phaseBMemberships = isPhaseBPrivate ? null : parseMaybeJsonArray(app.profileMembershipChapters) as Array<{ chapterName: string; expiryDate: string }> | null;
  const phaseBIndustry = isPhaseBPrivate ? null : (app.profileIndustry ?? null);
  const phaseBCompany = isPhaseBPrivate ? null : (app.profileCompany ?? null);
  const phaseBDesignation = isPhaseBPrivate ? null : (app.profileDesignation ?? null);
  // p150 worker patch (2026-05-12 hotfix5) — profileCertifications arrives from
  // PMI Community as a comma-separated STRING ("PMP" / "" / "PMP,PMI-RMP,PMO-CP").
  // Two DB columns receive this:
  //   - certifications (text)        → keep the raw CSV string (text column)
  //   - profile_certifications (text[]) → parse into array (text[] column)
  // The direct assignment to profile_certifications caused 25/32 cycle 4 UPDATE
  // errors with "malformed array literal". Sediment: profileMembershipChapters
  // has the same class of issue (see parseMaybeJsonArray double-encoded fix).
  const phaseBCertsString = isPhaseBPrivate ? null : (app.profileCertifications ?? null);
  const phaseBCertsArray = isPhaseBPrivate ? null : parseMaybeCsvArray(app.profileCertifications);
  const phaseBVolInterest = isPhaseBPrivate ? null : (app.profileVolunteerInterest ?? null);
  const phaseBSpecialties = isPhaseBPrivate ? null : (app.profileSpecialties ?? null);
  const phaseBLinkedin = isPhaseBPrivate ? null : (app.profileLinkedinUrl ?? null);
  const phaseBAboutMe = isPhaseBPrivate ? null : (app.profileAboutMe ?? null);
  const phaseBSvcCount = isPhaseBPrivate ? null : (app.serviceHistoryCount ?? null);
  const phaseBSvcChapters = isPhaseBPrivate ? null : (app.serviceHistoryChapters ?? null);
  const phaseBSvcFirst = isPhaseBPrivate ? null : (app.serviceFirstStartDate ?? null);
  const phaseBSvcLatest = isPhaseBPrivate ? null : (app.serviceLatestEndDate ?? null);
  const phaseBOpenToVol = isPhaseBPrivate ? null : (app.isOpenToVolunteer ?? null);

  // Wave 3 synth fix (3-agent convergent S-CONV-2): geo fallback when script
  // sent only profileLocation raw without parsed profileState/City/Country.
  // parseGeoFromLocation handles common patterns ("Cidade, Estado, País").
  let phaseBStateResolved = isPhaseBPrivate ? null : (app.profileState ?? null);
  let phaseBCityResolved = isPhaseBPrivate ? null : (app.profileCity ?? null);
  let phaseBCountryResolved = isPhaseBPrivate ? null : (app.profileCountry ?? null);
  if (!isPhaseBPrivate && app.profileLocation && !phaseBStateResolved && !phaseBCityResolved && !phaseBCountryResolved) {
    const parsed = parseGeoFromLocation(app.profileLocation);
    phaseBStateResolved = parsed.state;
    phaseBCityResolved = parsed.city;
    phaseBCountryResolved = parsed.country;
  }

  // Decision 4 — consent_version: prefer script-provided (Cycle 4+ termo-v3 dispatch),
  // fallback to Cycle 3 default termo-v2-${cycle_code}.
  // Wave 3 synth fix (3-agent convergent): backwards-compatible payload read
  const consentVersion = app.consentVersion ?? `termo-v2-${cycleCode || 'unknown'}`;

  // applicant_city: prefer resolved Phase B (parsed if needed), fallback Phase A applicantCity.
  // Wave 3 synth fix (data-architect D5): NÃO usar applicantState como fallback (UF != city).
  const applicantCity = isPhaseBPrivate
    ? null
    : (phaseBCityResolved ?? app.applicantCity ?? null);

  return {
    cycle_id: cycleId,
    vep_application_id: String(app.applicationId),
    vep_opportunity_id: String(app._opportunityId),
    pmi_id: app.applicantId ? String(app.applicantId) : null,
    applicant_name: app.applicantName ?? '',
    email: app.applicantEmail ?? '',
    phone: null,  // PMI doesn't surface phone via /api/applications/{id}
    linkedin_url: extractLinkedinFromText(coverLetterText) ?? phaseBLinkedin ?? null,
    resume_url: app.resumeUrl ?? null,
    chapter: parseChapterFromAffiliation(
      responses.chapter_affiliation ?? '',
      app.applicantState ?? '',
      app.applicantCountry ?? ''
    ),
    membership_status: null,
    // p150 P0 (2026-05-12): capture VEP raw status for reconciliation report.
    // Used by get_vep_divergence_report() to surface 3-lifecycle drift between
    // VEP and Núcleo (selection / onboarding / active member offboarded).
    // Source of truth for VEP-side. Compare with selection_applications.status
    // (Núcleo-side) to flag divergence.
    vep_status_raw: app.status ?? null,
    vep_last_seen_at: new Date().toISOString(),
    // Wave 3 synth fix (S-CONV-3 — 2 agents): null-semantic consistency vs empty string
    certifications: phaseBCertsString ?? null,
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
    organization_id: orgId,

    // ─── Phase B fields (use resolved geo per Wave 3 fallback fix) ────────
    applicant_city: applicantCity,
    profile_location: phaseBLocation,
    profile_state: phaseBStateResolved,
    profile_city: phaseBCityResolved,
    profile_country: phaseBCountryResolved,
    pmi_memberships: phaseBMemberships,
    profile_industry: phaseBIndustry,
    profile_company: phaseBCompany,
    profile_designation: phaseBDesignation,
    profile_certifications: phaseBCertsArray,
    profile_volunteer_interest: phaseBVolInterest,
    profile_specialties: phaseBSpecialties,
    profile_linkedin_url: phaseBLinkedin,
    profile_about_me: phaseBAboutMe,
    service_history_count: phaseBSvcCount,
    service_history_chapters: phaseBSvcChapters,
    service_first_start_date: phaseBSvcFirst,
    service_latest_end_date: phaseBSvcLatest,
    is_open_to_volunteer: phaseBOpenToVol,
    community_profile_private: isPhaseBPrivate,
    pmi_data_fetched_at: app.pmiDataFetchedAt ?? null,
    consent_version: consentVersion
  };
}

/**
 * p126 E2 — Map PMI Community profileMembershipChapters to canonical pmi_chapter_memberships
 * rows for UPSERT into the canonical table.
 *
 * Decision 2 (hybrid storage): selection_applications.pmi_memberships JSONB is the
 * snapshot at submission (immutable); pmi_chapter_memberships table is the canonical
 * live registry queried by E3 cron compliance.
 *
 * Returns empty array if profilePrivate=true (Decision 5) or no memberships data.
 *
 * @param app ScriptApplication with optional profileMembershipChapters
 * @param personId UUID of persons row (resolved by caller via email lookup)
 */
export function mapPmiChapterMemberships(
  app: ScriptApplication,
  personId: string
): PmiChapterMembershipUpsert[] {
  if (app.profilePrivate === true) return [];
  const memberships = app.profileMembershipChapters;
  if (!memberships || !Array.isArray(memberships) || memberships.length === 0) return [];

  const capturedAt = app.pmiDataFetchedAt ?? new Date().toISOString();

  return memberships
    .filter(m => m && typeof m.chapterName === 'string' && typeof m.expiryDate === 'string')
    .map(m => ({
      person_id: personId,
      chapter_name: m.chapterName.trim(),
      expiry_date: m.expiryDate.slice(0, 10),  // ensure YYYY-MM-DD
      source: 'pmi_community' as const,
      captured_at: capturedAt
    }));
}

/**
 * p126 E2 — Map serviceHistory rows from script payload to ServiceHistoryInsert
 * for INSERT into selection_application_service_history (1:N append-only).
 *
 * Filters by applicationId + skips empty/malformed rows. profilePrivate users get
 * empty array per Decision 5 (defense-in-depth — script may not have sent rows
 * for them anyway, but mapper enforces).
 *
 * @param app ScriptApplication (for profilePrivate check + applicationId match)
 * @param dbApplicationId UUID from selection_applications row (post-upsert)
 * @param allHistory Full payload.serviceHistory array
 */
export function mapServiceHistory(
  app: ScriptApplication,
  dbApplicationId: string,
  allHistory: ScriptServiceHistoryRow[] | undefined
): ServiceHistoryInsert[] {
  if (app.profilePrivate === true) return [];
  if (!allHistory || !Array.isArray(allHistory) || allHistory.length === 0) return [];

  const myRows = allHistory.filter(h =>
    String(h.applicationId) === String(app.applicationId)
  );
  if (myRows.length === 0) return [];

  const capturedAt = app.pmiDataFetchedAt ?? new Date().toISOString();

  return myRows
    .filter(h => h && typeof h.chapterName === 'string' && h.chapterName.trim().length > 0)
    .map(h => ({
      application_id: dbApplicationId,
      chapter_name: h.chapterName.trim(),
      role_name: h.roleName?.trim() ?? null,
      start_date: h.startDate ? h.startDate.slice(0, 10) : null,
      end_date: h.endDate ? h.endDate.slice(0, 10) : null,
      source: 'pmi_community' as const,
      captured_at: capturedAt
    }));
}

/**
 * p126 E2 — Parse profileLocation free text "Cidade, Estado, País" into structured.
 *
 * Examples:
 *   "Saquarema, RJ, Brazil" → { city: "Saquarema", state: "RJ", country: "Brazil" }
 *   "São Paulo, SP, Brazil" → { city: "São Paulo", state: "SP", country: "Brazil" }
 *   "Fortaleza, CE, Brazil" → { city: "Fortaleza", state: "CE", country: "Brazil" }
 *   "Washington DC, United States" → { city: "Washington DC", state: null, country: "United States" }
 *
 * Returns nulls when parse fails. Worker mapper prefers script-parsed profileState/City/Country
 * (already structured by browser script); this helper is for fallback when only profileLocation is present.
 */
/**
 * p150 worker patch — parse PMI Community API double-encoded JSON values.
 * PMI Community returns array-typed fields as JSON-encoded strings, not real arrays
 * (e.g. profileMembershipChapters: "[\"PMI Global\",\"Ceará, Brazil Chapter\"]").
 * Sediment: feedback_pmi_community_double_encoded_json.md (p125).
 * - Already an array → return as-is.
 * - String → JSON.parse; if parse OK and result is an array, return it; else null.
 * - Anything else → null.
 */
/**
 * p150 worker patch (hotfix5) — parse a comma-separated string into a real
 * string array, suitable for text[] DB columns. PMI Community returns fields
 * like profileCertifications as "PMP,PMI-RMP,PMO-CP" (CSV) or "" (empty).
 * Empty string → null (so the column stays NULL instead of [""]).
 * Already an array → return as-is (filtered for empty entries).
 * Anything else → null.
 */
export function parseMaybeCsvArray(value: unknown): string[] | null {
  if (value == null) return null;
  if (Array.isArray(value)) {
    const cleaned = value.map(v => typeof v === 'string' ? v.trim() : String(v).trim()).filter(s => s !== '');
    return cleaned.length > 0 ? cleaned : null;
  }
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (trimmed === '') return null;
    const parts = trimmed.split(',').map(s => s.trim()).filter(s => s !== '');
    return parts.length > 0 ? parts : null;
  }
  return null;
}

export function parseMaybeJsonArray(value: unknown): unknown[] | null {
  if (value == null) return null;
  if (Array.isArray(value)) return value;
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (trimmed === '' || trimmed === '[]') return null;
    try {
      const parsed = JSON.parse(trimmed);
      return Array.isArray(parsed) ? parsed : null;
    } catch {
      return null;
    }
  }
  return null;
}

export function parseGeoFromLocation(loc: string | null | undefined): {
  city: string | null;
  state: string | null;
  country: string | null;
} {
  if (!loc || typeof loc !== 'string') {
    return { city: null, state: null, country: null };
  }
  const parts = loc.split(',').map(p => p.trim()).filter(Boolean);
  if (parts.length === 0) return { city: null, state: null, country: null };
  if (parts.length === 1) return { city: parts[0]!, state: null, country: null };
  if (parts.length === 2) return { city: parts[0]!, state: null, country: parts[1]! };
  // 3+ parts — assume city, state, country (extra ignored)
  return { city: parts[0]!, state: parts[1]!, country: parts[2]! };
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
