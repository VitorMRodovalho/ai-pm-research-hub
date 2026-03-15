import { useState, useMemo, useRef, useEffect } from 'react';
import { safeChecklist, type BoardItem, type BoardI18n } from '../../types/board';

interface Props {
  items: BoardItem[];
  i18n: BoardI18n;
  onOpenDetail: (item: BoardItem) => void;
}

type ZoomLevel = 'week' | 'month' | 'quarter' | 'year';

const MONTHS_SHORT = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];

const ZOOM_LABELS: Record<ZoomLevel, string> = { week: 'Semana', month: 'Mês', quarter: 'Trimestre', year: 'Ano' };
const ZOOM_MIN_WIDTH: Record<ZoomLevel, string> = { week: '1400px', month: '900px', quarter: '600px', year: '400px' };

export default function TimelineView({ items, i18n, onOpenDetail }: Props) {
  const [zoom, setZoom] = useState<ZoomLevel>('month');
  const containerRef = useRef<HTMLDivElement>(null);

  // Only show items that have at least one date
  const datedItems = useMemo(() =>
    items.filter(i => i.baseline_date || i.forecast_date || i.due_date)
      .sort((a, b) => {
        const da = a.baseline_date || a.forecast_date || a.due_date || '';
        const db = b.baseline_date || b.forecast_date || b.due_date || '';
        return da.localeCompare(db);
      }),
    [items]
  );

  // Calculate time range
  const { startDate, endDate, totalDays } = useMemo(() => {
    if (datedItems.length === 0) {
      const now = new Date();
      return {
        startDate: new Date(now.getFullYear(), now.getMonth(), 1),
        endDate: new Date(now.getFullYear(), now.getMonth() + 3, 0),
        totalDays: 90,
      };
    }

    const dates = datedItems.flatMap(i => [i.baseline_date, i.forecast_date, i.actual_completion_date, i.due_date].filter(Boolean)) as string[];
    const min = new Date(Math.min(...dates.map(d => new Date(d).getTime())));
    const max = new Date(Math.max(...dates.map(d => new Date(d).getTime())));

    // Pad by 7 days on each side
    const start = new Date(min.getFullYear(), min.getMonth(), 1);
    const end = new Date(max.getFullYear(), max.getMonth() + 2, 0);
    const days = Math.ceil((end.getTime() - start.getTime()) / 86400000) || 90;

    return { startDate: start, endDate: end, totalDays: days };
  }, [datedItems]);

  const dayToX = (dateStr: string) => {
    const d = new Date(dateStr);
    const dayOffset = Math.round((d.getTime() - startDate.getTime()) / 86400000);
    return Math.max(0, Math.min(100, (dayOffset / totalDays) * 100));
  };

  // Generate time headers based on zoom level
  const timeHeaders = useMemo(() => {
    const headers: { label: string; left: number; width: number }[] = [];
    const d = new Date(startDate);

    if (zoom === 'week') {
      // Align to Monday
      const dayOfWeek = d.getDay();
      d.setDate(d.getDate() - ((dayOfWeek + 6) % 7));
      while (d <= endDate) {
        const weekStart = new Date(d);
        const weekEnd = new Date(d);
        weekEnd.setDate(weekEnd.getDate() + 6);
        const startOff = Math.max(0, Math.round((weekStart.getTime() - startDate.getTime()) / 86400000));
        const endOff = Math.min(totalDays, Math.round((weekEnd.getTime() - startDate.getTime()) / 86400000));
        headers.push({
          label: `${weekStart.getDate()}/${weekStart.getMonth() + 1}`,
          left: (startOff / totalDays) * 100,
          width: ((endOff - startOff) / totalDays) * 100,
        });
        d.setDate(d.getDate() + 7);
      }
    } else if (zoom === 'month') {
      while (d <= endDate) {
        const monthStart = new Date(d.getFullYear(), d.getMonth(), 1);
        const monthEnd = new Date(d.getFullYear(), d.getMonth() + 1, 0);
        const startOff = Math.max(0, Math.round((monthStart.getTime() - startDate.getTime()) / 86400000));
        const endOff = Math.min(totalDays, Math.round((monthEnd.getTime() - startDate.getTime()) / 86400000));
        headers.push({
          label: `${MONTHS_SHORT[d.getMonth()]} ${d.getFullYear()}`,
          left: (startOff / totalDays) * 100,
          width: ((endOff - startOff) / totalDays) * 100,
        });
        d.setMonth(d.getMonth() + 1);
      }
    } else if (zoom === 'quarter') {
      // Align to quarter start
      d.setMonth(Math.floor(d.getMonth() / 3) * 3);
      while (d <= endDate) {
        const qStart = new Date(d.getFullYear(), d.getMonth(), 1);
        const qEnd = new Date(d.getFullYear(), d.getMonth() + 3, 0);
        const startOff = Math.max(0, Math.round((qStart.getTime() - startDate.getTime()) / 86400000));
        const endOff = Math.min(totalDays, Math.round((qEnd.getTime() - startDate.getTime()) / 86400000));
        const qNum = Math.floor(d.getMonth() / 3) + 1;
        headers.push({
          label: `Q${qNum} ${d.getFullYear()}`,
          left: (startOff / totalDays) * 100,
          width: ((endOff - startOff) / totalDays) * 100,
        });
        d.setMonth(d.getMonth() + 3);
      }
    } else {
      // year
      d.setMonth(0);
      while (d <= endDate) {
        const yStart = new Date(d.getFullYear(), 0, 1);
        const yEnd = new Date(d.getFullYear(), 11, 31);
        const startOff = Math.max(0, Math.round((yStart.getTime() - startDate.getTime()) / 86400000));
        const endOff = Math.min(totalDays, Math.round((yEnd.getTime() - startDate.getTime()) / 86400000));
        headers.push({
          label: `${d.getFullYear()}`,
          left: (startOff / totalDays) * 100,
          width: ((endOff - startOff) / totalDays) * 100,
        });
        d.setFullYear(d.getFullYear() + 1);
      }
    }

    return headers;
  }, [startDate, endDate, totalDays, zoom]);

  // Today marker
  const todayX = dayToX(new Date().toISOString().split('T')[0]);

  const BAR_HEIGHT = 28;
  const ROW_HEIGHT = 36;

  return (
    <div>
      {/* Zoom controls */}
      <div className="flex items-center gap-2 mb-3">
        <span className="text-[11px] text-[var(--text-secondary)]">Zoom:</span>
        {(['week', 'month', 'quarter', 'year'] as ZoomLevel[]).map(z => (
          <button key={z} onClick={() => setZoom(z)}
            className={`px-2 py-0.5 rounded text-[10px] font-semibold cursor-pointer border-0
              ${zoom === z ? 'bg-blue-100 text-blue-700' : 'bg-[var(--surface-section-cool)] text-[var(--text-muted)]'}`}>
            {ZOOM_LABELS[z]}
          </button>
        ))}
      </div>

      {datedItems.length === 0 ? (
        <div className="text-center py-8 text-[var(--text-muted)] text-[13px]">
          Nenhum card com datas para exibir na timeline
        </div>
      ) : (
        <div ref={containerRef} className="overflow-x-auto">
          <div style={{ minWidth: ZOOM_MIN_WIDTH[zoom] }}>
            {/* Time headers */}
            <div className="relative h-6 border-b border-[var(--border-default)] mb-1">
              {timeHeaders.map((h, idx) => (
                <div key={idx}
                  className="absolute top-0 h-full flex items-center px-1 border-l border-[var(--border-subtle)] text-[9px] font-bold text-[var(--text-muted)]"
                  style={{ left: `${h.left}%`, width: `${h.width}%` }}>
                  {h.label}
                </div>
              ))}
            </div>

            {/* Gantt rows */}
            <div className="relative" style={{ height: `${datedItems.length * ROW_HEIGHT + 8}px` }}>
              {/* Today line */}
              <div className="absolute top-0 bottom-0 w-px bg-red-400 z-10" style={{ left: `${todayX}%` }}>
                <span className="absolute -top-4 -translate-x-1/2 text-[8px] text-red-500 font-bold">Hoje</span>
              </div>

              {/* Grid lines */}
              {timeHeaders.map((h, idx) => (
                <div key={idx} className="absolute top-0 bottom-0 w-px bg-[var(--border-subtle)]"
                  style={{ left: `${h.left}%` }} />
              ))}

              {/* Item bars */}
              {datedItems.map((item, idx) => {
                const baseDate = item.baseline_date || item.due_date;
                const foreDate = item.forecast_date || item.due_date;
                if (!baseDate && !foreDate) return null;

                const barStart = dayToX(baseDate || foreDate!);
                const barEnd = dayToX(foreDate || baseDate!);
                const barWidth = Math.max(1, barEnd - barStart);

                // Checklist progress
                const _cl = safeChecklist(item.checklist);
                const checkDone = _cl.filter(c => c.done).length;
                const checkTotal = _cl.length;
                const progressPct = checkTotal > 0 ? (checkDone / checkTotal) * 100 : 0;

                // Deviation color
                const hasDeviation = baseDate && foreDate && baseDate !== foreDate;
                const devDays = hasDeviation ? Math.round((new Date(foreDate!).getTime() - new Date(baseDate!).getTime()) / 86400000) : 0;
                const barColor = item.actual_completion_date
                  ? 'bg-emerald-400'
                  : devDays > 7 ? 'bg-red-400' : devDays > 0 ? 'bg-amber-400' : 'bg-blue-400';

                return (
                  <div key={item.id}
                    className="absolute flex items-center gap-2 group"
                    style={{ top: `${idx * ROW_HEIGHT + 4}px`, left: 0, right: 0, height: `${BAR_HEIGHT}px` }}>
                    {/* Bar */}
                    <div className="absolute rounded-md overflow-hidden cursor-pointer hover:shadow-md transition-shadow"
                      style={{ left: `${barStart}%`, width: `${barWidth}%`, height: `${BAR_HEIGHT}px`, minWidth: '4px' }}
                      onClick={() => onOpenDetail(item)}
                      title={`${item.title}\nBaseline: ${baseDate || '—'}\nForecast: ${foreDate || '—'}\nActual: ${item.actual_completion_date || '—'}`}>
                      {/* Background bar */}
                      <div className={`absolute inset-0 ${barColor} opacity-30`} />
                      {/* Progress fill */}
                      <div className={`absolute inset-y-0 left-0 ${barColor} opacity-70`}
                        style={{ width: `${progressPct}%` }} />
                      {/* Label */}
                      <div className="relative z-10 flex items-center h-full px-1.5">
                        <span className="text-[9px] font-bold text-[var(--text-primary)] truncate whitespace-nowrap">
                          {item.is_mirror && '🔗 '}{item.title}
                        </span>
                      </div>
                    </div>

                    {/* Deviation extension (dotted) */}
                    {hasDeviation && devDays > 0 && (
                      <div className="absolute border-t-2 border-dashed border-red-300"
                        style={{
                          left: `${dayToX(baseDate!)}%`,
                          width: `${dayToX(foreDate!) - dayToX(baseDate!)}%`,
                          top: `${BAR_HEIGHT - 2}px`,
                        }} />
                    )}
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      )}

      {/* Legend */}
      <div className="flex items-center gap-4 mt-4 text-[9px] text-[var(--text-muted)]">
        <span><span className="inline-block w-3 h-2 bg-blue-400 rounded mr-0.5" /> No prazo</span>
        <span><span className="inline-block w-3 h-2 bg-amber-400 rounded mr-0.5" /> Risco (1-7d)</span>
        <span><span className="inline-block w-3 h-2 bg-red-400 rounded mr-0.5" /> Atrasado (&gt;7d)</span>
        <span><span className="inline-block w-3 h-2 bg-emerald-400 rounded mr-0.5" /> Concluído</span>
        <span className="border-t-2 border-dashed border-red-300 w-4 inline-block mr-0.5" /> Desvio
      </div>
    </div>
  );
}
