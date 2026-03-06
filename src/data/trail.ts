// ─── PMI AI Certification Trail — 8 courses ───

export interface Course {
  code: string;
  name: string;
  category: 'core' | 'extra';
  url: string;
}

export const COURSES: Course[] = [
  {
    code: 'GENAI_OVERVIEW',
    name: 'Generative AI Overview for Project Managers',
    category: 'core',
    url: 'https://www.pmi.org/shop/p-/elearning/generative-ai-overview-for-project-managers/el083',
  },
  {
    code: 'DATA_LANDSCAPE',
    name: 'Data Landscape of GenAI for Project Managers',
    category: 'core',
    url: 'https://www.pmi.org/shop/p-/elearning/data-landscape-of-genai-for-project-managers/el106',
  },
  {
    code: 'PROMPT_ENG',
    name: 'Talking to AI: Prompt Engineering for Project Managers',
    category: 'core',
    url: 'https://www.pmi.org/shop/p-/elearning/talking-to-ai-prompt-engineering-for-project-managers/el128',
  },
  {
    code: 'PRACTICAL_GENAI',
    name: 'Practical Application of Generative AI for Project Managers',
    category: 'core',
    url: 'https://www.pmi.org/shop/p-/elearning/practical-application-of-generative-ai-for-project-managers/el173',
  },
  {
    code: 'CDBA_INTRO',
    name: 'PMI Citizen Developer: CDBA Introduction',
    category: 'extra',
    url: 'https://www.pmi.org/shop/p-/elearning/pmi-citizen-developer-business-architect-cdba-introduction/el058',
  },
  {
    code: 'CPMAI_INTRO',
    name: 'Free Introduction to Cognitive PM in AI (CPMAI)',
    category: 'extra',
    url: 'https://www.pmi.org/shop/brazil/p-/elearning/free-introduction-to-cognitive-project-management-in-ai-cpmai/el185',
  },
  {
    code: 'AI_INFRA',
    name: 'AI in Infrastructure and Construction Projects',
    category: 'extra',
    url: 'https://www.pmi.org/shop/p-/elearning/ai-in-infrastructure-and-construction-projects/el174',
  },
  {
    code: 'AI_AGILE',
    name: 'AI in Agile Delivery',
    category: 'extra',
    url: 'https://www.pmi.org/shop/p-/elearning/ai-in-agile-delivery/el251',
  },
];

export const TOTAL_COURSES = COURSES.length;

export function coreCourses(): Course[] {
  return COURSES.filter((c) => c.category === 'core');
}

export function extraCourses(): Course[] {
  return COURSES.filter((c) => c.category === 'extra');
}
