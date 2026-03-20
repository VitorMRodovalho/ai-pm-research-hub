import { useState, useEffect } from 'react';
import { useAttendance } from '../../hooks/useAttendance';
import { AttendanceCell } from './AttendanceCell';
import { getTribePermissions } from '../../lib/tribePermissions';
import type { AttendanceEvent } from './types';

interface MemberContext {
  id: string;
  tribe_id: number | null;
  operational_role: string;
  designations: string[];
  is_superadmin: boolean;
}

interface AttendanceGridProps {
  supabase: any;
  currentMember: MemberContext;
  tribeId: number;
  t: (key: string, fallback?: string) => string;
}

function getISOWeek(dateStr: string): number {
  const d = new Date(dateStr);
  const dayNum = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - dayNum);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  return Math.ceil((((d.getTime() - yearStart.getTime()) / 86400000) + 1) / 7);
}

function groupEventsByWeek(events: AttendanceEvent[]): Record<string, AttendanceEvent[]> {
  return events.reduce((acc, evt) => {
    const week = `S${getISOWeek(evt.date)}`;
    if (!acc[week]) acc[week] = [];
    acc[week].push(evt);
    return acc;
  }, {} as Record<string, AttendanceEvent[]>);
}

function formatShortDate(iso: string): string {
  const d = new Date(iso);
  return `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}`;
}

function rateColor(rate: number): string {
  if (rate >= 0.8) return 'text-green-500';
  if (rate >= 0.5) return 'text-yellow-500';
  return 'text-red-500';
}

function isWithinCheckInWindow(eventDate: string): boolean {
  const eventTs = new Date(eventDate + 'T12:00:00').getTime();
  const now = Date.now();
  const twoHoursBefore = eventTs - 2 * 60 * 60 * 1000;
  const fortyEightAfter = eventTs + 48 * 60 * 60 * 1000;
  return now >= twoHoursBefore && now <= fortyEightAfter;
}

