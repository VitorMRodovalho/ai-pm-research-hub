/**
 * W105 — Executive Cycle Report (React Island)
 * Auto-generated report for sponsors, PMI Global, and chapters.
 * Print-optimized layout with window.print() PDF export.
 */
import { useState, useEffect } from 'react';

function getSb() { return (window as any).navGetSb?.(); }

interface ReportData {
  cycle: number;
  generated_at: string;
  period: { start: string; end: string };
  overview: any;
  kpis: any;
  tribes: any[];
  gamification: any;
  pilots: any;
  events_timeline: any[];
  platform: any;
}

interface ReportConfig {
  title: string;
  subtitle: string;
  chapters: string;
  gp_notes: string;
  sections: Record<string, boolean>;
}

const DEFAULT_CONFIG: ReportConfig = {
  title: 'Relatório Executivo — Ciclo 3 (2026/1)',
  subtitle: 'Núcleo de Estudos e Pesquisa em IA & Gestão de Projetos',
  chapters: 'PMI-GO · PMI-CE · PMI-DF · PMI-MG · PMI-RS',
  gp_notes: '',
  sections: {
    overview: true, kpis: true, tribes: true, pilots: true,
    gamification: true, events: true, platform: true,
  },
};

// ── Stat Card ──
function StatCard({ label, value, accent }: { label: string; value: string | number; accent?: string }) {
  return (
    <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-3 text-center print:border-gray-300">
      <div className={`text-2xl font-extrabold ${accent || 'text-navy'}`}>{value}</div>
      <div className="text-[10px] uppercase tracking-wide font-semibold text-[var(--text-secondary)] print:text-gray-600">{label}</div>
    </div>
  );
}

// ── Horizontal Bar (inline SVG) ──
function HBar({ items, maxVal }: { items: { label: string; completed: number; inProgress: number; backlog: number }[]; maxVal: number }) {
  const barH = 22;
  const labelW = 100;
  const chartW = 400;
  const h = items.length * (barH + 6) + 10;
  return (
    <svg viewBox={`0 0 ${labelW + chartW + 60} ${h}`} className="w-full max-w-[600px]" style={{ font: '11px sans-serif' }}>
      {items.map((it, i) => {
        const y = i * (barH + 6) + 4;
        const scale = maxVal > 0 ? chartW / maxVal : 0;
        const wC = it.completed * scale;
        const wP = it.inProgress * scale;
        const wB = it.backlog * scale;
        return (
          <g key={i}>
            <text x={labelW - 4} y={y + barH / 2 + 4} textAnchor="end" className="fill-[var(--text-primary)] print:fill-black" style={{ fontSize: '10px' }}>{it.label}</text>
            <rect x={labelW} y={y} width={wC} height={barH} rx={3} fill="#16a34a" />
            <rect x={labelW + wC} y={y} width={wP} height={barH} rx={0} fill="#d97706" />
            <rect x={labelW + wC + wP} y={y} width={wB} height={barH} rx={0} fill="#d1d5db" />
            <text x={labelW + wC + wP + wB + 4} y={y + barH / 2 + 4} className="fill-[var(--text-muted)] print:fill-gray-500" style={{ fontSize: '9px' }}>
              {it.completed}/{it.completed + it.inProgress + it.backlog}
            </text>
          </g>
        );
      })}
    </svg>
  );
}

// ── Events Timeline Bar Chart (inline SVG) ──
function EventsChart({ data }: { data: { month: string; count: number; total_attendees: number }[] }) {
  if (!data || data.length === 0) return <p className="text-sm text-[var(--text-muted)]">Sem dados de eventos.</p>;
  const maxCount = Math.max(...data.map(d => d.count), 1);
  const barW = 40;
  const gap = 8;
  const chartH = 120;
  const svgW = data.length * (barW + gap) + 40;
  return (
    <svg viewBox={`0 0 ${svgW} ${chartH + 30}`} className="w-full max-w-[600px]" style={{ font: '10px sans-serif' }}>
      {data.map((d, i) => {
        const x = i * (barW + gap) + 20;
        const h = (d.count / maxCount) * chartH;
        const y = chartH - h;
        return (
          <g key={i}>
            <rect x={x} y={y} width={barW} height={h} rx={3} fill="#003B5C" />
            <text x={x + barW / 2} y={y - 4} textAnchor="middle" className="fill-[var(--text-primary)] print:fill-black" style={{ fontSize: '9px', fontWeight: 700 }}>{d.count}</text>
            <text x={x + barW / 2} y={chartH + 14} textAnchor="middle" className="fill-[var(--text-muted)] print:fill-gray-600" style={{ fontSize: '8px' }}>{d.month.slice(5)}</text>
          </g>
        );
      })}
    </svg>
  );
}

