import { useState, useEffect, useCallback } from 'react';

interface TribeRow {
  tribe_id: number;
  tribe_name: string;
  leader_name: string | null;
  member_count: number;
  attendance_rate: number | null;
  cards_done: number;
  cards_in_progress: number;
  cards_total: number;
  impact_hours: number | null;
  events_held: number;
  last_meeting: string | null;
}

interface Props { lang?: string; }

const L: Record<string, Record<string, string>> = {
  'pt-BR': { title: 'Comparativo de Tribos', tribe: 'Tribo', leader: 'Lider', members: 'Membros', attendance: 'Presenca', cards: 'Cards', hours: 'Horas', events: 'Eventos', lastMeeting: 'Ultima Reuniao', done: 'feitos', inProg: 'andamento', noData: 'Sem dados', daysAgo: 'd atras' },
  'en-US': { title: 'Tribe Comparison', tribe: 'Tribe', leader: 'Leader', members: 'Members', attendance: 'Attendance', cards: 'Cards', hours: 'Hours', events: 'Events', lastMeeting: 'Last Meeting', done: 'done', inProg: 'in progress', noData: 'No data', daysAgo: 'd ago' },
  'es-LATAM': { title: 'Comparativo de Tribus', tribe: 'Tribu', leader: 'Lider', members: 'Miembros', attendance: 'Asistencia', cards: 'Cards', hours: 'Horas', events: 'Eventos', lastMeeting: 'Ultima Reunion', done: 'hechos', inProg: 'progreso', noData: 'Sin datos', daysAgo: 'd atras' },
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
    const { data: result } = await sb.rpc('get_cross_tribe_comparison');
    if (Array.isArray(result)) setData(result);
    else if (result && !result.error) setData(result);
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
                    <span className="text-amber-600">{tribe.cards_in_progress}</span>
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
