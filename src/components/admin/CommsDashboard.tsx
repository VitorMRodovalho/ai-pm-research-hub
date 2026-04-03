import React, { useEffect, useState } from 'react';
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell,
  Legend,
} from 'recharts';

type CommsMetrics = {
  backlog_count: number;
  overdue_count: number;
  total_publications: number;
  by_status: Record<string, number>;
  by_format: Record<string, number>;
};

const STATUS_LABELS: Record<string, string> = {
  backlog: 'Backlog',
  todo: 'To Do',
  in_progress: 'Em Progresso',
  review: 'Revisão',
  done: 'Concluído',
  unknown: 'Outros',
};

const FORMAT_COLORS = ['#3B82F6', '#8B5CF6', '#10B981', '#F59E0B', '#EF4444', '#06B6D4', '#EC4899', '#6B7280'];

export default function CommsDashboard() {
  const [metrics, setMetrics] = useState<CommsMetrics | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const windowRef = globalThis as Window & { navGetSb?: () => any };

  useEffect(() => {
    let cancelled = false;
    const sb = windowRef?.navGetSb?.();
    if (!sb) {
      setError('Supabase não disponível.');
      setLoading(false);
      return;
    }
    sb.rpc('get_comms_dashboard_metrics')
      .then(({ data, error: err }: { data: CommsMetrics | null; error: any }) => {
        if (cancelled) return;
        if (err) {
          setError(String(err?.message || err || 'Erro ao carregar métricas'));
          setLoading(false);
          return;
        }
        setMetrics(data || {
          backlog_count: 0,
          overdue_count: 0,
          total_publications: 0,
          by_status: {},
          by_format: {},
        });
        setLoading(false);
      })
      .catch((e: unknown) => {
        if (!cancelled) {
          setError(String(e));
          setLoading(false);
        }
      });
    return () => { cancelled = true; };
  }, []);

  if (loading) {
    return (
      <div className="text-[var(--text-muted)] text-sm py-8">Loading metrics...</div>
    );
  }
  if (error) {
    return (
      <div className="rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-amber-800 text-sm">
        {error}
      </div>
    );
  }
  if (!metrics) return null;

  const statusData = Object.entries(metrics.by_status || {}).map(([status, count]) => ({
    name: STATUS_LABELS[status] || status,
    count,
  }));

  const formatData = Object.entries(metrics.by_format || {}).map(([name, value]) => ({
    name,
    value,
  }));

  return (
    <div className="space-y-6">
      {/* Macro cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
        <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-base)] p-3">
          <div className="text-xs text-[var(--text-secondary)] uppercase font-semibold">Posts no Backlog</div>
          <div className="text-lg font-extrabold text-[var(--text-primary)]">{metrics.backlog_count}</div>
        </div>
        <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-base)] p-3">
          <div className="text-xs text-[var(--text-secondary)] uppercase font-semibold">Posts Atrasados</div>
          <div className="text-lg font-extrabold text-[var(--text-primary)]">{metrics.overdue_count}</div>
        </div>
        <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-base)] p-3">
          <div className="text-xs text-[var(--text-secondary)] uppercase font-semibold">Total de Publicações</div>
          <div className="text-lg font-extrabold text-[var(--text-primary)]">{metrics.total_publications}</div>
        </div>
      </div>

      {/* Bar chart: Volume por status */}
      <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-4">
        <h2 className="text-sm font-semibold text-[var(--text-primary)] mb-3">Volume por Status</h2>
        {statusData.length > 0 ? (
          <ResponsiveContainer width="100%" height={220}>
            <BarChart data={statusData} margin={{ top: 8, right: 8, left: 8, bottom: 8 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--border-default, #e2e8f0)" />
              <XAxis dataKey="name" tick={{ fontSize: 11 }} />
              <YAxis tick={{ fontSize: 11 }} />
              <Tooltip formatter={(v: number) => [v, 'Itens']} />
              <Bar dataKey="count" fill="#3B82F6" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        ) : (
          <p className="text-[var(--text-secondary)] text-sm py-6">{t('comp.comms.noStatus', 'No status data.')}</p>
        )}
      </div>

      {/* Pie chart: Distribuição por formato */}
      <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-4">
        <h2 className="text-sm font-semibold text-[var(--text-primary)] mb-3">Distribuição por Formato</h2>
        {formatData.length > 0 ? (
          <ResponsiveContainer width="100%" height={220}>
            <PieChart>
              <Pie
                data={formatData}
                dataKey="value"
                nameKey="name"
                cx="50%"
                cy="50%"
                innerRadius={50}
                outerRadius={80}
                paddingAngle={2}
                label={({ name, percent }) => `${name} ${(percent * 100).toFixed(0)}%`}
              >
                {formatData.map((_, i) => (
                  <Cell key={i} fill={FORMAT_COLORS[i % FORMAT_COLORS.length]} />
                ))}
              </Pie>
              <Tooltip formatter={(v: number) => [v, 'Itens']} />
              <Legend />
            </PieChart>
          </ResponsiveContainer>
        ) : (
          <p className="text-[var(--text-secondary)] text-sm py-6">{t('comp.comms.noFormat', 'No format data.')}</p>
        )}
      </div>
    </div>
  );
}
