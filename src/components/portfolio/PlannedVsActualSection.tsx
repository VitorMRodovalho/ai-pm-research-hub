import { useState, useEffect, useCallback, useRef, useMemo } from 'react';

function detectLang(): string {
  if (typeof window === 'undefined') return 'pt-BR';
  if (location.pathname.startsWith('/en')) return 'en-US';
  if (location.pathname.startsWith('/es')) return 'es-LATAM';
  return 'pt-BR';
}

const L: Record<string, Record<string, string>> = {
  'pt-BR': { deliverables:'Entregáveis', completed:'Concluídos', spi:'SPI', avgDev:'Desvio Médio', planned:'Planejado', inProgress:'Em Andamento', onTime:'No Prazo', atRisk:'Em Risco', delayed:'Atrasado', deviation:'Desvio', tribe:'Tribo', total:'Total', loading:'Carregando...', noData:'Nenhum dado disponível.' },
  'en-US': { deliverables:'Deliverables', completed:'Completed', spi:'SPI', avgDev:'Avg Deviation', planned:'Planned', inProgress:'In Progress', onTime:'On Time', atRisk:'At Risk', delayed:'Delayed', deviation:'Deviation', tribe:'Tribe', total:'Total', loading:'Loading...', noData:'No data available.' },
  'es-LATAM': { deliverables:'Entregables', completed:'Completados', spi:'SPI', avgDev:'Desviación Media', planned:'Planificado', inProgress:'En Progreso', onTime:'A Tiempo', atRisk:'En Riesgo', delayed:'Retrasado', deviation:'Desviación', tribe:'Tribu', total:'Total', loading:'Cargando...', noData:'Sin datos disponibles.' },
};

interface TribeData {
  tribe_id: number;
  tribe_name: string;
  total_cards: number;
  portfolio_cards: number;
  planned: number;
  in_progress: number;
  done: number;
  backlog: number;
  on_time: number;
  at_risk: number;
  delayed: number;
  avg_deviation_days: number;
  spi: number;
  completion_pct: number;
}

