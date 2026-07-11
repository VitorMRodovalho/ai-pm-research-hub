import { useState, useEffect, useCallback } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';
import { CalendarDays, CheckCircle2, Clock, History, Loader2, Lock } from 'lucide-react';
import { SELF_CHECKIN_WINDOW_HOURS, withCheckinHours } from '../../lib/attendance-window';

/* #105 — member self-service "minhas reuniões" widget (discoverability, handoff 2026-04-25 Item 6).
   Three tabs derived client-side from get_my_meetings (member-scoped: own tribe + general events,
   confidential gate applied server-side):
     - Próximas            → event_date >= today
     - Recentes (sem marcar) → past 7 days AND no attendance row
     - Histórico           → past AND present=true

   Self-mark reuses register_own_presence (the same RPC as the workspace check-in banner) so the
   widget HONOURS the canonical self-check-in policy: a member may self-check-in only within the
   self-check-in window after an event (audience-gated). Rows past that window are shown as "prazo expirado
   · solicite ao gestor" instead of a dead button — no policy bypass. */

function getSb() { return (window as any).navGetSb?.(); }

interface Meeting {
  event_id: string;
  event_title: string;
  event_date: string;            // YYYY-MM-DD
  event_type: string;
  duration_minutes: number | null;
  initiative_id: string | null;
  initiative_title: string | null;
  attendance_present: boolean | null;   // null = no attendance row (not marked)
  excused: boolean | null;
}

type TabKey = 'upcoming' | 'unmarked' | 'history';

const EVENT_TYPE_LABELS: Record<string, string> = {
  general_meeting: 'Reunião Geral',
  tribe_meeting: 'Reunião de Tribo',
  leadership_meeting: 'Reunião de Liderança',
  kickoff: 'Kick-off',
  webinar: 'Webinar',
  interview: 'Entrevista',
  external_event: 'Evento Externo',
};

