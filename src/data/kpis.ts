// ─── KPI goals for 2026 — i18n via translation keys ───

export interface Kpi {
  value: string;
  labelKey: string;  // i18n key like 'data.kpi.chapters'
}

export const KPIS: Kpi[] = [
  { value: '8',      labelKey: 'data.kpi.chapters' },
  { value: '+10',    labelKey: 'data.kpi.articles' },
  { value: '+6',     labelKey: 'data.kpi.webinars' },
  { value: '3',      labelKey: 'data.kpi.pilots' },
  { value: '1.800h', labelKey: 'data.kpi.impact' },
  { value: '70%',    labelKey: 'data.kpi.cert' },
];
