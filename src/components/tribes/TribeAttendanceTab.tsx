import { useState, useEffect, useMemo, useCallback, useRef } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';
import { AttendanceCell } from '../attendance/AttendanceCell';
import { getTribePermissions } from '../../lib/tribePermissions';
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
  attendance: Record<string, CellStatus>;
  member_status?: string;
  detractor_status?: string;
  consecutive_absences?: number;
  chapter?: string;
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
  /** @deprecated Use initiativeId instead */
  tribeId?: number;
  initiativeId?: string;
}

/* ------------------------------------------------------------------ */
/*  Helpers                                                            */
/* ------------------------------------------------------------------ */

type EventTypeFilter = 'all' | 'geral' | 'tribo' | 'lideranca';
type SortKey = 'rate' | 'name';

const STATUS_ICON: Record<string, string> = {
  present: '✅',
  absent: '❌',
  na: '—',
  scheduled: '📅',
  excused: '⚠️',
};

const EVENT_TYPE_ICON: Record<string, string> = {
  geral: '🌐',
  tribo: '🔬',
  lideranca: '👥',
  kickoff: '🚀',
  comms: '📢',
  webinar: '🎙️',
  evento_externo: '🌍',
  '1on1': '🔒',
  parceria: '🤝',
  entrevista: '📌',
};

const MONTH_ABBR_PT = ['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago','Set','Out','Nov','Dez'];

