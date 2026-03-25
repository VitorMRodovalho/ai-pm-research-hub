import { useState, useEffect, useCallback, useRef } from 'react';

interface Props { lang?: string; }

function useLang(propLang?: string): string {
  if (propLang) return propLang;
  if (typeof window !== 'undefined') {
    if (location.pathname.startsWith('/en')) return 'en-US';
    if (location.pathname.startsWith('/es')) return 'es-LATAM';
    const p = new URLSearchParams(location.search).get('lang');
    if (p) return p;
  }
  return 'pt-BR';
}

const T: Record<string, Record<string, string>> = {
  'pt-BR': {
    subtitle: 'Visão executiva da contribuição do seu capítulo ao Núcleo.',
    cycle: 'Ciclo 3', print: 'Imprimir', selectChapter: 'Selecionar capítulo',
    members: 'Membros Ativos', output: 'Produção Científica', attendance: 'Taxa de Presença',
    hours: 'Horas Contribuídas', pdu: 'PDUs (máx 25)', certs: 'Certificações PMI',
    partnerships: 'Parcerias', gamification: 'Gamificação', avgXp: 'XP Médio',
    active: 'Ativas', negotiation: 'Em negociação', trail: 'Trilha IA',
    compTitle: 'Seu Capítulo vs Média do Núcleo', compChapter: 'Capítulo', compHub: 'Núcleo',
    membersTitle: 'Membros do Capítulo', name: 'Nome', role: 'Papel', xp: 'XP',
    attendanceLbl: 'Presença', trailLbl: 'Trilha', topTitle: 'Top Contribuidores',
    noData: 'Sem dados para este capítulo.', loading: 'Carregando...',
    observers: 'Observadores', alumni: 'Alumni', completed: 'Cards concluídos',
    publications: 'Publicações', hubAvg: 'vs Núcleo',
  },
  'en-US': {
    subtitle: 'Executive view of your chapter contribution to the Hub.',
    cycle: 'Cycle 3', print: 'Print', selectChapter: 'Select chapter',
    members: 'Active Members', output: 'Research Output', attendance: 'Attendance Rate',
    hours: 'Hours Contributed', pdu: 'PDUs (max 25)', certs: 'PMI Certifications',
    partnerships: 'Partnerships', gamification: 'Gamification', avgXp: 'Avg XP',
    active: 'Active', negotiation: 'In negotiation', trail: 'AI Trail',
    compTitle: 'Your Chapter vs Hub Average', compChapter: 'Chapter', compHub: 'Hub',
    membersTitle: 'Chapter Members', name: 'Name', role: 'Role', xp: 'XP',
    attendanceLbl: 'Attendance', trailLbl: 'Trail', topTitle: 'Top Contributors',
    noData: 'No data for this chapter.', loading: 'Loading...',
    observers: 'Observers', alumni: 'Alumni', completed: 'Cards completed',
    publications: 'Publications', hubAvg: 'vs Hub',
  },
  'es-LATAM': {
    subtitle: 'Vista ejecutiva de la contribución de su capítulo al Hub.',
    cycle: 'Ciclo 3', print: 'Imprimir', selectChapter: 'Seleccionar capítulo',
    members: 'Miembros Activos', output: 'Producción Científica', attendance: 'Tasa de Asistencia',
    hours: 'Horas Contribuidas', pdu: 'PDUs (máx 25)', certs: 'Certificaciones PMI',
    partnerships: 'Alianzas', gamification: 'Gamificación', avgXp: 'XP Promedio',
    active: 'Activas', negotiation: 'En negociación', trail: 'Ruta IA',
    compTitle: 'Su Capítulo vs Promedio del Hub', compChapter: 'Capítulo', compHub: 'Hub',
    membersTitle: 'Miembros del Capítulo', name: 'Nombre', role: 'Rol', xp: 'XP',
    attendanceLbl: 'Asistencia', trailLbl: 'Ruta', topTitle: 'Top Contribuidores',
    noData: 'Sin datos para este capítulo.', loading: 'Cargando...',
    observers: 'Observadores', alumni: 'Egresados', completed: 'Cards completados',
    publications: 'Publicaciones', hubAvg: 'vs Hub',
  },
};

