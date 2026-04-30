// ─── KPI goals for 2026 — aligned with GP-Sponsor agreement (12/Oct/2025) ───
//
// `surpassedFromGoal`: optional. Set when the public reality has already
// exceeded the agreed target — KpiSection then shows the celebratory
// "Meta era X · Superada" sublabel instead of the live progress bar
// (the bar would cap at 100% and hide the over-delivery).

export interface Kpi {
  value: string;
  labelKey: string;            // i18n key like 'data.kpi.chapters'
  surpassedFromGoal?: string;  // original goal value when reality exceeded it
}

export const KPIS: Kpi[] = [
  { value: '15',     labelKey: 'data.kpi.chapters', surpassedFromGoal: '8' },
  { value: '3',      labelKey: 'data.kpi.partners' },
  { value: '70%',    labelKey: 'data.kpi.certTrail' },
  { value: '2',      labelKey: 'data.kpi.cpmai' },
  { value: '+10',    labelKey: 'data.kpi.articles' },
  { value: '+6',     labelKey: 'data.kpi.webinars' },
  { value: '3',      labelKey: 'data.kpi.pilots' },
  { value: '90h',    labelKey: 'data.kpi.meetings' },
  { value: '1.800h', labelKey: 'data.kpi.impact' },
];
