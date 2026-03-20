import { useState, useEffect, useMemo, useCallback } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';
import { AttendanceCell } from '../attendance/AttendanceCell';
import { getTribePermissions } from '../../lib/permissions';
import type { CellStatus } from '../attendance/types';

/* ------------------------------------------------------------------ */
/*  Types                                                              */
/* ------------------------------------------------------------------ */

interface AttendanceEvent {
  id: string;
  date: string;
  title: string;
  type: string;
  is_tribe_event: boolean;
  is_leadership: boolean;
}

interface AttendanceMember {
  id: string;
  name: string;
  rate: number;
  present_count: number;
  eligible_count: number;
  attendance: Record<string, 'present' | 'absent' | 'na'>;
}

interface AttendanceSummary {
  overall_rate: number;
  perfect_attendance: number;
  below_50: number;
}

interface AttendanceGrid {
  summary: AttendanceSummary;
  events: AttendanceEvent[];
  members: AttendanceMember[];
}

interface Props {
  tribeId: number;
}

/* ------------------------------------------------------------------ */
/*  Helpers                                                            */
/* ------------------------------------------------------------------ */

type EventTypeFilter = 'all' | 'general' | 'tribe' | 'leadership';
type SortKey = 'rate' | 'name';

const STATUS_ICON: Record<string, string> = {
  present: '✅',
  absent: '❌',
  na: '—',
};

const EVENT_TYPE_ICON: Record<string, string> = {
  general: '🌐',
  tribe: '🏠',
  leadership: '👑',
};

function formatDate(iso: string): string {
  const d = new Date(iso);
  const dd = String(d.getDate()).padStart(2, '0');
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  return `${dd}/${mm}`;
}

function rateColor(rate: number): string {
  if (rate < 50) return 'var(--color-danger, #ef4444)';
  if (rate < 75) return 'var(--color-warning, #f59e0b)';
  return 'var(--color-success, #22c55e)';
}

function rateBg(rate: number): string {
  if (rate < 50) return 'rgba(239,68,68,0.07)';
  if (rate < 75) return 'rgba(245,158,11,0.06)';
  return 'rgba(34,197,94,0.05)';
}

/* ------------------------------------------------------------------ */
/*  Component                                                          */
/* ------------------------------------------------------------------ */

