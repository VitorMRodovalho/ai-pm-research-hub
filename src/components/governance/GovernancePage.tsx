import { useState, useEffect, useCallback } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';
import { canFor } from '../../lib/permissions';
import ManualDocumentViewer from './ManualDocumentViewer';
import CRList from './CRList';
import GovernanceApprovalTab from './GovernanceApprovalTab';

// #315 Wave 3 (#314): the `documents` tab was retired — the biblioteca now
// lives at the canonical /governance/documents route and consumes the
// list_governance_library RPC. The legacy `?view=documents` URL is handled
// at the top of `boot()` via window.location redirect (preserves existing
// bookmarks).
type View = 'document' | 'approvals' | 'changes';

const VIEW_MAP: Record<string, View> = {
  document: 'document', approvals: 'approvals', changes: 'changes',
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
  // p123 i18n nav: derive prefix from current URL since lang prop isn't passed
  const lp = typeof window !== 'undefined' && window.location.pathname.startsWith('/en/') ? '/en' : (typeof window !== 'undefined' && window.location.pathname.startsWith('/es/') ? '/es' : '');
  const t = usePageI18n();
  const lang = detectLang();
  const [view, setViewState] = useState<View>(getViewFromURL);
  const [sections, setSections] = useState<any[]>([]);
  const [crs, setCrs] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [member, setMember] = useState<any>(null);
  // p131: count de chains de governança onde o user atual tem eligible_gates
  // pendentes (ratificação, ciência, curadoria, presidência, etc). Surge como
  // callout no topo se > 0, com link para /governance/my-pending.
  const [pendingRatificationsCount, setPendingRatificationsCount] = useState<number>(0);
  const highlightCR = getHighlightCR();

  const setView = useCallback((v: View) => {
    setViewState(v);
    setViewInURL(v);
  }, []);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  useEffect(() => {
    let cancelled = false;
    let retries = 0;

    // #315 Wave 3 (#314): legacy ?view=documents bookmarks/links redirect
    // to the canonical /governance/documents biblioteca (consumes
    // list_governance_library RPC instead of get_governance_documents).
    if (typeof window !== 'undefined') {
      const params = new URLSearchParams(window.location.search);
      if (params.get('view') === 'documents') {
        const lp = window.location.pathname.startsWith('/en')
          ? '/en'
          : window.location.pathname.startsWith('/es')
            ? '/es'
            : '';
        params.delete('view');
        const qs = params.toString();
        window.location.replace(`${lp}/governance/documents${qs ? '?' + qs : ''}`);
        return;
      }
    }

    async function boot() {
      const sb = getSb();
      const m = (window as any).navGetMember?.();
      // Wait for sb (always available), but only wait for member up to 10 retries
      // After that, proceed as visitor (manual-only view)
      if (!sb && retries < 30) { retries++; setTimeout(boot, 300); return; }
      if (!m && retries < 10) { retries++; setTimeout(boot, 300); return; }
      if (m && !cancelled) setMember(m);
      if (!sb) { if (!cancelled) setLoading(false); return; }
      try {
        // Always load manual sections (anon-safe RPC)
        const secRes = await sb.rpc('get_manual_sections', { p_version: 'R2' });
        if (!cancelled) setSections(Array.isArray(secRes.data) ? secRes.data : []);

        // Only load auth-gated data if member is present
        if (m) {
          const [crRes, pendRes] = await Promise.all([
            sb.rpc('get_change_requests', { p_status: null, p_cr_type: null }),
            sb.rpc('get_pending_ratifications'),
          ]);
          if (!cancelled) {
            setCrs(Array.isArray(crRes.data) ? crRes.data : []);
            // p131: filtra rows onde realmente há gate eligível para o user
            const pending = Array.isArray(pendRes.data) ? pendRes.data : [];
            setPendingRatificationsCount(
              pending.filter((r: any) => Array.isArray(r.eligible_gates) && r.eligible_gates.length > 0).length
            );
          }
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

  // ADR-0007 V4 (p163 Opção C): governance submit/review derived from
  // engagement-based actions (sign_chain_leader / participate_in_governance_review)
  // not from operational_role cache. Replaces V3 tribe_leader exact-match that
  // leaked scope to workgroup/committee leaders. See docs/audit/P163_A3_BACKFILL_DECISION_AUDIT.md.
  const isGP = member?.is_superadmin || member?.operational_role === 'manager' || (member?.designations || []).includes('deputy_manager');
  const isCurator = (member?.designations || []).includes('curator');
  const canSubmit = isGP || isCurator || canFor('sign_chain_leader');
  const canReview = isGP || isCurator || canFor('participate_in_governance_review');

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <div className="animate-spin h-6 w-6 border-2 border-[var(--accent)] border-t-transparent rounded-full" />
        <span className="ml-3 text-sm text-[var(--text-secondary)]">{t('governance.loading', 'Carregando...')}</span>
      </div>
    );
  }

  const isVisitor = !member;
  const allViews: { key: View; icon: string; labelKey: string; fallback: string; authOnly?: boolean }[] = [
    { key: 'document', icon: '📖', labelKey: 'governance.manual_tab', fallback: 'Manual' },
    { key: 'approvals', icon: '🗳️', labelKey: 'governance.approvals_tab', fallback: 'Aprovações', authOnly: true },
    { key: 'changes', icon: '📋', labelKey: 'governance.cr_tab', fallback: 'Solicitações de Mudança', authOnly: true },
    // #315 Wave 3 (#314): retired `documents` view — biblioteca now lives at
    // /governance/documents. The cross-link below in the view body offers a
    // direct path; the legacy ?view=documents URL redirects there too.
  ];
  const views = isVisitor ? allViews.filter(v => !v.authOnly) : allViews;

  // Force document view for visitors trying to access auth-only tabs
  const activeView = isVisitor && view !== 'document' ? 'document' : view;

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
          <a href={`${lp}/admin/governance-v2`}
            className="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg bg-[var(--surface-hover)] border border-[var(--border-default)] text-[11px] font-semibold text-[var(--text-muted)] no-underline hover:text-[var(--text-primary)] hover:border-navy transition-colors shrink-0">
            ⚙️ Admin
          </a>
        )}
      </div>

      {/* p131: callout de pendências de assinatura — surge só se há chains com
          eligible_gates não-vazios para o user atual. Link rápido para a
          página dedicada /governance/my-pending. */}
      {pendingRatificationsCount > 0 && (
        <a
          href={`${lp}/governance/my-pending`}
          className="block rounded-xl border-2 border-navy bg-blue-50/30 p-4 no-underline hover:bg-blue-50/60 transition-colors"
        >
          <div className="flex items-center justify-between gap-3 flex-wrap">
            <div>
              <h3 className="text-sm font-bold text-navy">
                {t('governance.myPending.callout.title', 'Você tem assinaturas pendentes')}
              </h3>
              <p className="text-[12px] text-[var(--text-secondary)] mt-0.5">
                {t('governance.myPending.callout.body', '{count} cadeia(s) de governança aguardam sua ação (ratificação, ciência, curadoria ou outra)').replace('{count}', String(pendingRatificationsCount))}
              </p>
            </div>
            <span className="text-[12px] font-bold text-navy">
              {t('governance.myPending.callout.cta', 'Ver minhas pendências →')}
            </span>
          </div>
        </a>
      )}

      {/* View selector — only show tabs if authenticated (visitors see manual directly) */}
      {!isVisitor && (
        <div className="flex gap-2 flex-wrap">
          {views.map(v => (
            <button
              key={v.key}
              onClick={() => setView(v.key)}
              className={`px-4 py-2 rounded-full text-[13px] font-semibold cursor-pointer border-2 transition-all ${
                activeView === v.key
                  ? 'border-navy bg-navy text-white'
                  : 'border-[var(--border-default)] bg-[var(--surface-card)] text-[var(--text-secondary)]'
              }`}
            >
              {v.icon} {t(v.labelKey, v.fallback)}
            </button>
          ))}
        </div>
      )}

      {/* Views */}
      {activeView === 'document' && (
        <ManualDocumentViewer lang={lang} />
      )}
      {activeView === 'approvals' && (
        <GovernanceApprovalTab t={t} getSb={getSb} member={member} />
      )}
      {activeView === 'changes' && (
        <CRList crs={crs} sections={sections} member={member} canSubmit={canSubmit} canReview={canReview} t={t} getSb={getSb} onReload={reload} />
      )}

      {/* #315 Wave 3 (#314) — cross-link to the canonical biblioteca for
          authenticated members. Replaces the retired `documents` tab. */}
      {!isVisitor && activeView === 'document' && (
        <a
          href={`${lp}/governance/documents`}
          className="block rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-4 no-underline hover:border-navy transition-colors"
          data-testid="governance-library-crosslink"
        >
          <div className="flex items-center justify-between gap-3 flex-wrap">
            <div>
              <h3 className="text-sm font-bold text-navy">
                {t('governance.documents_tab', 'Documentos')}
              </h3>
              <p className="text-[12px] text-[var(--text-secondary)] mt-0.5">
                {t('governance.library.crosslinkHint', 'Veja a biblioteca de documentos de governança vigentes (Manual, políticas, termos, acordos).')}
              </p>
            </div>
            <span className="text-[12px] font-bold text-navy">
              {t('governance.library.crosslinkCta', 'Abrir biblioteca →')}
            </span>
          </div>
        </a>
      )}
    </div>
  );
}
