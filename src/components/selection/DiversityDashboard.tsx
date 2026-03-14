import { useEffect, useState } from 'react';
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
  const [data, setData] = useState<DiversityData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const load = async () => {
      const sb = (window as any).navGetSb?.();
      if (!sb) { setTimeout(load, 300); return; }

      try {
        const { data: result, error: err } = await sb.rpc('get_diversity_dashboard');
        if (err) throw err;
        if (result?.error) { setError(result.error); return; }
        setData(result);
      } catch (e: any) {
        setError(e?.message || 'Failed to load diversity data');
      } finally {
        setLoading(false);
      }
    };
    load();
  }, []);

  if (loading) return <div className="text-center py-8 text-[var(--text-muted)]">Carregando...</div>;
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
        <SummaryCard label="Total de Candidaturas" value={data.applicants_total} color="bg-blue-50 text-blue-700" />
        <SummaryCard label="Aprovados" value={data.approved_total} color="bg-green-50 text-green-700" />
        <SummaryCard
          label="Taxa de Aprovação"
          value={data.applicants_total > 0 ? `${Math.round((data.approved_total / data.applicants_total) * 100)}%` : '0%'}
          color="bg-indigo-50 text-indigo-700"
        />
      </div>

      {/* Gender distribution */}
      <ChartCard title="Distribuição por Gênero">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <ResponsiveContainer width="100%" height={220}>
            <PieChart>
              <Pie data={genderPie} dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={80} label>
                {genderPie.map((entry, i) => <Cell key={i} fill={entry.color} />)}
              </Pie>
              <Tooltip />
              <Legend />
            </PieChart>
          </ResponsiveContainer>
          <ResponsiveContainer width="100%" height={220}>
            <BarChart data={data.by_gender} layout="vertical">
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis type="number" />
              <YAxis dataKey="gender" type="category" width={100} tick={{ fontSize: 11 }} />
              <Tooltip />
              <Legend />
              <Bar dataKey="applicants" fill="#00799E" name="Candidaturas" />
              <Bar dataKey="approved" fill="#10B981" name="Aprovados" />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </ChartCard>

      {/* Chapter distribution */}
      <ChartCard title="Distribuição por Capítulo">
        <ResponsiveContainer width="100%" height={Math.max(200, (data.by_chapter?.length || 1) * 40)}>
          <BarChart data={data.by_chapter} layout="vertical">
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis type="number" />
            <YAxis dataKey="chapter" type="category" width={120} tick={{ fontSize: 11 }} />
            <Tooltip />
            <Legend />
            <Bar dataKey="applicants" fill="#00799E" name="Candidaturas" />
            <Bar dataKey="approved" fill="#10B981" name="Aprovados" />
          </BarChart>
        </ResponsiveContainer>
      </ChartCard>

      {/* Sector distribution */}
      <ChartCard title="Distribuição por Setor">
        <ResponsiveContainer width="100%" height={Math.max(200, (data.by_sector?.length || 1) * 35)}>
          <BarChart data={data.by_sector} layout="vertical">
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis type="number" />
            <YAxis dataKey="sector" type="category" width={130} tick={{ fontSize: 10 }} />
            <Tooltip />
            <Legend />
            <Bar dataKey="applicants" fill="#4F17A8" name="Candidaturas" />
            <Bar dataKey="approved" fill="#F59E0B" name="Aprovados" />
          </BarChart>
        </ResponsiveContainer>
      </ChartCard>

      {/* Seniority distribution */}
      <ChartCard title="Distribuição por Senioridade">
        <ResponsiveContainer width="100%" height={220}>
          <BarChart data={data.by_seniority}>
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis dataKey="band" tick={{ fontSize: 10 }} />
            <YAxis />
            <Tooltip />
            <Legend />
            <Bar dataKey="applicants" fill="#FF610F" name="Candidaturas" />
            <Bar dataKey="approved" fill="#10B981" name="Aprovados" />
          </BarChart>
        </ResponsiveContainer>
      </ChartCard>

      {/* Region distribution */}
      <ChartCard title="Distribuição por Região">
        <ResponsiveContainer width="100%" height={Math.max(200, (data.by_region?.length || 1) * 35)}>
          <BarChart data={data.by_region} layout="vertical">
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis type="number" />
            <YAxis dataKey="region" type="category" width={100} tick={{ fontSize: 10 }} />
            <Tooltip />
            <Legend />
            <Bar dataKey="applicants" fill="#6366F1" name="Candidaturas" />
            <Bar dataKey="approved" fill="#EC4899" name="Aprovados" />
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
