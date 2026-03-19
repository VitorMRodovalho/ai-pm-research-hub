import { useState, useEffect, useMemo } from 'react';
import {
  useReactTable,
  getCoreRowModel,
  getSortedRowModel,
  getFilteredRowModel,
  flexRender,
  type ColumnDef,
  type SortingState,
} from '@tanstack/react-table';
import { usePageI18n } from '../../i18n/usePageI18n';
import {
  Users,
  Percent,
  Clock,
  AlertTriangle,
  ShieldAlert,
  Trophy,
  Download,
  Search,
  ChevronUp,
  ChevronDown,
  Loader2,
  AlertCircle,
} from 'lucide-react';

/* ------------------------------------------------------------------ */
/*  Types                                                              */
/* ------------------------------------------------------------------ */

function getSb() {
  return (window as any).navGetSb?.();
}

interface GridEvent {
  id: string;
  date: string;
  title: string;
  type: string;
  tribe_id: string;
  tribe_name: string;
  duration_minutes: number;
  week_number: number;
}

interface GridMember {
  id: string;
  name: string;
  chapter: string;
  rate: number;
  hours: number;
  eligible_count: number;
  present_count: number;
  detractor_status: string | null;
  consecutive_absences: number;
  attendance: Record<string, 'present' | 'absent' | 'excused' | 'na'>;
}

interface GridTribe {
  tribe_id: string;
  tribe_name: string;
  leader_name: string;
  avg_rate: number;
  member_count: number;
  members: GridMember[];
}

interface GridSummary {
  total_members: number;
  overall_rate: number;
  total_hours: number;
  detractors_count: number;
  at_risk_count: number;
}

interface GridData {
  summary: GridSummary;
  events: GridEvent[];
  tribes: GridTribe[];
}

interface FlatRow {
  memberId: string;
  name: string;
  tribeName: string;
  tribeId: string;
  chapter: string;
  rate: number;
  hours: number;
  detractorStatus: string | null;
  consecutiveAbsences: number;
  eligibleCount: number;
  presentCount: number;
  attendance: Record<string, 'present' | 'absent' | 'excused' | 'na'>;
}

/* ------------------------------------------------------------------ */
/*  Helpers                                                            */
/* ------------------------------------------------------------------ */

const TYPE_ABBR: Record<string, string> = {
  geral: 'G',
  tribo: 'T',
  lideranca: 'L',
  kickoff: 'K',
};

function fmtDate(iso: string) {
  const d = new Date(iso);
  return `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}`;
}

function statusCell(v: string | undefined) {
  switch (v) {
    case 'present':
      return { label: '\u2705', bg: 'bg-green-100 dark:bg-green-900/30', csv: 'P' };
    case 'absent':
      return { label: '\u274C', bg: 'bg-red-100 dark:bg-red-900/30', csv: 'F' };
    case 'excused':
      return { label: '\u26A0\uFE0F', bg: 'bg-blue-100 dark:bg-blue-900/30', csv: 'FJ' };
    default:
      return { label: '\u2014', bg: 'bg-gray-100 dark:bg-gray-800/40', csv: 'NA' };
  }
}

function rowTint(rate: number) {
  if (rate < 50) return 'bg-red-50/60 dark:bg-red-950/20';
  if (rate < 75) return 'bg-amber-50/60 dark:bg-amber-950/20';
  return '';
}

/* ------------------------------------------------------------------ */
/*  KPI Cards                                                          */
/* ------------------------------------------------------------------ */

