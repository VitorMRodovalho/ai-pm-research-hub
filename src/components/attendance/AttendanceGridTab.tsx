import { useState, useEffect, useMemo, useCallback } from 'react';
import {
  useReactTable,
  getCoreRowModel,
  getSortedRowModel,
  getFilteredRowModel,
  flexRender,
  type ColumnDef,
  type SortingState,
  type ColumnGroup,
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
  ChevronRight,
  Loader2,
  AlertCircle,
} from 'lucide-react';

/* ------------------------------------------------------------------ */
/*  Types                                                              */
/* ------------------------------------------------------------------ */

function getSb() {
  if (typeof window === 'undefined') return null;
  return (window as any).navGetSb?.();
}

async function waitForSb(maxRetries = 15): Promise<any> {
  let sb = getSb();
  let retries = 0;
  while (!sb && retries < maxRetries) {
    await new Promise((r) => setTimeout(r, 250));
    sb = getSb();
    retries++;
  }
  return sb;
}

function getMember() {
  if (typeof window === 'undefined') return null;
  return (window as any).navGetMember?.();
}

function canManageAttendance(): boolean {
  const m = getMember();
  if (!m) return false;
  if (m.is_superadmin) return true;
  if (['manager', 'tribe_leader'].includes(m.operational_role)) return true;
  if ((m.designations || []).includes('deputy_manager')) return true;
  return false;
}

function isChapterBoard(): boolean {
  const m = getMember();
  return !!m && (m.designations || []).includes('chapter_board');
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
  geral: '🌐 G',
  tribo: '🔬 T',
  lideranca: '👥 L',
  kickoff: '🚀 K',
  comms: '📢 C',
  webinar: '🎙️ W',
  evento_externo: '🌍 E',
  '1on1': '🔒 1',
  parceria: '🤝 P',
  entrevista: '📌 I',
};

function getTypeFull(t: (k: string, fb?: string) => string): Record<string, string> {
  return {
    G: t('attendance.grid.legendGeral', 'Geral'),
    T: t('attendance.grid.legendTribo', 'Tribo'),
    L: t('attendance.grid.legendLideranca', 'Liderança'),
    K: t('attendance.grid.legendKickoff', 'Kickoff'),
    C: t('attendance.grid.legendComms', 'Comms'),
  };
}

function getLocale(): string {
  const lang = document.documentElement.lang || 'pt-BR';
  if (lang.startsWith('en')) return 'en-US';
  if (lang.startsWith('es')) return 'es';
  return 'pt-BR';
}

function fmtDate(iso: string): string {
  const locale = getLocale();
  const date = new Date(iso + 'T12:00:00');
  const day = date.toLocaleDateString(locale, { day: '2-digit' });
  const month = date.toLocaleDateString(locale, { month: 'short' }).replace('.', '');
  return `${day}/${month.charAt(0).toUpperCase() + month.slice(1)}`;
}

/** Ensure rate is displayed as 0-100 percentage. If RPC returns 0-1, multiply by 100. */
function normalizeRate(raw: number): number {
  if (raw >= 0 && raw <= 1 && raw !== 0) return raw * 100;
  return raw;
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
  if (isChapterBoard()) return '';
  if (rate < 50) return 'bg-red-50/60 dark:bg-red-950/20';
  if (rate < 75) return 'bg-amber-50/60 dark:bg-amber-950/20';
  return '';
}

/* Sticky column styles */
const STICKY_LEFT_BASE: React.CSSProperties = {
  position: 'sticky' as const,
  zIndex: 20,
  background: 'var(--surface-base, #f9fafb)',
};

const STICKY_RIGHT: React.CSSProperties = {
  position: 'sticky' as const,
  right: 0,
  zIndex: 20,
  background: 'var(--surface-base, #f9fafb)',
};

const STICKY_LEFT_TD_BASE: React.CSSProperties = {
  position: 'sticky' as const,
  zIndex: 10,
  background: 'var(--surface-card, #fff)',
};

const STICKY_RIGHT_TD: React.CSSProperties = {
  position: 'sticky' as const,
  right: 0,
  zIndex: 10,
  background: 'var(--surface-card, #fff)',
};

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

type DetractorFilter = 'all' | 'detractor' | 'at_risk' | 'regular';

