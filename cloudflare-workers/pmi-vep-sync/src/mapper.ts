/**
 * Mapping PMI VEP detail → Núcleo selection_applications.
 *
 * Usa essay_mapping de vep_opportunities para saber quais perguntas do PMI
 * correspondem a quais campos do Núcleo (motivation_letter, proposed_theme,
 * leadership_experience, etc).
 */

import type {
  VepApplicationDetail,
  VepOpportunityRow,
  SelectionApplicationUpsert
} from './types';

const ORG_ID_DEFAULT = '2b4f58ab-7c45-4170-8718-b77ee69ff906';

/**
 * Mapeia PMI VEP detail para shape do upsert do Núcleo.
 *
 * Per migration 20260516200000 B1: role_applied agora aceita
 * researcher | leader | both | manager (vep_opportunities.role_default
 * pode passar 'manager' para opportunities GP).
 */
export function mapPmiToNucleo(
  detail: VepApplicationDetail,
  opp: VepOpportunityRow,
  cycleId: string,
  orgId: string = ORG_ID_DEFAULT
): SelectionApplicationUpsert {
  const responses = extractResponsesByEssayMapping(detail, opp);

  return {
    cycle_id: cycleId,
    vep_application_id: String(detail.applicationId),
    vep_opportunity_id: opp.opportunity_id,
    pmi_id: detail.applicantId ? String(detail.applicantId) : null,
    applicant_name: detail.applicantName,
    email: detail.applicantEmail,
    phone: detail.phone ?? null,
    linkedin_url: detail.linkedinUrl
      ?? detail.coverLetterInfo?.linkedinUrl
      ?? null,
    resume_url: detail.resumeUrl ?? null,
    chapter: parseChapterFromMembership(detail.membershipStatus ?? '')
          ?? normalizeChapterAffiliation(responses.chapter_affiliation ?? null),
    membership_status: detail.membershipStatus ?? null,
    certifications: (detail.certifications ?? []).join(','),
    role_applied: opp.role_default,

    motivation_letter: responses.motivation_letter
      ?? detail.coverLetterInfo?.coverLetter
      ?? null,
    proposed_theme: responses.proposed_theme ?? null,
    areas_of_interest: responses.areas_of_interest ?? null,
    availability_declared: responses.availability_declared ?? null,
    leadership_experience: responses.leadership_experience ?? null,
    academic_background: responses.academic_background ?? null,
    chapter_affiliation: responses.chapter_affiliation ?? null,

    non_pmi_experience: detail.nonPMIExperience ?? null,
    reason_for_applying: responses.motivation_letter
      ?? responses.reason_for_applying
      ?? detail.coverLetterInfo?.coverLetter
      ?? null,
    application_date: detail.applicationDate ?? null,

    status: mapPmiStatusToNucleo(detail.status),
    imported_at: new Date().toISOString(),
    organization_id: orgId
  };
}

function extractResponsesByEssayMapping(
  detail: VepApplicationDetail,
  opp: VepOpportunityRow
): Record<string, string | null> {
  const mapping = opp.essay_mapping ?? {};
  const responses = detail.questionResponses ?? [];
  const out: Record<string, string | null> = {};

  for (const [idx, m] of Object.entries(mapping)) {
    const idxNum = parseInt(idx, 10);
    const resp = responses.find(r =>
      String(r.questionNumber) === idx ||
      r.questionIndex === idxNum
    );
    out[m.field] = (resp?.responseText ?? resp?.answer ?? null);
  }

  return out;
}

/**
 * Parse chapter slug a partir de membership_status.
 *
 * TODO_CLAUDE_CODE: confirmar mapping completo dos 5 chapters parceiros.
 */
function parseChapterFromMembership(ms: string): string | null {
  if (!ms) return null;

  const STATE_TO_CHAPTER: Record<string, string> = {
    'Goiás': 'PMI-GO',
    'Goias': 'PMI-GO',
    'Distrito Federal': 'PMI-DF',
    'Minas Gerais': 'PMI-MG',
    'Rio Grande do Sul': 'PMI-RS',
    'Ceará': 'PMI-CE',
    'Ceara': 'PMI-CE',
    'Pernambuco': 'PMI-PE',
    'São Paulo': 'PMI-SP',
    'Sao Paulo': 'PMI-SP',
    'Rio de Janeiro': 'PMI-RJ',
    'Paraná': 'PMI-PR',
    'Parana': 'PMI-PR',
    'Santa Catarina': 'PMI-SC',
    'Bahia': 'PMI-BA',
    'Espírito Santo': 'PMI-ES',
    'Espirito Santo': 'PMI-ES'
  };

  for (const [state, chapter] of Object.entries(STATE_TO_CHAPTER)) {
    if (ms.includes(state)) return chapter;
  }

  return null;
}

/**
 * Normalize chapter_affiliation raw field para canon (PMIRS → PMI-RS).
 *
 * Fix p87 #118: PMI VEP form retorna affiliation sem hífen ("PMIRS" /
 * "PMI RS"), o que não casa com canônico chapter_registry (PMI-RS).
 * Fallback usado quando parseChapterFromMembership não consegue resolver
 * via membership_status (caso João Uzejka — membership "Active" não tem
 * state name, mas chapter_affiliation tem "PMIRS").
 */
export function normalizeChapterAffiliation(raw: string | null | undefined): string | null {
  if (!raw) return null;
  // Strip whitespace, hyphens, dots → uppercase compact form
  const s = raw.toUpperCase().replace(/[\s\-_.]/g, '');
  const map: Record<string, string> = {
    'PMIGO': 'PMI-GO',
    'PMICE': 'PMI-CE',
    'PMIDF': 'PMI-DF',
    'PMIMG': 'PMI-MG',
    'PMIRS': 'PMI-RS',
    'PMIPE': 'PMI-PE',
    'PMISP': 'PMI-SP',
    'PMIRJ': 'PMI-RJ',
    'PMIPR': 'PMI-PR',
    'PMISC': 'PMI-SC',
    'PMIBA': 'PMI-BA',
    'PMIES': 'PMI-ES',
    'PMIAM': 'PMI-AM',
    'PMIPB': 'PMI-PB',
    'PMIRN': 'PMI-RN',
  };
  return map[s] ?? null;
}

/**
 * Mapeia status PMI VEP → status Núcleo (selection_applications.status).
 *
 * Núcleo CHECK: submitted | screening | objective_eval | objective_cutoff |
 *   interview_pending | interview_scheduled | interview_done | interview_noshow |
 *   final_eval | approved | rejected | waitlist | converted | withdrawn | cancelled
 */
function mapPmiStatusToNucleo(pmiStatus: string | undefined): string {
  if (!pmiStatus) return 'submitted';
  const s = pmiStatus.toLowerCase();

  if (s.includes('submitted')) return 'submitted';
  if (s.includes('qualified') || s.includes('approved')) return 'approved';
  if (s.includes('declined') || s.includes('rejected') || s.includes('expired')) return 'rejected';
  if (s.includes('withdrawn') || s.includes('removed')) return 'cancelled';

  return 'submitted';
}
