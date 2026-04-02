import { useState, useEffect, useCallback } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';
import { Search, Users, Clock, CheckCircle2, CalendarDays } from 'lucide-react';
import { hasPermission } from '../../lib/permissions';

function getSb() { return (window as any).navGetSb?.(); }

interface Event {
  id: string; date: string; type: string; title: string;
  tribe_id: number | null; tribe_name: string | null;
  headcount: number; duration_minutes: number | null; duration_actual: number | null;
}
interface Member {
  id: string; name: string; tribe_id: number | null;
  operational_role: string;
}
interface AttendanceRecord {
  member_id: string; present: boolean;
}

interface MemberInfo {
  id: string; tribe_id: number | null; operational_role: string; is_superadmin: boolean;
}

const EVENT_TYPE_LABELS: Record<string, string> = {
  general_meeting: 'Reunião Geral',
  tribe_meeting: 'Reunião de Tribo',
  leadership_meeting: 'Reunião de Liderança',
  kickoff: 'Kick-off',
  webinar: 'Webinar',
  interview: 'Entrevista',
  external_event: 'Evento Externo',
};

export default function AttendanceForm() {
  const t = usePageI18n();
  const [member, setMember] = useState<MemberInfo | null>(null);
  const [events, setEvents] = useState<Event[]>([]);
  const [selectedEvent, setSelectedEvent] = useState<Event | null>(null);
  const [members, setMembers] = useState<Member[]>([]);
  const [existing, setExisting] = useState<Set<string>>(new Set());
  const [checked, setChecked] = useState<Set<string>>(new Set());
  const [search, setSearch] = useState('');
  const [duration, setDuration] = useState('');
  const [loading, setLoading] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [collapsed, setCollapsed] = useState(true);

  // Get member from nav
  useEffect(() => {
    const tryGet = () => {
      const m = (window as any).navGetMember?.();
      if (m) { setMember(m); return true; }
      return false;
    };
    if (tryGet()) return;
    const handler = ((e: CustomEvent) => { if (e.detail) setMember(e.detail); }) as EventListener;
    window.addEventListener('nav:member', handler);
    return () => window.removeEventListener('nav:member', handler);
  }, []);

  const isGP = !!member && hasPermission(member, 'admin.access');
  const isLeader = !!member && hasPermission(member, 'event.create');

  // Load events (must be BEFORE any conditional return to respect hooks order)
  useEffect(() => {
    if (!member) return;
    (async () => {
      const sb = getSb();
      if (!sb) return;
      const { data } = await sb.rpc('get_recent_events', { p_days_back: 60, p_days_forward: 7 });
      if (data) {
        let filtered = data as Event[];
        if (!isGP && isLeader) {
          filtered = filtered.filter((e: Event) =>
            e.tribe_id === null || e.tribe_id === member.tribe_id
          );
        }
        setEvents(filtered);
      }
    })();
  }, [member]);

  // Load members + existing attendance when event selected
  const onEventSelect = useCallback(async (eventId: string) => {
    if (!member) return;
    const ev = events.find(e => e.id === eventId);
    if (!ev) return;
    setSelectedEvent(ev);
    setLoading(true);
    setChecked(new Set());
    setDuration(ev.duration_actual?.toString() || '');

    const sb = getSb();
    if (!sb) return;

    const { data: memberData } = await sb
      .from('active_members')
      .select('id, name, tribe_id, operational_role')
      .order('name');

    const { data: attData } = await sb
      .from('attendance')
      .select('member_id, present')
      .eq('event_id', eventId)
      .eq('present', true);

    const existingIds = new Set<string>((attData || []).map((a: AttendanceRecord) => a.member_id));
    setExisting(existingIds);

    let filteredMembers = (memberData || []) as Member[];
    if (ev.type === 'tribe_meeting' && ev.tribe_id) {
      filteredMembers = filteredMembers.filter(m => m.tribe_id === ev.tribe_id);
    } else if (!isGP && isLeader) {
      filteredMembers = filteredMembers.filter(m => m.tribe_id === member.tribe_id);
    }

    setMembers(filteredMembers);
    setLoading(false);
  }, [member, events, isGP, isLeader]);

  // Don't render until member is loaded (AFTER all hooks)
  if (!member) return null;

  const toggleMember = (id: string) => {
    setChecked(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  };

  const selectAll = () => {
    const visible = filteredMembers.filter(m => !existing.has(m.id));
    setChecked(new Set(visible.map(m => m.id)));
  };

  const submit = async () => {
    if (!selectedEvent || checked.size === 0) return;
    setSubmitting(true);
    const sb = getSb();
    if (!sb) return;
    try {
      const { data, error } = await sb.rpc('register_attendance_batch', {
        p_event_id: selectedEvent.id,
        p_member_ids: Array.from(checked),
        p_registered_by: member.id,
      });
      if (error) throw error;

      // Update duration if changed
      if (duration && Number(duration) !== selectedEvent.duration_actual) {
        await sb.rpc('update_event_duration', {
          p_event_id: selectedEvent.id,
          p_duration_actual: Number(duration),
          p_updated_by: member.id,
        });
      }

      (window as any).toast?.(t('comp.attendance.registered', '{count} attendances registered').replace('{count}', String(data)), 'success');
      // Refresh existing
      setExisting(prev => {
        const next = new Set(prev);
        checked.forEach(id => next.add(id));
        return next;
      });
      setChecked(new Set());
    } catch (e: any) {
      (window as any).toast?.(e?.message || 'Erro ao registrar', 'error');
    } finally {
      setSubmitting(false);
    }
  };

  const filteredMembers = members.filter(m =>
    m.name.toLowerCase().includes(search.toLowerCase())
  );

  const fmtDate = (d: string) => {
    const dt = new Date(d + 'T12:00:00');
    return dt.toLocaleDateString('pt-BR', { day: '2-digit', month: 'short', year: 'numeric' });
  };

  return (
    <div className="bg-[var(--surface-card)] border border-[var(--border-subtle)] rounded-2xl overflow-hidden">
      {/* Collapsible header */}
      <button
        onClick={() => setCollapsed(!collapsed)}
        className="w-full flex items-center justify-between p-4 text-left bg-transparent border-0 cursor-pointer hover:bg-[var(--surface-hover)] transition-colors"
      >
        <div className="flex items-center gap-2">
          <Users size={18} className="text-[var(--color-teal)]" />
          <span className="text-sm font-bold text-[var(--text-primary)]">Registrar Presença</span>
        </div>
        <span className="text-xs text-[var(--text-secondary)]">{collapsed ? '▼' : '▲'}</span>
      </button>

      {!collapsed && (
        <div className="px-4 pb-4 space-y-4 border-t border-[var(--border-subtle)]">
          {/* Event selector */}
          <div className="pt-4">
            <label className="text-xs font-semibold text-[var(--text-secondary)] block mb-1.5">
              <CalendarDays size={12} className="inline mr-1" />{t('comp.attendance.selectEvent', 'Select Event')}
            </label>
            <select
              className="w-full px-3 py-2 text-sm rounded-xl border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] outline-none"
              value={selectedEvent?.id || ''}
              onChange={e => onEventSelect(e.target.value)}
            >
              <option value="">— Escolha um evento —</option>
              {events.map(ev => (
                <option key={ev.id} value={ev.id}>
                  {fmtDate(ev.date)} · {EVENT_TYPE_LABELS[ev.type] || ev.type}
                  {ev.tribe_name ? ` · ${ev.tribe_name}` : ''}
                  {` (${ev.headcount} presentes)`}
                </option>
              ))}
            </select>
          </div>

          {/* Event info + member list */}
          {selectedEvent && !loading && (
            <>
              <div className="flex flex-wrap gap-3 text-xs text-[var(--text-secondary)]">
                <span className="px-2 py-1 rounded-lg bg-[var(--surface-base)]">
                  📅 {fmtDate(selectedEvent.date)}
                </span>
                <span className="px-2 py-1 rounded-lg bg-[var(--surface-base)]">
                  🏷️ {EVENT_TYPE_LABELS[selectedEvent.type] || selectedEvent.type}
                </span>
                {selectedEvent.tribe_name && (
                  <span className="px-2 py-1 rounded-lg bg-[var(--surface-base)]">
                    🏠 {selectedEvent.tribe_name}
                  </span>
                )}
                <span className="px-2 py-1 rounded-lg bg-[var(--surface-base)]">
                  ✅ {existing.size} já registrados
                </span>
              </div>

              {/* Search + select all */}
              <div className="flex items-center gap-2">
                <div className="flex-1 relative">
                  <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-[var(--text-muted)]" />
                  <input
                    type="text"
                    placeholder={t('comp.attendance.searchMember', 'Search member...')}
                    value={search}
                    onChange={e => setSearch(e.target.value)}
                    className="w-full pl-8 pr-3 py-2 text-sm rounded-xl border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] outline-none"
                  />
                </div>
                <button
                  onClick={selectAll}
                  className="px-3 py-2 text-xs font-semibold rounded-xl border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-secondary)] cursor-pointer hover:bg-[var(--surface-hover)] transition-colors"
                >
                  {t('comp.attendance.selectAll', 'Select all')}
                </button>
              </div>

              {/* Member list */}
              <div className="max-h-[320px] overflow-y-auto space-y-1 pr-1">
                {filteredMembers.map(m => {
                  const isExisting = existing.has(m.id);
                  const isChecked = checked.has(m.id);
                  return (
                    <label
                      key={m.id}
                      className={`flex items-center gap-3 px-3 py-2 rounded-xl cursor-pointer transition-colors ${
                        isExisting ? 'opacity-60 cursor-default' : isChecked ? 'bg-teal/10' : 'hover:bg-[var(--surface-hover)]'
                      }`}
                    >
                      <input
                        type="checkbox"
                        checked={isExisting || isChecked}
                        disabled={isExisting}
                        onChange={() => !isExisting && toggleMember(m.id)}
                        className="accent-[var(--color-teal)] w-4 h-4"
                      />
                      <span className="flex-1 text-sm text-[var(--text-primary)]">{m.name}</span>
                      {isExisting && (
                        <span className="text-[10px] font-semibold px-2 py-0.5 rounded-full bg-green-100 text-green-700">
                          já registrado
                        </span>
                      )}
                    </label>
                  );
                })}
              </div>

              {/* Duration + submit */}
              <div className="flex items-end gap-3 pt-2 border-t border-[var(--border-subtle)]">
                <div className="w-40">
                  <label className="text-xs font-semibold text-[var(--text-secondary)] block mb-1">
                    <Clock size={12} className="inline mr-1" />Duração real (min)
                  </label>
                  <input
                    type="number"
                    value={duration}
                    onChange={e => setDuration(e.target.value)}
                    placeholder={selectedEvent.duration_minutes?.toString() || '60'}
                    className="w-full px-3 py-2 text-sm rounded-xl border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] outline-none"
                  />
                </div>
                <button
                  onClick={submit}
                  disabled={submitting || checked.size === 0}
                  className="flex-1 flex items-center justify-center gap-2 px-4 py-2 text-sm font-bold rounded-xl bg-[var(--color-teal)] text-white border-0 cursor-pointer hover:opacity-90 transition-all disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  <CheckCircle2 size={16} />
                  {submitting ? 'Registrando...' : `Registrar Presença (${checked.size})`}
                </button>
              </div>
            </>
          )}

          {loading && (
            <div className="py-8 text-center text-sm text-[var(--text-secondary)]">{t('comp.attendance.loadingMembers', 'Loading members...')}</div>
          )}
        </div>
      )}
    </div>
  );
}
