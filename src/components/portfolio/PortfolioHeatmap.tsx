import { useMemo } from 'react';
import type { MonthBreakdown, TribeSummary, Artifact } from '../../hooks/usePortfolio';

interface Props {
  byMonth: MonthBreakdown[];
  tribes: TribeSummary[];
  artifacts: Artifact[];
  onCellClick: (tribe: number, month: string) => void;
}

function fmtMonth(m: string) {
  const [y, mo] = m.split('-');
  const dt = new Date(Number(y), Number(mo) - 1, 1);
  return dt.toLocaleDateString('pt-BR', { month: 'short' }).replace('.', '');
}

const INTENSITY: string[] = [
  'bg-gray-50',
  'bg-teal/10',
  'bg-teal/25',
  'bg-teal/40',
  'bg-teal/60',
];

function getIntensityClass(count: number): string {
  if (count === 0) return INTENSITY[0];
  if (count === 1) return INTENSITY[1];
  if (count === 2) return INTENSITY[2];
  if (count === 3) return INTENSITY[3];
  return INTENSITY[4];
}

export default function PortfolioHeatmap({ tribes, artifacts, onCellClick }: Props) {
  // Build matrix: tribe_id × month → count
  const { months, matrix } = useMemo(() => {
    const monthSet = new Set<string>();
    const matrixMap = new Map<string, number>(); // "tribe_id:month" → count

    for (const a of artifacts) {
      if (!a.baseline_date) continue;
      const month = a.baseline_date.slice(0, 7);
      monthSet.add(month);
      const key = `${a.tribe_id}:${month}`;
      matrixMap.set(key, (matrixMap.get(key) || 0) + 1);
    }

    const sortedMonths = Array.from(monthSet).sort();
    return { months: sortedMonths, matrix: matrixMap };
  }, [artifacts]);

  const cellCls = 'w-10 h-10 flex items-center justify-center text-[11px] font-bold cursor-pointer rounded transition-all hover:ring-2 hover:ring-teal';

  return (
    <div className="rounded-xl border border-[var(--border-default)] overflow-x-auto">
      <table className="w-full text-[11px]">
        <thead>
          <tr className="bg-[var(--surface-section-cool)]">
            <th className="px-3 py-2 text-left text-[10px] font-bold text-[var(--text-muted)] uppercase sticky left-0 bg-[var(--surface-section-cool)] z-10">Tribo</th>
            {months.map(m => (
              <th key={m} className="px-1 py-2 text-center text-[10px] font-bold text-[var(--text-muted)] uppercase whitespace-nowrap">
                {fmtMonth(m)}
              </th>
            ))}
            <th className="px-2 py-2 text-center text-[10px] font-bold text-[var(--text-muted)] uppercase">Total</th>
          </tr>
        </thead>
        <tbody>
          {tribes.map(tribe => {
            const total = artifacts.filter(a => a.tribe_id === tribe.tribe_id && a.baseline_date).length;
            const noBaseline = artifacts.filter(a => a.tribe_id === tribe.tribe_id && !a.baseline_date).length;
            return (
              <tr key={tribe.tribe_id} className="border-t border-[var(--border-subtle)] hover:bg-[var(--surface-hover)]">
                <td className="px-3 py-1 font-bold text-[var(--text-primary)] whitespace-nowrap sticky left-0 bg-[var(--surface-card)] z-10">
                  T{tribe.tribe_id}
                  <span className="ml-1 text-[9px] text-[var(--text-muted)] font-normal">{tribe.tribe_name}</span>
                </td>
                {months.map(m => {
                  const count = matrix.get(`${tribe.tribe_id}:${m}`) || 0;
                  return (
                    <td key={m} className="px-1 py-1 text-center">
                      <div
                        className={`${cellCls} ${getIntensityClass(count)} mx-auto`}
                        onClick={() => count > 0 && onCellClick(tribe.tribe_id, m)}
                        title={`T${tribe.tribe_id} · ${fmtMonth(m)}: ${count} artefato(s)`}
                      >
                        {count > 0 ? count : ''}
                      </div>
                    </td>
                  );
                })}
                <td className="px-2 py-1 text-center font-bold text-[var(--text-primary)]">
                  {total}
                  {noBaseline > 0 && <span className="text-[9px] text-gray-400 ml-0.5">+{noBaseline}</span>}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>

      {/* Legend */}
      <div className="flex items-center gap-3 px-3 py-2 border-t border-[var(--border-subtle)] bg-[var(--surface-section-cool)]">
        <span className="text-[10px] text-[var(--text-muted)]">Intensidade:</span>
        {[0, 1, 2, 3, 4].map(n => (
          <div key={n} className="flex items-center gap-1">
            <div className={`w-4 h-4 rounded ${getIntensityClass(n)}`} />
            <span className="text-[9px] text-[var(--text-muted)]">{n === 0 ? '0' : n === 4 ? '4+' : n}</span>
          </div>
        ))}
        <span className="text-[10px] text-[var(--text-muted)] ml-auto">Clique na célula para filtrar na tabela</span>
      </div>
    </div>
  );
}
