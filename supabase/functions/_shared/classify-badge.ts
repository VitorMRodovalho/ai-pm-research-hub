// _shared/classify-badge.ts
// Extracted from sync-credly-all (GC-083)
// Pure JS — no Deno APIs, no esm.sh imports
// Used by: sync-credly-all, verify-credly

// ── PMI AI Trail: 6 courses with Credly badges (20 XP, category: trail) ──
export const PMI_TRAIL_KEYWORDS = [
  { keywords: ['generative ai overview', 'project managers'], code: 'GENAI_OVERVIEW' },
  { keywords: ['data landscape', 'genai', 'project managers'], code: 'DATA_LANDSCAPE' },
  { keywords: ['prompt engineering', 'project managers'], code: 'PROMPT_ENG' },
  { keywords: ['practical application', 'gen ai', 'project managers'], code: 'PRACTICAL_GENAI' },
  { keywords: ['ai in infrastructure', 'construction'], code: 'AI_INFRA' },
  { keywords: ['ai in agile delivery'], code: 'AI_AGILE' },
]

// ── Non-trail PMI courses (15 XP, category: course) ──
// NOTE (p169): 'PMI Essentials: Seven AI Project Patterns' (el343) exists as
// course in DB but PMI does NOT currently emit Credly badge for it (confirmed
// 2026-05-16: 0 members in our DB + 0 results in credly.com PMI org page).
// When PMI starts emitting, add: { keywords: ['seven', 'ai', 'patterns'], code: 'AI_PATTERNS' }
// to this list so badge classifies as 'course' (15 XP) instead of fallback 'badge' (10 XP).
export const PMI_NONTRIAL_KEYWORDS = [
  { keywords: ['citizen developer', 'cdba'], code: 'CDBA_INTRO' },
  { keywords: ['introduction', 'cognitive', 'cpmai'], code: 'CPMAI_INTRO' },
  // #1209 (Tier 1/2 tuning — GP-approved 2026-07-08): PMI + adjacent PM courses that
  // previously fell through to fallback 'badge' (10). Live dry-run over gamification_points
  // confirmed exact match, zero collateral over the 380 already-recognized badges.
  { keywords: ['pmi essentials'], code: 'PMI_ESSENTIALS' },
  { keywords: ['m.o.r.e'], code: 'PMI_ESSENTIALS_MORE' }, // "PMI® Essentials: M.O.R.E." (® glues to 'PMI', so match the M.O.R.E. brand)
  { keywords: ['citizen developer'], code: 'PMI_CD' },     // CD Business Architect / Practitioner Skills (carry no 'cdba' token)
  { keywords: ['hybrid project management'], code: 'AGILE_HYBRID_PM' },
]

// ── Non-PMI training / formation (15 XP, category: course) — #2296 ──────────
// GP-approved 2026-09-15. These are TRAINING (a course, a program, a record of achievement),
// not a credential and not mere attendance. Checked AFTER the credential ladders on purpose
// (see the ordering note in classifyBadge). They fell into fallback 'badge' (10) because every
// course keyword above is PMI-specific.
//
// ⚠️ Deliberately NOT here, and left in fallback 'badge' on purpose: attendance and membership
// ("CertiProf Online Summit Attendee", "ACMP Member Badge", "APM Student", "Construction
// Management Association of America Member"), recognition and loyalty tiers ("Mentor Silver",
// "Instructor Recognition - *", "FY26 LevelUp *", "FY24/FY26 Value *"), community service
// ("Worldwide Communities - Community Champion/SME", "Connected Communities - Engagement Lead",
// "Chapter Leader"), survey participation ("Survey Contributor of The Agile Adoption Report"),
// "Lifelong Learning", "IPMA-UCL Megaproject CEO participant" (the name says participant) and
// "Microsoft Global Hackathon". Participation is worth 10, and that is the decision, not an
// oversight. Under-mapping is recoverable by the monthly detector; over-mapping silently moves
// someone's rank.
export const TRAINING_KEYWORDS = [
  'construction project communications',
  'construction performance', 'construction technology', 'digital construction',
  'organizational transformation',
  'people management essentials',
  'data-driven decision',
  'notion essentials',
  'red hat training',
  'sap cloud alm', 'sap solution manager', 'sap business technology platform',
  'sap s/4hana cloud', 'sap successfactors',
  'forward program',
  'accessibility in action',
  'black leadership academy',
  'human resource associate',
  'sales associate certificate',
]

// ── cert_cpmai (45 XP) — check BEFORE cert_pmi_senior since 'cpmai' overlaps ──
export const CERT_CPMAI_KEYWORDS = [
  'cpmai', 'pmi-cpmai', 'cognitive project management',
]

// ── cert_pmi_senior (50 XP) ──
export const CERT_PMI_SENIOR_KEYWORDS = [
  'pmp', 'project management professional',
  'pmi-acp', 'pmi-cp', 'pgmp', 'pfmp',
  'pmi-rmp', 'pmi risk management professional',
  'pmi-sp', 'pmi scheduling professional',
]

