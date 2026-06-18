import { useState, useEffect, useCallback, useRef } from 'react';

interface Props { lang?: string; stakeholderMode?: boolean; }

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
    cycle: 'Ciclo', print: 'Imprimir', csv: 'Exportar CSV', selectChapter: 'Selecionar capítulo',
    members: 'Membros Ativos', output: 'Produção Científica', attendance: 'Participação',
    hours: 'Horas Contribuídas', pdu: 'PDUs (máx 25)', certs: 'Certificações PMI',
    partnerships: 'Parcerias', gamification: 'Gamificação', avgXp: 'XP Médio',
    active: 'Ativas', negotiation: 'Em negociação', trail: 'Trilha IA',
    compTitle: 'Seu Capítulo vs Média do Núcleo', compChapter: 'Capítulo', compHub: 'Núcleo',
    membersTitle: 'Membros do Capítulo', name: 'Nome', role: 'Papel', xp: 'XP',
    trailLbl: 'Trilha', topTitle: 'Top Contribuidores',
    noData: 'Sem dados para este capítulo.', loading: 'Carregando...',
    observers: 'Observadores', alumni: 'Alumni', completed: 'Cards concluídos',
    publications: 'Publicações', hubAvg: 'vs Núcleo', other: 'Outros',
    reliabilityLbl: 'Confiabilidade',
    mvTitle: 'Movimentações (30 dias)', mvEntries: 'Entradas', mvExits: 'Saídas',
    mvReturn: 'Quer voltar', mvEmpty: 'Sem movimentações nos últimos 30 dias.',
    byTribeTitle: 'Membros por Tribo', noTribe: 'Sem tribo',
    scriptTitle: 'Script de divulgação', scriptHint: 'Copie e compartilhe para divulgar seu capítulo.',
    scriptCopy: 'Copiar', scriptCopied: 'Copiado!',
    pipelineTitle: 'Processo Seletivo', pipelineDeadline: 'Encerra em', pipelineApps: 'candidaturas',
    pipelineBooking: 'Link de agendamento', pipelineEmpty: 'Nenhum ciclo de seleção em andamento.',
    pipelineLast: 'Último ciclo encerrou em',
  },
  'en-US': {
    subtitle: 'Executive view of your chapter contribution to the Hub.',
    cycle: 'Cycle', print: 'Print', csv: 'Export CSV', selectChapter: 'Select chapter',
    members: 'Active Members', output: 'Research Output', attendance: 'Participation',
    hours: 'Hours Contributed', pdu: 'PDUs (max 25)', certs: 'PMI Certifications',
    partnerships: 'Partnerships', gamification: 'Gamification', avgXp: 'Avg XP',
    active: 'Active', negotiation: 'In negotiation', trail: 'AI Trail',
    compTitle: 'Your Chapter vs Hub Average', compChapter: 'Chapter', compHub: 'Hub',
    membersTitle: 'Chapter Members', name: 'Name', role: 'Role', xp: 'XP',
    trailLbl: 'Trail', topTitle: 'Top Contributors',
    noData: 'No data for this chapter.', loading: 'Loading...',
    observers: 'Observers', alumni: 'Alumni', completed: 'Cards completed',
    publications: 'Publications', hubAvg: 'vs Hub', other: 'Other',
    reliabilityLbl: 'Reliability',
    mvTitle: 'Movements (30 days)', mvEntries: 'Joined', mvExits: 'Left',
    mvReturn: 'Open to return', mvEmpty: 'No movements in the last 30 days.',
    byTribeTitle: 'Members by Tribe', noTribe: 'No tribe',
    scriptTitle: 'Outreach script', scriptHint: 'Copy and share to promote your chapter.',
    scriptCopy: 'Copy', scriptCopied: 'Copied!',
    pipelineTitle: 'Selection Process', pipelineDeadline: 'Closes on', pipelineApps: 'applications',
    pipelineBooking: 'Booking link', pipelineEmpty: 'No selection cycle in progress.',
    pipelineLast: 'Last cycle closed on',
  },
  'es-LATAM': {
    subtitle: 'Vista ejecutiva de la contribución de su capítulo al Hub.',
    cycle: 'Ciclo', print: 'Imprimir', csv: 'Exportar CSV', selectChapter: 'Seleccionar capítulo',
    members: 'Miembros Activos', output: 'Producción Científica', attendance: 'Participación',
    hours: 'Horas Contribuidas', pdu: 'PDUs (máx 25)', certs: 'Certificaciones PMI',
    partnerships: 'Alianzas', gamification: 'Gamificación', avgXp: 'XP Promedio',
    active: 'Activas', negotiation: 'En negociación', trail: 'Ruta IA',
    compTitle: 'Su Capítulo vs Promedio del Hub', compChapter: 'Capítulo', compHub: 'Hub',
    membersTitle: 'Miembros del Capítulo', name: 'Nombre', role: 'Rol', xp: 'XP',
    trailLbl: 'Ruta', topTitle: 'Top Contribuidores',
    noData: 'Sin datos para este capítulo.', loading: 'Cargando...',
    observers: 'Observadores', alumni: 'Egresados', completed: 'Cards completados',
    publications: 'Publicaciones', hubAvg: 'vs Hub', other: 'Otros',
    reliabilityLbl: 'Confiabilidad',
    mvTitle: 'Movimientos (30 días)', mvEntries: 'Entradas', mvExits: 'Salidas',
    mvReturn: 'Quiere volver', mvEmpty: 'Sin movimientos en los últimos 30 días.',
    byTribeTitle: 'Miembros por Tribu', noTribe: 'Sin tribu',
    scriptTitle: 'Script de divulgación', scriptHint: 'Copia y comparte para difundir tu capítulo.',
    scriptCopy: 'Copiar', scriptCopied: '¡Copiado!',
    pipelineTitle: 'Proceso de Selección', pipelineDeadline: 'Cierra el', pipelineApps: 'candidaturas',
    pipelineBooking: 'Enlace de agenda', pipelineEmpty: 'Ningún ciclo de selección en curso.',
    pipelineLast: 'Último ciclo cerró el',
  },
};

