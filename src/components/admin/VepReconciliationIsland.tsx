import { useState, useEffect, useCallback } from 'react';
import { canForAdminEntry } from '../../lib/permissions';
import { SELECTION_STATUS_TONE, VEP_STATUS_TONE, toneClasses } from '../../lib/statusFarol';
import { usePageI18n } from '../../i18n/usePageI18n';

interface Props { lang?: string; }

type TabKey = 'matrix' | 'selection' | 'onboarding' | 'active_members' | 'rejection' | 'offer_retracted';


function useLang(p?: string): string {
  if (p) return p;
  if (typeof window !== 'undefined') {
    if (location.pathname.startsWith('/en')) return 'en-US';
    if (location.pathname.startsWith('/es')) return 'es-LATAM';
  }
  return 'pt-BR';
}

function timeAgo(dateStr: string | null | undefined, label: string): string {
  if (!dateStr) return '—';
  const diff = Date.now() - new Date(dateStr).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 60) return `${mins}m ${label}`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ${label}`;
  const days = Math.floor(hours / 24);
  return `${days}d ${label}`;
}

// #1132 — palettes derived from the shared SSOT (src/lib/statusFarol), no longer
// a local colour map that could drift from selection.astro / AffiliationQueueIsland.
const NUCLEO_STATUS_COLOR: Record<string, string> = Object.fromEntries(
  Object.entries(SELECTION_STATUS_TONE).map(([status, tone]) => [status, toneClasses(tone)]),
);

const VEP_STATUS_COLOR: Record<string, string> = Object.fromEntries(
  Object.entries(VEP_STATUS_TONE).map(([status, tone]) => [status, toneClasses(tone)]),
);

// #1130 — role×cohort reconciliation matrix panel
function MatrixPanel({ t, data, loading, error, onRetry, roleLabel, cycleHref, renderBadge }: {
  t: (k: string, f?: string) => string;
  data: any;
  loading: boolean;
  error: string | null;
  onRetry: () => void;
  roleLabel: (r: string) => string;
  cycleHref: (code: string | null | undefined) => string | null;
  renderBadge: (status: string | null | undefined, palette: Record<string, string>) => any;
}) {
  if (loading && !data) {
    return <div className="text-center py-10 text-[var(--text-muted)] text-sm">{t('comp.vepReconciliation.loading')}</div>;
  }
  if (error && !data) {
    return (
      <div className="text-center py-10">
        <div className="text-sm font-semibold text-red-700 mb-1">{t('comp.vepReconciliation.errTitle')}</div>
        <div className="text-xs text-[var(--text-muted)] mb-4 font-mono max-w-xl mx-auto break-words">{error}</div>
        <button onClick={onRetry} className="px-4 py-1.5 rounded-lg text-[12px] font-semibold bg-navy text-white hover:opacity-90 cursor-pointer border-0">
          ↻ {t('comp.vepReconciliation.errRetry')}
        </button>
      </div>
    );
  }
  if (!data) {
    return <div className="text-center py-10 text-[var(--text-muted)] text-sm">{t('comp.vepReconciliation.matrixEmpty')}</div>;
  }

  const totals = data.totals || {};
  const matrix: any[] = data.matrix || [];
  const platformOnly: any[] = data.platform_only || [];
  const vepOnly: any[] = data.vep_only || [];

  const deltaCell = (d: number) => {
    if (d === 0) return <span className="text-[var(--text-muted)]">0</span>;
    const cls = d > 0 ? 'text-amber-700' : 'text-blue-700';
    return <span className={`font-bold ${cls}`}>{d > 0 ? '+' : ''}{d}</span>;
  };
  const cohortCell = (code: string) => {
    const href = cycleHref(code);
    return href ? <a href={href} className="text-navy hover:underline">{code}</a> : <span>{code}</span>;
  };

  return (
    <div className="space-y-4">
      {/* Totals headline */}
      <div className="flex flex-wrap gap-4 items-center rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)] px-4 py-3">
        <div className="text-[13px]"><span className="text-[var(--text-muted)]">{t('comp.vepReconciliation.colPlatform')}: </span><strong className="text-navy text-lg">{totals.platform_active ?? 0}</strong></div>
        <div className="text-[13px]"><span className="text-[var(--text-muted)]">{t('comp.vepReconciliation.colVepActive')}: </span><strong className="text-navy text-lg">{totals.vep_active_mirror ?? 0}</strong></div>
        <div className="text-[13px]"><span className="text-[var(--text-muted)]">{t('comp.vepReconciliation.colDelta')}: </span>{deltaCell(totals.delta ?? 0)}</div>
      </div>
      {data.mirror_note && <div className="text-[11px] text-[var(--text-muted)] italic">{t('comp.vepReconciliation.mirrorNote')}</div>}

      {/* Matrix table */}
      <div className="rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)] overflow-hidden overflow-x-auto">
        <table className="w-full text-[12px]">
          <thead className="bg-[var(--surface-section-cool)] text-[var(--text-muted)]">
            <tr>
              <th className="px-3 py-2 text-left font-semibold">{t('comp.vepReconciliation.colRole')}</th>
              <th className="px-3 py-2 text-left font-semibold">{t('comp.vepReconciliation.colCohort')}</th>
              <th className="px-3 py-2 text-right font-semibold">{t('comp.vepReconciliation.colPlatform')}</th>
              <th className="px-3 py-2 text-right font-semibold">{t('comp.vepReconciliation.colVepActive')}</th>
              <th className="px-3 py-2 text-right font-semibold">{t('comp.vepReconciliation.colDelta')}</th>
            </tr>
          </thead>
          <tbody>
            {matrix.map((c, i) => (
              <tr key={`${c.role}-${c.cohort}-${i}`} className="border-t border-[var(--border-subtle)] hover:bg-[var(--surface-hover)]">
                <td className="px-3 py-2 font-semibold text-[var(--text-primary)]">{roleLabel(c.role)}</td>
                <td className="px-3 py-2 text-[var(--text-secondary)]">{cohortCell(c.cohort)}</td>
                <td className="px-3 py-2 text-right">{c.platform_active}</td>
                <td className="px-3 py-2 text-right">{c.vep_active}</td>
                <td className="px-3 py-2 text-right">{deltaCell(c.delta)}</td>
              </tr>
            ))}
          </tbody>
          <tfoot>
            <tr className="border-t-2 border-[var(--border-default)] bg-[var(--surface-section-cool)]">
              <td className="px-3 py-2 font-bold text-navy" colSpan={2}>{t('comp.vepReconciliation.totalRow')}</td>
              <td className="px-3 py-2 text-right font-bold text-navy">{totals.platform_active ?? 0}</td>
              <td className="px-3 py-2 text-right font-bold text-navy">{totals.vep_active_mirror ?? 0}</td>
              <td className="px-3 py-2 text-right font-bold">{deltaCell(totals.delta ?? 0)}</td>
            </tr>
          </tfoot>
        </table>
      </div>

      {/* platform_only nominal list */}
      <div>
        <div className="text-[13px] font-bold text-navy mb-1">{t('comp.vepReconciliation.platformOnlyTitle')} <span className="text-[10px] font-bold px-1.5 py-0.5 rounded-full bg-amber-100 text-amber-700">{platformOnly.length}</span></div>
        <div className="text-[11px] text-[var(--text-muted)] italic mb-2">{t('comp.vepReconciliation.platformOnlyHint')}</div>
        <div className="rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)] overflow-hidden overflow-x-auto">
          {platformOnly.length === 0 ? (
            <div className="text-center py-6 text-[var(--text-muted)] text-[12px]">{t('comp.vepReconciliation.emptyState')}</div>
          ) : (
            <table className="w-full text-[12px]">
              <thead className="bg-[var(--surface-section-cool)] text-[var(--text-muted)]">
                <tr>
                  <th className="px-3 py-2 text-left font-semibold">{t('comp.vepReconciliation.colName')}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t('comp.vepReconciliation.colEmail')}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t('comp.vepReconciliation.colRole')}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t('comp.vepReconciliation.colCohort')}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t('comp.vepReconciliation.colVepStatus')}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t('comp.vepReconciliation.colAction')}</th>
                </tr>
              </thead>
              <tbody>
                {platformOnly.map((r, i) => (
                  <tr key={`${r.pmi_id || r.email}-${i}`} className="border-t border-[var(--border-subtle)] hover:bg-[var(--surface-hover)]">
                    <td className="px-3 py-2 font-semibold text-[var(--text-primary)]">{r.member_name || '—'}</td>
                    <td className="px-3 py-2 text-[var(--text-secondary)] font-mono text-[11px]">{r.email}</td>
                    <td className="px-3 py-2 text-[var(--text-secondary)]">{roleLabel(r.role)}</td>
                    <td className="px-3 py-2 text-[var(--text-secondary)]">{cohortCell(r.cohort)}</td>
                    <td className="px-3 py-2">{renderBadge(r.vep_status_raw, VEP_STATUS_COLOR)}</td>
                    <td className="px-3 py-2 text-[var(--text-secondary)] text-[11px]">{r.suggested_action}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {/* vep_only nominal list */}
      <div>
        <div className="text-[13px] font-bold text-navy mb-1">{t('comp.vepReconciliation.vepOnlyTitle')} <span className="text-[10px] font-bold px-1.5 py-0.5 rounded-full bg-amber-100 text-amber-700">{vepOnly.length}</span></div>
        <div className="text-[11px] text-[var(--text-muted)] italic mb-2">{t('comp.vepReconciliation.vepOnlyHint')}</div>
        <div className="rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)] overflow-hidden overflow-x-auto">
          {vepOnly.length === 0 ? (
            <div className="text-center py-6 text-[var(--text-muted)] text-[12px]">{t('comp.vepReconciliation.emptyState')}</div>
          ) : (
            <table className="w-full text-[12px]">
              <thead className="bg-[var(--surface-section-cool)] text-[var(--text-muted)]">
                <tr>
                  <th className="px-3 py-2 text-left font-semibold">{t('comp.vepReconciliation.colName')}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t('comp.vepReconciliation.colEmail')}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t('comp.vepReconciliation.colRole')}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t('comp.vepReconciliation.colCohort')}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t('comp.vepReconciliation.colMemberActive')}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t('comp.vepReconciliation.colAction')}</th>
                </tr>
              </thead>
              <tbody>
                {vepOnly.map((r, i) => (
                  <tr key={`${r.pmi_id || r.email}-${i}`} className="border-t border-[var(--border-subtle)] hover:bg-[var(--surface-hover)]">
                    <td className="px-3 py-2 font-semibold text-[var(--text-primary)]">{r.applicant_name || '—'}</td>
                    <td className="px-3 py-2 text-[var(--text-secondary)] font-mono text-[11px]">{r.email}</td>
                    <td className="px-3 py-2 text-[var(--text-secondary)]">{roleLabel(r.role)}</td>
                    <td className="px-3 py-2 text-[var(--text-secondary)]">{cohortCell(r.cohort)}</td>
                    <td className="px-3 py-2 text-[var(--text-secondary)]">{r.member_is_active === true ? t('comp.vepReconciliation.yes') : r.member_is_active === false ? t('comp.vepReconciliation.no') : '—'}</td>
                    <td className="px-3 py-2 text-[var(--text-secondary)] text-[11px]">{r.suggested_action}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>
    </div>
  );
}

export default function VepReconciliationIsland({ lang: propLang }: Props) {
  const lang = useLang(propLang);
  const t = usePageI18n();
  const [authorized, setAuthorized] = useState<boolean | null>(null);
  const [data, setData] = useState<any>(null);
  const [tab, setTab] = useState<TabKey>('matrix');
  const [loading, setLoading] = useState(false);
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [toast, setToast] = useState<{ type: 'ok' | 'err'; msg: string } | null>(null);
  // #1130 F3 — load error separate from data==null (avoid infinite spinner on RPC failure)
  const [loadError, setLoadError] = useState<string | null>(null);
  // #1130 — role×cohort matrix (lazy-loaded on tab select)
  const [matrixData, setMatrixData] = useState<any>(null);
  const [matrixLoading, setMatrixLoading] = useState(false);
  const [matrixError, setMatrixError] = useState<string | null>(null);
  // p153 OPP-152.5 — baseline drift panel
  const [baselineData, setBaselineData] = useState<any>(null);
  const [capturingBaseline, setCapturingBaseline] = useState(false);

  const loadBaselines = useCallback(async () => {
    const sb = (window as any).navGetSb?.();
    if (!sb) return;
    try {
      const { data: b, error } = await sb.rpc('get_vep_baseline_history', { p_limit: 10 });
      if (error) throw error;
      setBaselineData(b);
    } catch (e: any) {
      console.warn('[VepReconciliation] baseline load failed:', e?.message);
    }
  }, []);

  const captureBaseline = useCallback(async () => {
    const label = window.prompt(t('comp.vepReconciliation.captureLabelPrompt'), '');
    if (label === null || label.trim() === '') return;
    const notes = window.prompt(t('comp.vepReconciliation.captureNotesPrompt'), '');
    setCapturingBaseline(true);
    setToast(null);
    try {
      const sb = (window as any).navGetSb?.();
      if (!sb) throw new Error('no supabase');
      const { data: r, error } = await sb.rpc('capture_vep_baseline', {
        p_label: label.trim(),
        p_notes: notes ? notes.trim() : null,
      });
      if (error) throw error;
      if (r && typeof r === 'object' && (r as any).error) throw new Error((r as any).error);
      setToast({ type: 'ok', msg: t('comp.vepReconciliation.capturedOk') });
      await loadBaselines();
    } catch (e: any) {
      setToast({ type: 'err', msg: `${t('comp.vepReconciliation.capturedErr')}: ${e?.message || String(e)}` });
    } finally {
      setCapturingBaseline(false);
    }
  }, [t, loadBaselines]);

  const load = useCallback(async () => {
    const sb = (window as any).navGetSb?.();
    if (!sb) { setTimeout(load, 400); return; }
    const m = (window as any).navGetMember?.();
    // p152 W4 hotfix: retry while member is still loading (was: setAuthorized(false)
    // immediately, causing "Acesso restrito" flash for legit admins including superadmin).
    if (!m) { setTimeout(load, 400); return; }
    // ADR-0007 V4 (p163 Opção C): see docs/audit/P163_A3_BACKFILL_DECISION_AUDIT.md
    const isAdmin = m.is_superadmin
      || canForAdminEntry()
      || ['manager', 'deputy_manager'].includes(m.operational_role)
      || (m.designations || []).some((d: string) => d === 'deputy_manager' || d === 'curator' || d === 'chapter_board');
    if (!isAdmin) {
      setAuthorized(false);
      return;
    }
    setAuthorized(true);
    setLoading(true);
    setLoadError(null);
    try {
      const { data: d, error } = await sb.rpc('get_vep_divergence_report');
      if (error) throw error;
      if (d && typeof d === 'object' && (d as any).error) throw new Error((d as any).error);
      setData(d);
      setLoadError(null);
    } catch (e: any) {
      console.error('[VepReconciliation] load error:', e?.message);
      // #1130 F3 — surface a persistent error state (not just a 4s toast) so the GP
      // never mistakes a failed RPC for "still loading".
      setLoadError(e?.message || String(e));
      setToast({ type: 'err', msg: e?.message || String(e) });
    } finally {
      setLoading(false);
    }
  }, []);

  const loadMatrix = useCallback(async () => {
    const sb = (window as any).navGetSb?.();
    if (!sb) return;
    setMatrixLoading(true);
    setMatrixError(null);
    try {
      const { data: d, error } = await sb.rpc('get_vep_role_cohort_reconciliation');
      if (error) throw error;
      if (d && typeof d === 'object' && (d as any).error) throw new Error((d as any).error);
      setMatrixData(d);
      setMatrixError(null);
    } catch (e: any) {
      console.error('[VepReconciliation] matrix load error:', e?.message);
      setMatrixError(e?.message || String(e));
    } finally {
      setMatrixLoading(false);
    }
  }, []);

  useEffect(() => { load(); }, [load]);
  // #1130 — lazy-load the matrix the first time its tab is opened (and on authorize if default)
  useEffect(() => {
    if (authorized === true && tab === 'matrix' && matrixData === null && !matrixLoading && !matrixError) {
      loadMatrix();
    }
  }, [authorized, tab, matrixData, matrixLoading, matrixError, loadMatrix]);
  // p153 OPP-152.5 — load baseline history when authorized
  useEffect(() => { if (authorized === true) loadBaselines(); }, [authorized, loadBaselines]);

  const markReconciled = async (applicationId: string) => {
    const note = window.prompt(t('comp.vepReconciliation.notePrompt'), '');
    if (note === null) return;
    if (!window.confirm(t('comp.vepReconciliation.confirmMark'))) return;
    setPendingId(applicationId);
    setToast(null);
    try {
      const sb = (window as any).navGetSb?.();
      if (!sb) throw new Error('no supabase');
      const { data: r, error } = await sb.rpc('mark_vep_reconciled', {
        p_application_id: applicationId,
        p_note: note ? note.trim() : null,
      });
      if (error) throw error;
      if (r && typeof r === 'object' && (r as any).error) throw new Error((r as any).error);
      setToast({ type: 'ok', msg: t('comp.vepReconciliation.markOk') });
      await load();
    } catch (e: any) {
      setToast({ type: 'err', msg: `${t('comp.vepReconciliation.markErrPrefix')}: ${e?.message || String(e)}` });
    } finally {
      setPendingId(null);
    }
  };

  // #1445 — reachable offboard action for the "offer retracted + member still active" bucket.
  // Reuses admin_offboard_member (inactive) — no duplicate offboarding path. Category
  // 'reacceptance_refusal' (preserves return eligibility); the GP supplies the detail.
  const offboardMember = async (memberId: string, detailPrompt: string) => {
    const detail = window.prompt(t('comp.vepReconciliation.offboardPrompt'), detailPrompt);
    if (detail === null || detail.trim() === '') return;
    if (!window.confirm(t('comp.vepReconciliation.offboardConfirm'))) return;
    setPendingId(memberId);
    setToast(null);
    try {
      const sb = (window as any).navGetSb?.();
      if (!sb) throw new Error('no supabase');
      const { data: r, error } = await sb.rpc('admin_offboard_member', {
        p_member_id: memberId,
        p_new_status: 'inactive',
        p_reason_category: 'reacceptance_refusal',
        p_reason_detail: detail.trim(),
        p_reassign_to: null,
      });
      if (error) throw error;
      if (r && typeof r === 'object' && (r as any).error) throw new Error((r as any).error);
      setToast({ type: 'ok', msg: t('comp.vepReconciliation.offboardOk') });
      await load();
    } catch (e: any) {
      setToast({ type: 'err', msg: `${t('comp.vepReconciliation.offboardErrPrefix')}: ${e?.message || String(e)}` });
    } finally {
      setPendingId(null);
    }
  };

  if (authorized === false) {
    return <div className="text-center py-12 text-[var(--text-muted)]">{t('comp.vepReconciliation.deniedAccess')}</div>;
  }
  // #1130 F3 — a failed RPC must not read as "still loading". Show a real error + retry.
  if (loadError && !data) {
    return (
      <div className="text-center py-12">
        <div className="text-sm font-semibold text-red-700 mb-1">{t('comp.vepReconciliation.errTitle')}</div>
        <div className="text-xs text-[var(--text-muted)] mb-4 font-mono max-w-xl mx-auto break-words">{loadError}</div>
        <button
          onClick={load}
          disabled={loading}
          className="px-4 py-1.5 rounded-lg text-[12px] font-semibold bg-navy text-white hover:opacity-90 cursor-pointer border-0 disabled:opacity-50"
        >
          {loading ? t('comp.vepReconciliation.refreshing') : `↻ ${t('comp.vepReconciliation.errRetry')}`}
        </button>
      </div>
    );
  }
  if (authorized === null || !data) {
    return <div className="text-center py-12 text-[var(--text-muted)]">{t('comp.vepReconciliation.loading')}</div>;
  }

  const summary = data.summary || {};
  const lists: Record<Exclude<TabKey, 'matrix'>, any[]> = {
    selection: data.selection_divergent || [],
    onboarding: data.onboarding_divergent || [],
    active_members: data.active_members_divergent || [],
    rejection: data.rejection_divergent || [],
    offer_retracted: data.offer_retracted_active_divergent || [],
  };
  const matrixDivCount = (matrixData?.totals?.platform_only_count ?? 0) + (matrixData?.totals?.vep_only_count ?? 0);
  const tabCounts: Record<TabKey, number> = {
    matrix: matrixDivCount,
    selection: summary.selection_count ?? lists.selection.length,
    onboarding: summary.onboarding_count ?? lists.onboarding.length,
    active_members: summary.active_members_count ?? lists.active_members.length,
    rejection: summary.rejection_count ?? lists.rejection.length,
    offer_retracted: summary.offer_retracted_active_count ?? lists.offer_retracted.length,
  };
  const tabHints: Record<TabKey, string> = {
    matrix: t('comp.vepReconciliation.tabMatrixHint'),
    selection: t('comp.vepReconciliation.tabSelectionHint'),
    onboarding: t('comp.vepReconciliation.tabOnboardingHint'),
    active_members: t('comp.vepReconciliation.tabActiveMembersHint'),
    rejection: t('comp.vepReconciliation.tabRejectionHint'),
    offer_retracted: t('comp.vepReconciliation.tabOfferRetractedHint'),
  };
  const tabLabels: Record<TabKey, string> = {
    matrix: t('comp.vepReconciliation.tabMatrix'),
    selection: t('comp.vepReconciliation.tabSelection'),
    onboarding: t('comp.vepReconciliation.tabOnboarding'),
    active_members: t('comp.vepReconciliation.tabActiveMembers'),
    rejection: t('comp.vepReconciliation.tabRejection'),
    offer_retracted: t('comp.vepReconciliation.tabOfferRetracted'),
  };
  const currentList = tab === 'matrix' ? [] : lists[tab];

  // #1130 F4 — cross-nav helpers to the sibling admin screens.
  const langPrefix = lang === 'en-US' ? '/en' : lang === 'es-LATAM' ? '/es' : '';
  const filiacaoHref = `${langPrefix}/admin/filiacao`;
  const cycleHref = (code: string | null | undefined) =>
    code && code !== 'no_cycle' ? `${langPrefix}/admin/selection?cycle=${encodeURIComponent(code)}` : null;
  const roleLabel = (r: string) => (r === 'leader' ? t('comp.vepReconciliation.mLeader') : r === 'researcher' ? t('comp.vepReconciliation.mResearcher') : t('comp.vepReconciliation.mOther'));

  const renderBadge = (status: string | null | undefined, palette: Record<string, string>) => {
    if (!status) return <span className="text-[var(--text-muted)]">—</span>;
    const cls = palette[status] || 'bg-gray-100 text-gray-700';
    return <span className={`inline-block text-[10px] font-semibold px-2 py-0.5 rounded-full ${cls}`}>{status}</span>;
  };

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex flex-wrap items-end justify-between gap-3 mb-2">
        <div>
          <h2 className="text-xl font-extrabold text-navy">{t('comp.vepReconciliation.title')}</h2>
          <p className="text-xs text-[var(--text-secondary)] mt-1 max-w-2xl">{t('comp.vepReconciliation.subtitle')}</p>
        </div>
        <div className="flex items-center gap-3">
          {/* #1130 F4 — cross-nav to affiliation queue */}
          <a
            href={filiacaoHref}
            className="text-[11px] font-semibold text-navy hover:underline"
          >
            {t('comp.vepReconciliation.linkFiliacao')}
          </a>
          <div className="text-[11px] text-[var(--text-muted)]">
            {t('comp.vepReconciliation.summary')}: <strong className="text-navy text-base ml-1">{summary.total_divergent ?? 0}</strong>
          </div>
          <button
            onClick={load}
            disabled={loading}
            className="px-3 py-1.5 rounded-lg text-[11px] font-semibold bg-navy text-white hover:opacity-90 cursor-pointer border-0 disabled:opacity-50"
          >
            {loading ? t('comp.vepReconciliation.refreshing') : `↻ ${t('comp.vepReconciliation.refresh')}`}
          </button>
        </div>
      </div>

      {/* Toast */}
      {toast && (
        <div
          role="status"
          className={`text-xs px-3 py-2 rounded-lg ${toast.type === 'ok' ? 'bg-emerald-50 text-emerald-700' : 'bg-red-50 text-red-700'}`}
        >
          {toast.msg}
        </div>
      )}

      {/* p153 OPP-152.5 — Baseline / drift panel (collapsible) */}
      <details className="rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)] overflow-hidden" open={(baselineData?.baselines?.length ?? 0) > 0}>
        <summary className="cursor-pointer px-4 py-3 text-[13px] font-bold text-navy hover:bg-[var(--surface-hover)] flex items-center justify-between">
          <span>{t('comp.vepReconciliation.baselineTitle')}</span>
          <span className="text-[10px] text-[var(--text-muted)] font-normal">
            {baselineData?.baselines?.length ?? 0} {(baselineData?.baselines?.length ?? 0) === 1 ? 'baseline' : 'baselines'}
          </span>
        </summary>
        <div className="px-4 pb-4">
          <p className="text-[11px] text-[var(--text-secondary)] mb-3">{t('comp.vepReconciliation.baselineSubtitle')}</p>
          <div className="flex justify-end mb-2">
            <button
              onClick={captureBaseline}
              disabled={capturingBaseline}
              className="px-3 py-1.5 rounded-lg text-[11px] font-semibold bg-purple-600 text-white hover:opacity-90 cursor-pointer border-0 disabled:opacity-50"
            >
              {capturingBaseline ? '…' : t('comp.vepReconciliation.captureBaselineBtn')}
            </button>
          </div>
          {(!baselineData?.baselines || baselineData.baselines.length === 0) ? (
            <div className="text-center py-6 text-[11px] text-[var(--text-muted)] italic">{t('comp.vepReconciliation.baselineEmpty')}</div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-[11px]">
                <thead className="text-[var(--text-muted)]">
                  <tr className="border-b border-[var(--border-subtle)]">
                    <th className="px-2 py-1.5 text-left font-semibold">{t('comp.vepReconciliation.colCaptured')}</th>
                    <th className="px-2 py-1.5 text-left font-semibold">{t('comp.vepReconciliation.colLabel')}</th>
                    <th className="px-2 py-1.5 text-right font-semibold">{t('comp.vepReconciliation.colSel')}</th>
                    <th className="px-2 py-1.5 text-right font-semibold">{t('comp.vepReconciliation.colOnb')}</th>
                    <th className="px-2 py-1.5 text-right font-semibold">{t('comp.vepReconciliation.colActMem')}</th>
                    <th className="px-2 py-1.5 text-right font-semibold">{t('comp.vepReconciliation.colMissing')}</th>
                  </tr>
                </thead>
                <tbody>
                  {/* "Current" pinned row at top */}
                  {baselineData?.current && (
                    <tr className="bg-purple-50/40 border-b border-purple-100">
                      <td className="px-2 py-1.5 font-mono text-[10px] text-purple-700">— {t('comp.vepReconciliation.cur')} —</td>
                      <td className="px-2 py-1.5 italic text-purple-700">{t('comp.vepReconciliation.deltaLabel')}</td>
                      <td className="px-2 py-1.5 text-right font-bold text-purple-700">{baselineData.current.selection_divergent ?? 0}</td>
                      <td className="px-2 py-1.5 text-right font-bold text-purple-700">{baselineData.current.onboarding_divergent ?? 0}</td>
                      <td className="px-2 py-1.5 text-right font-bold text-purple-700">{baselineData.current.active_members_divergent ?? 0}</td>
                      <td className="px-2 py-1.5 text-right font-bold text-purple-700">{baselineData.current.missing_from_latest_vep ?? 0}</td>
                    </tr>
                  )}
                  {baselineData.baselines.map((b: any) => {
                    const cur = baselineData.current || {};
                    const renderDelta = (current: number, baseline: number) => {
                      const d = current - baseline;
                      if (d === 0) return <span className="text-[var(--text-muted)]">={baseline}</span>;
                      const sign = d > 0 ? '+' : '';
                      const cls = d > 0 ? 'text-amber-700' : 'text-emerald-700';
                      return <span><span className="text-[var(--text-secondary)]">{baseline}</span> <span className={`font-bold ${cls}`}>({sign}{d})</span></span>;
                    };
                    return (
                      <tr key={b.id} className="border-b border-[var(--border-subtle)] hover:bg-[var(--surface-hover)]" title={b.notes || ''}>
                        <td className="px-2 py-1.5 text-[var(--text-secondary)] whitespace-nowrap">{new Date(b.captured_at).toLocaleString()}</td>
                        <td className="px-2 py-1.5 font-semibold text-[var(--text-primary)]">{b.label}{b.captured_by_name ? <span className="text-[10px] text-[var(--text-muted)] font-normal"> · {b.captured_by_name}</span> : null}</td>
                        <td className="px-2 py-1.5 text-right">{renderDelta(cur.selection_divergent ?? 0, b.selection_divergent ?? 0)}</td>
                        <td className="px-2 py-1.5 text-right">{renderDelta(cur.onboarding_divergent ?? 0, b.onboarding_divergent ?? 0)}</td>
                        <td className="px-2 py-1.5 text-right">{renderDelta(cur.active_members_divergent ?? 0, b.active_members_divergent ?? 0)}</td>
                        <td className="px-2 py-1.5 text-right">{renderDelta(cur.missing_from_latest_vep ?? 0, b.missing_from_latest_vep ?? 0)}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </details>

      {/* Tabs */}
      <div className="flex border-b border-[var(--border-default)]">
        {(['matrix', 'selection', 'onboarding', 'active_members', 'rejection', 'offer_retracted'] as TabKey[]).map((key) => {
          const active = tab === key;
          const count = tabCounts[key];
          return (
            <button
              key={key}
              onClick={() => setTab(key)}
              className={`px-4 py-2 text-[12px] font-semibold cursor-pointer border-0 border-b-2 ${
                active ? 'border-navy text-navy bg-transparent' : 'border-transparent text-[var(--text-secondary)] bg-transparent hover:text-navy'
              }`}
            >
              {tabLabels[key]}
              <span className={`ml-2 inline-block text-[10px] font-bold px-1.5 py-0.5 rounded-full ${count > 0 ? 'bg-amber-100 text-amber-700' : 'bg-gray-100 text-gray-500'}`}>
                {count}
              </span>
            </button>
          );
        })}
      </div>

      {/* Hint */}
      <div className="text-[11px] text-[var(--text-muted)] italic">{tabHints[tab]}</div>

      {/* #1130 — Matrix tab */}
      {tab === 'matrix' && (
        <MatrixPanel
          t={t}
          data={matrixData}
          loading={matrixLoading}
          error={matrixError}
          onRetry={loadMatrix}
          roleLabel={roleLabel}
          cycleHref={cycleHref}
          renderBadge={renderBadge}
        />
      )}

      {/* Table (divergence tabs) */}
      {tab !== 'matrix' && (
      <div className="rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)] overflow-hidden">
        {currentList.length === 0 ? (
          <div className="text-center py-10 text-[var(--text-muted)] text-sm">{summary.total_divergent === 0 ? t('comp.vepReconciliation.emptyState') : t('comp.vepReconciliation.noDivergence')}</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-[12px]">
              <thead className="bg-[var(--surface-section-cool)] text-[var(--text-muted)]">
                <tr>
                  <th className="px-3 py-2 text-left font-semibold">{t('comp.vepReconciliation.colName')}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t('comp.vepReconciliation.colEmail')}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t('comp.vepReconciliation.colCycle')}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t('comp.vepReconciliation.colNucleo')}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t('comp.vepReconciliation.colVep')}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t('comp.vepReconciliation.colLastSeen')}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t('comp.vepReconciliation.colAction')}</th>
                  <th className="px-3 py-2 text-right font-semibold">{t('comp.vepReconciliation.colReconciled')}</th>
                </tr>
              </thead>
              <tbody>
                {currentList.map((row: any) => {
                  const appId = row.application_id || row.latest_application_id;
                  const name = row.applicant_name || row.member_name || '—';
                  const isReconciled = row.vep_reconciled_at && row.vep_last_seen_at && new Date(row.vep_reconciled_at).getTime() >= new Date(row.vep_last_seen_at).getTime();
                  return (
                    <tr key={appId || `${row.email}-${row.cycle_code}`} className="border-t border-[var(--border-subtle)] hover:bg-[var(--surface-hover)]">
                      <td className="px-3 py-2 font-semibold text-[var(--text-primary)]">{name}</td>
                      <td className="px-3 py-2 text-[var(--text-secondary)] font-mono text-[11px]">{row.email}</td>
                      <td className="px-3 py-2 text-[var(--text-secondary)]">
                        {/* #1130 F4 — deep-link to the selection screen filtered by cycle */}
                        {cycleHref(row.cycle_code) ? (
                          <a href={cycleHref(row.cycle_code)!} className="text-navy hover:underline font-medium" title={t('comp.vepReconciliation.linkSelectionCycle')}>{row.cycle_code}</a>
                        ) : (row.cycle_code || '—')}
                      </td>
                      <td className="px-3 py-2">{renderBadge(row.nucleo_status || (row.is_active === false ? 'inactive' : null), NUCLEO_STATUS_COLOR)}</td>
                      <td className="px-3 py-2">{renderBadge(row.vep_status_raw, VEP_STATUS_COLOR)}</td>
                      <td className="px-3 py-2 text-[var(--text-secondary)] text-[11px]">{timeAgo(row.vep_last_seen_at, 'ago')}</td>
                      <td className="px-3 py-2 text-[var(--text-secondary)] text-[11px]">{row.suggested_action}</td>
                      <td className="px-3 py-2 text-right">
                        <div className="flex items-center justify-end gap-1.5">
                          {/* #1445 — offboard action for the offer-retracted bucket (member still active) */}
                          {tab === 'offer_retracted' && row.member_id && (
                            <button
                              onClick={() => offboardMember(row.member_id, name !== '—' ? `Oferta VEP retirada — ${name}` : '')}
                              disabled={pendingId === row.member_id}
                              title={t('comp.vepReconciliation.offboardHint')}
                              className="px-2 py-1 rounded-lg text-[10px] font-semibold bg-red-50 text-red-700 hover:bg-red-100 cursor-pointer border-0 disabled:opacity-50"
                            >
                              {pendingId === row.member_id ? '…' : `⏻ ${t('comp.vepReconciliation.offboardMember')}`}
                            </button>
                          )}
                          {appId ? (
                            <button
                              onClick={() => markReconciled(appId)}
                              disabled={pendingId === appId}
                              title={t('comp.vepReconciliation.markReconciledHint')}
                              className="px-2 py-1 rounded-lg text-[10px] font-semibold bg-emerald-50 text-emerald-700 hover:bg-emerald-100 cursor-pointer border-0 disabled:opacity-50"
                            >
                              {pendingId === appId ? '…' : `✓ ${t('comp.vepReconciliation.markReconciled')}`}
                            </button>
                          ) : (!(tab === 'offer_retracted' && row.member_id) && (
                            <span className="text-[var(--text-muted)] text-[10px]">—</span>
                          ))}
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
      )}

      {/* Footer */}
      <div className="text-[10px] text-[var(--text-muted)] text-right">
        {summary.generated_at && `${t('comp.vepReconciliation.generatedAt')}: ${new Date(summary.generated_at).toLocaleString()}`}
      </div>
    </div>
  );
}
