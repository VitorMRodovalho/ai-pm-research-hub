import { useState, useEffect, useCallback } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';
import ManualBrowser from './ManualBrowser';
import CRList from './CRList';
import DocumentsList from './DocumentsList';
import GovernanceApprovalTab from './GovernanceApprovalTab';

type Tab = 'manual' | 'crs' | 'documents' | 'approvals';

function detectLang(): string {
  if (typeof window === 'undefined') return 'pt-BR';
  const params = new URLSearchParams(window.location.search);
  const langParam = params.get('lang');
  if (langParam) return langParam;
  if (window.location.pathname.startsWith('/en')) return 'en-US';
  if (window.location.pathname.startsWith('/es')) return 'es-LATAM';
  return 'pt-BR';
}

export default function GovernancePage() {
  const t = usePageI18n();
  const lang = detectLang();
  const [tab, setTab] = useState<Tab>('approvals');
  const [sections, setSections] = useState<any[]>([]);
  const [crs, setCrs] = useState<any[]>([]);
  const [docs, setDocs] = useState<any[]>([]);
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
        const [secRes, crRes, docRes] = await Promise.all([
          sb.rpc('get_manual_sections', { p_version: 'R2' }),
          sb.rpc('get_change_requests', { p_status: null, p_cr_type: null }),
          sb.rpc('get_governance_documents'),
        ]);

        if (!cancelled) {
          setSections(Array.isArray(secRes.data) ? secRes.data : []);
          setCrs(Array.isArray(crRes.data) ? crRes.data : []);
          setDocs(Array.isArray(docRes.data) ? docRes.data : []);
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

  const isSponsor = member?.operational_role === 'sponsor';
  const tabs: { key: Tab; icon: string; labelKey: string; fallback: string }[] = [
    { key: 'approvals', icon: '🗳️', labelKey: 'governance.approvals_tab', fallback: 'Aprovações' },
    { key: 'manual', icon: '📖', labelKey: 'governance.manual_tab', fallback: 'Manual' },
    { key: 'crs', icon: '📋', labelKey: 'governance.cr_tab', fallback: 'Solicitações de Mudança' },
    { key: 'documents', icon: '📄', labelKey: 'governance.documents_tab', fallback: 'Documentos' },
  ];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-extrabold text-navy">{t('governance.title', 'Governança & Controle de Mudanças')}</h1>
        <p className="text-sm text-[var(--text-secondary)] mt-1">{t('governance.manual_version', 'Manual de Governança e Operações — R2')}</p>
        <p className="text-xs text-[var(--text-muted)]">{t('governance.docusign_ref', 'DocuSign B2AFB185 · Aprovado 22/Set/2025')}</p>
      </div>

      <div className="flex gap-2 flex-wrap">
        {tabs.map(tb => (
          <button
            key={tb.key}
            onClick={() => setTab(tb.key)}
            className={`px-4 py-2 rounded-full text-[13px] font-semibold cursor-pointer border-2 transition-all ${
              tab === tb.key
                ? 'border-navy bg-navy text-white'
                : 'border-[var(--border-default)] bg-[var(--surface-card)] text-[var(--text-secondary)]'
            }`}
          >
            {tb.icon} {t(tb.labelKey, tb.fallback)}
          </button>
        ))}
      </div>

      {tab === 'manual' && (
        <ManualBrowser sections={sections} crs={crs} t={t} onSwitchToCr={() => setTab('crs')} lang={lang} />
      )}
      {tab === 'crs' && (
        <CRList crs={crs} sections={sections} member={member} canSubmit={canSubmit} canReview={canReview} t={t} getSb={getSb} onReload={reload} />
      )}
      {tab === 'documents' && (
        <DocumentsList docs={docs} t={t} />
      )}
      {tab === 'approvals' && (
        <GovernanceApprovalTab t={t} getSb={getSb} member={member} />
      )}
    </div>
  );
}