// Offboard reason labels per language (the RPC neutralizes health/policy_violation → 'other'
// server-side for LGPD, so those never reach the FE). Mirrors offboard_reason_categories.label_*.
const REASONS: Record<string, Record<string, string>> = {
  'pt-BR': {
    end_of_cycle: 'Fim de ciclo', personal_agenda: 'Agenda pessoal', personal_workload: 'Sobrecarga profissional',
    academic_conflict: 'Conflito acadêmico', relocation: 'Mudança de localidade', external_priority: 'Prioridade externa',
    lack_of_fit: 'Falta de fit', other: 'Outros',
  },
  'en-US': {
    end_of_cycle: 'End of cycle', personal_agenda: 'Personal agenda', personal_workload: 'Work overload',
    academic_conflict: 'Academic conflict', relocation: 'Relocation', external_priority: 'External priority',
    lack_of_fit: 'Lack of fit', other: 'Other',
  },
  'es-LATAM': {
    end_of_cycle: 'Fin de ciclo', personal_agenda: 'Agenda personal', personal_workload: 'Sobrecarga profesional',
    academic_conflict: 'Conflicto académico', relocation: 'Mudanza', external_priority: 'Prioridad externa',
    lack_of_fit: 'Falta de fit', other: 'Otros',
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

export default function ChapterDashboard({ lang: propLang, stakeholderMode }: Props) {
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
            { label: t.compChapter, data: [p.active || 0, a.engagement?.avg_rate != null ? Math.round(a.engagement.avg_rate * 100) : 0, g.avg_xp || 0], backgroundColor: '#0d9488' },
            { label: t.compHub, data: [p.hub_total || 0, a.hub_engagement_pct || 0, g.hub_avg_xp || 0], backgroundColor: '#94a3b8' },
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

  // #106 PR1: instrumentation — fire once when the dashboard data first loads (product-leader).
  const viewedRef = useRef(false);
  useEffect(() => {
    if (data && !data.error && !viewedRef.current) {
      viewedRef.current = true;
      const m = (window as any).navGetMember?.();
      (window as any).__nucleoTrack?.('chapter_dashboard_viewed', {
        chapter_code: data.chapter,
        is_own_chapter: m?.chapter === data.chapter,
        designation: Array.isArray(m?.designations) ? m.designations.join(',') : null,
      });
    }
  }, [data]);

  // #106 PR2 Bloco 4: outreach script (read-only here; GP edits on /admin/settings). Global key
  // via the narrow get_chapter_outreach_script reader (platform_settings is deny-all RLS).
  const [script, setScript] = useState<Record<string, string> | null>(null);
  const [scriptTab, setScriptTab] = useState<string>(lang);
  const [copied, setCopied] = useState(false);
  const fetchScript = useCallback(async () => {
    const sb = getSb(); if (!sb) { setTimeout(fetchScript, 400); return; }
    const { data } = await sb.rpc('get_chapter_outreach_script');
    if (data && typeof data === 'object') setScript(data as Record<string, string>);
  }, [getSb]);
  useEffect(() => { fetchScript(); }, [fetchScript]);

  // #106 PR3 Bloco 3: selection pipeline summary (separate lazy RPC; same chapter as the dashboard).
  const [pipeline, setPipeline] = useState<any>(null);
  const fetchPipeline = useCallback(async () => {
    const sb = getSb(); if (!sb) { setTimeout(fetchPipeline, 400); return; }
    const { data } = await sb.rpc('get_chapter_selection_summary', { p_chapter: chapter || null });
    if (data && !data.error) setPipeline(data);
  }, [getSb, chapter]);
  useEffect(() => { fetchPipeline(); }, [fetchPipeline]);

  const copyScript = useCallback(() => {
    const text = script?.[scriptTab] || '';
    if (!text || !navigator.clipboard) return;
    navigator.clipboard.writeText(text).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
      (window as any).__nucleoTrack?.('chapter_script_copied', { lang: scriptTab });
    });
  }, [script, scriptTab]);

  // #106 PR1 Bloco 5: CSV export of the already-loaded member list (FE-only, no extra RPC).
  const exportCsv = useCallback(() => {
    const rows = (data?.members || []) as any[];
    const esc = (v: any) => `"${String(v ?? '').replace(/"/g, '""')}"`;
    const header = [t.name, t.role, t.xp, t.attendance, t.trailLbl].map(esc).join(',');
    const lines = [header].concat(
      rows.map((m: any) => [m.name, m.operational_role, m.total_xp, `${m.attendance_pct}%`, `${m.trail_count}/7`].map(esc).join(','))
    );
    const blob = new Blob(['﻿' + lines.join('\r\n')], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `chapter_${data?.chapter || 'export'}_${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
    (window as any).__nucleoTrack?.('chapter_csv_exported', { chapter_code: data?.chapter, rows: rows.length });
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
  const mv = data.movements || {};
  const mvEntries = (mv.entries || []) as any[];
  const mvExits = (mv.exits || []) as any[];
  const byTribeEntries = Object.entries((p.by_tribe || {}) as Record<string, number>).sort((a, b) => b[1] - a[1]);
  const reasonLabel = (code: string) => (REASONS[lang] || REASONS['pt-BR'])[code] || code;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3 print:mb-4">
        <div>
          <h1 className="text-xl font-extrabold text-navy print:text-2xl">{data.chapter}</h1>
          <p className="text-xs text-[var(--text-secondary)]">{t.subtitle}</p>
          <span className="text-[10px] text-[var(--text-muted)]">{data.cycle_label || t.cycle} · {new Date().toLocaleDateString(dateLocale, { month: 'long', year: 'numeric' })}</span>
        </div>
        <div className="flex items-center gap-2 no-print">
          {isGP && data.available_chapters && (
            <select value={chapter || ''} onChange={(e) => load(e.target.value)}
              className="text-xs rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] px-2 py-1.5">
              {(data.available_chapters || []).map((ch: string) => <option key={ch} value={ch}>{ch}</option>)}
            </select>
          )}
          <button onClick={exportCsv} className="px-3 py-1.5 rounded-lg border border-[var(--border-default)] text-xs font-semibold cursor-pointer bg-transparent hover:bg-[var(--surface-hover)] no-print">
            ⬇️ {t.csv}
          </button>
          <button onClick={() => window.print()} className="px-3 py-1.5 rounded-lg border border-[var(--border-default)] text-xs font-semibold cursor-pointer bg-transparent hover:bg-[var(--surface-hover)] no-print">
            🖨️ {t.print}
          </button>
        </div>
      </div>

      {/* Metric Cards */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 metric-cards">
        <MetricCard icon="👥" label={t.members} value={p.active || 0} sub={`${p.observers || 0} ${t.observers} · ${p.alumni || 0} ${t.alumni}`} />
        <MetricCard icon="📄" label={t.output} value={o.board_cards_completed || 0} sub={`${o.publications_submitted || 0} ${t.publications}`} />
        <MetricCard icon="📊" label={t.attendance} value={`${a.engagement?.avg_rate != null ? Math.round(a.engagement.avg_rate * 100) : 0}%`} sub={`${t.reliabilityLbl} ${a.reliability?.avg_rate != null ? Math.round(a.reliability.avg_rate * 100) : '—'}% · P${a.reliability?.present_total ?? 0}/A${a.reliability?.absent_total ?? 0}/E${a.reliability?.excused_total ?? 0}`} />
        <MetricCard icon="⏱️" label={t.hours} value={`${h.total_hours || 0}h`} sub={`${t.pdu}: ${h.pdu_equivalent || 0}`} />
        <MetricCard icon="🎓" label={t.certs} value={c.total_certs || 0} sub={`PMP: ${c.pmp || 0} · CPMAI: ${c.cpmai || 0}${(c.total_certs || 0) - (c.pmp || 0) - (c.cpmai || 0) > 0 ? ` · ${t.other}: ${(c.total_certs || 0) - (c.pmp || 0) - (c.cpmai || 0)}` : ''}`} />
        <MetricCard icon="🤝" label={t.partnerships} value={pr.total || 0} sub={`${pr.active || 0} ${t.active} · ${pr.negotiation || 0} ${t.negotiation}${(pr.total || 0) - (pr.active || 0) - (pr.negotiation || 0) > 0 ? ` · ${(pr.total || 0) - (pr.active || 0) - (pr.negotiation || 0)} ${t.other}` : ''}`} />
        <MetricCard icon="🏆" label={t.gamification} value={g.avg_xp || 0} sub={`${t.hubAvg}: ${g.hub_avg_xp || 0}`} />
      </div>

      {/* #106 PR1 Bloco 2: Movements 30d (card-list, high position per ux R1) */}
      <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-base)] p-4">
        <div className="flex items-center justify-between gap-2 flex-wrap mb-3">
          <h2 className="text-sm font-bold text-navy">{t.mvTitle}</h2>
          <div className="flex items-center gap-2 text-xs">
            <span className="px-2 py-0.5 rounded-full bg-teal/10 text-teal font-bold">+{mv.joined_30d || 0} {t.mvEntries}</span>
            <span className="px-2 py-0.5 rounded-full bg-amber-100 text-amber-700 font-bold">−{mv.left_30d || 0} {t.mvExits}</span>
          </div>
        </div>
        {(mvEntries.length === 0 && mvExits.length === 0) ? (
          <p className="text-xs text-[var(--text-muted)]">{t.mvEmpty}</p>
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <div className="text-[11px] font-bold uppercase tracking-wide text-teal mb-2">{t.mvEntries} ({mvEntries.length})</div>
              <div className="space-y-1.5">
                {mvEntries.map((e: any, i: number) => (
                  <div key={i} className="flex items-center justify-between gap-2 text-xs px-2.5 py-1.5 rounded-lg bg-[var(--surface-section-cool)]">
                    <span className="font-medium text-[var(--text-primary)] truncate">{e.name}</span>
                    <span className="text-[10px] text-[var(--text-muted)] whitespace-nowrap">{new Date(e.created_at).toLocaleDateString(dateLocale, { day: '2-digit', month: 'short' })}</span>
                  </div>
                ))}
              </div>
            </div>
            <div>
              <div className="text-[11px] font-bold uppercase tracking-wide text-amber-700 mb-2">{t.mvExits} ({mvExits.length})</div>
              <div className="space-y-1.5">
                {mvExits.map((e: any, i: number) => (
                  <div key={i} className="flex items-center justify-between gap-2 text-xs px-2.5 py-1.5 rounded-lg bg-[var(--surface-section-cool)]">
                    <span className="font-medium text-[var(--text-primary)] truncate">{e.name}</span>
                    <span className="flex items-center gap-1.5 whitespace-nowrap">
                      <span className="text-[10px] px-1.5 py-0.5 rounded bg-[var(--surface-base)] border border-[var(--border-subtle)] text-[var(--text-secondary)]">{reasonLabel(e.reason_code)}</span>
                      {e.return_interest && <span className="text-[10px] text-teal" title={t.mvReturn} aria-label={t.mvReturn}>↩</span>}
                      <span className="text-[10px] text-[var(--text-muted)]">{new Date(e.offboarded_at).toLocaleDateString(dateLocale, { day: '2-digit', month: 'short' })}</span>
                    </span>
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}
      </div>

      {/* #106 PR1 Bloco 1: snapshot by tribe (sum == active; '__none__' → Sem tribo) */}
      {byTribeEntries.length > 0 && (
        <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-base)] p-4">
          <h2 className="text-sm font-bold text-navy mb-3">{t.byTribeTitle}</h2>
          <div className="flex flex-wrap gap-2">
            {byTribeEntries.map(([tname, cnt]) => (
              <span key={tname} className="text-xs px-2.5 py-1 rounded-lg bg-[var(--surface-section-cool)] border border-[var(--border-subtle)]">
                <span className="font-medium text-[var(--text-primary)]">{tname === '__none__' ? t.noTribe : tname}</span>
                <span className="ml-1.5 font-bold text-teal">{cnt}</span>
              </span>
            ))}
          </div>
        </div>
      )}

      {/* #106 PR2 Bloco 4: outreach script (read-only, copy-to-clipboard; GP edits in /admin/settings) */}
      {script && (script[scriptTab] || script['pt-BR']) && (
        <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-base)] p-4">
          <div className="flex items-center justify-between gap-2 flex-wrap mb-2">
            <h2 className="text-sm font-bold text-navy">{t.scriptTitle}</h2>
            <div className="flex items-center gap-1 no-print" role="tablist">
              {['pt-BR', 'en-US', 'es-LATAM'].map((l) => (
                <button key={l} type="button" role="tab" aria-selected={scriptTab === l}
                  onClick={() => setScriptTab(l)}
                  className={`text-[10px] font-bold px-2 py-1 rounded cursor-pointer border ${scriptTab === l ? 'bg-teal text-white border-teal' : 'bg-transparent text-[var(--text-secondary)] border-[var(--border-subtle)]'}`}>
                  {l.slice(0, 2).toUpperCase()}
                </button>
              ))}
            </div>
          </div>
          <p className="text-[10px] text-[var(--text-muted)] mb-2">{t.scriptHint}</p>
          <pre className="whitespace-pre-wrap break-words text-xs text-[var(--text-primary)] p-3 rounded-lg bg-[var(--surface-section-cool)] font-sans">{script[scriptTab] || script['pt-BR'] || ''}</pre>
          <div className="mt-2 flex items-center gap-2 no-print">
            <button type="button" onClick={copyScript}
              className="min-h-[36px] px-3 rounded-lg border border-teal text-teal text-xs font-semibold cursor-pointer bg-transparent hover:bg-teal hover:text-white transition-all">
              {copied ? t.scriptCopied : `⧉ ${t.scriptCopy}`}
            </button>
            <span aria-live="polite" className="sr-only">{copied ? t.scriptCopied : ''}</span>
          </div>
        </div>
      )}

      {/* #106 PR3 Bloco 3: selection pipeline (graceful empty-state per ux R2) */}
      {pipeline && (
        <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-base)] p-4">
          <h2 className="text-sm font-bold text-navy mb-2">{t.pipelineTitle}</h2>
          {pipeline.open ? (
            <div className="space-y-1.5">
              <div className="text-sm font-semibold text-[var(--text-primary)]">{pipeline.open.title}</div>
              <div className="text-xs text-[var(--text-secondary)]">
                {t.pipelineDeadline} <strong>{pipeline.open.close_date ? new Date(pipeline.open.close_date).toLocaleDateString(dateLocale, { day: '2-digit', month: 'short', year: 'numeric' }) : '—'}</strong>
                {' · '}<strong className="text-teal">{pipeline.open.open_apps ?? 0}</strong> {t.pipelineApps}
              </div>
              {pipeline.open.booking_url && (
                <a href={pipeline.open.booking_url} target="_blank" rel="noopener noreferrer"
                  className="inline-flex items-center text-xs font-semibold text-teal hover:underline no-print">
                  {t.pipelineBooking} ↗
                </a>
              )}
            </div>
          ) : (
            <div className="flex items-start gap-2 text-xs text-[var(--text-muted)]">
              <span aria-hidden="true">🗓️</span>
              <p>
                {t.pipelineEmpty}
                {pipeline.last?.close_date && (
                  <span className="block mt-0.5">{t.pipelineLast} {new Date(pipeline.last.close_date).toLocaleDateString(dateLocale, { day: '2-digit', month: 'short', year: 'numeric' })}.</span>
                )}
              </p>
            </div>
          )}
        </div>
      )}

      {/* Comparison Chart (moved below operational blocks per ux R1 — detail, not primary) */}
      <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-base)] p-4">
        <h2 className="text-sm font-bold text-navy mb-3">{t.compTitle}</h2>
        <div style={{ height: '180px' }}><canvas ref={chartRef} /></div>
      </div>

      {/* Top Contributors (hidden in stakeholder mode — no PII) */}
      {!stakeholderMode && g.top_contributors && g.top_contributors.length > 0 && (
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

      {/* Member Table (hidden in stakeholder mode — no PII) */}
      {!stakeholderMode && <div className="member-table">
        <h2 className="text-sm font-bold text-navy mb-2">{t.membersTitle}</h2>
        <div className="overflow-x-auto rounded-xl border border-[var(--border-default)]">
          <table className="w-full text-[11px]">
            <thead>
              <tr className="bg-[var(--surface-section-cool)]">
                <th className="px-3 py-2 text-left font-bold text-[var(--text-secondary)]">{t.name}</th>
                <th className="px-2 py-2 text-center font-bold text-[var(--text-secondary)]">{t.role}</th>
                <th className="px-2 py-2 text-center font-bold text-[var(--text-secondary)]">{t.xp}</th>
                <th className="px-2 py-2 text-center font-bold text-[var(--text-secondary)]">{t.attendance}</th>
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
      </div>}

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
