import type { FilterState } from '../../hooks/useBoardFilters';
import type { BoardI18n } from '../../types/board';

interface Props {
  filters: FilterState;
  hasActive: boolean;
  allTags: string[];
  allAssignees: { id: string; name: string }[];
  onSearch: (v: string) => void;
  onAssignee: (v: string | null) => void;
  onTags: (v: string[]) => void;
  onDueDate: (v: FilterState['dueDateFilter']) => void;
  onClear: () => void;
  showCuration?: boolean;
  onCurationStatus?: (v: string | null) => void;
  i18n: BoardI18n;
}

export default function BoardFilters({
  filters, hasActive, allTags, allAssignees,
  onSearch, onAssignee, onDueDate, onClear, showCuration, onCurationStatus, i18n,
}: Props) {
  return (
    <div className="flex items-center gap-2 flex-wrap">
      {/* Search */}
      <div className="relative min-w-[180px] max-w-xs flex-1">
        <input
          type="text"
          value={filters.search}
          onChange={(e) => onSearch(e.target.value)}
          placeholder={i18n.search || 'Buscar...'}
          className="w-full rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] px-3 py-2 text-[12px]
            text-[var(--text-primary)] outline-none focus:border-blue-400 transition-all pl-8"
        />
        <svg className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-[var(--text-muted)]" fill="none"
          stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="m21 21-4.34-4.34M11 19a8 8 0 100-16 8 8 0 000 16z" />
        </svg>
        {filters.search && (
          <button onClick={() => onSearch('')}
            className="absolute right-2 top-1/2 -translate-y-1/2 text-[var(--text-muted)] hover:text-[var(--text-secondary)] 
              cursor-pointer bg-transparent border-0 text-sm">✕</button>
        )}
      </div>

      {/* Assignee filter */}
      {allAssignees.length > 0 && (
        <select
          value={filters.assigneeId || ''}
          onChange={(e) => onAssignee(e.target.value || null)}
          className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] px-3 py-2 text-[12px] text-[var(--text-secondary)]
            outline-none focus:border-blue-400 cursor-pointer"
        >
          <option value="">👤 Todos</option>
          {allAssignees.map((a) => (
            <option key={a.id} value={a.id}>{a.name}</option>
          ))}
        </select>
      )}

      {/* Due date filter */}
      <select
        value={filters.dueDateFilter}
        onChange={(e) => onDueDate(e.target.value as any)}
        className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] px-3 py-2 text-[12px] text-[var(--text-secondary)]
          outline-none focus:border-blue-400 cursor-pointer"
      >
        <option value="all">📅 Todas as datas</option>
        <option value="overdue">🔴 Vencidos</option>
        <option value="week">📆 Próximos 7 dias</option>
        <option value="none">{i18n.noDate || 'No date'}</option>
      </select>

      {/* Curation status filter */}
      {showCuration && onCurationStatus && (
        <select
          value={filters.curationStatus || ''}
          onChange={(e) => onCurationStatus(e.target.value || null)}
          className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] px-3 py-2 text-[12px] text-[var(--text-secondary)]
            outline-none focus:border-blue-400 cursor-pointer"
        >
          <option value="">🔍 Curadoria: Todos</option>
          <option value="draft">{i18n.draftFilter || 'Pending'}</option>
          <option value="review">Em revisão</option>
          <option value="approved">{i18n.approve || 'Approved'}</option>
          <option value="rejected">Descartado</option>
        </select>
      )}

      {/* Clear */}
      {hasActive && (
        <button onClick={onClear}
          className="px-3 py-2 rounded-xl text-[11px] font-semibold text-red-500 hover:bg-red-50
            cursor-pointer border border-red-200 bg-[var(--surface-card)] transition-colors">
          ✕ Limpar filtros
        </button>
      )}
    </div>
  );
}