function MetricCard({ value, label, sub, icon }: { value: string | number; label: string; sub?: string; icon: string }) {
  return (
    <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-base)] p-4">
      <div className="flex items-center gap-2 mb-2">
        <span className="text-lg">{icon}</span>
        <span className="text-[10px] font-bold uppercase tracking-wide text-[var(--text-muted)]">{label}</span>
      </div>
      <div className="text-2xl font-black text-[var(--text-primary)]">{value}</div>
      {sub && <div className="text-[10px] text-[var(--text-muted)] mt-1">{sub}</div>}
    </div>
  );
}

export default function ChapterDashboard({ lang: propLang }: Props) {
  const lang = useLang(propLang);
  const t = T[lang] || T['pt-BR'];
  const dateLocale = lang === 'en-US' ? 'en-US' : lang === 'es-LATAM' ? 'es' : 'pt-BR';
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [chapter, setChapter] = useState<string | null>(null);
  const [isGP, setIsGP] = useState(false);
  const chartRef = useRef<HTMLCanvasElement>(null);
  const chartInst = useRef<any>(null);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const load = useCallback(async (ch?: string) => {
    const sb = getSb(); if (!sb) { setTimeout(() => load(ch), 300); return; }
    setLoading(true);
    const { data: d } = await sb.rpc('get_chapter_dashboard', { p_chapter: ch || null });
    if (d && !d.error) { setData(d); setChapter(d.chapter); }
    setLoading(false);
  }, [getSb]);

  useEffect(() => {
    const boot = () => {
      const m = (window as any).navGetMember?.();
      if (m) {
        setIsGP(m.is_superadmin || ['manager', 'deputy_manager'].includes(m.operational_role));
        load();
      } else setTimeout(boot, 400);
    };
    boot();
  }, [load]);

  // Chart
  useEffect(() => {
    if (!data || !chartRef.current) return;
    const renderChart = async () => {
      const { Chart, BarController, BarElement, CategoryScale, LinearScale, Tooltip, Legend } = await import('chart.js');
      Chart.register(BarController, BarElement, CategoryScale, LinearScale, Tooltip, Legend);
      if (chartInst.current) chartInst.current.destroy();
      const isDark = document.documentElement.classList.contains('dark');
      const textColor = isDark ? '#c2c0b6' : '#3d3d3a';
      const p = data.people || {};
      const a = data.attendance || {};
      const g = data.gamification || {};
      chartInst.current = new Chart(chartRef.current!, {
        type: 'bar',
        data: {
          labels: [t.members, t.attendance, t.avgXp],
          datasets: [
            { label: t.compChapter, data: [p.active || 0, a.rate_pct || 0, g.avg_xp || 0], backgroundColor: '#0d9488' },
            { label: t.compHub, data: [p.hub_total || 0, 70, g.hub_avg_xp || 0], backgroundColor: '#94a3b8' },
          ],
        },
        options: { indexAxis: 'y', responsive: true, maintainAspectRatio: false,
          plugins: { legend: { labels: { color: textColor } } },
          scales: { x: { ticks: { color: textColor } }, y: { ticks: { color: textColor } } },
        },
      });
    };
    renderChart();
    return () => { if (chartInst.current) chartInst.current.destroy(); };
  }, [data, t]);

  if (loading) return <div className="text-center py-12 text-[var(--text-muted)]">{t.loading}</div>;
  if (!data) return <div className="text-center py-12 text-[var(--text-muted)]">{t.noData}</div>;

  const p = data.people || {};
  const o = data.output || {};
  const a = data.attendance || {};
  const h = data.hours || {};
  const c = data.certifications || {};
  const pr = data.partnerships || {};
  const g = data.gamification || {};
  const members = data.members || [];

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3 print:mb-4">
        <div>
          <h1 className="text-xl font-extrabold text-navy print:text-2xl">{data.chapter}</h1>
          <p className="text-xs text-[var(--text-secondary)]">{t.subtitle}</p>
          <span className="text-[10px] text-[var(--text-muted)]">{t.cycle} · {new Date().toLocaleDateString(dateLocale, { month: 'long', year: 'numeric' })}</span>
        </div>
        <div className="flex items-center gap-2 no-print">
          {isGP && data.available_chapters && (
            <select value={chapter || ''} onChange={(e) => load(e.target.value)}
              className="text-xs rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] px-2 py-1.5">
              {(data.available_chapters || []).map((ch: string) => <option key={ch} value={ch}>{ch}</option>)}
            </select>
          )}
          <button onClick={() => window.print()} className="px-3 py-1.5 rounded-lg border border-[var(--border-default)] text-xs font-semibold cursor-pointer bg-transparent hover:bg-[var(--surface-hover)] no-print">
            🖨️ {t.print}
          </button>
        </div>
      </div>

      {/* Metric Cards */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 metric-cards">
        <MetricCard icon="👥" label={t.members} value={p.active || 0} sub={`${p.observers || 0} ${t.observers} · ${p.alumni || 0} ${t.alumni}`} />
        <MetricCard icon="📄" label={t.output} value={o.board_cards_completed || 0} sub={`${o.publications_submitted || 0} ${t.publications}`} />
        <MetricCard icon="📊" label={t.attendance} value={`${a.rate_pct || 0}%`} sub={`${a.total_events_attended || 0} events`} />
        <MetricCard icon="⏱️" label={t.hours} value={`${h.total_hours || 0}h`} sub={`${t.pdu}: ${h.pdu_equivalent || 0}`} />
        <MetricCard icon="🎓" label={t.certs} value={c.total_certs || 0} sub={`PMP: ${c.pmp || 0} · CPMAI: ${c.cpmai || 0}`} />
        <MetricCard icon="🤝" label={t.partnerships} value={pr.total || 0} sub={`${pr.active || 0} ${t.active} · ${pr.negotiation || 0} ${t.negotiation}`} />
        <MetricCard icon="🏆" label={t.gamification} value={g.avg_xp || 0} sub={`${t.hubAvg}: ${g.hub_avg_xp || 0}`} />
      </div>

      {/* Comparison Chart */}
      <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-base)] p-4">
        <h2 className="text-sm font-bold text-navy mb-3">{t.compTitle}</h2>
        <div style={{ height: '180px' }}><canvas ref={chartRef} /></div>
      </div>

      {/* Top Contributors */}
      {g.top_contributors && g.top_contributors.length > 0 && (
        <div>
          <h2 className="text-sm font-bold text-navy mb-2">{t.topTitle}</h2>
          <div className="flex gap-3">
            {g.top_contributors.map((tc: any, i: number) => (
              <div key={i} className="flex items-center gap-2 px-3 py-2 rounded-lg bg-[var(--surface-section-cool)] border border-[var(--border-subtle)]">
                {tc.photo_url ? <img src={tc.photo_url} className="w-8 h-8 rounded-full object-cover" alt="" /> : <div className="w-8 h-8 rounded-full bg-teal/20 flex items-center justify-center text-teal text-xs font-bold">{(tc.name || '?')[0]}</div>}
                <div>
                  <div className="text-xs font-semibold text-[var(--text-primary)]">{tc.name}</div>
                  <div className="text-[10px] text-[var(--text-muted)]">{tc.total_xp} XP</div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Member Table */}
      <div className="member-table">
        <h2 className="text-sm font-bold text-navy mb-2">{t.membersTitle}</h2>
        <div className="overflow-x-auto rounded-xl border border-[var(--border-default)]">
          <table className="w-full text-[11px]">
            <thead>
              <tr className="bg-[var(--surface-section-cool)]">
                <th className="px-3 py-2 text-left font-bold text-[var(--text-secondary)]">{t.name}</th>
                <th className="px-2 py-2 text-center font-bold text-[var(--text-secondary)]">{t.role}</th>
                <th className="px-2 py-2 text-center font-bold text-[var(--text-secondary)]">{t.xp}</th>
                <th className="px-2 py-2 text-center font-bold text-[var(--text-secondary)]">{t.attendanceLbl}</th>
                <th className="px-2 py-2 text-center font-bold text-[var(--text-secondary)]">{t.trailLbl}</th>
              </tr>
            </thead>
            <tbody>
              {members.map((m: any) => (
                <tr key={m.id} className="border-t border-[var(--border-subtle)] hover:bg-[var(--surface-hover)]">
                  <td className="px-3 py-2 font-medium text-[var(--text-primary)]">{m.name}</td>
                  <td className="px-2 py-2 text-center text-[var(--text-secondary)]">{m.operational_role}</td>
                  <td className="px-2 py-2 text-center font-bold">{m.total_xp}</td>
                  <td className="px-2 py-2 text-center">{m.attendance_pct}%</td>
                  <td className="px-2 py-2 text-center">{m.trail_count}/7</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Print CSS */}
      <style>{`
        @media print {
          nav, .admin-sidebar, .no-print, button { display: none !important; }
          body, main { background: white !important; color: black !important; }
          .metric-cards { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; }
          canvas { max-width: 100%; }
          .member-table { page-break-before: always; }
        }
      `}</style>
    </div>
  );
}
