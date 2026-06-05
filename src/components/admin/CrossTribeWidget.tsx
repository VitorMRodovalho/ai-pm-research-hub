import { useState, useEffect, useCallback } from 'react';

// p194 OPP-192.E/OPP-193.A: migrated to V4 exec_cross_initiative_comparison.
// V4 envelope: { initiatives: [...], kinds_present, generated_at }. We call with
// p_kind='research_tribe' to preserve V3 widget semantics (tribes-only).
// V4 lacks cards_in_progress (only exposes total/completed) — dropped from display
// to avoid misleading derivation (PM decision A, p194).
interface TribeRow {
  tribe_id: number;
  tribe_name: string;
  leader_name: string | null;
  member_count: number;
  attendance_rate: number | null;
  cards_done: number;
  cards_total: number;
  impact_hours: number | null;
  events_held: number;
  last_meeting: string | null;
}

// p195 LOW-194.B: exhaustive shape mirroring V4 RPC return.
// 6 fields (quadrant, members_inactive_30d, articles_submitted, total_xp,
// avg_xp, days_since_last_meeting) are not consumed by this compact widget
// but documented here so future readers see the full envelope at the
// type-as-documentation level.
interface V4InitiativeRow {
  initiative_id: string;
  initiative_kind: string;
  initiative_title: string;
  tribe_id: number | null;
  tribe_name: string | null;
  quadrant: string | null;
  leader: string | null;
  member_count: number;
  members_inactive_30d: number;
  total_cards: number;
  cards_completed: number;
  articles_submitted: number;
  attendance_rate: number;
  total_hours: number;
  meetings_count: number;
  total_xp: number;
  avg_xp: number;
  last_meeting_date: string | null;
  days_since_last_meeting: number | null;
}

interface Props { lang?: string; }

const L: Record<string, Record<string, string>> = {
  'pt-BR': { title: 'Comparativo de Tribos', tribe: 'Tribo', leader: 'Lider', members: 'Membros', attendance: 'Presenca', cards: 'Cards', hours: 'Horas', events: 'Eventos', lastMeeting: 'Ultima Reuniao', done: 'feitos', noData: 'Sem dados', daysAgo: 'd atras' },
  'en-US': { title: 'Tribe Comparison', tribe: 'Tribe', leader: 'Leader', members: 'Members', attendance: 'Attendance', cards: 'Cards', hours: 'Hours', events: 'Events', lastMeeting: 'Last Meeting', done: 'done', noData: 'No data', daysAgo: 'd ago' },
  'es-LATAM': { title: 'Comparativo de Tribus', tribe: 'Tribu', leader: 'Lider', members: 'Miembros', attendance: 'Asistencia', cards: 'Cards', hours: 'Horas', events: 'Eventos', lastMeeting: 'Ultima Reunion', done: 'hechos', noData: 'Sin datos', daysAgo: 'd atras' },
};

function getSb() {
  return typeof window !== 'undefined' ? (window as any).navGetSb?.() : null;
}

function daysAgo(dateStr: string | null): number | null {
  if (!dateStr) return null;
  return Math.floor((Date.now() - new Date(dateStr).getTime()) / 86400000);
}

function rateColor(rate: number | null): string {
  if (rate === null) return 'text-[var(--text-muted)]';
  if (rate >= 75) return 'text-green-600';
  if (rate >= 50) return 'text-amber-600';
  return 'text-red-600';
}

