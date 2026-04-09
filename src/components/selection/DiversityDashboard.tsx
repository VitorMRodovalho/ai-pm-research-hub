import { useEffect, useState, useCallback } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend,
  ResponsiveContainer, PieChart, Pie, Cell,
} from 'recharts';

interface DimensionData {
  applicants: number;
  approved: number;
  [key: string]: string | number;
}

interface DiversityData {
  cycle_id: string;
  applicants_total: number;
  approved_total: number;
  by_gender: DimensionData[];
  by_chapter: DimensionData[];
  by_sector: DimensionData[];
  by_seniority: DimensionData[];
  by_region: DimensionData[];
  snapshots: any[];
}

const COLORS = ['#00799E', '#FF610F', '#4F17A8', '#10B981', '#F59E0B', '#EF4444', '#6366F1', '#EC4899'];

export default function DiversityDashboard() {
  const t = usePageI18n();
  const [data, setData] = useState<DiversityData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [cycleId, setCycleId] = useState<string | null>(null);

  const fetchData = useCallback(async (cId?: string | null) => {
    const sb = (window as any).navGetSb?.();
    if (!sb) { setTimeout(() => fetchData(cId), 300); return; }
    setLoading(true);
    setError(null);
    try {
      const params = cId ? { p_cycle_id: cId } : {};
      const { data: result, error: err } = await sb.rpc('get_diversity_dashboard', params);
      if (err) throw err;
      if (result?.error) { setError(result.error); return; }
      setData(result);
    } catch (e: any) {
      setError(e?.message || 'Failed to load diversity data');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetchData(); }, [fetchData]);

  // Listen for cycle changes from the vanilla script
  useEffect(() => {
    const handler = (e: Event) => {
      const detail = (e as CustomEvent).detail;
      if (detail?.cycleId) {
        setCycleId(detail.cycleId);
        fetchData(detail.cycleId);
      }
    };
    window.addEventListener('selection:cycle-changed', handler);
    return () => window.removeEventListener('selection:cycle-changed', handler);
  }, [fetchData]);

  if (loading) return <div className="text-center py-8 text-[var(--text-muted)]">{t('diversity.loading', 'Loading...')}</div>;
  if (error) return <div className="text-center py-8 text-red-500">{error}</div>;
  if (!data) return null;

  const genderPie = (data.by_gender || []).map((g, i) => ({
    name: g.gender as string,
    value: g.applicants,
    color: COLORS[i % COLORS.length],
  }));

  return (
    <div className="space-y-6">
      {/* Summary cards */}
      <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
        <SummaryCard label={t('diversity.totalApplicants', 'Total de Candidaturas')} value={data.applicants_total} color="bg-blue-50 text-blue-700 dark:bg-blue-950/30 dark:text-blue-300" />
        <SummaryCard label={t('diversity.approved', 'Aprovados')} value={data.approved_total} color="bg-green-50 text-green-700 dark:bg-green-950/30 dark:text-green-300" />
        <SummaryCard
          label={t('diversity.approvalRate', 'Taxa de Aprovação')}
          value={data.applicants_total > 0 ? `${Math.round((data.approved_total / data.applicants_total) * 100)}%` : '0%'}
          color="bg-indigo-50 text-indigo-700 dark:bg-indigo-950/30 dark:text-indigo-300"
        />
      </div>

      {/* Gender distribution */}
      <ChartCard title={t('diversity.byGender', 'Distribuição por Gênero')}>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <p className="text-[10px] text-[var(--text-muted)] text-center mb-1 font-semibold">{t('diversity.applicantsOnly', 'Candidaturas')}</p>
            <ResponsiveContainer width="100%" height={280}>
              <PieChart>
                <Pie data={genderPie} dataKey="value" nameKey="name" cx="50%" cy="45%" outerRadius={90}
                  label={({ name, value, percent }) => `${name}: ${value} (${(percent * 100).toFixed(0)}%)`}
                  labelLine={{ strokeWidth: 1 }}
                >
                  {genderPie.map((entry, i) => <Cell key={i} fill={entry.color} />)}
                </Pie>
                <Tooltip />
                <Legend wrapperStyle={{ fontSize: 11 }} />
              </PieChart>
            </ResponsiveContainer>
          </div>
          <ResponsiveContainer width="100%" height={280}>
            <BarChart data={data.by_gender} layout="vertical">
              <CartesianGrid strokeDasharray="3 3" stroke="var(--border-subtle)" />
              <XAxis type="number" />
              <YAxis dataKey="gender" type="category" width={110} tick={{ fontSize: 11 }} />
              <Tooltip />
              <Legend wrapperStyle={{ fontSize: 11 }} />
              <Bar dataKey="applicants" fill="#00799E" name={t('diversity.applicants', 'Candidaturas')} />
              <Bar dataKey="approved" fill="#10B981" name={t('diversity.approved', 'Aprovados')} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </ChartCard>

      {/* Chapter distribution */}
      <ChartCard title={t('diversity.byChapter', 'Distribuição por Capítulo')}>
        <ResponsiveContainer width="100%" height={Math.max(200, (data.by_chapter?.length || 1) * 45)}>
          <BarChart data={data.by_chapter} layout="vertical">
            <CartesianGrid strokeDasharray="3 3" stroke="var(--border-subtle)" />
            <XAxis type="number" />
            <YAxis dataKey="chapter" type="category" width={120} tick={{ fontSize: 11 }} />
            <Tooltip />
            <Legend wrapperStyle={{ fontSize: 11 }} />
            <Bar dataKey="applicants" fill="#00799E" name={t('diversity.applicants', 'Candidaturas')} />
            <Bar dataKey="approved" fill="#10B981" name={t('diversity.approved', 'Aprovados')} />
          </BarChart>
        </ResponsiveContainer>
      </ChartCard>

      {/* Sector distribution */}
      <ChartCard title={t('diversity.bySector', 'Distribuição por Setor')}>
        <ResponsiveContainer width="100%" height={Math.max(200, (data.by_sector?.length || 1) * 40)}>
          <BarChart data={data.by_sector} layout="vertical">
            <CartesianGrid strokeDasharray="3 3" stroke="var(--border-subtle)" />
            <XAxis type="number" />
            <YAxis dataKey="sector" type="category" width={150} tick={{ fontSize: 10 }} />
            <Tooltip />
            <Legend wrapperStyle={{ fontSize: 11 }} />
            <Bar dataKey="applicants" fill="#4F17A8" name={t('diversity.applicants', 'Candidaturas')} />
            <Bar dataKey="approved" fill="#F59E0B" name={t('diversity.approved', 'Aprovados')} />
          </BarChart>
        </ResponsiveContainer>
      </ChartCard>

      {/* Seniority distribution */}
      <ChartCard title={t('diversity.bySeniority', 'Distribuição por Senioridade')}>
        <ResponsiveContainer width="100%" height={250}>
          <BarChart data={data.by_seniority}>
            <CartesianGrid strokeDasharray="3 3" stroke="var(--border-subtle)" />
            <XAxis dataKey="band" tick={{ fontSize: 10 }} />
            <YAxis />
            <Tooltip />
            <Legend wrapperStyle={{ fontSize: 11 }} />
            <Bar dataKey="applicants" fill="#FF610F" name={t('diversity.applicants', 'Candidaturas')} />
            <Bar dataKey="approved" fill="#10B981" name={t('diversity.approved', 'Aprovados')} />
          </BarChart>
        </ResponsiveContainer>
      </ChartCard>

      {/* Region distribution */}
      <ChartCard title={t('diversity.byRegion', 'Distribuição por Região')}>
        <ResponsiveContainer width="100%" height={Math.max(250, (data.by_region?.length || 1) * 35)}>
          <BarChart data={data.by_region} layout="vertical">
            <CartesianGrid strokeDasharray="3 3" stroke="var(--border-subtle)" />
            <XAxis type="number" />
            <YAxis dataKey="region" type="category" width={140} tick={{ fontSize: 10 }} />
            <Tooltip />
            <Legend wrapperStyle={{ fontSize: 11 }} />
            <Bar dataKey="applicants" fill="#6366F1" name={t('diversity.applicants', 'Candidaturas')} />
            <Bar dataKey="approved" fill="#EC4899" name={t('diversity.approved', 'Aprovados')} />
          </BarChart>
        </ResponsiveContainer>
      </ChartCard>
    </div>
  );
}

function SummaryCard({ label, value, color }: { label: string; value: number | string; color: string }) {
  return (
    <div className={`rounded-xl p-4 text-center ${color}`}>
      <div className="text-2xl font-extrabold">{value}</div>
      <div className="text-[.72rem] font-bold mt-1">{label}</div>
    </div>
  );
}

function ChartCard({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-xl overflow-hidden">
      <div className="px-5 py-3 border-b border-[var(--border-default)]">
        <h3 className="text-sm font-bold text-navy">{title}</h3>
      </div>
      <div className="p-4">{children}</div>
    </div>
  );
}
