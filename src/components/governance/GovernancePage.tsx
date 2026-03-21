import { useState, useEffect, useCallback } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';
import ManualBrowser from './ManualBrowser';
import CRList from './CRList';

type Tab = 'manual' | 'crs';

export default function GovernancePage() {
  const t = usePageI18n();
  const [tab, setTab] = useState<Tab>('manual');
  const [sections, setSections] = useState<any[]>([]);
  const [crs, setCrs] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [member, setMember] = useState<any>(null);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  useEffect(() => {
    let cancelled = false;
    let retries = 0;

    async function boot() {
      const sb = getSb();
      const m = (window as any).navGetMember?.();

      if ((!sb || !m) && retries < 30) {
        retries++;
        setTimeout(boot, 300);
        return;
      }

      if (m && !cancelled) setMember(m);
      if (!sb) { if (!cancelled) setLoading(false); return; }

      try {
        const [secRes, crRes] = await Promise.all([
          sb.rpc('get_manual_sections', { p_version: 'R2' }),
          sb.rpc('get_change_requests', { p_status: null, p_cr_type: null }),
        ]);

        if (!cancelled) {
          setSections(Array.isArray(secRes.data) ? secRes.data : []);
          setCrs(Array.isArray(crRes.data) ? crRes.data : []);
        }
      } catch (e) {
        console.warn('Governance load error:', e);
      } finally {
        if (!cancelled) setLoading(false);
      }
    }

    boot();
    return () => { cancelled = true; };
  }, [getSb]);

  const reload = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    const { data } = await sb.rpc('get_change_requests', { p_status: null, p_cr_type: null });
    if (Array.isArray(data)) setCrs(data);
  }, [getSb]);

  const isGP = member?.is_superadmin || member?.operational_role === 'manager' || (member?.designations || []).includes('deputy_manager');
  const isCurator = (member?.designations || []).includes('curator');
  const isLeader = member?.operational_role === 'tribe_leader';
  const canSubmit = isGP || isCurator || isLeader;
  const canReview = isGP || isCurator || ['sponsor', 'chapter_liaison'].includes(member?.operational_role);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <div className="animate-spin h-6 w-6 border-2 border-[var(--accent)] border-t-transparent rounded-full" />
        <span className="ml-3 text-sm text-[var(--text-secondary)]">{t('governance.loading', 'Carregando...')}</span>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-extrabold text-navy">{t('governance.title', 'Governança & Controle de Mudanças')}</h1>
        <p className="text-sm text-[var(--text-secondary)] mt-1">{t('governance.manual_version', 'Manual de Governança e Operações — R2')}</p>
        <p className="text-xs text-[var(--text-muted)]">{t('governance.docusign_ref', 'DocuSign B2AFB185 · Aprovado 22/Set/2025')}</p>
      </div>

      {/* Tabs */}
      <div className="flex gap-2">
        {(['manual', 'crs'] as Tab[]).map(t2 => (
          <button
            key={t2}
            onClick={() => setTab(t2)}
            className={`px-4 py-2 rounded-full text-[13px] font-semibold cursor-pointer border-2 transition-all ${
              tab === t2
                ? 'border-navy bg-navy text-white'
                : 'border-[var(--border-default)] bg-[var(--surface-card)] text-[var(--text-secondary)]'
            }`}
          >
            {t2 === 'manual' ? `📖 ${t('governance.manual_tab', 'Manual')}` : `📋 ${t('governance.cr_tab', 'Solicitações de Mudança')}`}
          </button>
        ))}
      </div>

      {/* Tab content */}
      {tab === 'manual' ? (
        <ManualBrowser sections={sections} crs={crs} t={t} onSwitchToCr={(crNum) => { setTab('crs'); }} />
      ) : (
        <CRList
          crs={crs}
          sections={sections}
          member={member}
          canSubmit={canSubmit}
          canReview={canReview}
          t={t}
          getSb={getSb}
          onReload={reload}
        />
      )}
    </div>
  );
}
