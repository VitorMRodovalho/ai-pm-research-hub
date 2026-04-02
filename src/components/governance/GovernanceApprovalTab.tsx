import { useState, useEffect, useCallback } from 'react';

interface Props {
  t: (key: string, fallback?: string) => string;
  getSb: () => any;
  member: any;
}

const CAT_COLORS: Record<string, string> = {
  manual_update: 'bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-300',
  role_structure: 'bg-purple-100 text-purple-800 dark:bg-purple-900/30 dark:text-purple-300',
  operational_procedure: 'bg-emerald-100 text-emerald-800 dark:bg-emerald-900/30 dark:text-emerald-300',
  technical_architecture: 'bg-gray-100 text-gray-700 dark:bg-gray-800/50 dark:text-gray-300',
};

const CAT_LABELS: Record<string, string> = {
  manual_update: 'Manual', role_structure: 'Papéis',
  operational_procedure: 'Procedimentos', technical_architecture: 'Técnica',
};

const PRIO_COLORS: Record<string, string> = {
  high: 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400',
  medium: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400',
  low: 'bg-gray-100 text-gray-600 dark:bg-gray-800/50 dark:text-gray-400',
};

export default function GovernanceApprovalTab({ t, getSb, member }: Props) {
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('all');
  const [expandedCr, setExpandedCr] = useState<string | null>(null);
  const [confirmAction, setConfirmAction] = useState<{ crId: string; action: string } | null>(null);
  const [comment, setComment] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const loadData = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    try {
      const { data: d, error } = await sb.rpc('get_governance_dashboard');
      if (error) throw error;
      setData(d);
    } catch (e) { console.warn('Dashboard load failed:', e); }
    finally { setLoading(false); }
  }, [getSb]);

  useEffect(() => { loadData(); }, [loadData]);

  const handleApprove = async (crId: string, action: string) => {
    const sb = getSb();
    if (!sb || submitting) return;
    setSubmitting(true);
    try {
      const { data: result, error } = await sb.rpc('approve_change_request', {
        p_cr_id: crId, p_action: action,
        p_comment: comment || null, p_ip: null, p_user_agent: navigator.userAgent,
      });
      if (error) throw error;
      if (result?.error) { alert(result.error); return; }
      setConfirmAction(null);
      setComment('');
      if (result?.quorum_met) {
        (window as any).toast?.(t('governance.cr.quorumMet', 'Quórum atingido! CR aprovado.'), 'success');
      } else {
        (window as any).toast?.(
          t('governance.cr.signature', 'Assinatura: {hash}').replace('{hash}', (result?.signature_hash || '').slice(0, 12) + '...'),
          'success'
        );
      }
      await loadData();
    } catch (e) {
      console.error('Approve failed:', e);
      (window as any).toast?.('Erro ao processar voto', 'error');
    } finally { setSubmitting(false); }
  };

  if (loading) {
    return <div className="flex items-center justify-center py-12">
      <div className="animate-spin h-5 w-5 border-2 border-[var(--accent)] border-t-transparent rounded-full" />
    </div>;
  }

  if (!data) {
    return <p className="text-[var(--text-muted)] text-sm py-8 text-center">{t('governance.cr.noData')}</p>;
  }

  const canApprove = data.can_approve;
  const stats = data.stats || {};
  const pendingCrs: any[] = data.pending_crs || [];
  const recentApproved: any[] = data.recent_approved || [];
  const filtered = filter === 'all' ? pendingCrs : pendingCrs.filter((cr: any) => cr.category === filter);

  const categories = [...new Set(pendingCrs.map((cr: any) => cr.category))];

  return (
    <div className="space-y-4">
      {/* Greeting + Stats */}
      <div className="bg-[var(--surface-card)] rounded-xl border border-[var(--border-default)] p-4 sm:p-5">
        {data.member_name && (
          <p className="text-sm text-[var(--text-primary)] font-medium mb-3">
            {t('governance.dashboard.greeting', 'Olá, {name}.').replace('{name}', data.member_name.split(' ')[0])}{' '}
            <span className="text-[var(--text-secondary)]">
              {t('governance.dashboard.pendingCount', '{count} propostas aguardando.').replace('{count}', String(stats.pending || 0))}
            </span>
          </p>
        )}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
          {[
            { key: 'pending', value: stats.pending, color: 'text-amber-600 dark:text-amber-400' },
            { key: 'approved', value: stats.approved, color: 'text-emerald-600 dark:text-emerald-400' },
            { key: 'implemented', value: stats.implemented, color: 'text-blue-600 dark:text-blue-400' },
            { key: 'rejected', value: stats.rejected, color: 'text-red-600 dark:text-red-400' },
          ].map(s => (
            <div key={s.key} className="text-center py-2 rounded-lg bg-[var(--surface-hover)]">
              <div className={`text-lg font-bold ${s.color}`}>{s.value || 0}</div>
              <div className="text-[10px] font-semibold text-[var(--text-muted)] uppercase tracking-wide">
                {t(`governance.dashboard.stats.${s.key}`, s.key)}
              </div>
            </div>
          ))}
        </div>
        <p className="text-xs text-[var(--text-muted)] mt-3">
          {t('governance.dashboard.quorum', 'Quórum: {needed} de {total} presidentes')
            .replace('{needed}', String(data.quorum_needed || 3))
            .replace('{total}', String(data.total_sponsors || 5))}
        </p>
      </div>

      {/* Filters */}
      {categories.length > 1 && (
        <div className="flex gap-1.5 flex-wrap">
          <button onClick={() => setFilter('all')}
            className={`px-3 py-1.5 rounded-full text-[12px] font-semibold cursor-pointer border transition-all ${
              filter === 'all' ? 'border-navy bg-navy text-white' : 'border-[var(--border-default)] bg-[var(--surface-card)] text-[var(--text-secondary)]'
            }`}>{t('governance.dashboard.filter.all', 'Todos')} ({pendingCrs.length})</button>
          {categories.map(cat => (
            <button key={cat} onClick={() => setFilter(cat)}
              className={`px-3 py-1.5 rounded-full text-[12px] font-semibold cursor-pointer border transition-all ${
                filter === cat ? 'border-navy bg-navy text-white' : 'border-[var(--border-default)] bg-[var(--surface-card)] text-[var(--text-secondary)]'
              }`}>{CAT_LABELS[cat] || cat} ({pendingCrs.filter((c: any) => c.category === cat).length})</button>
          ))}
        </div>
      )}

      {/* CR Cards */}
      <div className="space-y-3">
        {filtered.map((cr: any) => {
          const isExpanded = expandedCr === cr.id;
          const catColor = CAT_COLORS[cr.category] || CAT_COLORS.technical_architecture;
          const prioColor = PRIO_COLORS[cr.priority] || '';
          const myVote = cr.my_vote;

          return (
            <div key={cr.id} className="bg-[var(--surface-card)] rounded-xl border border-[var(--border-default)] overflow-hidden">
              {/* Header — always visible */}
              <button onClick={() => setExpandedCr(isExpanded ? null : cr.id)}
                className="w-full text-left px-4 py-3 flex items-start gap-2 cursor-pointer border-0 bg-transparent">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-1.5 flex-wrap mb-1">
                    <span className="text-[11px] font-bold text-[var(--text-muted)]">{cr.cr_number}</span>
                    {cr.priority && <span className={`text-[10px] font-bold px-1.5 py-0.5 rounded ${prioColor}`}>
                      {t(`governance.cr.priority.${cr.priority}`, cr.priority)}
                    </span>}
                    <span className={`text-[10px] font-semibold px-1.5 py-0.5 rounded ${catColor}`}>
                      {CAT_LABELS[cr.category] || cr.category}
                    </span>
                    {myVote && (
                      <span className={`text-[10px] font-bold px-1.5 py-0.5 rounded ${
                        myVote === 'approved' ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400'
                        : myVote === 'rejected' ? 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400'
                        : 'bg-gray-100 text-gray-600 dark:bg-gray-800/50 dark:text-gray-400'
                      }`}>
                        {t('governance.cr.yourVote', 'Seu voto')}: {myVote}
                      </span>
                    )}
                  </div>
                  <p className="text-sm font-medium text-[var(--text-primary)] leading-snug">{cr.title}</p>
                  <p className="text-[11px] text-[var(--text-muted)] mt-1">
                    {t('governance.cr.approvalCount', '{count}/{needed}')
                      .replace('{count}', String(cr.approval_count || 0))
                      .replace('{needed}', String(data.quorum_needed || 3))}
                  </p>
                </div>
                <span className="text-[var(--text-muted)] text-sm shrink-0 mt-1">{isExpanded ? '▾' : '▸'}</span>
              </button>

              {/* Expanded detail */}
              {isExpanded && (
                <div className="px-4 pb-4 border-t border-[var(--border-subtle)]">
                  {cr.description && (
                    <details className="mt-3" open>
                      <summary className="text-[11px] font-semibold text-[var(--text-muted)] cursor-pointer">{t('governance.cr.description')}</summary>
                      <p className="mt-1 text-xs text-[var(--text-secondary)] leading-relaxed">{cr.description}</p>
                    </details>
                  )}
                  {cr.proposed_changes && (
                    <details className="mt-2">
                      <summary className="text-[11px] font-semibold text-[var(--text-muted)] cursor-pointer">{t('governance.cr.proposedChanges')}</summary>
                      <pre className="mt-1 text-xs text-[var(--text-secondary)] leading-relaxed whitespace-pre-line bg-[var(--surface-hover)] rounded-lg p-3">{cr.proposed_changes}</pre>
                    </details>
                  )}
                  {cr.justification && (
                    <details className="mt-2">
                      <summary className="text-[11px] font-semibold text-[var(--text-muted)] cursor-pointer">{t('governance.cr.justification')}</summary>
                      <p className="mt-1 text-xs text-[var(--text-secondary)] leading-relaxed bg-[var(--surface-hover)] rounded-lg p-3">{cr.justification}</p>
                    </details>
                  )}

                  {/* Sponsor status */}
                  <SponsorPanel crId={cr.id} getSb={getSb} t={t} quorumNeeded={data.quorum_needed} />

                  {/* Approve/Reject buttons (sponsors only) */}
                  {canApprove && !myVote && (
                    <div className="mt-4 flex gap-2 flex-wrap">
                      <button onClick={() => setConfirmAction({ crId: cr.id, action: 'approved' })}
                        className="flex-1 sm:flex-none px-4 py-2.5 rounded-lg bg-emerald-600 text-white text-sm font-semibold border-0 cursor-pointer hover:bg-emerald-700 transition-colors">
                        ✅ {t('governance.cr.approve')}
                      </button>
                      <button onClick={() => setConfirmAction({ crId: cr.id, action: 'rejected' })}
                        className="flex-1 sm:flex-none px-4 py-2.5 rounded-lg bg-red-600 text-white text-sm font-semibold border-0 cursor-pointer hover:bg-red-700 transition-colors">
                        ❌ {t('governance.cr.reject')}
                      </button>
                    </div>
                  )}
                  {canApprove && myVote && (
                    <p className="mt-3 text-xs text-[var(--text-muted)]">
                      {t('governance.cr.voted', 'Votou')}: <strong>{myVote}</strong>
                    </p>
                  )}
                </div>
              )}
            </div>
          );
        })}
      </div>

      {/* Preview link */}
      <div className="text-center pt-2">
        <a href="/governance/preview" className="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-[var(--surface-card)] border border-[var(--border-default)] text-sm font-semibold text-[var(--text-primary)] no-underline hover:bg-[var(--surface-hover)] transition-colors">
          📋 {t('governance.previewLink', 'Preview Manual R3')}
        </a>
      </div>

      {/* Recently Approved */}
      {recentApproved.length > 0 && (
        <div className="bg-[var(--surface-card)] rounded-xl border border-[var(--border-default)] p-4">
          <h3 className="text-xs font-bold uppercase tracking-wide text-[var(--text-muted)] mb-2">
            {t('governance.cr.recentApproved', 'Aprovados Recentemente')}
          </h3>
          {recentApproved.map((cr: any) => (
            <div key={cr.id} className="flex items-center justify-between py-1.5 border-b border-[var(--border-subtle)] last:border-b-0">
              <span className="text-xs text-[var(--text-primary)]"><strong>{cr.cr_number}</strong> {cr.title}</span>
              <span className="text-[10px] text-emerald-600 dark:text-emerald-400 font-semibold">✅</span>
            </div>
          ))}
        </div>
      )}

      {/* Confirmation Modal */}
      {confirmAction && (
        <div className="fixed inset-0 z-[500] flex items-center justify-center bg-black/50 p-4"
          onClick={(e) => { if (e.target === e.currentTarget) setConfirmAction(null); }}>
          <div className="bg-[var(--surface-card)] rounded-xl border border-[var(--border-default)] p-6 max-w-md w-full shadow-xl">
            <p className="text-sm font-semibold text-[var(--text-primary)] mb-3">
              {confirmAction.action === 'approved'
                ? t('governance.cr.confirmApprove', 'Confirmar aprovação?')
                : t('governance.cr.confirmReject', 'Confirmar rejeição?')}
            </p>
            <textarea value={comment} onChange={e => setComment(e.target.value)}
              placeholder={t('governance.cr.commentPlaceholder', 'Comment (optional)')}
              className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-input)] text-sm text-[var(--text-primary)] resize-none h-20 focus:outline-none focus:border-navy mb-3" />
            <div className="flex gap-2 justify-end">
              <button onClick={() => { setConfirmAction(null); setComment(''); }}
                className="px-4 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-sm font-semibold text-[var(--text-secondary)] cursor-pointer">
                {t('governance.cr.cancelBtn', 'Cancel')}
              </button>
              <button onClick={() => handleApprove(confirmAction.crId, confirmAction.action)}
                disabled={submitting}
                className={`px-4 py-2 rounded-lg text-white text-sm font-semibold border-0 cursor-pointer ${
                  confirmAction.action === 'approved' ? 'bg-emerald-600 hover:bg-emerald-700' : 'bg-red-600 hover:bg-red-700'
                } ${submitting ? 'opacity-50' : ''}`}>
                {submitting ? '...' : t('governance.cr.confirmBtn', 'Confirm')}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function SponsorPanel({ crId, getSb, t, quorumNeeded }: { crId: string; getSb: () => any; t: (k: string, f?: string) => string; quorumNeeded: number }) {
  const [sponsors, setSponsors] = useState<any[]>([]);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const sb = getSb();
      if (!sb) return;
      try {
        const { data } = await sb.rpc('get_cr_approval_status', { p_cr_id: crId });
        if (!cancelled && data?.sponsors) setSponsors(data.sponsors);
      } catch { /* noop */ }
    })();
    return () => { cancelled = true; };
  }, [crId, getSb]);

  if (!sponsors.length) return null;

  return (
    <div className="mt-3 flex gap-1.5 flex-wrap">
      {sponsors.map((s: any) => {
        const firstName = (s.name || '').split(' ')[0];
        const icon = s.has_voted
          ? s.vote === 'approved' ? '✅' : s.vote === 'rejected' ? '❌' : '⏸️'
          : '⏳';
        return (
          <div key={s.member_id} className={`flex items-center gap-1 px-2 py-1 rounded-lg text-[11px] font-medium border ${
            s.has_voted
              ? 'border-emerald-200 bg-emerald-50 text-emerald-700 dark:border-emerald-800 dark:bg-emerald-900/20 dark:text-emerald-400'
              : 'border-[var(--border-subtle)] bg-[var(--surface-hover)] text-[var(--text-muted)]'
          }`}>
            <span>{icon}</span>
            <span>{firstName}</span>
          </div>
        );
      })}
    </div>
  );
}
