// ─── Trilha PMI AI — 4 tiers: 4 core mini-certs + 2 specialty + 3 complementary + 1 master cert ───
// PM-confirmed 2026-05-16 (p169) — synced with DB courses.tier column.
//
// CONTRACT (p169): This file MUST stay in sync with public.courses DB rows.
// `tests/contracts/courses-trail-sync.test.mjs` asserts code/tier/is_trail/url
// match between this file and DB via get_trail_courses() RPC. When adding a
// new course, update BOTH:
//   1. Insert into public.courses via migration
//   2. Add entry to COURSES array below
// The contract test will fail (when SUPABASE_URL + key present) if they diverge.

export type CourseTier = 'core' | 'specialty' | 'complementary' | 'master';

export interface Course {
  code: string;
  name: string;
  tier: CourseTier;
  url: string;
  isTrail: boolean;
  hasCredly: boolean;
}

export const COURSES: Course[] = [
  {
    code: 'GENAI_OVERVIEW',
    name: 'Generative AI Overview for Project Managers',
    tier: 'core',
    isTrail: true,
    hasCredly: true,
    url: 'https://www.pmi.org/shop/p-/elearning/generative-ai-overview-for-project-managers/el083',
  },
  {
    code: 'DATA_LANDSCAPE',
    name: 'Data Landscape of GenAI for Project Managers',
    tier: 'core',
    isTrail: true,
    hasCredly: true,
    url: 'https://www.pmi.org/shop/p-/elearning/data-landscape-of-genai-for-project-managers/el106',
  },
  {
    code: 'PROMPT_ENG',
    name: 'Talking to AI: Prompt Engineering for Project Managers',
    tier: 'core',
    isTrail: true,
    hasCredly: true,
    url: 'https://www.pmi.org/shop/p-/elearning/talking-to-ai-prompt-engineering-for-project-managers/el128',
  },
  {
    code: 'PRACTICAL_GENAI',
    name: 'Practical Application of Generative AI for Project Managers',
    tier: 'core',
    isTrail: true,
    hasCredly: true,
    url: 'https://www.pmi.org/shop/p-/elearning/practical-application-of-generative-ai-for-project-managers/el173',
  },
  {
    code: 'AI_INFRA',
    name: 'AI in Infrastructure and Construction Projects',
    tier: 'specialty',
    isTrail: true,
    hasCredly: true,
    url: 'https://www.pmi.org/shop/p-/elearning/ai-in-infrastructure-and-construction-projects/el174',
  },
  {
    code: 'AI_AGILE',
    name: 'AI in Agile Delivery',
    tier: 'specialty',
    isTrail: true,
    hasCredly: true,
    url: 'https://www.pmi.org/shop/p-/elearning/ai-in-agile-delivery/el251',
  },
  {
    code: 'CPMAI_INTRO',
    name: 'Free Introduction to Cognitive PM in AI (CPMAI)',
    tier: 'complementary',
    isTrail: false,
    hasCredly: true,
    url: 'https://www.pmi.org/shop/brazil/p-/elearning/free-introduction-to-cognitive-project-management-in-ai-cpmai/el185',
  },
  {
    code: 'AI_PATTERNS',
    name: 'PMI Essentials: Seven AI Project Patterns',
    tier: 'complementary',
    isTrail: false,
    hasCredly: false,
    url: 'https://www.pmi.org/shop/p-/elearning/pmi-essentials-seven-ai-project-patterns/el343',
  },
  {
    code: 'CDBA_INTRO',
    name: 'PMI Citizen Developer: CDBA Introduction',
    tier: 'complementary',
    isTrail: false,
    hasCredly: false,
    url: 'https://www.pmi.org/shop/p-/elearning/pmi-citizen-developer-business-architect-cdba-introduction/el058',
  },
  {
    code: 'PMI_CPMAI_MASTER',
    name: 'PMI Certified Professional in Managing AI (PMI-CPMAI)™',
    tier: 'master',
    isTrail: false,
    hasCredly: true,
    url: 'https://www.pmi.org/certifications/managing-artificial-intelligence',
  },
];

/** Trail courses only (6 with Credly badge from PMI_TRAIL_KEYWORDS) */
export const TRAIL_COURSES = COURSES.filter((c) => c.isTrail);

/** Total mandatory trail courses (6 badges) */
export const TOTAL_COURSES = TRAIL_COURSES.length; // 6

export function coreCourses(): Course[] {
  return COURSES.filter((c) => c.tier === 'core');
}

export function specialtyCourses(): Course[] {
  return COURSES.filter((c) => c.tier === 'specialty');
}

export function complementaryCourses(): Course[] {
  return COURSES.filter((c) => c.tier === 'complementary');
}

export function masterCertCourses(): Course[] {
  return COURSES.filter((c) => c.tier === 'master');
}
