import { useEffect, useState, useMemo } from 'react';
import {
  BarChart, Bar, LineChart, Line, PieChart, Pie, Cell,
  XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
} from 'recharts';
import { usePageI18n } from '../../i18n/usePageI18n';

interface TribeGamificationTabProps {
  /** @deprecated Use initiativeId instead */
  tribeId?: number;
  initiativeId?: string;
}

interface Summary {
  total_xp: number;
  avg_xp: number;
  tribe_rank: number;
  cert_coverage: number;
  trail_completion: number;
}

interface Member {
  id: number;
  name: string;
  total_points: number;
  cycle_points: number;
  attendance_points: number;
  cert_points: number;
  badge_points: number;
  learning_points: number;
  credly_badge_count: number;
  has_cpmai: boolean;
  trail_progress: number;
}

interface TribeRankEntry {
  tribe_id: number;
  tribe_name: string;
  total_xp: number;
}

interface MonthlyTrend {
  month: string;
  xp: number;
}

interface GamificationData {
  summary: Summary;
  members: Member[];
  tribe_ranking: TribeRankEntry[];
  monthly_trend: MonthlyTrend[];
}

type SortKey = 'total_points' | 'cycle_points' | 'attendance_points' | 'cert_points'
  | 'badge_points' | 'learning_points' | 'name';

const CHART_COLORS = ['#00799E', '#FF610F', '#4F17A8', '#10B981', '#F59E0B', '#EF4444'];