function ymd(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/* Mirrors register_own_presence: checkable while now < event-midnight + the self-check-in window (these are past
   events, so the 2h-before lower bound is always satisfied). */
function withinCheckinWindow(dateStr: string): boolean {
  const eventMidnight = new Date(dateStr + 'T00:00:00').getTime();
  return Date.now() < eventMidnight + SELF_CHECKIN_WINDOW_HOURS * 3600000;
}

export default function MyMeetingsIsland() {
  const t = usePageI18n();
  const [meetings, setMeetings] = useState<Meeting[]>([]);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<TabKey>('upcoming');
  const [marking, setMarking] = useState<string | null>(null);

  const fetchMeetings = useCallback(async () => {
    const sb = getSb();
    if (!sb) { setTimeout(fetchMeetings, 300); return; }
    setLoading(true);
    const { data, error } = await sb.rpc('get_my_meetings', { p_days_back: 30, p_days_forward: 60 });
    if (!error && data) setMeetings(data as Meeting[]);
    setLoading(false);
  }, []);

  useEffect(() => { fetchMeetings(); }, [fetchMeetings]);

  const todayStr = ymd(new Date());
  const sevenAgoStr = ymd(new Date(Date.now() - 7 * 86400000));

  const upcoming = meetings
    .filter(m => m.event_date >= todayStr)
    .sort((a, b) => a.event_date.localeCompare(b.event_date));
  const unmarked = meetings
    .filter(m => m.event_date < todayStr && m.event_date >= sevenAgoStr && m.attendance_present == null);
  const history = meetings
    .filter(m => m.event_date < todayStr && m.attendance_present === true);

  const checkIn = async (eventId: string) => {
    setMarking(eventId);
    const sb = getSb();
    const { data, error } = await sb.rpc('register_own_presence', { p_event_id: eventId });
    setMarking(null);
    if (error || !data?.success) {
      (window as any).toast?.(data?.message || error?.message || t('comp.myMeetings.markError', 'Erro ao marcar presença'), 'error');
      return;
    }
    (window as any).toast?.(t('comp.myMeetings.marked', 'Presença registrada'), 'success');
    await fetchMeetings();
  };

  const typeLabel = (type: string) => t(`comp.myMeetings.type.${type}`, EVENT_TYPE_LABELS[type] || type);

  const fmtDate = (d: string) =>
    new Date(d + 'T12:00:00').toLocaleDateString(undefined, { day: '2-digit', month: 'short', year: 'numeric' });

  const rows = tab === 'upcoming' ? upcoming : tab === 'unmarked' ? unmarked : history;

  const emptyMsg = tab === 'upcoming'
    ? t('comp.myMeetings.emptyUpcoming', 'Nenhuma reunião agendada.')
    : tab === 'unmarked'
      ? t('comp.myMeetings.emptyUnmarked', 'Nada pendente — sua presença está em dia.')
      : t('comp.myMeetings.emptyHistory', 'Ainda sem presenças registradas.');

  const tabs: { key: TabKey; label: string; count: number; icon: typeof CalendarDays }[] = [
    { key: 'upcoming', label: t('comp.myMeetings.tabUpcoming', 'Próximas'), count: upcoming.length, icon: CalendarDays },
    { key: 'unmarked', label: t('comp.myMeetings.tabUnmarked', 'Recentes (sem marcar)'), count: unmarked.length, icon: Clock },
    { key: 'history', label: t('comp.myMeetings.tabHistory', 'Histórico'), count: history.length, icon: History },
  ];

  return (
    <div className="bg-[var(--surface-card)] border border-[var(--border-subtle)] rounded-2xl overflow-hidden">
      <div className="flex items-center gap-2 p-4 border-b border-[var(--border-subtle)]">
        <CalendarDays size={18} className="text-[var(--color-teal)]" />
        <span className="text-sm font-bold text-[var(--text-primary)]">{t('comp.myMeetings.title', 'Minhas reuniões')}</span>
      </div>

      {/* Tabs */}
      <div className="flex flex-wrap gap-1 px-3 pt-3">
        {tabs.map(tb => {
          const Icon = tb.icon;
          const active = tab === tb.key;
          return (
            <button
              key={tb.key}
              onClick={() => setTab(tb.key)}
              className={`flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold rounded-lg border-0 cursor-pointer transition-colors ${
                active ? 'bg-[var(--color-teal)] text-white' : 'bg-[var(--surface-base)] text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]'
              }`}
            >
              <Icon size={13} />
              {tb.label}
              {tb.count > 0 && (
                <span className={`px-1.5 py-0.5 rounded-full text-[10px] font-bold ${active ? 'bg-white/25' : 'bg-[var(--surface-hover)]'}`}>
                  {tb.count}
                </span>
              )}
            </button>
          );
        })}
      </div>

      {/* Body */}
      <div className="p-3">
        {loading ? (
          <div className="flex items-center justify-center py-10 text-[var(--text-secondary)] text-sm">
            <Loader2 size={18} className="animate-spin mr-2" /> {t('comp.myMeetings.loading', 'Carregando...')}
          </div>
        ) : rows.length === 0 ? (
          <div className="py-10 text-center text-sm text-[var(--text-muted)]">{emptyMsg}</div>
        ) : (
          <div className="space-y-1.5 max-h-[360px] overflow-y-auto pr-1">
            {rows.map(m => {
              const canCheckin = tab === 'unmarked' && withinCheckinWindow(m.event_date);
              return (
                <div key={m.event_id} className="flex items-center gap-3 px-3 py-2 rounded-xl bg-[var(--surface-base)]">
                  <div className="min-w-0 flex-1">
                    <div className="text-sm font-medium text-[var(--text-primary)] truncate">{m.event_title || typeLabel(m.event_type)}</div>
                    <div className="text-[11px] text-[var(--text-muted)] flex flex-wrap gap-x-2 gap-y-0.5">
                      <span>📅 {fmtDate(m.event_date)}</span>
                      <span>🏷️ {typeLabel(m.event_type)}</span>
                      {m.initiative_title && <span>🏠 {m.initiative_title}</span>}
                    </div>
                  </div>
                  {tab === 'history' ? (
                    <span className="flex-shrink-0 text-[10px] font-semibold px-2 py-0.5 rounded-full bg-emerald-100 text-emerald-700 flex items-center gap-1">
                      <CheckCircle2 size={12} /> {t('comp.myMeetings.present', 'Presente')}
                    </span>
                  ) : tab === 'unmarked' ? (
                    canCheckin ? (
                      <button
                        onClick={() => checkIn(m.event_id)}
                        disabled={marking === m.event_id}
                        className="flex-shrink-0 flex items-center gap-1.5 px-3 py-1.5 text-xs font-bold rounded-lg bg-[var(--color-teal)] text-white border-0 cursor-pointer hover:opacity-90 transition-all disabled:opacity-50 disabled:cursor-not-allowed"
                      >
                        <CheckCircle2 size={14} />
                        {marking === m.event_id ? t('comp.myMeetings.marking', 'Marcando...') : t('comp.myMeetings.markPresent', 'Marcar presença')}
                      </button>
                    ) : (
                      <span className="flex-shrink-0 text-[10px] text-[var(--text-muted)] flex items-center gap-1" title={withCheckinHours(t('comp.myMeetings.expiredHint', 'O prazo de {hours}h para auto check-in expirou. Solicite ao gestor.'))}>
                        <Lock size={11} /> {t('comp.myMeetings.expired', 'Prazo expirado — solicite ao gestor')}
                      </span>
                    )
                  ) : (
                    <span className="flex-shrink-0 text-[10px] text-[var(--text-muted)]">{t('comp.myMeetings.soon', 'Em breve')}</span>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