// ── Progress Bar ──
function ProgressBar({ pct, label }: { pct: number; label?: string }) {
  const clamped = Math.min(Math.max(pct, 0), 100);
  const color = clamped >= 75 ? 'bg-emerald-500' : clamped >= 50 ? 'bg-amber-500' : 'bg-red-500';
  return (
    <div className="w-full">
      {label && <div className="text-xs text-[var(--text-secondary)] mb-1">{label}</div>}
      <div className="w-full h-2 rounded-full bg-gray-200 overflow-hidden">
        <div className={`h-full rounded-full ${color}`} style={{ width: `${clamped}%` }} />
      </div>
      <div className="text-[10px] text-[var(--text-muted)] mt-0.5">{clamped.toFixed(0)}%</div>
    </div>
  );
}

export default function ReportPage() {
  const [data, setData] = useState<ReportData | null>(null);
  const [config, setConfig] = useState<ReportConfig>(DEFAULT_CONFIG);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    let retries = 0;
    const boot = async () => {
      const sb = getSb();
      if (!sb) {
        retries++;
        if (retries < 20) { setTimeout(boot, 200); return; }
        setError('Não foi possível conectar ao servidor.');
        setLoading(false);
        return;
      }

      try {
        // Load report data
        const { data: reportData, error: rpcErr } = await sb.rpc('get_cycle_report', { p_cycle: 3 });
        if (rpcErr) throw rpcErr;
        setData(reportData);

        // Load config from site_config
        const { data: cfgData } = await sb.from('site_config').select('value').eq('key', 'report_config').maybeSingle();
        if (cfgData?.value) {
          setConfig(prev => ({ ...prev, ...cfgData.value }));
        }
      } catch (err: any) {
        console.warn('Report error:', err);
        setError('Erro ao carregar relatório.');
      }
      setLoading(false);
    };
    boot();
  }, []);

  if (loading) return <div className="text-center py-10 text-[var(--text-muted)]">Gerando relatório executivo...</div>;
  if (error) return <div className="text-center py-10 text-red-600">{error}</div>;
  if (!data) return null;

  const { overview, kpis, tribes, gamification, pilots, events_timeline, platform } = data;
  const sec = config.sections;

  // Compute tribe chart data
  const tribeChartItems = (tribes || []).map((t: any) => ({
    label: (() => { const _n = t.name_i18n?.[typeof window !== 'undefined' ? (window.location.pathname.startsWith('/en') ? 'en' : window.location.pathname.startsWith('/es') ? 'es' : 'pt') : 'pt'] || t.name; return _n?.length > 12 ? _n.slice(0, 12) + '…' : _n; })(),
    completed: t.artifacts_completed || 0,
    inProgress: t.artifacts_in_progress || 0,
    backlog: Math.max((t.artifacts_total || 0) - (t.artifacts_completed || 0) - (t.artifacts_in_progress || 0), 0),
  }));
  const maxArtifacts = Math.max(...tribeChartItems.map((t: any) => t.completed + t.inProgress + t.backlog), 1);

  const pilotsData = pilots?.pilots || [];
  const pilotsActive = pilotsData.filter((p: any) => p.status === 'active').length;
  const pilotsTotal = pilotsData.length || 3;

  return (
    <div className="space-y-8">
      {/* ── HEADER ── */}
      <header className="report-section flex items-start justify-between flex-wrap gap-4 print:block">
        <div>
          <h1 className="text-2xl font-extrabold text-navy">{config.title}</h1>
          <p className="text-sm text-[var(--text-secondary)]">{config.subtitle}</p>
          <p className="text-xs text-[var(--text-muted)]">{config.chapters}</p>
          <p className="text-xs text-[var(--text-muted)] mt-1">
            Gerado em: {new Date(data.generated_at).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' })}
          </p>
        </div>
        <button onClick={() => window.print()} className="no-print px-4 py-2 rounded-lg bg-navy text-white text-sm font-semibold cursor-pointer border-0 hover:opacity-90">
          Exportar PDF
        </button>
      </header>

      {/* ── OVERVIEW ── */}
      {sec.overview && overview && (
        <section className="report-section">
          <h2 className="text-lg font-extrabold text-navy mb-3 border-b border-[var(--border-default)] pb-1">Visão Geral</h2>
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
            <StatCard label="Membros Ativos" value={overview.active_members} accent="text-emerald-600" />
            <StatCard label="Tribos" value={overview.tribes} />
            <StatCard label="Capítulos" value={overview.chapters} />
            <StatCard label="Entregáveis" value={overview.artifacts_total} />
            <StatCard label="Eventos" value={overview.events_count} />
          </div>
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-3 mt-3">
            <StatCard label="Presença Total" value={overview.total_attendance} />
            <StatCard label="Horas de Impacto" value={`${overview.total_impact_hours}h`} accent="text-teal-600" />
            <StatCard label="Boards Ativos" value={overview.boards_active} />
          </div>
        </section>
      )}

      {/* ── KPIs ── */}
      {sec.kpis && kpis && (
        <section className="report-section report-section-full">
          <h2 className="text-lg font-extrabold text-navy mb-3 border-b border-[var(--border-default)] pb-1">Metas do Ciclo (KPIs)</h2>
          {kpis.kpis && Array.isArray(kpis.kpis) ? (
            <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
              {kpis.kpis.map((k: any, i: number) => {
                const pct = k.target > 0 ? Math.round((k.current / k.target) * 100) : 0;
                const health = pct >= 75 ? 'emerald' : pct >= 50 ? 'amber' : 'red';
                return (
                  <div key={i} className={`rounded-xl border p-3 bg-${health}-50 border-${health}-200 print:border-gray-300`}>
                    <div className={`text-xl font-extrabold text-${health}-700`}>{k.current}{k.unit || ''}</div>
                    <div className="text-[10px] font-bold uppercase tracking-wide text-[var(--text-secondary)]">{k.name}</div>
                    <ProgressBar pct={pct} />
                    <div className="text-[9px] text-[var(--text-muted)]">Meta: {k.target}{k.unit || ''}</div>
                  </div>
                );
              })}
            </div>
          ) : (
            <p className="text-sm text-[var(--text-muted)]">KPIs não disponíveis.</p>
          )}
        </section>
      )}

      {/* ── TRIBES ── */}
      {sec.tribes && tribes && (
        <section className="report-section report-section-full">
          <h2 className="text-lg font-extrabold text-navy mb-3 border-b border-[var(--border-default)] pb-1">Desempenho por Tribo</h2>
          <div className="overflow-x-auto mb-4">
            <table className="w-full text-xs">
              <thead>
                <tr className="bg-[var(--surface-base)] print:bg-gray-100">
                  <th className="text-left px-3 py-2 font-semibold">Tribo</th>
                  <th className="text-left px-3 py-2 font-semibold">Líder</th>
                  <th className="text-center px-3 py-2 font-semibold">Membros</th>
                  <th className="text-center px-3 py-2 font-semibold">Entregas</th>
                  <th className="text-center px-3 py-2 font-semibold">Concluídos</th>
                  <th className="text-center px-3 py-2 font-semibold">%</th>
                </tr>
              </thead>
              <tbody>
                {tribes.map((t: any, i: number) => (
                  <tr key={i} className="border-t border-[var(--border-subtle)]">
                    <td className="px-3 py-2 font-semibold text-[var(--text-primary)]">{t.name_i18n?.[typeof window !== 'undefined' ? (window.location.pathname.startsWith('/en') ? 'en' : window.location.pathname.startsWith('/es') ? 'es' : 'pt') : 'pt'] || t.name}</td>
                    <td className="px-3 py-2 text-[var(--text-secondary)]">{t.leader}</td>
                    <td className="px-3 py-2 text-center">{t.members_count}</td>
                    <td className="px-3 py-2 text-center">{t.artifacts_total}</td>
                    <td className="px-3 py-2 text-center">{t.artifacts_completed}</td>
                    <td className="px-3 py-2 text-center font-bold">{t.completion_pct}%</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <h3 className="text-sm font-bold text-navy mb-2">Entregas por Tribo</h3>
          <HBar items={tribeChartItems} maxVal={maxArtifacts} />
          <div className="flex gap-4 mt-1 text-[9px] text-[var(--text-muted)]">
            <span><span className="inline-block w-3 h-2 rounded bg-emerald-600 mr-1" />Concluído</span>
            <span><span className="inline-block w-3 h-2 rounded bg-amber-500 mr-1" />Em Andamento</span>
            <span><span className="inline-block w-3 h-2 rounded bg-gray-300 mr-1" />Backlog</span>
          </div>
        </section>
      )}

      {/* ── PILOTS ── */}
      {sec.pilots && pilots && (
        <section className="report-section">
          <h2 className="text-lg font-extrabold text-navy mb-3 border-b border-[var(--border-default)] pb-1">Pilotos de IA</h2>
          <div className="mb-3">
            <div className="text-sm text-[var(--text-secondary)] mb-1">Progresso: {pilotsActive}/{pilotsTotal}</div>
            <ProgressBar pct={(pilotsActive / pilotsTotal) * 100} />
          </div>
          <div className="space-y-2">
            {pilotsData.map((p: any, i: number) => (
              <div key={i} className="flex items-center gap-2 p-2 rounded-lg bg-[var(--surface-base)]">
                <span className={`w-3 h-3 rounded-full ${p.status === 'active' ? 'bg-emerald-500' : p.status === 'completed' ? 'bg-blue-500' : 'bg-gray-300'}`} />
                <span className="text-sm font-bold text-navy">Pilot #{p.pilot_number}</span>
                <span className="text-sm text-[var(--text-secondary)]">{p.title}</span>
                <span className={`ml-auto px-2 py-0.5 rounded-full text-[.6rem] font-bold ${p.status === 'active' ? 'bg-emerald-50 text-emerald-700' : p.status === 'completed' ? 'bg-blue-50 text-blue-700' : 'bg-gray-100 text-gray-500'}`}>
                  {p.status}
                </span>
              </div>
            ))}
          </div>
        </section>
      )}

      {/* ── GAMIFICATION ── */}
      {sec.gamification && gamification && (
        <section className="report-section">
          <h2 className="text-lg font-extrabold text-navy mb-3 border-b border-[var(--border-default)] pb-1">Gamificação & Aprendizado</h2>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-4">
            <StatCard label="XP Total" value={Number(gamification.total_xp_distributed).toLocaleString('pt-BR')} accent="text-purple-600" />
            <StatCard label="Trilha Média" value={`${gamification.trail_completion_avg}%`} />
            <StatCard label="Trilha Completa" value={gamification.members_with_trail_complete} accent="text-emerald-600" />
            <StatCard label="CPMAI Certificados" value={gamification.cpmai_certified} accent="text-blue-600" />
          </div>
          {gamification.top_5 && gamification.top_5.length > 0 && (
            <div>
              <h3 className="text-sm font-bold text-navy mb-2">Top 5 Ranking</h3>
              <div className="space-y-1">
                {gamification.top_5.map((m: any, i: number) => (
                  <div key={i} className="flex items-center justify-between p-2 rounded-lg bg-[var(--surface-base)] text-xs">
                    <span><span className="font-bold text-navy mr-2">{i + 1}.</span>{m.name}</span>
                    <span className="text-[var(--text-muted)]">{m.total_points} XP · {m.tribe_name}</span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </section>
      )}

      {/* ── EVENTS ── */}
      {sec.events && (
        <section className="report-section">
          <h2 className="text-lg font-extrabold text-navy mb-3 border-b border-[var(--border-default)] pb-1">Eventos & Presença</h2>
          <EventsChart data={events_timeline || []} />
        </section>
      )}

      {/* ── PLATFORM ── */}
      {sec.platform && platform && (
        <section className="report-section">
          <h2 className="text-lg font-extrabold text-navy mb-3 border-b border-[var(--border-default)] pb-1">Plataforma (Pilot #1)</h2>
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
            <StatCard label="Stack" value={platform.stack?.split(' + ').slice(0, 2).join(' + ')} />
            <StatCard label="Versão" value={platform.version} />
            <StatCard label="Testes" value={platform.tests_count} accent="text-emerald-600" />
            <StatCard label="Governança" value={`${platform.governance_entries} decisões`} />
            <StatCard label="Custo Mensal" value={platform.zero_cost ? 'R$0' : '—'} accent="text-emerald-600" />
          </div>
        </section>
      )}

      {/* ── GP NOTES ── */}
      {config.gp_notes && (
        <section className="report-section">
          <h2 className="text-sm font-bold text-navy mb-1">Notas do GP</h2>
          <p className="text-xs text-[var(--text-secondary)] whitespace-pre-wrap">{config.gp_notes}</p>
        </section>
      )}

      {/* ── FOOTER ── */}
      <footer className="report-section text-center text-xs text-[var(--text-muted)] pt-4 border-t border-[var(--border-default)]">
        <p>{config.subtitle} · Ciclo {data.cycle} ({data.period.start} — {data.period.end})</p>
        <p>GP: Vitor Maia Rodovalho · Deputy: Fabricio Costa</p>
      </footer>
    </div>
  );
}
