import { useState, useEffect } from 'react';
import { Clock, Award, Rocket, FileText, Video, MapPin } from 'lucide-react';

function getSb() { return (window as any).navGetSb?.(); }

interface KpiItem {
  name: string; current: number; target: number; unit: string; icon: string;
}
interface KpiData {
  cycle_pct: number;
  kpis: KpiItem[];
}

const ICON_MAP: Record<string, any> = {
  clock: Clock, award: Award, rocket: Rocket,
  'file-text': FileText, video: Video, 'map-pin': MapPin,
};

function KpiCard({ kpi, cyclePct }: { kpi: KpiItem; cyclePct: number }) {
  const Icon = ICON_MAP[kpi.icon] || FileText;
  const pct = kpi.target > 0 ? Math.round((kpi.current / kpi.target) * 100) : 0;

  let barColor: string;
  let statusColor: string;
  if (pct >= cyclePct) {
    barColor = 'bg-green-500';
    statusColor = 'text-green-600';
  } else if (pct >= cyclePct * 0.75) {
    barColor = 'bg-yellow-500';
    statusColor = 'text-yellow-600';
  } else {
    barColor = 'bg-red-500';
    statusColor = 'text-red-600';
  }

  return (
    <div className="bg-[var(--surface-card)] border border-[var(--border-subtle)] rounded-2xl p-4 hover:shadow-md transition-all group relative">
      <div className="flex items-start justify-between mb-3">
        <div className="p-2 rounded-xl bg-[var(--surface-base)]">
          <Icon size={18} className="text-[var(--color-teal)]" />
        </div>
        <span className={`text-lg font-extrabold ${statusColor}`}>{pct}%</span>
      </div>

      <h4 className="text-xs font-bold text-[var(--text-primary)] mb-1">{kpi.name}</h4>
      <p className="text-lg font-extrabold text-[var(--text-primary)]">
        {kpi.current.toLocaleString('pt-BR')}
        <span className="text-xs font-normal text-[var(--text-muted)]"> / {kpi.target.toLocaleString('pt-BR')} {kpi.unit}</span>
      </p>

      {/* Progress bar */}
      <div className="mt-3 h-2 rounded-full bg-[var(--border-subtle)] overflow-hidden">
        <div className={`h-full rounded-full transition-all ${barColor}`} style={{ width: `${Math.min(pct, 100)}%` }} />
      </div>

      {/* Tooltip on hover */}
      <div className="absolute bottom-full left-1/2 -translate-x-1/2 mb-2 hidden group-hover:block z-10">
        <div className="bg-[var(--surface-elevated)] border border-[var(--border-default)] rounded-lg px-3 py-2 shadow-lg text-[10px] text-[var(--text-secondary)] whitespace-nowrap">
          {kpi.current} de {kpi.target} ({pct}%) — Projeção linear esperada: {cyclePct}%
        </div>
      </div>
    </div>
  );
}

export default function KpiDashboard() {
  const [data, setData] = useState<KpiData | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      const sb = getSb();
      if (!sb) return;
      const { data: result } = await sb.rpc('get_kpi_dashboard');
      if (result) setData(result as KpiData);
      setLoading(false);
    })();
  }, []);

  if (loading) {
    return (
      <div className="grid grid-cols-2 lg:grid-cols-3 gap-4">
        {Array.from({ length: 6 }).map((_, i) => (
          <div key={i} className="bg-[var(--surface-card)] border border-[var(--border-subtle)] rounded-2xl p-4 animate-pulse">
            <div className="h-4 bg-[var(--border-subtle)] rounded w-20 mb-3" />
            <div className="h-6 bg-[var(--border-subtle)] rounded w-24 mb-2" />
            <div className="h-2 bg-[var(--border-subtle)] rounded" />
          </div>
        ))}
      </div>
    );
  }

  if (!data) return null;

  return (
    <div>
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-sm font-bold text-[var(--text-primary)] flex items-center gap-2">
          🎯 KPIs do Ciclo 3
        </h3>
        <span className="text-[10px] font-semibold px-2 py-1 rounded-full bg-[var(--surface-base)] text-[var(--text-secondary)]">
          {data.cycle_pct}% do ciclo decorrido
        </span>
      </div>
      <div className="grid grid-cols-2 lg:grid-cols-3 gap-4">
        {data.kpis.map((kpi, i) => (
          <KpiCard key={i} kpi={kpi} cyclePct={data.cycle_pct} />
        ))}
      </div>
    </div>
  );
}
