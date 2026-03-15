import type { PortfolioFilters as Filters, TribeSummary, TypeBreakdown } from '../../hooks/usePortfolio';

interface Props {
  filters: Filters;
  setFilters: (fn: (f: Filters) => Filters) => void;
  clearFilters: () => void;
  hasActive: boolean;
  tribes: TribeSummary[];
  types: TypeBreakdown[];
}

const STATUSES = [
  { value: 'backlog', label: 'Backlog' },
  { value: 'in_progress', label: 'Em Andamento' },
  { value: 'review', label: 'Revisão' },
  { value: 'done', label: 'Concluído' },
];

const HEALTH_OPTIONS = [
  { value: 'on_track', label: '🟢 No Prazo' },
  { value: 'at_risk', label: '🟡 Em Risco' },
  { value: 'delayed', label: '🔴 Atrasado' },
  { value: 'no_baseline', label: '⚪ Sem Baseline' },
  { value: 'completed', label: '✅ Concluído' },
];

const QUARTERS = ['Q1', 'Q2', 'Q3', 'Q4'];

const selectCls = 'px-2.5 py-1.5 rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[11px] text-[var(--text-primary)] font-semibold cursor-pointer';

export default function PortfolioFilters({ filters, setFilters, clearFilters, hasActive, tribes, types }: Props) {
  const set = (key: keyof Filters, value: any) =>
    setFilters(f => ({ ...f, [key]: value || null }));

  return (
    <div className="flex flex-wrap items-center gap-2">
      <select className={selectCls} value={filters.tribe ?? ''} onChange={e => set('tribe', e.target.value ? Number(e.target.value) : null)}>
        <option value="">Todas as Tribos</option>
        {tribes.map(t => (
          <option key={t.tribe_id} value={t.tribe_id}>T{t.tribe_id} — {t.tribe_name}</option>
        ))}
      </select>

      <select className={selectCls} value={filters.type ?? ''} onChange={e => set('type', e.target.value)}>
        <option value="">Todos os Tipos</option>
        {types.map(t => (
          <option key={t.type} value={t.type}>{t.label} ({t.count})</option>
        ))}
      </select>

      <select className={selectCls} value={filters.status ?? ''} onChange={e => set('status', e.target.value)}>
        <option value="">Todos os Status</option>
        {STATUSES.map(s => <option key={s.value} value={s.value}>{s.label}</option>)}
      </select>

      <select className={selectCls} value={filters.health ?? ''} onChange={e => set('health', e.target.value)}>
        <option value="">Toda Saúde</option>
        {HEALTH_OPTIONS.map(h => <option key={h.value} value={h.value}>{h.label}</option>)}
      </select>

      <select className={selectCls} value={filters.quarter ?? ''} onChange={e => set('quarter', e.target.value)}>
        <option value="">Todo Período</option>
        {QUARTERS.map(q => <option key={q} value={q}>{q} 2026</option>)}
      </select>

      <input
        type="text"
        placeholder="Buscar..."
        className="px-2.5 py-1.5 rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[11px] text-[var(--text-primary)] w-36"
        value={filters.search}
        onChange={e => setFilters(f => ({ ...f, search: e.target.value }))}
      />

      {hasActive && (
        <button
          onClick={clearFilters}
          className="px-2.5 py-1.5 rounded-lg bg-red-50 border border-red-200 text-red-700 text-[10px] font-bold cursor-pointer hover:bg-red-100 border-0"
        >
          Limpar Filtros
        </button>
      )}
    </div>
  );
}