export default function AttendanceGridTab() {
  const t = usePageI18n();

  /* State */
  const [data, setData] = useState<GridData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [tribeFilter, setTribeFilter] = useState('all');
  const [typeFilter, setTypeFilter] = useState('all');
  const [detractorFilter, setDetractorFilter] = useState<DetractorFilter>('all');
  const [search, setSearch] = useState('');
  // TODO: add nature to get_attendance_grid events output
  // const [natureFilter, setNatureFilter] = useState('all');
  const [sorting, setSorting] = useState<SortingState>([{ id: 'rate', desc: false }]);
  const [isMobile, setIsMobile] = useState(false);
  const [expandedTribes, setExpandedTribes] = useState<Set<string>>(new Set());
  const [toggling, setToggling] = useState<string | null>(null);
  const [showAllEvents, setShowAllEvents] = useState(false);
  const [memberReady, setMemberReady] = useState(!!getMember());

  /* Wait for member to be available (nav loads async) */
  useEffect(() => {
    if (memberReady) return;
    const check = () => { if (getMember()) setMemberReady(true); };
    window.addEventListener('nav:member', check, { once: true });
    const timer = setInterval(() => { if (getMember()) { setMemberReady(true); clearInterval(timer); } }, 500);
    return () => { window.removeEventListener('nav:member', check); clearInterval(timer); };
  }, [memberReady]);

  /* Toggle attendance cell — click handler for managers */
  /* Toggle cycles: absent → present → excused → absent */
  const handleToggle = useCallback(async (eventId: string, memberId: string, current: string) => {
    const sb = getSb();
    if (!sb || toggling) return;
    const cellKey = `${eventId}:${memberId}`;
    setToggling(cellKey);
    try {
      // Cycle: absent/none → present, present → excused, excused → absent
      const nextState = current === 'present' ? 'excused' : current === 'excused' ? 'absent' : 'present';

      if (nextState === 'excused') {
        const { error: rpcErr } = await sb.rpc('mark_member_excused', {
          p_event_id: eventId, p_member_id: memberId, p_excused: true,
        });
        if (rpcErr) throw rpcErr;
      } else {
        const { error: rpcErr } = await sb.rpc('mark_member_present', {
          p_event_id: eventId, p_member_id: memberId, p_present: nextState === 'present',
        });
        if (rpcErr) throw rpcErr;
        // If going from excused to absent, also clear excused flag
        if (current === 'excused') {
          await sb.rpc('mark_member_excused', { p_event_id: eventId, p_member_id: memberId, p_excused: false });
        }
      }

      // Optimistic update in local data
      setData(prev => {
        if (!prev) return prev;
        const updated = JSON.parse(JSON.stringify(prev)) as GridData;
        for (const tribe of updated.tribes) {
          for (const m of tribe.members) {
            if (m.member_id === memberId) {
              m.attendance[eventId] = nextState as any;
            }
          }
        }
        return updated;
      });
      const toastMap: Record<string, string> = {
        present: t('attendance.grid.toastPresent', '✅ Presente'),
        excused: t('attendance.grid.toastExcused', '⚠️ Falta justificada'),
        absent: t('attendance.grid.toastAbsent', '❌ Ausente'),
      };
      (window as any).toast?.(toastMap[nextState], 'success');
    } catch (e: any) {
      console.error('Toggle failed:', e);
      (window as any).toast?.('Erro ao registrar presença', 'error');
    } finally {
      setToggling(null);
    }
  }, [toggling]);

  /* Document-level click delegation for attendance cells */
  useEffect(() => {
    const handler = (e: MouseEvent) => {
      const target = (e.target as HTMLElement)?.closest('[data-toggle-event]') as HTMLElement;
      if (!target) return;
      const eventId = target.dataset.toggleEvent!;
      const memberId = target.dataset.toggleMember!;
      const current = target.dataset.toggleCurrent || 'none';
      handleToggle(eventId, memberId, current);
    };
    document.addEventListener('click', handler);
    return () => document.removeEventListener('click', handler);
  }, [handleToggle]);

  /* Responsive */
  useEffect(() => {
    const mq = window.matchMedia('(max-width: 767px)');
    setIsMobile(mq.matches);
    const handler = (e: MediaQueryListEvent) => setIsMobile(e.matches);
    mq.addEventListener('change', handler);
    return () => mq.removeEventListener('change', handler);
  }, []);

  /* Fetch — FIX 6: proper error handling for RPC response */
  useEffect(() => {
    (async () => {
      try {
        const sb = await waitForSb();
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

        /* FIX 6: check if RPC result itself contains an error key */
        if (result && typeof result === 'object' && 'error' in result && result.error) {
          setError(
            typeof result.error === 'string'
              ? result.error
              : result.error?.message || t('attendance.grid.errorGeneric', 'Failed to load attendance grid'),
          );
          setLoading(false);
          return;
        }

        const parsed = result as GridData;

        /* FIX 8: normalize rates from 0-1 to 0-100 if needed */
        if (parsed && parsed.summary) {
          parsed.summary.overall_rate = normalizeRate(parsed.summary.overall_rate);
        }
        if (parsed && parsed.tribes) {
          for (const tribe of parsed.tribes) {
            tribe.avg_rate = normalizeRate(tribe.avg_rate);
            for (const m of tribe.members) {
              m.rate = normalizeRate(m.rate);
            }
          }
        }

        setData(parsed);

        /* Initialize expanded tribes — all expanded by default (include cross-functional) */
        if (parsed && parsed.tribes) {
          const ids = parsed.tribes.map((tr) => tr.tribe_id);
          ids.push('__cross_functional__');
          setExpandedTribes(new Set(ids));
        }
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

  /* Filtered events — show general events even when tribe-filtered if any
     filtered member has a non-"na" status for that event.
     Exclude events more than 7 days in the future to avoid grid clutter. */
  const filteredEvents = useMemo(() => {
    if (!data) return [];
    const maxDate = new Date(Date.now() + 7 * 86400000).toISOString().slice(0, 10);
    return data.events.filter((ev) => {
      if (ev.date > maxDate) return false;
      if (typeFilter !== 'all' && ev.type !== typeFilter) return false;
      if (tribeFilter !== 'all') {
        // Tribe-specific events: only show if they belong to the filtered tribe
        if (ev.tribe_id !== null && String(ev.tribe_id) !== tribeFilter) return false;
        // General events (tribe_id=null): show if any filtered member has non-"na" status
        if (ev.tribe_id === null) {
          const tribeMembers = flatRows.filter((r) => String(r.tribeId) === tribeFilter);
          const anyRelevant = tribeMembers.some((m) => {
            const status = m.attendance?.[ev.id];
            return status && status !== 'na';
          });
          if (!anyRelevant) return false;
        }
      }
      return true;
    });
  }, [data, typeFilter, tribeFilter, flatRows]);

  /* Filtered rows — FIX 7: detractor status filter */
  const filteredRows = useMemo(() => {
    let rows = flatRows;
    if (tribeFilter !== 'all') {
      rows = rows.filter((r) => String(r.tribeId) === tribeFilter);
    }
    if (detractorFilter !== 'all') {
      rows = rows.filter((r) => {
        if (detractorFilter === 'detractor') return r.detractorStatus === 'detractor';
        if (detractorFilter === 'at_risk') return r.detractorStatus === 'at_risk';
        if (detractorFilter === 'regular') return !r.detractorStatus || r.detractorStatus === 'regular';
        return true;
      });
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
  }, [flatRows, tribeFilter, detractorFilter, search]);

  /* Filtered KPIs — computed from filteredRows so KPI cards reflect active filters */
  const filteredKPIs = useMemo(() => {
    const members = filteredRows;
    const total = members.length;
    const avgRate = total > 0 ? members.reduce((s, m) => s + m.rate, 0) / total : 0;
    const totalHours = members.reduce((s, m) => s + m.hours, 0);
    const detractors = members.filter(m => m.detractorStatus === 'detractor').length;
    const atRisk = members.filter(m => m.detractorStatus === 'at_risk').length;
    return { total, avgRate, totalHours, detractors, atRisk };
  }, [filteredRows]);

  /* Best tribe */
  const bestTribe = useMemo(() => {
    if (!data || data.tribes.length === 0) return null;
    return data.tribes.reduce((best, cur) => (cur.avg_rate > best.avg_rate ? cur : best), data.tribes[0]);
  }, [data]);

  /* FIX 1: Week-grouped event columns */
  /* FIX 4: Within each week, sub-group by date */
  const weekGroups = useMemo(() => {
    const weekMap = new Map<number, GridEvent[]>();
    filteredEvents.forEach((e) => {
      const week = e.week_number;
      if (!weekMap.has(week)) weekMap.set(week, []);
      weekMap.get(week)!.push(e);
    });
    return Array.from(weekMap.entries())
      .sort(([a], [b]) => a - b)
      .map(([week, evts]) => {
        const dateMap = new Map<string, GridEvent[]>();
        evts.forEach((e) => {
          if (!dateMap.has(e.date)) dateMap.set(e.date, []);
          dateMap.get(e.date)!.push(e);
        });
        const dateGroups = Array.from(dateMap.entries()).sort(([a], [b]) => a.localeCompare(b));
        return { week, evts, dateGroups };
      });
  }, [filteredEvents]);

  /* Columns with week grouping */
  const columns = useMemo<ColumnDef<FlatRow, any>[]>(() => {
    const cols: ColumnDef<FlatRow, any>[] = [
      {
        id: 'status_icon',
        header: '',
        size: 36,
        enableSorting: false,
        meta: { sticky: 'left', leftOffset: 0 },
        cell: ({ row }) => {
          if (isChapterBoard()) return null;
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
        meta: { sticky: 'left', leftOffset: 36 },
      },
      {
        accessorKey: 'chapter',
        header: t('attendance.grid.chapter', 'Chapter'),
        size: 100,
        enableSorting: true,
        meta: { sticky: 'left', leftOffset: 196 },
      },
    ];

    /* FIX 1+3+4: event columns grouped by week > date > type abbreviation */
    const typeFull = getTypeFull(t);
    for (const { dateGroups } of weekGroups) {
      for (const [, dateEvts] of dateGroups) {
        for (const ev of dateEvts) {
          const abbr = TYPE_ABBR[ev.type] || ev.type.charAt(0).toUpperCase();
          const fullTypeName = typeFull[abbr] || ev.type;
          cols.push({
            id: `ev_${ev.id}`,
            header: () => (
              <span title={`${fullTypeName} — ${ev.title}`} className="cursor-help font-extrabold">
                {abbr}
              </span>
            ),
            size: 52,
            enableSorting: false,
            meta: { weekNumber: ev.week_number, date: ev.date },
            cell: ({ row }) => {
              const st = statusCell(row.original.attendance[ev.id]);
              const manage = canManageAttendance();
              return (
                <span
                  className={`inline-flex items-center justify-center w-full h-full text-xs ${st.bg} rounded px-1 ${manage ? 'cursor-pointer hover:ring-2 hover:ring-navy/30' : ''}`}
                  {...(manage ? {
                    'data-toggle-event': ev.id,
                    'data-toggle-member': row.original.memberId,
                    'data-toggle-current': row.original.attendance[ev.id] || 'none',
                    role: 'button',
                    tabIndex: 0,
                  } : {})}
                >
                  {st.label}
                </span>
              );
            },
          });
        }
      }
    }

    /* FIX 4: Rate column sticky right */
    cols.push({
      accessorKey: 'rate',
      header: t('attendance.grid.rate', 'Rate %'),
      size: 80,
      enableSorting: true,
      meta: { sticky: 'right' },
      cell: ({ getValue }) => {
        const v = getValue() as number;
        const color = v < 50 ? 'text-red-600' : v < 75 ? 'text-amber-600' : 'text-green-600';
        return <span className={`font-bold ${color}`}>{Math.round(v)}%</span>;
      },
    });

    return cols;
  }, [weekGroups, t, memberReady]);

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

  /* FIX 5: Group rows by tribe for collapsible rendering */
  /* FIX 5b: Include cross-functional members (tribe_id is null) */
  const CROSS_FUNCTIONAL_ID = '__cross_functional__';
  const crossFunctionalTribe: GridTribe = useMemo(() => ({
    tribe_id: CROSS_FUNCTIONAL_ID,
    tribe_name: t('attendance.grid.crossFunctional', 'Cross-functional'),
    leader_name: '\u2014',
    avg_rate: 0,
    member_count: 0,
    members: [],
  }), [t]);

  const groupedByTribe = useMemo(() => {
    if (!data) return [];
    const sortedRows = table.getRowModel().rows;
    const tribeMap = new Map<string, { tribe: GridTribe; rows: typeof sortedRows }>();

    for (const tribe of data.tribes) {
      tribeMap.set(tribe.tribe_id, { tribe, rows: [] });
    }

    const orphanRows: typeof sortedRows = [];

    for (const row of sortedRows) {
      const entry = tribeMap.get(row.original.tribeId);
      if (entry) {
        entry.rows.push(row);
      } else {
        orphanRows.push(row);
      }
    }

    const groups = Array.from(tribeMap.values()).filter((g) => g.rows.length > 0);

    /* Add cross-functional group for members with no tribe */
    if (orphanRows.length > 0) {
      groups.push({ tribe: crossFunctionalTribe, rows: orphanRows });
    }

    return groups;
  }, [data, table.getRowModel().rows, crossFunctionalTribe]);

  const toggleTribe = useCallback((tribeId: string) => {
    setExpandedTribes((prev) => {
      const next = new Set(prev);
      if (next.has(tribeId)) {
        next.delete(tribeId);
      } else {
        next.add(tribeId);
      }
      return next;
    });
  }, []);

  /* CSV Export */
  function exportCsv() {
    if (!data) return;
    const headers = [
      'Name',
      'Tribe',
      'Chapter',
      ...filteredEvents.map((e) => `${fmtDate(e.date)} ${TYPE_ABBR[e.type] || e.type}`),
      'Rate %',
    ];
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

  /* Helper to get sticky style for a column */
  function getStickyThStyle(meta: any): React.CSSProperties {
    if (!meta) return {};
    if (meta.sticky === 'left') return { ...STICKY_LEFT_BASE, left: meta.leftOffset ?? 0 };
    if (meta.sticky === 'right') return STICKY_RIGHT;
    return {};
  }

  function getStickyTdStyle(meta: any): React.CSSProperties {
    if (!meta) return {};
    if (meta.sticky === 'left') return { ...STICKY_LEFT_TD_BASE, left: meta.leftOffset ?? 0 };
    if (meta.sticky === 'right') return STICKY_RIGHT_TD;
    return {};
  }

  /* Total column count for colSpan */
  const totalColCount = columns.length;

  /* ---------------------------------------------------------------- */
  /*  Render                                                           */
  /* ---------------------------------------------------------------- */

  /* Loading */
  if (loading) {
    return (
      <div className="space-y-4">
        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3">
          {Array.from({ length: 6 }).map((_, i) => (
            <div
              key={i}
              className="bg-[var(--surface-card)] border border-[var(--border-subtle)] rounded-2xl p-4 animate-pulse"
            >
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

  return (
    <div className="space-y-5">
      {/* KPI Cards — driven by filteredKPIs so they reflect active filters */}
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3">
        <KpiCard
          icon={Users}
          label={t('attendance.grid.totalMembers', 'Total Members')}
          value={filteredKPIs.total}
        />
        <KpiCard
          icon={Percent}
          label={t('attendance.grid.overallRate', 'Overall Rate')}
          value={`${Math.round(filteredKPIs.avgRate)}%`}
          accent={filteredKPIs.avgRate < 75 ? 'text-amber-500' : 'text-green-500'}
        />
        <KpiCard
          icon={Clock}
          label={t('attendance.grid.totalHours', 'Total Hours')}
          value={Math.round(filteredKPIs.totalHours)}
          suffix="h"
        />
        {!isChapterBoard() && (
          <KpiCard
            icon={ShieldAlert}
            label={t('attendance.grid.detractors', 'Detractors')}
            value={filteredKPIs.detractors}
            accent="text-red-500"
          />
        )}
        {!isChapterBoard() && (
          <KpiCard
            icon={AlertTriangle}
            label={t('attendance.grid.atRisk', 'At Risk')}
            value={filteredKPIs.atRisk}
            accent="text-amber-500"
          />
        )}
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
          <option value="kickoff">{t('attendance.grid.typeKickoff', 'Kickoff')}</option>
          <option value="comms">{t('attendance.grid.typeComms', 'Comms')}</option>
        </select>

        {/* FIX 7: Detractor Status Filter — hidden for chapter_board */}
        {!isChapterBoard() && (
          <select
            value={detractorFilter}
            onChange={(e) => setDetractorFilter(e.target.value as DetractorFilter)}
            className="bg-[var(--surface-base)] border border-[var(--border-default)] rounded-lg px-3 py-1.5 text-sm text-[var(--text-primary)] focus:outline-none focus:ring-2 focus:ring-[var(--color-teal)]"
          >
            <option value="all">{t('attendance.grid.filterAll', 'Todos')}</option>
            <option value="detractor">{t('attendance.grid.filterDetractors', 'Detratores')}</option>
            <option value="at_risk">{t('attendance.grid.filterAtRisk', 'Em Risco')}</option>
            <option value="regular">{t('attendance.grid.filterRegular', 'Regulares')}</option>
          </select>
        )}

        {/* Search */}
        <div className="relative flex-1 min-w-[180px]">
          <Search
            size={14}
            className="absolute left-2.5 top-1/2 -translate-y-1/2 text-[var(--text-muted)]"
          />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder={t('attendance.grid.search', 'Search member...')}
            className="w-full bg-[var(--surface-base)] border border-[var(--border-default)] rounded-lg pl-8 pr-3 py-1.5 text-sm text-[var(--text-primary)] placeholder:text-[var(--text-muted)] focus:outline-none focus:ring-2 focus:ring-[var(--color-teal)]"
          />
        </div>

        {/* Smart filter toggle — GP only */}
        {canManageAttendance() && (
          <label className="inline-flex items-center gap-1.5 text-xs text-[var(--text-muted)] cursor-pointer select-none whitespace-nowrap">
            <input
              type="checkbox"
              checked={showAllEvents}
              onChange={(e) => setShowAllEvents(e.target.checked)}
              className="rounded border-[var(--border-default)] accent-[var(--color-teal)]"
            />
            {t('attendance.grid.showAllEvents', 'Show all events')}
          </label>
        )}

        {/* CSV Export */}
        <button
          onClick={exportCsv}
          className="inline-flex items-center gap-1.5 bg-[var(--color-teal)] text-white text-sm font-semibold px-4 py-1.5 rounded-lg hover:opacity-90 transition-opacity"
        >
          <Download size={14} />
          {t('attendance.grid.export', 'Export CSV')}
        </button>
      </div>

      {/* FIX 3: Legend bar */}
      <div className="flex flex-wrap items-center gap-3 text-xs text-[var(--text-muted)] bg-[var(--surface-card)] border border-[var(--border-subtle)] rounded-lg px-3 py-2">
        <span className="font-semibold text-[var(--text-primary)]">
          {t('attendance.grid.legend', 'Legenda')}:
        </span>
        <span>🌐 <strong>G</strong> = {t('attendance.grid.legendGeral', 'Geral')}</span>
        <span className="text-[var(--border-default)]">|</span>
        <span>🔬 <strong>T</strong> = {t('attendance.grid.legendTribo', 'Tribo')}</span>
        <span className="text-[var(--border-default)]">|</span>
        <span>🚀 <strong>K</strong> = {t('attendance.grid.legendKickoff', 'Kickoff')}</span>
        <span className="text-[var(--border-default)]">|</span>
        <span>👥 <strong>L</strong> = {t('attendance.grid.legendLideranca', 'Liderança')}</span>
        <span className="text-[var(--border-default)]">|</span>
        <span>📢 <strong>C</strong> = {t('attendance.grid.legendComms', 'Comms')}</span>
      </div>

      {/* Grid / Mobile */}
      {isMobile ? (
        <MobileCardList rows={table.getRowModel().rows} events={filteredEvents} t={t} />
      ) : !showAllEvents ? (
        /* Smart mode: each tribe section has its own table with only relevant event columns */
        <div className="bg-[var(--surface-card)] border border-[var(--border-subtle)] rounded-xl overflow-hidden">
          {groupedByTribe.length > 0 ? (
            groupedByTribe.map(({ tribe, rows: tribeRows }) => (
              <SmartTribeSection
                key={tribe.tribe_id}
                tribe={tribe}
                rows={tribeRows}
                allEvents={filteredEvents}
                isExpanded={expandedTribes.has(tribe.tribe_id)}
                onToggle={() => toggleTribe(tribe.tribe_id)}
                t={t}
              />
            ))
          ) : (
            <p className="px-4 py-12 text-center text-[var(--text-muted)] text-sm">
              {t('attendance.grid.noResults', 'No members found.')}
            </p>
          )}
        </div>
      ) : (
        /* Full mode: original single table with all event columns */
        <div className="bg-[var(--surface-card)] border border-[var(--border-subtle)] rounded-xl overflow-auto">
          <table className="w-full text-sm border-collapse">
            <thead>
              {/* Week group header row */}
              {weekGroups.length > 0 && (
                <tr className="border-b border-[var(--border-subtle)]">
                  <th
                    colSpan={3}
                    className="px-2 py-1 text-left text-xs font-bold text-[var(--text-muted)] bg-[var(--surface-base)]"
                    style={{ ...STICKY_LEFT_BASE, left: 0 }}
                  />
                  {weekGroups.map(({ week, evts }) => (
                    <th
                      key={`wk-${week}`}
                      colSpan={evts.length}
                      className="px-2 py-1 text-center text-xs font-bold text-[var(--color-teal)] bg-[var(--surface-base)] border-l border-[var(--border-subtle)]"
                    >
                      {t('attendance.grid.week', 'Sem')} {week}
                    </th>
                  ))}
                  <th
                    className="px-2 py-1 bg-[var(--surface-base)]"
                    style={STICKY_RIGHT}
                  />
                </tr>
              )}

              {/* Date sub-group header row */}
              {weekGroups.length > 0 && (
                <tr className="border-b border-[var(--border-subtle)]">
                  <th
                    colSpan={3}
                    className="px-2 py-0.5 bg-[var(--surface-base)]"
                    style={{ ...STICKY_LEFT_BASE, left: 0 }}
                  />
                  {weekGroups.flatMap(({ dateGroups }) =>
                    dateGroups.map(([date, dateEvts]) => (
                      <th
                        key={`dt-${date}`}
                        colSpan={dateEvts.length}
                        className="px-1 py-0.5 text-center text-[10px] font-semibold text-[var(--text-muted)] bg-[var(--surface-base)] border-l border-[var(--border-subtle)] whitespace-nowrap"
                      >
                        {fmtDate(date)}
                      </th>
                    ))
                  )}
                  <th
                    className="px-2 py-0.5 bg-[var(--surface-base)]"
                    style={STICKY_RIGHT}
                  />
                </tr>
              )}

              {/* Column headers */}
              {table.getHeaderGroups().map((hg) => (
                <tr key={hg.id} className="border-b border-[var(--border-subtle)]">
                  {hg.headers.map((header) => {
                    const meta = header.column.columnDef.meta as any;
                    return (
                      <th
                        key={header.id}
                        className="px-2 py-2 text-left text-xs font-bold text-[var(--text-muted)] bg-[var(--surface-base)] whitespace-nowrap sticky top-0 select-none"
                        style={{
                          width: header.getSize(),
                          ...getStickyThStyle(meta),
                        }}
                        onClick={
                          header.column.getCanSort()
                            ? header.column.getToggleSortingHandler()
                            : undefined
                        }
                      >
                        <span
                          className={`inline-flex items-center gap-1 ${header.column.getCanSort() ? 'cursor-pointer hover:text-[var(--text-primary)]' : ''}`}
                        >
                          {flexRender(header.column.columnDef.header, header.getContext())}
                          {header.column.getIsSorted() === 'asc' && <ChevronUp size={12} />}
                          {header.column.getIsSorted() === 'desc' && <ChevronDown size={12} />}
                        </span>
                      </th>
                    );
                  })}
                </tr>
              ))}
            </thead>
            <tbody>
              {groupedByTribe.length > 0 ? (
                groupedByTribe.map(({ tribe, rows: tribeRows }) => {
                  const isExpanded = expandedTribes.has(tribe.tribe_id);
                  return (
                    <TribeGroup
                      key={tribe.tribe_id}
                      tribe={tribe}
                      rows={tribeRows}
                      isExpanded={isExpanded}
                      onToggle={() => toggleTribe(tribe.tribe_id)}
                      totalColCount={totalColCount}
                      getStickyTdStyle={getStickyTdStyle}
                      t={t}
                    />
                  );
                })
              ) : (
                <tr>
                  <td
                    colSpan={totalColCount}
                    className="px-4 py-12 text-center text-[var(--text-muted)] text-sm"
                  >
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
/*  Tribe Group (collapsible)                                          */
/* ------------------------------------------------------------------ */

function TribeGroup({
  tribe,
  rows,
  isExpanded,
  onToggle,
  totalColCount,
  getStickyTdStyle,
  t,
}: {
  tribe: GridTribe;
  rows: any[];
  isExpanded: boolean;
  onToggle: () => void;
  totalColCount: number;
  getStickyTdStyle: (meta: any) => React.CSSProperties;
  t: (key: string, fb?: string) => string;
}) {
  const chevronClass = isExpanded
    ? 'transform rotate-90 transition-transform'
    : 'transition-transform';

  return (
    <>
      {/* Tribe header row */}
      <tr
        className="border-b border-[var(--border-subtle)] bg-[var(--surface-base)] cursor-pointer hover:bg-[var(--border-subtle)] transition-colors"
        onClick={onToggle}
      >
        <td
          colSpan={totalColCount}
          className="px-3 py-2 text-sm font-bold text-[var(--text-primary)]"
        >
          <span className="inline-flex items-center gap-2">
            <ChevronRight size={14} className={chevronClass} />
            <span>{tribe.tribe_name}</span>
            {tribe.leader_name && (
              <span className="text-[var(--text-muted)] font-normal text-xs">
                ({t('attendance.grid.leader', 'Líder')}: {tribe.leader_name})
              </span>
            )}
            <span className="text-xs font-semibold text-[var(--color-teal)]">
              — {t('attendance.grid.avg', 'Média')}: {Math.round(tribe.avg_rate)}%
            </span>
            <span className="text-xs text-[var(--text-muted)] font-normal">
              ({rows.length} {t('attendance.grid.members', 'members')})
            </span>
          </span>
        </td>
      </tr>

      {/* Member rows */}
      {isExpanded &&
        rows.map((row: any) => (
          <tr
            key={row.id}
            className={`border-b border-[var(--border-subtle)] hover:bg-[var(--surface-base)] transition-colors ${rowTint(row.original.rate)}`}
          >
            {row.getVisibleCells().map((cell: any) => {
              const meta = cell.column.columnDef.meta as any;
              return (
                <td
                  key={cell.id}
                  className="px-2 py-1.5 whitespace-nowrap text-[var(--text-primary)]"
                  style={getStickyTdStyle(meta)}
                >
                  {flexRender(cell.column.columnDef.cell, cell.getContext())}
                </td>
              );
            })}
          </tr>
        ))}
    </>
  );
}

/* ------------------------------------------------------------------ */
/*  Smart Tribe Section (filtered columns per tribe)                   */
/* ------------------------------------------------------------------ */

function SmartTribeSection({
  tribe,
  rows,
  allEvents,
  isExpanded,
  onToggle,
  t,
}: {
  tribe: GridTribe;
  rows: any[];
  allEvents: GridEvent[];
  isExpanded: boolean;
  onToggle: () => void;
  t: (key: string, fb?: string) => string;
}) {
  const relevantEvents = useMemo(
    () => allEvents.filter((evt) => rows.some((row) => row.original.attendance[evt.id] !== 'na')),
    [allEvents, rows],
  );

  const sectionWeekGroups = useMemo(() => {
    const weekMap = new Map<number, GridEvent[]>();
    relevantEvents.forEach((e) => {
      if (!weekMap.has(e.week_number)) weekMap.set(e.week_number, []);
      weekMap.get(e.week_number)!.push(e);
    });
    return Array.from(weekMap.entries())
      .sort(([a], [b]) => a - b)
      .map(([week, evts]) => {
        const dateMap = new Map<string, GridEvent[]>();
        evts.forEach((e) => {
          if (!dateMap.has(e.date)) dateMap.set(e.date, []);
          dateMap.get(e.date)!.push(e);
        });
        return {
          week,
          evts,
          dateGroups: Array.from(dateMap.entries()).sort(([a], [b]) => a.localeCompare(b)),
        };
      });
  }, [relevantEvents]);

  const manage = canManageAttendance();
  const chevronClass = isExpanded ? 'transform rotate-90 transition-transform' : 'transition-transform';

  return (
    <div className="border-b border-[var(--border-subtle)] last:border-b-0">
      {/* Tribe header */}
      <div
        className="px-3 py-2 text-sm font-bold text-[var(--text-primary)] bg-[var(--surface-base)] cursor-pointer hover:bg-[var(--border-subtle)] transition-colors"
        onClick={onToggle}
      >
        <span className="inline-flex items-center gap-2">
          <ChevronRight size={14} className={chevronClass} />
          <span>{tribe.tribe_name}</span>
          {tribe.leader_name && (
            <span className="text-[var(--text-muted)] font-normal text-xs">
              ({t('attendance.grid.leader', 'Líder')}: {tribe.leader_name})
            </span>
          )}
          <span className="text-xs font-semibold text-[var(--color-teal)]">
            — {t('attendance.grid.avg', 'Média')}: {Math.round(tribe.avg_rate)}%
          </span>
          <span className="text-xs text-[var(--text-muted)] font-normal">
            ({rows.length} {t('attendance.grid.members', 'members')})
          </span>
          <span className="text-xs text-[var(--text-muted)] font-normal">
            · {relevantEvents.length} {t('attendance.grid.events', 'events')}
          </span>
        </span>
      </div>

      {isExpanded && (
        <div className="overflow-x-auto">
          <table className="w-full text-sm border-collapse">
            <thead>
              {/* Week headers */}
              {sectionWeekGroups.length > 0 && (
                <tr className="border-b border-[var(--border-subtle)]">
                  <th
                    colSpan={3}
                    className="px-2 py-1 text-left text-xs font-bold text-[var(--text-muted)] bg-[var(--surface-base)]"
                    style={{ ...STICKY_LEFT_BASE, left: 0 }}
                  />
                  {sectionWeekGroups.map(({ week, evts }) => (
                    <th
                      key={`wk-${week}`}
                      colSpan={evts.length}
                      className="px-2 py-1 text-center text-xs font-bold text-[var(--color-teal)] bg-[var(--surface-base)] border-l border-[var(--border-subtle)]"
                    >
                      {t('attendance.grid.week', 'Sem')} {week}
                    </th>
                  ))}
                  <th className="px-2 py-1 bg-[var(--surface-base)]" style={STICKY_RIGHT} />
                </tr>
              )}

              {/* Date headers */}
              {sectionWeekGroups.length > 0 && (
                <tr className="border-b border-[var(--border-subtle)]">
                  <th
                    colSpan={3}
                    className="px-2 py-0.5 bg-[var(--surface-base)]"
                    style={{ ...STICKY_LEFT_BASE, left: 0 }}
                  />
                  {sectionWeekGroups.flatMap(({ dateGroups }) =>
                    dateGroups.map(([date, dateEvts]) => (
                      <th
                        key={`dt-${date}`}
                        colSpan={dateEvts.length}
                        className="px-1 py-0.5 text-center text-[10px] font-semibold text-[var(--text-muted)] bg-[var(--surface-base)] border-l border-[var(--border-subtle)] whitespace-nowrap"
                      >
                        {fmtDate(date)}
                      </th>
                    )),
                  )}
                  <th className="px-2 py-0.5 bg-[var(--surface-base)]" style={STICKY_RIGHT} />
                </tr>
              )}

              {/* Column headers */}
              <tr className="border-b border-[var(--border-subtle)]">
                <th
                  className="px-2 py-2 text-left text-xs font-bold text-[var(--text-muted)] bg-[var(--surface-base)] whitespace-nowrap"
                  style={{ ...STICKY_LEFT_BASE, left: 0, width: 36 }}
                />
                <th
                  className="px-2 py-2 text-left text-xs font-bold text-[var(--text-muted)] bg-[var(--surface-base)] whitespace-nowrap"
                  style={{ ...STICKY_LEFT_BASE, left: 36, width: 160 }}
                >
                  {t('attendance.grid.name', 'Name')}
                </th>
                <th
                  className="px-2 py-2 text-left text-xs font-bold text-[var(--text-muted)] bg-[var(--surface-base)] whitespace-nowrap"
                  style={{ ...STICKY_LEFT_BASE, left: 196, width: 100 }}
                >
                  {t('attendance.grid.chapter', 'Chapter')}
                </th>
                {relevantEvents.map((ev) => {
                  const abbr = TYPE_ABBR[ev.type] || ev.type.charAt(0).toUpperCase();
                  const fullTypeName = getTypeFull(t)[abbr] || ev.type;
                  return (
                    <th
                      key={ev.id}
                      className="px-2 py-2 text-center text-xs font-bold text-[var(--text-muted)] bg-[var(--surface-base)] whitespace-nowrap"
                      style={{ width: 52 }}
                    >
                      <span title={`${fullTypeName} — ${ev.title}`} className="cursor-help font-extrabold">
                        {abbr}
                      </span>
                    </th>
                  );
                })}
                <th
                  className="px-2 py-2 text-left text-xs font-bold text-[var(--text-muted)] bg-[var(--surface-base)] whitespace-nowrap"
                  style={{ ...STICKY_RIGHT, width: 80 }}
                >
                  {t('attendance.grid.rate', 'Rate %')}
                </th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row: any) => {
                const r: FlatRow = row.original;
                const rateColor = r.rate < 50 ? 'text-red-600' : r.rate < 75 ? 'text-amber-600' : 'text-green-600';
                return (
                  <tr
                    key={row.id}
                    className={`border-b border-[var(--border-subtle)] hover:bg-[var(--surface-base)] transition-colors ${rowTint(r.rate)}`}
                  >
                    <td
                      className="px-2 py-1.5 whitespace-nowrap text-[var(--text-primary)]"
                      style={{ ...STICKY_LEFT_TD_BASE, left: 0 }}
                    >
                      {r.detractorStatus === 'detractor' ? (
                        <span title={t('attendance.grid.detractor', 'Detractor')}>🔴</span>
                      ) : r.detractorStatus === 'at_risk' ? (
                        <span title={t('attendance.grid.atRisk', 'At risk')}>🟡</span>
                      ) : null}
                    </td>
                    <td
                      className="px-2 py-1.5 whitespace-nowrap text-[var(--text-primary)]"
                      style={{ ...STICKY_LEFT_TD_BASE, left: 36 }}
                    >
                      {r.name}
                    </td>
                    <td
                      className="px-2 py-1.5 whitespace-nowrap text-[var(--text-primary)]"
                      style={{ ...STICKY_LEFT_TD_BASE, left: 196 }}
                    >
                      {r.chapter}
                    </td>
                    {relevantEvents.map((ev) => {
                      const st = statusCell(r.attendance[ev.id]);
                      return (
                        <td key={ev.id} className="px-2 py-1.5 whitespace-nowrap text-[var(--text-primary)]">
                          <span
                            className={`inline-flex items-center justify-center w-full h-full text-xs ${st.bg} rounded px-1 ${manage ? 'cursor-pointer hover:ring-2 hover:ring-navy/30' : ''}`}
                            {...(manage
                              ? {
                                  'data-toggle-event': ev.id,
                                  'data-toggle-member': r.memberId,
                                  'data-toggle-current': r.attendance[ev.id] || 'none',
                                  role: 'button',
                                  tabIndex: 0,
                                }
                              : {})}
                          >
                            {st.label}
                          </span>
                        </td>
                      );
                    })}
                    <td
                      className="px-2 py-1.5 whitespace-nowrap text-[var(--text-primary)]"
                      style={STICKY_RIGHT_TD}
                    >
                      <span className={`font-bold ${rateColor}`}>{Math.round(r.rate)}%</span>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
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
        const rateColor =
          r.rate < 50 ? 'text-red-600' : r.rate < 75 ? 'text-amber-600' : 'text-green-600';
        const statusPrefix =
          r.detractorStatus === 'detractor'
            ? '🔴 '
            : r.detractorStatus === 'at_risk'
              ? '🟡 '
              : '';

        return (
          <div
            key={r.memberId}
            className={`bg-[var(--surface-card)] border border-[var(--border-subtle)] rounded-xl p-3 ${rowTint(r.rate)}`}
          >
            <div className="flex items-center justify-between mb-2">
              <div>
                <p className="text-sm font-bold text-[var(--text-primary)]">
                  {statusPrefix}
                  {r.name}
                </p>
                <p className="text-xs text-[var(--text-muted)]">
                  {r.tribeName} &middot; {r.chapter}
                </p>
              </div>
              <span className={`text-lg font-extrabold ${rateColor}`}>{Math.round(r.rate)}%</span>
            </div>

            {/* Scrollable attendance strip with date headers */}
            <div className="overflow-x-auto -mx-1 px-1 pb-1">
              <table className="border-collapse" style={{ minWidth: `${events.length * 2.25}rem` }}>
                <thead>
                  <tr>
                    {events.map((ev) => (
                      <th
                        key={`h-${ev.id}`}
                        className="text-[7px] leading-tight text-center text-[var(--text-muted)] font-medium px-0.5 pb-0.5 whitespace-nowrap"
                        title={ev.title}
                      >
                        {fmtDate(ev.date)}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    {events.map((ev) => {
                      const st = statusCell(r.attendance[ev.id]);
                      return (
                        <td key={ev.id} className="px-0.5 text-center">
                          <span
                            title={`${fmtDate(ev.date)} ${ev.title}`}
                            className={`inline-flex items-center justify-center w-7 h-6 text-[10px] rounded ${st.bg}`}
                          >
                            {st.label}
                          </span>
                        </td>
                      );
                    })}
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        );
      })}
    </div>
  );
}
