import { useState, useEffect, useCallback } from 'react';

interface Props { lang?: string; }

const L: Record<string, Record<string, string>> = {
  'pt-BR': { title: 'Termo de Voluntariado', eligible: 'Elegíveis', signed: 'Assinaram', pending: 'Pendentes', compliance: 'Compliance', viewAll: 'Ver detalhes', scopedLabel: 'Seu capítulo' },
  'en-US': { title: 'Volunteer Agreement', eligible: 'Eligible', signed: 'Signed', pending: 'Pending', compliance: 'Compliance', viewAll: 'View details', scopedLabel: 'Your chapter' },
  'es-LATAM': { title: 'Acuerdo de Voluntariado', eligible: 'Elegibles', signed: 'Firmados', pending: 'Pendientes', compliance: 'Cumplimiento', viewAll: 'Ver detalles', scopedLabel: 'Su capítulo' },
};

function useLang(p?: string): string {
  if (p) return p;
  if (typeof window !== 'undefined') {
    if (location.pathname.startsWith('/en')) return 'en-US';
    if (location.pathname.startsWith('/es')) return 'es-LATAM';
  }
  return 'pt-BR';
}

export default function VolunteerComplianceWidget({ lang: propLang }: Props) {
  const lang = useLang(propLang);
  const t = L[lang] || L['pt-BR'];
  const [data, setData] = useState<any>(null);
  const [authorized, setAuthorized] = useState(false);

  const load = useCallback(async () => {
    const sb = (window as any).navGetSb?.();
    if (!sb) { setTimeout(load, 400); return; }
    const m = (window as any).navGetMember?.();
    if (!m) { setTimeout(load, 500); return; }
    if (!(m.is_superadmin || ['manager', 'deputy_manager'].includes(m.operational_role) || (m.designations || []).includes('chapter_board'))) return;
    setAuthorized(true);
    const { data: d } = await sb.rpc('get_volunteer_agreement_status');
    if (d && !d.error) setData(d);
  }, []);

  useEffect(() => { load(); }, [load]);

  if (!authorized || !data?.summary) return null;

  const s = data.summary;
  const pct = s.pct ?? 0;
  const pctColor = pct >= 80 ? 'text-emerald-600' : pct >= 50 ? 'text-amber-600' : 'text-red-600';
  const barColor = pct >= 80 ? 'bg-emerald-500' : pct >= 50 ? 'bg-amber-400' : 'bg-red-400';

  return (
    <div className="rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)] p-5 shadow-sm">
      <div className="flex items-center gap-2 mb-3">
        <span className="text-lg">📋</span>
        <h3 className="text-sm font-extrabold text-navy">{t.title}</h3>
        {!data.is_manager && data.caller_chapter && (
          <span className="ml-1 text-[9px] px-2 py-0.5 rounded-full bg-blue-100 text-blue-700 font-semibold">{data.caller_chapter}</span>
        )}
        <span className={`ml-auto text-lg font-extrabold ${pctColor}`}>{pct}%</span>
      </div>

      {/* Progress bar */}
      <div className="w-full bg-[var(--surface-section-cool)] rounded-full h-2.5 mb-3 overflow-hidden">
        <div className={`h-full rounded-full transition-all ${barColor}`} style={{ width: `${pct}%` }} />
      </div>

      {/* Stats row */}
      <div className="grid grid-cols-3 gap-2 text-center mb-3">
        <div>
          <div className="text-lg font-bold text-navy">{s.total_eligible}</div>
          <div className="text-[9px] text-[var(--text-muted)] font-semibold uppercase">{t.eligible}</div>
        </div>
        <div>
          <div className="text-lg font-bold text-emerald-600">{s.signed}</div>
          <div className="text-[9px] text-emerald-600 font-semibold uppercase">{t.signed}</div>
        </div>
        <div>
          <div className="text-lg font-bold text-amber-600">{s.unsigned}</div>
          <div className="text-[9px] text-amber-600 font-semibold uppercase">{t.pending}</div>
        </div>
      </div>

      {/* Link to full view */}
      <a
        href="/admin/certificates"
        className="block text-center text-[10px] font-semibold text-teal hover:underline no-underline"
      >
        {t.viewAll} →
      </a>
    </div>
  );
}
