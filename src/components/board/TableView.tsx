import { useState, useMemo } from 'react';
import { safeChecklist, COLUMN_PRESETS, getColumnLabel, type BoardItem, type BoardI18n } from '../../types/board';

interface Props {
  items: BoardItem[];
  columns: string[];
  i18n: BoardI18n;
  onOpenDetail: (item: BoardItem) => void;
  onMove: (itemId: string, newStatus: string) => void;
}

type SortKey = 'title' | 'assignee' | 'status' | 'baseline' | 'forecast' | 'deviation' | 'checklist';
type SortDir = 'asc' | 'desc';

// p160 bug fix: schedule-aware deviation. Mirrors CardDetail Desvio badge logic (commit e34e2df).
// Returns null when baseline+forecast missing. Positive = behind schedule / late. Negative = early.
// Three modes:
//   actual_completion_date set → final accounting: actual − baseline
//   active + today > forecast → overdue: today − forecast (forced positive, signals red)
//   active + today ≤ forecast → planning variance: forecast − baseline
function computeDeviation(item: BoardItem): number | null {
  if (!item.baseline_date || !item.forecast_date) return null;
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const baseline = new Date(item.baseline_date);
  const forecast = new Date(item.forecast_date);
  const actual = item.actual_completion_date ? new Date(item.actual_completion_date) : null;
  if (actual) return Math.round((actual.getTime() - baseline.getTime()) / 86400000);
  if (today.getTime() > forecast.getTime()) return Math.round((today.getTime() - forecast.getTime()) / 86400000);
  return Math.round((forecast.getTime() - baseline.getTime()) / 86400000);
}

function deviationCellMode(item: BoardItem): 'concluded' | 'overdue' | 'planning' | 'none' {
  if (!item.baseline_date || !item.forecast_date) return 'none';
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const forecast = new Date(item.forecast_date);
  if (item.actual_completion_date) return 'concluded';
  if (today.getTime() > forecast.getTime()) return 'overdue';
  return 'planning';
}