function formatDate(iso: string): string {
  const d = new Date(iso + 'T12:00:00');
  const dd = String(d.getDate()).padStart(2, '0');
  const mmm = MONTH_ABBR_PT[d.getMonth()] || String(d.getMonth() + 1).padStart(2, '0');
  return `${dd}/${mmm}`;
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

export default function TribeAttendanceTab({ tribeId, initiativeId }: Props) {
  const t = usePageI18n();

  const [data, setData] = useState<AttendanceGrid | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<EventTypeFilter>('all');
  const [sortKey, setSortKey] = useState<SortKey>('rate');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);
  const getMember = useCallback(() => (window as any).navGetMember?.(), []);

  // Permissions (defensive — never crashes render)
  let canToggleAttendance = false;
  let canSelfCheckIn = false;
  let currentMemberId = '';
  try {
    const member = getMember();
    if (member) {
      const perms = getTribePermissions(member, tribeId || 0, initiativeId);
      canToggleAttendance = perms.canToggleAttendance;
      canSelfCheckIn = !!(perms.canSelfCheckIn && perms.selfCheckInHasWindow);
      currentMemberId = member.id || '';
    }
  } catch { /* permissions unavailable — read-only mode */ }

  // Toggle handler with toast + undo
  const [undoToast, setUndoToast] = useState<{ msg: string; undo: () => void } | null>(null);

  /* p87 Sprint UX: modal state for excused via long-press */
  const [excusedModal, setExcusedModal] = useState<null | { eventId: string; memberId: string; memberName: string; current: CellStatus }>(null);
  const [reasonDraft, setReasonDraft] = useState('');
  const [excuseReasons, setExcuseReasons] = useState<Record<string, string>>({});
  const longPressTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const longPressFiredRef = useRef(false);

  const refreshGrid = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    const eventType = filter === 'all' ? null : filter;
    const { data: result } = initiativeId
      ? await sb.rpc('get_initiative_attendance_grid', { p_initiative_id: initiativeId, p_event_type: eventType })
      : await sb.rpc('get_tribe_attendance_grid', { p_tribe_id: tribeId, p_event_type: eventType });
    if (result) setData(result as AttendanceGrid);
  }, [getSb, tribeId, initiativeId, filter]);

  /* p87 Bug Ana Carla fix (Sprint UX): cycle present↔absent only.
     Excused state via long-press modal (handleSetState) — captures reason. */
  const handleToggle = useCallback(async (eventId: string, memberId: string, currentStatus: CellStatus) => {
    if (currentStatus === 'na' || currentStatus === 'scheduled') return;
    const sb = getSb();
    if (!sb) return;
    const memberName = (Array.isArray(data?.members) ? data.members : []).find(m => m.id === memberId)?.name || '';
    const cellKey = `${eventId}:${memberId}`;

    // If currently excused, confirm before destroying (going to absent)
    if (currentStatus === 'excused' && excuseReasons[cellKey]) {
      const reason = excuseReasons[cellKey];
      const confirmMsg = (t('attendance.grid.confirmDestroyReason', 'Isso removerá o motivo registrado: "{reason}". Continuar?') || 'Confirmar?').replace('{reason}', reason);
      if (!window.confirm(confirmMsg)) return;
    }

    // Cycle: present → absent, absent/excused → present
    const newPresent = currentStatus !== 'present';
    try {
      await sb.rpc('mark_member_present', { p_event_id: eventId, p_member_id: memberId, p_present: newPresent });
      if (currentStatus === 'excused') {
        await sb.rpc('mark_member_excused', { p_event_id: eventId, p_member_id: memberId, p_excused: false });
        setExcuseReasons(prev => { const n = { ...prev }; delete n[cellKey]; return n; });
      }
      await refreshGrid();
      const msg = `${memberName}: ${newPresent ? t('attendance.grid.toastPresent', '✅ Presente') : t('attendance.grid.toastAbsent', '❌ Ausente')}`;
      setUndoToast({
        msg,
        undo: async () => {
          try {
            await sb.rpc('mark_member_present', { p_event_id: eventId, p_member_id: memberId, p_present: !newPresent });
            await refreshGrid();
          } catch {}
          setUndoToast(null);
        },
      });
      setTimeout(() => setUndoToast(prev => prev?.msg === msg ? null : prev), 5000);
    } catch (e: any) {
      (window as any).toast?.(e.message || 'Erro', 'error');
    }
  }, [getSb, tribeId, initiativeId, filter, data, refreshGrid, excuseReasons, t]);

  /* Load existing excuse reasons for tooltip + modal pre-fill */
  useEffect(() => {
    (async () => {
      const sb = getSb();
      if (!sb) return;
      try {
        const { data: excuses } = await sb.from('attendance')
          .select('event_id, member_id, excuse_reason')
          .eq('excused', true)
          .not('excuse_reason', 'is', null);
        if (excuses) {
          const map: Record<string, string> = {};
          for (const ex of excuses) {
            map[`${ex.event_id}:${ex.member_id}`] = ex.excuse_reason as string;
          }
          setExcuseReasons(map);
        }
      } catch { /* best effort */ }
    })();
  }, [data]);

  const startLongPress = useCallback((eventId: string, memberId: string, memberName: string, current: CellStatus) => {
    longPressFiredRef.current = false;
    if (longPressTimerRef.current) clearTimeout(longPressTimerRef.current);
    longPressTimerRef.current = setTimeout(() => {
      longPressFiredRef.current = true;
      setExcusedModal({ eventId, memberId, memberName, current });
      setReasonDraft(excuseReasons[`${eventId}:${memberId}`] || '');
    }, 300);
  }, [excuseReasons]);

  const cancelLongPress = useCallback(() => {
    if (longPressTimerRef.current) { clearTimeout(longPressTimerRef.current); longPressTimerRef.current = null; }
  }, []);

  const handleSetState = useCallback(async (state: 'present' | 'absent' | 'excused', reason: string = '') => {
    if (!excusedModal) return;
    const sb = getSb();
    if (!sb) return;
    const { eventId, memberId, memberName, current } = excusedModal;
    const cellKey = `${eventId}:${memberId}`;

    // Confirm if destroying persisted reason
    if (current === 'excused' && state !== 'excused' && excuseReasons[cellKey]) {
      const persistedReason = excuseReasons[cellKey];
      const confirmMsg = (t('attendance.grid.confirmDestroyReason', 'Isso removerá o motivo registrado: "{reason}". Continuar?') || 'Confirmar?').replace('{reason}', persistedReason);
      if (!window.confirm(confirmMsg)) return;
    }

    setExcusedModal(null);
    try {
      if (state === 'excused') {
        await sb.rpc('mark_member_excused', {
          p_event_id: eventId, p_member_id: memberId, p_excused: true, p_reason: reason || null,
        });
      } else {
        await sb.rpc('mark_member_present', {
          p_event_id: eventId, p_member_id: memberId, p_present: state === 'present',
        });
        if (current === 'excused') {
          await sb.rpc('mark_member_excused', { p_event_id: eventId, p_member_id: memberId, p_excused: false });
        }
      }
      await refreshGrid();
      // Update local reasons cache
      if (state === 'excused' && reason) {
        setExcuseReasons(prev => ({ ...prev, [cellKey]: reason }));
      } else if (state !== 'excused') {
        setExcuseReasons(prev => { const n = { ...prev }; delete n[cellKey]; return n; });
      }
      const toastMap: Record<string, string> = {
        present: t('attendance.grid.toastPresent', '✅ Presente'),
        excused: t('attendance.grid.toastExcused', '⚠️ Falta justificada'),
        absent: t('attendance.grid.toastAbsent', '❌ Ausente'),
      };
      (window as any).toast?.(`${memberName}: ${toastMap[state]}`, 'success');
    } catch (e: any) {
      (window as any).toast?.(e.message || 'Erro', 'error');
    }
  }, [excusedModal, excuseReasons, refreshGrid, t]);

  // Self check-in handler
  const handleSelfCheckIn = useCallback(async (eventId: string) => {
    const sb = getSb();
    if (!sb) return;
    try {
      const { data: res } = await sb.rpc('register_own_presence', { p_event_id: eventId });
      if (res?.success) {
        (window as any).toast?.(t('comp.attendance.selfCheckedIn', '✅ Presença registrada!'), 'success');
        await refreshGrid();
      } else {
        (window as any).toast?.(res?.message || res?.error || 'Erro', 'error');
      }
    } catch (e: any) {
      (window as any).toast?.(e.message || 'Erro', 'error');
    }
  }, [getSb, refreshGrid]);

  // Check-in window helper
  const isWithinCheckInWindow = (eventDate: string): boolean => {
    const eventTs = new Date(eventDate + 'T12:00:00').getTime();
    const now = Date.now();
    return now >= eventTs - 2 * 60 * 60 * 1000 && now <= eventTs + 48 * 60 * 60 * 1000;
  };

  /* ---- data loading ---- */
  useEffect(() => {
    let cancelled = false;
    let retries = 0;
    setLoading(true);
    setError(null);

    async function load() {
      try {
        const sb = getSb();
        if (!sb) {
          if (retries < 30) { retries++; setTimeout(load, 300); return; }
          throw new Error('Supabase client unavailable');
        }

        const eventType = filter === 'all' ? null : filter;
        const { data: result, error: rpcErr } = initiativeId
          ? await sb.rpc('get_initiative_attendance_grid', { p_initiative_id: initiativeId, p_event_type: eventType })
          : await sb.rpc('get_tribe_attendance_grid', { p_tribe_id: tribeId, p_event_type: eventType });

        if (rpcErr) throw rpcErr;
        if (!cancelled) setData(result as AttendanceGrid);
      } catch (e: any) {
        if (!cancelled) setError(e.message ?? 'Unknown error');
      } finally {
        if (!cancelled) setLoading(false);
      }
    }
    load();

    return () => { cancelled = true; };
  }, [tribeId, initiativeId, filter, getSb]);

  /* ---- sort ---- */
  const toggleSort = (key: SortKey) => {
    if (sortKey === key) setSortDir(d => (d === 'asc' ? 'desc' : 'asc'));
    else { setSortKey(key); setSortDir(key === 'rate' ? 'desc' : 'asc'); }
  };

  const sortedMembers = useMemo(() => {
    if (!data) return [];
    const arr = [...(Array.isArray(data.members) ? data.members : [])];
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
    { value: 'geral', label: t('attendance.filter.general', 'Gerais') },
    { value: 'tribo', label: t('attendance.filter.tribe', 'Tribo') },
    { value: 'lideranca', label: t('attendance.filter.leadership', 'Liderança') },
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

  if (!data || !Array.isArray(data.members) || data.members.length === 0) {
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
          value={`${Math.round(summary.overall_rate <= 1 ? summary.overall_rate * 100 : summary.overall_rate)}%`}
          accent={rateColor(summary.overall_rate <= 1 ? summary.overall_rate * 100 : summary.overall_rate)}
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
          label={t('attendance.kpi.events_past', 'Eventos Realizados')}
          value={String((summary as any).past_events ?? events.filter((e: any) => !e.is_future).length)}
          accent="var(--accent, #6366f1)"
        />
      </div>

      {/* ---------- Legend ---------- */}
      <div className="flex flex-wrap gap-x-4 gap-y-1 text-[10px] text-[var(--text-muted)] mb-1 px-1">
        <span>✅ {t('attendance.legend_present', 'Presente')}</span>
        <span>❌ {t('attendance.legend_absent', 'Ausente')}</span>
        <span>⚠️ {t('attendance.legend_excused', 'Falta justificada')}</span>
        <span>⚠️* {t('attendance.legend_excused_reason', 'com motivo')}</span>
        <span>— {t('attendance.legend_not_required', 'Não convocado')}</span>
        <span className="text-[var(--border-color)]">|</span>
        <span>🌐 {t('attendance.legend_general', 'Geral')}</span>
        <span>🔬 {t('attendance.legend_tribe', 'Tribo')}</span>
        <span>👥 {t('attendance.legend_leadership', 'Liderança')}</span>
        <span>🚀 Kickoff</span>
      </div>

      {/* p87 Sprint UX: help banner explaining cycle + long-press */}
      {canToggleAttendance && (
        <div className="bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg px-3 py-2 mb-2 flex items-start gap-2 text-[11px] text-blue-800 dark:text-blue-200">
          <span className="text-base leading-none">💡</span>
          <div>
            <strong>{t('attendance.helpTitle', 'Como marcar presença')}:</strong>{' '}
            {t('attendance.helpClick', 'Clique rápido alterna entre Presente ✅ e Ausente ❌.')}{' '}
            <strong>{t('attendance.helpLongPress', 'Toque longo (300ms) ou segure o mouse')}</strong>{' '}
            {t('attendance.helpLongPressDetail', 'abre menu com Falta Justificada ⚠️ + campo de motivo (opcional, recomendado).')}
          </div>
        </div>
      )}

      {/* ---------- Attendance Grid ---------- */}
      <div className="overflow-x-auto rounded-lg border border-[var(--border-color,#e5e7eb)]">
        <table className="w-full border-collapse text-xs">
          <thead>
            <tr className="bg-[var(--bg-secondary,#f9fafb)]">
              <th
                onClick={() => toggleSort('name')}
                className="sticky left-0 z-20 bg-[var(--bg-secondary,#f9fafb)] px-3 py-2 text-left text-[10px] font-bold text-[var(--text-secondary)] uppercase tracking-wide cursor-pointer hover:text-[var(--text-primary)] whitespace-nowrap select-none min-w-[140px]"
              >
                {t('attendance.col.member', 'Membro')}{' '}
                {sortKey === 'name' ? (sortDir === 'asc' ? '↑' : '↓') : ''}
              </th>
              {events.map(ev => (
                <th
                  key={ev.id}
                  title={ev.title}
                  className={`px-1.5 py-2 text-center text-[10px] font-medium text-[var(--text-secondary)] whitespace-nowrap ${(ev as any).is_future ? 'opacity-50' : ''}`}
                >
                  <div>{formatDate(ev.date)}</div>
                  <div className="text-[9px]">{EVENT_TYPE_ICON[ev.type] || '🌐'}</div>
                </th>
              ))}
              <th
                onClick={() => toggleSort('rate')}
                className="sticky right-0 z-10 bg-[var(--bg-secondary,#f9fafb)] px-3 py-2 text-right text-[10px] font-bold text-[var(--text-secondary)] uppercase tracking-wide cursor-pointer hover:text-[var(--text-primary)] whitespace-nowrap select-none min-w-[64px]"
              >
                {t('attendance.col.rate', 'Taxa')}{' '}
                {sortKey === 'rate' ? (sortDir === 'asc' ? '↑' : '↓') : ''}
              </th>
            </tr>
          </thead>

          <tbody>
            {sortedMembers.map(member => {
              const rawRate = member.rate <= 1 ? member.rate * 100 : member.rate;
              const pct = Math.round(rawRate);
              return (
                <tr
                  key={member.id}
                  className="border-t border-[var(--border-color,#e5e7eb)] hover:bg-[var(--bg-tertiary,#f3f4f6)] transition-colors"
                  style={{ backgroundColor: rateBg(rawRate) }}
                >
                  {/* Name */}
                  <td className="sticky left-0 z-10 px-3 py-1.5 font-medium text-[var(--text-primary)] whitespace-nowrap bg-[var(--surface-card,#fff)]"
                  >
                    {member.name}
                    {member.member_status === 'observer' && <span className="text-[9px] text-blue-500 ml-1">(Observer)</span>}
                    {member.member_status === 'alumni' && <span className="text-[9px] text-gray-400 ml-1">(Alumni)</span>}
                  </td>

                  {/* Attendance cells — interactive via AttendanceCell + long-press wrapper */}
                  {events.map(ev => {
                    const status = (member.attendance[ev.id] ?? 'na') as CellStatus;
                    const isSelf = member.id === currentMemberId;
                    const cellKey = `${ev.id}:${member.id}`;
                    const reason = status === 'excused' ? excuseReasons[cellKey] : undefined;
                    const titleText = reason
                      ? `⚠️ ${reason}`
                      : canToggleAttendance
                        ? `${member.name} — ${ev.title} — clique alterna / segure para menu`
                        : `${member.name} — ${ev.title}: ${status}`;

                    // p87 Sprint UX: wrap with pointer handlers for long-press → modal
                    const cellContent = (
                      <AttendanceCell
                        status={status}
                        canToggle={canToggleAttendance}
                        isSelf={isSelf}
                        canSelfCheckIn={isSelf && canSelfCheckIn}
                        isWithinWindow={isWithinCheckInWindow(ev.date)}
                        onToggle={() => {
                          // Skip if long-press already fired (modal opened)
                          if (longPressFiredRef.current) {
                            longPressFiredRef.current = false;
                            return;
                          }
                          handleToggle(ev.id, member.id, status);
                        }}
                        onCheckIn={() => handleSelfCheckIn(ev.id)}
                      />
                    );

                    return (
                      <td
                        key={ev.id}
                        className="px-1.5 py-1.5 text-center whitespace-nowrap"
                        title={titleText}
                      >
                        {canToggleAttendance && status !== 'na' && status !== 'scheduled' ? (
                          <span
                            className="inline-block select-none"
                            onPointerDown={() => startLongPress(ev.id, member.id, member.name, status)}
                            onPointerUp={cancelLongPress}
                            onPointerCancel={cancelLongPress}
                            onPointerLeave={cancelLongPress}
                            onContextMenu={(e) => e.preventDefault()}
                          >
                            {cellContent}
                            {reason && <sup className="text-[9px] text-blue-600 ml-0.5" title={reason}>*</sup>}
                          </span>
                        ) : cellContent}
                      </td>
                    );
                  })}

                  {/* Rate */}
                  <td
                    className="sticky right-0 z-[5] px-3 py-1.5 text-right font-bold whitespace-nowrap"
                    style={{
                      backgroundColor: 'inherit',
                      color: rateColor(rawRate),
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

      {/* Undo toast */}
      {undoToast && (
        <div className="fixed bottom-4 left-1/2 -translate-x-1/2 z-50 bg-[var(--surface-elevated,#1f2937)] text-[var(--text-primary,#fff)] px-4 py-3 rounded-lg shadow-lg flex items-center gap-3 text-sm border border-[var(--border-default)]">
          <span>{undoToast.msg}</span>
          <button onClick={undoToast.undo} className="text-blue-400 font-semibold hover:text-blue-300 border-0 bg-transparent cursor-pointer text-sm">
            {t('attendance.toast_undo', 'Desfazer')}
          </button>
        </div>
      )}

      {/* p87 Sprint UX: Excused state modal (long-press trigger) */}
      {excusedModal && (
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="tribe-excused-modal-title"
          className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
          onClick={(e) => { if (e.target === e.currentTarget) setExcusedModal(null); }}
        >
          <div className="bg-[var(--surface-card,#fff)] dark:bg-gray-800 rounded-2xl p-5 max-w-md w-full shadow-2xl border border-[var(--border-default)]">
            <h3 id="tribe-excused-modal-title" className="text-base font-bold mb-1 text-[var(--text-primary)]">
              {t('attendance.grid.modal.title', 'Marcar presença')}
            </h3>
            <p className="text-sm text-[var(--text-muted)] mb-4">{excusedModal.memberName}</p>
            <div className="space-y-2">
              <button
                type="button"
                onClick={() => handleSetState('present')}
                className="w-full bg-green-50 hover:bg-green-100 dark:bg-green-900/20 dark:hover:bg-green-900/40 text-green-800 dark:text-green-200 px-4 py-3 rounded-lg flex items-center gap-2 font-semibold border border-green-200 dark:border-green-800 transition-colors"
              >
                ✅ {t('attendance.grid.modal.present', 'Presente')}
              </button>
              <div className="border-2 border-blue-200 dark:border-blue-800 bg-blue-50/50 dark:bg-blue-900/10 rounded-lg p-3">
                <button
                  type="button"
                  onClick={() => handleSetState('excused', reasonDraft.trim())}
                  className="w-full bg-blue-100 hover:bg-blue-200 dark:bg-blue-900/40 dark:hover:bg-blue-900/60 text-blue-800 dark:text-blue-200 px-4 py-3 rounded-lg flex items-center gap-2 font-semibold border border-blue-300 dark:border-blue-700 transition-colors mb-2"
                >
                  ⚠️ {t('attendance.grid.modal.excused', 'Falta justificada')}
                </button>
                <input
                  type="text"
                  value={reasonDraft}
                  onChange={(e) => setReasonDraft(e.target.value)}
                  placeholder={t('attendance.grid.modal.reasonPlaceholder', 'Motivo (recomendado)')}
                  aria-label={t('attendance.grid.modal.reasonAriaLabel', 'Motivo da falta justificada')}
                  aria-describedby="tribe-excused-reason-hint"
                  className="w-full text-sm border border-blue-300 dark:border-blue-700 rounded px-3 py-2 bg-white dark:bg-gray-900 text-[var(--text-primary)]"
                />
                <p id="tribe-excused-reason-hint" className="text-[11px] text-[var(--text-muted)] mt-1">
                  {t('attendance.grid.modal.reasonHint', 'Recomendado para registro de auditoria. Não obrigatório.')}
                </p>
              </div>
              <button
                type="button"
                onClick={() => handleSetState('absent')}
                className="w-full bg-red-50 hover:bg-red-100 dark:bg-red-900/20 dark:hover:bg-red-900/40 text-red-800 dark:text-red-200 px-4 py-3 rounded-lg flex items-center gap-2 font-semibold border border-red-200 dark:border-red-800 transition-colors"
              >
                ❌ {t('attendance.grid.modal.absent', 'Ausente')}
              </button>
            </div>
            <button
              type="button"
              onClick={() => setExcusedModal(null)}
              className="mt-4 text-sm text-[var(--text-muted)] hover:text-[var(--text-primary)] underline"
            >
              {t('attendance.grid.modal.cancel', 'Cancelar')}
            </button>
          </div>
        </div>
      )}
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
