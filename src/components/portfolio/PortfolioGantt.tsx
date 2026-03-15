import { useState, useMemo, useRef } from 'react';
import type { Artifact } from '../../hooks/usePortfolio';

interface Props {
  artifacts: Artifact[];
}

type Zoom = 'year' | 'quarter' | 'month' | 'week';

const HEALTH_COLOR: Record<string, string> = {
  on_track: '#22c55e',
  at_risk: '#eab308',
  delayed: '#ef4444',
  no_baseline: '#9ca3af',
  completed: '#3b82f6',
};

const ZOOM_LABELS: { key: Zoom; label: string }[] = [
  { key: 'year', label: 'Ano' },
  { key: 'quarter', label: 'Trim' },
  { key: 'month', label: 'Mês' },
  { key: 'week', label: 'Sem' },
];

function parseDate(d: string | null): Date | null {
  if (!d) return null;
  return new Date(d + 'T00:00:00');
}

function fmtDateShort(d: string | null) {
  if (!d) return '—';
  const dt = new Date(d + 'T00:00:00');
  return dt.toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' });
}

function diffDays(a: Date, b: Date) {
  return Math.round((b.getTime() - a.getTime()) / 86400000);
}

function addMonths(d: Date, n: number) {
  const r = new Date(d);
  r.setMonth(r.getMonth() + n);
  return r;
}

