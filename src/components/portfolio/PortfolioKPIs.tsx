import type { PortfolioSummary } from '../../hooks/usePortfolio';

interface Props {
  summary: PortfolioSummary;
}

const CARDS: { key: keyof PortfolioSummary; label: string; color: string; icon: string }[] = [
  { key: 'total_artifacts', label: 'Artefatos', color: 'text-[var(--text-primary)]', icon: '📦' },
  { key: 'completed', label: 'Concluídos', color: 'text-emerald-600', icon: '✅' },
  { key: 'on_track', label: 'No Prazo', color: 'text-green-600', icon: '🟢' },
  { key: 'at_risk', label: 'Em Risco', color: 'text-amber-600', icon: '🟡' },
  { key: 'delayed', label: 'Atrasado', color: 'text-red-600', icon: '🔴' },
  { key: 'no_baseline', label: 'Sem Baseline', color: 'text-gray-500', icon: '⚪' },
];

export default function PortfolioKPIs({ summary }: Props) {
  const checkPct = summary.checklist_total > 0
    ? Math.round((summary.checklist_done / summary.checklist_total) * 100)
    : 0;

  return (
    <div className="space-y-3">
      <div className="grid grid-cols-3 sm:grid-cols-6 gap-2">
        {CARDS.map(c => (
          <div key={c.key} className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-3 text-center">
            <div className="text-[10px] text-[var(--text-muted)] mb-1">{c.icon} {c.label}</div>
            <div className={`text-2xl font-extrabold ${c.color}`}>
              {Number(summary[c.key]) || 0}
            </div>
          </div>
        ))}
      </div>
      <div className="flex flex-wrap gap-4 text-[11px] text-[var(--text-secondary)] px-1">
        <span>Variância média: <strong>{summary.avg_variance_days ?? 0}d</strong></span>
        <span>Atividades: <strong>{summary.checklist_done}/{summary.checklist_total}</strong> ({checkPct}%)</span>
        <span>Com baseline: <strong>{summary.pct_with_baseline}%</strong></span>
      </div>
    </div>
  );
}