export default function TableView({ items, columns, i18n, onOpenDetail, onMove }: Props) {
  const [sortKey, setSortKey] = useState<SortKey>('title');
  const [sortDir, setSortDir] = useState<SortDir>('asc');

  const toggleSort = (key: SortKey) => {
    if (sortKey === key) setSortDir(d => d === 'asc' ? 'desc' : 'asc');
    else { setSortKey(key); setSortDir('asc'); }
  };

  const sorted = useMemo(() => {
    const arr = [...items];
    const dir = sortDir === 'asc' ? 1 : -1;
    arr.sort((a, b) => {
      switch (sortKey) {
        case 'title': return dir * a.title.localeCompare(b.title);
        case 'assignee': return dir * (a.assignee_name || '').localeCompare(b.assignee_name || '');
        case 'status': return dir * a.status.localeCompare(b.status);
        case 'baseline': return dir * ((a.baseline_date || '').localeCompare(b.baseline_date || ''));
        case 'forecast': return dir * ((a.forecast_date || '').localeCompare(b.forecast_date || ''));
        case 'deviation': {
          const devA = computeDeviation(a) ?? -Infinity;
          const devB = computeDeviation(b) ?? -Infinity;
          return dir * (devA - devB);
        }
        case 'checklist': {
          const clA = safeChecklist(a.checklist), clB = safeChecklist(b.checklist);
          const pctA = clA.length ? clA.filter(c => c.done).length / clA.length : 0;
          const pctB = clB.length ? clB.filter(c => c.done).length / clB.length : 0;
          return dir * (pctA - pctB);
        }
        default: return 0;
      }
    });
    return arr;
  }, [items, sortKey, sortDir]);

  const SortHeader = ({ label, k }: { label: string; k: SortKey }) => (
    <th onClick={() => toggleSort(k)}
      className="px-3 py-2 text-left text-[10px] font-bold text-[var(--text-secondary)] uppercase tracking-wide cursor-pointer hover:text-[var(--text-primary)] whitespace-nowrap select-none">
      {label} {sortKey === k ? (sortDir === 'asc' ? '↑' : '↓') : ''}
    </th>
  );

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-[12px] border-collapse">
        <thead className="border-b border-[var(--border-default)]">
          <tr>
            <SortHeader label="Título" k="title" />
            <SortHeader label="Responsável" k="assignee" />
            <th className="px-3 py-2 text-left text-[10px] font-bold text-[var(--text-secondary)] uppercase tracking-wide">Tags</th>
            <SortHeader label="Status" k="status" />
            <SortHeader label="Baseline" k="baseline" />
            <SortHeader label="Forecast" k="forecast" />
            <SortHeader label="Desvio" k="deviation" />
            <SortHeader label="Checklist" k="checklist" />
          </tr>
        </thead>
        <tbody>
          {sorted.map((item) => {
            const dev = computeDeviation(item);
            const devMode = deviationCellMode(item);
            const devColor = dev === null ? ''
              : devMode === 'overdue' ? 'text-red-600'
              : dev <= 0 ? 'text-emerald-600'
              : dev <= 7 ? 'text-amber-600'
              : 'text-red-600';
            const devIcon = dev === null ? ''
              : devMode === 'overdue' ? '🔴'
              : devMode === 'concluded' ? (dev <= 0 ? '✅' : '🟠')
              : dev <= 0 ? '✅' : dev <= 7 ? '⚠️' : '🔴';
            const devPrefix = devMode === 'overdue' ? '+' : devMode === 'concluded' && dev > 0 ? '+' : '';
            const devTitle = devMode === 'overdue' ? `Atrasado ${dev}d (forecast venceu)`
              : devMode === 'concluded' ? (dev <= 0 ? `Concluído ${Math.abs(dev)}d antes` : `Concluído ${dev}d após baseline`)
              : dev === null ? '' : dev === 0 ? 'No prazo' : dev < 0 ? `${Math.abs(dev)}d adiantado` : `Forecast ${dev}d após baseline`;
            const _cl = safeChecklist(item.checklist);
            const checkDone = _cl.filter(c => c.done).length;
            const checkTotal = _cl.length;
            const assignees = item.assignments?.length
              ? item.assignments.map(a => a.name).join(', ')
              : item.assignee_name || '—';

            return (
              <tr key={item.id}
                onClick={() => onOpenDetail(item)}
                className="border-b border-[var(--border-subtle)] hover:bg-[var(--surface-hover)] cursor-pointer transition-colors">
                <td className="px-3 py-2.5 font-semibold text-[var(--text-primary)] max-w-[250px] truncate">
                  {item.is_mirror && <span className="mr-1">🔗</span>}
                  {item.title}
                </td>
                <td className="px-3 py-2.5 text-[var(--text-secondary)] max-w-[150px] truncate">{assignees}</td>
                <td className="px-3 py-2.5">
                  <div className="flex flex-wrap gap-0.5">
                    {item.tags?.slice(0, 3).map(t => (
                      <span key={t} className="px-1 py-0.5 bg-blue-50 text-blue-700 rounded text-[9px]">{t}</span>
                    ))}
                  </div>
                </td>
                <td className="px-3 py-2.5">
                  <select value={item.status}
                    onClick={(e) => e.stopPropagation()}
                    onChange={(e) => { e.stopPropagation(); onMove(item.id, e.target.value); }}
                    className="rounded border border-[var(--border-default)] px-1 py-0.5 text-[10px] bg-[var(--surface-card)] outline-none cursor-pointer">
                    {columns.map(col => (
                      <option key={col} value={col}>{getColumnLabel(col)}</option>
                    ))}
                  </select>
                </td>
                <td className="px-3 py-2.5 text-[var(--text-muted)] whitespace-nowrap">{item.baseline_date || '—'}</td>
                <td className="px-3 py-2.5 text-[var(--text-muted)] whitespace-nowrap">{item.forecast_date || '—'}</td>
                <td className={`px-3 py-2.5 font-bold whitespace-nowrap ${devColor}`} title={devTitle}>
                  {dev !== null ? `${devIcon} ${devPrefix}${dev}d` : '—'}
                </td>
                <td className="px-3 py-2.5 text-[var(--text-muted)]">{checkTotal > 0 ? `${checkDone}/${checkTotal}` : '—'}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
      {sorted.length === 0 && (
        <div className="text-center py-8 text-[var(--text-muted)] text-[13px]">{i18n.empty || 'No cards found'}</div>
      )}
    </div>
  );
}
