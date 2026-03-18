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
export const PMI_NONTRIAL_KEYWORDS = [
  { keywords: ['citizen developer', 'cdba'], code: 'CDBA_INTRO' },
  { keywords: ['introduction', 'cognitive', 'cpmai'], code: 'CPMAI_INTRO' },
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
]

/**
 * Classify a Credly badge into one of 10 W143-aligned categories.
 * Returns { category, points } based on keyword matching.
 * Order matters: more specific matches checked first.
 */
export function classifyBadge(name: string, slug: string): { category: string; points: number } {
  const combined = (name + ' ' + slug).toLowerCase()

  // PMI AI Trail courses → trail (20 XP)
  for (const trail of PMI_TRAIL_KEYWORDS) {
    if (trail.keywords.every(kw => combined.includes(kw))) {
      return { category: 'trail', points: 20 }
    }
  }

  // Non-trail PMI courses → course (15 XP)
  for (const course of PMI_NONTRIAL_KEYWORDS) {
    if (course.keywords.every(kw => combined.includes(kw))) {
      return { category: 'course', points: 15 }
    }
  }

  // cert_cpmai (45 XP) — check BEFORE cert_pmi_senior since 'cpmai' overlaps
  if (CERT_CPMAI_KEYWORDS.some(kw => combined.includes(kw))) {
    return { category: 'cert_cpmai', points: 45 }
  }

  // cert_pmi_senior (50 XP)
  if (CERT_PMI_SENIOR_KEYWORDS.some(kw => combined.includes(kw))) {
    return { category: 'cert_pmi_senior', points: 50 }
  }

  // cert_pmi_mid (40 XP)
  if (CERT_PMI_MID_KEYWORDS.some(kw => combined.includes(kw))) {
    return { category: 'cert_pmi_mid', points: 40 }
  }

  // cert_pmi_practitioner (35 XP) — check BEFORE cert_pmi_entry (DASSM contains DASM)
  if (CERT_PMI_PRACTITIONER_KEYWORDS.some(kw => combined.includes(kw))) {
    return { category: 'cert_pmi_practitioner', points: 35 }
  }

  // cert_pmi_entry (30 XP)
  if (CERT_PMI_ENTRY_KEYWORDS.some(kw => combined.includes(kw))) {
    return { category: 'cert_pmi_entry', points: 30 }
  }

  // specialization (25 XP)
  if (SPECIALIZATION_KEYWORDS.some(kw => combined.includes(kw))) {
    return { category: 'specialization', points: 25 }
  }

  // knowledge_ai_pm (20 XP)
  if (KNOWLEDGE_AI_PM_KEYWORDS.some(kw => combined.includes(kw))) {
    return { category: 'knowledge_ai_pm', points: 20 }
  }

  // Fallback: generic badge (10 XP)
  return { category: 'badge', points: 10 }
}