// ── cert_pmi_mid (40 XP) ──
export const CERT_PMI_MID_KEYWORDS = [
  'pmi-pmocp', 'pmi pmo certified professional',
]

// ── cert_pmi_practitioner (35 XP) — check BEFORE cert_pmi_entry (DASSM contains DASM) ──
export const CERT_PMI_PRACTITIONER_KEYWORDS = [
  'disciplined agile senior scrum master', 'dassm',
  'pmo certified practitioner', 'pmo-cp',
]

// ── cert_pmi_entry (30 XP) ──
export const CERT_PMI_ENTRY_KEYWORDS = [
  'disciplined agile scrum master (dasm)',
]

// ── specialization (25 XP) ──
export const SPECIALIZATION_KEYWORDS = [
  'capm', 'pmi-pbsm',
  'professional scrum master', 'psm', 'pspo',
  'safe', 'scaled agile', 'csm', 'certified scrum',
  'prosci', 'finops',
  'aws', 'azure', 'microsoft certified', 'microsoft 365 certified',
  'microsoft certified trainer', 'google cloud certified',
  'power bi', 'power platform',
  'itil', 'togaf', 'cobit', 'prince2',
  'lean six sigma', 'scrum alliance', 'scrum foundation', 'sfpc',
  'authorized training partner',
  'fortinet', 'isc2', 'cybersecurity', 'threat landscape',
  'mta:', 'mcsa:', 'md-100',
  'ibm business automation',
  'remote work professional',
  // #1209 (Tier 2 tuning — GP-approved 2026-07-08): PM/infra specializations previously in fallback 'badge'
  'scaled professional scrum',
  'green project manager', 'sustainable project professional',
  'cloud essentials', 'well-architected',
  // ⚠️ NAO acrescente aqui, sem decisao NOVA do dono: 'devops essentials'/'depc', 'onetrust',
  // 'oracle certified'/'oracle database'. O #1209 (GP, 08/07) fixou em
  // tests/edge-functions/classify-badge.test.mjs que certificacao FORA DO DOMINIO do nucleo
  // (nucleo = IA + GP) fica em `badge`/10, e essas tres sao nomeadas la, uma a uma. A decisao de
  // 15/09 foi tomada sem essa regra na tela, entao ela NAO a revoga. Mesmo caso de
  // 'essentials for projects' e 'product and project collaboration' na lista de treinamento.
  //
  // ⚠️ E a regra como escrita NAO bate com o acervo: 'aws', 'azure', 'fortinet', 'isc2' e
  // 'cybersecurity' ja estao nesta lista valendo 25, e sao tao fora de IA+GP quanto Oracle.
  // Isso e uma inconsistencia REAL do repo, nao um detalhe — e ela precisa de decisao, nao de
  // mais uma palavra-chave.
  // #2296 (GP-approved 2026-09-15): THIRD-PARTY professional certifications previously in
  // fallback 'badge'. They land here, not in `cert_pmi_*`: that ladder is the PMI credential
  // ladder (PMP, PgMP, DASM/DASSM, PMO-CP), and 'specialization' is already where every
  // non-PMI credential lives (AWS, Azure, ITIL, TOGAF, PRINCE2, ISC2, PRINCE2, Scrum Alliance).
  'public-private partnership',
  'lgpdf', 'lei geral de proteção de dados',
  'okrcpc', 'okrmpc',
  'professional agile leadership', 'pal-ebm',
  'professional scrum',          // PSK I and SPS; 'professional scrum master' already above
  'sap certified',
  'office 365', 'microsoft ppm',
  'google data analytics',
]

// ── knowledge_ai_pm (20 XP) ──
export const KNOWLEDGE_AI_PM_KEYWORDS = [
  'artificial intelligence', 'machine learning', 'deep learning',
  'generative ai', 'gen ai', 'genai', 'prompt engineering',
  'data science', 'data landscape', 'business intelligence',
  'cognitive', 'ai ', ' ai', 'ml ', ' ml',
  'agile metrics', 'fundamentals of agile', 'fundamentals of predictive',
  'fundamentos de gerenciamento', 'fundamentos do gerenciamento',
  'enterprise design thinking', 'design sprint',
  'value stream management', 'agile coach',
  'ibm program manager', 'program manager capstone',
  'ai-driven project manager',
  // #1209 (Tier 2 tuning — GP-approved 2026-07-08): data/design-thinking courses previously in fallback 'badge'
  'data visualization', 'big data', 'design thinking',
]

// ── Category → points (#1149, SSOT alignment) ──────────────────────────────
// SINGLE pricing table in code. Every value MUST equal gamification_rules.base_points
// for the same slug — locked by tests/contracts/1149-credly-ssot.test.mjs (DB-gated).
// The sync classifies; gamification_rules prices. If a rule is repriced in the DB,
// update here too or the contract test fails (no silent drift).
export const CATEGORY_POINTS: Record<string, number> = {
  trail: 20,
  course: 15,
  cert_cpmai: 45,
  cert_pmi_senior: 50,
  cert_pmi_mid: 40,
  cert_pmi_practitioner: 35,
  cert_pmi_entry: 30,
  specialization: 25,
  knowledge_ai_pm: 20,
  badge: 10,
}

