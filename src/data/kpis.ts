// ─── KPI goals for 2026 — aligned with GP-Sponsor agreement (12/Oct/2025) ───

export interface Kpi {
  value: string;
  labelKey: string;  // i18n key like 'data.kpi.chapters'
}

export const KPIS: Kpi[] = [
  { value: '8',      labelKey: 'data.kpi.chapters' },
  { value: '3',      labelKey: 'data.kpi.partners' },
  { value: '70%',    labelKey: 'data.kpi.certTrail' },
  { value: '2',      labelKey: 'data.kpi.cpmai' },
  { value: '+10',    labelKey: 'data.kpi.articles' },
  { value: '+6',     labelKey: 'data.kpi.webinars' },
  { value: '3',      labelKey: 'data.kpi.pilots' },
  { value: '90h',    labelKey: 'data.kpi.meetings' },
  { value: '1.800h', labelKey: 'data.kpi.impact' },
];
