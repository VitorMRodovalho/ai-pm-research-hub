import { useState, useEffect, useCallback } from 'react';
import { Users, TrendingUp, Package, Clock, Award, Building, AlertTriangle, AlertCircle, CheckCircle, Activity, Loader2 } from 'lucide-react';
import { usePageI18n } from '../../../i18n/usePageI18n';

/* ────── Types ────── */
interface DashboardData {
  generated_at: string;
  kpis: {
    active_members: number;
    adoption_7d: number;
    deliverables_completed: number;
    deliverables_total: number;
    impact_hours: number;
    cpmai_current: number;
    cpmai_target: number | null;
    chapters_current: number;
    chapters_target: number | null;
  };
  alerts: Array<{
    severity: 'high' | 'medium' | 'low';
    message: string;
    action_label: string;
    action_href: string;
  }> | null;
  recent_activity: Array<{
    type: string;
    message: string;
    details?: any;
    timestamp: string;
  }>;
}

/* ────── Helpers ────── */
// NOTE: timeAgo contains Portuguese strings but is a module-scope helper; i18n deferred.
function timeAgo(dateStr: string): string {
  const diff = Date.now() - new Date(dateStr).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 60) return `há ${mins}min`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `há ${hours}h`;
  const days = Math.floor(hours / 24);
  return `há ${days}d`;
}

function fmtDateTime(dateStr: string): string {
  const d = new Date(dateStr);
  return d.toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' }) + ' ' + d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
}

const ACTIVITY_ICONS: Record<string, string> = {
  audit: '📋',
  campaign: '📧',
  publication: '📄',
};