export default function TribeAttendanceTab({ tribeId }: Props) {
  const t = usePageI18n();

  const [data, setData] = useState<AttendanceGrid | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<EventTypeFilter>('all');
  const [sortKey, setSortKey] = useState<SortKey>('rate');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);
  const getMember = useCallback(() => (window as any).navGetMember?.(), []);

  // Permissions
  const member = getMember();
  const perms = member ? getTribePermissions(member, tribeId) : null;
  const canToggleAttendance = perms?.canToggleAttendance ?? false;
  const canSelfCheckIn = (perms?.canSelfCheckIn && perms?.selfCheckInHasWindow) ?? false;
  const currentMemberId = member?.id ?? '';

  // Toggle handler
  const handleToggle = useCallback(async (eventId: string, memberId: string, currentStatus: CellStatus) => {
    if (currentStatus === 'na') return;
    const sb = getSb();
    if (!sb) return;
    const newPresent = currentStatus !== 'present';
    try {
      await sb.rpc('mark_member_present', { p_event_id: eventId, p_member_id: memberId, p_present: newPresent });
      // Refresh grid
      const eventType = filter === 'all' ? null : filter;
      const { data: result } = await sb.rpc('get_tribe_attendance_grid', { p_tribe_id: tribeId, p_event_type: eventType });
      if (result) setData(result as AttendanceGrid);
    } catch (e: any) {
      (window as any).toast?.(e.message || 'Erro', 'error');
    }
  }, [getSb, tribeId, filter]);

  // Self check-in handler
  const handleSelfCheckIn = useCallback(async (eventId: string) => {
    const sb = getSb();
    if (!sb) return;
    try {
      const { data: res } = await sb.rpc('register_own_presence', { p_event_id: eventId });
      if (res?.success) {
        (window as any).toast?.('Presença registrada!', 'success');
        const eventType = filter === 'all' ? null : filter;
        const { data: result } = await sb.rpc('get_tribe_attendance_grid', { p_tribe_id: tribeId, p_event_type: eventType });
        if (result) setData(result as AttendanceGrid);
      } else {
        (window as any).toast?.(res?.message || res?.error || 'Erro', 'error');
      }
    } catch (e: any) {
      (window as any).toast?.(e.message || 'Erro', 'error');
    }
  }, [getSb, tribeId, filter]);

  // Check-in window helper
  const isWithinCheckInWindow = (eventDate: string): boolean => {
    const eventTs = new Date(eventDate + 'T12:00:00').getTime();
    const now = Date.now();
    return now >= eventTs - 2 * 60 * 60 * 1000 && now <= eventTs + 48 * 60 * 60 * 1000;
  };

  /* ---- data loading ---- */
  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);

    (async () => {
      try {
        const sb = getSb();
        if (!sb) throw new Error('Supabase client unavailable');

        const eventType = filter === 'all' ? null : filter;
        const { data: result, error: rpcErr } = await sb.rpc(
          'get_tribe_attendance_grid',
          { p_tribe_id: tribeId, p_event_type: eventType },
        );

        if (rpcErr) throw rpcErr;
        if (!cancelled) setData(result as AttendanceGrid);
      } catch (e: any) {
        if (!cancelled) setError(e.message ?? 'Unknown error');
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();

    return () => { cancelled = true; };
  }, [tribeId, filter, getSb]);

  /* ---- sort ---- */
  const toggleSort = (key: SortKey) => {
    if (sortKey === key) setSortDir(d => (d === 'asc' ? 'desc' : 'asc'));
    else { setSortKey(key); setSortDir(key === 'rate' ? 'desc' : 'asc'); }
  };

  const sortedMembers = useMemo(() => {
    if (!data) return [];
    const arr = [...data.members];
    const dir = sortDir === 'asc' ? 1 : -1;
    arr.sort((a, b) => {
      if (sortKey === 'rate') return dir * (a.rate - b.rate);
      return dir * a.name.localeCompare(b.name);
    });
    return arr;
  }, [data, sortKey, sortDir]);

  /* ---- render helpers ---- */

  const filterOptions: { value: EventTypeFilter; label: string }[] = [
    { value: 'all', label: t('attendance.filter.all', 'All') },
    { value: 'general', label: t('attendance.filter.general', 'General') },
    { value: 'tribe', label: t('attendance.filter.tribe', 'Tribe') },
    { value: 'leadership', label: t('attendance.filter.leadership', 'Leadership') },
  ];

  /* ---------------------------------------------------------------- */
  /*  Loading / error / empty                                         */
  /* ---------------------------------------------------------------- */

  if (loading) {
    return (
      <div className="flex items-center justify-center py-16">
        <div className="animate-spin h-6 w-6 border-2 border-[var(--accent)] border-t-transparent rounded-full" />
        <span className="ml-3 text-sm text-[var(--text-secondary)]">
          {t('attendance.loading', 'Loading attendance data...')}
        </span>
      </div>
    );
  }

  if (error) {
    return (
      <div className="rounded-lg border border-red-300 bg-red-50 dark:bg-red-900/20 dark:border-red-800 p-4 text-sm text-red-700 dark:text-red-300">
        {t('attendance.error', 'Failed to load attendance data')}: {error}
      </div>
    );
  }

  if (!data || data.members.length === 0) {
    return (
      <div className="text-center py-16 text-[var(--text-secondary)] text-sm">
        {t('attendance.empty', 'No attendance data available for this tribe.')}
      </div>
    );
  }

  const { summary, events } = data;

  /* ---------------------------------------------------------------- */
  /*  Main render                                                     */
  /* ---------------------------------------------------------------- */

  return (
    <div className="space-y-4">

      {/* ---------- Filter Bar ---------- */}
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-xs font-semibold text-[var(--text-secondary)] uppercase tracking-wide">
          {t('attendance.filter.label', 'Event type')}:
        </span>
        {filterOptions.map(opt => (
          <button
            key={opt.value}
            onClick={() => setFilter(opt.value)}
            className={`px-3 py-1 rounded-full text-xs font-medium transition-colors ${
              filter === opt.value
                ? 'bg-[var(--accent)] text-white'
                : 'bg-[var(--bg-secondary,#f3f4f6)] text-[var(--text-secondary)] hover:bg-[var(--bg-tertiary,#e5e7eb)]'
            }`}
          >
            {opt.label}
          </button>
        ))}
      </div>

      {/* ---------- KPI Cards ---------- */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <KpiCard
          label={t('attendance.kpi.overall', 'Overall Rate')}
          value={`${Math.round(summary.overall_rate)}%`}
          accent={rateColor(summary.overall_rate)}
        />
        <KpiCard
          label={t('attendance.kpi.perfect', 'Perfect Attendance')}
          value={String(summary.perfect_attendance)}
          accent="var(--color-success, #22c55e)"
        />
        <KpiCard
          label={t('attendance.kpi.below50', 'Below 50%')}
          value={String(summary.below_50)}
          accent="var(--color-danger, #ef4444)"
        />
        <KpiCard
          label={t('attendance.kpi.events', 'Total Events')}
          value={String(events.length)}
          accent="var(--accent, #6366f1)"
        />
      </div>

      {/* ---------- Attendance Grid ---------- */}
      <div className="overflow-x-auto rounded-lg border border-[var(--border-color,#e5e7eb)]">
        <table className="w-full border-collapse text-xs">
          <thead>
            <tr className="bg-[var(--bg-secondary,#f9fafb)]">
              {/* Member name column */}
              <th
                onClick={() => toggleSort('name')}
                className="sticky left-0 z-10 bg-[var(--bg-secondary,#f9fafb)] px-3 py-2 text-left text-[10px] font-bold text-[var(--text-secondary)] uppercase tracking-wide cursor-pointer hover:text-[var(--text-primary)] whitespace-nowrap select-none min-w-[140px]"
              >
                {t('attendance.col.member', 'Member')}{' '}
                {sortKey === 'name' ? (sortDir === 'asc' ? '↑' : '↓') : ''}
              </th>

              {/* Event columns */}
              {events.map(ev => {
                const icon = ev.is_leadership
                  ? EVENT_TYPE_ICON.leadership
                  : ev.is_tribe_event
                    ? EVENT_TYPE_ICON.tribe
                    : EVENT_TYPE_ICON.general;
                return (
                  <th
                    key={ev.id}
                    title={ev.title}
                    className="px-1.5 py-2 text-center text-[10px] font-medium text-[var(--text-secondary)] whitespace-nowrap"
                  >
                    <div>{formatDate(ev.date)}</div>
                    <div className="text-[9px]">{icon}</div>
                  </th>
                );
              })}

              {/* Rate column */}
              <th
                onClick={() => toggleSort('rate')}
                className="sticky right-0 z-10 bg-[var(--bg-secondary,#f9fafb)] px-3 py-2 text-right text-[10px] font-bold text-[var(--text-secondary)] uppercase tracking-wide cursor-pointer hover:text-[var(--text-primary)] whitespace-nowrap select-none min-w-[64px]"
              >
                {t('attendance.col.rate', 'Rate')}{' '}
                {sortKey === 'rate' ? (sortDir === 'asc' ? '↑' : '↓') : ''}
              </th>
            </tr>
          </thead>

          <tbody>
            {sortedMembers.map(member => {
              const pct = Math.round(member.rate);
              return (
                <tr
                  key={member.id}
                  className="border-t border-[var(--border-color,#e5e7eb)] hover:bg-[var(--bg-tertiary,#f3f4f6)] transition-colors"
                  style={{ backgroundColor: rateBg(member.rate) }}
                >
                  {/* Name */}
                  <td className="sticky left-0 z-[5] px-3 py-1.5 font-medium text-[var(--text-primary)] whitespace-nowrap"
                    style={{ backgroundColor: 'inherit' }}
                  >
                    {member.name}
                  </td>

                  {/* Attendance cells — interactive via AttendanceCell */}
                  {events.map(ev => {
                    const status = (member.attendance[ev.id] ?? 'na') as CellStatus;
                    const isSelf = member.id === currentMemberId;

                    return (
                      <td
                        key={ev.id}
                        className="px-1.5 py-1.5 text-center whitespace-nowrap"
                        title={`${member.name} — ${ev.title}: ${status}`}
                      >
                        <AttendanceCell
                          status={status}
                          canToggle={canToggleAttendance}
                          isSelf={isSelf}
                          canSelfCheckIn={isSelf && canSelfCheckIn}
                          isWithinWindow={isWithinCheckInWindow(ev.date)}
                          onToggle={() => handleToggle(ev.id, member.id, status)}
                          onCheckIn={() => handleSelfCheckIn(ev.id)}
                        />
                      </td>
                    );
                  })}

                  {/* Rate */}
                  <td
                    className="sticky right-0 z-[5] px-3 py-1.5 text-right font-bold whitespace-nowrap"
                    style={{
                      backgroundColor: 'inherit',
                      color: rateColor(member.rate),
                    }}
                  >
                    {pct}%
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  KPI Card sub-component                                             */
/* ------------------------------------------------------------------ */

function KpiCard({ label, value, accent }: { label: string; value: string; accent: string }) {
  return (
    <div className="rounded-lg border border-[var(--border-color,#e5e7eb)] bg-[var(--bg-primary,#fff)] p-3 text-center">
      <div className="text-2xl font-bold" style={{ color: accent }}>
        {value}
      </div>
      <div className="mt-1 text-[10px] font-medium text-[var(--text-secondary)] uppercase tracking-wide">
        {label}
      </div>
    </div>
  );
}
