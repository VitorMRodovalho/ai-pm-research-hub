import { useEffect, useState, useMemo } from 'react';
import { BarChart, Bar, LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer, Cell } from 'recharts';

interface TribeMetrics {
  tribe_id: number;
  tribe_name: string;
  quadrant: string;
  leader: string;
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

interface AlertItem {
  severity: 'high' | 'medium' | 'low';
  type: string;
  tribe_name?: string;
  member_name?: string;
  message: string;
}

interface AlertsData {
  alerts: AlertItem[];
  total: number;
  by_severity: { high: number; medium: number; low: number };
}

type SortKey = 'tribe_name' | 'member_count' | 'attendance_rate' | 'cards_completed' | 'total_xp' | 'total_hours' | 'days_since_last_meeting';
type RankingMetric = 'attendance' | 'production' | 'xp' | 'hours';

const TRIBE_COLORS = ['#0d9488', '#2563eb', '#7c3aed', '#dc2626', '#ea580c', '#0891b2', '#4f46e5', '#059669'];
const SEVERITY_COLORS = { high: '#ef4444', medium: '#f59e0b', low: '#3b82f6' };
const SEVERITY_ICONS = { high: '🔴', medium: '⚠️', low: 'ℹ️' };

function getCellColor(value: number, sorted: number[], isPercent = false): string {
  const rank = sorted.indexOf(value);
  if (rank < 3) return '#dcfce7'; // green top 3
  if (rank >= sorted.length - 2) return '#fef2f2'; // red bottom 2
  return '#fffbeb'; // amber middle
}

export default function CrossTribeIsland() {
  const [tribes, setTribes] = useState<TribeMetrics[]>([]);
  const [alerts, setAlerts] = useState<AlertsData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [sortBy, setSortBy] = useState<SortKey>('attendance_rate');
  const [sortAsc, setSortAsc] = useState(false);
  const [alertsExpanded, setAlertsExpanded] = useState(false);
  const [trendMetric, setTrendMetric] = useState<RankingMetric>('attendance');

  useEffect(() => {
    let cancelled = false;
    const load = async () => {
      const sb = (window as any).navGetSb?.();
      if (!sb) { setTimeout(load, 300); return; }
      try {
        const [compRes, alertRes] = await Promise.all([
          sb.rpc('exec_cross_tribe_comparison'),
          sb.rpc('detect_operational_alerts'),
        ]);
        if (!cancelled) {
          if (compRes.error) throw new Error(compRes.error.message);
          setTribes(compRes.data?.tribes || []);
          setAlerts(alertRes.data || null);
        }
      } catch (e: any) {
        if (!cancelled) setError(e.message);
      }
      if (!cancelled) setLoading(false);
    };
    load();
    return () => { cancelled = true; };
  }, []);

  const sortedTribes = useMemo(() => {
    const copy = [...tribes];
    copy.sort((a, b) => {
      const av = a[sortBy] ?? 0;
      const bv = b[sortBy] ?? 0;
      if (typeof av === 'string' && typeof bv === 'string') return sortAsc ? av.localeCompare(bv) : bv.localeCompare(av);
      return sortAsc ? (av as number) - (bv as number) : (bv as number) - (av as number);
    });
    return copy;
  }, [tribes, sortBy, sortAsc]);

  const rankings = useMemo(() => {
    const byAttendance = [...tribes].sort((a, b) => b.attendance_rate - a.attendance_rate);
    const byProduction = [...tribes].sort((a, b) => b.cards_completed - a.cards_completed);
    const byXp = [...tribes].sort((a, b) => b.total_xp - a.total_xp);
    const byHours = [...tribes].sort((a, b) => b.total_hours - a.total_hours);
    return { attendance: byAttendance, production: byProduction, xp: byXp, hours: byHours };
  }, [tribes]);

  const handleSort = (key: SortKey) => {
    if (sortBy === key) setSortAsc(!sortAsc);
    else { setSortBy(key); setSortAsc(false); }
  };

  const SortHeader = ({ label, sKey }: { label: string; sKey: SortKey }) => (
    <th className="px-3 py-2 text-left text-xs font-bold uppercase tracking-wide text-[var(--text-secondary)] cursor-pointer hover:text-[var(--text-primary)] select-none whitespace-nowrap"
        onClick={() => handleSort(sKey)}>
      {label} {sortBy === sKey ? (sortAsc ? '↑' : '↓') : ''}
    </th>
  );

  if (loading) return <div className="text-center py-20 text-[var(--text-muted)]">Carregando comparativo...</div>;
  if (error) return <div className="text-center py-20 text-red-500">{error}</div>;

  const rankingConfig: Record<RankingMetric, { label: string; key: keyof TribeMetrics; suffix: string }> = {
    attendance: { label: 'Presença', key: 'attendance_rate', suffix: '%' },
    production: { label: 'Produção', key: 'cards_completed', suffix: '' },
    xp: { label: 'XP Total', key: 'total_xp', suffix: '' },
    hours: { label: 'Horas', key: 'total_hours', suffix: 'h' },
  };

  return (
    <div className="space-y-8">
      {/* Alerts Banner */}
      {alerts && alerts.total > 0 && (
        <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-4">
          <button onClick={() => setAlertsExpanded(!alertsExpanded)}
                  className="w-full flex items-center justify-between bg-transparent border-0 cursor-pointer p-0">
            <div className="flex items-center gap-3">
              <span className="text-lg">🚨</span>
              <span className="font-bold text-sm text-[var(--text-primary)]">Alertas Operacionais</span>
              <div className="flex gap-2">
                {alerts.by_severity.high > 0 && <span className="text-xs font-bold px-2 py-0.5 rounded-full bg-red-100 text-red-700">{SEVERITY_ICONS.high} {alerts.by_severity.high}</span>}
                {alerts.by_severity.medium > 0 && <span className="text-xs font-bold px-2 py-0.5 rounded-full bg-amber-100 text-amber-700">{SEVERITY_ICONS.medium} {alerts.by_severity.medium}</span>}
                {alerts.by_severity.low > 0 && <span className="text-xs font-bold px-2 py-0.5 rounded-full bg-blue-100 text-blue-700">{SEVERITY_ICONS.low} {alerts.by_severity.low}</span>}
              </div>
            </div>
            <span className="text-[var(--text-muted)] text-sm">{alertsExpanded ? '▲' : '▼'}</span>
          </button>
          {alertsExpanded && (
            <div className="mt-3 space-y-2 border-t border-[var(--border-default)] pt-3">
              {alerts.alerts.map((a, i) => (
                <div key={i} className="flex items-start gap-2 text-sm p-2 rounded-lg" style={{ background: SEVERITY_COLORS[a.severity] + '10' }}>
                  <span>{SEVERITY_ICONS[a.severity]}</span>
                  <span className="text-[var(--text-primary)]">{a.message}</span>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* Rankings — 4 bar charts */}
      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-4">
        {(['attendance', 'production', 'xp', 'hours'] as RankingMetric[]).map(metric => {
          const cfg = rankingConfig[metric];
          const ranked = rankings[metric];
          const maxVal = Math.max(...ranked.map(t => Number(t[cfg.key]) || 0), 1);
          return (
            <div key={metric} className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-xl p-4">
              <h3 className="text-xs font-bold uppercase tracking-wide text-[var(--text-secondary)] mb-3">{cfg.label}</h3>
              <div className="space-y-2">
                {ranked.map((t, i) => {
                  const val = Number(t[cfg.key]) || 0;
                  const pct = (val / maxVal) * 100;
                  const display = metric === 'attendance' ? `${Math.round(val * 100)}%` : `${Math.round(val)}${cfg.suffix}`;
                  return (
                    <div key={t.tribe_id} className="flex items-center gap-2">
                      <span className="text-[11px] font-bold w-10 text-right text-[var(--text-secondary)]">T{String(t.tribe_id).padStart(2, '0')}</span>
                      <div className="flex-1 h-5 rounded bg-[var(--border-subtle)] overflow-hidden">
                        <div className="h-full rounded transition-all" style={{ width: `${pct}%`, background: TRIBE_COLORS[i % 8] }} />
                      </div>
                      <span className="text-[11px] font-bold w-12 text-[var(--text-primary)]">{display}</span>
                    </div>
                  );
                })}
              </div>
            </div>
          );
        })}
      </div>

      {/* Comparison Table */}
      <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-[var(--surface-hover)]">
              <tr>
                <SortHeader label="Tribo" sKey="tribe_name" />
                <SortHeader label="Membros" sKey="member_count" />
                <SortHeader label="Presença" sKey="attendance_rate" />
                <SortHeader label="Cards" sKey="cards_completed" />
                <SortHeader label="XP" sKey="total_xp" />
                <SortHeader label="Horas" sKey="total_hours" />
                <SortHeader label="Última Reunião" sKey="days_since_last_meeting" />
              </tr>
            </thead>
            <tbody>
              {sortedTribes.map((t, i) => (
                <tr key={t.tribe_id} className="border-t border-[var(--border-subtle)] hover:bg-[var(--surface-hover)]">
                  <td className="px-3 py-2.5">
                    <a href={`/admin/tribe/${t.tribe_id}`} className="no-underline hover:underline">
                      <span className="font-bold text-xs mr-1" style={{ color: TRIBE_COLORS[i % 8] }}>T{String(t.tribe_id).padStart(2, '0')}</span>
                      <span className="font-semibold text-[var(--text-primary)]">{t.tribe_name}</span>
                    </a>
                    <div className="text-[11px] text-[var(--text-muted)]">{t.leader}</div>
                  </td>
                  <td className="px-3 py-2.5 text-center">
                    <span className="font-bold">{t.member_count}</span>
                    {t.members_inactive_30d > 0 && <span className="text-red-500 text-xs ml-1">({t.members_inactive_30d} inat.)</span>}
                  </td>
                  <td className="px-3 py-2.5 text-center font-bold">{Math.round(t.attendance_rate * 100)}%</td>
                  <td className="px-3 py-2.5 text-center">
                    <span className="font-bold">{t.cards_completed}</span>
                    <span className="text-[var(--text-muted)]">/{t.total_cards}</span>
                  </td>
                  <td className="px-3 py-2.5 text-center font-bold">{t.total_xp}</td>
                  <td className="px-3 py-2.5 text-center font-bold">{Math.round(t.total_hours)}h</td>
                  <td className="px-3 py-2.5 text-center">
                    {t.days_since_last_meeting != null ? (
                      <span className={`font-bold ${t.days_since_last_meeting > 14 ? 'text-red-500' : t.days_since_last_meeting > 7 ? 'text-amber-500' : 'text-green-600'}`}>
                        {t.days_since_last_meeting}d
                      </span>
                    ) : <span className="text-[var(--text-muted)]">—</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Trend Overlay Chart */}
      <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="font-bold text-[var(--text-primary)]">Comparativo Visual</h3>
          <div className="flex gap-2">
            {(['attendance', 'production', 'xp', 'hours'] as RankingMetric[]).map(m => (
              <button key={m} onClick={() => setTrendMetric(m)}
                      className={`px-3 py-1 rounded-lg text-xs font-semibold border-0 cursor-pointer transition-all ${
                        trendMetric === m ? 'bg-navy text-white' : 'bg-[var(--surface-hover)] text-[var(--text-secondary)]'
                      }`}>
                {rankingConfig[m].label}
              </button>
            ))}
          </div>
        </div>
        <ResponsiveContainer width="100%" height={300}>
          <BarChart data={rankings[trendMetric].map((t, i) => ({
            name: `T${String(t.tribe_id).padStart(2, '0')}`,
            value: trendMetric === 'attendance' ? Math.round(Number(t[rankingConfig[trendMetric].key]) * 100) : Number(t[rankingConfig[trendMetric].key]),
            fill: TRIBE_COLORS[tribes.findIndex(tr => tr.tribe_id === t.tribe_id) % 8],
          }))}>
            <CartesianGrid strokeDasharray="3 3" stroke="var(--border-subtle)" />
            <XAxis dataKey="name" tick={{ fontSize: 12 }} />
            <YAxis tick={{ fontSize: 12 }} />
            <Tooltip />
            <Bar dataKey="value" radius={[4, 4, 0, 0]}>
              {rankings[trendMetric].map((t, i) => (
                <Cell key={t.tribe_id} fill={TRIBE_COLORS[tribes.findIndex(tr => tr.tribe_id === t.tribe_id) % 8]} />
              ))}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