export default function PlannedVsActualSection() {
  const l = useMemo(() => L[detectLang()] || L['pt-BR'], []);
  const [data, setData] = useState<TribeData[]>([]);
  const [loading, setLoading] = useState(true);
  const chartRef = useRef<HTMLCanvasElement>(null);
  const chartInstance = useRef<any>(null);

  const load = useCallback(async () => {
    const sb = (window as any).navGetSb?.();
    if (!sb) { setTimeout(load, 300); return; }
    setLoading(true);
    const { data: d } = await sb.rpc('get_portfolio_planned_vs_actual', { p_cycle: 3 });
    if (Array.isArray(d)) setData(d);
    setLoading(false);
  }, []);

  useEffect(() => { load(); }, [load]);

  // Chart.js
  useEffect(() => {
    if (!data.length || !chartRef.current) return;
    const renderChart = async () => {
      const { Chart, BarController, BarElement, CategoryScale, LinearScale, Tooltip, Legend } = await import('chart.js');
      Chart.register(BarController, BarElement, CategoryScale, LinearScale, Tooltip, Legend);
      if (chartInstance.current) chartInstance.current.destroy();
      const isDark = document.documentElement.classList.contains('dark');
      const textColor = isDark ? '#c2c0b6' : '#3d3d3a';
      chartInstance.current = new Chart(chartRef.current!, {
        type: 'bar',
        data: {
          labels: data.map(t => t.tribe_name),
          datasets: [
            { label: l.planned, data: data.map(t => t.planned), backgroundColor: '#3b82f6' },
            { label: l.completed, data: data.map(t => t.done), backgroundColor: '#22c55e' },
            { label: l.inProgress, data: data.map(t => t.in_progress), backgroundColor: '#eab308' },
          ],
        },
        options: {
          indexAxis: 'y',
          responsive: true,
          maintainAspectRatio: false,
          plugins: { legend: { labels: { color: textColor } } },
          scales: {
            x: { stacked: false, ticks: { color: textColor } },
            y: { ticks: { color: textColor, font: { size: 11 } } },
          },
        },
      });
    };
    renderChart();
    return () => { if (chartInstance.current) chartInstance.current.destroy(); };
  }, [data]);

  if (loading) return <p className="text-sm text-[var(--text-muted)]">{l.loading}</p>;
  if (!data.length) return <p className="text-sm text-[var(--text-muted)]">{l.noData}</p>;

  const totals = data.reduce(
    (acc, t) => ({
      portfolio: acc.portfolio + t.portfolio_cards,
      done: acc.done + t.done,
      inProgress: acc.inProgress + t.in_progress,
      onTime: acc.onTime + t.on_time,
      atRisk: acc.atRisk + t.at_risk,
      delayed: acc.delayed + t.delayed,
      avgDev: acc.avgDev + t.avg_deviation_days,
    }),
    { portfolio: 0, done: 0, inProgress: 0, onTime: 0, atRisk: 0, delayed: 0, avgDev: 0 }
  );
  const avgDev = data.length ? Math.round(totals.avgDev / data.length) : 0;
  const spi = totals.portfolio > 0 ? (totals.done / totals.portfolio).toFixed(2) : '0.00';
  const completionPct = totals.portfolio > 0 ? Math.round((totals.done / totals.portfolio) * 100) : 0;

  return (
    <div className="space-y-5">
      {/* Summary cards */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-base)] p-3 text-center">
          <div className="text-2xl font-black text-[var(--text-primary)]">{totals.portfolio}</div>
          <div className="text-[10px] text-[var(--text-muted)] font-semibold uppercase">{l.deliverables}</div>
        </div>
        <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-base)] p-3 text-center">
          <div className="text-2xl font-black text-emerald-600">{totals.done}</div>
          <div className="text-[10px] text-[var(--text-muted)] font-semibold uppercase">{l.completed} ({completionPct}%)</div>
        </div>
        <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-base)] p-3 text-center">
          <div className={`text-2xl font-black ${parseFloat(spi) >= 1 ? 'text-emerald-600' : parseFloat(spi) >= 0.5 ? 'text-amber-600' : 'text-red-600'}`}>{spi}</div>
          <div className="text-[10px] text-[var(--text-muted)] font-semibold uppercase" title={l.spi}>{l.spi}</div>
        </div>
        <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-base)] p-3 text-center">
          <div className={`text-2xl font-black ${avgDev <= 0 ? 'text-emerald-600' : avgDev <= 7 ? 'text-amber-600' : 'text-red-600'}`}>{avgDev}d</div>
          <div className="text-[10px] text-[var(--text-muted)] font-semibold uppercase">{l.avgDev}</div>
        </div>
      </div>

      {/* Chart */}
      <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-base)] p-4" style={{ height: `${Math.max(200, data.length * 50 + 60)}px` }}>
        <canvas ref={chartRef} />
      </div>

      {/* Table */}
      <div className="overflow-x-auto rounded-xl border border-[var(--border-default)]">
        <table className="w-full text-[11px]">
          <thead>
            <tr className="bg-[var(--surface-section-cool)]">
              <th className="px-3 py-2 text-left font-bold text-[var(--text-secondary)]">{l.tribe}</th>
              <th className="px-2 py-2 text-center font-bold text-[var(--text-secondary)]">{l.deliverables}</th>
              <th className="px-2 py-2 text-center font-bold text-[var(--text-secondary)]">{l.completed}</th>
              <th className="px-2 py-2 text-center font-bold text-[var(--text-secondary)]">{l.inProgress}</th>
              <th className="px-2 py-2 text-center font-bold text-emerald-600">{l.onTime}</th>
              <th className="px-2 py-2 text-center font-bold text-amber-600">{l.atRisk}</th>
              <th className="px-2 py-2 text-center font-bold text-red-600">{l.delayed}</th>
              <th className="px-2 py-2 text-center font-bold text-[var(--text-secondary)]">{l.deviation}</th>
              <th className="px-2 py-2 text-center font-bold text-[var(--text-secondary)]">SPI</th>
            </tr>
          </thead>
          <tbody>
            {data.map((t) => {
              const health = t.portfolio_cards > 0
                ? t.on_time / t.portfolio_cards >= 0.8 ? '🟢' : t.on_time / t.portfolio_cards >= 0.5 ? '🟡' : '🔴'
                : '⚪';
              return (
                <tr key={t.tribe_id} className="border-t border-[var(--border-subtle)] hover:bg-[var(--surface-hover)]">
                  <td className="px-3 py-2 font-medium text-[var(--text-primary)]">{health} {t.tribe_name}</td>
                  <td className="px-2 py-2 text-center">{t.portfolio_cards}</td>
                  <td className="px-2 py-2 text-center text-emerald-600 font-bold">{t.done}</td>
                  <td className="px-2 py-2 text-center text-amber-600">{t.in_progress}</td>
                  <td className="px-2 py-2 text-center">{t.on_time}</td>
                  <td className="px-2 py-2 text-center">{t.at_risk}</td>
                  <td className="px-2 py-2 text-center">{t.delayed}</td>
                  <td className="px-2 py-2 text-center">{t.avg_deviation_days}d</td>
                  <td className="px-2 py-2 text-center font-bold">{t.spi.toFixed(2)}</td>
                </tr>
              );
            })}
            <tr className="border-t-2 border-[var(--border-default)] bg-[var(--surface-section-cool)] font-bold">
              <td className="px-3 py-2">{l.total}</td>
              <td className="px-2 py-2 text-center">{totals.portfolio}</td>
              <td className="px-2 py-2 text-center text-emerald-600">{totals.done}</td>
              <td className="px-2 py-2 text-center text-amber-600">{totals.inProgress}</td>
              <td className="px-2 py-2 text-center">{totals.onTime}</td>
              <td className="px-2 py-2 text-center">{totals.atRisk}</td>
              <td className="px-2 py-2 text-center">{totals.delayed}</td>
              <td className="px-2 py-2 text-center">{avgDev}d</td>
              <td className="px-2 py-2 text-center">{spi}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  );
}