export default function PortfolioGantt({ artifacts }: Props) {
  const [zoom, setZoom] = useState<Zoom>('month');
  const [collapsed, setCollapsed] = useState<Set<number>>(new Set());
  const [tooltip, setTooltip] = useState<{ x: number; y: number; a: Artifact } | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  // Group by tribe
  const tribes = useMemo(() => {
    const map = new Map<number, { tribe_id: number; tribe_name: string; items: Artifact[] }>();
    for (const a of artifacts) {
      if (!map.has(a.tribe_id)) {
        map.set(a.tribe_id, { tribe_id: a.tribe_id, tribe_name: a.tribe_name, items: [] });
      }
      map.get(a.tribe_id)!.items.push(a);
    }
    return Array.from(map.values()).sort((a, b) => a.tribe_id - b.tribe_id);
  }, [artifacts]);

  // Calculate timeline range
  const { rangeStart, rangeEnd, totalDays } = useMemo(() => {
    const cycleStart = new Date('2026-03-01T00:00:00');
    let end = new Date('2026-12-31T00:00:00');

    for (const a of artifacts) {
      const bd = parseDate(a.baseline_date);
      const fd = parseDate(a.forecast_date);
      if (bd && bd > end) end = bd;
      if (fd && fd > end) end = fd;
    }
    // Add one month buffer
    end = addMonths(end, 1);

    return {
      rangeStart: cycleStart,
      rangeEnd: end,
      totalDays: diffDays(cycleStart, end),
    };
  }, [artifacts]);

  // Generate columns based on zoom
  const columns = useMemo(() => {
    const cols: { label: string; start: Date; end: Date }[] = [];
    const cursor = new Date(rangeStart);

    if (zoom === 'year') {
      while (cursor < rangeEnd) {
        const year = cursor.getFullYear();
        const yearEnd = new Date(`${year + 1}-01-01T00:00:00`);
        cols.push({ label: String(year), start: new Date(cursor), end: yearEnd > rangeEnd ? rangeEnd : yearEnd });
        cursor.setFullYear(year + 1);
        cursor.setMonth(0);
        cursor.setDate(1);
      }
    } else if (zoom === 'quarter') {
      while (cursor < rangeEnd) {
        const q = Math.floor(cursor.getMonth() / 3) + 1;
        const qEnd = new Date(cursor.getFullYear(), q * 3, 1);
        cols.push({ label: `Q${q} ${cursor.getFullYear()}`, start: new Date(cursor), end: qEnd > rangeEnd ? rangeEnd : qEnd });
        cursor.setMonth(q * 3);
        cursor.setDate(1);
      }
    } else if (zoom === 'month') {
      while (cursor < rangeEnd) {
        const label = cursor.toLocaleDateString('pt-BR', { month: 'short', year: '2-digit' });
        const mEnd = addMonths(new Date(cursor), 1);
        cols.push({ label, start: new Date(cursor), end: mEnd > rangeEnd ? rangeEnd : mEnd });
        cursor.setMonth(cursor.getMonth() + 1);
        cursor.setDate(1);
      }
    } else {
      // week
      // Align to Monday
      const day = cursor.getDay();
      const diff = day === 0 ? -6 : 1 - day;
      cursor.setDate(cursor.getDate() + diff);
      while (cursor < rangeEnd) {
        const wEnd = new Date(cursor);
        wEnd.setDate(wEnd.getDate() + 7);
        const weekNum = Math.ceil(((cursor.getTime() - new Date(cursor.getFullYear(), 0, 1).getTime()) / 86400000 + 1) / 7);
        cols.push({ label: `S${weekNum}`, start: new Date(cursor), end: wEnd > rangeEnd ? rangeEnd : wEnd });
        cursor.setDate(cursor.getDate() + 7);
      }
    }
    return cols;
  }, [zoom, rangeStart, rangeEnd]);

  const LABEL_W = 240;
  const colWidth = zoom === 'week' ? 40 : zoom === 'month' ? 100 : zoom === 'quarter' ? 160 : 300;
  const timelineW = columns.length * colWidth;
  const ROW_H = 28;
  const HEADER_H = 32;

  // Calculate rows
  const rows = useMemo(() => {
    const r: { type: 'tribe' | 'item'; tribe_id: number; label: string; count?: number; artifact?: Artifact }[] = [];
    for (const tribe of tribes) {
      r.push({ type: 'tribe', tribe_id: tribe.tribe_id, label: `T${tribe.tribe_id} — ${tribe.tribe_name}`, count: tribe.items.length });
      if (!collapsed.has(tribe.tribe_id)) {
        for (const item of tribe.items) {
          r.push({ type: 'item', tribe_id: tribe.tribe_id, label: item.title, artifact: item });
        }
      }
    }
    return r;
  }, [tribes, collapsed]);

  const totalH = HEADER_H + rows.length * ROW_H;
  const today = new Date();
  const todayX = totalDays > 0 ? (diffDays(rangeStart, today) / totalDays) * timelineW : 0;

  function getBarX(dateStr: string | null): number {
    const d = parseDate(dateStr);
    if (!d) return 0;
    const days = diffDays(rangeStart, d);
    return (days / totalDays) * timelineW;
  }

  const toggleTribe = (id: number) => {
    setCollapsed(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  return (
    <div className="rounded-xl border border-[var(--border-default)] overflow-hidden">
      {/* Zoom controls */}
      <div className="flex items-center justify-between px-3 py-2 bg-[var(--surface-section-cool)] border-b border-[var(--border-subtle)]">
        <span className="text-[10px] font-bold text-[var(--text-muted)] uppercase">Gantt Consolidado</span>
        <div className="flex gap-1">
          {ZOOM_LABELS.map(z => (
            <button
              key={z.key}
              onClick={() => setZoom(z.key)}
              className={`px-2 py-1 rounded text-[10px] font-bold border-0 cursor-pointer transition-all ${
                zoom === z.key
                  ? 'bg-[var(--surface-card)] text-[var(--text-primary)] shadow-sm'
                  : 'bg-transparent text-[var(--text-muted)] hover:text-[var(--text-secondary)]'
              }`}
            >
              {z.label}
            </button>
          ))}
        </div>
      </div>

      {/* Chart area */}
      <div className="overflow-x-auto relative" ref={containerRef}>
        <div style={{ display: 'flex', minWidth: LABEL_W + timelineW }}>
          {/* Label column */}
          <div style={{ width: LABEL_W, flexShrink: 0 }} className="border-r border-[var(--border-subtle)]">
            <div style={{ height: HEADER_H }} className="bg-[var(--surface-section-cool)] border-b border-[var(--border-subtle)]" />
            {rows.map((row, i) => (
              <div
                key={i}
                style={{ height: ROW_H }}
                className={`flex items-center px-2 text-[11px] border-b border-[var(--border-subtle)] ${
                  row.type === 'tribe'
                    ? 'bg-[var(--surface-section-cool)] font-bold text-[var(--text-primary)] cursor-pointer hover:bg-[var(--surface-hover)]'
                    : 'text-[var(--text-secondary)] pl-5'
                }`}
                onClick={() => row.type === 'tribe' && toggleTribe(row.tribe_id)}
              >
                {row.type === 'tribe' && (
                  <span className="mr-1 text-[9px]">{collapsed.has(row.tribe_id) ? '▶' : '▼'}</span>
                )}
                <span className="truncate">{row.label}</span>
                {row.type === 'tribe' && <span className="ml-auto text-[9px] text-[var(--text-muted)]">({row.count})</span>}
              </div>
            ))}
          </div>

          {/* Timeline */}
          <div style={{ width: timelineW, position: 'relative' }}>
            {/* Header */}
            <div style={{ height: HEADER_H, display: 'flex' }} className="bg-[var(--surface-section-cool)] border-b border-[var(--border-subtle)]">
              {columns.map((col, i) => (
                <div
                  key={i}
                  style={{ width: colWidth }}
                  className="flex items-center justify-center text-[10px] font-bold text-[var(--text-muted)] border-r border-[var(--border-subtle)]"
                >
                  {col.label}
                </div>
              ))}
            </div>

            {/* Rows SVG */}
            <svg width={timelineW} height={rows.length * ROW_H} style={{ display: 'block' }}>
              {/* Grid lines */}
              {columns.map((_, i) => (
                <line
                  key={`grid-${i}`}
                  x1={i * colWidth}
                  y1={0}
                  x2={i * colWidth}
                  y2={rows.length * ROW_H}
                  stroke="var(--border-subtle)"
                  strokeWidth={1}
                />
              ))}

              {/* Row backgrounds */}
              {rows.map((row, i) => (
                <rect
                  key={`bg-${i}`}
                  x={0}
                  y={i * ROW_H}
                  width={timelineW}
                  height={ROW_H}
                  fill={row.type === 'tribe' ? 'var(--surface-section-cool)' : 'transparent'}
                />
              ))}

              {/* Row borders */}
              {rows.map((_, i) => (
                <line
                  key={`border-${i}`}
                  x1={0}
                  y1={(i + 1) * ROW_H}
                  x2={timelineW}
                  y2={(i + 1) * ROW_H}
                  stroke="var(--border-subtle)"
                  strokeWidth={0.5}
                />
              ))}

              {/* Bars */}
              {rows.map((row, i) => {
                if (row.type !== 'item' || !row.artifact) return null;
                const a = row.artifact;
                const bd = a.baseline_date;
                const fd = a.forecast_date;
                if (!bd) {
                  // No baseline — show a small gray marker at cycle start
                  return (
                    <rect
                      key={`bar-${i}`}
                      x={4}
                      y={i * ROW_H + 8}
                      width={12}
                      height={ROW_H - 16}
                      rx={3}
                      fill={HEALTH_COLOR.no_baseline}
                      opacity={0.5}
                    />
                  );
                }

                const cycleStart = new Date('2026-03-01T00:00:00');
                const startDate = parseDate(bd)!;
                // Bar starts 30 days before baseline (or at cycle start)
                const barStart = startDate > cycleStart
                  ? new Date(Math.max(cycleStart.getTime(), startDate.getTime() - 30 * 86400000))
                  : cycleStart;
                const endDate = fd ? parseDate(fd)! : startDate;
                const displayEnd = endDate > startDate ? endDate : startDate;

                const x1 = getBarX(barStart.toISOString().slice(0, 10));
                const x2 = getBarX(displayEnd.toISOString().slice(0, 10));
                const barW = Math.max(x2 - x1, 8);
                const color = HEALTH_COLOR[a.health] || HEALTH_COLOR.no_baseline;

                // Checklist progress fill
                const pct = a.checklist_total > 0 ? a.checklist_done / a.checklist_total : 0;

                return (
                  <g
                    key={`bar-${i}`}
                    onMouseEnter={(e) => {
                      const rect = containerRef.current?.getBoundingClientRect();
                      if (rect) {
                        setTooltip({ x: e.clientX - rect.left, y: i * ROW_H + HEADER_H, a });
                      }
                    }}
                    onMouseLeave={() => setTooltip(null)}
                    style={{ cursor: 'pointer' }}
                    onClick={() => window.open(`/tribe/${a.tribe_id}`, '_blank')}
                  >
                    {/* Background bar */}
                    <rect
                      x={x1}
                      y={i * ROW_H + 7}
                      width={barW}
                      height={ROW_H - 14}
                      rx={4}
                      fill={color}
                      opacity={0.25}
                    />
                    {/* Progress fill */}
                    {pct > 0 && (
                      <rect
                        x={x1}
                        y={i * ROW_H + 7}
                        width={barW * pct}
                        height={ROW_H - 14}
                        rx={4}
                        fill={color}
                        opacity={0.7}
                      />
                    )}
                    {/* Border */}
                    <rect
                      x={x1}
                      y={i * ROW_H + 7}
                      width={barW}
                      height={ROW_H - 14}
                      rx={4}
                      fill="none"
                      stroke={color}
                      strokeWidth={1.5}
                    />
                    {/* Baseline marker */}
                    <line
                      x1={getBarX(bd)}
                      y1={i * ROW_H + 5}
                      x2={getBarX(bd)}
                      y2={i * ROW_H + ROW_H - 5}
                      stroke={color}
                      strokeWidth={2}
                      strokeDasharray="2,2"
                    />
                  </g>
                );
              })}

              {/* Today marker */}
              {todayX > 0 && todayX < timelineW && (
                <line
                  x1={todayX}
                  y1={0}
                  x2={todayX}
                  y2={rows.length * ROW_H}
                  stroke="#ef4444"
                  strokeWidth={1.5}
                  strokeDasharray="4,4"
                />
              )}
            </svg>

            {/* Tooltip */}
            {tooltip && (
              <div
                className="absolute z-50 bg-[var(--surface-card)] border border-[var(--border-default)] rounded-lg shadow-lg p-2 text-[11px] pointer-events-none"
                style={{
                  left: Math.min(tooltip.x, timelineW - 200),
                  top: tooltip.y + ROW_H,
                  maxWidth: 220,
                }}
              >
                <div className="font-bold text-[var(--text-primary)] mb-1">{tooltip.a.title}</div>
                <div className="text-[var(--text-secondary)]">
                  <span>T{tooltip.a.tribe_id} · {tooltip.a.leader_name?.split(' ')[0]}</span>
                </div>
                <div className="text-[var(--text-muted)] mt-1">
                  Baseline: {fmtDateShort(tooltip.a.baseline_date)} · Forecast: {fmtDateShort(tooltip.a.forecast_date)}
                </div>
                {tooltip.a.variance_days !== null && (
                  <div className={tooltip.a.variance_days > 0 ? 'text-red-600 font-bold' : 'text-green-600'}>
                    Desvio: {tooltip.a.variance_days > 0 ? '+' : ''}{tooltip.a.variance_days}d
                  </div>
                )}
                {tooltip.a.checklist_total > 0 && (
                  <div className="text-[var(--text-muted)]">
                    Atividades: {tooltip.a.checklist_done}/{tooltip.a.checklist_total}
                  </div>
                )}
              </div>
            )}
          </div>
        </div>
      </div>

      {artifacts.length === 0 && (
        <div className="text-center py-8 text-[var(--text-muted)] text-sm">Nenhum artefato com baseline para exibir no Gantt.</div>
      )}
    </div>
  );
}
