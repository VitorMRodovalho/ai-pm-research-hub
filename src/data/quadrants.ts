// ─── Quadrant data — the 4 strategic pillars (i18n via translation keys) ───

export interface Quadrant {
  key: 'q1' | 'q2' | 'q3' | 'q4';
  labelKey: string;     // e.g. 'data.q1.label'
  titleKey: string;     // e.g. 'data.q1.title'
  subtitleKey: string;  // e.g. 'data.q1.sub'
  /** Tailwind color class (matches @theme vars) */
  color: string;
  /** CSS variable for inline style fallbacks */
  cssVar: string;
}

export const QUADRANTS: Quadrant[] = [
  {
    key: 'q1',
    labelKey: 'data.q1.label',
    titleKey: 'data.q1.title',
    subtitleKey: 'data.q1.sub',
    color: 'teal',
    cssVar: '--color-teal',
  },
  {
    key: 'q2',
    labelKey: 'data.q2.label',
    titleKey: 'data.q2.title',
    subtitleKey: 'data.q2.sub',
    color: 'orange',
    cssVar: '--color-orange',
  },
  {
    key: 'q3',
    labelKey: 'data.q3.label',
    titleKey: 'data.q3.title',
    subtitleKey: 'data.q3.sub',
    color: 'purple',
    cssVar: '--color-purple',
  },
  {
    key: 'q4',
    labelKey: 'data.q4.label',
    titleKey: 'data.q4.title',
    subtitleKey: 'data.q4.sub',
    color: 'emerald',
    cssVar: '--color-emerald',
  },
];
