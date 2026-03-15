import { useState, useMemo } from 'react';
import type { Artifact } from '../../hooks/usePortfolio';

interface Props {
  artifacts: Artifact[];
}

type SortKey = 'tribe_id' | 'title' | 'status' | 'baseline_date' | 'variance_days' | 'health' | 'checklist';
type SortDir = 'asc' | 'desc';

const HEALTH_BADGE: Record<string, { label: string; cls: string }> = {
  on_track: { label: '🟢 No Prazo', cls: 'bg-green-50 text-green-700 border-green-200' },
  at_risk: { label: '🟡 Em Risco', cls: 'bg-amber-50 text-amber-700 border-amber-200' },
  delayed: { label: '🔴 Atrasado', cls: 'bg-red-50 text-red-700 border-red-200' },
  no_baseline: { label: '⚪ Sem Base', cls: 'bg-gray-50 text-gray-600 border-gray-200' },
  completed: { label: '✅ Concluído', cls: 'bg-emerald-50 text-emerald-700 border-emerald-200' },
};

const STATUS_LABEL: Record<string, string> = {
  backlog: 'Backlog',
  in_progress: 'Em Andamento',
  review: 'Revisão',
  done: 'Concluído',
  todo: 'A Fazer',
};

function fmtDate(d: string | null) {
  if (!d) return '—';
  const dt = new Date(d + 'T00:00:00');
  return dt.toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' });
}

export default function PortfolioTable({ artifacts }: Props) {
  const [sortKey, setSortKey] = useState<SortKey>('tribe_id');
  const [sortDir, setSortDir] = useState<SortDir>('asc');

  const sorted = useMemo(() => {
    return [...artifacts].sort((a, b) => {
      let cmp = 0;
      switch (sortKey) {
        case 'tribe_id': cmp = a.tribe_id - b.tribe_id; break;
        case 'title': cmp = a.title.localeCompare(b.title); break;
        case 'status': cmp = (a.status || '').localeCompare(b.status || ''); break;
        case 'baseline_date': cmp = (a.baseline_date || '9').localeCompare(b.baseline_date || '9'); break;
        case 'variance_days': cmp = (a.variance_days ?? 999) - (b.variance_days ?? 999); break;
        case 'health': cmp = a.health.localeCompare(b.health); break;
        case 'checklist': {
          const pA = a.checklist_total ? a.checklist_done / a.checklist_total : 0;
          const pB = b.checklist_total ? b.checklist_done / b.checklist_total : 0;
          cmp = pA - pB; break;
        }
      }
      return sortDir === 'asc' ? cmp : -cmp;
    });
  }, [artifacts, sortKey, sortDir]);

  const toggleSort = (key: SortKey) => {
    if (sortKey === key) setSortDir(d => d === 'asc' ? 'desc' : 'asc');
    else { setSortKey(key); setSortDir('asc'); }
  };

  const thCls = 'px-2 py-2 text-left text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)] cursor-pointer hover:text-[var(--text-primary)] select-none whitespace-nowrap';
  const arrow = (key: SortKey) => sortKey === key ? (sortDir === 'asc' ? ' ↑' : ' ↓') : '';

  return (
    <div className="rounded-xl border border-[var(--border-default)] overflow-x-auto">
      <table className="w-full text-[12px]">
        <thead className="bg-[var(--surface-section-cool)]">
          <tr>
            <th className={thCls} onClick={() => toggleSort('tribe_id')}>Tribo{arrow('tribe_id')}</th>
            <th className={thCls} onClick={() => toggleSort('title')}>Artefato{arrow('title')}</th>
            <th className={thCls}>Tipo</th>
            <th className={thCls}>Líder</th>
            <th className={thCls} onClick={() => toggleSort('baseline_date')}>Baseline{arrow('baseline_date')}</th>
            <th className={thCls}>Forecast</th>
            <th className={thCls} onClick={() => toggleSort('variance_days')}>Desvio{arrow('variance_days')}</th>
            <th className={thCls} onClick={() => toggleSort('checklist')}>Atividades{arrow('checklist')}</th>
            <th className={thCls} onClick={() => toggleSort('health')}>Saúde{arrow('health')}</th>
            <th className={thCls} onClick={() => toggleSort('status')}>Status{arrow('status')}</th>
          </tr>
        </thead>
        <tbody>
          {sorted.map(a => {
            const hb = HEALTH_BADGE[a.health] || HEALTH_BADGE.no_baseline;
            const mainTag = a.unified_tags?.[0];
            return (
              <tr key={a.id} className="border-t border-[var(--border-subtle)] hover:bg-[var(--surface-hover)] transition-colors">
                <td className="px-2 py-2 font-bold text-[var(--text-secondary)]">T{a.tribe_id}</td>
                <td className="px-2 py-2 max-w-[220px]">
                  <a href={`/tribe/${a.tribe_id}`} className="text-[var(--text-primary)] font-semibold no-underline hover:underline line-clamp-1">
                    {a.title}
                  </a>
                </td>
                <td className="px-2 py-2">
                  {mainTag && (
                    <span className="inline-block px-1.5 py-0.5 rounded text-[9px] font-bold" style={{ backgroundColor: mainTag.color + '20', color: mainTag.color }}>
                      {mainTag.label}
                    </span>
                  )}
                </td>
                <td className="px-2 py-2 text-[var(--text-secondary)] whitespace-nowrap">{a.leader_name?.split(' ')[0]}</td>
                <td className="px-2 py-2 whitespace-nowrap">{fmtDate(a.baseline_date)}</td>
                <td className="px-2 py-2 whitespace-nowrap">{fmtDate(a.forecast_date)}</td>
                <td className="px-2 py-2 whitespace-nowrap text-center">
                  {a.variance_days !== null ? (
                    <span className={a.variance_days > 0 ? 'text-red-600 font-bold' : a.variance_days < 0 ? 'text-green-600' : ''}>
                      {a.variance_days > 0 ? '+' : ''}{a.variance_days}d
                    </span>
                  ) : '—'}
                </td>
                <td className="px-2 py-2 whitespace-nowrap">
                  {a.checklist_total > 0 ? `${a.checklist_done}/${a.checklist_total}` : '—'}
                </td>
                <td className="px-2 py-2">
                  <span className={`inline-block px-1.5 py-0.5 rounded border text-[9px] font-bold ${hb.cls}`}>{hb.label}</span>
                </td>
                <td className="px-2 py-2 text-[var(--text-secondary)]">{STATUS_LABEL[a.status] || a.status}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
      {sorted.length === 0 && (
        <div className="text-center py-8 text-[var(--text-muted)] text-sm">Nenhum artefato encontrado com os filtros aplicados.</div>
      )}
    </div>
  );
}
