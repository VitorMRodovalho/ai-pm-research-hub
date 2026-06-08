import { useEffect, useState, useMemo, Fragment } from 'react';
import {
  BarChart, Bar, LineChart, Line, PieChart, Pie, Cell,
  XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
} from 'recharts';
import { usePageI18n } from '../../i18n/usePageI18n';
import { TOTAL_COURSES } from '../../data/trail';

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

// #425: per-course trail status for the per-member coaching drill-down.
interface TrailCourse {
  course_id: number;
  code: string;
  name: string;
  tier: string;
  status: 'completed' | 'in_progress' | 'missing';
}

interface Member {
  id: string; // #425: members.id is uuid (was typed number)
  name: string;
  total_points: number;
  cycle_points: number;
  attendance_points: number;
  cert_points: number;
  badge_points: number;
  learning_points: number;
  producao_points: number;
  curadoria_points: number;
  champions_points: number;
  credly_badge_count: number;
  has_cpmai: boolean;
  trail_progress: number;
  // #425 coaching primitives
  attendance_rate: number | null;
  current_streak: number;
  longest_streak: number;
  active_cycles: number;
  last_activity: string | null;
  trail_courses: TrailCourse[];
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

type SortKey = 'total_points' | 'cycle_points' | 'attendance_points' | 'attendance_rate'
  | 'current_streak' | 'cert_points' | 'badge_points' | 'learning_points'
  | 'producao_points' | 'curadoria_points' | 'champions_points' | 'name';

const CHART_COLORS = ['#00799E', '#FF610F', '#4F17A8', '#10B981', '#F59E0B', '#EF4444', '#0EA5E9'];

// Columns spanned by the drill-down panel row (keep in sync with the header/body).
// #577: progressive disclosure — the table renders in two widths. COMPACT (default)
// shows only the high-signal columns; FULL adds the 7 raw-pillar point columns when
// the "show points breakdown" toggle is on. colSpan must follow the active width.
const TABLE_COLS_FULL = 16;
const TABLE_COLS_COMPACT = 9;

// #577: the sort keys that only exist as columns when the breakdown is shown.
// Collapsing the breakdown while sorted by one of these would leave the table
// sorted by an invisible column with no aria-sort indicator — so we reset the
// sort to total_points on collapse (see toggleBreakdown). FULL = COMPACT + these.
const BREAKDOWN_SORT_KEYS: SortKey[] = [
  'attendance_points', 'cert_points', 'badge_points',
  'learning_points', 'producao_points', 'curadoria_points', 'champions_points',
];

export default function TribeGamificationTab({ tribeId, initiativeId }: TribeGamificationTabProps) {
  const t = usePageI18n();
  const [data, setData] = useState<GamificationData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [sortKey, setSortKey] = useState<SortKey>('total_points');
  const [sortAsc, setSortAsc] = useState(false);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  // #577: progressive disclosure — the 7 raw-pillar point columns are hidden by
  // default so the summary scans on high-signal columns (XP, cycle, streak, presence%,
  // CPMAI, trail). Leaders who curate by a specific pillar reveal them inline via the
  // toggle. Default collapsed to keep the median (mobile) scan clean; in-memory by
  // design — no persistence (stateless component, default-scannable). Revisit if
  // analytics show power users consistently re-expand on landing (follow-up issue).
  const [showBreakdown, setShowBreakdown] = useState(false);

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

  // #425 a11y: move focus to the drill-down panel when a member row is expanded,
  // so a keyboard/screen-reader user lands on the coaching content instead of
  // tabbing through every remaining row's expand button.
  useEffect(() => {
    if (expandedId) {
      document.getElementById(`gamif-detail-${expandedId}`)?.focus();
    }
  }, [expandedId]);

  const sortedMembers = useMemo(() => {
    if (!data?.members) return [];
    return [...data.members].sort((a, b) => {
      if (sortKey === 'name') {
        const cmp = (a.name || '').localeCompare(b.name || '');
        return sortAsc ? cmp : -cmp;
      }
      const diff = ((a[sortKey] as number) || 0) - ((b[sortKey] as number) || 0);
      return sortAsc ? diff : -diff;
    });
  }, [data?.members, sortKey, sortAsc]);

  const xpDistribution = useMemo(() => {
    if (!data?.members) return [];
    const totals = data.members.reduce(
      (acc, m) => ({
        attendance: acc.attendance + (m.attendance_points || 0),
        certs: acc.certs + (m.cert_points || 0),
        badges: acc.badges + (m.badge_points || 0),
        learning: acc.learning + (m.learning_points || 0),
        producao: acc.producao + (m.producao_points || 0),
        curadoria: acc.curadoria + (m.curadoria_points || 0),
        champions: acc.champions + (m.champions_points || 0),
      }),
      { attendance: 0, certs: 0, badges: 0, learning: 0, producao: 0, curadoria: 0, champions: 0 },
    );
    return [
      { name: t('comp.gamification.attendance', 'Presenca'), value: totals.attendance },
      { name: t('comp.gamification.certs', 'Certificacoes'), value: totals.certs },
      { name: t('comp.gamification.badges', 'Badges'), value: totals.badges },
      { name: t('comp.gamification.learning', 'Aprendizado'), value: totals.learning },
      { name: t('comp.gamification.producao', 'Producao'), value: totals.producao },
      { name: t('comp.gamification.curadoria', 'Curadoria'), value: totals.curadoria },
      { name: t('comp.gamification.champions', 'Champions'), value: totals.champions },
    ].filter(d => d.value > 0);
    // p124: include t in deps so the memo recomputes when usePageI18n's
    // dict updates after the post-mount useEffect. Without this, the pie
    // chart slice labels stay on the JS fallback (PT) for the whole session.
  }, [data?.members, t]);

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

  const toggleExpand = (id: string) => setExpandedId(prev => (prev === id ? null : id));

  // #577: active table width — drives every colSpan below. Keep in sync with the
  // count of always-on columns (COMPACT) + the 7 gated point columns (FULL).
  const visibleCols = showBreakdown ? TABLE_COLS_FULL : TABLE_COLS_COMPACT;

  // #577: toggle the breakdown. When collapsing while sorted by a now-hidden pillar
  // column, reset the sort to total_points so the table never sits in a sort order
  // whose column (and aria-sort indicator) is no longer visible.
  const toggleBreakdown = () => {
    const next = !showBreakdown;
    // #591b enabler: instrument the toggle so a future session can measure the
    // expand-on-landing cohort — the gate for persisting the breakdown across
    // mounts (#591 follow-up). Best-effort, never blocks the UI. No persistence
    // is shipped here: as of this change there were 0 toggle interactions in the
    // trailing 30d (the toggle is new), so there is no cohort to gate on yet.
    try {
      (window as any).posthog?.capture?.('gamification_breakdown_toggled', {
        expanded: next,
        // council (gp-leader): carry tribe/initiative so a future session can
        // segment the expand-on-landing cohort by surface before deciding persistence.
        tribe_id: tribeId ?? null,
        initiative_id: initiativeId ?? null,
      });
    } catch { /* analytics is best-effort */ }
    if (!next && BREAKDOWN_SORT_KEYS.includes(sortKey)) {
      setSortKey('total_points');
      setSortAsc(false);
    }
    setShowBreakdown(next);
  };

  // p124 phase 5: derive 2-letter lang code to pull localized tribe_name from
  // tribe_name_i18n jsonb (added in phase 1). Falls back to canonical PT name.
  const _langCode: 'pt' | 'en' | 'es' = (() => {
    const p = (typeof window !== 'undefined' && (window as any).__LANG_PREFIX) || '';
    return p === '/en' ? 'en' : p === '/es' ? 'es' : 'pt';
  })();
  const rankingData = (tribe_ranking || []).map((r: any) => ({
    ...r,
    tribe_name: r.tribe_name_i18n?.[_langCode] || r.tribe_name,
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
        <div className="flex flex-wrap items-center justify-between gap-2 mb-3">
          <h3 id="gamif-members-table-label" className="text-sm font-bold text-navy">
            {t('comp.gamification.membersTable', 'Membros')}
          </h3>
          <button
            type="button"
            onClick={toggleBreakdown}
            aria-pressed={showBreakdown}
            aria-controls="gamif-members-table"
            className="inline-flex items-center gap-1.5 text-[.72rem] font-semibold rounded-md border border-[var(--border-default)] px-2.5 py-1 text-[var(--text-secondary)] hover:text-navy hover:bg-[var(--surface-hover)] focus:outline-none focus:ring-2 focus:ring-[#00799E] forced-colors:focus:outline forced-colors:focus:outline-2 forced-colors:focus:outline-offset-2 whitespace-nowrap"
          >
            {/* columns/expand icon — a pre-attentive cue that hidden columns exist (#577) */}
            <span aria-hidden="true">{showBreakdown ? '⊟' : '⊞'}</span>
            {showBreakdown
              ? t('comp.gamification.hideBreakdown', 'Ocultar detalhamento de pontos')
              : `${t('comp.gamification.showBreakdown', 'Mostrar detalhamento de pontos')} (+${BREAKDOWN_SORT_KEYS.length})`}
          </button>
        </div>
        <div className="overflow-x-auto">
          <table id="gamif-members-table" aria-labelledby="gamif-members-table-label" className="w-full text-[.75rem]">
            <thead>
              <tr className="bg-[var(--surface-section-cool)]">
                <Th label="#" />
                <Th label={t('comp.gamification.name', 'Nome')} sortKey="name" currentSort={sortKey} asc={sortAsc} onSort={handleSort} className="sticky left-0 z-20 bg-[var(--surface-section-cool)]" />
                <Th label={t('comp.gamification.totalXp', 'XP Total')} sortKey="total_points" currentSort={sortKey} asc={sortAsc} onSort={handleSort} />
                <Th label={t('comp.gamification.cycleXp', 'Ciclo XP')} sortKey="cycle_points" currentSort={sortKey} asc={sortAsc} onSort={handleSort} />
                <Th label={t('comp.gamification.streakCol', 'Seq.')} sortKey="current_streak" currentSort={sortKey} asc={sortAsc} onSort={handleSort} />
                {showBreakdown && (
                  <Th label={t('comp.gamification.attendanceCol', 'Presenca')} sortKey="attendance_points" currentSort={sortKey} asc={sortAsc} onSort={handleSort} />
                )}
                <Th label={t('comp.gamification.attendanceRateCol', 'Pres. %')} sortKey="attendance_rate" currentSort={sortKey} asc={sortAsc} onSort={handleSort} />
                {showBreakdown && (
                  <>
                    <Th label={t('comp.gamification.certsCol', 'Certs')} sortKey="cert_points" currentSort={sortKey} asc={sortAsc} onSort={handleSort} />
                    <Th label={t('comp.gamification.badgesCol', 'Badges')} sortKey="badge_points" currentSort={sortKey} asc={sortAsc} onSort={handleSort} />
                    <Th label={t('comp.gamification.learningCol', 'Aprendizado')} sortKey="learning_points" currentSort={sortKey} asc={sortAsc} onSort={handleSort} />
                    <Th label={t('comp.gamification.producaoCol', 'Producao')} sortKey="producao_points" currentSort={sortKey} asc={sortAsc} onSort={handleSort} />
                    <Th label={t('comp.gamification.curadoriaCol', 'Curadoria')} sortKey="curadoria_points" currentSort={sortKey} asc={sortAsc} onSort={handleSort} />
                    <Th label={t('comp.gamification.championsCol', 'Champions')} sortKey="champions_points" currentSort={sortKey} asc={sortAsc} onSort={handleSort} />
                  </>
                )}
                <Th label="CPMAI" />
                <Th label={t('comp.gamification.trail', 'Trilha')} />
                <Th label="" className="sticky right-0 z-20 bg-[var(--surface-section-cool)]" />
              </tr>
            </thead>
            <tbody>
              {sortedMembers.map((m, i) => {
                const isOpen = expandedId === m.id;
                return (
                  <Fragment key={m.id}>
                    <tr
                      className="border-t border-[var(--border-subtle)] hover:bg-[var(--surface-hover)]"
                    >
                      <td className="px-3 py-2.5 text-center text-[var(--text-secondary)] font-bold">
                        {i + 1}
                      </td>
                      <td className="px-3 py-2.5 font-semibold text-navy whitespace-nowrap sticky left-0 z-10 bg-[var(--surface-card)]">
                        {m.name}
                      </td>
                      <td className="px-3 py-2.5 text-center font-bold">{m.total_points}</td>
                      <td className="px-3 py-2.5 text-center">{m.cycle_points}</td>
                      <td className="px-3 py-2.5 text-center whitespace-nowrap">
                        {m.current_streak > 0 ? (
                          <span className="font-semibold text-orange-600 dark:text-orange-400">
                            &#x1F525; {m.current_streak}
                          </span>
                        ) : (
                          <span className="text-[var(--text-muted)]">0</span>
                        )}
                      </td>
                      {showBreakdown && (
                        <td className="px-3 py-2.5 text-center">{m.attendance_points}</td>
                      )}
                      <td className="px-3 py-2.5 text-center">
                        {m.attendance_rate != null ? (
                          <AttendanceRatePill rate={m.attendance_rate} />
                        ) : (
                          <span className="text-[var(--text-muted)]">—</span>
                        )}
                      </td>
                      {showBreakdown && (
                        <>
                          <td className="px-3 py-2.5 text-center">{m.cert_points}</td>
                          <td className="px-3 py-2.5 text-center">{m.badge_points}</td>
                          <td className="px-3 py-2.5 text-center">{m.learning_points}</td>
                          <td className="px-3 py-2.5 text-center">{m.producao_points}</td>
                          <td className="px-3 py-2.5 text-center">{m.curadoria_points}</td>
                          <td className="px-3 py-2.5 text-center">{m.champions_points}</td>
                        </>
                      )}
                      <td className="px-3 py-2.5 text-center">
                        {m.has_cpmai ? (
                          <span className="text-emerald-600 dark:text-emerald-400 font-bold">&#x2705;</span>
                        ) : (
                          <span className="text-red-400 dark:text-red-500">&#x274C;</span>
                        )}
                      </td>
                      <td className="px-3 py-2.5 text-center font-medium text-[var(--text-secondary)]">
                        {m.trail_progress}/{m.trail_courses?.length || TOTAL_COURSES}
                      </td>
                      <td className="px-3 py-2.5 text-center sticky right-0 z-10 bg-[var(--surface-card)]">
                        <button
                          type="button"
                          onClick={() => toggleExpand(m.id)}
                          aria-expanded={isOpen}
                          // #592 a11y: the drill-down panel (gamif-detail-*) is only in the
                          // DOM while open, so aria-controls must point at it only then —
                          // a dangling aria-controls makes some screen readers announce a
                          // control for a target that does not exist.
                          aria-controls={isOpen ? `gamif-detail-${m.id}` : undefined}
                          aria-label={isOpen
                            ? t('comp.gamification.collapse', 'Ocultar detalhes')
                            : t('comp.gamification.expand', 'Ver detalhes do membro')}
                          // #592 a11y: forced-colors fallback ring (Windows High Contrast
                          // strips box-shadow, so focus:ring is invisible there) — mirrors
                          // the #577 breakdown toggle button.
                          className="rounded-md px-2 py-1 text-[var(--text-secondary)] hover:bg-[var(--surface-hover)] hover:text-navy focus:outline-none focus:ring-2 focus:ring-[#00799E] forced-colors:focus:outline forced-colors:focus:outline-2 forced-colors:focus:outline-offset-2"
                        >
                          {isOpen ? <span>&#x25B4;</span> : <span>&#x25BE;</span>}
                        </button>
                      </td>
                    </tr>
                    {isOpen && (
                      <tr className="border-t border-[var(--border-subtle)]">
                        <td colSpan={visibleCols} className="p-0">
                          <MemberDrillDown member={m} t={t} />
                        </td>
                      </tr>
                    )}
                  </Fragment>
                );
              })}
              {sortedMembers.length === 0 && (
                <tr>
                  <td colSpan={visibleCols} className="px-3 py-6 text-center text-[var(--text-muted)]">
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

// ─── Attendance Rate Pill (color-coded by threshold) ───
function AttendanceRatePill({ rate }: { rate: number }) {
  const pct = Math.round(rate * 100);
  const cls =
    rate >= 0.8
      ? 'text-emerald-700 dark:text-emerald-400'
      : rate >= 0.5
        ? 'text-amber-600 dark:text-amber-400'
        : 'text-red-600 dark:text-red-400';
  return <span className={`font-semibold ${cls}`}>{pct}%</span>;
}

// ─── Per-member coaching drill-down (#425) ───
function MemberDrillDown({ member, t }: { member: Member; t: (k: string, f?: string) => string }) {
  const courses = member.trail_courses || [];
  const lastActivity = member.last_activity
    ? new Date(`${member.last_activity}T00:00:00`).toLocaleDateString(undefined, { day: '2-digit', month: 'short', year: 'numeric' })
    : null;
  const statusMeta: Record<string, { icon: string; label: string; cls: string }> = {
    completed: {
      icon: '✅',
      label: t('comp.gamification.statusCompleted', 'Concluido'),
      cls: 'border-emerald-300 dark:border-emerald-700 bg-emerald-50 dark:bg-emerald-950/30',
    },
    in_progress: {
      icon: '◑',
      label: t('comp.gamification.statusInProgress', 'Em progresso'),
      cls: 'border-amber-300 dark:border-amber-700 bg-amber-50 dark:bg-amber-950/30',
    },
    missing: {
      icon: '○',
      label: t('comp.gamification.statusMissing', 'Pendente'),
      cls: 'border-[var(--border-subtle)] bg-[var(--surface-section-cool)] opacity-80',
    },
  };

  return (
    <div
      id={`gamif-detail-${member.id}`}
      tabIndex={-1}
      className="bg-[var(--surface-section-cool)] border-l-2 border-[#00799E] px-5 py-4 space-y-5 focus:outline-none"
    >
      <div className="text-sm font-bold text-navy">
        {t('comp.gamification.coachingTitle', 'Coaching do membro')} &middot; {member.name}
      </div>

      {/* Coaching signals */}
      <div>
        <div className="text-[.72rem] font-bold uppercase tracking-wide text-[var(--text-secondary)] mb-2">
          {t('comp.gamification.coachingSignals', 'Sinais de coaching')}
        </div>
        <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
          <StatCard
            label={t('comp.gamification.attendanceRateLabel', 'Taxa de presenca (ciclo)')}
            value={member.attendance_rate != null ? `${Math.round(member.attendance_rate * 100)}%` : t('comp.gamification.noData', 'Sem dados')}
          />
          <StatCard
            label={t('comp.gamification.currentStreak', 'Sequencia atual')}
            value={`${member.current_streak} ${t('comp.gamification.cyclesUnit', 'ciclos')}`}
          />
          <StatCard
            label={t('comp.gamification.longestStreak', 'Maior sequencia')}
            value={`${member.longest_streak} ${t('comp.gamification.cyclesUnit', 'ciclos')}`}
          />
          <StatCard
            label={t('comp.gamification.activeCycles', 'Ciclos ativos')}
            value={String(member.active_cycles)}
          />
          <StatCard
            label={t('comp.gamification.lastActivity', 'Ultima atividade')}
            value={lastActivity || t('comp.gamification.noActivity', 'Sem atividade')}
          />
        </div>
      </div>

      {/* Trail breakdown */}
      <div>
        <div className="text-[.72rem] font-bold uppercase tracking-wide text-[var(--text-secondary)] mb-2">
          {t('comp.gamification.trailBreakdown', 'Trilha PMI AI')} &middot; {member.trail_progress}/{courses.length || TOTAL_COURSES}
        </div>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-2">
          {courses.map((c) => {
            const meta = statusMeta[c.status] || statusMeta.missing;
            return (
              <div
                key={c.course_id}
                className={`flex items-center gap-2 rounded-lg border px-3 py-2 ${meta.cls}`}
              >
                <span className="text-base leading-none">{meta.icon}</span>
                <div className="min-w-0">
                  <div className="text-[.72rem] font-semibold text-navy truncate">{c.name}</div>
                  <div className="text-[.66rem] text-[var(--text-secondary)]">{meta.label}</div>
                </div>
              </div>
            );
          })}
          {courses.length === 0 && (
            <div className="text-[.72rem] text-[var(--text-muted)]">
              {t('comp.gamification.noData', 'Sem dados')}
            </div>
          )}
        </div>
      </div>

      {/* XP by pillar (#591a) — surfaces all 7 raw-pillar point values so the
          summary-table column collapse (#577) is lossless: every pillar's XP
          stays reachable even with the breakdown columns hidden. Sits after the
          coaching/trail narrative (council fold: keep behavioural + learning
          adjacent). Champions lives HERE — its canonical XP-source home — and is
          no longer duplicated under Recognition (council: 4/5 reviewers flagged
          the dup). Reuses the pie-chart pillar labels (no new label keys). The
          Fragment carries the React key because the plain-function StatCard does
          not forward one (a bare key={…} on it is a TS2322). */}
      <div>
        <div className="text-[.72rem] font-bold uppercase tracking-wide text-[var(--text-secondary)] mb-2">
          {t('comp.gamification.xpByPillar', 'XP por pilar')}
        </div>
        <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-2">
          {([
            ['comp.gamification.attendance', 'Presenca', member.attendance_points],
            ['comp.gamification.certs', 'Certificacoes', member.cert_points],
            ['comp.gamification.badges', 'Badges', member.badge_points],
            ['comp.gamification.learning', 'Aprendizado', member.learning_points],
            ['comp.gamification.producao', 'Producao', member.producao_points],
            ['comp.gamification.curadoria', 'Curadoria', member.curadoria_points],
            ['comp.gamification.champions', 'Champions', member.champions_points],
          ] as const).map(([labelKey, fallback, value]) => (
            <Fragment key={labelKey}>
              <StatCard label={t(labelKey, fallback)} value={String(value ?? 0)} />
            </Fragment>
          ))}
        </div>
      </div>

      {/* Recognition */}
      <div>
        <div className="text-[.72rem] font-bold uppercase tracking-wide text-[var(--text-secondary)] mb-2">
          {t('comp.gamification.recognition', 'Reconhecimento')}
        </div>
        <div className="grid grid-cols-2 gap-3">
          <StatCard
            label={t('comp.gamification.credlyBadges', 'Badges Credly')}
            value={String(member.credly_badge_count)}
          />
          <StatCard
            label="CPMAI"
            value={member.has_cpmai
              ? t('comp.gamification.cpmaiYes', 'Certificado')
              : t('comp.gamification.cpmaiNo', 'Nao certificado')}
          />
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

// ─── Small stat card (drill-down) ───
function StatCard({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-lg p-3">
      <div className="text-[.66rem] font-bold uppercase tracking-wide text-[var(--text-secondary)]">{label}</div>
      <div className="text-sm font-extrabold text-navy mt-1">{value}</div>
      {hint && <div className="text-[.64rem] text-[var(--text-muted)] mt-0.5">{hint}</div>}
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
  className,
}: {
  label: string;
  sortKey?: SortKey;
  currentSort?: SortKey;
  asc?: boolean;
  onSort?: (key: SortKey) => void;
  className?: string;
}) {
  const isSorted = sortKey && currentSort === sortKey;
  const arrow = isSorted ? (asc ? ' ▲' : ' ▼') : '';
  const ariaSort: 'ascending' | 'descending' | 'none' | undefined = sortKey
    ? (isSorted ? (asc ? 'ascending' : 'descending') : 'none')
    : undefined;

  return (
    <th
      scope="col"
      aria-sort={ariaSort}
      tabIndex={sortKey ? 0 : undefined}
      className={`text-center px-3 py-2.5 font-bold text-[var(--text-secondary)] whitespace-nowrap ${
        // #592 a11y: sortable headers are keyboard-focusable (tabIndex 0); add the same
        // forced-colors fallback ring as the buttons so the focus indicator survives
        // Windows High Contrast (which drops box-shadow → focus:ring vanishes).
        sortKey ? 'cursor-pointer select-none hover:text-navy focus:outline-none focus:ring-2 focus:ring-inset focus:ring-[#00799E] forced-colors:focus:outline forced-colors:focus:outline-2 forced-colors:focus:outline-offset-2' : ''
      } ${className || ''}`}
      onClick={() => sortKey && onSort?.(sortKey)}
      onKeyDown={(e) => {
        if (sortKey && (e.key === 'Enter' || e.key === ' ')) {
          e.preventDefault();
          onSort?.(sortKey);
        }
      }}
    >
      {label}{arrow}
    </th>
  );
}