function KpiCard({
  icon: Icon,
  label,
  value,
  suffix,
  accent,
}: {
  icon: any;
  label: string;
  value: string | number;
  suffix?: string;
  accent?: string;
}) {
  return (
    <div className="bg-[var(--surface-card)] border border-[var(--border-subtle)] rounded-2xl p-4 flex flex-col gap-1">
      <div className="flex items-center gap-2 text-[var(--text-muted)] text-xs font-semibold">
        <Icon size={14} className={accent || 'text-[var(--color-teal)]'} />
        {label}
      </div>
      <p className="text-xl font-extrabold text-[var(--text-primary)]">
        {value}
        {suffix && <span className="text-xs font-normal text-[var(--text-muted)]"> {suffix}</span>}
      </p>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Main Component                                                     */
/* ------------------------------------------------------------------ */

export default function AttendanceGridTab() {
  const t = usePageI18n();

  /* State */
  const [data, setData] = useState<GridData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [tribeFilter, setTribeFilter] = useState('all');
  const [typeFilter, setTypeFilter] = useState('all');
  const [search, setSearch] = useState('');
  const [sorting, setSorting] = useState<SortingState>([{ id: 'rate', desc: false }]);
  const [isMobile, setIsMobile] = useState(false);

  /* Responsive */
  useEffect(() => {
    const mq = window.matchMedia('(max-width: 767px)');
    setIsMobile(mq.matches);
    const handler = (e: MediaQueryListEvent) => setIsMobile(e.matches);
    mq.addEventListener('change', handler);
    return () => mq.removeEventListener('change', handler);
  }, []);

  /* Fetch */
  useEffect(() => {
    (async () => {
      try {
        const sb = getSb();
        if (!sb) {
          setError(t('attendance.grid.errorNoSb', 'Could not connect to database'));
          setLoading(false);
          return;
        }
        const { data: result, error: rpcErr } = await sb.rpc('get_attendance_grid', {
          p_tribe_id: null,
          p_event_type: null,
        });
        if (rpcErr) throw rpcErr;
        setData(result as GridData);
      } catch (e: any) {
        setError(e?.message || t('attendance.grid.errorGeneric', 'Failed to load attendance grid'));
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  /* Flatten tribes->members */
  const flatRows = useMemo<FlatRow[]>(() => {
    if (!data) return [];
    const rows: FlatRow[] = [];
    for (const tribe of data.tribes) {
      for (const m of tribe.members) {
        rows.push({
          memberId: m.id,
          name: m.name,
          tribeName: tribe.tribe_name,
          tribeId: tribe.tribe_id,
          chapter: m.chapter,
          rate: m.rate,
          hours: m.hours,
          detractorStatus: m.detractor_status,
          consecutiveAbsences: m.consecutive_absences,
          eligibleCount: m.eligible_count,
          presentCount: m.present_count,
          attendance: m.attendance,
        });
      }
    }
    return rows;
  }, [data]);

  /* Filtered events */
  const filteredEvents = useMemo(() => {
    if (!data) return [];
    return data.events.filter((ev) => {
      if (typeFilter !== 'all' && ev.type !== typeFilter) return false;
      if (tribeFilter !== 'all' && ev.tribe_id !== tribeFilter) return false;
      return true;
    });
  }, [data, typeFilter, tribeFilter]);

  /* Filtered rows */
  const filteredRows = useMemo(() => {
    let rows = flatRows;
    if (tribeFilter !== 'all') {
      rows = rows.filter((r) => r.tribeId === tribeFilter);
    }
    if (search.trim()) {
      const q = search.toLowerCase();
      rows = rows.filter(
        (r) =>
          r.name.toLowerCase().includes(q) ||
          r.tribeName.toLowerCase().includes(q) ||
          r.chapter.toLowerCase().includes(q),
      );
    }
    return rows;
  }, [flatRows, tribeFilter, search]);

  /* Best tribe */
  const bestTribe = useMemo(() => {
    if (!data || data.tribes.length === 0) return null;
    return data.tribes.reduce((best, cur) => (cur.avg_rate > best.avg_rate ? cur : best), data.tribes[0]);
  }, [data]);

  /* Columns */
  const columns = useMemo<ColumnDef<FlatRow, any>[]>(() => {
    const cols: ColumnDef<FlatRow, any>[] = [
      {
        id: 'status_icon',
        header: '',
        size: 36,
        enableSorting: false,
        cell: ({ row }) => {
          const d = row.original.detractorStatus;
          if (d === 'detractor') return <span title={t('attendance.grid.detractor', 'Detractor')}>🔴</span>;
          if (d === 'at_risk') return <span title={t('attendance.grid.atRisk', 'At risk')}>🟡</span>;
          return null;
        },
      },
      {
        accessorKey: 'name',
        header: t('attendance.grid.name', 'Name'),
        size: 160,
        enableSorting: true,
      },
      {
        accessorKey: 'tribeName',
        header: t('attendance.grid.tribe', 'Tribe'),
        size: 120,
        enableSorting: true,
      },
      {
        accessorKey: 'chapter',
        header: t('attendance.grid.chapter', 'Chapter'),
        size: 100,
        enableSorting: true,
      },
    ];

    for (const ev of filteredEvents) {
      const abbr = TYPE_ABBR[ev.type] || ev.type.charAt(0).toUpperCase();
      cols.push({
        id: `ev_${ev.id}`,
        header: `${fmtDate(ev.date)} ${abbr}`,
        size: 72,
        enableSorting: false,
        cell: ({ row }) => {
          const st = statusCell(row.original.attendance[ev.id]);
          return (
            <span className={`inline-flex items-center justify-center w-full h-full text-xs ${st.bg} rounded px-1`}>
              {st.label}
            </span>
          );
        },
      });
    }

    cols.push({
      accessorKey: 'rate',
      header: t('attendance.grid.rate', 'Rate %'),
      size: 80,
      enableSorting: true,
      cell: ({ getValue }) => {
        const v = getValue() as number;
        const color = v < 50 ? 'text-red-600' : v < 75 ? 'text-amber-600' : 'text-green-600';
        return <span className={`font-bold ${color}`}>{Math.round(v)}%</span>;
      },
    });

    return cols;
  }, [filteredEvents, t]);

  /* Table instance */
  const table = useReactTable({
    data: filteredRows,
    columns,
    state: { sorting },
    onSortingChange: setSorting,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
    getFilteredRowModel: getFilteredRowModel(),
  });

  /* CSV Export */
  function exportCsv() {
    if (!data) return;
    const headers = ['Name', 'Tribe', 'Chapter', ...filteredEvents.map((e) => `${fmtDate(e.date)} ${TYPE_ABBR[e.type] || e.type}`), 'Rate %'];
    const csvRows = [headers.join(',')];
    for (const row of table.getRowModel().rows) {
      const r = row.original;
      const cells = [
        `"${r.name}"`,
        `"${r.tribeName}"`,
        `"${r.chapter}"`,
        ...filteredEvents.map((e) => statusCell(r.attendance[e.id]).csv),
        `${Math.round(r.rate)}`,
      ];
      csvRows.push(cells.join(','));
    }
    const blob = new Blob([csvRows.join('\n')], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    const today = new Date().toISOString().slice(0, 10);
    a.href = url;
    a.download = `attendance_grid_${today}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  /* ---------------------------------------------------------------- */
  /*  Render                                                           */
  /* ---------------------------------------------------------------- */

  /* Loading */
  if (loading) {
    return (
      <div className="space-y-4">
        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3">
          {Array.from({ length: 6 }).map((_, i) => (
            <div key={i} className="bg-[var(--surface-card)] border border-[var(--border-subtle)] rounded-2xl p-4 animate-pulse">
              <div className="h-3 bg-[var(--border-subtle)] rounded w-16 mb-2" />
              <div className="h-6 bg-[var(--border-subtle)] rounded w-20" />
            </div>
          ))}
        </div>
        <div className="flex items-center justify-center py-20 text-[var(--text-muted)]">
          <Loader2 size={24} className="animate-spin mr-2" />
          {t('attendance.grid.loading', 'Loading attendance grid...')}
        </div>
      </div>
    );
  }

  /* Error */
  if (error) {
    return (
      <div className="flex flex-col items-center justify-center py-20 text-[var(--text-muted)] gap-3">
        <AlertCircle size={32} className="text-red-500" />
        <p className="text-sm">{error}</p>
      </div>
    );
  }

  if (!data) return null;

  const { summary } = data;

  return (
    <div className="space-y-5">
      {/* KPI Cards */}
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3">
        <KpiCard icon={Users} label={t('attendance.grid.totalMembers', 'Total Members')} value={summary.total_members} />
        <KpiCard
          icon={Percent}
          label={t('attendance.grid.overallRate', 'Overall Rate')}
          value={`${Math.round(summary.overall_rate)}%`}
          accent={summary.overall_rate < 75 ? 'text-amber-500' : 'text-green-500'}
        />
        <KpiCard icon={Clock} label={t('attendance.grid.totalHours', 'Total Hours')} value={Math.round(summary.total_hours)} suffix="h" />
        <KpiCard
          icon={ShieldAlert}
          label={t('attendance.grid.detractors', 'Detractors')}
          value={summary.detractors_count}
          accent="text-red-500"
        />
        <KpiCard
          icon={AlertTriangle}
          label={t('attendance.grid.atRisk', 'At Risk')}
          value={summary.at_risk_count}
          accent="text-amber-500"
        />
        <KpiCard
          icon={Trophy}
          label={t('attendance.grid.bestTribe', 'Best Tribe')}
          value={bestTribe ? bestTribe.tribe_name : '-'}
          suffix={bestTribe ? `${Math.round(bestTribe.avg_rate)}%` : ''}
          accent="text-[var(--color-teal)]"
        />
      </div>

      {/* Filter Bar */}
      <div className="flex flex-wrap items-center gap-3 bg-[var(--surface-card)] border border-[var(--border-subtle)] rounded-xl p-3">
        {/* Tribe */}
        <select
          value={tribeFilter}
          onChange={(e) => setTribeFilter(e.target.value)}
          className="bg-[var(--surface-base)] border border-[var(--border-default)] rounded-lg px-3 py-1.5 text-sm text-[var(--text-primary)] focus:outline-none focus:ring-2 focus:ring-[var(--color-teal)]"
        >
          <option value="all">{t('attendance.grid.allTribes', 'All Tribes')}</option>
          {data.tribes.map((tr) => (
            <option key={tr.tribe_id} value={tr.tribe_id}>
              {tr.tribe_name}
            </option>
          ))}
        </select>

        {/* Event Type */}
        <select
          value={typeFilter}
          onChange={(e) => setTypeFilter(e.target.value)}
          className="bg-[var(--surface-base)] border border-[var(--border-default)] rounded-lg px-3 py-1.5 text-sm text-[var(--text-primary)] focus:outline-none focus:ring-2 focus:ring-[var(--color-teal)]"
        >
          <option value="all">{t('attendance.grid.allTypes', 'All Types')}</option>
          <option value="geral">{t('attendance.grid.typeGeral', 'Geral')}</option>
          <option value="tribo">{t('attendance.grid.typeTribo', 'Tribo')}</option>
          <option value="lideranca">{t('attendance.grid.typeLideranca', 'Lideranca')}</option>
        </select>

        {/* Search */}
        <div className="relative flex-1 min-w-[180px]">
          <Search size={14} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-[var(--text-muted)]" />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder={t('attendance.grid.search', 'Search member...')}
            className="w-full bg-[var(--surface-base)] border border-[var(--border-default)] rounded-lg pl-8 pr-3 py-1.5 text-sm text-[var(--text-primary)] placeholder:text-[var(--text-muted)] focus:outline-none focus:ring-2 focus:ring-[var(--color-teal)]"
          />
        </div>

        {/* CSV Export */}
        <button
          onClick={exportCsv}
          className="inline-flex items-center gap-1.5 bg-[var(--color-teal)] text-white text-sm font-semibold px-4 py-1.5 rounded-lg hover:opacity-90 transition-opacity"
        >
          <Download size={14} />
          {t('attendance.grid.export', 'Export CSV')}
        </button>
      </div>

      {/* Grid / Mobile */}
      {isMobile ? (
        <MobileCardList rows={table.getRowModel().rows} events={filteredEvents} t={t} />
      ) : (
        <div className="bg-[var(--surface-card)] border border-[var(--border-subtle)] rounded-xl overflow-auto">
          <table className="w-full text-sm border-collapse">
            <thead>
              {table.getHeaderGroups().map((hg) => (
                <tr key={hg.id} className="border-b border-[var(--border-subtle)]">
                  {hg.headers.map((header) => (
                    <th
                      key={header.id}
                      className="px-2 py-2 text-left text-xs font-bold text-[var(--text-muted)] bg-[var(--surface-base)] whitespace-nowrap sticky top-0 z-10 select-none"
                      style={{ width: header.getSize() }}
                      onClick={header.column.getCanSort() ? header.column.getToggleSortingHandler() : undefined}
                    >
                      <span className={`inline-flex items-center gap-1 ${header.column.getCanSort() ? 'cursor-pointer hover:text-[var(--text-primary)]' : ''}`}>
                        {flexRender(header.column.columnDef.header, header.getContext())}
                        {header.column.getIsSorted() === 'asc' && <ChevronUp size={12} />}
                        {header.column.getIsSorted() === 'desc' && <ChevronDown size={12} />}
                      </span>
                    </th>
                  ))}
                </tr>
              ))}
            </thead>
            <tbody>
              {table.getRowModel().rows.map((row) => (
                <tr
                  key={row.id}
                  className={`border-b border-[var(--border-subtle)] hover:bg-[var(--surface-base)] transition-colors ${rowTint(row.original.rate)}`}
                >
                  {row.getVisibleCells().map((cell) => (
                    <td key={cell.id} className="px-2 py-1.5 whitespace-nowrap text-[var(--text-primary)]">
                      {flexRender(cell.column.columnDef.cell, cell.getContext())}
                    </td>
                  ))}
                </tr>
              ))}
              {table.getRowModel().rows.length === 0 && (
                <tr>
                  <td colSpan={columns.length} className="px-4 py-12 text-center text-[var(--text-muted)] text-sm">
                    {t('attendance.grid.noResults', 'No members found.')}
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      )}

      {/* Row count */}
      <p className="text-xs text-[var(--text-muted)]">
        {t('attendance.grid.showing', 'Showing')} {table.getRowModel().rows.length}{' '}
        {t('attendance.grid.of', 'of')} {flatRows.length} {t('attendance.grid.members', 'members')}
      </p>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Mobile Card List                                                   */
/* ------------------------------------------------------------------ */

function MobileCardList({
  rows,
  events,
  t,
}: {
  rows: any[];
  events: GridEvent[];
  t: (key: string, fb?: string) => string;
}) {
  if (rows.length === 0) {
    return (
      <p className="text-center text-sm text-[var(--text-muted)] py-12">
        {t('attendance.grid.noResults', 'No members found.')}
      </p>
    );
  }

  return (
    <div className="space-y-3">
      {rows.map((row: any) => {
        const r: FlatRow = row.original;
        const rateColor = r.rate < 50 ? 'text-red-600' : r.rate < 75 ? 'text-amber-600' : 'text-green-600';
        const statusPrefix =
          r.detractorStatus === 'detractor' ? '🔴 ' : r.detractorStatus === 'at_risk' ? '🟡 ' : '';

        return (
          <div
            key={r.memberId}
            className={`bg-[var(--surface-card)] border border-[var(--border-subtle)] rounded-xl p-3 ${rowTint(r.rate)}`}
          >
            <div className="flex items-center justify-between mb-2">
              <div>
                <p className="text-sm font-bold text-[var(--text-primary)]">
                  {statusPrefix}{r.name}
                </p>
                <p className="text-xs text-[var(--text-muted)]">
                  {r.tribeName} &middot; {r.chapter}
                </p>
              </div>
              <span className={`text-lg font-extrabold ${rateColor}`}>{Math.round(r.rate)}%</span>
            </div>

            {/* Compact attendance strip */}
            <div className="flex flex-wrap gap-1">
              {events.map((ev) => {
                const st = statusCell(r.attendance[ev.id]);
                return (
                  <span
                    key={ev.id}
                    title={`${fmtDate(ev.date)} ${ev.title}`}
                    className={`inline-flex items-center justify-center w-6 h-6 text-[10px] rounded ${st.bg}`}
                  >
                    {st.label}
                  </span>
                );
              })}
            </div>
          </div>
        );
      })}
    </div>
  );
}
