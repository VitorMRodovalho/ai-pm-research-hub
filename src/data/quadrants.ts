// ─── Quadrant data — the 4 strategic pillars ───

export interface Quadrant {
  key: 'q1' | 'q2' | 'q3' | 'q4';
  label: string;
  title: string;
  subtitle: string;
  /** Tailwind color class (matches @theme vars) */
  color: string;
  /** CSS variable for inline style fallbacks */
  cssVar: string;
}

export const QUADRANTS: Quadrant[] = [
  {
    key: 'q1',
    label: 'QUADRANTE 1',
    title: 'O Praticante Aumentado',
    subtitle: 'Ferramentas, Produtividade e Engenharia de Agentes',
    color: 'teal',
    cssVar: '--color-teal',
  },
  {
    key: 'q2',
    label: 'QUADRANTE 2',
    title: 'Gestão de Projetos de IA',
    subtitle: 'Metodologia GenAI/ML e Equipes Híbridas',
    color: 'orange',
    cssVar: '--color-orange',
  },
  {
    key: 'q3',
    label: 'QUADRANTE 3',
    title: 'Liderança Organizacional',
    subtitle: 'Estratégia, Pessoas, Cultura e Portfólio',
    color: 'purple',
    cssVar: '--color-purple',
  },
  {
    key: 'q4',
    label: 'QUADRANTE 4',
    title: 'Futuro e Responsabilidade',
    subtitle: 'Ética, Governança e Sociedade',
    color: 'emerald',
    cssVar: '--color-emerald',
  },
];
