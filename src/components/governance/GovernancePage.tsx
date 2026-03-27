import { useState, useEffect, useCallback } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';
import ManualDocumentViewer from './ManualDocumentViewer';
import CRList from './CRList';
import DocumentsList from './DocumentsList';
import GovernanceApprovalTab from './GovernanceApprovalTab';

type View = 'document' | 'approvals' | 'changes' | 'documents';

const VIEW_MAP: Record<string, View> = {
  document: 'document', approvals: 'approvals', changes: 'changes', documents: 'documents',
  // Legacy compat
  manual: 'document', crs: 'changes',
};

function detectLang(): string {
  if (typeof window === 'undefined') return 'pt-BR';
  const params = new URLSearchParams(window.location.search);
  const langParam = params.get('lang');
  if (langParam) return langParam;
  if (window.location.pathname.startsWith('/en')) return 'en-US';
  if (window.location.pathname.startsWith('/es')) return 'es-LATAM';
  return 'pt-BR';
}

function getViewFromURL(): View {
  if (typeof window === 'undefined') return 'document';
  const params = new URLSearchParams(window.location.search);
  const v = params.get('view') || 'document';
  return VIEW_MAP[v] || 'document';
}

function getHighlightCR(): string | null {
  if (typeof window === 'undefined') return null;
  return new URLSearchParams(window.location.search).get('highlight') || null;
}

function setViewInURL(view: View) {
  if (typeof window === 'undefined') return;
  const url = new URL(window.location.href);
  url.searchParams.set('view', view);
  url.searchParams.delete('highlight');
  window.history.replaceState(null, '', url.toString());
}

export default function GovernancePage() {
  const t = usePageI18n();
  const lang = detectLang();
  const [view, setViewState] = useState<View>(getViewFromURL);
  const [sections, setSections] = useState<any[]>([]);
  const [crs, setCrs] = useState<any[]>([]);
  const [docs, setDocs] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [member, setMember] = useState<any>(null);
  const highlightCR = getHighlightCR();

  const setView = useCallback((v: View) => {
    setViewState(v);
    setViewInURL(v);
  }, []);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  useEffect(() => {
    let cancelled = false;
    let retries = 0;

    async function boot() {
      const sb = getSb();
      const m = (window as any).navGetMember?.();
      if ((!sb || !m) && retries < 30) { retries++; setTimeout(boot, 300); return; }
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
      } catch (e) { console.warn('Governance load error:', e); }
      finally { if (!cancelled) setLoading(false); }
    }
    boot();
    return () => { cancelled = true; };
  }, [getSb]);

  // If URL has ?highlight=CR-XXX, switch to approvals view
  useEffect(() => {
    if (highlightCR && view !== 'approvals') {
      setView('approvals');
    }
  }, [highlightCR]);

  // After approvals view renders with highlight, scroll to it
  useEffect(() => {
    if (highlightCR && view === 'approvals') {
      const timer = setTimeout(() => {
        const el = document.querySelector(`[data-cr-number="${highlightCR}"]`);
        if (el) {
          el.scrollIntoView({ behavior: 'smooth', block: 'center' });
          el.classList.add('ring-2', 'ring-navy', 'ring-offset-2');
          setTimeout(() => el.classList.remove('ring-2', 'ring-navy', 'ring-offset-2'), 3000);
        }
      }, 1000);
      return () => clearTimeout(timer);
    }
  }, [highlightCR, view]);

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

  const views: { key: View; icon: string; labelKey: string; fallback: string }[] = [
    { key: 'document', icon: '📖', labelKey: 'governance.manual_tab', fallback: 'Manual' },
    { key: 'approvals', icon: '🗳️', labelKey: 'governance.approvals_tab', fallback: 'Aprovações' },
    { key: 'changes', icon: '📋', labelKey: 'governance.cr_tab', fallback: 'Solicitações de Mudança' },
    { key: 'documents', icon: '📄', labelKey: 'governance.documents_tab', fallback: 'Documentos' },
  ];

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-start justify-between gap-4 flex-wrap">
        <div>
          <h1 className="text-2xl font-extrabold text-navy">{t('governance.title', 'Governança & Controle de Mudanças')}</h1>
          <p className="text-sm text-[var(--text-secondary)] mt-1">{t('governance.manual_version', 'Manual de Governança e Operações — R2')}</p>
          <p className="text-xs text-[var(--text-muted)]">{t('governance.docusign_ref', 'DocuSign B2AFB185 · Aprovado 22/Set/2025')}</p>
        </div>
        {isGP && (
          <a href="/admin/governance-v2"
            className="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg bg-[var(--surface-hover)] border border-[var(--border-default)] text-[11px] font-semibold text-[var(--text-muted)] no-underline hover:text-[var(--text-primary)] hover:border-navy transition-colors shrink-0">
            ⚙️ Admin
          </a>
        )}
      </div>

      {/* View selector */}
      <div className="flex gap-2 flex-wrap">
        {views.map(v => (
          <button
            key={v.key}
            onClick={() => setView(v.key)}
            className={`px-4 py-2 rounded-full text-[13px] font-semibold cursor-pointer border-2 transition-all ${
              view === v.key
                ? 'border-navy bg-navy text-white'
                : 'border-[var(--border-default)] bg-[var(--surface-card)] text-[var(--text-secondary)]'
            }`}
          >
            {v.icon} {t(v.labelKey, v.fallback)}
          </button>
        ))}
      </div>

      {/* Views */}
      {view === 'document' && (
        <ManualDocumentViewer lang={lang} />
      )}
      {view === 'approvals' && (
        <GovernanceApprovalTab t={t} getSb={getSb} member={member} />
      )}
      {view === 'changes' && (
        <CRList crs={crs} sections={sections} member={member} canSubmit={canSubmit} canReview={canReview} t={t} getSb={getSb} onReload={reload} />
      )}
      {view === 'documents' && (
        <DocumentsList docs={docs} t={t} />
      )}
    </div>
  );
}
