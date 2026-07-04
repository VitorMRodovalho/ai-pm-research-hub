// ─── Quadrant data — the 4 strategic pillars (i18n via translation keys) ───

export interface Quadrant {
  key: 'q1' | 'q2' | 'q3' | 'q4';
  labelKey: string;     // e.g. 'data.q1.label'
  titleKey: string;     // e.g. 'data.q1.title'
  subtitleKey: string;  // e.g. 'data.q1.sub'
  /** Info popover — full pillar context (data.qN.info.*) */
  infoPilarKey: string;
  infoIntroKey: string;
  infoThemeKey: string;
  infoTopicKeys: string[];
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
    infoPilarKey: 'data.q1.info.pilar',
    infoIntroKey: 'data.q1.info.intro',
    infoThemeKey: 'data.q1.info.theme',
    infoTopicKeys: ['data.q1.info.t1', 'data.q1.info.t2', 'data.q1.info.t3'],
    color: 'teal',
    cssVar: '--color-teal',
  },
  {
    key: 'q2',
    labelKey: 'data.q2.label',
    titleKey: 'data.q2.title',
    subtitleKey: 'data.q2.sub',
    infoPilarKey: 'data.q2.info.pilar',
    infoIntroKey: 'data.q2.info.intro',
    infoThemeKey: 'data.q2.info.theme',
    infoTopicKeys: ['data.q2.info.t1', 'data.q2.info.t2', 'data.q2.info.t3'],
    color: 'orange',
    cssVar: '--color-orange',
  },
  {
    key: 'q3',
    labelKey: 'data.q3.label',
    titleKey: 'data.q3.title',
    subtitleKey: 'data.q3.sub',
    infoPilarKey: 'data.q3.info.pilar',
    infoIntroKey: 'data.q3.info.intro',
    infoThemeKey: 'data.q3.info.theme',
    infoTopicKeys: ['data.q3.info.t1', 'data.q3.info.t2', 'data.q3.info.t3'],
    color: 'purple',
    cssVar: '--color-purple',
  },
  {
    key: 'q4',
    labelKey: 'data.q4.label',
    titleKey: 'data.q4.title',
    subtitleKey: 'data.q4.sub',
    infoPilarKey: 'data.q4.info.pilar',
    infoIntroKey: 'data.q4.info.intro',
    infoThemeKey: 'data.q4.info.theme',
    infoTopicKeys: ['data.q4.info.t1', 'data.q4.info.t2', 'data.q4.info.t3'],
    color: 'emerald',
    cssVar: '--color-emerald',
  },
];
