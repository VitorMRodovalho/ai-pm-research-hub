import { useState, useMemo } from 'react';
import type { BoardItem, BoardI18n } from '../../types/board';
import { COLUMN_PRESETS } from '../../types/board';

interface Props {
  items: BoardItem[];
  i18n: BoardI18n;
  onOpenDetail: (item: BoardItem) => void;
}

const DAYS_PT = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
const MONTHS_PT = ['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'];

export default function CalendarView({ items, i18n, onOpenDetail }: Props) {
  const [currentDate, setCurrentDate] = useState(() => {
    const now = new Date();
    return new Date(now.getFullYear(), now.getMonth(), 1);
  });

  const year = currentDate.getFullYear();
  const month = currentDate.getMonth();

  const prevMonth = () => setCurrentDate(new Date(year, month - 1, 1));
  const nextMonth = () => setCurrentDate(new Date(year, month + 1, 1));

  // Build calendar grid
  const calendarDays = useMemo(() => {
    const firstDay = new Date(year, month, 1).getDay();
    const daysInMonth = new Date(year, month + 1, 0).getDate();
    const days: (number | null)[] = [];

    // Leading empty cells
    for (let i = 0; i < firstDay; i++) days.push(null);
    for (let d = 1; d <= daysInMonth; d++) days.push(d);
    // Trailing to fill last week
    while (days.length % 7 !== 0) days.push(null);

    return days;
  }, [year, month]);

  // Map items to dates (by forecast_date or due_date)
  const itemsByDate = useMemo(() => {
    const map = new Map<string, BoardItem[]>();
    items.forEach((item) => {
      const dateStr = item.forecast_date || item.due_date;
      if (!dateStr) return;
      const d = new Date(dateStr);
      if (d.getFullYear() === year && d.getMonth() === month) {
        const key = d.getDate().toString();
        if (!map.has(key)) map.set(key, []);
        map.get(key)!.push(item);
      }
    });
    return map;
  }, [items, year, month]);

  const today = new Date();
  const isToday = (day: number) => today.getFullYear() === year && today.getMonth() === month && today.getDate() === day;

  return (
    <div>
      {/* Month nav */}
      <div className="flex items-center justify-between mb-4">
        <button onClick={prevMonth}
          className="px-2 py-1 rounded-lg bg-[var(--surface-section-cool)] text-[var(--text-secondary)] text-[12px] font-bold
            cursor-pointer border-0 hover:bg-[var(--surface-hover)]">← Anterior</button>
        <h3 className="text-[14px] font-bold text-[var(--text-primary)]">
          {MONTHS_PT[month]} {year}
        </h3>
        <button onClick={nextMonth}
          className="px-2 py-1 rounded-lg bg-[var(--surface-section-cool)] text-[var(--text-secondary)] text-[12px] font-bold
            cursor-pointer border-0 hover:bg-[var(--surface-hover)]">Próximo →</button>
      </div>

      {/* Day headers */}
      <div className="grid grid-cols-7 gap-px mb-1">
        {DAYS_PT.map((d) => (
          <div key={d} className="text-center text-[10px] font-bold text-[var(--text-muted)] uppercase py-1">{d}</div>
        ))}
      </div>

      {/* Calendar grid */}
      <div className="grid grid-cols-7 gap-px bg-[var(--border-subtle)] rounded-lg overflow-hidden">
        {calendarDays.map((day, idx) => {
          const dayItems = day ? (itemsByDate.get(day.toString()) || []) : [];
          return (
            <div key={idx}
              className={`min-h-[80px] p-1 bg-[var(--surface-card)] ${
                day === null ? 'bg-[var(--surface-base)]' : ''
              } ${isToday(day!) ? 'ring-2 ring-inset ring-blue-400' : ''}`}>
              {day !== null && (
                <>
                  <div className={`text-[10px] font-bold mb-0.5 ${isToday(day) ? 'text-blue-600' : 'text-[var(--text-muted)]'}`}>
                    {day}
                  </div>
                  <div className="space-y-0.5">
                    {dayItems.slice(0, 3).map((item) => {
                      const colors: Record<string, string> = {
                        backlog: 'bg-gray-200 text-gray-700',
                        todo: 'bg-blue-100 text-blue-700',
                        doing: 'bg-amber-100 text-amber-700',
                        review: 'bg-purple-100 text-purple-700',
                        done: 'bg-emerald-100 text-emerald-700',
                      };
                      const color = colors[item.status] || 'bg-gray-100 text-gray-600';
                      return (
                        <button key={item.id}
                          onClick={() => onOpenDetail(item)}
                          className={`w-full text-left px-1 py-0.5 rounded text-[8px] font-medium truncate cursor-pointer border-0 ${color}`}
                          title={item.title}>
                          {item.title}
                        </button>
                      );
                    })}
                    {dayItems.length > 3 && (
                      <span className="text-[8px] text-[var(--text-muted)] pl-1">+{dayItems.length - 3} mais</span>
                    )}
                  </div>
                </>
              )}
            </div>
          );
        })}
      </div>

      {/* Items without dates */}
      {items.filter(i => !i.forecast_date && !i.due_date).length > 0 && (
        <div className="mt-4 p-3 bg-[var(--surface-section-cool)] rounded-lg">
          <span className="text-[11px] font-bold text-[var(--text-secondary)] block mb-1">
            Sem data ({items.filter(i => !i.forecast_date && !i.due_date).length})
          </span>
          <div className="flex flex-wrap gap-1">
            {items.filter(i => !i.forecast_date && !i.due_date).slice(0, 10).map((item) => (
              <button key={item.id}
                onClick={() => onOpenDetail(item)}
                className="px-1.5 py-0.5 bg-gray-100 text-gray-600 rounded text-[9px] cursor-pointer border-0 hover:bg-gray-200 truncate max-w-[150px]">
                {item.title}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