export function AttendanceGrid({ supabase, currentMember, tribeId, t }: AttendanceGridProps) {
  const perms = getTribePermissions(currentMember, tribeId);
  const { grid, loading, error, fetchGrid, toggleMember, selfCheckIn, getEffectiveStatus } =
    useAttendance({ supabase, tribeId });

  const [filter, setFilter] = useState<string | null>(null);
  const [sortKey, setSortKey] = useState<'rate' | 'name'>('rate');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');

  useEffect(() => { fetchGrid(filter); }, [fetchGrid, filter]);

  const toggleSort = (key: 'rate' | 'name') => {
    if (sortKey === key) setSortDir(d => d === 'asc' ? 'desc' : 'asc');
    else { setSortKey(key); setSortDir(key === 'rate' ? 'desc' : 'asc'); }
  };

  if (loading && !grid) {
    return (
      <div className="flex items-center justify-center py-16">
        <div className="animate-spin h-6 w-6 border-2 border-[var(--accent)] border-t-transparent rounded-full" />
        <span className="ml-3 text-sm text-[var(--text-secondary)]">
          {t('attendance.loading', 'Carregando...')}
        </span>
      </div>
    );
  }

  if (error) {
    return (
      <div className="rounded-lg border border-red-300 bg-red-50 p-4 text-sm text-red-700">
        {t('attendance.error', 'Erro ao carregar presença')}: {error}
      </div>
    );
  }

  if (!grid || grid.events.length === 0) {
    return (
      <div className="text-center py-16 text-[var(--text-secondary)] text-sm">
        {t('attendance.empty', 'Nenhum dado de presença disponível.')}
      </div>
    );
  }

  const { summary, events } = grid;
  const eventsByWeek = groupEventsByWeek(events);

  const sortedMembers = [...grid.members].sort((a, b) => {
    const dir = sortDir === 'asc' ? 1 : -1;
    if (sortKey === 'rate') return dir * (a.rate - b.rate);
    return dir * a.name.localeCompare(b.name);
  });

  const filters = [
    { key: null, label: t('attendance.filter.all', 'Todos') },
    { key: 'geral', label: t('attendance.filter.general', 'Gerais') },
    { key: 'tribo', label: t('attendance.filter.tribe', 'Tribo') },
    { key: 'lideranca', label: t('attendance.filter.leadership', 'Liderança') },
  ];

  return (
    <div className="space-y-4">
      {/* Filter bar */}
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-xs font-semibold text-[var(--text-secondary)] uppercase tracking-wide">
          {t('attendance.filter.label', 'Tipo')}:
        </span>
        {filters.map(f => (
          <button
            key={f.key ?? 'all'}
            onClick={() => setFilter(f.key)}
            className={`px-3 py-1 rounded-full text-xs font-medium border-0 cursor-pointer transition-colors ${
              filter === f.key
                ? 'bg-[var(--accent,#6366f1)] text-white'
                : 'bg-[var(--surface-section-cool,#f3f4f6)] text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]'
            }`}
          >
            {f.label}
          </button>
        ))}
      </div>

      {/* Summary cards */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <SummaryCard label={t('attendance.kpi.overall', 'Taxa Geral')} value={`${Math.round(summary.overall_rate)}%`} color={rateColor(summary.overall_rate / 100)} />
        <SummaryCard label={t('attendance.kpi.perfect', 'Presença 100%')} value={String(summary.perfect_attendance)} color="text-green-500" />
        <SummaryCard label={t('attendance.kpi.below50', 'Abaixo de 50%')} value={String(summary.below_50)} color="text-red-500" />
        <SummaryCard label={t('attendance.kpi.events', 'Eventos')} value={String(events.length)} color="text-[var(--accent)]" />
      </div>

      {/* Attendance grid */}
      <div className="overflow-x-auto rounded-lg border border-[var(--border-default,#e5e7eb)]">
        <table className="w-full border-collapse text-xs">
          <thead>
            {/* Week grouping row */}
            <tr className="bg-[var(--surface-section-cool,#f9fafb)]">
              <th
                onClick={() => toggleSort('name')}
                rowSpan={2}
                className="sticky left-0 z-20 bg-[var(--surface-section-cool,#f9fafb)] px-3 py-2 text-left text-[10px] font-bold text-[var(--text-secondary)] uppercase tracking-wide cursor-pointer hover:text-[var(--text-primary)] whitespace-nowrap select-none min-w-[140px]"
              >
                {t('attendance.col.member', 'Membro')} {sortKey === 'name' ? (sortDir === 'asc' ? '↑' : '↓') : ''}
              </th>
              {Object.entries(eventsByWeek).map(([week, evts]) => (
                <th key={week} colSpan={evts.length} className="px-1 py-1.5 text-center text-[9px] font-bold text-[var(--text-muted)] uppercase tracking-wider border-b border-[var(--border-subtle)]">
                  {week}
                </th>
              ))}
              <th
                onClick={() => toggleSort('rate')}
                rowSpan={2}
                className="sticky right-0 z-20 bg-[var(--surface-section-cool,#f9fafb)] px-3 py-2 text-right text-[10px] font-bold text-[var(--text-secondary)] uppercase tracking-wide cursor-pointer hover:text-[var(--text-primary)] whitespace-nowrap select-none min-w-[60px]"
              >
                {t('attendance.col.rate', 'Taxa')} {sortKey === 'rate' ? (sortDir === 'asc' ? '↑' : '↓') : ''}
              </th>
            </tr>
            {/* Date + type icon row */}
            <tr className="bg-[var(--surface-section-cool,#f9fafb)]">
              {events.map(evt => (
                <th key={evt.id} title={evt.title} className="px-1 py-1.5 text-center text-[10px] font-medium text-[var(--text-secondary)] whitespace-nowrap">
                  <div>{formatShortDate(evt.date)}</div>
                  <div className="text-[9px]">{evt.type === 'geral' ? '🌐' : evt.is_leadership ? '👥' : evt.is_tribe_event ? '🔬' : '🌐'}</div>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {sortedMembers.map(member => {
              const pct = Math.round(member.rate);
              return (
                <tr key={member.id} className="border-t border-[var(--border-subtle,#e5e7eb)] hover:bg-[var(--surface-hover)] transition-colors">
                  <td className="sticky left-0 z-10 px-3 py-1.5 font-medium text-[var(--text-primary)] whitespace-nowrap bg-[var(--surface-card,#fff)]">
                    {member.name}
                  </td>
                  {events.map(evt => {
                    const serverStatus = member.attendance[evt.id] ?? 'absent';
                    const effectiveStatus = getEffectiveStatus(evt.id, member.id, serverStatus);
                    const isSelf = member.id === currentMember.id;

                    return (
                      <td key={evt.id} className="px-1 py-1.5 text-center whitespace-nowrap">
                        <AttendanceCell
                          status={effectiveStatus}
                          canToggle={perms.canToggleAttendance}
                          isSelf={isSelf}
                          canSelfCheckIn={isSelf && perms.canSelfCheckIn && perms.selfCheckInHasWindow}
                          isWithinWindow={isWithinCheckInWindow(evt.date)}
                          onToggle={() => toggleMember(evt.id, member.id, effectiveStatus)}
                          onCheckIn={() => selfCheckIn(evt.id)}
                        />
                      </td>
                    );
                  })}
                  <td className={`sticky right-0 z-10 px-3 py-1.5 text-right font-bold whitespace-nowrap bg-[var(--surface-card,#fff)] ${rateColor(member.rate / 100)}`}>
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

function SummaryCard({ label, value, color }: { label: string; value: string; color: string }) {
  return (
    <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-3">
      <div className="text-[10px] uppercase tracking-wide font-semibold text-[var(--text-secondary)]">{label}</div>
      <div className={`text-2xl font-extrabold ${color}`}>{value}</div>
    </div>
  );
}