/* ────── Component ────── */
export default function AdminDashboardIsland() {
  const t = usePageI18n();
  const [data, setData] = useState<DashboardData | null>(null);
  const [loading, setLoading] = useState(true);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const fetchDashboard = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    setLoading(true);
    const { data: result, error } = await sb.rpc('get_admin_dashboard');
    if (!error && result) setData(result);
    setLoading(false);
  }, [getSb]);

  useEffect(() => {
    const boot = () => {
      if (getSb()) fetchDashboard();
      else setTimeout(boot, 300);
    };
    boot();
    window.addEventListener('nav:member', () => fetchDashboard());
  }, []);

  /* ── Loading state ── */
  if (loading && !data) {
    return (
      <div className="flex items-center justify-center py-20 text-[var(--text-muted)]">
        <Loader2 className="animate-spin mr-2" size={20} />
        {t('comp.adminDash.loading', 'Carregando dashboard...')}
      </div>
    );
  }

  if (!data) {
    return (
      <div className="flex items-center justify-center py-20 text-[var(--text-muted)]">
        <AlertCircle className="mr-2" size={20} />
        {t('comp.adminDash.error', 'Erro ao carregar dashboard.')}
      </div>
    );
  }

  const { kpis, alerts, recent_activity } = data;

  /* ── KPI card definitions ── */
  const kpiCards = [
    {
      label: t('comp.adminDash.activeMembers', 'Membros Ativos'),
      value: String(kpis.active_members),
      icon: Users,
      color: 'rgb(20 184 166)', // teal-500
      href: '/admin/members',
    },
    {
      label: t('comp.adminDash.adoption7d', 'Adoção 7d'),
      value: `${kpis.adoption_7d}%`,
      icon: TrendingUp,
      color: 'rgb(59 130 246)', // blue-500
      href: '/admin/adoption',
    },
    {
      label: t('comp.adminDash.deliverables', 'Entregas'),
      value: `${kpis.deliverables_completed}/${kpis.deliverables_total}`,
      icon: Package,
      color: 'rgb(168 85 247)', // purple-500
      href: '/admin/portfolio',
      progress: kpis.deliverables_total > 0 ? kpis.deliverables_completed / kpis.deliverables_total : 0,
    },
    {
      label: t('comp.adminDash.impactHours', 'Horas de Impacto'),
      value: `${kpis.impact_hours}h`,
      icon: Clock,
      color: 'rgb(245 158 11)', // amber-500
      href: '/admin/analytics',
    },
    {
      label: 'CPMAI',
      value: `${kpis.cpmai_current}/${kpis.cpmai_target ?? '?'}`,
      icon: Award,
      color: 'rgb(16 185 129)', // emerald-500
      href: '/admin/analytics',
      progress: kpis.cpmai_target ? kpis.cpmai_current / kpis.cpmai_target : undefined,
    },
    {
      label: t('comp.adminDash.chapters', 'Capítulos'),
      value: `${kpis.chapters_current}/${kpis.chapters_target ?? '?'}`,
      icon: Building,
      color: 'rgb(249 115 22)', // orange-500
      href: '/admin/chapter-report',
      progress: kpis.chapters_target ? kpis.chapters_current / kpis.chapters_target : undefined,
    },
  ];

  const severityIcon = (s: 'high' | 'medium' | 'low') => {
    if (s === 'high') return '🔴';
    if (s === 'medium') return '🟡';
    return '🟢';
  };

  return (
    <div className="max-w-[1100px] mx-auto">
      {/* ── Title Row ── */}
      <div className="mb-8">
        <h1 className="text-2xl font-extrabold text-[var(--text-primary)]">{t('comp.adminDash.title', 'Dashboard do Núcleo')}</h1>
        <p className="text-sm text-[var(--text-muted)] mt-1">
          {t('comp.adminDash.currentCycle', 'Ciclo atual')} &middot; {t('comp.adminDash.generated', 'Gerado')} {timeAgo(data.generated_at)}
        </p>
      </div>

      {/* ── KPI Grid ── */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 mb-8">
        {kpiCards.map((card) => {
          const Icon = card.icon;
          return (
            <a
              key={card.label}
              href={card.href}
              className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-5 cursor-pointer hover:border-teal-500/50 transition-colors block no-underline"
            >
              <div className="flex items-center gap-2 mb-2">
                <Icon size={20} style={{ color: card.color }} />
                <span className="text-xs uppercase tracking-wider text-[var(--text-muted)]">{card.label}</span>
              </div>
              <div className="text-3xl font-black text-[var(--text-primary)]">{card.value}</div>
              {card.progress !== undefined && (
                <div className="mt-3 h-1.5 rounded-full bg-[var(--border-default)] overflow-hidden">
                  <div
                    className="h-full rounded-full transition-all"
                    style={{
                      width: `${Math.min(card.progress * 100, 100)}%`,
                      backgroundColor: card.color,
                    }}
                  />
                </div>
              )}
            </a>
          );
        })}
      </div>

      {/* ── Operational Alerts ── */}
      <div className="mb-8">
        <h2 className="text-lg font-bold text-[var(--text-primary)] flex items-center gap-2 mb-4">
          <AlertTriangle size={20} />
          {t('comp.adminDash.operationalAlerts', 'Alertas Operacionais')}
        </h2>
        <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-5">
          {alerts && alerts.length > 0 ? (
            <ul className="space-y-3">
              {alerts.map((alert, i) => (
                <li key={i} className="flex items-center justify-between gap-3">
                  <div className="flex items-center gap-2 min-w-0">
                    <span className="flex-shrink-0">{severityIcon(alert.severity)}</span>
                    <span className="text-sm text-[var(--text-primary)] truncate">{alert.message}</span>
                  </div>
                  <a
                    href={alert.action_href}
                    className="flex-shrink-0 text-xs font-semibold px-3 py-1 rounded-lg bg-teal-500/10 text-teal-500 hover:bg-teal-500/20 transition-colors no-underline"
                  >
                    {alert.action_label}
                  </a>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm text-[var(--text-muted)]">{t('comp.adminDash.noAlerts', 'Nenhum alerta operacional')}</p>
          )}
        </div>
      </div>

      {/* ── Recent Activity ── */}
      <div className="mb-8">
        <h2 className="text-lg font-bold text-[var(--text-primary)] flex items-center gap-2 mb-4">
          <Activity size={20} />
          {t('comp.adminDash.recentActivity', 'Atividade Recente')}
        </h2>
        <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-5">
          {recent_activity && recent_activity.length > 0 ? (
            <ul className="space-y-3">
              {recent_activity.map((act, i) => (
                <li key={i} className="flex items-start gap-3 text-sm">
                  <span className="flex-shrink-0 text-xs text-[var(--text-muted)] whitespace-nowrap mt-0.5">
                    {fmtDateTime(act.timestamp)}
                  </span>
                  <span className="flex-shrink-0">{ACTIVITY_ICONS[act.type] ?? '📌'}</span>
                  <span className="text-[var(--text-primary)]">{act.message}</span>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm text-[var(--text-muted)]">{t('comp.adminDash.noActivity', 'Nenhuma atividade recente')}</p>
          )}
        </div>
      </div>
    </div>
  );
}