export default function TribeGamificationTab({ tribeId, initiativeId }: TribeGamificationTabProps) {
  const t = usePageI18n();
  const [data, setData] = useState<GamificationData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [sortKey, setSortKey] = useState<SortKey>('total_points');
  const [sortAsc, setSortAsc] = useState(false);

  useEffect(() => {
    const load = async () => {
      const sb = (window as any).navGetSb?.();
      if (!sb) { setTimeout(load, 300); return; }

      try {
        const { data: result, error: err } = initiativeId
          ? await sb.rpc('get_initiative_gamification', { p_initiative_id: initiativeId })
          : await sb.rpc('get_tribe_gamification', { p_tribe_id: tribeId });
        if (err) throw err;
        setData(result as GamificationData);
      } catch (e: any) {
        setError(e?.message || t('comp.gamification.loadError', 'Failed to load gamification data'));
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [tribeId, initiativeId]);

  const sortedMembers = useMemo(() => {
    if (!data?.members) return [];
    return [...data.members].sort((a, b) => {
      if (sortKey === 'name') {
        const cmp = (a.name || '').localeCompare(b.name || '');
        return sortAsc ? cmp : -cmp;
      }
      const diff = (a[sortKey] || 0) - (b[sortKey] || 0);
      return sortAsc ? diff : -diff;
    });
  }, [data?.members, sortKey, sortAsc]);

  const xpDistribution = useMemo(() => {
    if (!data?.members) return [];
    const totals = data.members.reduce(
      (acc, m) => ({
        cycle: acc.cycle + (m.cycle_points || 0),
        attendance: acc.attendance + (m.attendance_points || 0),
        certs: acc.certs + (m.cert_points || 0),
        badges: acc.badges + (m.badge_points || 0),
        learning: acc.learning + (m.learning_points || 0),
      }),
      { cycle: 0, attendance: 0, certs: 0, badges: 0, learning: 0 },
    );
    return [
      { name: t('comp.gamification.cycle', 'Ciclo'), value: totals.cycle },
      { name: t('comp.gamification.attendance', 'Presenca'), value: totals.attendance },
      { name: t('comp.gamification.certs', 'Certificacoes'), value: totals.certs },
      { name: t('comp.gamification.badges', 'Badges'), value: totals.badges },
      { name: t('comp.gamification.learning', 'Aprendizado'), value: totals.learning },
    ].filter(d => d.value > 0);
  }, [data?.members]);

  if (loading) {
    return (
      <div className="text-center py-12 text-[var(--text-muted)]">
        {t('comp.gamification.loading', 'Carregando gamificacao...')}
      </div>
    );
  }

  if (error) {
    return (
      <div className="text-center py-12 text-red-500 dark:text-red-400">
        {error}
      </div>
    );
  }

  if (!data) return null;

  const { summary = {} as any, tribe_ranking, monthly_trend } = data as any;

  const handleSort = (key: SortKey) => {
    if (sortKey === key) {
      setSortAsc(!sortAsc);
    } else {
      setSortKey(key);
      setSortAsc(false);
    }
  };

  const rankingData = (tribe_ranking || []).map(r => ({
    ...r,
    fill: r.tribe_id === tribeId ? '#00799E' : '#94A3B8',
  }));

  return (
    <div className="space-y-6">
      {/* KPI Cards */}
      <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
        <KpiCard
          label={t('comp.gamification.totalXp', 'XP Total')}
          value={summary.total_xp ?? 0}
        />
        <KpiCard
          label={t('comp.gamification.avgXp', 'XP Medio')}
          value={summary.avg_xp ?? 0}
        />
        <KpiCard
          label={t('comp.gamification.tribeRank', 'Ranking')}
          value={`#${summary.tribe_rank ?? '—'}`}
        />
        <KpiCard
          label={t('comp.gamification.certCoverage', 'Cobertura Cert.')}
          value={`${Math.round((summary.cert_coverage ?? 0) * 100)}%`}
        />
        <KpiCard
          label={t('comp.gamification.trailCompletion', 'Trilha Completa')}
          value={`${Math.round((summary.trail_completion ?? 0) * 100)}%`}
        />
      </div>

      {/* Tribe Ranking - Horizontal Bar Chart */}
      {rankingData.length > 0 && (
        <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-xl p-5">
          <h3 className="text-sm font-bold text-navy mb-3">
            {t('comp.gamification.tribeRanking', 'Ranking de Tribos')}
          </h3>
          <ResponsiveContainer width="100%" height={Math.max(200, rankingData.length * 36)}>
            <BarChart data={rankingData} layout="vertical">
              <CartesianGrid strokeDasharray="3 3" stroke="var(--border-subtle)" />
              <XAxis type="number" tick={{ fontSize: 11 }} />
              <YAxis
                dataKey="tribe_name"
                type="category"
                width={120}
                tick={{ fontSize: 11 }}
              />
              <Tooltip
                contentStyle={{
                  backgroundColor: 'var(--surface-card)',
                  border: '1px solid var(--border-default)',
                  borderRadius: '8px',
                  color: 'var(--text-primary)',
                }}
              />
              <Bar dataKey="total_xp" name="XP">
                {rankingData.map((entry, i) => (
                  <Cell key={i} fill={entry.fill} />
                ))}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </div>
      )}

      {/* Members Table */}
      <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-xl p-5">
        <h3 className="text-sm font-bold text-navy mb-3">
          {t('comp.gamification.membersTable', 'Membros')}
        </h3>
        <div className="overflow-x-auto">
          <table className="w-full text-[.75rem]">
            <thead>
              <tr className="bg-[var(--surface-section-cool)]">
                <Th label="#" />
                <Th label={t('comp.gamification.name', 'Nome')} sortKey="name" currentSort={sortKey} asc={sortAsc} onSort={handleSort} />
                <Th label={t('comp.gamification.totalXp', 'XP Total')} sortKey="total_points" currentSort={sortKey} asc={sortAsc} onSort={handleSort} />
                <Th label={t('comp.gamification.cycleXp', 'Ciclo XP')} sortKey="cycle_points" currentSort={sortKey} asc={sortAsc} onSort={handleSort} />
                <Th label={t('comp.gamification.attendanceCol', 'Presenca')} sortKey="attendance_points" currentSort={sortKey} asc={sortAsc} onSort={handleSort} />
                <Th label={t('comp.gamification.certsCol', 'Certs')} sortKey="cert_points" currentSort={sortKey} asc={sortAsc} onSort={handleSort} />
                <Th label={t('comp.gamification.badgesCol', 'Badges')} sortKey="badge_points" currentSort={sortKey} asc={sortAsc} onSort={handleSort} />
                <Th label={t('comp.gamification.learningCol', 'Aprendizado')} sortKey="learning_points" currentSort={sortKey} asc={sortAsc} onSort={handleSort} />
                <Th label="CPMAI" />
                <Th label={t('comp.gamification.trail', 'Trilha')} />
              </tr>
            </thead>
            <tbody>
              {sortedMembers.map((m, i) => (
                <tr
                  key={m.id}
                  className="border-t border-[var(--border-subtle)] hover:bg-[var(--surface-hover)]"
                >
                  <td className="px-3 py-2.5 text-center text-[var(--text-secondary)] font-bold">
                    {i + 1}
                  </td>
                  <td className="px-3 py-2.5 font-semibold text-navy whitespace-nowrap">
                    {m.name}
                  </td>
                  <td className="px-3 py-2.5 text-center font-bold">{m.total_points}</td>
                  <td className="px-3 py-2.5 text-center">{m.cycle_points}</td>
                  <td className="px-3 py-2.5 text-center">{m.attendance_points}</td>
                  <td className="px-3 py-2.5 text-center">{m.cert_points}</td>
                  <td className="px-3 py-2.5 text-center">{m.badge_points}</td>
                  <td className="px-3 py-2.5 text-center">{m.learning_points}</td>
                  <td className="px-3 py-2.5 text-center">
                    {m.has_cpmai ? (
                      <span className="text-emerald-600 dark:text-emerald-400 font-bold">&#x2705;</span>
                    ) : (
                      <span className="text-red-400 dark:text-red-500">&#x274C;</span>
                    )}
                  </td>
                  <td className="px-3 py-2.5 text-center font-medium text-[var(--text-secondary)]">
                    {m.trail_progress}/7
                  </td>
                </tr>
              ))}
              {sortedMembers.length === 0 && (
                <tr>
                  <td colSpan={10} className="px-3 py-6 text-center text-[var(--text-muted)]">
                    {t('comp.gamification.noMembers', 'Nenhum membro encontrado')}
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Charts row: Pie + Line */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* XP Distribution Pie */}
        <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-xl p-5">
          <h3 className="text-sm font-bold text-navy mb-3">
            {t('comp.gamification.xpDistribution', 'Distribuicao de XP')}
          </h3>
          {xpDistribution.length > 0 ? (
            <ResponsiveContainer width="100%" height={240}>
              <PieChart>
                <Pie
                  data={xpDistribution}
                  dataKey="value"
                  nameKey="name"
                  cx="50%"
                  cy="50%"
                  outerRadius={80}
                  label={({ name, percent }) => `${name} ${Math.round(percent * 100)}%`}
                >
                  {xpDistribution.map((_, i) => (
                    <Cell key={i} fill={CHART_COLORS[i % CHART_COLORS.length]} />
                  ))}
                </Pie>
                <Tooltip
                  contentStyle={{
                    backgroundColor: 'var(--surface-card)',
                    border: '1px solid var(--border-default)',
                    borderRadius: '8px',
                    color: 'var(--text-primary)',
                  }}
                />
              </PieChart>
            </ResponsiveContainer>
          ) : (
            <p className="text-sm text-[var(--text-muted)]">
              {t('comp.gamification.noData', 'Sem dados')}
            </p>
          )}
        </div>

        {/* Monthly XP Trend Line */}
        <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-xl p-5">
          <h3 className="text-sm font-bold text-navy mb-3">
            {t('comp.gamification.monthlyTrend', 'Tendencia Mensal de XP')}
          </h3>
          {monthly_trend && monthly_trend.length > 0 ? (
            <ResponsiveContainer width="100%" height={240}>
              <LineChart data={monthly_trend}>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--border-subtle)" />
                <XAxis dataKey="month" tick={{ fontSize: 10 }} />
                <YAxis tick={{ fontSize: 11 }} />
                <Tooltip
                  contentStyle={{
                    backgroundColor: 'var(--surface-card)',
                    border: '1px solid var(--border-default)',
                    borderRadius: '8px',
                    color: 'var(--text-primary)',
                  }}
                />
                <Line
                  type="monotone"
                  dataKey="xp"
                  stroke="#00799E"
                  strokeWidth={2}
                  dot={{ fill: '#00799E', r: 4 }}
                  name="XP"
                />
              </LineChart>
            </ResponsiveContainer>
          ) : (
            <p className="text-sm text-[var(--text-muted)]">
              {t('comp.gamification.noData', 'Sem dados')}
            </p>
          )}
        </div>
      </div>
    </div>
  );
}

// ─── KPI Card ───
function KpiCard({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-xl p-4 text-center">
      <div className="text-2xl font-extrabold text-navy">{value}</div>
      <div className="text-[.72rem] font-bold text-[var(--text-secondary)] mt-1">{label}</div>
    </div>
  );
}

// ─── Sortable Table Header ───
function Th({
  label,
  sortKey,
  currentSort,
  asc,
  onSort,
}: {
  label: string;
  sortKey?: SortKey;
  currentSort?: SortKey;
  asc?: boolean;
  onSort?: (key: SortKey) => void;
}) {
  const isSorted = sortKey && currentSort === sortKey;
  const arrow = isSorted ? (asc ? ' \u25B2' : ' \u25BC') : '';

  return (
    <th
      className={`text-center px-3 py-2.5 font-bold text-[var(--text-secondary)] whitespace-nowrap ${
        sortKey ? 'cursor-pointer select-none hover:text-navy' : ''
      }`}
      onClick={() => sortKey && onSort?.(sortKey)}
    >
      {label}{arrow}
    </th>
  );
}
