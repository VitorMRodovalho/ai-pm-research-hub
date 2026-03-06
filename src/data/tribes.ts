// ─── Tribe data — extracted from v1 index.html ───
// Static data: leader names, descriptions, deliverables, videos
// Dynamic data (slot counts, leader photos) comes from Supabase at runtime

export interface Tribe {
  id: number;
  name: string;
  leader: string;
  leaderLinkedIn: string;
  quadrant: 'q1' | 'q2' | 'q3' | 'q4';
  quadrantLabel: string;
  description: string;
  deliverables: string[];
  meetingSchedule: string;
  videoUrl: string;
  videoDuration: string;
}

export const MAX_SLOTS = 6;
export const MIN_SLOTS = 3;

export const TRIBES: Tribe[] = [
  {
    id: 1,
    name: 'Radar Tecnológico do GP',
    leader: 'Hayala Curto, MSc, MBA, PMP®',
    leaderLinkedIn: 'https://www.linkedin.com/in/hayala/',
    quadrant: 'q1',
    quadrantLabel: 'Q1 — Praticante Aumentado',
    description:
      'Fazer um simples pedido para uma IA já não é suficiente para entregas de excelência. É hora de elevar o nível com a engenharia de agentes! O desafio não é buscar um "prompt mágico", mas organizar múltiplos prompts e modelos em uma arquitetura de agentes capaz de planejar, executar e se autocorrigir.',
    deliverables: [
      'Radar Tecnológico do GP (comparativo GPT vs Claude vs Gemini por artefato)',
      'Padrões de Arquitetura de Agentes (com código Python)',
      '1-2 Artigos científicos',
    ],
    meetingSchedule: 'Segundas ou Quartas, 19h',
    videoUrl: 'https://www.youtube.com/watch?v=XJLAvcHFKT8',
    videoDuration: '7min',
  },
  {
    id: 2,
    name: 'Agentes Autônomos & Equipes Híbridas',
    leader: 'Débora Moura',
    leaderLinkedIn: 'https://www.linkedin.com/in/deboralmoura/',
    quadrant: 'q2',
    quadrantLabel: 'Q2 — Gestão de Projetos de IA',
    description:
      '72% dos GPs usam IA de forma ad-hoc, sem alinhamento estratégico. Como criar um framework que guie os GPs na estruturação dos seus próprios agentes? Assim como a EAP guia o escopo, a EAA será o padrão para estruturar agentes!',
    deliverables: [
      'Framework EAA (Estrutura Analítica do Agente)',
      'E-book / Guia Prático',
      'Webinário focado',
      'Artigo científico (previsão junho)',
    ],
    meetingSchedule: 'Quintas, 20h30',
    videoUrl: 'https://www.youtube.com/watch?v=HwgjMalJXQE',
    videoDuration: '8min',
  },
  {
    id: 3,
    name: 'TMO & PMO do Futuro',
    leader: 'Marcel Fleming',
    leaderLinkedIn: 'https://www.linkedin.com/in/marcelfleming/',
    quadrant: 'q3',
    quadrantLabel: 'Q3 — Liderança Organizacional',
    description:
      'Organizações com maior maturidade em GP obtêm taxas muito maiores de sucesso. Vamos desenvolver uma POC de IA para diagnosticar maturidade (modelo Prado-MMGP), criar checklists e sugerir ações de melhoria.',
    deliverables: [
      'Assistente de IA para diagnóstico de maturidade',
      'Plano de Ação Inteligente personalizado',
      'Relatório técnico com resultados da POC',
    ],
    meetingSchedule: 'A definir com o time',
    videoUrl: 'https://www.youtube.com/watch?v=vxQ4WLTyKpY',
    videoDuration: '4min',
  },
  {
    id: 4,
    name: 'Cultura & Change',
    leader: 'Fernando Maquiaveli',
    leaderLinkedIn: 'https://www.linkedin.com/in/fernandomaquiaveli/',
    quadrant: 'q3',
    quadrantLabel: 'Q3 — Liderança Organizacional',
    description:
      'Sem cultura, a IA escala o caos. Com 80%+ dos projetos em ambientes multiculturais, precisamos de Inteligência Cultural. O "internal stickiness" bloqueia fluxo de informação — é o inimigo invisível dos projetos.',
    deliverables: [
      'Entregas mensais práticas (ferramentas de uso imediato)',
      'Framework Inteligência Cultural + IA',
      'Pesquisa com metodologias mistas',
      'Artigos acadêmicos',
    ],
    meetingSchedule: 'Cadência semanal',
    videoUrl: 'https://www.youtube.com/watch?v=LZSk96EsepA',
    videoDuration: '3min',
  },
  {
    id: 5,
    name: 'Talentos & Upskilling',
    leader: 'Jefferson Pinto',
    leaderLinkedIn: 'https://www.linkedin.com/in/jeffersonpp/',
    quadrant: 'q3',
    quadrantLabel: 'Q3 — Liderança Organizacional',
    description:
      'Adoção de IA acelerou, mas faltam critérios observáveis e evidências claras de proficiência. Sem métricas, não há evolução estruturada! Vamos criar o MVP da Proficiência em IA para GPs.',
    deliverables: [
      'Taxonomia (estrutura hierárquica de competências)',
      'Matriz + Rubricas (Iniciante/Intermediário/Avançado)',
      'Toolkit v1.0 (checklist + evidências)',
      'Artigo + Webinário',
    ],
    meetingSchedule: 'Segundas, 20h',
    videoUrl: 'https://www.youtube.com/watch?v=KbhnAJdSeDw',
    videoDuration: '5min',
  },
  {
    id: 6,
    name: 'ROI & Portfólio',
    leader: 'Fabricio Costa, PMP',
    leaderLinkedIn: 'https://www.linkedin.com/in/fabriciorcc/',
    quadrant: 'q3',
    quadrantLabel: 'Q3 — Liderança Organizacional',
    description:
      'Chega de decisões milionárias baseadas em intuição! A IA para priorização ainda é uma "caixa preta". Vamos transformá-la em "caixa de vidro" — transparente, explicável e auditável.',
    deliverables: [
      'Modelos Híbridos (IA + julgamento humano)',
      'Métricas além do ROI (riscos, reputação, aprendizado)',
      'Artigos mensais no LinkedIn',
      'Protótipo de plataforma IA para simulação e priorização',
    ],
    meetingSchedule: 'A definir com o time',
    videoUrl: 'https://www.youtube.com/watch?v=R2fA7hVE1dc',
    videoDuration: '11min',
  },
  {
    id: 7,
    name: 'Governança & Trustworthy AI',
    leader: 'Marcos Klemz',
    leaderLinkedIn: 'https://www.linkedin.com/in/maklemz/',
    quadrant: 'q4',
    quadrantLabel: 'Q4 — Futuro e Responsabilidade',
    description:
      '83% das organizações planejam implantar IA, mas apenas 29% se sentem prontas. 46% das PoCs são descartadas. Riscos silenciosos: alucinações, dados, vieses. Fim das "PoCs Eternas"!',
    deliverables: [
      'Framework de Governança de IA',
      'Matriz de Qualidade de Dados',
      'Guia de Métricas de Valor (ROI real)',
      'Checklist Critérios de Aceite (GenAI/RAG)',
      'Toolkit v1.0 Governança',
    ],
    meetingSchedule: 'Terças, 20h',
    videoUrl: 'https://www.youtube.com/watch?v=3su8GgtFzVY',
    videoDuration: '3min',
  },
  {
    id: 8,
    name: 'Inclusão & Colaboração',
    leader: 'Ana Carla Cavalcante',
    leaderLinkedIn: 'https://www.linkedin.com/in/anacarlacavalcante/',
    quadrant: 'q4',
    quadrantLabel: 'Q4 — Futuro e Responsabilidade',
    description:
      '15-20% da população mundial é neurodivergente. Apenas 25% dos neuroatípicos empregados se sentem incluídos. Vamos desenvolver o Neuroadvantage Framework 1.0: um "exoesqueleto cognitivo" suportado por IA.',
    deliverables: [
      'Neuroadvantage Framework 1.0 (5 pilares)',
      'Artigo científico (pilar teórico)',
      'Webinar prático (pilar tecnológico)',
      'Testes práticos + versão 1.0 para o mercado',
    ],
    meetingSchedule: 'Terças e Quintas, 20h30',
    videoUrl: 'https://www.youtube.com/watch?v=ghrgJ3_nk4k',
    videoDuration: '14min',
  },
];

/** Helper: get tribes by quadrant key */
export function tribesByQuadrant(q: Tribe['quadrant']): Tribe[] {
  return TRIBES.filter((t) => t.quadrant === q);
}
