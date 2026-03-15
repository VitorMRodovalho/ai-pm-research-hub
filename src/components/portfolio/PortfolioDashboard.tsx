import { useState } from 'react';
import { usePortfolio } from '../../hooks/usePortfolio';
import PortfolioKPIs from './PortfolioKPIs';
import PortfolioFilters from './PortfolioFilters';
import PortfolioTable from './PortfolioTable';
import PortfolioGantt from './PortfolioGantt';
import PortfolioHeatmap from './PortfolioHeatmap';
import PortfolioTribeCards from './PortfolioTribeCards';

type Tab = 'table' | 'gantt' | 'heatmap' | 'tribes';

const TABS: { key: Tab; label: string }[] = [
  { key: 'table', label: 'Tabela' },
  { key: 'gantt', label: 'Gantt' },
  { key: 'heatmap', label: 'Heatmap' },
  { key: 'tribes', label: 'Tribos' },
];

export default function PortfolioDashboard() {
  const { data, filtered, filters, setFilters, clearFilters, hasActiveFilters, loading, error } = usePortfolio(3);
  const [tab, setTab] = useState<Tab>('table');

  if (loading) {
    return (
      <div className="space-y-4 animate-pulse">
        <div className="grid grid-cols-2 sm:grid-cols-5 gap-3">
          {[1, 2, 3, 4, 5].map(n => (
            <div key={n} className="h-20 rounded-xl bg-[var(--surface-hover)]" />
          ))}
        </div>
        <div className="h-10 w-72 rounded-xl bg-[var(--surface-hover)]" />
        <div className="h-64 rounded-xl bg-[var(--surface-hover)]" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-red-50 border border-red-200 rounded-xl p-6 text-center">
        <p className="font-bold text-red-700">Erro ao carregar portfólio</p>
        <p className="text-sm text-red-600 mt-1">{error}</p>
      </div>
    );
  }

  if (!data) return null;

  return (
    <div className="space-y-4">
      <PortfolioKPIs summary={data.summary} />

      <PortfolioFilters
        filters={filters}
        setFilters={setFilters}
        clearFilters={clearFilters}
        hasActive={hasActiveFilters}
        tribes={data.by_tribe}
        types={data.by_type}
      />

      {/* Tabs */}
      <div className="flex gap-1 bg-[var(--surface-section-cool)] rounded-xl p-1">
        {TABS.map(t => (
          <button
            key={t.key}
            onClick={() => setTab(t.key)}
            className={`flex-1 px-3 py-2 rounded-lg text-xs font-bold border-0 cursor-pointer transition-all ${
              tab === t.key
                ? 'bg-[var(--surface-card)] text-[var(--text-primary)] shadow-sm'
                : 'bg-transparent text-[var(--text-muted)] hover:text-[var(--text-secondary)]'
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      {/* View content */}
      {tab === 'table' && <PortfolioTable artifacts={filtered} />}
      {tab === 'gantt' && <PortfolioGantt artifacts={filtered} />}
      {tab === 'heatmap' && (
        <PortfolioHeatmap
          byMonth={data.by_month}
          tribes={data.by_tribe}
          artifacts={data.artifacts}
          onCellClick={(tribe, month) => {
            setFilters(f => ({ ...f, tribe, month }));
            setTab('table');
          }}
        />
      )}
      {tab === 'tribes' && <PortfolioTribeCards tribes={data.by_tribe} />}

      {/* Footer */}
      <div className="text-[10px] text-[var(--text-muted)] text-right">
        {filtered.length} de {data.summary.total_artifacts} artefatos
        {hasActiveFilters && ' (filtrado)'}
        {' · '}Gerado: {new Date(data.generated_at).toLocaleString('pt-BR')}
      </div>
    </div>
  );
}
