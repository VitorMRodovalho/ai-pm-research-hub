import { useEffect, useState, useMemo } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Cell } from 'recharts';

interface InitiativeMetrics {
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

type SortKey = 'initiative_title' | 'member_count' | 'attendance_rate' | 'cards_completed' | 'total_xp' | 'total_hours' | 'days_since_last_meeting';
type RankingMetric = 'attendance' | 'production' | 'xp' | 'hours';
type KindFilter = 'research_tribe' | 'workgroup' | 'committee' | 'study_group' | 'congress' | 'all';

const ROW_COLORS = ['#0d9488', '#2563eb', '#7c3aed', '#dc2626', '#ea580c', '#0891b2', '#4f46e5', '#059669'];
const SEVERITY_COLORS = { high: '#ef4444', medium: '#f59e0b', low: '#3b82f6' };
const SEVERITY_ICONS = { high: '🔴', medium: '⚠️', low: 'ℹ️' };

const KIND_PREFIX: Record<string, string> = {
  research_tribe: 'T',
  workgroup: 'WG',
  committee: 'C',
  study_group: 'SG',
  congress: 'CG',
};

function rowLabel(it: InitiativeMetrics): string {
  // Only research_tribe rows get the T0X legacy prefix; guard prevents leakage if a
  // future non-tribe kind ever inherits legacy_tribe_id (code-reviewer p192 LOW).
  if (it.tribe_id != null && it.initiative_kind === 'research_tribe') return `T${String(it.tribe_id).padStart(2, '0')}`;
  const prefix = KIND_PREFIX[it.initiative_kind] || it.initiative_kind.slice(0, 2).toUpperCase();
  return prefix + (it.initiative_id ? it.initiative_id.slice(0, 4) : '');
}

export default function CrossTribeIsland() {
  const t = usePageI18n();
  const [items, setItems] = useState<InitiativeMetrics[]>([]);
  const [alerts, setAlerts] = useState<AlertsData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [sortBy, setSortBy] = useState<SortKey>('attendance_rate');
  const [sortAsc, setSortAsc] = useState(false);
  const [alertsExpanded, setAlertsExpanded] = useState(false);
  const [trendMetric, setTrendMetric] = useState<RankingMetric>('attendance');
  const [selectedKind, setSelectedKind] = useState<KindFilter>('research_tribe');

  useEffect(() => {
    let cancelled = false;
    const load = async () => {
      const sb = (window as any).navGetSb?.();
      if (!sb) { setTimeout(load, 300); return; }
      setLoading(true);
      try {
        const p_kind = selectedKind === 'all' ? null : selectedKind;
        const [compRes, alertRes] = await Promise.all([
          sb.rpc('exec_cross_initiative_comparison', { p_kind }),
          sb.rpc('detect_operational_alerts'),
        ]);
        if (!cancelled) {
          if (compRes.error) throw new Error(compRes.error.message);
          setItems(compRes.data?.initiatives || []);
          setAlerts(alertRes.data || null);
        }
      } catch (e: any) {
        if (!cancelled) setError(e.message);
      }
      if (!cancelled) setLoading(false);
    };
    load();
    return () => { cancelled = true; };
  }, [selectedKind]);

  const sortedItems = useMemo(() => {
    const copy = [...items];
    copy.sort((a, b) => {
      const av = a[sortBy] ?? 0;
      const bv = b[sortBy] ?? 0;
      if (typeof av === 'string' && typeof bv === 'string') return sortAsc ? av.localeCompare(bv) : bv.localeCompare(av);
      return sortAsc ? (av as number) - (bv as number) : (bv as number) - (av as number);
    });
    return copy;
  }, [items, sortBy, sortAsc]);

  const rankings = useMemo(() => {
    const byAttendance = [...items].sort((a, b) => b.attendance_rate - a.attendance_rate);
    const byProduction = [...items].sort((a, b) => b.cards_completed - a.cards_completed);
    const byXp = [...items].sort((a, b) => b.total_xp - a.total_xp);
    const byHours = [...items].sort((a, b) => b.total_hours - a.total_hours);
    return { attendance: byAttendance, production: byProduction, xp: byXp, hours: byHours };
  }, [items]);

  // Per-initiative color map keyed by initiative_id (stable across chart sections).
  // code-reviewer p192 MED: was inconsistent — inline rankings used rank-position color
  // and Recharts used items-order color, so the same initiative changed color across sections.
  const colorMap = useMemo(() => {
    const m = new Map<string, string>();
    items.forEach((it, i) => m.set(it.initiative_id, ROW_COLORS[i % 8]));
    return m;
  }, [items]);

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

  const KIND_OPTIONS: { value: KindFilter; key: string; fallback: string }[] = [
    { value: 'research_tribe', key: 'comp.crossTribe.kindResearchTribe', fallback: 'Tribos de Pesquisa' },
    { value: 'workgroup', key: 'comp.crossTribe.kindWorkgroup', fallback: 'Grupos de Trabalho' },
    { value: 'committee', key: 'comp.crossTribe.kindCommittee', fallback: 'Comitês' },
    { value: 'study_group', key: 'comp.crossTribe.kindStudyGroup', fallback: 'Grupos de Estudo' },
    { value: 'congress', key: 'comp.crossTribe.kindCongress', fallback: 'Congressos' },
    { value: 'all', key: 'comp.crossTribe.kindAll', fallback: 'Todas as Iniciativas' },
  ];

  const FilterBar = (
    <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-3 flex items-center gap-3 flex-wrap">
      <label htmlFor="initiative-kind-filter" className="text-xs font-semibold text-[var(--text-secondary)] uppercase tracking-wide">
        {t('comp.crossTribe.filterKindLabel', 'Tipo de iniciativa:')}
      </label>
      <select
        id="initiative-kind-filter"
        value={selectedKind}
        onChange={(e) => setSelectedKind(e.target.value as KindFilter)}
        className="text-sm px-3 py-1.5 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-[var(--text-primary)]"
      >
        {KIND_OPTIONS.map(opt => (
          <option key={opt.value} value={opt.value}>{t(opt.key, opt.fallback)}</option>
        ))}
      </select>
      <span className="text-[11px] text-[var(--text-muted)]">{items.length} {t('comp.crossTribe.itemsLabel', 'itens')}</span>
    </div>
  );

  if (loading) return <div className="space-y-4">{FilterBar}<div className="text-center py-20 text-[var(--text-muted)]">{t('comp.crossTribe.loading', 'Loading comparison...')}</div></div>;
  if (error) return <div className="space-y-4">{FilterBar}<div className="text-center py-20 text-red-500">{error}</div></div>;
  if (items.length === 0) {
    return <div className="space-y-4">{FilterBar}<div className="text-center py-20 text-[var(--text-muted)]">{t('comp.crossTribe.empty', 'Nenhuma iniciativa neste tipo no ciclo atual.')}</div></div>;
  }

  const rankingConfig: Record<RankingMetric, { label: string; key: keyof InitiativeMetrics; suffix: string }> = {
    attendance: { label: t('comp.tribe.attendance', 'Presença'), key: 'attendance_rate', suffix: '%' },
    production: { label: t('comp.crossTribe.rankingProduction', 'Produção'), key: 'cards_completed', suffix: '' },
    xp: { label: t('comp.crossTribe.rankingXp', 'XP Total'), key: 'total_xp', suffix: '' },
    hours: { label: t('comp.crossTribe.rankingHours', 'Horas'), key: 'total_hours', suffix: 'h' },
  };

  return (
    <div className="space-y-8">
      {FilterBar}

      {/* Alerts Banner */}
      {alerts && alerts.total > 0 && (
        <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-4">
          <button onClick={() => setAlertsExpanded(!alertsExpanded)}
                  className="w-full flex items-center justify-between bg-transparent border-0 cursor-pointer p-0">
            <div className="flex items-center gap-3">
              <span className="text-lg">🚨</span>
              <span className="font-bold text-sm text-[var(--text-primary)]">{t('comp.crossTribe.alertsTitle', 'Alertas Operacionais')}</span>
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
          const maxVal = Math.max(...ranked.map(it => Number(it[cfg.key]) || 0), 1);
          return (
            <div key={metric} className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-xl p-4">
              <h3 className="text-xs font-bold uppercase tracking-wide text-[var(--text-secondary)] mb-3">{cfg.label}</h3>
              <div className="space-y-2">
                {ranked.map((it, i) => {
                  const val = Number(it[cfg.key]) || 0;
                  const pct = (val / maxVal) * 100;
                  const display = metric === 'attendance' ? `${Math.round(val * 100)}%` : `${Math.round(val)}${cfg.suffix}`;
                  return (
                    <div key={it.initiative_id} className="flex items-center gap-2">
                      <span className="text-[11px] font-bold w-10 text-right text-[var(--text-secondary)]">{rowLabel(it)}</span>
                      <div className="flex-1 h-5 rounded bg-[var(--border-subtle)] overflow-hidden">
                        <div className="h-full rounded transition-all" style={{ width: `${pct}%`, background: colorMap.get(it.initiative_id) || ROW_COLORS[i % 8] }} />
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
                <SortHeader label={t('comp.crossTribe.initiative', 'Iniciativa')} sKey="initiative_title" />
                <SortHeader label={t('comp.tribe.members', 'Membros')} sKey="member_count" />
                <SortHeader label={t('comp.tribe.attendance', 'Presença')} sKey="attendance_rate" />
                <SortHeader label="Cards" sKey="cards_completed" />
                <SortHeader label="XP" sKey="total_xp" />
                <SortHeader label={t('comp.crossTribe.rankingHours', 'Horas')} sKey="total_hours" />
                <SortHeader label={t('comp.crossTribe.lastMeeting', 'Última Reunião')} sKey="days_since_last_meeting" />
              </tr>
            </thead>
            <tbody>
              {sortedItems.map((it, i) => {
                const isTribe = it.tribe_id != null;
                const linkHref = isTribe ? `/admin/tribe/${it.tribe_id}` : null;
                const nameNode = (
                  <>
                    <span className="font-bold text-xs mr-1" style={{ color: colorMap.get(it.initiative_id) || ROW_COLORS[i % 8] }}>{rowLabel(it)}</span>
                    <span className="font-semibold text-[var(--text-primary)]">{it.tribe_name || it.initiative_title}</span>
                  </>
                );
                return (
                  <tr key={it.initiative_id} className="border-t border-[var(--border-subtle)] hover:bg-[var(--surface-hover)]">
                    <td className="px-3 py-2.5">
                      {linkHref ? <a href={linkHref} className="no-underline hover:underline">{nameNode}</a> : nameNode}
                      <div className="text-[11px] text-[var(--text-muted)]">{it.leader || '—'}</div>
                    </td>
                    <td className="px-3 py-2.5 text-center">
                      <span className="font-bold">{it.member_count}</span>
                      {/* p195 OPP-194.F: suppress red inactive indicator when initiative has no own events.
                          Post-GAP-194.A (strict scope), kinds with meetings_count=0 always show 100% inactive
                          (tautologically — no events means no attendance possible). Showing red is visually
                          alarming + uninformative for async-work kinds (workgroups/committees/congress). */}
                      {it.meetings_count === 0
                        ? <span className="text-[var(--text-muted)] text-xs ml-1" title={t('comp.crossTribe.noOwnEventsTooltip', 'Iniciativa sem eventos próprios — métrica de presença não aplicável')}>{t('comp.crossTribe.noOwnEventsShort', '(s/ eventos)')}</span>
                        : it.members_inactive_30d > 0 && <span className="text-red-500 text-xs ml-1">({it.members_inactive_30d} {t('comp.crossTribe.inactiveShort', 'inat.')})</span>
                      }
                    </td>
                    <td className="px-3 py-2.5 text-center font-bold">{Math.round(it.attendance_rate * 100)}%</td>
                    <td className="px-3 py-2.5 text-center">
                      <span className="font-bold">{it.cards_completed}</span>
                      <span className="text-[var(--text-muted)]">/{it.total_cards}</span>
                    </td>
                    <td className="px-3 py-2.5 text-center font-bold">{it.total_xp}</td>
                    <td className="px-3 py-2.5 text-center font-bold">{Math.round(it.total_hours)}h</td>
                    <td className="px-3 py-2.5 text-center">
                      {it.days_since_last_meeting != null ? (
                        <span className={`font-bold ${it.days_since_last_meeting > 14 ? 'text-red-500' : it.days_since_last_meeting > 7 ? 'text-amber-500' : 'text-green-600'}`}>
                          {it.days_since_last_meeting}d
                        </span>
                      ) : <span className="text-[var(--text-muted)]">—</span>}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      {/* Trend Overlay Chart */}
      <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="font-bold text-[var(--text-primary)]">{t('comp.crossTribe.visualComparison', 'Comparativo Visual')}</h3>
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
          <BarChart data={rankings[trendMetric].map((it) => ({
            name: rowLabel(it),
            value: trendMetric === 'attendance' ? Math.round(Number(it[rankingConfig[trendMetric].key]) * 100) : Number(it[rankingConfig[trendMetric].key]),
            fill: colorMap.get(it.initiative_id) || ROW_COLORS[0],
          }))}>
            <CartesianGrid strokeDasharray="3 3" stroke="var(--border-subtle)" />
            <XAxis dataKey="name" tick={{ fontSize: 12 }} />
            <YAxis tick={{ fontSize: 12 }} />
            <Tooltip />
            <Bar dataKey="value" radius={[4, 4, 0, 0]}>
              {rankings[trendMetric].map((it) => (
                <Cell key={it.initiative_id} fill={colorMap.get(it.initiative_id) || ROW_COLORS[0]} />
              ))}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