function classified(category: string): { category: string; points: number } {
  return { category, points: CATEGORY_POINTS[category] }
}

/**
 * Classify a Credly badge into one of 10 W143-aligned categories.
 * Returns { category, points } based on keyword matching.
 * Order matters: more specific matches checked first.
 */
export function classifyBadge(name: string, slug: string): { category: string; points: number } {
  const combined = (name + ' ' + slug).toLowerCase()

  // PMI AI Trail courses → trail
  for (const trail of PMI_TRAIL_KEYWORDS) {
    if (trail.keywords.every(kw => combined.includes(kw))) {
      return classified('trail')
    }
  }

  // Non-trail PMI courses → course
  for (const course of PMI_NONTRIAL_KEYWORDS) {
    if (course.keywords.every(kw => combined.includes(kw))) {
      return classified('course')
    }
  }

  // cert_cpmai — check BEFORE cert_pmi_senior since 'cpmai' overlaps
  if (CERT_CPMAI_KEYWORDS.some(kw => combined.includes(kw))) {
    return classified('cert_cpmai')
  }

  if (CERT_PMI_SENIOR_KEYWORDS.some(kw => combined.includes(kw))) {
    return classified('cert_pmi_senior')
  }

  if (CERT_PMI_MID_KEYWORDS.some(kw => combined.includes(kw))) {
    return classified('cert_pmi_mid')
  }

  // cert_pmi_practitioner — check BEFORE cert_pmi_entry (DASSM contains DASM)
  if (CERT_PMI_PRACTITIONER_KEYWORDS.some(kw => combined.includes(kw))) {
    return classified('cert_pmi_practitioner')
  }

  if (CERT_PMI_ENTRY_KEYWORDS.some(kw => combined.includes(kw))) {
    return classified('cert_pmi_entry')
  }

  if (SPECIALIZATION_KEYWORDS.some(kw => combined.includes(kw))) {
    return classified('specialization')
  }

  // Non-PMI training → course (#2296). Deliberadamente DEPOIS das escadas de credencial e de
  // `specialization`: "SAP Certified - Managing SAP S/4HANA Cloud Public Edition Projects" carrega
  // AS DUAS naturezas, e a credencial tem de vencer. Com este bloco antes de `specialization`, ele
  // caia em `course` (15) enquanto o irmao "SAP Certified - Project Manager - SAP Activate" ia para
  // `specialization` (25) — dois badges "SAP Certified" com precos diferentes por acidente de ordem.
  if (TRAINING_KEYWORDS.some(kw => combined.includes(kw))) {
    return classified('course')
  }

  if (KNOWLEDGE_AI_PM_KEYWORDS.some(kw => combined.includes(kw))) {
    return classified('knowledge_ai_pm')
  }

  // Fallback: generic badge
  return classified('badge')
}

// ── CPMAI family collapse (#1149 P1) ────────────────────────────────────────
// PMI's CPMAI credential family (v7 / +E / PLUS / PMI-CPMAI) represents ONE
// certification: PMI officially replaced "CPMAI v7" with "PMI-CPMAI" on
// 2025-09-30 (rebrand, no re-exam); +E is an optional add-on exam; PLUS is
// co-issued with v7. Policy (Vitor, 2026-07-06): one cert_cpmai XP credit per
// person — keep the PMI-CPMAI-branded badge as canonical, else the most
// recently issued. Display surfaces (members.credly_badges) still list every
// badge the person holds; only the XP credit collapses.

const CPMAI_CANONICAL_MARKERS = [
  'pmi-cpmai', 'pmi certified professional in managing ai',
]

export function isCanonicalCpmaiName(name: string, slug = ''): boolean {
  const combined = (name + ' ' + slug).toLowerCase()
  return CPMAI_CANONICAL_MARKERS.some(kw => combined.includes(kw))
}

/**
 * From the cert_cpmai-classified badges of ONE member, pick the single badge
 * whose XP credit survives. Prefer the PMI-CPMAI-branded badge (current
 * official credential), else the most recent issued_at (tiebreak: name, for
 * determinism). Returns null for an empty family.
 */
export function selectCanonicalCpmai<T extends { name: string; slug?: string; issued_at?: string }>(
  family: T[],
): T | null {
  if (!family.length) return null
  const branded = family.filter(b => isCanonicalCpmaiName(b.name, b.slug || ''))
  const pool = branded.length ? branded : family
  return [...pool].sort((a, b) =>
    (Date.parse(b.issued_at || '') || 0) - (Date.parse(a.issued_at || '') || 0)
    || a.name.localeCompare(b.name),
  )[0]
}