export default function CrossTribeWidget({ lang: propLang }: Props) {
  const langKey = propLang || (typeof document !== 'undefined' && document.documentElement.lang?.startsWith('en') ? 'en-US' : document.documentElement.lang?.startsWith('es') ? 'es-LATAM' : 'pt-BR');
  const t = L[langKey] || L['pt-BR'];
  const [data, setData] = useState<TribeRow[] | null>(null);

  const load = useCallback(async () => {
    const sb = getSb();
    if (!sb) { setTimeout(load, 400); return; }
    const m = (window as any).navGetMember?.();
    if (!m) { setTimeout(load, 400); return; }
    const { data: result } = await sb.rpc('exec_cross_initiative_comparison', { p_kind: 'research_tribe' });
    const initiatives: V4InitiativeRow[] = result?.initiatives ?? [];
    // V4 returns attendance_rate as 0-1 fraction; widget UI expects 0-100 (V3 parity).
    // tribe_id is guaranteed non-null when p_kind='research_tribe' (RPC filters via legacy_tribe_id join).
    // RPC guarantees: attendance_rate + total_hours both wrapped in COALESCE(..., 0)
    // server-side, so null-guards here would be dead branches. Council p194 LOW-194.A.
    const mapped: TribeRow[] = initiatives
      .filter((it) => it.tribe_id != null && it.tribe_name != null)
      .map((it) => ({
        tribe_id: it.tribe_id as number,
        tribe_name: it.tribe_name as string,
        leader_name: it.leader,
        member_count: it.member_count,
        // p277 PR4: attendance_rate is now canonical engagement (0..1 by construction via
        // get_attendance_engagement_summary), so the old Math.min(.,100) clamp for the
        // members×events >1.0 anomaly is no longer needed.
        attendance_rate: Math.round(it.attendance_rate * 100),
        cards_done: it.cards_completed,
        cards_total: it.total_cards,
        impact_hours: Math.round(it.total_hours),
        events_held: it.meetings_count,
        last_meeting: it.last_meeting_date,
      }));
    setData(mapped);
  }, []);

  useEffect(() => { load(); }, [load]);

  if (!data) return null;

  return (
    <div className="rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)] p-5 shadow-sm">
      <h3 className="text-sm font-extrabold text-navy mb-4 flex items-center gap-2">
        <span className="text-lg">📊</span> {t.title}
      </h3>
      <div className="overflow-x-auto">
        <table className="w-full text-xs border-collapse">
          <thead>
            <tr className="border-b border-[var(--border-subtle)] text-[var(--text-muted)]">
              <th className="text-left py-2 font-semibold">{t.tribe}</th>
              <th className="text-center py-2 font-semibold">{t.members}</th>
              <th className="text-center py-2 font-semibold">{t.attendance}</th>
              <th className="text-center py-2 font-semibold">{t.cards}</th>
              <th className="text-center py-2 font-semibold">{t.hours}</th>
              <th className="text-center py-2 font-semibold">{t.events}</th>
              <th className="text-center py-2 font-semibold">{t.lastMeeting}</th>
            </tr>
          </thead>
          <tbody>
            {data.map((tribe) => {
              const days = daysAgo(tribe.last_meeting);
              const stale = days !== null && days > 14;
              return (
                <tr key={tribe.tribe_id} className="border-b border-[var(--border-subtle)] hover:bg-[var(--surface-hover)] transition-colors">
                  <td className="py-2.5 text-left">
                    <div className="font-bold text-[var(--text-primary)]">T{tribe.tribe_id} {tribe.tribe_name}</div>
                    <div className="text-[10px] text-[var(--text-muted)]">{tribe.leader_name || '—'}</div>
                  </td>
                  <td className="py-2.5 text-center font-bold">{tribe.member_count}</td>
                  <td className={`py-2.5 text-center font-extrabold ${rateColor(tribe.attendance_rate)}`}>
                    {tribe.attendance_rate !== null ? `${tribe.attendance_rate}%` : '—'}
                  </td>
                  <td className="py-2.5 text-center">
                    <span className="text-green-600 font-bold">{tribe.cards_done}</span>
                    <span className="text-[var(--text-muted)]"> / </span>
                    <span>{tribe.cards_total}</span>
                  </td>
                  <td className="py-2.5 text-center font-bold">{tribe.impact_hours ?? 0}h</td>
                  <td className="py-2.5 text-center">{tribe.events_held}</td>
                  <td className={`py-2.5 text-center text-[10px] ${stale ? 'text-red-500 font-bold' : 'text-[var(--text-muted)]'}`}>
                    {days !== null ? `${days}${t.daysAgo}` : '—'}
                    {stale && ' ⚠️'}
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
