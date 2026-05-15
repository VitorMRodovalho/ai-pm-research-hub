import { useState, useEffect, useCallback } from 'react';
import { canForAdminEntry } from '../../lib/permissions';

interface Props { lang?: string; }

const L: Record<string, Record<string, string>> = {
  'pt-BR': {
    title: 'Reconciliação VEP ↔ Núcleo',
    subtitle: 'Divergências aguardando reconciliação manual',
    total: 'divergente(s)',
    selection: 'Seleção',
    onboarding: 'Onboarding',
    activeMembers: 'Membros',
    open: 'Abrir →',
    healthy: 'Tudo reconciliado',
    notMonitored: 'Sem dados VEP ainda',
  },
  'en-US': {
    title: 'VEP ↔ Núcleo Reconciliation',
    subtitle: 'Divergences awaiting manual reconciliation',
    total: 'divergent',
    selection: 'Selection',
    onboarding: 'Onboarding',
    activeMembers: 'Members',
    open: 'Open →',
    healthy: 'All reconciled',
    notMonitored: 'No VEP data yet',
  },
  'es-LATAM': {
    title: 'Reconciliación VEP ↔ Núcleo',
    subtitle: 'Divergencias esperando reconciliación manual',
    total: 'divergente(s)',
    selection: 'Selección',
    onboarding: 'Onboarding',
    activeMembers: 'Miembros',
    open: 'Abrir →',
    healthy: 'Todo reconciliado',
    notMonitored: 'Sin datos VEP aún',
  },
};

function useLang(p?: string): string {
  if (p) return p;
  if (typeof window !== 'undefined') {
    if (location.pathname.startsWith('/en')) return 'en-US';
    if (location.pathname.startsWith('/es')) return 'es-LATAM';
  }
  return 'pt-BR';
}

export default function VepReconciliationWidget({ lang: propLang }: Props) {
  const lang = useLang(propLang);
  const t = L[lang] || L['pt-BR'];
  const [data, setData] = useState<any>(null);
  const [authorized, setAuthorized] = useState(false);
  const [hasVepData, setHasVepData] = useState<boolean | null>(null);

  const load = useCallback(async () => {
    const sb = (window as any).navGetSb?.();
    if (!sb) { setTimeout(load, 400); return; }
    const m = (window as any).navGetMember?.();
    if (!m) { setTimeout(load, 400); return; }
    // ADR-0007 V4 (p163 Opção C): admin entry via canForAdminEntry (engagement-derived
     // org-scoped actions). manager/deputy_manager kept as hard-tier fallback.
    // See docs/audit/P163_A3_BACKFILL_DECISION_AUDIT.md.
    const isAdmin = m.is_superadmin
      || canForAdminEntry()
      || ['manager', 'deputy_manager'].includes(m.operational_role)
      || (m.designations || []).some((d: string) => d === 'deputy_manager' || d === 'curator' || d === 'chapter_board');
    if (!isAdmin) return;
    setAuthorized(true);
    try {
      const { data: d, error } = await sb.rpc('get_vep_divergence_report');
      if (error) { console.error('[VepReconciliation] RPC error:', error.message); return; }
      if (d && typeof d === 'object' && !(d as any).error) {
        setData(d);
        const total = (d as any).summary?.total_divergent ?? 0;
        setHasVepData(total > 0 || ((d as any).summary?.generated_at != null));
      }
    } catch (e: any) {
      console.error('[VepReconciliation] error:', e?.message);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  if (!authorized || !data) return null;

  const summary = data.summary || {};
  const total = summary.total_divergent ?? 0;
  const healthy = total === 0;
  const target = lang === 'en-US' ? '/admin/vep-reconciliation?lang=en-US' : lang === 'es-LATAM' ? '/admin/vep-reconciliation?lang=es-LATAM' : '/admin/vep-reconciliation';

  return (
    <div className="rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)] p-5 shadow-sm">
      <div className="flex items-center gap-2 mb-2">
        <span className="text-lg">🔁</span>
        <h3 className="text-sm font-extrabold text-navy">{t.title}</h3>
        <span className={`ml-auto text-[9px] px-2 py-0.5 rounded-full font-semibold ${healthy ? 'bg-emerald-100 text-emerald-700' : 'bg-amber-100 text-amber-700'}`}>
          {healthy ? t.healthy : `${total} ${t.total}`}
        </span>
      </div>
      <p className="text-[11px] text-[var(--text-secondary)] mb-3">{t.subtitle}</p>
      <div className="grid grid-cols-3 gap-2 mb-3">
        <div className="bg-[var(--surface-section-cool)] rounded-lg px-2 py-2 text-center">
          <div className="text-[9px] text-[var(--text-muted)] font-semibold uppercase">{t.selection}</div>
          <div className={`font-bold text-base ${(summary.selection_count || 0) > 0 ? 'text-amber-700' : 'text-[var(--text-muted)]'}`}>{summary.selection_count ?? 0}</div>
        </div>
        <div className="bg-[var(--surface-section-cool)] rounded-lg px-2 py-2 text-center">
          <div className="text-[9px] text-[var(--text-muted)] font-semibold uppercase">{t.onboarding}</div>
          <div className={`font-bold text-base ${(summary.onboarding_count || 0) > 0 ? 'text-amber-700' : 'text-[var(--text-muted)]'}`}>{summary.onboarding_count ?? 0}</div>
        </div>
        <div className="bg-[var(--surface-section-cool)] rounded-lg px-2 py-2 text-center">
          <div className="text-[9px] text-[var(--text-muted)] font-semibold uppercase">{t.activeMembers}</div>
          <div className={`font-bold text-base ${(summary.active_members_count || 0) > 0 ? 'text-amber-700' : 'text-[var(--text-muted)]'}`}>{summary.active_members_count ?? 0}</div>
        </div>
      </div>
      <a
        href={target}
        className="block w-full text-center px-3 py-2 rounded-lg text-[11px] font-semibold bg-navy text-white hover:opacity-90 no-underline"
      >
        {t.open}
      </a>
      {hasVepData === false && (
        <div className="mt-2 text-[10px] text-[var(--text-muted)] italic text-center">{t.notMonitored}</div>
      )}
    </div>
  );
}
